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
$blocks = @()
$current = $null
foreach ($line in (Get-Content -LiteralPath $WorkflowPath)) {
    if ($line -match '^\s*paths:\s*$') { $current = New-Object System.Collections.ArrayList; $blocks += ,$current; continue }
    if ($null -ne $current) {
        if ($line -match "^\s*-\s*['""]([^'""]+)['""]\s*$") { [void]$current.Add($Matches[1]) } else { $current = $null }
    }
}
# NON-VACUITY. Both are real failures, not "nothing to do": a parse that yields no blocks, or a block
# that yields no entries, would make every assertion below pass without testing anything.
if ($blocks.Count -lt 2) { Fail "expected at least 2 paths: blocks (push and pull_request) in $WorkflowPath, parsed $($blocks.Count) - the parser or the workflow changed shape."; exit 1 }
for ($i = 0; $i -lt $blocks.Count; $i++) {
    if ($blocks[$i].Count -eq 0) { Fail "paths: block #$($i+1) parsed as EMPTY - the gate would pass vacuously."; exit 1 }
}

# ---- CHECK A: every required entry, in EVERY block. ---------------------------------------------
foreach ($entry in $Required.Keys) {
    $missing = @()
    for ($i = 0; $i -lt $blocks.Count; $i++) { if ($blocks[$i] -notcontains $entry) { $missing += ($i + 1) } }
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
            if ($l -eq $r -or $l.StartsWith($r + '/')) {
                if (-not $reached.ContainsKey($r)) { $reached[$r] = New-Object System.Collections.ArrayList }
                if (-not $reached[$r].Contains($s.Name)) { [void]$reached[$r].Add($s.Name) }
                break
            }
        }
    }
}

$coveredRoots = @{}
foreach ($e in $blocks[0]) { $coveredRoots[($e -split '/')[0]] = $true }

foreach ($r in ($reached.Keys | Sort-Object)) {
    if ($coveredRoots.ContainsKey($r)) { continue }
    if ($Exemptions.ContainsKey($r)) { continue }
    $problems += "  UNCOVERED root '$r' - named by: $($reached[$r] -join ', ')"
}
foreach ($e in ($Exemptions.Keys | Sort-Object)) {
    if (-not $reached.ContainsKey($e))    { $problems += "  STALE exemption '$e' - no suite names it any more; delete the entry." }
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
