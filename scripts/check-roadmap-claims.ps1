#!/usr/bin/env pwsh
# Verifies the ROADMAP's own MECHANICALLY CHECKABLE claims. It does not judge whether an item is done -
# nothing can - it checks the evidence an entry cites about the repository.
#
# WHY THIS EXISTS. The ROADMAP has read OPEN for shipped work FOUR times (13b, 17, 18, 19, 14h). The rule
# earned from that - "whoever closes an item writes its closing sha in the same commit" - had ZERO
# implementation when this was written, and a rule with no implementation is worse than none because it is
# believed. MEASURED 2026-08-31: all FOUR of the ROADMAP's `(N lines)` claims were wrong, and all four sat
# in the 14h entry - the one that had been stale for sixteen days. Precision 4/4 on the real defect.
#
# TWO CHECKS, deliberately narrow so they cannot be argued with:
#   A. every `path` (N lines) claim matches the tracked file it names;
#   B. every backticked 7-40 hex sha on a line ALSO carrying a closure token actually exists.
# Check B passed 28/28 when written - it is a trap for a future phantom, not a backlog.
#
# EXIT CODES: 0 = every claim holds · 1 = at least one claim is false · 2 = cannot check.
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$RoadmapPath
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot)    { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $RoadmapPath) { $RoadmapPath = Join-Path $RepoRoot 'clavity-dotnet' 'ROADMAP.md' }

if (-not (Test-Path -LiteralPath $RoadmapPath)) {
    Write-Host "check-roadmap-claims: '$RoadmapPath' not found - nothing was checked" -ForegroundColor Yellow
    exit 2
}

$tracked = @(& git -C $RepoRoot ls-files)
if ($LASTEXITCODE -ne 0) {
    Write-Host "check-roadmap-claims: '$RepoRoot' is not a git repository - nothing was checked" -ForegroundColor Yellow
    exit 2
}

$lines = [IO.File]::ReadAllText($RoadmapPath) -split "`r?`n"
$problems = @()

# --- A. line-count claims -------------------------------------------------------------------------
$claimRe = [regex]'`([A-Za-z0-9_./-]+\.(?:md|ps1|sh|cs|rs|json))`\s*\((\d+)\s+lines\)'
for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($m in $claimRe.Matches($lines[$i])) {
        $rel     = $m.Groups[1].Value
        $claimed = [int]$m.Groups[2].Value
        $hits    = @($tracked | Where-Object { $_ -eq $rel -or $_.EndsWith("/$rel") })
        if ($hits.Count -eq 0) {
            $problems += "UNRESOLVED  ROADMAP:$($i+1)  ``$rel`` is not a tracked file"
            continue
        }
        $counts = @($hits | ForEach-Object {
            ([IO.File]::ReadAllText((Join-Path $RepoRoot ($_ -replace '/', [IO.Path]::DirectorySeparatorChar))) -split "`n").Count - 1
        })
        if (@($counts | Sort-Object -Unique).Count -gt 1) {
            $problems += "AMBIGUOUS   ROADMAP:$($i+1)  ``$rel`` resolves to $($hits.Count) tracked files with different counts ($($counts -join ', ')) - name the path"
            continue
        }
        if ($counts[0] -ne $claimed) {
            $problems += "STALE       ROADMAP:$($i+1)  ``$rel`` claims $claimed lines, actual $($counts[0])"
        }
    }
}

# --- B. sha existence beside a closure token -------------------------------------------------------
$closure = [regex]'SHIPPED|RULED|OWNER ACCEPTED|CLOSED'
$shaRe   = [regex]'`([0-9a-f]{7,40})`'
$seen    = @{}
for ($i = 0; $i -lt $lines.Count; $i++) {
    if (-not $closure.IsMatch($lines[$i])) { continue }
    foreach ($m in $shaRe.Matches($lines[$i])) {
        $s = $m.Groups[1].Value
        $key = "$s|$($i+1)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        & git -C $RepoRoot cat-file -e "$s^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) {
            $problems += "PHANTOM     ROADMAP:$($i+1)  ``$s`` does not exist in this repository"
        }
    }
}

if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host $p -ForegroundColor Red }
    Write-Host ""
    Write-Host "check-roadmap-claims: $($problems.Count) false claim(s) in $RoadmapPath" -ForegroundColor Red
    exit 1
}
Write-Host "check-roadmap-claims: OK - every line-count claim and closure sha in $RoadmapPath holds" -ForegroundColor Green
exit 0
