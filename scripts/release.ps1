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
# F17: the last chore(release) commit must have a remote tag (else a prior tag-push failed / limbo) —
# UNLESS the maintainer deliberately RETRACTED that serial (recorded in scripts/release-abandoned.txt), in
# which case a missing remote tag is EXPECTED, not stuck. N is read from the immutable commit SUBJECT (not a
# local git tag, which a retraction deletes), so this survives on a fresh clone.
$lastRel = git log --basic-regexp --grep='^chore(release): clavity-v' -n1 --format=%s 2>$null
if ($lastRel) {
    if ($lastRel -match '(clavity-v[0-9]+)') {
        $tag = $Matches[1]
        $serial = [int]($tag -replace '^clavity-v','')
        $abandoned = @(Get-AbandonedSerials $RepoRoot)
        $remote = git ls-remote --tags origin "refs/tags/$tag"
        if (-not $remote -and ($serial -notin $abandoned)) { Die "last release prep '$tag' has NO remote tag (stuck release). Run: git push origin $tag  — or record it in scripts/release-abandoned.txt to abandon." }
        elseif (-not $remote) { Write-Host "release: '$tag' was retracted (in scripts/release-abandoned.txt) — serial burned, proceeding." -ForegroundColor DarkGray }
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

$dateStr = (Get-Date -Format 'yyyy-MM-dd')
foreach ($b in $script:Computed.Bumps) {
    if ($b.Channel) { & just bump-ghidrust $b.Channel $b.Next }   # ghidrust per channel
    else            { & just bump $b.Key $b.Next }
    if ($LASTEXITCODE -ne 0) { Die "bump failed for $($b.Key) $($b.Channel)" }
    [void](Update-Changelog $RepoRoot $b $dateStr)
}

# F13‴: stage tracked bump edits repo-wide (no path enumeration) + explicit changelog adds; never -am/-A.
git add -u
foreach ($root in ($script:Computed.Bumps.Root | Select-Object -Unique)) {
    $cl = Join-Path $root 'CHANGELOG.md'
    if (Test-Path $cl) { git add -- $cl }
}

# Subject = baseline anchor; body = aggregated notes (CC1). Write body to a temp file for -F to avoid
# quoting hazards, then commit with -m subject -F bodyfile order preserved via two -F/-m? Use file for both.
$members = ($script:Computed.Bumps | ForEach-Object { $l = if ($_.Channel) { "$($_.Key)/$($_.Channel)" } else { $_.Key }; "$l $($_.Next)" }) -join ', '
$subject = "chore(release): $($script:Target) [$members]"
$body    = Format-ReleaseNotes $script:Computed.Bumps
$msgFile = New-TemporaryFile
Set-Content -Path $msgFile -Value ("$subject`n`n$body") -NoNewline
git commit -F $msgFile
$commitRc = $LASTEXITCODE
Remove-Item $msgFile
if ($commitRc -ne 0) { Die "commit failed" }

# --- Local pre-flight (fast gate; no E2E/ISCC) ---
& pwsh -File (Join-Path $PSScriptRoot 'check-roster.ps1');   if ($LASTEXITCODE -ne 0) { Die "pre-flight: roster drift — release roster and build/members.json disagree (CC2 gate)" }
& just test-scripts;                                  if ($LASTEXITCODE -ne 0) { Die "pre-flight: scripts tests failed" }
& just lint;                                          if ($LASTEXITCODE -ne 0) { Die "pre-flight: lint failed" }
& just test;                                          if ($LASTEXITCODE -ne 0) { Die "pre-flight: tests failed" }
foreach ($key in ($script:Computed.Bumps.Key | Select-Object -Unique)) {
    & pwsh -File (Join-Path $PSScriptRoot 'check-versions.ps1') $key;             if ($LASTEXITCODE -ne 0) { Die "pre-flight: check-versions $key failed" }
    & pwsh -File (Join-Path $PSScriptRoot 'check-versions.ps1') $key -Coverage;   if ($LASTEXITCODE -ne 0) { Die "pre-flight: coverage $key failed" }
}

# --- Push sequence (F5): commit first; only then tag + push tag ---
git push origin main
if ($LASTEXITCODE -ne 0) { Die "push main rejected (raced?) — nothing tagged; fix and re-run." }
git tag $script:Target
git push origin $script:Target
if ($LASTEXITCODE -ne 0) {
    Write-Host "release: COMMIT IS ON main BUT TAG PUSH FAILED — no release has fired." -ForegroundColor Red
    Write-Host "release: run  git push origin $($script:Target)  to complete it." -ForegroundColor Red
    exit 1
}

# --- Observability (F11/V2): print run URL, suggest non-blocking watch ---
$repo = (gh repo view --json nameWithOwner -q .nameWithOwner 2>$null)
Write-Host "release: tag $($script:Target) pushed. CI is gating + will auto-publish on green." -ForegroundColor Green
if ($repo) { Write-Host "release: watch → https://github.com/$repo/actions   (or: gh run watch)" -ForegroundColor Green }
