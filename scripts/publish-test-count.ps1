<#
 Copyright (c) 2026 Costas Kirgoussios

 This software is licensed under the PolyForm Noncommercial License 1.0.0.
 You may obtain a copy of the License at:
 https://polyformproject.org/licenses/noncommercial/1.0.0/
#>

# Render the README "tests" badge files (endpoint.json, ledger.json, README.md) into a checkout of the `badges` branch.
# The nine suites' counts come from TC_<ID>_PASSED / TC_<ID>_SKIPPED in the environment; every value is validated
# before it is used. A badges tree that already holds a ledger must carry a valid one whose commit is an ancestor of
# (or equal to) -Commit in the -MainDir checkout, so a re-run of an older workflow can never move the figure backwards.
# Nothing is written unless every check passed. Appends changed=true|false to $env:GITHUB_OUTPUT (false when all three
# files are byte-identical to what was there).
#   scripts/publish-test-count.ps1 -BadgesDir <dir> -MainDir <dir> -Commit <sha> -RunId <id> -RunUrl <url> -Date <yyyy-MM-dd> -Repo <owner/name>
param(
    [Parameter(Mandatory)][string]$BadgesDir,
    [Parameter(Mandatory)][string]$MainDir,
    [Parameter(Mandatory)][string]$Commit,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$RunUrl,
    [Parameter(Mandatory)][string]$Date,
    [Parameter(Mandatory)][string]$Repo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dot-sourced through $PSScriptRoot: the publish job calls main/scripts/... from another working directory.
. (Join-Path $PSScriptRoot 'lib' 'test-count-lib.ps1')

if (-not $env:GITHUB_OUTPUT) { throw 'test-count: GITHUB_OUTPUT is not set' }
if (-not (Test-Path -LiteralPath $MainDir -PathType Container)) { throw "test-count: -MainDir is not a directory: $MainDir" }

# Validate everything first; none of this touches the badges tree.
Assert-TestCountPublishInputs $Commit $RunId $RunUrl $Date $Repo
$counts = Read-TestCountEnv
$files = New-TestCountFiles $counts $Commit $RunId $RunUrl $Date $Repo
Test-EndpointJson $files['endpoint.json']   # the schema check the spec puts before the write

$utf8 = [Text.UTF8Encoding]::new($false)
$ledgerPath = Join-Path $BadgesDir 'ledger.json'
$existing = @()
if (Test-Path -LiteralPath $BadgesDir -PathType Container) {
    $existing = @(Get-ChildItem -LiteralPath $BadgesDir -Force | Where-Object { $_.Name -cne '.git' })
}

if ($existing.Count -gt 0) {
    # Not the first publish: the ledger must be there, valid, and an ancestor of what we are about to publish.
    if (-not (Test-Path -LiteralPath $ledgerPath -PathType Leaf)) { throw "test-count: ledger: $BadgesDir holds files but no ledger.json" }
    $old = (Test-TestCountLedger ([IO.File]::ReadAllText($ledgerPath))).commit
    # $old and $Commit are 40 lowercase hex by now; the `--` is belt and braces so neither can ever read as an option.
    $git = & git -C $MainDir merge-base --is-ancestor -- $old $Commit 2>&1
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        if ($code -ne 1) { Write-Warning "test-count: git merge-base exited ${code}: $($git -join ' ')" }
        throw "test-count: refusing to publish ${Commit}: not a descendant of $old"
    }
}

if (-not (Test-Path -LiteralPath $BadgesDir -PathType Container)) { $null = New-Item -ItemType Directory -Path $BadgesDir -Force }

$changed = $false
foreach ($name in $files.Keys) {
    $path = Join-Path $BadgesDir $name
    $bytes = $utf8.GetBytes($files[$name])
    $same = (Test-Path -LiteralPath $path -PathType Leaf) -and [System.Linq.Enumerable]::SequenceEqual([byte[]][IO.File]::ReadAllBytes($path), [byte[]]$bytes)
    if (-not $same) {
        [IO.File]::WriteAllBytes($path, $bytes)
        $changed = $true
    }
}

$flag = if ($changed) { 'true' } else { 'false' }
[IO.File]::AppendAllText($env:GITHUB_OUTPUT, "changed=$flag`n", $utf8)
"test-count publish $Commit changed=$flag"
