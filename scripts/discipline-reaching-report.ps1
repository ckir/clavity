<#
.SYNOPSIS
    Read .clavity/discipline-reaching.jsonl and report whether the AGY-ANOMALIES dispatch relay is
    reaching a driver. ROADMAP section 0, step 1a - the named consumer for that record.

.DESCRIPTION
    Read-only. No -WhatIf: it changes nothing (read-only checkers are exempt from the ShouldProcess rule).

    THREE THINGS THIS REPORT DELIBERATELY REFUSES TO DO, each of which would reintroduce a measured
    failure - followed by ONE THING THAT QUIETLY CHANGED MEANING, which is not a refusal and must not be
    filed as one:

    1. IT NEVER FOLDS A NULL INTO A ZERO. A null count means the scan could not run; a zero means it ran
       and found nothing. Averaging them manufactures exactly the confident-wrong conclusion this item
       exists to remove, so degraded rows are excluded from the totals and listed separately by
       scan_status.

    2. IT NEVER PRINTS A RATIO. The schema has no capture numerator at all - that field was removed
       precisely so a conversion figure would be UNCONSTRUCTIBLE rather than merely discouraged. And
       `compactions` is an OPPORTUNITY count with no matching delivery number (PreCompact firings produce
       zero transcript records, measured across 112 transcripts), so dividing by it fabricates a rate. It
       is printed in its own section for that reason, not for tidiness.

    3. IT NEVER SAYS "SESSIONS RUN", AND ITS REASONS ARE NOT THE ONES THIS FILE USED TO GIVE. The old text
       cited SessionEnd not firing reliably and a machine without jq - both dead: the recorder is on
       SessionStart now and the hook uses no subprocesses. The denominator is STILL unknowable, for four
       reasons that replace them: sessions that ran before the plugin was installed; sessions suppressed by
       .no-agy; sessions outside any git repository, which the recorder now deliberately declines to
       record; and sessions where the registration silently failed - the class this whole item exists to
       fight and still cannot detect from the inside. The last two are consequences of the SessionStart
       design, so this refusal is better founded than it was, not weaker.

    AND THE ONE THAT CHANGED MEANING:

    4. "SESSIONS RECORDED" NOW COUNTS DISTINCT SESSIONS, NOT ROWS. It counted rows until dedup existed, and
       the two were equal only because SessionEnd wrote exactly one row per session. The label stays
       honest; the quantity behind it changed, so a v17-era report and a v18 one are not comparable.

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
    # try/catch DOES NOT CATCH A NATIVE BINARY'S NON-ZERO EXIT. That is why $LASTEXITCODE is checked
    # explicitly below rather than trusted to throw. MEASURED: a transcript whose last line is truncated -
    # an ordinary consequence of a session killed mid-write - makes jq exit 5 while STILL emitting the
    # records it parsed before dying. Without this check the partial output flowed straight into the
    # success tail and was stamped `scan_status = ok`: a scan reported as complete on a count that was
    # merely whatever jq managed before it failed. Refusal #1 says a null is never a zero; this is the
    # same rule for a PARTIAL, which is worse, because a plausible number invites more trust than a blank.
    $jqExit = 0
    try {
        $pat = '"type":"hook_additional_context"|"isCompactSummary":true|"command":"bash .{0,120}agy-anomaly-dispatch-reminder'
        $global:LASTEXITCODE = 0
        $classified = @(
            Select-String -LiteralPath $tx -Pattern $pat -Raw -AllMatches -ErrorAction Stop |
                & $jqExe.Source -r --arg s $stamp $filter 2>$null
        ) | Sort-Object -Unique
        $jqExit = $global:LASTEXITCODE
    } catch {
        & $add 'scan_status' 'transcript_unreadable'
        foreach ($f in 'dispatch_nudges','dispatch_nudges_unstamped','dispatch_fired','compactions') { & $add $f $null }
        return $Row
    }
    if ($jqExit -ne 0) {
        & $add 'scan_status' 'transcript_unreadable'
        foreach ($f in 'dispatch_nudges','dispatch_nudges_unstamped','dispatch_fired','compactions') { & $add $f $null }
        return $Row
    }
    & $add 'dispatch_nudges'           (@($classified | Where-Object { $_ -like 'N *' }).Count)
    & $add 'dispatch_fired'            (@($classified | Where-Object { $_ -like 'F *' }).Count)
    & $add 'dispatch_nudges_unstamped' (@($classified | Where-Object { $_ -like 'L *' }).Count)
    & $add 'compactions'               (@($classified | Where-Object { $_ -like 'C *' }).Count)

    # PROVISIONAL: the transcript is still being written, so these counts are INCOMPLETE - not wrong. Every
    # dispatch counted really happened; more may follow. Sample the mtime AFTER the scan, never before: a
    # transcript written to DURING the scan is exactly the in-flight case this bucket exists for, and only
    # an after-reading sample can see it. This also subsumes the session running the report, whose own
    # transcript was appended to moments ago - which matters because a PowerShell script is never handed its
    # caller's session_id and cannot identify itself any other way.
    # mtime is a heuristic and it FAILS SAFE: a backup or antivirus pass that merely touches a file pushes a
    # finished session into provisional for a few minutes, moving a complete session OUT of the clean total.
    # The opposite error - a live session counted as complete - is the one this exists to prevent.
    $fresh = $false
    try { $fresh = ((Get-Item -LiteralPath $tx).LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-15)) } catch { $fresh = $false }
    & $add 'scan_status' $(if ($fresh) { 'provisional' } else { 'ok' })
    return $Row
}

