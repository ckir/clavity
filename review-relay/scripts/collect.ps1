#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Collect a review-relay round: find the AiSave captures saved for it and summarise them side by side.
.DESCRIPTION
  Spec: docs/superpowers/specs/2026-09-28-review-relay-design.md, sections 5.2 and 6.
  Exit codes: 0 success, 1 usage or state error, 2 no capture found.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9][a-z0-9-]*$')][string]$Review,
    [ValidateRange(1, [int]::MaxValue)][int]$Round,
    [string]$Inbox,
    [string]$ProjectRoot = (Get-Location).Path
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'relay-lib.ps1')

function Stop-Collect([string]$Message) { Write-Host "collect: $Message" -ForegroundColor Red; exit 1 }
function ConvertTo-RoundStartedAtUtc($Value) {
    if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
    [DateTime]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).ProviderPath
$ws = Join-Path $root '.review-relay' $Review
if (-not (Test-Path -LiteralPath (Join-Path $ws 'review.json'))) { Stop-Collect "no review named '$Review' in $root" }
$rounds = @(Get-ChildItem -LiteralPath $ws -Directory -Filter 'round-*' |
    Where-Object { $_.Name -match '^round-\d+$' } | Sort-Object { [int]($_.Name.Substring(6)) })
if ($rounds.Count -eq 0) { Stop-Collect 'no rounds yet: run new-round.ps1 first' }
$roundDir = if ($PSBoundParameters.ContainsKey('Round')) { Join-Path $ws ('round-{0:D2}' -f $Round) } else { $rounds[-1].FullName }
if (-not (Test-Path -LiteralPath (Join-Path $roundDir 'round.json'))) { Stop-Collect "round $(Split-Path -Leaf $roundDir) has no round.json (was new-round interrupted?)" }

$lockPath = Join-Path $roundDir '.collect.lock'
try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
} catch {
    Stop-Collect "another collect is running for $(Split-Path -Leaf $roundDir) (could not lock $lockPath); nothing was written"
}

$rm = try { Get-Content -LiteralPath (Join-Path $roundDir 'round.json') -Raw | ConvertFrom-Json } catch { Stop-Collect "round.json is not valid JSON: $($_.Exception.Message)" }
$started = ConvertTo-RoundStartedAtUtc $rm.startedAt
$thisNo = [int]((Split-Path -Leaf $roundDir).Substring(6))
$next = @($rounds | Where-Object { [int]($_.Name.Substring(6)) -gt $thisNo }) | Select-Object -First 1
$ended = $null
if ($next -and (Test-Path -LiteralPath (Join-Path $next.FullName 'round.json'))) {
    $nm = try { Get-Content -LiteralPath (Join-Path $next.FullName 'round.json') -Raw | ConvertFrom-Json } catch { Stop-Collect "$($next.Name)/round.json is not valid JSON: $($_.Exception.Message)" }
    $ended = ConvertTo-RoundStartedAtUtc $nm.startedAt
}

# Spec T: the review's capture window starts at the LOWEST-numbered round that has a round.json,
# not at this round's own start - a round-tagged capture saved after a later round started must
# still be reachable by number.
$firstRoundWithJson = @($rounds | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'round.json') }) | Select-Object -First 1
if (-not $firstRoundWithJson) { Stop-Collect 'no round has a round.json' }
$reviewStart = if ($firstRoundWithJson.FullName -eq $roundDir) {
    $started
} else {
    $frm = try { Get-Content -LiteralPath (Join-Path $firstRoundWithJson.FullName 'round.json') -Raw | ConvertFrom-Json } catch { Stop-Collect "$($firstRoundWithJson.Name)/round.json is not valid JSON: $($_.Exception.Message)" }
    ConvertTo-RoundStartedAtUtc $frm.startedAt
}

$inboxDir = Resolve-RelayInbox $Inbox
if (-not (Test-Path -LiteralPath $inboxDir -PathType Container)) { Stop-Collect "inbox folder not found: $inboxDir" }

$candidates = @(Get-ChildItem -LiteralPath $inboxDir -File -Filter '*.md' |
    Where-Object { $_.LastWriteTimeUtc -gt $reviewStart } | Sort-Object LastWriteTimeUtc)

