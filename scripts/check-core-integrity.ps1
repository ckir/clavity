#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Assert every PROTECTED driver-owned file is byte-identical to its committed HEAD version after a drain (EXTEND
  model). The curator owns only the GROWTH proposal + docs side-artifacts; it must never touch the SEED, the four
  driver manuals, or the byte-pinned driver-cheatsheet.core.md. Hard drain gate: any modification fails the drain.
  (Byte-equality is strictly stronger than the old "[Core] lines survive" check — an unchanged file trivially
  preserves its **[Core]** lines and also blocks any other rewrite of a protected file.)
.PARAMETER RepoRoot
  Repo root (default: this script's parent's parent).
.PARAMETER Files
  Repo-relative protected paths. Default: SEED + the four manuals + the driver-cheatsheet core.
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
    # SINGLE SOURCE OF TRUTH (panel agy-R2-1): derive the protected set from drain-lib's Get-DrainProtectedPaths —
    # the SAME list drain-knowledge's step-6 revert loop iterates — so the gate and the revert can never check and
    # fix DIFFERENT files if the list ever changes. drain-lib.ps1 is parameter-less, so dot-sourcing it defines
    # functions only (no $Files/$RepoRoot clobber). Both scripts live in scripts/, so $PSScriptRoot resolves it.
    . (Join-Path $PSScriptRoot 'drain-lib.ps1')
    $Files = Get-DrainProtectedPaths
}

function Fail([string]$msg) {
    Write-Host "check-core-integrity: FAIL: $msg" -ForegroundColor Red
    exit 1
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "required tool 'git' not found on PATH" }

# Fail CLOSED if $RepoRoot is not a git work tree. The per-file `cat-file -e HEAD:<rel>` below returns the SAME
# non-zero (128) for "not a git repo" as for "file legitimately absent from HEAD", so without this guard a drain
# where git cannot run would `continue` past every file and exit 0 — a dangerous false-GREEN for a protected-files
# gate (it would report "all protected files unchanged" having verified nothing). `rev-parse --is-inside-work-tree`
# exits 0 inside a work tree and non-zero (128) outside, independent of any file, so it isolates the git-cannot-run
# case cleanly (execution finding: the Step-1 not-a-repo test vs this Step-3 script — the two 128s are ambiguous).
& git -C $RepoRoot rev-parse --is-inside-work-tree *> $null
if ($LASTEXITCODE -ne 0) { Fail "'$RepoRoot' is not a git repository (or git could not run there) — cannot confirm protected files are unchanged; failing closed" }

foreach ($rel in $Files) {
    # A file not in HEAD has no committed baseline to protect (new/uncommitted) — nothing to compare, skip.
    & git -C $RepoRoot cat-file -e "HEAD:$rel" 2>$null
    if ($LASTEXITCODE -ne 0) { continue }

    # `git diff --quiet HEAD -- <rel>` exits 0 when the working tree matches HEAD, 1 when it differs (including a
    # deletion). A different exit (>1) means git itself failed (not a repo, corrupt index) — fail closed.
    & git -C $RepoRoot diff --quiet HEAD -- $rel 2>$null
    $code = $LASTEXITCODE
    if ($code -eq 1) { Fail "a protected driver-owned file was modified by the drain (curator may never touch it): $rel" }
    if ($code -ne 0) { Fail "'git diff' could not evaluate $rel (exit $code) — cannot confirm it is unchanged; failing closed" }

    # ALSO check the INDEX vs HEAD (capstone R2-F4, "the index smuggle"). `git diff --quiet HEAD` compares the
    # WORKING TREE to HEAD, so a curator that stages an edit (`git add`) and then restores only the worktree
    # (`git restore --worktree`) leaves the malicious change in the INDEX, invisible to the worktree check — and a
    # later `git commit`/`git commit -a`/GUI commit would commit it. Compare index→HEAD too so a staged-but-not-
    # worktree edit is caught.
    & git -C $RepoRoot diff --cached --quiet HEAD -- $rel 2>$null
    $codeCached = $LASTEXITCODE
    if ($codeCached -eq 1) { Fail "a protected driver-owned file has a STAGED (index) modification the drain must never make (index smuggle): $rel" }
    if ($codeCached -ne 0) { Fail "'git diff --cached' could not evaluate $rel (exit $codeCached) — cannot confirm the index is unchanged; failing closed" }
}

Write-Host "check-core-integrity: OK — every protected driver-owned file is byte-identical to HEAD" -ForegroundColor Green
exit 0
