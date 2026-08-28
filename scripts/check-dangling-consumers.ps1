#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Fail when a binary reads a runtime filename FROM A NAMED CONSTANT that nothing in the repository
  DECLARES it produces.

  The "from a named constant" clause is not padding - see WHAT THIS DOES NOT COVER below. An earlier
  version of this line said simply "when a binary READS a runtime filename", which claimed a coverage the
  check does not have, and overclaiming in this header has already produced one weaker-than-documented
  gate in this file's history.

.DESCRIPTION
  A "dangling consumer" is a reader pointed at a filename that has no producer. It is invisible to every
  other gate we own: the code compiles, every test passes (the tests write the file themselves), and the
  reader degrades to its fallback in silence. MEASURED 2026-08-27 - commit f497aaa repointed both
  driver-cheatsheet readers at a new filename while the only writer kept writing the RETIRED one, so the
  EXTEND path was unreachable in production from the moment it shipped and nothing said a word.

  HOW A PRODUCER IS IDENTIFIED: IT SAYS SO. A file declares itself the producer of a runtime artifact with
  an explicit marker, on any line, in any file type - the marker word followed by the quoted filename. The
  gate looks for exactly that. Nothing else counts.

  WHY THE MARKER, AND WHAT IT REPLACED - the load-bearing part of this header. Four earlier versions
  INFERRED production from prose, and a capstone round measured each inference wrong in turn:
    * v1 accepted any non-test file CONTAINING the filename. MEASURED: seven files contained it and
      exactly one wrote it, so deleting the real writer would have left the gate green.
    * v2 required the filename NEAR a write word. MEASURED: a line saying we do NOT write that file
      satisfied it - a denial counted as a declaration.
    * v3 added a negation list. MEASURED: a PowerShell line guarding a real write with the -not operator
      was read as a denial, so the guard vetoed the only genuine writer in the tree.
    * v4 added a lookbehind, on the theory that a leading hyphen distinguishes the OPERATOR from prose.
      MEASURED false twice over: PowerShell also spells that operator with a bang, and a write line
      carrying an ordinary English comment containing "not" trips the filter anyway.

  Each fix was a smaller epicycle on one mistake - inferring intent from unstructured text by regex
  proximity. Four rounds of that IS the evidence. The marker asks the producer to state the fact instead
  of asking this script to deduce it, turning a semantic guess into an exact string match. It also deleted
  the entire test-file exclusion, because every exclusion rule this gate ever had became a defect of its
  own. That deletion is a TRADE, not a free win: a test CAN contain a marker - this file assembles its own
  from a char code precisely so its suite does not vouch for the filenames it discusses, which is proof
  that the case is real rather than theoretical. The residual assumption is stated below; an earlier draft
  of this paragraph claimed no rule was needed at all, which contradicted it two paragraphs later.

  WHAT THIS DOES NOT COVER, and the gap is structural rather than an oversight. Only a filename bound to a
  NAMED CONSTANT in one of the scanned sources is checked. A reader that computes its path, or names the
  file inline, has no constant to extract - so it is not checked and the gate reports OK. That is a false
  NEGATIVE, which is the worse direction: under the previous design the same shape produced a false ALARM,
  which is loud. MEASURED 2026-08-28, the tree contains the SHAPE (two manuals named in a tuple array in
  EscalationIndex.cs, and a joined "SKILL.md" in main.rs) but no live instance of the DEFECT - both are
  written or existence-checked by the same code that names them. Tracked as debt rather than closed,
  because the honest fixes are either a reader-side marker or a real analyzer, and neither is worth its
  cost while the live count is zero. Re-check that count before relying on this gate for a new reader.

  WHAT THIS PROVES, AND WHAT IT DOES NOT. The marker is a DECLARATION, not a proven write - nothing here
  executes the writer or watches a filesystem, and a file that declares it may still fail to write. The
  claim is deliberately narrow, and it is exactly the shape that has actually occurred: a reader whose
  filename NOBODY EVEN CLAIMS to produce. Do not upgrade that sentence to "verifiable producer" - an
  earlier header said precisely that while the check underneath accepted a bare mention.

  THE ONE RESIDUAL ASSUMPTION, stated rather than hidden: a fixture that writes a marker for a REAL
  runtime filename into a tracked file would satisfy this gate falsely. Nothing guards that, deliberately.
  Use a fictional filename in fixtures, as this gate's own suite does. One greppable convention beats a
  pile of semantic guesses.

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

