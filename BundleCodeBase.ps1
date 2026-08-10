<#
.SYNOPSIS
    Bundle this repository into a single text file for upload to the agy peer.

.DESCRIPTION
    Wraps `dir-to-text`, which writes `<directory-name>.txt` into the output directory - so from the
    repo root the artifact is always `clavity.txt` (already gitignored at .gitignore:12).

    `--use-gitignore` honours every .gitignore in the tree, including the per-product ones, so anything
    already ignored needs no -e flag here. MEASURED 2026-08-10: that alone covers /target, /dist,
    publish/, .venv/, __pycache__/, .clavity/, .worktrees/, .agent/, .serena/, /Microsoft/, *.log,
    testResults.xml and the bulk of docs/superpowers/. The -e flags below name ONLY what gitignore does
    not.

.PARAMETER WhatIf
    Report what would be removed and written without touching anything.

.EXAMPLE
    .\BundleCodeBase.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'

$Root = $PSScriptRoot
$Out  = Join-Path $Root 'clavity.txt'

# Excludes gitignore does NOT already handle. Each one is here by measurement, not by habit:
#   .git         - never appears in a .gitignore, and dir-to-text walks the filesystem, not the index.
#   *.lock       - three TRACKED lockfiles (clavity-classic/Cargo.lock, ghidrust/Cargo.lock,
#                  clavity-classic/agy-mcp-bridge/uv.lock). Generated, and pure noise to a reader.
#   *.bin        - five TRACKED binary wire-capture oracles under
#                  clavity-dotnet/tests/Clavity.Ls.Tests/TestData/. Raw protobuf bytes; .gitattributes
#                  marks them binary. Bundling them as text is garbage.
#   .ruff_cache  - a root-level tool cache that is NOT gitignored (unlike .pytest_cache/).
#   scratchpad   - root-level scratch dir, NOT gitignored.
#
# Deliberately NOT excluded, and each was in the pre-2026-08-10 version of this script:
#   docs         - dropped as an exclude. docs/superpowers/* (the bulky in-flight specs and plans) is
#                  already gitignored, so what survives is the curated public set - the runbooks and the
#                  hosting playbook - which is exactly the context that makes this bundle worth sending.
#                  Re-add `-e docs` if you want code only.
#   .wrangler,
#   pnpm-lock.yaml,
#   Cargo.lock   - carried over from another project. The first two match nothing in this repository;
#                  the third is subsumed by *.lock.
$excludes = @(
    '-e', '.git'
    '-e', '*.lock'
    '-e', '*.bin'
    '-e', '.ruff_cache'
    '-e', 'scratchpad'
)

if (Test-Path -LiteralPath $Out) {
    if ($PSCmdlet.ShouldProcess($Out, 'Remove previous bundle')) {
        Remove-Item -LiteralPath $Out -Force
    }
}

if (-not $PSCmdlet.ShouldProcess($Root, 'Bundle repository to clavity.txt')) { return }

# Run from the repo root: dir-to-text derives the artifact name from the directory it is given, so the
# output name is only 'clavity.txt' when the cwd is this repository. The old version inherited whatever
# cwd the caller happened to be in.
Push-Location -LiteralPath $Root
try {
    & dir-to-text --use-gitignore @excludes .
    if ($LASTEXITCODE -ne 0) { throw "dir-to-text exited $LASTEXITCODE" }
}
finally {
    Pop-Location
}

if (Test-Path -LiteralPath $Out) {
    $mb = (Get-Item -LiteralPath $Out).Length / 1MB
    Write-Host ("Bundled -> {0} ({1:N2} MB)" -f $Out, $mb)
} else {
    throw "dir-to-text reported success but $Out was not created."
}
