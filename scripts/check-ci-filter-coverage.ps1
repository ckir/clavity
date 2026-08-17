#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Gate: ci-scripts.yml's `paths:` filter must actually cover what the scripts Pester suite asserts
  against - checked two ways, one precise and one fail-closed.
.DESCRIPTION
  WHY THIS EXISTS. ci-scripts.yml is the ONLY workflow that runs `Invoke-Pester scripts/tests`, and its
  own comment states the rule: every file the suite reads and asserts against must appear in the filter,
  because otherwise "the assertion reds on a developer's machine and the same edit merges with a green
  check, because no job ever ran". That rule had NO IMPLEMENTATION, and it drifted exactly as an
  unimplemented rule does. The workflow's comment records one file being missed when another was added;
  a later audit measured FIVE more trees the suite asserts against that the filter never listed - both
  plugin trees, the driver cheatsheet, the marker contract, and build/members.json. A hand-maintained
  count in a comment was wrong three times, twice in one afternoon. Hence a gate, not a better comment.

  TWO CHECKS, BECAUSE ONE CANNOT DO BOTH JOBS.

  CHECK A - REQUIRED ENTRIES (precise). The table below names every entry the filter must carry, each
  with the suite that makes it necessary. It also asserts each appears in BOTH `paths:` blocks: the
  workflow has one for `push` and one for `pull_request`, they must agree, and NOTHING previously checked
  that - adding to one and forgetting the other yields a filter that is right on merge and wrong on PRs,
  or the reverse. This check is what makes the gate useful today.

  CHECK B - ROOT VOCABULARY (fail-closed on the unknown). Every git-tracked top-level directory that any
  suite mentions as a string literal must be covered by some filter entry or carry a written exemption.
  This is the anti-rot net: it fires on a tree nobody has thought about yet, which is the case Check A
  structurally cannot cover because a required-entry table only knows what someone already wrote in it.

  WHAT THIS DELIBERATELY DOES NOT CHECK, stated rather than papered over: Check B matches at ROOT
  granularity, so a NEW SUBTREE under an already-covered root does not fire - `clavity-dotnet/install/**`
  alone satisfies the root `clavity-dotnet`, which is precisely why the original `clavity-dotnet/plugin/**`
  gap survived. Check A is what closes that case, and only for the entries actually listed in it. A gate
  that claimed to catch every new subtree would be certifying what it had stopped checking.

  WHY THE AST, NOT A REGEX (Check B). Suites build paths three ways - a bare literal, a
  `Join-Path $script:RepoRoot 'a/b'`, and `[IO.Path]::Combine($PSScriptRoot,'..','..','a','b')`. A
  path-shaped grep sees the first two and is BLIND to the third: the string `installer/_shared` appears
  ZERO times in register-plugin.Tests.ps1, which is exactly how that tree escaped a hand audit. The AST
  returns every string constant however it is later assembled, so the third form yields the bare literal
  'installer' and is caught. Measured against all three forms before this gate was written.

  WHY ROOTS COME FROM GIT, NOT THE FILESYSTEM. `git ls-files` is what CI checks out; a filesystem scan
  also sees untracked local junk (tool caches, build output), making the verdict depend on the
  developer's working tree.
.PARAMETER RepoRoot
  Repo root (default: this script's parent's parent).
.PARAMETER WorkflowPath
  The workflow whose paths: filter is checked (default: .github/workflows/ci-scripts.yml).
#>
[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$WorkflowPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $WorkflowPath) { $WorkflowPath = Join-Path $RepoRoot '.github/workflows/ci-scripts.yml' }