# The reader sources scanned for runtime filename constants.
$sourceGlobs = @('clavity-dotnet/src/Clavity.Ls/*.cs', 'clavity-classic/src/*.rs')
$sources = @()
foreach ($g in $sourceGlobs) {
    $sources += @(Get-ChildItem -Path (Join-Path $repo $g) -File -ErrorAction SilentlyContinue)
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

# ONE early exit, not two. A capstone round found the previous version's "no binary sources" exit was
# unreachable BY ITS OWN TEST: the row asserted exit 0 plus the word SKIP, and a SECOND exit downstream
# produced both, so the row passed with the code it claimed to guard deleted. Collapsing the two removes
# the vacuity at its source instead of bolting a sharper assertion onto a redundant branch.
if ($consts.Count -eq 0) {
    Write-Host "check-dangling-consumers: SKIP - no runtime filename constants found under $($sourceGlobs -join ', ')" -ForegroundColor DarkGray
    exit 0
}

$searchable = @(Get-ChildItem -LiteralPath $repo -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
        $n = $_.FullName.Replace('\', '/')
        $n -notmatch '/\.git/' -and $n -notmatch '/\.clavity/' -and
        $n -notmatch '/target/' -and $n -notmatch '/bin/' -and $n -notmatch '/obj/' -and
        $n -notmatch '/node_modules/' -and $_.Length -lt 2MB
    })

# The marker is ASSEMBLED, never written literally in this file, so that the gate's own prose cannot vouch
# for a filename it discusses. The previous design had to special-case its own filename to avoid exactly
# that; removing the possibility beats excluding a path.
$marker = [char]64 + 'produces'
$markerPattern = $marker + '\s+"([^"]+)"'

# Collect every declaration in the tree ONCE rather than re-reading every file per constant. The cheap
# -notlike guard runs first: only a handful of files carry a marker, and reading the whole tree is the
# expensive part.
$declared = @{}
foreach ($f in $searchable) {
    $txt = try { [System.IO.File]::ReadAllText($f.FullName) } catch { continue }
    if ($txt -notlike "*$marker*") { continue }
    foreach ($m in [regex]::Matches($txt, $markerPattern)) {
        $name = $m.Groups[1].Value
        if (-not $declared.ContainsKey($name)) { $declared[$name] = @() }
        $declared[$name] += $f.FullName.Substring($repo.Length).TrimStart('\', '/')
    }
}

$problems = @()
$skipped = @()
foreach ($c in $consts) {
    # DERIVED exemption: the identifier itself declares the constant read-only.
    if ($c.Symbol -match '(?i)legacy|retired') {
        $skipped += "$($c.Symbol) = '$($c.Literal)' ($($c.File):$($c.Line)) - identifier declares it read-only"
        continue
    }
    if (-not $declared.ContainsKey($c.Literal)) {
        $problems += "DANGLING CONSUMER: $($c.File):$($c.Line) reads '$($c.Literal)' (const $($c.Symbol)), but NOTHING in the repository declares it produces that file. Add a marker line to whatever writes it - the word $marker followed by the quoted filename - or, if the file is written by an EARLIER version and only read here for compatibility, rename the constant to declare it Legacy/Retired, which is the derived exemption."
    }
}

foreach ($s in $skipped) { Write-Host "  skipped (read-only by design): $s" -ForegroundColor DarkGray }

if ($problems.Count -gt 0) {
    Write-Host "check-dangling-consumers: $($problems.Count) problem(s)" -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
}
$checked = $consts.Count - $skipped.Count
Write-Host "check-dangling-consumers: OK - $checked runtime filename constant(s) each carry a producer declaration; $($skipped.Count) exempt." -ForegroundColor Green
exit 0
