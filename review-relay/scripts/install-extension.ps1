#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Install or update the bundled AiSaveDev capture extension into a fixed folder for "Load unpacked".
.DESCRIPTION
  Spec: docs/superpowers/specs/2026-09-29-aisavedev-shipping-design.md, section 4.
  Mirrors ../extension/aisavedev into -Destination (default %LOCALAPPDATA%\review-relay\aisavedev),
  staged in <Destination>.new and swapped into place, so the folder Chrome points at never moves and
  never keeps stale files. It only ever writes into folders that are absent, empty, or carry its marker.
  Exit codes: 0 success, 1 refused or failed (the previous install is left in place).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Destination
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MarkerName = '.review-relay-extension'
function Stop-Install([string]$Message) { Write-Host "install-extension: $Message" -ForegroundColor Red; exit 1 }

if (-not $Destination) {
    if (-not $env:LOCALAPPDATA) { Stop-Install 'LOCALAPPDATA is not set; pass -Destination <folder>' }
    $Destination = Join-Path $env:LOCALAPPDATA 'review-relay' 'aisavedev'
}
$Destination = [IO.Path]::GetFullPath($Destination).TrimEnd([char]'\', [char]'/')
# A drive root trims to "C:" (drive-RELATIVE) or "" - refuse it explicitly, never by accident.
if (-not $Destination -or $Destination -eq [IO.Path]::GetPathRoot("$Destination\").TrimEnd([char]'\', [char]'/')) {
    Stop-Install "-Destination must be a folder below a drive root; nothing was changed"
}
$newDir = "$Destination.new"
$oldDir = "$Destination.old"
$source = Join-Path $PSScriptRoot '..' 'extension' 'aisavedev'
$pluginJson = Join-Path $PSScriptRoot '..' 'plugin.json'

# Absent, an empty directory, or a directory carrying our marker: the only folders this script may touch.
function Test-OwnedOrFree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    if (Test-Path -LiteralPath (Join-Path $Path $MarkerName) -PathType Leaf) { return $true }
    return -not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)
}

# The manifest in $Dir must parse, be AiSaveDev's, and carry plugin.json's version.
function Assert-Manifest([string]$Dir, [string]$Expected) {
    $m = Join-Path $Dir 'manifest.json'
    $obj = try { Get-Content -LiteralPath $m -Raw | ConvertFrom-Json } catch { Stop-Install "cannot read $m : $($_.Exception.Message)" }
    if ($obj.name -ne 'AiSaveDev') { Stop-Install "$m is not AiSaveDev's manifest (name '$($obj.name)')" }
    if ($obj.version -ne $Expected) { Stop-Install "$m has version $($obj.version) but plugin.json has $Expected; nothing was changed" }
}

function Get-InstalledVersion([string]$Dir) {
    $m = Join-Path $Dir 'manifest.json'
    if (-not (Test-Path -LiteralPath $m)) { return $null }
    try { (Get-Content -LiteralPath $m -Raw | ConvertFrom-Json).version } catch { 'unknown' }
}

$expected = try { (Get-Content -LiteralPath $pluginJson -Raw | ConvertFrom-Json).version } catch { Stop-Install "cannot read $pluginJson : $($_.Exception.Message)" }
Assert-Manifest $source $expected

foreach ($p in @($Destination, $newDir, $oldDir)) {
    if (-not (Test-OwnedOrFree $p)) { Stop-Install "$p is not an AiSaveDev install folder; nothing was changed" }
}

# A run that died between the two renames leaves the good install in .old and no destination.
if (-not (Test-Path -LiteralPath $Destination) -and (Test-Path -LiteralPath (Join-Path $oldDir $MarkerName))) {
    if ($PSCmdlet.ShouldProcess($oldDir, "restore the previous install to $Destination")) {
        Move-Item -LiteralPath $oldDir -Destination $Destination
        Write-Host "install-extension: restored the previous install from $oldDir"
    }
}

$previous = Get-InstalledVersion $Destination

if (-not $PSCmdlet.ShouldProcess($Destination, "install AiSaveDev $expected (stage it in $newDir with its marker file, then swap it in)")) { exit 0 }

if (Test-Path -LiteralPath $newDir) { Remove-Item -LiteralPath $newDir -Recurse -Force }
New-Item -ItemType Directory -Path $newDir | Out-Null
# The marker goes in FIRST, so a run that dies mid-copy leaves a .new the next run may clear.
Set-Content -LiteralPath (Join-Path $newDir $MarkerName) -Value "Managed by review-relay's install-extension.ps1. Do not put your own files here."
Copy-Item -Path (Join-Path $source '*') -Destination $newDir -Recurse -Force
Assert-Manifest $newDir $expected

# A leftover .old (an earlier run whose final delete failed) must go BEFORE the swap: Move-Item onto an
# existing folder would nest the install INSIDE it, and a failed second move would then "restore" that nest.
if (Test-Path -LiteralPath $oldDir) {
    try { Remove-Item -LiteralPath $oldDir -Recurse -Force }
    catch { Stop-Install "could not clear the leftover $oldDir ($($_.Exception.Message)); the current install is unchanged." }
}
if (Test-Path -LiteralPath $Destination) {
    try { Move-Item -LiteralPath $Destination -Destination $oldDir }
    catch { Stop-Install "could not move the current install aside ($($_.Exception.Message)); it is unchanged. Close anything using $Destination and run again." }
}
try { Move-Item -LiteralPath $newDir -Destination $Destination }
catch {
    $why = $_.Exception.Message
    if (Test-Path -LiteralPath $oldDir) {
        try { Move-Item -LiteralPath $oldDir -Destination $Destination; Stop-Install "could not move the new files into place ($why); the previous install was restored." }
        catch { Stop-Install "could not move the new files into place ($why) AND could not restore $oldDir. Rename $oldDir back to $Destination by hand." }
    }
    Stop-Install "could not move the new files into place ($why)."
}
if (Test-Path -LiteralPath $oldDir) {
    try { Remove-Item -LiteralPath $oldDir -Recurse -Force }
    catch { Write-Warning "install-extension: the install succeeded, but $oldDir was left behind ($($_.Exception.Message)); the next run removes it." }
}

$what = if ($previous) { "(replaced $previous)" } else { '(first install)' }
Write-Host "installed AiSaveDev $expected at $Destination $what"
if ($previous) {
    Write-Host "Next: open chrome://extensions (or edge://extensions) and click Reload on AiSaveDev."
} else {
    Write-Host "Next, once: open chrome://extensions (or edge://extensions), turn on Developer mode, click Load unpacked, and pick $Destination"
}
