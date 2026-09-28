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
    [int]$Round,
    [string]$Inbox,
    [string]$ProjectRoot = (Get-Location).Path
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'relay-lib.ps1')

function Stop-Collect([string]$Message) { Write-Host "collect: $Message" -ForegroundColor Red; exit 1 }

$root = (Resolve-Path -LiteralPath $ProjectRoot).ProviderPath
$ws = Join-Path $root '.review-relay' $Review
if (-not (Test-Path -LiteralPath (Join-Path $ws 'review.json'))) { Stop-Collect "no review named '$Review' in $root" }
$rounds = @(Get-ChildItem -LiteralPath $ws -Directory -Filter 'round-*' |
    Where-Object { $_.Name -match '^round-\d+$' } | Sort-Object { [int]($_.Name.Substring(6)) })
if ($rounds.Count -eq 0) { Stop-Collect 'no rounds yet: run new-round.ps1 first' }
$roundDir = if ($Round) { Join-Path $ws ('round-{0:D2}' -f $Round) } else { $rounds[-1].FullName }
if (-not (Test-Path -LiteralPath (Join-Path $roundDir 'round.json'))) { Stop-Collect "round $Round does not exist" }
$rm = try { Get-Content -LiteralPath (Join-Path $roundDir 'round.json') -Raw | ConvertFrom-Json } catch { Stop-Collect "round.json is not valid JSON: $($_.Exception.Message)" }
$started = if ($rm.startedAt -is [datetime]) { $rm.startedAt.ToUniversalTime() } else { [DateTime]::Parse($rm.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
$thisNo = [int]((Split-Path -Leaf $roundDir).Substring(6))
$next = @($rounds | Where-Object { [int]($_.Name.Substring(6)) -gt $thisNo }) | Select-Object -First 1
$ended = $null
if ($next -and (Test-Path -LiteralPath (Join-Path $next.FullName 'round.json'))) {
    $nm = try { Get-Content -LiteralPath (Join-Path $next.FullName 'round.json') -Raw | ConvertFrom-Json } catch { Stop-Collect "$($next.Name)/round.json is not valid JSON: $($_.Exception.Message)" }
    $ended = if ($nm.startedAt -is [datetime]) { $nm.startedAt.ToUniversalTime() } else { [DateTime]::Parse($nm.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime() }
}

$inboxDir = Resolve-RelayInbox $Inbox
if (-not (Test-Path -LiteralPath $inboxDir -PathType Container)) { Stop-Collect "inbox folder not found: $inboxDir" }

$captures = @(
    foreach ($f in @(Get-ChildItem -LiteralPath $inboxDir -File -Filter '*.md' | Where-Object { $_.LastWriteTimeUtc -gt $started -and ($null -eq $ended -or $_.LastWriteTimeUtc -lt $ended) } | Sort-Object LastWriteTimeUtc)) {
        $c = try { Read-AiSaveCapture $f.FullName } catch { Write-Warning "collect: skipped $($f.Name): $($_.Exception.Message)"; $null }
        if ($c) { [pscustomobject]@{ File = $f; Capture = $c } }
    }
)
if ($captures.Count -eq 0) {
    Write-Host "collect: no AiSave captures in $inboxDir saved after $($started.ToString('o'))$(if ($ended) { " and before $($ended.ToString('o'))" })"
    exit 2
}

$rows = [System.Collections.Generic.List[string]]::new()
$bodies = [System.Collections.Generic.List[string]]::new()
$n = 0
$repliesDir = Join-Path $roundDir 'replies'
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
    $rows.Add("| $n | $($c.Platform) | $($proof.Result) | $reported | $verdict | $($counts.BLOCKING) | $($counts.MATERIAL) | $($counts.MINOR) |")
    $bodies.Add("## $n. $($c.Platform) - $($c.Title)`n`nSource: ``replies/$copyName`` ($($c.Url))`n`n$($c.Reply)`n")
    if ($PSCmdlet.ShouldProcess((Join-Path $roundDir 'replies' $copyName), 'copy capture')) {
        Copy-Item -LiteralPath $item.File.FullName -Destination (Join-Path $roundDir 'replies' $copyName)
    }
}

$summary = @(
    "# review-relay: $Review, round $($rm.round)"
    ''
    "Collected $([DateTime]::UtcNow.ToString('o')) from ``$inboxDir``. Expected end marker ``$($rm.endMarker)``; expected last content line: ``$($rm.expectedLastLine)``; artifact line count $($rm.expectedLineCount) (information only)."
    ''
    '| # | Site | Read proof | Reported lines | Verdict | BLOCKING | MATERIAL | MINOR |'
    '|---|---|---|---|---|---|---|---|'
    $rows
    ''
    $bodies
) -join "`n"

if ($PSCmdlet.ShouldProcess((Join-Path $roundDir 'collected.md'), 'write summary')) {
    [IO.File]::WriteAllText((Join-Path $roundDir 'collected.md'), $summary, [Text.UTF8Encoding]::new($false))
    Write-Host "collect: $($captures.Count) capture(s) -> $(Join-Path $roundDir 'collected.md')"
}
exit 0