function ConvertTo-SortKey {
    <#
      Return a key that sorts CHRONOLOGICALLY as a string, whatever the host's culture.

      WHY THIS EXISTS - measured, not theorised. `ConvertFrom-Json` does NOT hand back the ISO-8601 STRING
      it read: it parses an ISO-looking value into a [System.DateTime]. A later `[string]` cast then
      formats that with the host's CurrentCulture, so on this machine (el-GR) the timestamp
      "2026-08-05T08:00:00Z" becomes the sort key "08/05/2026 08:00:00". Sorted alphabetically,
      "01/01/2027 ..." lands BEFORE "08/05/2026 ...", so -Last N drops the NEWEST sessions and keeps the
      oldest. Every fixture in the suite used same-day, increasing-hour timestamps, which hid it entirely.

      A value that is not a DateTime is returned unchanged, so it still sorts deterministically. Note what
      that does NOT claim: a raw string does not necessarily interleave correctly with the keys produced
      here. `[string]::CompareOrdinal('2026-08-05T08:00:00.0000000Z','2026-08-05T08:00:00Z')` is -44,
      because '.' (0x2E) sorts below 'Z' (0x5A) - so at the SAME SECOND the two shapes invert.
      That is unreachable from this producer rather than handled: MEASURED, ConvertFrom-Json parses every
      `T...Z` form to DateTime, and the hook only ever writes `%Y-%m-%dT%H:%M:%SZ`, so a surviving raw
      string means a timestamp that is not ISO at all - which cannot collide at a second with anything.
      If a future writer emits a different shape, this is the line to revisit.
    #>
    param($Value)
    if ($null -eq $Value) { return '' }
    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return [string]$Value
}