# CHECK A's table. Each entry names WHY it is required, so a later reader can re-derive it instead of
# trusting it. Removing an entry here is a decision, not an oversight.
$Required = [ordered]@{
    'scripts/**'                                      = 'the suite itself'
    'installer/_shared/**'                            = 'register-plugin.Tests.ps1 dot-sources installer/_shared/register-plugin.ps1'
    'clavity-dotnet/install/**'                       = 'test-suite-registration.Tests.ps1 pins clavity-install.Tests.ps1 by PATH and asserts the file exists'
    'clavity-dotnet/plugin/**'                        = 'agy-mark / agy-shield-lib / agy-seam-inject / agy-discipline-reaching suites all read hooks from this tree'
    'clavity-classic/plugin/**'                       = 'the byte-identical mirror of the above; plugin-hooks-payload compares both trees'
    'justfile'                                        = 'test-suite-registration reads the real justfile; assertion-strength-reminder pins its own fast-suite entry'
    'lefthook.yml'                                    = 'check-curate-in-progress asserts the pre-commit wiring lives there'
    'agy-autotrain/skills/agy-curate/SKILL.md'        = 'check-curate-in-progress asserts the marker path that skill ARMS is the one the guard READS'
    'agy-autotrain/knowledge/driver-cheatsheet.core.md' = 'check-cheatsheet-budget reads the canonical cheatsheet; listed narrowly so the high-churn observations inbox beside it does not trigger CI'
    'docs/agy-disciplines-marker-contract.md'         = 'check-injected-context resolves that token against the real repo root, so a rename reds the row'
    'build/members.json'                              = 'check-roster reads the real members manifest (validate-members.yml fires on it but does NOT run Pester)'
    '.github/workflows/ci-scripts.yml'                = 'the filter must re-run the job it controls'
}

# CHECK B's exemptions: a root the suites NAME but do not read from the real repository. Each says why.
# A stale or redundant exemption is a FAILURE below, so this table cannot quietly rot either.
$Exemptions = @{
    'seed'         = 'named only inside temp fixtures - check-injected-context builds its seed under GetTempPath() and passes it as -RepoRoot $base; no suite reads the repo copy'
    'ghidrust'     = 'named only in fixture trees and ignore/exemption corpora; no suite reads the repo copy'
    'commonmemory' = 'named only in fixture trees and member-manifest corpora; no suite reads the repo copy'
    '.claude'      = 'named as a path SEGMENT the suites create inside their own temp fixtures; the real ~/.claude is out of bounds for tests'
}

function Fail([string]$msg) { Write-Host "check-ci-filter-coverage: FAIL: $msg" -ForegroundColor Red }
$problems = @()

# ---- Parse the workflow's paths: blocks. --------------------------------------------------------
if (-not (Test-Path -LiteralPath $WorkflowPath)) { Fail "workflow not found at $WorkflowPath"; exit 1 }
$wfLines = [string[]](Get-Content -LiteralPath $WorkflowPath)

# TABS ARE A HARD FAIL, AND THAT IS NOT PEDANTRY. YAML forbids tab indentation outright, so a
# tab-indented filter makes the WHOLE workflow unparseable and GitHub never runs it - while `\s` in the
# regexes below matches tabs perfectly happily, so this gate would read the filter, find everything it
# wanted, and report OK on a workflow that CANNOT RUN. MEASURED: with the list items tab-indented, the
# gate said "OK - 12 required entries present in all 2 paths: blocks" while `yq` rejected the file.
$tabLines = @(for ($i = 0; $i -lt $wfLines.Count; $i++) { if ($wfLines[$i] -match "`t") { $i + 1 } })
if ($tabLines.Count -gt 0) {
    Fail "$WorkflowPath contains TAB characters on line(s) $($tabLines -join ', ') - YAML forbids tab indentation, so GitHub cannot parse this workflow and would never run it."
    exit 1
}

