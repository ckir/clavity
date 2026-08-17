#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Gate: every entry the scripts Pester suite depends on must be present in BOTH of ci-scripts.yml's
  `paths:` filters (`on.push` and `on.pull_request`).
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
  that makes it necessary, and asserts each appears under BOTH triggers. That last part matters on its
  own: `push` and `pull_request` must agree, and nothing else checks that - adding to one and forgetting
  the other yields a filter that is right on merge and wrong on every PR, or the reverse.

  THE FORMAT'S OWN PARSER DECIDES WHAT THE FILTER SAYS, and that is the whole design. This gate used to
  locate the blocks with hand-written regexes, and SIX CONSECUTIVE capstone rounds each found a defect in
  them: tab handling, `on:`-key anchoring, block scalars, YAML anchors, trailing comments, and optional
  quoting on list items. Two of those were fail-CLOSED on perfectly legal documents, which on a pre-push
  hook means a blocked push for no reason. `yq` was the oracle that measured every one of those defects,
  so the gate now uses it directly - the checker and its own oracle agree by construction, and the entire
  defect class is gone rather than iterated on. (Owner decision 2026-08-17, after a round that found two
  more parser defects.)

  yq IS REQUIRED, NOT OPTIONAL. A missing yq is a hard failure, never a skip: a gate that quietly stops
  checking certifies what it stopped looking at. It is NOT on the GitHub `windows-latest` image - measured
  against the runner-images manifest, which lists jq and not yq - so ci-scripts.yml installs it
  explicitly in the job that runs this suite, the same way it installs a pinned Pester rather than
  trusting whatever the image ships.

  WHAT IT DELIBERATELY DOES NOT CHECK. A second half - a "root vocabulary" check that parsed every suite's
  AST for string literals and required each named top-level directory to be covered or exempted - was
  DELETED by owner decision on this evidence: across five capstone rounds it produced four defects of its
  own against five real gaps found ONCE, all five now pinned by the table below. So a NEW tree asserted
  against by a NEW suite is not detected here; the suite's own assertion still reds locally, and the fix
  if it bites is a row in $Required, not a parser.
.PARAMETER RepoRoot
  Repo root, used only to locate the default workflow (default: this script's parent's parent).
.PARAMETER WorkflowPath
  The workflow whose paths: filters are checked (default: .github/workflows/ci-scripts.yml).
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

# Each entry names WHY it is required, so a later reader can re-derive it instead of trusting it.
# Removing a row is a DECISION, not an oversight.
$Required = [ordered]@{
    'scripts/**'                                        = 'the suite itself'
    'installer/_shared/**'                              = 'register-plugin.Tests.ps1 dot-sources installer/_shared/register-plugin.ps1'
    'clavity-dotnet/install/**'                         = 'test-suite-registration.Tests.ps1 pins clavity-install.Tests.ps1 by PATH and asserts the file exists'
    'clavity-dotnet/plugin/**'                          = 'agy-mark / agy-shield-lib / agy-seam-inject / agy-discipline-reaching suites all read hooks from this tree'
    'clavity-classic/plugin/**'                         = 'the byte-identical mirror of the above; plugin-hooks-payload compares both trees'
    'justfile'                                          = 'test-suite-registration reads the real justfile; assertion-strength-reminder pins its own fast-suite entry'
    'lefthook.yml'                                      = 'check-curate-in-progress asserts the pre-commit wiring lives there'
    'agy-autotrain/skills/agy-curate/SKILL.md'          = 'check-curate-in-progress asserts the marker path that skill ARMS is the one the guard READS'
    'agy-autotrain/knowledge/driver-cheatsheet.core.md' = 'check-cheatsheet-budget reads the canonical cheatsheet; listed narrowly so the high-churn observations inbox beside it does not trigger CI'
    'docs/agy-disciplines-marker-contract.md'           = 'check-injected-context resolves that token against the real repo root, so a rename reds the row'
    'build/members.json'                                = 'check-roster reads the real members manifest (validate-members.yml fires on it but does NOT run Pester)'
    '.github/workflows/ci-scripts.yml'                  = 'the filter must re-run the job it controls'
}

