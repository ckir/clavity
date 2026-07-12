#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Write every version source for one clavity member (or one ghidrust channel) to <Version>, then
  self-verify with check-versions.ps1. Idempotent: re-running with the same version is a no-op.

.PARAMETER Member
  dotnet | classic | ghidrust | agy-autotrain | commonmemory

.PARAMETER Version
  Target semver, e.g. 0.1.3

.PARAMETER Channel
  ghidrust only: 'binary' or 'plugin' (required for ghidrust; forbidden for other members).
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet('dotnet', 'classic', 'ghidrust', 'agy-autotrain', 'commonmemory')]
    [string]$Member,

    [Parameter(Mandatory, Position = 1)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    [ValidateSet('binary', 'plugin')]
    [string]$Channel
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Die([string]$m) { Write-Host "bump-version: $m" -ForegroundColor Red; exit 1 }

function Set-IssVersion([string]$relPath) {
    $p = Join-Path $RepoRoot $relPath
    $c = Get-Content -Raw $p
    # -cnotmatch (case-sensitive) mirrors the case-sensitive [regex]::Replace below, so the guard fires
    # exactly when the replace would no-op — closing the silent-no-op + false-success-line gap.
    if ($c -cnotmatch '#define AppVersion "[^"]+"') { Die "no '#define AppVersion' line in $relPath" }
    $new = [regex]::Replace($c, '(#define AppVersion ")[^"]+(")', "`${1}$Version`${2}")
    if ($new -ne $c) { Set-Content -Path $p -Value $new -NoNewline }
    Write-Host "  iss  $relPath -> $Version"
}

function Set-JsonVersion([string]$relPath) {
    $p = Join-Path $RepoRoot $relPath
    # RAW first-match replace preserves EOL + trailing-newline byte-for-byte. The version files are LF
    # with core.autocrlf=true; a Get-Content/Set-Content line-rejoin would flip them to CRLF on every
    # bump (churn + CRLF-parity test breakage). Targets the first (top-level) "version" in the file.
    $c = Get-Content -Raw $p
    $rx = [regex]'(?m)^(\s*"version"\s*:\s*")[^"]+(")'
    if (-not $rx.IsMatch($c)) { Die "no top-level 'version' line in $relPath" }
    $new = $rx.Replace($c, "`${1}$Version`${2}", 1)
    if ($new -ne $c) { Set-Content -Path $p -Value $new -NoNewline }
    Write-Host "  json $relPath -> $Version"
}

function Set-PyprojectVersion([string]$relPath) {
    $p = Join-Path $RepoRoot $relPath
    # RAW first-match replace preserves EOL (see Set-JsonVersion). [project] is the first table and its
    # version is the first line-anchored `version = "..."`; the writer self-verifies via check-versions
    # (which section-scopes the read), so a wrong-line write would fail the post-bump gate.
    $c = Get-Content -Raw $p
    $rx = [regex]'(?m)^(version\s*=\s*")[^"]+(")'
    if (-not $rx.IsMatch($c)) { Die "no [project] version line in $relPath" }
    $new = $rx.Replace($c, "`${1}$Version`${2}", 1)
    if ($new -ne $c) { Set-Content -Path $p -Value $new -NoNewline }
    Write-Host "  toml $relPath [project] -> $Version"
}

function Invoke-CargoSetVersion([string]$crateDirRel, [switch]$Workspace) {
    if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { Die "cargo not found on PATH" }
    if (-not (cargo set-version --help 2>$null)) { Die "cargo-edit not installed (cargo install cargo-edit --locked)" }
    Push-Location (Join-Path $RepoRoot $crateDirRel)
    try {
        # A VIRTUAL workspace root (ghidrust/Cargo.toml has no [package]) has no "current package",
        # so `cargo set-version` needs --workspace to bump every member; a single-package manifest
        # (clavity-classic) has a current package and uses the default (no --workspace).
        if ($Workspace) { & cargo set-version --workspace $Version }
        else            { & cargo set-version $Version }
        if ($LASTEXITCODE -ne 0) { Die "cargo set-version failed in $crateDirRel" }
    } finally { Pop-Location }
    Write-Host "  cargo set-version $Version ($crateDirRel$(if ($Workspace) { ' --workspace' } else { '' })) [Cargo.toml + Cargo.lock]"
}

function Invoke-UvLock([string]$bridgeDirRel) {
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) { Die "uv not found on PATH" }
    Push-Location (Join-Path $RepoRoot $bridgeDirRel)
    try { & uv lock; if ($LASTEXITCODE -ne 0) { Die "uv lock failed in $bridgeDirRel" } }
    finally { Pop-Location }
    Write-Host "  uv lock ($bridgeDirRel) [uv.lock]"
}

if ($Member -eq 'ghidrust') {
    if (-not $Channel) { Die "ghidrust requires -Channel binary|plugin" }
} elseif ($Channel) {
    Die "-Channel is only valid for ghidrust"
}

Write-Host "bump-version: $Member$(if ($Channel) { " ($Channel)" }) -> $Version"

switch ($Member) {
    'dotnet' {
        Set-IssVersion  'clavity-dotnet/installer/clavity-dotnet.iss'
        Set-JsonVersion 'clavity-dotnet/plugin/plugin.json'
        Set-JsonVersion 'clavity-dotnet/plugin/.claude-plugin/plugin.json'
    }
    'classic' {
        Invoke-CargoSetVersion 'clavity-classic'
        Set-PyprojectVersion   'clavity-classic/agy-mcp-bridge/pyproject.toml'
        Invoke-UvLock          'clavity-classic/agy-mcp-bridge'
        Set-IssVersion  'clavity-classic/installer/clavity-classic.iss'
        Set-JsonVersion 'clavity-classic/plugin/plugin.json'
        Set-JsonVersion 'clavity-classic/plugin/.claude-plugin/plugin.json'
    }
    'agy-autotrain' {
        Set-IssVersion  'agy-autotrain/installer/agy-autotrain.iss'
        Set-JsonVersion 'agy-autotrain/plugin.json'
        Set-JsonVersion 'agy-autotrain/.claude-plugin/plugin.json'
    }
    'commonmemory' {
        Set-IssVersion  'commonmemory/installer/commonmemory.iss'
        Set-JsonVersion 'commonmemory/plugin.json'
        Set-JsonVersion 'commonmemory/.claude-plugin/plugin.json'
    }
    'ghidrust' {
        if ($Channel -eq 'binary') {
            Invoke-CargoSetVersion 'ghidrust' -Workspace   # virtual workspace root: --workspace bumps all 3 crates + Cargo.lock
            Set-IssVersion 'ghidrust/installer/ghidrust.iss'
        } else {
            Set-JsonVersion 'ghidrust/plugin/plugin.json'
            Set-JsonVersion 'ghidrust/plugin/.claude-plugin/plugin.json'
        }
    }
}

Write-Host "bump-version: self-verifying with check-versions.ps1 ..."
& (Join-Path $PSScriptRoot 'check-versions.ps1') $Member
if ($LASTEXITCODE -ne 0) { Die "post-bump check-versions FAILED — sources not consistent" }
Write-Host "bump-version: done ($Member -> $Version)" -ForegroundColor Green
