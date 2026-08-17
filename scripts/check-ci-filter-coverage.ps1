#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Gate: every entry the scripts Pester suite depends on must be present in BOTH of ci-scripts.yml's
  `paths:` blocks.
.DESCRIPTION
  WHY THIS EXISTS. ci-scripts.yml is the ONLY workflow that runs `Invoke-Pester scripts/tests`, and its
  own comment states the rule: every file the suite reads and asserts against must appear in the filter,
  because otherwise "the assertion reds on a developer's machine and the same edit merges with a green
  check, because no job ever ran". That rule had NO IMPLEMENTATION, and it drifted exactly as an
  unimplemented rule does. The workflow's comment records one file being missed when another was added;
  a later audit measured FIVE more trees the suite asserts against that the filter never listed - both
  plugin trees, the driver cheatsheet, the marker contract, and build/members.json. A hand-maintained
  count in a comment was wrong three times, twice in one afternoon. Hence a gate, not a better comment.

  WHAT IT CHECKS. The $Required table below names every entry the filter must carry, each with the suite
  that makes it necessary, and asserts each appears in BOTH `paths:` blocks. That last part matters on its
  own: the workflow has one block for `push` and one for `pull_request`, they must agree, and nothing else
  checks it - adding to one and forgetting the other yields a filter that is right on merge and wrong on
  every PR, or the reverse.

  WHAT IT DELIBERATELY DOES NOT CHECK, and this is a decision the owner took rather than an omission.
  There was a second half - a "root vocabulary" check that parsed every suite's AST for string literals,
  derived the repository's top-level directories from `git ls-files`, and required each named directory to
  be covered by the filter or carry a written exemption. Its purpose was to fire on a tree nobody had
  thought about yet, which a hand-maintained table structurally cannot do. It was DELETED, on this
  evidence: across five capstone rounds it produced four defects of its own - two fail-opens, one
  fail-closed-on-legal-input, and a false premise about YAML that drove three rounds of work - against the
  five real filter gaps it found ONCE, all five of which are now pinned by the table below. A gate whose
  own defect rate exceeds its discovery rate is not paying for itself.

  SO THE KNOWN LIMIT IS: a NEW tree, asserted against by a NEW suite, will not be detected here. The
  suite's own assertion still reds on a developer's machine; what is lost is the automatic reminder to add
  it to the filter. That trade was made knowingly. If it bites, the fix is a row in $Required, not a
  parser.
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
# INDENTATION ONLY, AND NOT INSIDE A BLOCK SCALAR. YAML forbids a tab in INDENTATION; a tab inside a
# string VALUE is legal, and so is one anywhere in a block scalar's BODY - `run: |` here holds shell
# script, which is opaque text. The first version flagged any tab in the file; the second still flagged
# tab-indented lines inside a `run: |` step. Both would fail this gate - now a pre-push hook - on a legal
# edit, and a gate that reds on legal input is its own kind of defect. Not reachable today (measured:
# zero such lines) but tab-indenting a line of shell is an ordinary thing to do.
# INDENTATION IS SPACES, AND A TAB ENDS IT. That is what YAML means, and both wrong answers came from
# pretending otherwise. Counting CHARACTERS made a tab worth 1 while it indents further, so a legal
# <TAB><sp><sp> body line measured shallower than its opener and reddened valid YAML. Expanding a tab to
# the next multiple of 8 then overshot the other way: an ILLEGAL line - fewer spaces than the scalar
# requires, followed by a tab - measured DEEPER than the opener, so it was taken for scalar body and the
# tab check was skipped, certifying a workflow GitHub cannot parse. MEASURED, both directions, at the
# geometry that breaks each. Counting leading SPACES ONLY gets both right and needs no tab-width
# constant: the illegal line measures 3 against a 4-space opener (checked, correctly flagged), the legal
# one measures 6 (skipped, correctly).
function Get-IndentSpaces([string]$s) {
    $c = 0
    foreach ($ch in $s.ToCharArray()) { if ($ch -eq ' ') { $c++ } else { break } }
    return $c
}

# ONE STRUCTURAL PASS, CONSUMED BY BOTH CHECKS BELOW. Deriving block-scalar state independently in two
# loops is exactly how they diverged: the tab loop understood scalars, the `paths:` loop did not, so a
# line reading `paths: # comma separated list` inside a `description: |` body registered as a real filter
# block. MEASURED: `yq` parsed that document happily with all 12 real paths while this gate failed with
# "paths: block #1 parsed as EMPTY" - a legal edit, a misleading message, and a blocked push.
$inScalar = New-Object 'bool[]' $wfLines.Count
$scalarIndent = -1
for ($i = 0; $i -lt $wfLines.Count; $i++) {
    $line = $wfLines[$i]
    if ($line -match '^\s*$') { $inScalar[$i] = ($scalarIndent -ge 0); continue }
    $indent = Get-IndentSpaces $line
    if ($scalarIndent -ge 0) {
        if ($indent -gt $scalarIndent) { $inScalar[$i] = $true; continue }
        $scalarIndent = -1
    }
    # `key: |`, `key: >`, with optional chomping/indent indicators, opens a block scalar.
    if ($line -match ':\s*[|>][-+0-9]*\s*$') { $scalarIndent = $indent }
}

