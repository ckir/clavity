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
  The budget. Default 4096. THE single source of truth; a deliberate raise is a committed edit here.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [int]$MaxBytes = 4096
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
$bytes = 0
if (Test-Path $Path) {
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount([System.IO.File]::ReadAllText($Path))
}

if ($bytes -gt $MaxBytes) {
    Fail "driver cheatsheet is ${bytes}B > ${MaxBytes}B - consolidate it, or raise the -MaxBytes default in scripts/check-cheatsheet-budget.ps1 deliberately"
}

Write-Host "check-cheatsheet-budget: OK - cheatsheet ${bytes}B <= ${MaxBytes}B" -ForegroundColor Green
exit 0
