#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Assert the injected golden-header SEED is within its committed byte budget (token-economy gate,
  Hard-invariant #2 / decision 8). Dev/CI-time only. Test-Path-guarded: a missing SEED counts as 0 bytes.
.PARAMETER SeedPath
  Path to the SEED markdown. Defaults to the repo-root seed/golden-header.md.
.PARAMETER MaxBytes
  The budget. Default 7992 = 8 KiB minus ~200 B runtime-escalation-index headroom. THE single source of truth;
  a deliberate raise is a committed edit to this default.
#>
[CmdletBinding()]
param(
    [string]$SeedPath,
    [int]$MaxBytes = 7992
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $SeedPath) { $SeedPath = Join-Path $RepoRoot 'seed/golden-header.md' }

function Fail([string]$msg) {
    Write-Host "check-seed-budget: FAIL: $msg" -ForegroundColor Red
    exit 1
}

# F24: a missing SEED (fresh clone, never drained) is 0 bytes ≤ budget — never a crash.
$bytes = 0
if (Test-Path $SeedPath) {
    $bytes = [System.Text.Encoding]::UTF8.GetByteCount([System.IO.File]::ReadAllText($SeedPath))
}

if ($bytes -gt $MaxBytes) {
    Fail "injected SEED is ${bytes}B > ${MaxBytes}B — consolidate via 'just drain-knowledge' or bump SEED_MAX_BYTES (the -MaxBytes default in scripts/check-seed-budget.ps1) deliberately"
}

Write-Host "check-seed-budget: OK — SEED ${bytes}B <= ${MaxBytes}B" -ForegroundColor Green
exit 0