# ONLY `paths:` KEYS INSIDE THE TOP-LEVEL `on:` SECTION COUNT. The first version matched
# `^\s*paths:\s*$` ANYWHERE in the file, so a filter sitting somewhere with no trigger meaning still
# satisfied the gate. MEASURED: with the `on:` key renamed, the gate reported "OK - 12 required entries
# present in all 2 paths: blocks" while `yq` resolved `.on.push.paths` to length 0 - a filter GitHub
# ignores completely. Blank and comment lines are skipped rather than treated as terminators, because a
# comment between list items is legal YAML and must not silently truncate a block.
$blocks = @()
$current = $null
$inOn = $false
foreach ($line in $wfLines) {
    if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
    if ($line -match '^\S') { $inOn = ($line -match '^(on|"on"|''on''):\s*$'); $current = $null; continue }
    if (-not $inOn) { continue }
    if ($line -match '^\s*paths:\s*$') { $current = New-Object System.Collections.ArrayList; $blocks += ,$current; continue }
    if ($null -ne $current) {
        if ($line -match "^\s*-\s*['""]([^'""]+)['""]\s*$") { [void]$current.Add($Matches[1]) } else { $current = $null }
    }
}
# NON-VACUITY, AND THE RATIONALE HERE WAS WRONG UNTIL A CAPSTONE ROUND CORRECTED IT. An empty block does
# NOT make the checks below "pass without testing anything": `-cnotcontains` against an empty block flags
# every required entry as missing, so the gate already fails closed. What these two guards actually buy
# is a message naming the REAL cause - the parser or the workflow changed shape - instead of twelve
# misleading "missing entry" lines sending the reader off to edit a filter that is fine. That is also
# exactly what the matching test rows assert, and what goes red if either guard is deleted.
if ($blocks.Count -lt 2) { Fail "expected at least 2 paths: blocks (push and pull_request) under the top-level ``on:`` key in $WorkflowPath, parsed $($blocks.Count) - the parser or the workflow changed shape."; exit 1 }
for ($i = 0; $i -lt $blocks.Count; $i++) {
    if ($blocks[$i].Count -eq 0) { Fail "paths: block #$($i+1) parsed as EMPTY - reporting that instead of listing every required entry as missing, which is what the checks below would otherwise say."; exit 1 }
}

# ---- CHECK A: every required entry, in EVERY block. ---------------------------------------------
# CASE-SENSITIVE ON PURPOSE (`-cnotcontains`, not `-notcontains`). GitHub Actions matches `paths:`
# case-sensitively, but PowerShell's `-notcontains` does not: `@('scripts/**') -notcontains 'Scripts/**'`
# is FALSE, so a capitalised entry would satisfy this gate while GitHub silently never fired the
# workflow. Measured both operators before changing it. That is the worst shape available - a green gate
# certifying a filter that does not trigger.
foreach ($entry in $Required.Keys) {
    $missing = @()
    for ($i = 0; $i -lt $blocks.Count; $i++) { if ($blocks[$i] -cnotcontains $entry) { $missing += ($i + 1) } }
    if ($missing.Count -gt 0) {
        $problems += "  MISSING required entry '$entry' from paths: block(s) $($missing -join ', ') - needed because: $($Required[$entry])"
    }
}

# ---- CHECK B: root vocabulary. ------------------------------------------------------------------
Push-Location $RepoRoot
try { $tracked = & git ls-files } finally { Pop-Location }
if ($LASTEXITCODE -ne 0 -or -not $tracked) { Fail "``git ls-files`` returned nothing in $RepoRoot - roots could not be enumerated, so nothing was checked."; exit 1 }
$roots = @($tracked | ForEach-Object { $p = $_ -split '/'; if ($p.Count -gt 1) { $p[0] } } |
    Sort-Object -Unique | Where-Object { $_ -ne 'scripts' })
if ($roots.Count -eq 0) { Fail 'no top-level directories found - the enumeration is broken, not the repo.'; exit 1 }

$suites = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts/tests') -Filter '*.Tests.ps1' -ErrorAction SilentlyContinue)
if ($suites.Count -eq 0) { Fail 'no *.Tests.ps1 found under scripts/tests - the gate would pass vacuously.'; exit 1 }