$captures = @(
    foreach ($f in $candidates) {
        $inWindow = $f.LastWriteTimeUtc -gt $started -and ($null -eq $ended -or $f.LastWriteTimeUtc -lt $ended)
        $c = $null
        $readErr = $null
        try {
            $c = Read-AiSaveCapture $f.FullName
        } catch {
            $readErr = $_
        }
        if ($readErr) {
            Stop-Collect "could not read $($f.Name) ($($readErr.Exception.Message)); it may still be downloading or open in another program. Nothing was written - run collect again."
        }
        if ($null -eq $c) { continue }
        # Spec T: a tagged capture is included only when its Review/Round match this run, regardless
        # of window; an untagged capture is included only when it falls in the existing window.
        if ($c.Tag) {
            if ($c.Tag.Review -ceq $Review -and $c.Tag.Round -eq $thisNo) {
                [pscustomobject]@{ File = $f; Capture = $c }
            }
        } elseif ($inWindow) {
            [pscustomobject]@{ File = $f; Capture = $c }
        }
    }
)
if ($captures.Count -eq 0) {
    Write-Host "collect: no AiSave captures in $inboxDir saved after $($started.ToString('o'))$(if ($ended) { " and before $($ended.ToString('o'))" })"
    $lock.Dispose()
    exit 2
}

$rows = [System.Collections.Generic.List[string]]::new()
$bodies = [System.Collections.Generic.List[string]]::new()
$n = 0
$repliesDir = Join-Path $roundDir 'replies'
$summaryPath = Join-Path $roundDir 'collected.md'
if ((Test-Path -LiteralPath $summaryPath) -and $PSCmdlet.ShouldProcess($summaryPath, 'remove previous summary')) { Remove-Item -LiteralPath $summaryPath }
foreach ($old in @(Get-ChildItem -LiteralPath $repliesDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d{2}-' })) {
    if ($PSCmdlet.ShouldProcess($old.FullName, 'remove previous copy')) { Remove-Item -LiteralPath $old.FullName }
}
foreach ($item in $captures) {
    $n++
    $c = $item.Capture
    $copyName = '{0:D2}-{1}' -f $n, $item.File.Name
    $proof = Get-RelayReadProof -Reply $c.Reply -EndMarkerCode $rm.endMarker -ExpectedLastLine $rm.expectedLastLine
    $verdict = Get-RelayVerdict $c.Reply
    $counts = Get-RelayCounts -Findings @(Get-RelayFindings $c.Reply) -Verdict $verdict
    $reported = if ($null -ne $proof.ReportedLineCount) { $proof.ReportedLineCount } else { '-' }
    $rows.Add("| $n | $($c.Platform) | $($proof.Result) | $reported | $verdict | $($counts.BLOCKING) | $($counts.MATERIAL) | $($counts.MINOR) | $($counts.UNKNOWN) |")
    $replyBody = $c.Reply
    if ([string]::IsNullOrWhiteSpace($replyBody)) {
        $replyBody = '(This capture has no reply - it has no "## Assistant" section. It was probably saved before the model finished answering. Save it again once the answer is complete.)'
        $hint = ''
        if ($c.Format -eq 'aisave') {
            # G2 (owner ruling 2026-09-29): a plain AiSave capture has no unambiguous turn delimiter,
            # so a reply that quotes its own "---" + "## Human" (a transcript in a code block, say) hides
            # the reply. The parser is left alone; the failure stays loud and names the fix.
            $hint = ' If the answer WAS complete, it probably quotes a "## Human" heading, which a plain AiSave capture cannot tell apart from a new turn: save it again with AiSaveDev instead.'
            $replyBody = $replyBody.TrimEnd(')') + $hint + ')'
        }
        Write-Warning "collect: $($item.File.Name) has no reply (saved before the model finished?)$hint"
    }
    $bodies.Add("## $n. $($c.Platform) - $($c.Title)`n`nSource: ``replies/$copyName`` ($($c.Url))`n`n$replyBody`n")
    if ($PSCmdlet.ShouldProcess((Join-Path $roundDir 'replies' $copyName), 'copy capture')) {
        Copy-Item -LiteralPath $item.File.FullName -Destination (Join-Path $roundDir 'replies' $copyName)
    }
}

$summary = @(
    "# review-relay: $Review, round $($rm.round)"
    ''
    "Collected $([DateTime]::UtcNow.ToString('o')) from ``$inboxDir``. Expected end marker ``$($rm.endMarker)``; expected last content line: ``$($rm.expectedLastLine)``; artifact line count $($rm.expectedLineCount) (information only)."
    ''
    '| # | Site | Read proof | Reported lines | Verdict | BLOCKING | MATERIAL | MINOR | UNKNOWN |'
    '|---|---|---|---|---|---|---|---|---|'
    $rows
    ''
    $bodies
) -join "`n"

if ($PSCmdlet.ShouldProcess($summaryPath, 'write summary')) {
    [IO.File]::WriteAllText($summaryPath, $summary, [Text.UTF8Encoding]::new($false))
    Write-Host "collect: $($captures.Count) capture(s) -> $summaryPath"
}
$lock.Dispose()
exit 0