function Merge-SessionRows {
    <#
      Collapse rows by session_id - FOR THE SessionStart CAPTURE SCHEMA (v:3) ONLY.

      WHY ONLY v:3. Dedup reconstructs ONE session from an EVENT STREAM: v:3 fires on startup, resume,
      clear and compact, so N rows describe one session. v:1 and v:2 were SessionEnd hooks with strictly
      one row per session, and a v:1 row carries its delivery counts INLINE - so collapsing two of them
      would silently DISCARD the second row's counts. Applying event-stream reconstruction to summary
      records is a category error, not a harmless no-op. (Owner ruling 2026-08-05.)

      TWO DIFFERENT QUESTIONS, deliberately answered by two different rows:
        - CONTENT comes from the EARLIEST row - it names how the session ORIGINATED (source=startup rather
          than the compact that followed).
        - RECENCY comes from the LATEST row. -Last N must rank a session by its most recent activity, not
          its birth: otherwise a session started at 08:00 and still alive at 18:00 sorts older than twenty
          short midday ones, and -Last 20 drops the most active session on the machine.

      transcript_path is the ONE EXCEPTION to content-from-earliest. Both observed payloads name
      <session_id>.jsonl, so a stable id implies a stable path - but that is a STRUCTURAL INFERENCE from a
      naming convention seen twice, not a measurement. If the paths ever disagree, prefer the LATEST and
      say so rather than silently naming a stale transcript.

      EVERY row leaves here carrying last_seen and fire_count - collapsed or not. The sort
      that follows reads last_seen off every row, and under Set-StrictMode + $ErrorActionPreference='Stop'
      a single row missing it KILLS THE WHOLE REPORT. A pass-through row is a session of one fire, so
      last_seen = its own timestamp is not a placeholder, it is the truth. MEASURED: the hook
      writes "session_id":"" when the payload carries none, so an uncollapsible row is reachable from the
      real producer, not merely hypothetical.
    #>
    param([object[]]$Rows)
    $ownTs = { param($Row)
        if ($Row.PSObject.Properties.Name -contains 'timestamp') { ConvertTo-SortKey $Row.timestamp } else { '' }
    }
    # No `first_seen`. It was stamped on every row and READ BY NOTHING - not sorted on, not printed, not
    # asserted. A session's origin is already visible as `began <source>`, and the origin TIME is not a
    # question this report answers. A property written for symmetry is a property that rots.
    $stamp = { param($Row, $Last, $Count)
        $Row | Add-Member -NotePropertyName 'last_seen'  -NotePropertyValue ([string]$Last)  -Force
        $Row | Add-Member -NotePropertyName 'fire_count' -NotePropertyValue $Count -Force
    }
    $out = [System.Collections.Generic.List[object]]::new()
    $groups = [ordered]@{}
    foreach ($r in $Rows) {
        $v   = if ($r.PSObject.Properties.Name -contains 'v') { $r.v } else { $null }
        $sid = if ($r.PSObject.Properties.Name -contains 'session_id') { [string]$r.session_id } else { '' }
        if ($v -ne $SCHEMA_CAPTURE_3 -or [string]::IsNullOrWhiteSpace($sid)) {
            $t = & $ownTs $r
            & $stamp $r $t 1
            $out.Add($r); continue
        }
        if (-not $groups.Contains($sid)) { $groups[$sid] = [System.Collections.Generic.List[object]]::new() }
        $groups[$sid].Add($r)
    }
    foreach ($sid in $groups.Keys) {
        $g = @($groups[$sid] | Sort-Object -Property @{ Expression = { ConvertTo-SortKey $_.timestamp } })
        $keep = $g[0]
        & $stamp $keep (& $ownTs $g[-1]) $g.Count
        $paths = @($g | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains 'transcript_path') { [string]$_.transcript_path } else { '' }
        } | Where-Object { $_ -ne '' })
        $keepPath = if ($keep.PSObject.Properties.Name -contains 'transcript_path') { [string]$keep.transcript_path } else { '' }
        if ($paths.Count -gt 0) {
            # The LATEST NON-EMPTY path, NOT $g[-1].transcript_path: the newest row may carry no path at
            # all, and reading an absent property here would kill the report under StrictMode. $paths is
            # already in timestamp order, so its last element is the newest one that named anything.
            #
            # TWO DISTINCT CASES, and only the second is a disagreement:
            #   GAP - the earliest row named NO transcript and a later fire did. There is one distinct path,
            #     so the disagreement test below never fires; without this branch the session would keep the
            #     earliest row's EMPTY path and report `transcript_not_found` for a transcript that is right
            #     there and readable. A startup fire that names nothing, followed by a compact that does, is
            #     ordinary - the earliest row is the LEAST likely of the group to know the path.
            #   DISAGREEMENT - the rows named DIFFERENT transcripts, which would mean the <session_id>.jsonl
            #     convention this design infers from has broken. That one is surfaced to the reader.
            if ([string]::IsNullOrWhiteSpace($keepPath)) {
                $keep | Add-Member -NotePropertyName 'transcript_path' -NotePropertyValue $paths[-1] -Force
            }
            if (@($paths | Sort-Object -Unique).Count -gt 1) {
                $keep | Add-Member -NotePropertyName 'transcript_path'   -NotePropertyValue $paths[-1] -Force
                $keep | Add-Member -NotePropertyName 'path_disagreement' -NotePropertyValue $true      -Force
            }
        }
        $out.Add($keep)
    }
    return $out.ToArray()
}

Write-Output 'AGY-ANOMALIES discipline reaching'
Write-Output '================================='

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Output "No records yet (0 sessions recorded). Looked in: $Path"
    Write-Output 'The recorder writes a row at SessionStart (startup, resume, clear and compact), from the'
    Write-Output 'INSTALLED plugin - not from this repo. No rows means it has not fired since installation.'
    return
}

