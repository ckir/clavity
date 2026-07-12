#!/usr/bin/env pwsh
[CmdletBinding()]
param([switch]$BaselineOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib' 'release-lib.ps1')

$baseline = Get-BaselineSha
if ($BaselineOnly) { return $baseline }
# (full emit added in Task 6)
