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

  This is NOT the runtime cap. `driver_cheatsheet.rs` / `DriverCheatsheet.cs` set MAX_BYTES = 16 * 1024 on
  the COMBINED block, and a combined block over it degrades to the compiled-in baseline floor. This budget
  is deliberately far below that, so drift in the FLOOR is caught long before the cliff.
.PARAMETER CheckCombined
  Also measure the floor PLUS the runtime GROWTH file against the runtime 16 KiB cap, and print the
  REMAINING budget a curator may spend.

  This exists because the floor budget above is blind to the half that actually moves. Since the readers
  became EXTEND, what gets injected is `floor + "

" + growth`, and only the SUM is capped - a growth
  file that fits its own cap can still push the combined block over, at which point the binary silently
  drops GROWTH and keeps the floor. MEASURED 2026-08-27, the sibling golden header was in exactly that
  state in production: 16,803 B against a 16,384 B cap, dropping its GROWTH on EVERY injection, while its
  own budget gate measured REPO paths and so could not see it.

  agy-curate/SKILL.md tells the curator to run this rather than hand-computing the remaining bytes from a
  figure written in prose - that figure has rotted twice.
.PARAMETER GrowthPath
  The runtime growth file to add when -CheckCombined is given. Defaults to the resolved runtime path
  (CLAVITY_GOLDEN_HEADER, else ~/.clavity), which is what the binary actually reads. A parameter so the
  suite can point it at a fixture - a gate that can only run against one machine's home directory cannot
  have its failure path proven.
.PARAMETER CombinedMaxBytes
  The runtime combined cap. Default 16384, mirroring MAX_BYTES / MaxBytes in the two readers.
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
    [int]$MaxBytes = 6144,
    [switch]$CheckCombined,
    [string]$GrowthPath,
    [int]$CombinedMaxBytes = 16384
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

if ($CheckCombined) {
    if (-not $GrowthPath) {
        # Resolve exactly as the binaries do: the override DIRECTORY first, then the user profile.
        $dir = $env:CLAVITY_GOLDEN_HEADER
        if (-not $dir) { $dir = Join-Path ($env:USERPROFILE ? $env:USERPROFILE : $HOME) '.clavity' }
        $GrowthPath = Join-Path $dir 'driver-cheatsheet.growth.md'
    }
    $growth = 0
    if (Test-Path -LiteralPath $GrowthPath) {
        $growth = [System.IO.File]::ReadAllBytes($GrowthPath).Length
    }
    # The separator is two bytes and is spent whether or not the curator remembers it. Count it always, so
    # the REMAINING figure a curator sizes against is never one that only just fits.
    $sep = 2
    $combined = $bytes + $sep + $growth
    if ($combined -gt $CombinedMaxBytes) {
        Fail ("combined driver-cheatsheet is ${combined}B > ${CombinedMaxBytes}B (floor ${bytes}B + separator ${sep}B + growth ${growth}B at ${GrowthPath}). " +
              "The binary DROPS GROWTH SILENTLY above this and keeps the floor alone, so nothing else will tell you. Trim the growth file.")
    }
    $remaining = $CombinedMaxBytes - $bytes - $sep
    Write-Host "check-cheatsheet-budget: OK - combined ${combined}B <= ${CombinedMaxBytes}B (floor ${bytes}B + sep ${sep}B + growth ${growth}B)" -ForegroundColor Green
    Write-Host "check-cheatsheet-budget: REMAINING GROWTH BUDGET = ${remaining}B" -ForegroundColor Cyan
}
exit 0
