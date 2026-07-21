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
# An UNCLASSIFIED path means the engine has no idea who owns a change — the silent under-bump that stranded
# the 69ee30f registration fix. Refuse unconditionally, NOT merely when there is nothing else to release:
# an undeclared shared asset committed alongside any member-scoped change still produces a bump, and gating
# on `Nothing` would let it through on a warning (agy adversarial review, 2026-07-21). A genuinely dev-only
# range is classified, so this still can't cry wolf.
if ($r.Unclassified.Count) {
    Write-Host "release: these touched paths are UNCLASSIFIED — nobody would be versioned for them:" -ForegroundColor Red
    foreach ($p in $r.Unclassified) { Write-Host "  $p" -ForegroundColor Red }
    Die "refusing to release. Classify each path in scripts/lib/release-lib.ps1: `$SharedPaths (it ships to members) or `$DevOnlyPaths (it reaches no end user)."
}
if ($r.Nothing) { Write-Host "release: nothing to release (dev-only changes)." -ForegroundColor Yellow; exit 0 }

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
# Keepalives, mirrored from ~/.ssh/config so the fix travels with the repo (a fresh clone or another
# machine has no such config). git opens the SSH connection BEFORE any pre-push hook runs and leaves it
# idle for the hook's duration; without probes, a drop with no RST is invisible and git blocks forever.
$env:GIT_SSH_COMMAND = 'ssh -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o TCPKeepAlive=yes'

# A push that HANGS is not a push that FAILS: on 2026-07-21 two `git push origin main` and one
# `just release` sat wedged ~19h with no output, no error and no timeout, and had to be force-killed.
# Retry is deliberately OPT-IN on transport signatures only, checked AFTER rejection signatures, with
# anything unrecognised treated as fatal. A retry must never turn a real refusal (non-fast-forward,
# permission denied, remote hook decline) into a silent second attempt that appears to succeed.
$script:PushRejectRe = 'rejected|non-fast-forward|fetch first|Permission denied|Authentication failed|' +
                       'pre-receive hook declined|protected branch|denied to |not authorized|forbidden'
$script:PushRetryRe  = 'Connection closed|Connection reset|Connection timed out|Broken pipe|' +
                       'kex_exchange_identification|ssh_exchange_identification|Timeout, server|' +
                       'The remote end hung up|early EOF|RPC failed|Network is unreachable|' +
                       'Temporary failure in name resolution|Could not resolve hostname|CLAVITY_PUSH_TIMEOUT'

# $FailHint is printed IMMEDIATELY BEFORE exiting on any fatal path. It is a parameter rather than a
# try/catch at the call site on purpose: Die calls `exit`, which unwinds the whole script and can never
# be caught — so a catch block around this function would silently never run.
function Invoke-GitPush([string]$Ref, [string]$What, [string[]]$FailHint = @()) {
    $maxAttempts = 3
    $timeoutSec  = 180
    function Stop-Push([string]$msg) {
        foreach ($line in $FailHint) { Write-Host $line -ForegroundColor Red }
        Die $msg
    }
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $o = [IO.Path]::GetTempFileName(); $e = [IO.Path]::GetTempFileName()
        $p = Start-Process git -ArgumentList @('push', 'origin', $Ref) -NoNewWindow -PassThru `
                              -RedirectStandardOutput $o -RedirectStandardError $e
        if ($p.WaitForExit($timeoutSec * 1000)) {
            $code = $p.ExitCode
            $text = ((Get-Content $o -Raw -EA SilentlyContinue) + (Get-Content $e -Raw -EA SilentlyContinue))
        } else {
            # Bounded, and LOUD. This is the exact state that previously sat silent for 19 hours.
            try { $p.Kill($true) } catch { }
            $code = 1
            $text = "CLAVITY_PUSH_TIMEOUT: no response from origin within ${timeoutSec}s (connection dead or idle, not refused)"
        }
        Remove-Item $o, $e -Force -EA SilentlyContinue
        if ($text) { Write-Host $text.TrimEnd() }
        if ($code -eq 0) { return }

        if ($text -match $script:PushRejectRe) {
            Stop-Push "$What REJECTED by origin (not a connection problem) — no retry, nothing else was pushed. Fix and re-run.`n$text"
        }
        if ($text -notmatch $script:PushRetryRe) {
            Stop-Push "$What failed with an UNRECOGNISED error — refusing to retry blind, since a retry must never mask a rejection.`n$text"
        }
        if ($attempt -lt $maxAttempts) {
            Write-Host "release: $What — transport failure (attempt $attempt/$maxAttempts), retrying in ${attempt}0s..." -ForegroundColor Yellow
            Start-Sleep -Seconds ($attempt * 10)
        }
    }
    Stop-Push "$What failed after $maxAttempts transport attempts — origin unreachable or dropping the connection. Nothing further was pushed."
}

Invoke-GitPush 'main' 'push main' @('release: nothing was tagged — fix and re-run.')
git tag $script:Target
Invoke-GitPush $script:Target "push tag $($script:Target)" @(
    'release: COMMIT IS ON main BUT TAG PUSH FAILED — no release has fired.',
    "release: run  git push origin $($script:Target)  to complete it."
)

# --- Observability (F11/V2): print run URL, suggest non-blocking watch ---
$repo = (gh repo view --json nameWithOwner -q .nameWithOwner 2>$null)
Write-Host "release: tag $($script:Target) pushed. CI is gating + will auto-publish on green." -ForegroundColor Green
if ($repo) { Write-Host "release: watch → https://github.com/$repo/actions   (or: gh run watch)" -ForegroundColor Green }
