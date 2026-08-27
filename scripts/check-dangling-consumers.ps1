#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fail when a binary READS a runtime filename that nothing in the repository WRITES.

.DESCRIPTION
  A "dangling consumer" is a reader pointed at a filename that has no producer. It is invisible to every
  other gate we own: the code compiles, every test passes (the tests write the file themselves), and the
  reader degrades to its fallback in silence. MEASURED 2026-08-27, this is not hypothetical - commit
  f497aaa repointed both driver-cheatsheet readers at `driver-cheatsheet.growth.md` while the only writer
  (agy-curate/SKILL.md) kept writing the RETIRED name, so the EXTEND path was unreachable in production
  from the moment it shipped and nothing said a word. This gate would have failed that commit.

  WHY THE LITERAL, NOT THE SYMBOL. Symbol names collide across files - `GrowthFileName` is declared in
  BOTH DriverCheatsheet.cs and GoldenHeader.cs - so a symbol search reports a producer for one constant
  because a DIFFERENT constant of the same name has one. The literal is unique and unambiguous.

  WHY TEST FILES ARE NOT PRODUCERS - this is the whole subtlety, and it was volunteered as the likely
  false negative before the gate was written. A test necessarily writes the file it is testing the reader
  against, so counting tests as producers makes this gate PASS on precisely the bug it exists to catch:
  for `driver-cheatsheet.growth.md` the literal appears in three test files and nowhere else. A gate that
  accepted those would have been green on F1. See the exclusion test in the suite, which pins this.

  THE EXEMPTION IS DERIVED, NEVER A HAND-MAINTAINED ROSTER. A constant whose IDENTIFIER declares it legacy
  or retired is read-only by design - it names a file an EARLIER version wrote, kept so an upgrading user's
  file is still recognised. Those are skipped, and every skip is PRINTED, so an exemption cannot be quiet.
  Renaming a live constant to "Legacy" to dodge this gate would be a visible lie in the diff.

.PARAMETER RepoRoot
  Repository root. Defaults to this script's parent's parent. A parameter so the suite can point the gate
  at a throwaway fixture tree - a gate whose failure path cannot be exercised is indistinguishable from a
  vacuous one.
.NOTES
  Read-only checker: no -WhatIf, by the standing exemption for checkers and *.Tests.ps1.
#>
[CmdletBinding()]
param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
$repo = (Resolve-Path -LiteralPath $RepoRoot).Path

# The reader sources we scan. These are also, by construction, NOT producers for their own constants.
$sourceGlobs = @('clavity-dotnet/src/Clavity.Ls/*.cs', 'clavity-classic/src/*.rs')
$sources = @()
foreach ($g in $sourceGlobs) {
    $sources += @(Get-ChildItem -Path (Join-Path $repo $g) -File -ErrorAction SilentlyContinue)
}
if ($sources.Count -eq 0) {
    Write-Host "check-dangling-consumers: SKIP - no binary sources under $($sourceGlobs -join ', ')" -ForegroundColor DarkGray
    exit 0
}

# A constant bound to a *.md literal, in either language:
#   public const string GrowthFileName = "driver-cheatsheet.growth.md";
#   pub const GROWTH_FILE: &str = "golden-header.growth.md";
$declPattern = '(?:const\s+string|const)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*&str\s*)?=\s*"([^"]+\.md)"'

$consts = @()
foreach ($f in $sources) {
    $lines = [System.IO.File]::ReadAllLines($f.FullName)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $m = [regex]::Match($lines[$i], $declPattern)
        if ($m.Success) {
            $consts += [pscustomobject]@{
                Symbol  = $m.Groups[1].Value
                Literal = $m.Groups[2].Value
                File    = $f.FullName.Substring($repo.Length).TrimStart('\', '/')
                Line    = $i + 1
            }
        }
    }
}

if ($consts.Count -eq 0) {
    Write-Host "check-dangling-consumers: SKIP - no runtime filename constants found" -ForegroundColor DarkGray
    exit 0
}

# A file is not evidence of a producer if it is one of the readers we scanned, a test, or this gate.
$readerPaths = @($sources | ForEach-Object { $_.FullName })
function Test-IsProducerCandidate([string]$path) {
    if ($readerPaths -contains $path) { return $false }
    $leaf = Split-Path -Leaf $path
    if ($leaf -like '*.Tests.*' -or $leaf -like '*Tests.*' -or $leaf -eq 'integration.rs') { return $false }
    if ($leaf -eq 'check-dangling-consumers.ps1') { return $false }
    # Any path segment that is a test directory.
    $norm = $path.Replace('\', '/')
    if ($norm -match '/tests?/') { return $false }
    return $true
}

$searchable = @(Get-ChildItem -LiteralPath $repo -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $n = $_.FullName.Replace('\', '/')
        $n -notmatch '/\.git/' -and $n -notmatch '/\.clavity/' -and
        $n -notmatch '/target/' -and $n -notmatch '/bin/' -and $n -notmatch '/obj/' -and
        $n -notmatch '/node_modules/' -and $_.Length -lt 2MB
    })

$problems = @()
$skipped = @()
foreach ($c in $consts) {
    # DERIVED exemption: the identifier itself declares the constant read-only.
    if ($c.Symbol -match '(?i)legacy|retired') {
        $skipped += "$($c.Symbol) = '$($c.Literal)' ($($c.File):$($c.Line)) - identifier declares it read-only"
        continue
    }

    $producers = @()
    foreach ($f in $searchable) {
        if (-not (Test-IsProducerCandidate $f.FullName)) { continue }
        $txt = try { [System.IO.File]::ReadAllText($f.FullName) } catch { continue }
        if ($txt.Contains($c.Literal)) {
            $producers += $f.FullName.Substring($repo.Length).TrimStart('\', '/')
        }
    }
    if ($producers.Count -eq 0) {
        $problems += "DANGLING CONSUMER: $($c.File):$($c.Line) reads '$($c.Literal)' (const $($c.Symbol)), but NOTHING in the repository writes that name. Tests do not count as producers - a test writes the file it is testing, so counting them makes this gate green on exactly the bug it exists to catch. Either point the producer at this name, or - if the file is written by an earlier version and only READ here - rename the constant to declare it Legacy/Retired, which is the derived exemption."
    }
}

foreach ($s in $skipped) { Write-Host "  skipped (read-only by design): $s" -ForegroundColor DarkGray }

if ($problems.Count -gt 0) {
    Write-Host "check-dangling-consumers: $($problems.Count) problem(s)" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
$checked = $consts.Count - $skipped.Count
Write-Host "check-dangling-consumers: OK - $checked runtime filename constant(s) each have a producer outside the readers and tests; $($skipped.Count) exempt." -ForegroundColor Green
exit 0
