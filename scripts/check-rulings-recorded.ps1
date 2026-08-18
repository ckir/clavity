<#
.SYNOPSIS
  Assert that each named ROADMAP entry carries an OWNER RULING block.

.DESCRIPTION
  Written for the steps-0-1 plan (docs/superpowers/plans/2026-08-19-steps-0-1-merge-and-rulings.md,
  Task 8). It exists because the plan's first verifier - an inline awk one-liner - FAILED SILENTLY on
  the last of the four entries: it scanned forward for the next `#### ` heading to bound the section,
  and the entry after §17b is `### §18` (three hashes), so the bound never matched, the loop ran to
  EOF, and it printed nothing at all. No output read as "not ruled" to a human skimming and as success
  to a pipeline. The entry it silently skipped is §17b, whose ruling may legitimately be KILLED - the
  one most likely to be written in an unexpected shape.

  A section here is bounded by the NEXT heading of ANY level, and every named section must be found.
  A section that cannot be located is a hard failure, never a silent pass.

  The marker match is CASE-SENSITIVE, which is also load-bearing: every unruled entry carries the
  literal 'needs an owner ruling, not a fix' in its own OPEN marker, so a case-insensitive check
  reported §14f as RULED *because the entry said it needed a ruling*.

.PARAMETER RoadmapPath
  Path to the ROADMAP under test. Defaults to the repository's clavity-dotnet/ROADMAP.md.

.PARAMETER Marker
  The literal that marks a recorded ruling. Defaults to 'OWNER RULING (' - the trailing paren is
  deliberate, and the comparison is case-SENSITIVE. See the case-sensitivity note above.

.PARAMETER Section
  The section identifiers to require a ruling for. Defaults to the four from the plan.

.EXAMPLE
  pwsh -NoProfile -File scripts/check-rulings-recorded.ps1
  Exit 0 when all four sections carry a ruling; exit 1 otherwise, naming each that does not.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]   $RoadmapPath = (Join-Path $PSScriptRoot '..' 'clavity-dotnet' 'ROADMAP.md'),
    [string]   $Marker      = 'OWNER RULING (',
    [string[]] $Section     = @('14f', '14g', '17a', '17b')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $RoadmapPath)) {
    Write-Error "ROADMAP not found: $RoadmapPath"
    exit 1
}

if ($PSCmdlet.ShouldProcess($RoadmapPath, "Check for '$Marker' in sections $($Section -join ', ')")) {

    # Read with newline='' semantics: keep the file's own line endings out of the comparison.
    $lines = [System.IO.File]::ReadAllLines($RoadmapPath)

    # A heading is any markdown ATX heading, at ANY level. Bounding on `#### ` alone is the defect
    # this script was written to replace.
    $headingIdx = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^#{1,6}\s') { $headingIdx += $i }
    }

    $failed  = @()
    $missing = @()

    foreach ($s in $Section) {
        # Locate the section's own heading. The entries are written two ways in this file -
        # `#### §17a - ...` and `**§14f - ...` - so match the identifier, not the heading syntax.
        $start = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match ("(?:^#{1,6}\s.*|^\*\*)§" + [regex]::Escape($s) + '(?![0-9a-z])')) {
                $start = $i; break
            }
        }
        if ($start -lt 0) {
            # NOT a silent pass. An anchor that cannot be found means the plan's anchor is stale.
            $missing += $s
            continue
        }

        # Bound at the next heading of ANY level after the start, else EOF.
        $end = $lines.Count
        foreach ($h in $headingIdx) { if ($h -gt $start) { $end = $h; break } }

        $body = $lines[$start..($end - 1)] -join "`n"
        # -cmatch, NOT -match. PowerShell's -match is CASE-INSENSITIVE, and every unruled entry here
        # carries the literal 'needs an owner ruling, not a fix' in its own OPEN marker - so a
        # case-insensitive check reported an entry as RULED *because it said it needed a ruling*.
        # That is the strongest possible false positive: the marker matched the NEGATION of itself.
        # The trailing '(' of 'OWNER RULING (' keeps it clear of prose mentions too.
        if ($body -cnotmatch [regex]::Escape($Marker)) { $failed += $s }
    }

    foreach ($s in $Section) {
        $state = if ($missing -contains $s) { 'SECTION-NOT-FOUND' }
                 elseif ($failed -contains $s) { 'NO RULING' }
                 else { 'RULED' }
        Write-Host ("{0,-6} {1}" -f $s, $state)
    }

    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "FAIL: section anchor(s) not found: $($missing -join ', ')" -ForegroundColor Red
        Write-Host "The ROADMAP heading changed. Re-locate the entry rather than assuming it is unruled."
        exit 1
    }
    if ($failed.Count -gt 0) {
        Write-Host ""
        Write-Host "FAIL: no '$Marker' block in: $($failed -join ', ')" -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "OK: all $($Section.Count) section(s) carry a '$Marker' block." -ForegroundColor Green
    exit 0
}