$raw = @(Get-Content -LiteralPath $Path | Where-Object { $_.Trim() -ne '' })
if ($raw.Count -eq 0) {
    Write-Output "No records yet (0 sessions recorded). File is empty: $Path"
    return
}

$rows = @(); $malformed = 0; $unsupported = 0
$sourceCounts = [ordered]@{}; $legacyRows = 0
foreach ($line in $raw) {
    try { $o = $line | ConvertFrom-Json } catch { $malformed++; continue }
    $v = if ($o.PSObject.Properties.Name -contains 'v') { $o.v } else { $null }
    # Counted per ROW, before dedup - this is a count of hook FIRINGS, not of sessions.
    if ($v -eq $SCHEMA_CAPTURE_3 -and $o.PSObject.Properties.Name -contains 'source') {
        $s = [string]$o.source
        if ([string]::IsNullOrWhiteSpace($s)) { $s = '(unnamed)' }
        if (-not $sourceCounts.Contains($s)) { $sourceCounts[$s] = 0 }
        $sourceCounts[$s]++
    } elseif ($v -eq $SCHEMA_ANALYSED -or $v -eq $SCHEMA_CAPTURE) {
        $legacyRows++
    }
    # An unrecognised version is COUNTED, not parsed - mirroring the null discipline. Guessing at the
    # shape of a future record is how a reader silently mixes incompatible numbers into one total.
    if ($v -eq $SCHEMA_CAPTURE -or $v -eq $SCHEMA_CAPTURE_3) {
        # A capture row names a transcript and defers the scan. The scan does NOT happen here: it happens
        # after dedup and slicing, so a session's fifteen compact rows read their transcript ONCE, not
        # fifteen times. (Scanning at SessionEnd was CANCELLED on shipped v17 twice, writing nothing, which
        # is why the analysis lives in this script at all.)
        $o | Add-Member -NotePropertyName 'needs_scan' -NotePropertyValue $true -Force
    } elseif ($v -ne $SCHEMA_ANALYSED) { $unsupported++; continue }
    $rows += $o
}

# Collapse BEFORE slicing. Slicing first makes -Last 20 return however many distinct sessions happen to
# fall in the last 20 lines - the number stays plausible while its meaning changes, which is the failure
# this report exists to refuse.
$rows = @(Merge-SessionRows -Rows $rows)
$rows = @($rows | Sort-Object -Property @{ Expression = { [string]$_.last_seen } })
if ($Last -gt 0 -and $rows.Count -gt $Last) { $rows = $rows[-$Last..-1] }

# SAY WHAT IS ABOUT TO HAPPEN BEFORE THE SLOW PART, not after. -Last defaults to 0, meaning ALL recorded
# sessions, and each one costs a Select-String plus a jq over a whole transcript. MEASURED on this
# machine: 118 transcripts totalling 1766 MB, the largest 264 MB taking 8,98s for the Select-String pass
# alone. So a full-history run is a minute at a hundred sessions and climbing, with nothing on screen
# until it finishes. The DEFAULT IS DELIBERATELY UNCHANGED - it is a documented contract and a bounded
# default would silently narrow what an existing caller measures. Telling the operator turns a silent
# wait into an informed one, which is this report's own posture applied to itself.
$toScan = @($rows | Where-Object { $_.PSObject.Properties.Name -contains 'needs_scan' -and $_.needs_scan })
if ($toScan.Count -ge 20) {
    Write-Output ("Scanning {0} transcripts (-Last is 0, meaning every recorded session). Pass -Last 20 to bound it." -f $toScan.Count)
}

# Pipeline order: parse -> collapse -> slice -> EXPAND. This bounds transcript reads to N.
$rows = @($rows | ForEach-Object {
    if ($_.PSObject.Properties.Name -contains 'needs_scan' -and $_.needs_scan) { Expand-CaptureRow -Row $_ } else { $_ }
})

function Get-Num { param($Row, [string]$Name)
    if ($Row.PSObject.Properties.Name -notcontains $Name) { return $null }
    $val = $Row.$Name
    if ($null -eq $val) { return $null }
    # A NON-NUMERIC value is an UNKNOWN, not a crash. `[int]"N/A"` throws, and under
    # $ErrorActionPreference='Stop' that terminating error kills the whole report over one bad field in
    # one row - so a single corrupted or hand-edited line would take down the reading of every other
    # session. Returning $null routes the row into the `not scanned` bucket, which already exists to say
    # exactly this: the value is unknowable. Degrade the row, never the report.
    try { return [int]$val } catch { return $null }
}

