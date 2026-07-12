#!/usr/bin/env pwsh
[CmdletBinding()]
param([switch]$WhatIf)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib' 'release-lib.ps1')
Set-Location $RepoRoot
function Die($m){ Write-Host "release: $m" -ForegroundColor Red; exit 1 }

# --- Precondition-0 (F6/D2/F17/TO1) ---
git fetch --tags --quiet; if ($LASTEXITCODE -ne 0) { Die "git fetch failed (offline?) — baseline/serial need true remote state" }
if ((git rev-parse --abbrev-ref HEAD) -ne 'main') { Die "not on main" }
git diff --quiet;        if ($LASTEXITCODE -ne 0) { Die "unstaged tracked changes present (untracked OK)" }
git diff --cached --quiet;if ($LASTEXITCODE -ne 0) { Die "staged changes present" }
# Only a dangling un-pushed CHORE(RELEASE) commit blocks (plan-review R1) — un-pushed FEATURE commits are
# the normal case (they get swept + pushed by this release). Spec precondition (c) is release-commit-scoped.
if (git log 'origin/main..HEAD' --grep='^chore(release):' --oneline) { Die "un-pushed chore(release) commit on main — a prior release is half-finished; resolve first" }
# F17: the last chore(release) commit must have a remote tag (else a prior tag-push failed / limbo)
$lastRel = git log --basic-regexp --grep='^chore(release): clavity-v' -n1 --format=%s 2>$null
if ($lastRel) {
    if ($lastRel -match '(clavity-v[0-9]+)') {
        $tag = $Matches[1]
        $remote = git ls-remote --tags origin "refs/tags/$tag"
        if (-not $remote) { Die "last release prep '$tag' has NO remote tag (stuck release). Run: git push origin $tag  — or reset to abandon." }
    }
}

# --- Compute ---
$r = & (Join-Path $PSScriptRoot 'compute-release.ps1')
if ($r.Nothing) { Write-Host "release: nothing to release." -ForegroundColor Yellow; exit 0 }

# --- Non-conventional warning (F4) ---
if ($r.NonConventional.Count) {
    Write-Host "release: WARNING — non-conventional commits will NOT be versioned/changelogged:" -ForegroundColor Yellow
    foreach ($w in $r.NonConventional) { foreach ($s in $w.Subjects) { Write-Host "  [$($w.Key)] $s" -ForegroundColor Yellow } }
}

# --- Preview (F9: list EVERY swept bump) ---
$target = "clavity-v$($r.Serial)"
Write-Host "Preparing $target" -ForegroundColor Cyan
$r.Bumps | ForEach-Object {
    $label = if ($_.Channel) { "$($_.Key) ($($_.Channel))" } else { $_.Key }
    Write-Host ("  {0,-24} {1} -> {2}  ({3}, {4} commits)" -f $label,$_.Current,$_.Next,$_.Level,$_.CommitCount)
}
Write-Host "`n--- release notes preview ---`n$(Format-ReleaseNotes $r.Bumps)`n" -ForegroundColor DarkGray

if ($WhatIf) { Write-Host "release: -WhatIf, stopping before any write." -ForegroundColor Yellow; exit 0 }

# --- Typed confirm (F9) ---
$answer = Read-Host "Type '$target' to proceed"
if ($answer -ne $target) { Write-Host "aborted." -ForegroundColor Yellow; exit 0 }

# (bump/commit/pre-flight/push added in Tasks 8-9; stash $r + $target for them)
$script:Computed = $r; $script:Target = $target
