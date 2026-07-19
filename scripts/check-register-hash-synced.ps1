#requires -Version 5.1
# Fail (exit 1) if register-plugin-hash.iss is stale vs the current register-plugin.ps1 (drift guard).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$ps1  = Join-Path $root 'installer\_shared\register-plugin.ps1'
$iss  = Join-Path $root 'installer\_shared\register-plugin-hash.iss'
$hash = (Get-FileHash -Algorithm SHA256 -Path $ps1).Hash.ToUpperInvariant()
$text = Get-Content -Raw -Path $iss
if ($text -notmatch [regex]::Escape("`"$hash`"")) {
    Write-Error "register-plugin-hash.iss is STALE. Run: just sync-register-hash"
    exit 1
}
Write-Host "register-plugin-hash.iss in sync ($hash)"
exit 0
