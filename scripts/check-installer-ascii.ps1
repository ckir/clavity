#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Assert every .ps1 in the Windows PowerShell 5.1 domain is pure ASCII.

  WHY: installer/_shared/register-plugin.ps1 runs on an END-USER Windows box, where only Windows
  PowerShell 5.1 is guaranteed. 5.1 decodes a BOM-less .ps1 as ANSI/CP1252, so a stray em-dash or
  arrow is read as mojibake. Sometimes that kills the parser; worse, sometimes it merely corrupts a
  string literal at RUNTIME and ships silently.

  Why ASCII rather than "add a UTF-8 BOM": a BOM is invisible state that any editor, tool, or
  copy-paste can drop, and the failure it prevents reappears silently. A byte gate cannot be
  defeated by editor config. Concretely, register-plugin.ps1 is SHA-256 hash-pinned
  (check-register-hash-synced.ps1), so adding a BOM there would break the uninstaller tamper check.

  Dev/CI-time only. This script itself lives in the pwsh 7 dev domain, but is deliberately kept
  ASCII too so it stays valid if it is ever run by the engine it polices.
.PARAMETER RepoRoot
  Repo root. Defaults to the parent of this script's directory.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

# THE 5.1 domain. Anything added here must hold on a stock Windows box with no pwsh 7.
$installerDir = Join-Path $RepoRoot 'installer'
$targets = @()
if (Test-Path $installerDir) {
    $targets += @(Get-ChildItem -Path $installerDir -Recurse -Filter *.ps1 -File)
}
$registerTests = Join-Path $RepoRoot 'scripts/tests/register-plugin.Tests.ps1'
if (Test-Path $registerTests) { $targets += @(Get-Item $registerTests) }

function Fail([string]$msg) {
    Write-Host "check-installer-ascii: FAIL: $msg" -ForegroundColor Red
    exit 1
}

if ($targets.Count -eq 0) {
    # A silent zero-file pass is a false green: the domain is never legitimately empty.
    Fail "found no .ps1 in the 5.1 domain - expected at least installer/_shared/register-plugin.ps1 (wrong -RepoRoot?)"
}

$bad = @()
foreach ($f in $targets) {
    $offenders = @([System.IO.File]::ReadAllBytes($f.FullName) | Where-Object { $_ -gt 0x7F })
    if ($offenders.Count -gt 0) {
        $rel = $f.FullName.Substring($RepoRoot.Length).TrimStart('\', '/')
        $bad += "  $rel - $($offenders.Count) non-ASCII byte(s)"
    }
}

if ($bad.Count -gt 0) {
    Fail ("non-ASCII in the Windows PowerShell 5.1 domain; 5.1 reads these as CP1252 and will mangle" +
          " them on an end-user box:`n" + ($bad -join "`n"))
}

Write-Host "check-installer-ascii: OK - $($targets.Count) file(s) in the 5.1 domain are pure ASCII" -ForegroundColor Green
exit 0
