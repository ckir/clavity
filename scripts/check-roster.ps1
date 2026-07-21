#!/usr/bin/env pwsh
[CmdletBinding()]
param([string]$MembersJsonPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'lib' 'release-lib.ps1')
if (-not $MembersJsonPath) { $MembersJsonPath = Join-Path $RepoRoot 'build/members.json' }
try {
    Assert-RosterMatchesMembers -MembersJsonPath $MembersJsonPath
    # Second, independent gate: the shared-path map vs what the members' installers actually reference.
    Assert-SharedMapHealthy -RepoRoot $RepoRoot
    Write-Host "check-roster: OK — release roster == build/members.json member set; shared-path map matches the installers." -ForegroundColor Green
    exit 0
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