$reached = @{}
foreach ($s in $suites) {
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($s.FullName, [ref]$tokens, [ref]$errors)
    # A SUITE THAT DOES NOT PARSE IS A HARD ERROR, NOT A SKIP. Skipping would silently shrink the corpus
    # this gate reasons over - the exact fail-open shape it exists to prevent.
    if ($errors -and $errors.Count -gt 0) { Fail "$($s.Name) does not parse: $($errors[0].Message)"; exit 1 }
    $lits = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
        ForEach-Object { $_.Value }
    foreach ($r in $roots) {
        foreach ($l in $lits) {
            # ORDINAL, not culture-sensitive, and case-SENSITIVE: these are repository paths, and the
            # roots they are compared against came straight out of `git ls-files`.
            if ($l -ceq $r -or $l.StartsWith($r + '/', [StringComparison]::Ordinal)) {
                if (-not $reached.ContainsKey($r)) { $reached[$r] = New-Object System.Collections.ArrayList }
                if (-not $reached[$r].Contains($s.Name)) { [void]$reached[$r].Add($s.Name) }
                break
            }
        }
    }
}

# COVERED MEANS COVERED IN *EVERY* BLOCK, NOT IN THE FIRST ONE. Building this from $blocks[0] alone was
# a MEASURED fail-open: with `ghidrust/**` added to the `push` block only, the gate declared the root
# covered and returned 0, while the `pull_request` trigger - the half that actually gates review - stayed
# blind to it. Check A cannot backstop that, because Check A only knows the entries someone already wrote
# into $Required; a brand-new tree added to one block is exactly the case Check B exists for.
# A plain @{} would ALSO defeat the case-sensitivity fix above, since PowerShell hashtable keys are
# case-insensitive - hence an ordinal dictionary.
$coveredRoots = [System.Collections.Generic.Dictionary[string, bool]]::new([StringComparer]::Ordinal)
$blockRoots = New-Object System.Collections.ArrayList
foreach ($b in $blocks) {
    $h = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($e in $b) { [void]$h.Add(($e -split '/')[0]) }
    [void]$blockRoots.Add($h)
}
foreach ($k in $blockRoots[0]) {
    $inAll = $true
    foreach ($h in $blockRoots) { if (-not $h.Contains($k)) { $inAll = $false; break } }
    if ($inAll) { $coveredRoots[$k] = $true }
}

foreach ($r in ($reached.Keys | Sort-Object)) {
    if ($coveredRoots.ContainsKey($r)) { continue }
    if ($Exemptions.ContainsKey($r)) { continue }
    $problems += "  UNCOVERED root '$r' - named by: $($reached[$r] -join ', ')"
}
foreach ($e in ($Exemptions.Keys | Sort-Object)) {
    # EVERY EXEMPTION KEY MUST BE AN EXACT, CASE-SENSITIVE MATCH FOR A REAL GIT ROOT. $Exemptions is a
    # PowerShell hashtable, whose keys are CASE-INSENSITIVE, while $coveredRoots above is ordinal. A key
    # written 'Seed' would therefore still suppress the root 'seed' on the lookup at :203, but
    # $coveredRoots.ContainsKey('Seed') would be FALSE forever - so a redundant exemption could never be
    # reported and would rot in place, silently exempting a root the filter already covers. Demanding an
    # exact ordinal match against git's own root list closes that, and catches an ordinary typo too.
    if ($roots -cnotcontains $e) {
        $problems += "  BOGUS exemption '$e' - not an exact (case-sensitive) top-level git root. Real roots: $($roots -join ', ')"
    }
    elseif (-not $reached.ContainsKey($e)) { $problems += "  STALE exemption '$e' - no suite names it any more; delete the entry." }
    elseif ($coveredRoots.ContainsKey($e)) { $problems += "  REDUNDANT exemption '$e' - the filter now covers that root; delete the entry." }
}

# ---- Verdict. -----------------------------------------------------------------------------------
if ($problems.Count -gt 0) {
    Fail "ci-scripts.yml's paths: filter does not cover what the scripts suite asserts against."
    $problems | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "  Fix: add the entry to BOTH paths: blocks in $WorkflowPath, or record a reason in $PSCommandPath." -ForegroundColor Red
    exit 1
}

Write-Host "check-ci-filter-coverage: OK - $($Required.Count) required entries present in all $($blocks.Count) paths: blocks; $($reached.Count) root(s) named by $($suites.Count) suites, all covered or exempt." -ForegroundColor Green
exit 0
