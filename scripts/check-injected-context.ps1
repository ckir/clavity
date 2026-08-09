<#
.SYNOPSIS
  Audits every file this repository injects into a user's AI-agent context.
.DESCRIPTION
  Discovery is SUBTRACTIVE: walk the domain roots, subtract an explicit ignorelist. An additive
  role-matcher would be an allowlist of globs, which is the exact defect this gate exists to remove
  (see scripts/check-agy-discipline-skills.ps1:13 for the drift it caused there).
.PARAMETER RepoRoot
  Repository root. Defaults to the parent of this script's directory.
.PARAMETER WhatIf
  Read-only checker; accepted and ignored, for parity with the repo's other scripts.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$RepoRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }

# The six roots. Owner ruling 2026-08-08 (spec 6.1): all six, no product excluded.
$script:DomainRoots = @(
    'clavity-dotnet/plugin'
    'clavity-classic/plugin'
    'seed'
    'agy-autotrain'
    'ghidrust/plugin'
    'commonmemory'
)

function Get-InjectedContextFiles {
    param([string]$RepoRoot)
    # Replaced in Task 2. Returns nothing so the suite stays honest until then.
    @()
}

# DOT-SOURCE / EXECUTE SPLIT. The test suite dot-sources this file to reach the functions above, so the
# main body must NOT run in that case - otherwise every dot-source would walk the tree and set an exit
# code. `$MyInvocation.InvocationName` is '.' exactly when dot-sourced.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-InjectedContextCheck -RepoRoot $RepoRoot   # defined in Task 9
}
