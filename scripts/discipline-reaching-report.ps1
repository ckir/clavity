<#
.SYNOPSIS
    Read .clavity/discipline-reaching.jsonl and report whether the AGY-ANOMALIES dispatch relay is
    reaching a driver. ROADMAP section 0, step 1a - the named consumer for that record.

.DESCRIPTION
    Read-only. No -WhatIf: it changes nothing (read-only checkers are exempt from the ShouldProcess rule).

    THREE THINGS THIS REPORT DELIBERATELY REFUSES TO DO, each of which would reintroduce a measured failure:

    1. IT NEVER FOLDS A NULL INTO A ZERO. A null count means the scan could not run; a zero means it ran
       and found nothing. Averaging them manufactures exactly the confident-wrong conclusion this item
       exists to remove, so degraded rows are excluded from the totals and listed separately by
       scan_status.

    2. IT NEVER PRINTS A RATIO. The schema has no capture numerator at all - that field was removed
       precisely so a conversion figure would be UNCONSTRUCTIBLE rather than merely discouraged. And
       `compactions` is an OPPORTUNITY count with no matching delivery number (PreCompact firings produce
       zero transcript records, measured across 112 transcripts), so dividing by it fabricates a rate. It
       is printed in its own section for that reason, not for tidiness.

    3. IT NEVER SAYS "SESSIONS RUN". SessionEnd is not proven to fire on every exit path, and a machine
       without jq records nothing, so the denominator is unknowable. Sessions RECORDED is the honest count.

.PARAMETER Last
    Report over the last N recorded sessions. Default: all of them.

.PARAMETER Path
    The record file. Defaults to .clavity/discipline-reaching.jsonl under the current repo.
