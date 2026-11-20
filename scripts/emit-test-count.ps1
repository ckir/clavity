<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Extract one suite's passed/skipped counts from its runner output, validate them, and append
# <suite>_passed=<P> / <suite>_skipped=<S> to the file in $env:GITHUB_OUTPUT. Used by the emitter steps of the
# called CI workflows; the publish job reads those outputs. Throws (non-zero exit) on any unrecognised or
# failing summary, so a runner format change turns the step red instead of publishing a wrong number.
#   scripts/emit-test-count.ps1 -Suite <id> -Path <runner output or junit xml>
#   scripts/emit-test-count.ps1 -Suite pester_install -Passed <n> -Skipped <n>   (the step holds Pester's result object)
param(
    [Parameter(Mandatory)][string]$Suite,
    [string]$Path,
    [int]$Passed,
    [int]$Skipped
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-sourced through $PSScriptRoot: the steps run from other working directories.
. (Join-Path $PSScriptRoot 'lib' 'test-count-lib.ps1')

if ($Suite -cnotin $script:TestCountSuiteIds) {
    throw "test-count: ${Suite}: unknown suite (expected one of: $($script:TestCountSuiteIds -join ', '))"
}
if (-not $env:GITHUB_OUTPUT) { throw "test-count: ${Suite}: GITHUB_OUTPUT is not set" }

$direct = $PSBoundParameters.ContainsKey('Passed') -or $PSBoundParameters.ContainsKey('Skipped')
if ($Suite -eq 'pester_install') {
    if (-not ($PSBoundParameters.ContainsKey('Passed') -and $PSBoundParameters.ContainsKey('Skipped'))) {
        throw "test-count: ${Suite}: needs both -Passed and -Skipped (0 is a valid -Skipped)"
    }
    if ($PSBoundParameters.ContainsKey('Path')) { throw "test-count: ${Suite}: takes -Passed/-Skipped, not -Path" }
    $result = [pscustomobject]@{ Passed = $Passed; Skipped = $Skipped }
} else {
    if ($direct) { throw "test-count: ${Suite}: takes -Path, not -Passed/-Skipped" }
    if (-not $Path) { throw "test-count: ${Suite}: needs -Path" }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "test-count: ${Suite}: runner output not found: $Path" }
    $result = switch ($Suite) {
        'dotnet_ls'          { Get-DotnetProjectCounts (Get-Content -LiteralPath $Path -Raw) 'Clavity.Ls.Tests' }
        'dotnet_integration' { Get-DotnetProjectCounts (Get-Content -LiteralPath $Path -Raw) 'Clavity.Integration.Tests' }
        'rust'               { Get-CargoCounts (Get-Content -LiteralPath $Path -Raw) }
        'python_bridge'      { Get-PytestCounts $Path @('test_agy_bus', 'test_agy_tmux', 'tests.test_mcp_wiring', 'tests.test_secret_scrub') }
        'pester_scripts'     { Get-PesterRunnerCounts (Get-Content -LiteralPath $Path -Raw) }
        'bash_hooks'         { Get-BashHookCounts (Get-Content -LiteralPath $Path -Raw) }
        'node_relay'         { Get-NodeTapCounts (Get-Content -LiteralPath $Path -Raw) }
        'site_checks'        { Get-UnittestCounts (Get-Content -LiteralPath $Path -Raw) }
    }
}

if ($result.Passed -lt 1 -or $result.Passed -gt 1000000) { throw "test-count: ${Suite}: passed $($result.Passed) is outside 1..1000000" }
if ($result.Skipped -lt 0 -or $result.Skipped -gt 1000000) { throw "test-count: ${Suite}: skipped $($result.Skipped) is outside 0..1000000" }

[IO.File]::AppendAllText($env:GITHUB_OUTPUT, "${Suite}_passed=$($result.Passed)`n${Suite}_skipped=$($result.Skipped)`n", [Text.UTF8Encoding]::new($false))
"test-count $Suite passed=$($result.Passed) skipped=$($result.Skipped)"