function Fail([string]$msg) { Write-Host "check-ci-filter-coverage: FAIL: $msg" -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $WorkflowPath)) { Fail "workflow not found at $WorkflowPath"; exit 1 }

$yq = Get-Command yq -ErrorAction SilentlyContinue
if (-not $yq) {
    Fail "``yq`` is not on PATH. This gate parses the workflow with yq rather than with hand-written regexes, so it cannot run without it - and skipping the check is not an option. This repo's portable toolchain ships yq; CI installs it in the dev-scripts job."
    exit 1
}

# `.on` RESOLVES CORRECTLY DESPITE `on` BEING A YAML 1.1 BOOLEAN. Verified against the yq in use
# (mikefarah/yq v4.50.1): `.on.push.paths` returns the 12 entries. yq v4 reads YAML 1.2, where the bare
# word `on` is a string. If a future yq regresses this, the trigger read below fails LOUDLY rather than
# silently returning nothing, because -e makes a missing path a non-zero exit.
function Get-TriggerPaths([string]$trigger) {
    $out = & $yq.Source -e ".on.$trigger.paths[]" $WorkflowPath 2>&1
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Lines = @($out | Where-Object { $_ -ne '' }) }
}

# NON-VACUITY, PER TRIGGER. An unparseable workflow, a renamed trigger, or a trigger with no paths must
# each be a hard failure naming its own cause - not a silent pass, and not twelve misleading "missing
# entry" lines that send the reader off to edit a filter which is fine.
#
# ONE BRANCH COVERS ALL THREE, and a separate "parsed as EMPTY" branch was DELETED as unreachable rather
# than left in place. MEASURED with `-e`: `paths: []` and a null `paths:` BOTH exit 1 with "no matches
# found", so there is no document where yq succeeds and returns zero entries. A mutation test confirmed
# the empty-count branch had no oracle - nothing could redden it - and dead code that advertises handling
# a case the parser forecloses is the same "certifies what it stopped checking" shape this gate exists to
# avoid.
$filters = [ordered]@{}
foreach ($trigger in @('push', 'pull_request')) {
    $r = Get-TriggerPaths $trigger
    if (-not $r.Ok) {
        Fail "could not read ``.on.$trigger.paths`` from $WorkflowPath - the trigger is missing, lists no paths, or the file does not parse. yq reported: $(($r.Lines -join ' ').Trim())"
        exit 1
    }
    $filters[$trigger] = $r.Lines
}

# CASE-SENSITIVE ON PURPOSE (`-cnotcontains`, not `-notcontains`). GitHub matches `paths:`
# case-sensitively, but PowerShell's `-notcontains` does not: `@('scripts/**') -notcontains 'Scripts/**'`
# is FALSE, so a capitalised entry would satisfy this gate while GitHub silently never fired the workflow.
# Measured both operators. That is the worst shape available - a green gate certifying a dead filter.
$problems = @()
foreach ($entry in $Required.Keys) {
    $missing = @($filters.Keys | Where-Object { $filters[$_] -cnotcontains $entry })
    if ($missing.Count -gt 0) {
        # NAMED TRIGGERS, NOT POSITIONS. The old message said "block(s) 1, 2", which made the reader count
        # blocks in the file to find out whether merge or PR was affected.
        $problems += "  MISSING required entry '$entry' from: $($missing -join ', ') - needed because: $($Required[$entry])"
    }
}

if ($problems.Count -gt 0) {
    Fail "ci-scripts.yml's paths: filter is missing an entry the scripts suite depends on."
    $problems | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "  Fix: add the entry under BOTH on.push.paths and on.pull_request.paths in $WorkflowPath. Removing a row from `$Required instead is a DECISION, not an oversight." -ForegroundColor Red
    exit 1
}

Write-Host "check-ci-filter-coverage: OK - all $($Required.Count) required entries present under both triggers ($(($filters.Keys | ForEach-Object { "$_=$($filters[$_].Count)" }) -join ', '))." -ForegroundColor Green
exit 0