# THE TAB CHECK NEEDS NO SCALAR EXEMPTION, AND THREE ROUNDS OF THIS FILE WERE SPENT PRETENDING IT DID.
# MEASURED against `yq`, every case sharing one skeleton with a spaces-only CONTROL that parses:
#     tab starts a scalar body line ............ REJECTED
#     spaces, then a tab, then content ......... REJECTED
#     tab in the MIDDLE of content (echo<TAB>x)  VALID
# So a tab is illegal anywhere in LEADING WHITESPACE - inside a block scalar exactly as much as outside -
# and legal only after the first non-space character. `^[ ]*<tab>` says precisely that: it matches a tab
# reached over spaces alone, and cannot match `echo<TAB>hi`. The original R8 check was already right; the
# block-scalar exemption added later, the column-based indent added after that, and the shared-state
# version after THAT were all fixing a problem that does not exist. An earlier probe appeared to show
# mid-content tabs being rejected too - it had no structural control, and the fixtures were failing for
# an unrelated reason. The control is why this is now stated as fact rather than believed.
$tabLines = @()
for ($i = 0; $i -lt $wfLines.Count; $i++) {
    if ($wfLines[$i] -match "^[ ]*`t") { $tabLines += ($i + 1) }
}
if ($tabLines.Count -gt 0) {
    Fail "$WorkflowPath uses a TAB in the indentation of line(s) $($tabLines -join ', ') - YAML forbids that, so GitHub cannot parse this workflow and would never run it."
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
for ($i = 0; $i -lt $wfLines.Count; $i++) {
    $line = $wfLines[$i]
    # A BLOCK SCALAR'S BODY IS OPAQUE TEXT AND CANNOT CONTAIN KEYS. Shared with the tab check above, so
    # the two can no longer disagree about where a scalar is - which is what let `paths: # ...` inside a
    # `description: |` be counted as a filter block.
    if ($inScalar[$i]) { continue }
    if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
    # A TRAILING COMMENT ON `on:` IS LEGAL TOO, and leaving it out was an inconsistency of my own making:
    # the `paths:` key below was made comment-tolerant while this one still demanded end-of-line. MEASURED:
    # `on: # the triggers` is VALID to yq, and this gate reported "parsed 0" blocks and blocked the push.
    if ($line -match '^\S') { $inOn = ($line -match '^(?:on|"on"|''on''):[ \t]*(?:#.*)?$'); $current = $null; continue }
    if (-not $inOn) { continue }
    # A YAML ANCHOR OR A TRAILING COMMENT ON THE KEY IS LEGAL, and this repo's OTHER gate already says so:
    # check-injected-context.Tests.ps1's $PathsKeyRx is `^\s+paths:[ \t]*(?:&[^\s#]+)?[ \t]*(?:#.*)?\r?$`.
    # A stricter matcher here meant the two gates disagreed about what a `paths:` block IS - so `paths: &shared`
    # satisfied one and made the other red with "expected at least 2 paths: blocks". Two gates answering the
    # same question differently is a defect even when each is individually defensible; this one now matches
    # the established shape. `paths-ignore:` still cannot match, having no `paths:`-then-end.
    if ($line -match '^\s*paths:[ \t]*(?:&[^\s#]+)?[ \t]*(?:#.*)?$') { $current = New-Object System.Collections.ArrayList; $blocks += ,$current; continue }
    if ($null -ne $current) {
        # QUOTES ARE OPTIONAL IN YAML, and demanding them was a fail-closed defect. `- justfile` is exactly
        # as valid as `- 'justfile'`; the strict form made a legal edit fail to match, fall into the `else`
        # below, TRUNCATE the block at that line, and cascade into false "missing entry" failures for
        # everything after it. MEASURED: yq VALID, gate exit 1. A trailing comment on an item is legal as
        # well. Quotes are stripped when present so the comparison against $Required is unaffected, and a
        # `#` with no space before it stays part of the value (`- 'a#b'` is a path, not a comment).
        if ($line -match '^\s*-\s*(\S.*?)\s*$') {
            $v = ($Matches[1] -replace '\s+#.*$', '').Trim()
            if ($v.Length -ge 2 -and
                (($v[0] -eq "'" -and $v[-1] -eq "'") -or ($v[0] -eq '"' -and $v[-1] -eq '"'))) {
                $v = $v.Substring(1, $v.Length - 2)
            }
            if ($v) { [void]$current.Add($v) }
        } else { $current = $null }
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

# ---- Verdict. -----------------------------------------------------------------------------------
if ($problems.Count -gt 0) {
    Fail "ci-scripts.yml's paths: filter is missing an entry the scripts suite depends on."
    $problems | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "  Fix: add the entry to BOTH paths: blocks in $WorkflowPath. Removing a row from $Required instead is a DECISION, not an oversight." -ForegroundColor Red
    exit 1
}

Write-Host "check-ci-filter-coverage: OK - all $($Required.Count) required entries present in all $($blocks.Count) paths: blocks." -ForegroundColor Green
exit 0