# THREE disjoint sets keyed on scan_status, NOT on null-ness. Null-ness worked as a discriminator only
# while "has counts" and "is complete" meant the same thing; `provisional` is exactly where they come
# apart - it has non-null counts and is not complete, so a null-based split would blend a partial count
# into the totals.
function Get-Status { param($Row)
    if ($Row.PSObject.Properties.Name -notcontains 'scan_status') { return '' }
    return [string]$Row.scan_status
}
$counted     = @($rows | Where-Object { (Get-Status $_) -eq 'ok' -and $null -ne (Get-Num $_ 'dispatch_nudges') })
$provisional = @($rows | Where-Object { (Get-Status $_) -eq 'provisional' })
$degraded    = @($rows | Where-Object { (Get-Status $_) -ne 'ok' -and (Get-Status $_) -ne 'provisional' })

$sumReached   = 0; $sumUnstamped = 0; $sumFired = 0; $sumCompactions = 0
foreach ($r in $counted) {
    $sumReached   += ([int](Get-Num $r 'dispatch_nudges'))
    $u = Get-Num $r 'dispatch_nudges_unstamped'; if ($null -ne $u) { $sumUnstamped += [int]$u }
    $f = Get-Num $r 'dispatch_fired';            if ($null -ne $f) { $sumFired     += [int]$f }
    $c = Get-Num $r 'compactions';               if ($null -ne $c) { $sumCompactions += [int]$c }
}

# THE PROVISIONAL ROWS ARE SUMMED SEPARATELY, AND THEY NEVER ENTER THE TOTALS ABOVE. They exist for one
# reason: the v15 ALARM below. Keeping a partial count out of a TOTAL is correct - a growing number must
# not be reported as a final one. Keeping it out of the ALARM was a defect, and the worst one in this
# epic: the failure signature this whole report exists to detect belongs to the session you are running
# the report FROM, which is by definition still running, hence provisional. MEASURED before this fix: a
# live session with fired=1 and reached=0 printed `hook fired : 0` and no alarm at all - the report was
# silent during exactly the outage it was invoked to diagnose.
$liveReached = 0; $liveUnstamped = 0; $liveFired = 0
foreach ($r in $provisional) {
    $n = Get-Num $r 'dispatch_nudges';            if ($null -ne $n) { $liveReached   += [int]$n }
    $u = Get-Num $r 'dispatch_nudges_unstamped';  if ($null -ne $u) { $liveUnstamped += [int]$u }
    $f = Get-Num $r 'dispatch_fired';             if ($null -ne $f) { $liveFired     += [int]$f }
}

Write-Output ''
Write-Output ("Sessions recorded : {0}" -f $rows.Count)
Write-Output ("  scanned cleanly : {0}" -f $counted.Count)
# UNCONDITIONAL, exactly like the two lines around it. A partition summary must name every bucket every
# time: a line that vanishes when the count is zero makes "no session was live" indistinguishable from
# "this build does not track live sessions" - which is this report's own first refusal (a null and a zero
# must never look alike) applied to its own output. `provisional : 0` says we looked and found none.
Write-Output ("  provisional     : {0}   (still running - excluded from every total below)" -f $provisional.Count)
Write-Output ("  not scanned     : {0}   (excluded from every total below)" -f $degraded.Count)

Write-Output ''
Write-Output 'DISPATCH RELAY  (PreToolUse: Agent|Task)'
Write-Output ("  reached the model, stamped   : {0}" -f $sumReached)
Write-Output ("  reached the model, unstamped : {0}   (pre-stamp build - delivery worked)" -f $sumUnstamped)
Write-Output ("  hook fired                   : {0}" -f $sumFired)
if ($sumFired -gt 0 -and $sumReached -eq 0 -and $sumUnstamped -eq 0) {
    Write-Output '  ^ FIRED BUT NEVER REACHED - this is the v15 failure signature. Investigate.'
}
if ($liveFired -gt 0 -and $liveReached -eq 0 -and $liveUnstamped -eq 0) {
    Write-Output ("  ^ FIRED BUT NEVER REACHED in a session that is STILL RUNNING ({0} fired, 0 reached)." -f $liveFired)
    Write-Output '    This reading is INCOMPLETE and is not in the totals above - more may yet reach. But it is'
    Write-Output '    the v15 signature happening NOW, which is the case those totals can never show you.'
}

