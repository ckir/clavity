#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Assert every committed `**[Core]**` line survives verbatim in the working tree for each guarded file (decision
  7 / F15). Dev-time gate. HEAD is the "before" oracle (git show HEAD:<file>); the working tree is "after".
.PARAMETER RepoRoot
  Repo root (default: this script's parent's parent).
.PARAMETER Files
  Repo-relative paths to guard. Default: the SEED + the four canonical manuals.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string[]]$Files
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $Files) {
    $Files = @(
        'seed/golden-header.md'
        'clavity-dotnet/plugin/knowledge/agy-assumptions.md'
        'clavity-dotnet/plugin/knowledge/agy-capabilities.md'
        'clavity-classic/plugin/knowledge/agy-assumptions.md'
        'clavity-classic/plugin/knowledge/agy-capabilities.md'
    )
}

function Fail([string]$msg) {
    Write-Host "check-core-integrity: FAIL: $msg" -ForegroundColor Red
    exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "required tool 'git' not found on PATH" }

# Only lines beginning with the literal **[Core]** marker are guarded (leading whitespace tolerated).
function Get-CoreLines([string[]]$lines) {
    if ($null -eq $lines) { return @() }
    return ,@($lines | Where-Object { $_ -match '^\s*\*\*\[Core\]\*\*' })
}

foreach ($rel in $Files) {
    # "before" = committed HEAD version; a file not in HEAD has no baseline to protect (returns non-zero → skip).
    $headText = & git -C $RepoRoot show "HEAD:$rel" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }              # new/uncommitted file: nothing committed to protect.
    $headCore = Get-CoreLines @($headText)
    $abs = Join-Path $RepoRoot $rel
    if (-not (Test-Path $abs)) {
        if ($headCore.Count -gt 0) { Fail "a guarded file with committed **[Core]** lines was deleted: $rel" }
        continue
    }
    $nowCore = Get-CoreLines (Get-Content $abs)
    $headSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$headCore)
    $nowSet  = [System.Collections.Generic.HashSet[string]]::new([string[]]$nowCore)

    # SET-EQUALITY, not just superset (agy plan-panel R3 BS2). [Core] is maintainer-owned (F18): the curator may
    # neither ALTER/REMOVE an existing [Core] line NOR ADD a new one. Rejecting additions closes the prompt-
    # injection hole where a hostile observation makes the curator write `**[Core]** <malicious>` into the SEED.
    foreach ($line in $headCore) {
        if (-not $nowSet.Contains($line)) {
            Fail "a committed **[Core]** line in $rel was altered or removed (the curator may never touch [Core]):`n  $line"
        }
    }
    foreach ($line in $nowCore) {
        if (-not $headSet.Contains($line)) {
            Fail "a NEW **[Core]** line appeared in $rel — [Core] is maintainer-owned; the curator may never ADD one:`n  $line"
        }
    }
}

Write-Host "check-core-integrity: OK — every committed **[Core]** line survives verbatim" -ForegroundColor Green
exit 0
