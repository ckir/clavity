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
# ANY extension, not a whitelist. It was `(?:md|ps1|sh|cs|rs|json)`, which SILENTLY ignored a claim
# about a .yml, .txt or .iss file - a fail-open in a guard whose whole job is to close one. Zero such
# claims exist today (measured), so this closes a latent hole rather than fixing a live miss. The
# backticks plus the literal `(N lines)` already make the shape specific enough that widening the
# extension cannot pull in prose. AGY-CAPSTONE round 1.
$claimRe = [regex]'`([A-Za-z0-9_./-]+\.[A-Za-z0-9]+)`\s*\((\d+)\s+lines\)'
for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($m in $claimRe.Matches($lines[$i])) {
        $rel     = $m.Groups[1].Value
        # TryParse, not a bare [int] cast. The regex's `\d+` is unbounded, so a claim like
        # `(99999999999999999999999999 lines)` overflowed Int32 and threw an unhandled conversion error.
        # Uncontrolled input must not crash a checker: report it and carry on. AGY-CAPSTONE round 2.
        $claimed = 0
        if (-not [int]::TryParse($m.Groups[2].Value, [ref]$claimed)) {
            $problems += "UNPARSEABLE ROADMAP:$($i+1)  ``$rel`` claims '$($m.Groups[2].Value)' lines, which is not a number this checker can hold"
            continue
        }
        $hits    = @($tracked | Where-Object { $_ -eq $rel -or $_.EndsWith("/$rel") })
        if ($hits.Count -eq 0) {
            $problems += "UNRESOLVED  ROADMAP:$($i+1)  ``$rel`` is not a tracked file"
            continue
        }
        # A TRACKED FILE CAN BE ABSENT FROM THE WORKTREE - `git ls-files` reads the INDEX, so a file
        # deleted but not staged is still listed. MEASURED at AGY-CAPSTONE round 1: `ReadAllText` then
        # threw an unhandled FileNotFoundException and the script exited **1**, which is the "a claim is
        # false" code - so a broken worktree was indistinguishable from a stale line count, sending the
        # reader to hunt a number that was never wrong. Fail CLOSED, and say which thing broke.
        # -PathType Leaf, NOT a bare Test-Path. AGY-CAPSTONE round 2 caught this in round 1's OWN FIX:
        # a bare Test-Path returns TRUE for a DIRECTORY, so a tracked file replaced by a directory of the
        # same name passed this guard and then threw an unhandled UnauthorizedAccessException at
        # ReadAllText. MEASURED: Test-Path -> True, Test-Path -PathType Leaf -> False. A fix is a fresh
        # claim, and this one shipped its own edge.
        $absent = @($hits | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $RepoRoot ($_ -replace '/', [IO.Path]::DirectorySeparatorChar)) -PathType Leaf)
        })
        if ($absent.Count -gt 0) {
            $problems += "UNREADABLE  ROADMAP:$($i+1)  ``$rel`` is tracked but is not a readable file in the worktree ($($absent -join ', ')) - the claim cannot be checked"
            continue
        }
        $counts = @($hits | ForEach-Object {
            ([IO.File]::ReadAllText((Join-Path $RepoRoot ($_ -replace '/', [IO.Path]::DirectorySeparatorChar))) -split "`n").Count - 1
        })
        if (@($counts | Sort-Object -Unique).Count -gt 1) {
            $problems += "AMBIGUOUS   ROADMAP:$($i+1)  ``$rel`` resolves to $($hits.Count) tracked files with different counts ($($counts -join ', ')) - disambiguate it with the FULL repo-relative path, e.g. ``clavity-dotnet/plugin/$rel``"
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