Write-Output ''
Write-Output 'SESSION CONTEXT  (opportunity only - NOT a denominator)'
Write-Output ("  compactions : {0}" -f $sumCompactions)
Write-Output '  The PreCompact capture reminder is UNMEASURED here: its firings produce zero transcript'
Write-Output '  records, so its delivery cannot be observed. Never divide a delivery count by this number.'

Write-Output ''
Write-Output 'HOOK INVOCATIONS  (firings, NOT sessions - one session fires once per start, clear and compact)'
foreach ($k in $sourceCounts.Keys) { Write-Output ("  {0} : {1}" -f $k, $sourceCounts[$k]) }
if ($legacyRows -gt 0) { Write-Output ("  legacy (v1/v2) : {0}   (they carry an EXIT reason, not a boot source)" -f $legacyRows) }
Write-Output '  These are NOT the `compactions` figure above: that one is derived from the transcript and'
Write-Output '  counts different things. They WILL diverge - a compaction before the plugin was installed'
Write-Output '  appears in one and not the other. A reader who expects them to agree will misread a correct report.'

if ($degraded.Count -gt 0) {
    Write-Output ''
    Write-Output 'NOT SCANNED  (an unknown, never a zero)'
    $degraded | Group-Object -Property scan_status | Sort-Object Name | ForEach-Object {
        Write-Output ("  {0} : {1}" -f $_.Name, $_.Count)
    }
}

if ($provisional.Count -gt 0) {
    Write-Output ''
    Write-Output 'PROVISIONAL  (still running - counts may grow, and are NOT in the totals above)'
    foreach ($p in $provisional) {
        # `began` is the ORIGIN source - the earliest row of the collapsed session, not the latest. It is
        # printed for two reasons. It is genuinely useful: a live session that began as `compact` has a
        # history behind it that a `startup` one does not. And it is the ONLY place the content-from-
        # earliest rule in Merge-SessionRows becomes OBSERVABLE - every other field is identical across a
        # session's rows. MEASURED 2026-08-05: before this line existed, changing that merge to keep the
        # LATEST row broke NOTHING - all 25 tests stayed green. A design rule no output can distinguish is
        # a rule no test can pin.
        # `-contains 'source'` is TRUE for `"source":""` - the hook always emits the key, possibly empty -
        # so a presence check alone printed `began , 2 fires` with a stray comma. Normalised the same way
        # the invocation distribution normalises it, so the two sections agree on what an unnamed source
        # looks like.
        $began = if ($p.PSObject.Properties.Name -contains 'source') { [string]$p.source } else { '' }
        if ([string]::IsNullOrWhiteSpace($began)) { $began = '(unnamed)' }
        $fires = if ($p.PSObject.Properties.Name -contains 'fire_count') { [string]$p.fire_count } else { '?' }
        Write-Output ("  {0}  began {1}, {2} fires, reached {3}, fired {4}" -f `
            ([string]$p.session_id), $began, $fires, (Get-Num $p 'dispatch_nudges'), (Get-Num $p 'dispatch_fired'))
    }
}

# The disagreement guard from Merge-SessionRows is USELESS if nobody is told. A session whose collapsed
# rows named different transcripts had the LATEST path used; that is a silent choice unless surfaced, and
# it would mean the <session_id>.jsonl naming convention this design infers from has changed.
$disagreed = @($rows | Where-Object { $_.PSObject.Properties.Name -contains 'path_disagreement' })
if ($disagreed.Count -gt 0) {
    Write-Output ''
    Write-Output 'TRANSCRIPT PATH DISAGREEMENT  (the latest path was used)'
    foreach ($x in $disagreed) { Write-Output ("  {0} : {1}" -f ([string]$x.session_id), ([string]$x.transcript_path)) }
    Write-Output '  Rows of one session named DIFFERENT transcripts. This design assumes <session_id>.jsonl;'
    Write-Output '  if this line ever appears, that assumption has broken and the dedup key needs revisiting.'
}

if ($malformed -gt 0 -or $unsupported -gt 0) {
    Write-Output ''
    Write-Output 'SKIPPED ROWS'
    if ($malformed -gt 0)   { Write-Output ("  unparseable : {0}" -f $malformed) }
    if ($unsupported -gt 0) { Write-Output ("  unsupported schema version : {0}   (counted, not parsed)" -f $unsupported) }
}
