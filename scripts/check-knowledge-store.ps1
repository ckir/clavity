#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Guard the agy-driving knowledge STORE (tier 2): no rule file may be DELETED, none may be unreachable
  from the index, and the corpus stays LF + pure ASCII.

.DESCRIPTION
  The store is tier 2 of the knowledge tiering - unbounded, never injected, version-controlled. The
  injected GROWTH region is a bounded SELECTED PROJECTION of it. A rule absent from GROWTH is not gone;
  it is not currently projected. Preservation is therefore a property of THE STORE PLUS GIT, not of the
  store alone: consolidation edits content freely and git keeps what it replaced.

  WHY DELETION IS THE CHECK THAT MATTERS. A panel round established that pure reachability checking is
  defeated by COORDINATED DELETION - remove a rule file AND its index pointer together and every
  topological check still passes: `mlc` sees no dangling pointer, and an orphan sweep no longer
  enumerates the file. Only a BASELINE can see it, because the file existed at the baseline and does not
  now. That is what git supplies and what the memory-index pattern this design was ported from does NOT
  have (measured: that directory is not a git repository at all).

  DIVISION OF LABOUR - this script deliberately does NOT check links. `mlc` already resolves the store's
  markdown links (`just check-links`), exits 1 on a dangling one, and is configured with a documented
  baseline of 2 pre-existing errors where "any third error is a genuine regression". The store uses
  STANDARD markdown links precisely so that gate can see it: mlc CANNOT resolve [[wikilinks]] (measured
  2026-08-27 against a fixture), so a wikilink store would be invisible to its own gate.

  A RENAME IS A DELETE PLUS AN ADD AND WILL FAIL THIS GATE. That is intended, not an oversight: renaming
  a rule breaks the git-visible continuity of its history, which is the preservation guarantee. Retire a
  rule by editing its content to a superseded stub; never by removing or renaming its file.

.PARAMETER RepoRoot
  Repository root. Defaults to this script's parent's parent. A parameter so the suite can point the
  gate at a throwaway fixture repo - a gate that can only ever run against the real tree cannot have its
  failure paths proven, and an unproven failure path is indistinguishable from a vacuous one.
.PARAMETER StoreDir
  Repo-relative store path. Default agy-autotrain/knowledge/rules.
.PARAMETER BaselineRef
  Git ref the store is compared against for deletions. Default HEAD.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$StoreDir = 'agy-autotrain/knowledge/rules',
    [string]$BaselineRef = 'HEAD'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$repo = $RepoRoot
$abs = Join-Path $repo $StoreDir
$problems = @()
function Problem([string]$m) { $script:problems += $m }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "check-knowledge-store: FAIL: required tool 'git' not found on PATH" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $abs)) {
    Write-Host "check-knowledge-store: SKIP - no store at $StoreDir" -ForegroundColor DarkGray
    exit 0
}

$onDisk = @(Get-ChildItem -LiteralPath $abs -Filter '*.md' -File | ForEach-Object { $_.Name })

# ---- 1. DELETION vs the git baseline -------------------------------------------------------------
# FAIL CLOSED if the baseline cannot be read. A gate that treats "I could not look" as "nothing is
# missing" certifies exactly what it stopped checking.
$baseline = @(& git -C $repo ls-tree --name-only "${BaselineRef}:$StoreDir" 2>$null)
if ($LASTEXITCODE -ne 0) {
    if (@(& git -C $repo rev-parse --verify --quiet $BaselineRef 2>$null).Count -eq 0) {
        Write-Host "check-knowledge-store: SKIP - baseline ref '$BaselineRef' does not resolve (a fresh repo has no HEAD)" -ForegroundColor DarkGray
        exit 0
    }
    Write-Host "check-knowledge-store: SKIP - the store does not exist at '$BaselineRef' yet (first commit)" -ForegroundColor DarkGray
    $baseline = @()
}
foreach ($b in $baseline) {
    if ($b -notlike '*.md') { continue }
    if ($onDisk -notcontains $b) {
        Problem "DELETED: $b existed at $BaselineRef and is gone. A rule file is never removed - retire it by editing its content to a superseded stub. Git history is the preservation tier and a deletion severs it. (A RENAME lands here too, and that is intended.)"
    }
}

# ---- 2. ORPHANS: reachable from the index --------------------------------------------------------
$indexPath = Join-Path $abs 'INDEX.md'
if (-not (Test-Path -LiteralPath $indexPath)) {
    Problem "NO INDEX: $StoreDir/INDEX.md is missing. Without it nothing is reachable and the store is a pile of files."
} else {
    $indexText = [System.IO.File]::ReadAllText($indexPath)
    # Strip code spans before parsing. MEASURED on a sibling corpus: bare bracketed tokens inside
    # backticks parse as links and produced 2 of 11 false positives. A checker that cries wolf is
    # ignored within a week - the same reason .mlc.toml scopes itself so tightly.
    $stripped = [regex]::Replace($indexText, '`[^`]*`', ' ')
    $stripped = [regex]::Replace($stripped, '(?s)```.*?```', ' ')
    $linked = @([regex]::Matches($stripped, '\(([A-Za-z0-9_.-]+\.md)\)') | ForEach-Object { $_.Groups[1].Value })
    foreach ($f in $onDisk) {
        if ($f -eq 'INDEX.md') { continue }
        if ($linked -notcontains $f) {
            Problem "ORPHAN: $f is not linked from INDEX.md. It still exists, but nothing leads a reader - or the curator selecting a projection - to it."
        }
    }
}

# ---- 3. HYGIENE: LF and pure ASCII ---------------------------------------------------------------
# Inherited from the GROWTH region these rules were split out of: that region is published through a
# byte transport which corrupted it once (2026-07-19 to 2026-08-01, 22 CP437 sequences, with a sha256
# sidecar that matched the CORRUPT content and so certified it).
foreach ($f in $onDisk) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $abs $f))
    if ($bytes -contains 13) { Problem "CRLF: $f contains a carriage return; the store is authored LF." }
    $hi = @($bytes | Where-Object { $_ -gt 127 })
    if ($hi.Count -gt 0) { Problem "NON-ASCII: $f has $($hi.Count) byte(s) > 127; the store is pure ASCII by policy." }
}

if ($problems.Count -gt 0) {
    Write-Host "check-knowledge-store: $($problems.Count) problem(s)" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
$ruleCount = @($onDisk | Where-Object { $_ -ne 'INDEX.md' }).Count
Write-Host "check-knowledge-store: OK - $ruleCount rule(s), none deleted since $BaselineRef, all reachable from INDEX.md, LF + pure ASCII." -ForegroundColor Green
exit 0
