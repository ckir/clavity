<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

#requires -Version 5.1
# Fail (exit 1) if register-plugin-hash.iss is stale vs the current register-plugin.ps1 (drift guard).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ps1  = Join-Path (Join-Path (Join-Path $root 'installer') '_shared') 'register-plugin.ps1'
$iss  = Join-Path (Join-Path (Join-Path $root 'installer') '_shared') 'register-plugin-hash.iss'
# Hash the CRLF form of the file on every OS: .gitattributes pins register-plugin.ps1 to eol=crlf, so the
# bytes a Windows checkout (and the shipped installer) hold are CRLF, while a Linux working tree holds LF.
$raw  = [IO.File]::ReadAllBytes($ps1)
$norm = ([Text.Encoding]::UTF8.GetString($raw)) -replace "`r`n", "`n" -replace "`n", "`r`n"
$sha  = [Security.Cryptography.SHA256]::Create()
$hash = ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($norm))) -replace '-', '').ToUpperInvariant()
$text = Get-Content -Raw -Path $iss
if ($text -notmatch [regex]::Escape("`"$hash`"")) {
    Write-Error "register-plugin-hash.iss is STALE. Run: just sync-register-hash"
    exit 1
}
Write-Host "register-plugin-hash.iss in sync ($hash)"
exit 0
