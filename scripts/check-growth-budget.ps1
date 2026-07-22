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

$seedBytes   = Get-RawBytes (Join-Path $RepoRoot 'seed/golden-header.md')
$growthBytes = Get-RawBytes (Join-Path $RepoRoot 'docs/agy-golden-header.growth.md')
# The binary joins the regions as trim(SEED) + "\n\n" + trim(GROWTH) (GoldenHeader.Join), so the real injected
# size adds a 2-byte separator when BOTH regions are present (panel agy-A1). Counting raw bytes + the separator,
# WITHOUT subtracting the binary's trim + leading-comment strip, makes this a CONSERVATIVE upper bound: it errs
# toward warning slightly early, never toward missing a real overflow — the safe direction for a warn gate.
$separator = if ($seedBytes -gt 0 -and $growthBytes -gt 0) { 2 } else { 0 }
$combined = $seedBytes + $separator + $growthBytes

if ($combined -gt $MaxBytes) {
    Write-Host "check-growth-budget: FAIL: SEED (${seedBytes}B) + GROWTH (${growthBytes}B) = ${combined}B > ${MaxBytes}B — the binary would inject SEED-only and silently drop GROWTH. Trim the proposal." -ForegroundColor Red
    exit 1
}

Write-Host "check-growth-budget: OK — SEED (${seedBytes}B) + GROWTH (${growthBytes}B) = ${combined}B <= ${MaxBytes}B" -ForegroundColor Green
exit 0
