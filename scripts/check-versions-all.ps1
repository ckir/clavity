#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Run check-versions.ps1 for every member in ONE pwsh process. Pre-push hook entry point.

.DESCRIPTION
  Semantically identical to chaining five `pwsh -File scripts/check-versions.ps1 <member>` calls with
  `&&`: same members, same order, same fail-fast on the first failure, same exit code. The only
  difference is process count — one cold pwsh start instead of five.

  That matters because of WHERE this runs. A pwsh cold start costs ~6s on this platform (see the
  installer-ascii note in lefthook.yml), so the old five-call chain spent ~30s of its ~34s purely
  starting processes. git opens the remote SSH connection BEFORE running the pre-push hook and leaves
  it idle for the hook's entire duration, so every one of those seconds is idle time on a live
  connection — the window in which a silently-dropped connection wedges a push indefinitely
  (observed 2026-07-21: two pushes and one release hung ~19h with no output and no timeout).
  Measured: hook total 62.5s, of which check-versions was 33.7s.

  Not a substitute for the per-member form: CI's build-<member>.yml gates each member individually,
  and bump-version.ps1 self-verifies one member. Both still call check-versions.ps1 directly.

.EXAMPLE
  pwsh -File scripts/check-versions-all.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$checker = Join-Path $PSScriptRoot 'check-versions.ps1'
if (-not (Test-Path -PathType Leaf $checker)) {
    Write-Host "check-versions-all: FAIL: missing $checker" -ForegroundColor Red
    exit 1
}

# Same order the lefthook `&&` chain used. Kept explicit rather than derived from a roster file so this
# hook entry point has no dependency that could make it silently check FEWER members than it claims.
$members = @('dotnet', 'classic', 'ghidrust', 'agy-autotrain', 'commonmemory')

$LASTEXITCODE = 0
foreach ($member in $members) {
    & $checker $member
    if ($LASTEXITCODE -ne 0) {
        Write-Host "check-versions-all: FAIL at '$member' (remaining members not checked)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Write-Host "check-versions-all: OK ($($members.Count) members)" -ForegroundColor Green
exit 0
