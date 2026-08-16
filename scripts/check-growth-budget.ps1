#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Warn gate: assert the compiled GROWTH proposal, prepended after the SEED, fits the binary's COMBINED injection
  cap. The binary injects SEED + GROWTH only when their combined UTF-8 size is <= 16 KiB; over that it silently
  drops GROWTH and injects SEED-only, so a proposal that fits its own 16 KiB cap but overflows combined is written
  yet never injected. drain-knowledge.ps1 runs this WARN-only (breach does not abort the drain).
.PARAMETER RepoRoot
  Repo root (default: this script's parent's parent).
.PARAMETER MaxBytes
  The combined cap. Default 16384 = 16 KiB, matching GoldenHeader.MaxBytes in both binaries.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [int]$MaxBytes = 16384
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

function Get-RawBytes([string]$path) {
    # RAW on-disk length — NOT GetByteCount(ReadAllText), which strips a UTF-8 BOM and substitutes invalid bytes,
    # under-counting the true on-disk size the binary's raw-byte read actually sees (panel agy-A6).
    if (-not (Test-Path $path)) { return 0 }
    return (Get-Item -LiteralPath $path).Length
}

$seedPath   = Join-Path $RepoRoot 'seed/golden-header.md'
$growthPath = Join-Path $RepoRoot 'docs/agy-golden-header.growth.md'

# TEST PRESENCE AT THE CALL SITE. Get-RawBytes returns 0 for a missing path (:26) AND 0 for a
# present-but-empty one, so a caller handed 0 cannot tell them apart - the distinction is already
# destroyed by the time it returns. Changing its signature is worse: -1 or $null would flow into the
# arithmetic below, where `-gt 0` and the addition both silently accept a sentinel, and throwing would
# turn a WARN-only gate into a crashing one.
$seedMissing   = -not (Test-Path -LiteralPath $seedPath)
$growthMissing = -not (Test-Path -LiteralPath $growthPath)

$seedBytes   = Get-RawBytes $seedPath
$growthBytes = Get-RawBytes $growthPath

# THE SEED CASE IS A REAL FAIL-OPEN, NOT A REPORTING DEFECT. A missing seed silently measures 0, so
# `0 + <proposal> <= 16384` certifies a proposal of up to the FULL cap; the binary then combines the
# REAL seed with it, overflows, and silently drops GROWTH - the exact failure this gate exists to
# prevent. The gate does not merely report badly; it validates a falsified equation and returns green.
if ($seedMissing) {
    Write-Host "check-growth-budget: FAIL: the SEED is ABSENT at $seedPath - the combined budget cannot be checked at all. This is NOT an overflow: nothing was measured. Restore the seed, then re-run." -ForegroundColor Red
    exit 1
}
if ($seedBytes -eq 0) {
    Write-Host "check-growth-budget: FAIL: the SEED at $seedPath is present but EMPTY (0 bytes) - the combined budget cannot be checked meaningfully. This is NOT an overflow." -ForegroundColor Red
    exit 1
}

# THE SEED MUST STILL BE CHECKED AGAINST THE CAP BEFORE ANY EARLY RETURN. Panel R4 caught this as a
# FAIL-OPEN INTRODUCED BY 13c'S OWN FIX: the first draft of these two branches printed
# "SEED ${seedBytes}B <= ${MaxBytes}B" and exited 0 WITHOUT EVER TESTING THAT CLAIM. The original code
# had no such hole - with GROWTH absent, `$separator` is 0 and `$combined` is just `$seedBytes`, so `:39`
# still compared it to the cap. Adding an early return for the legitimate GROWTH-absent case silently
# deleted the only check that a seed OVER the cap on its own would ever fail, and printed a
# mathematically false sentence in green while doing it. A reporting fix that removes an assertion is not
# a reporting fix.
if ($seedBytes -gt $MaxBytes) {
    Write-Host "check-growth-budget: FAIL: SEED (${seedBytes}B) alone exceeds ${MaxBytes}B, before any GROWTH is added." -ForegroundColor Red
    exit 1
}

# For GROWTH, ABSENCE IS LEGITIMATE - a docs-only drain has nothing to publish - so this half is a
# reporting fix and stays exit 0. Safe to return here ONLY because the seed was just checked above.
if ($growthMissing) {
    Write-Host "check-growth-budget: OK - the GROWTH proposal is ABSENT at $growthPath (a docs-only drain publishes nothing). SEED ${seedBytes}B <= ${MaxBytes}B." -ForegroundColor Green
    exit 0
}
if ($growthBytes -eq 0) {
    Write-Host "check-growth-budget: OK - the GROWTH proposal at $growthPath is present but EMPTY (0 bytes). SEED ${seedBytes}B <= ${MaxBytes}B." -ForegroundColor Green
    exit 0
}
# The binary joins the regions as trim(SEED) + "\n\n" + trim(GROWTH) (GoldenHeader.Join), so the real injected
# size adds a 2-byte separator when BOTH regions are present (panel agy-A1). Counting raw bytes + the separator,
# WITHOUT subtracting the binary's trim + leading-comment strip, makes this a CONSERVATIVE upper bound: it errs
# toward warning slightly early, never toward missing a real overflow — the safe direction for a warn gate.
# THE `else { 0 }` IS CURRENTLY UNREACHABLE, and it is kept deliberately (capstone R3). 13c added two
# guards ABOVE this line - a zero seed exits 1 and a zero growth exits 0 - so by the time execution
# arrives here both values are strictly positive and the condition is always true. MEASURED: replacing
# the else with a nonsense value leaves the suite fully green, so no row can redden it.
# It is NOT simplified to `$separator = 2`: that would silently couple this arithmetic to those two
# guards, so removing or relaxing either one later would produce a wrong separator with nothing to catch
# it. A defensive branch with no oracle, documented as such rather than deleted or credited with cover.
$separator = if ($seedBytes -gt 0 -and $growthBytes -gt 0) { 2 } else { 0 }
$combined = $seedBytes + $separator + $growthBytes

if ($combined -gt $MaxBytes) {
    # THE SEPARATOR IS IN THE SUM, SO IT MUST BE IN THE SENTENCE (capstone R4). Printing
    # "SEED (10B) + GROWTH (10B) = 22B" is arithmetic the operator can see is wrong, and the natural
    # reading is that the gate has miscounted - which sends them checking the tool instead of the
    # proposal, exactly when a borderline overflow needs trimming.
    Write-Host "check-growth-budget: FAIL: SEED (${seedBytes}B) + ${separator}B separator + GROWTH (${growthBytes}B) = ${combined}B > ${MaxBytes}B — the binary would inject SEED-only and silently drop GROWTH. Trim the proposal." -ForegroundColor Red
    exit 1
}

# SAME OMISSION AS THE FAIL LINE ABOVE - the peer named only that one; this sibling had it too.
Write-Host "check-growth-budget: OK — SEED (${seedBytes}B) + ${separator}B separator + GROWTH (${growthBytes}B) = ${combined}B <= ${MaxBytes}B" -ForegroundColor Green
exit 0