#>
[CmdletBinding()]
param(
    [int]$Last = 0,
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SCHEMA_ANALYSED  = 1   # v1: counts were computed at SessionEnd (SHIPPED in v17 - real machines hold these)
$SCHEMA_CAPTURE   = 2   # v2: SessionEnd capture; never shipped, dev machines only
$SCHEMA_CAPTURE_3 = 3   # v3: SessionStart capture. `source` replaces `reason`; adds `model`

if (-not $Path) {
    $root = (& git rev-parse --show-toplevel 2>$null)
    if (-not $root) { $root = (Get-Location).Path }
    $Path = Join-Path $root '.clavity/discipline-reaching.jsonl'
}

function Expand-CaptureRow {
    # Turn a v2 capture row into the analysed shape by scanning the transcript it names. Same two-stage
    # strategy the hook used to run inline - ONE grep over selective patterns, ONE classifying jq - because
    # the cost model is BYTES FED TO JQ, not lines: prefiltering `fired` on the record type once matched
    # 132 MB of a 176 MB file. The prefilter is only an optimisation; the jq filter is what makes the count
    # correct (a prefilter alone measured 256 where the structural filter measured 1).
    param($Row)
    $add = { param($n,$v) $Row | Add-Member -NotePropertyName $n -NotePropertyValue $v -Force }
    $tx = if ($Row.PSObject.Properties.Name -contains 'transcript_path') { $Row.transcript_path } else { '' }

    if ([string]::IsNullOrWhiteSpace($tx) -or -not (Test-Path -LiteralPath $tx)) {
        & $add 'scan_status' 'transcript_not_found'
        foreach ($f in 'dispatch_nudges','dispatch_nudges_unstamped','dispatch_fired','compactions') { & $add $f $null }
        return $Row
    }

    $jqExe = Get-Command jq -ErrorAction SilentlyContinue
    if (-not $jqExe) {
        # No jq means the counts are UNKNOWN, never zero.
        & $add 'scan_status' 'transcript_unreadable'
        foreach ($f in 'dispatch_nudges','dispatch_nudges_unstamped','dispatch_fired','compactions') { & $add $f $null }
        return $Row
    }

    $stamp = 'AGY-ANOMALIES/1'
    $filter = @'
if (.type=="attachment" and .attachment.type=="hook_additional_context"
    and (.attachment.hookEvent // "")=="PreToolUse"
    and (((.attachment.content // "") | tostring) | contains($s)))       then "N " + (.uuid // "")
elif (.type=="attachment" and .attachment.type=="hook_success"
    and (((.attachment.command // "") | tostring) | contains("agy-anomaly-dispatch-reminder"))) then "F " + (.uuid // "")
elif (.type=="attachment" and .attachment.type=="hook_additional_context"
    and (.attachment.hookEvent // "")=="PreToolUse"
    and (((.attachment.content // "") | tostring) | contains("AGY-ANOMALIES"))) then "L " + (.uuid // "")
elif (.isCompactSummary==true)                                          then "C " + (.uuid // "")
else empty end
'@
    try {
        $pat = '"type":"hook_additional_context"|"isCompactSummary":true|"command":"bash .{0,120}agy-anomaly-dispatch-reminder'
        $classified = @(
            Select-String -LiteralPath $tx -Pattern $pat -Raw -AllMatches -ErrorAction Stop |
                & $jqExe.Source -r --arg s $stamp $filter 2>$null
        ) | Sort-Object -Unique
    } catch {
        & $add 'scan_status' 'transcript_unreadable'
        foreach ($f in 'dispatch_nudges','dispatch_nudges_unstamped','dispatch_fired','compactions') { & $add $f $null }
        return $Row
    }
    & $add 'dispatch_nudges'           (@($classified | Where-Object { $_ -like 'N *' }).Count)
    & $add 'dispatch_fired'            (@($classified | Where-Object { $_ -like 'F *' }).Count)
    & $add 'dispatch_nudges_unstamped' (@($classified | Where-Object { $_ -like 'L *' }).Count)
    & $add 'compactions'               (@($classified | Where-Object { $_ -like 'C *' }).Count)
    & $add 'scan_status' 'ok'
    return $Row
}

Write-Output 'AGY-ANOMALIES discipline reaching'
Write-Output '================================='

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Output "No records yet (0 sessions recorded). Looked in: $Path"
    Write-Output 'The recorder writes one row per session at SessionEnd, from the INSTALLED plugin.'
    return
}

$raw = @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -ne '' })
if ($raw.Count -eq 0) {
    Write-Output "No records yet (0 sessions recorded). File is empty: $Path"
    return
}

if ($Last -gt 0 -and $raw.Count -gt $Last) { $raw = $raw[-$Last..-1] }

$rows = @(); $malformed = 0; $unsupported = 0
foreach ($line in $raw) {
    try { $o = $line | ConvertFrom-Json } catch { $malformed++; continue }
    $v = if ($o.PSObject.Properties.Name -contains 'v') { $o.v } else { $null }
    # An unrecognised version is COUNTED, not parsed - mirroring the null discipline. Guessing at the
    # shape of a future record is how a reader silently mixes incompatible numbers into one total.
    if ($v -eq $SCHEMA_CAPTURE -or $v -eq $SCHEMA_CAPTURE_3) {
        # v2 names a transcript and defers the analysis to HERE, where there is no time limit. Scanning at
        # SessionEnd was CANCELLED on shipped v17 twice, writing nothing, so the work moved to this script.
        $o = Expand-CaptureRow -Row $o
    } elseif ($v -ne $SCHEMA_ANALYSED) { $unsupported++; continue }
    $rows += $o
}

function Get-Num { param($Row, [string]$Name)
    if ($Row.PSObject.Properties.Name -notcontains $Name) { return $null }
    $val = $Row.$Name
    if ($null -eq $val) { return $null }
    return [int]$val
}

$counted = @($rows | Where-Object { $null -ne (Get-Num $_ 'dispatch_nudges') })
$degraded = @($rows | Where-Object { $null -eq (Get-Num $_ 'dispatch_nudges') })

$sumReached   = 0; $sumUnstamped = 0; $sumFired = 0; $sumCompactions = 0
foreach ($r in $counted) {
    $sumReached   += ([int](Get-Num $r 'dispatch_nudges'))
    $u = Get-Num $r 'dispatch_nudges_unstamped'; if ($null -ne $u) { $sumUnstamped += [int]$u }
    $f = Get-Num $r 'dispatch_fired';            if ($null -ne $f) { $sumFired     += [int]$f }
    $c = Get-Num $r 'compactions';               if ($null -ne $c) { $sumCompactions += [int]$c }
}

Write-Output ''
Write-Output ("Sessions recorded : {0}" -f $rows.Count)
Write-Output ("  scanned cleanly : {0}" -f $counted.Count)
Write-Output ("  not scanned     : {0}   (excluded from every total below)" -f $degraded.Count)

Write-Output ''
Write-Output 'DISPATCH RELAY  (PreToolUse: Agent|Task)'
Write-Output ("  reached the model, stamped   : {0}" -f $sumReached)
Write-Output ("  reached the model, unstamped : {0}   (pre-stamp build - delivery worked)" -f $sumUnstamped)
Write-Output ("  hook fired                   : {0}" -f $sumFired)
if ($sumFired -gt 0 -and $sumReached -eq 0 -and $sumUnstamped -eq 0) {
    Write-Output '  ^ FIRED BUT NEVER REACHED - this is the v15 failure signature. Investigate.'
}

Write-Output ''
Write-Output 'SESSION CONTEXT  (opportunity only - NOT a denominator)'
Write-Output ("  compactions : {0}" -f $sumCompactions)
Write-Output '  The PreCompact capture reminder is UNMEASURED here: its firings produce zero transcript'
Write-Output '  records, so its delivery cannot be observed. Never divide a delivery count by this number.'

if ($degraded.Count -gt 0) {
    Write-Output ''
    Write-Output 'NOT SCANNED  (an unknown, never a zero)'
    $degraded | Group-Object -Property scan_status | Sort-Object Name | ForEach-Object {
        Write-Output ("  {0} : {1}" -f $_.Name, $_.Count)
    }
}

if ($malformed -gt 0 -or $unsupported -gt 0) {
    Write-Output ''
    Write-Output 'SKIPPED ROWS'
    if ($malformed -gt 0)   { Write-Output ("  unparseable : {0}" -f $malformed) }
    if ($unsupported -gt 0) { Write-Output ("  unsupported schema version : {0}   (counted, not parsed)" -f $unsupported) }
}
