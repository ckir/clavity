#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Assert the canonical driver cheatsheet is within its committed byte budget. Dev/CI-time only.
  Test-Path-guarded: a missing file counts as 0 bytes.
.DESCRIPTION
  agy-curate/SKILL.md instructs the curator to distil the durable driver knowledge into a lean cheatsheet.
  That instruction previously named a size (~150 tokens / ~3 bullets) that NOTHING enforced, and the
  artifact drifted to roughly 4x it unnoticed. This is the enforcement half: an unenforced budget is how
  the drift happened, so the number and its checker ship together.

  This is NOT the runtime cap. clavity-classic/src/driver_cheatsheet.rs:12 sets MAX_BYTES = 16 * 1024 on
  the RUNTIME driver-cheatsheet.md, and a file over it degrades to the compiled-in baseline floor. This
  budget is deliberately far below that, so drift is caught long before the cliff.
.PARAMETER Path
  Path to the canonical cheatsheet. Defaults to agy-autotrain/knowledge/driver-cheatsheet.core.md.
.PARAMETER MaxBytes
  The budget. Default 6144. THE single source of truth; a deliberate raise is a committed edit here.

  RAISED 4096 -> 6144 on 2026-08-19, deliberately, and this is the record of why. The canonical
  cheatsheet reached 4750B at af2a256 (2026-08-17) and sat over the old budget for two days undetected,
  because this gate runs only in build-*.yml, which is `branches: [main]` on push - so it had never
  executed on the branch the growth happened on. PR #1 is the first run that caught it, which is the
  gate working, just later than it should have.

  Why raise rather than consolidate: the growth is earned - it is drained peer-behaviour rules, each of
  which cost a real defect to learn - and the canonical is byte-pinned into both drivers, so trimming it
  means editing two compiled literals and re-running both pinning oracles. 6144 keeps ~29% headroom over
  today's 4750B and stays 2.6x below the 16 KiB runtime cliff in driver_cheatsheet.rs, so drift is still
  caught long before degradation. It is NOT an invitation to grow into: the next raise should have to
  argue for itself the same way.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [int]$MaxBytes = 6144
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $Path) { $Path = Join-Path $RepoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md' }

function Fail([string]$msg) {
    Write-Host "check-cheatsheet-budget: FAIL: $msg" -ForegroundColor Red
    exit 1
}

# A missing cheatsheet (fresh clone, never drained) is 0 bytes <= budget - never a crash. This mirrors
# check-seed-budget.ps1 deliberately.
#
# Yes, that means a DELETED canonical also reports OK here. That is not a hole, because deletion is
# already caught harder elsewhere and this script is a BUDGET gate, not an existence gate: the file is
# byte-pinned into both drivers (agy-curate/SKILL.md documents the three-file pin), so removing it reds
# `baseline_floor_matches_canonical_core_source` and `BaselineFloor_matches_the_canonical_core_source`;
# it is in the drain's protected-path list; and this script's own Pester suite asserts Test-Path on the
# real canonical before invoking it. Making a budget checker fail on absence would break the fresh-clone
# case its sibling exists to protect.
# Measure the RAW BYTES ON DISK, never a decoded string. ReadAllText detects and STRIPS a UTF-8 BOM
# before returning, so UTF8.GetByteCount over its result under-reports a BOM'd file by exactly 3 bytes
# (measured: 8 bytes on disk, 5 counted). The consumer this budget protects reads raw bytes, so a
# decoded count is measuring something the runtime never sees - and the gap only shows up at the
# boundary, which is precisely where a budget gate is supposed to be right.
$bytes = 0
if (Test-Path $Path) {
    $bytes = [System.IO.File]::ReadAllBytes($Path).Length
}

if ($bytes -gt $MaxBytes) {
    Fail "driver cheatsheet is ${bytes}B > ${MaxBytes}B - consolidate it, or raise the -MaxBytes default in scripts/check-cheatsheet-budget.ps1 deliberately"
}

Write-Host "check-cheatsheet-budget: OK - cheatsheet ${bytes}B <= ${MaxBytes}B" -ForegroundColor Green
exit 0
