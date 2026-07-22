# docs-rationalize SP1 — user-facing list + drift-guard + voice-gap close — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the canonical 25-file user-facing doc list, a drift-guard check that validates it, and close the `docs-spec.md` voice-classification gap for the two clavity-classic evaluator docs — so SP2/SP3 build on a validated source of truth.

**Architecture:** A tracked plain-text list (`docs/user-facing-docs.txt`) is the single source of truth. A sibling check script (`scripts/check-user-facing-docs.ps1`, mirroring `check-member-docs.ps1`'s dot-sourceable-functions + main-guard shape) asserts (a) every listed path exists and (b) none is in `docs-spec.md`'s do-not-touch set — which, by `docs-spec.md`'s own in-table-XOR-excluded invariant (`docs-spec.md:94-95`), proves each listed doc is voiced; plus (c) a non-failing heuristic warning for a user-facing-shaped tracked doc absent from the list. `docs-spec.md` gains explicit user-facing evaluator voice entries for the two `clavity-classic/docs/*` docs (currently voiced only by the generic internal `<member>/docs/**` glob) and a one-line pointer to the list.

**Tech Stack:** PowerShell 5.1-compatible scripts, Pester v5 tests (`$TestDrive` scratch dirs), `just`, `lefthook`. This SP references only code that exists today: `scripts/check-member-docs.ps1`, `scripts/tests/check-member-docs.Tests.ps1`, `docs/docs-spec.md`, `justfile`, `lefthook.yml`, and the 25 target docs (all verified present 2026-07-22).

**Source spec:** `docs/superpowers/specs/2026-07-22-docs-rationalize-tool-design.md` (committed `8475a33`), §Scope, §Voice-contract coverage, §List storage and drift, §Testing.

---

## File Structure

- **Create** `docs/user-facing-docs.txt` — the 25 repo-relative paths, one per line, `#` comments. Sole source of truth read by the check (and later by SP2's `docs-audit.ps1`).
- **Create** `scripts/check-user-facing-docs.ps1` — dot-sourceable functions + `Invoke-UserFacingDocsCheck($repoRoot)` returning `{ExitCode; Failures; Warnings}`, plus a main-guard. One responsibility: validate the list against the tree + `docs-spec.md`'s do-not-touch set.
- **Create** `scripts/tests/check-user-facing-docs.Tests.ps1` — Pester v5, auto-discovered by `just test-scripts`.
- **Modify** `docs/docs-spec.md` — add two explicit user-facing evaluator voice rows for the clavity-classic docs; add a one-line pointer to `docs/user-facing-docs.txt`.
- **Modify** `justfile` — add a `check-user-facing-docs` recipe mirroring `check-member-docs`.
- **Modify** `lefthook.yml` — add the check to the **pre-push** `commands` (verified: `check-member-docs` is under `pre-push:` at line 26, NOT pre-commit; the pre-push header requires seconds-range jobs, which this check satisfies).

---

## Task 1: The user-facing list file

**Files:**
- Create: `docs/user-facing-docs.txt`

- [ ] **Step 1: Write the list file**

Create `docs/user-facing-docs.txt` with exactly this content (paths verified present 2026-07-22; the three buckets match the spec §Scope):

```text
# Canonical user-facing documentation list — the docs-rationalize tool's target.
# Source of truth read by scripts/check-user-facing-docs.ps1 and scripts/docs-audit.ps1 (SP2).
# One repo-relative path per line. Blank lines and lines starting with '#' are ignored.
# Narrower than docs-spec.md's full voice-table (which also voices CLAUDE.md, ROADMAP.md, internal docs).
# See docs/docs-spec.md and docs/superpowers/specs/2026-07-22-docs-rationalize-tool-design.md.

# --- End-user / operator / integrator (12) ---
README.md
agy-autotrain/README.md
commonmemory/README.md
clavity-classic/README.md
clavity-dotnet/README.md
ghidrust/README.md
clavity-classic/plugin/README.md
clavity-dotnet/plugin/README.md
ghidrust/plugin/README.md
clavity-classic/installer/clavity-classic-MANUAL-SETUP.md
clavity-classic/installer/clavity-classic-bridge-README-FIRST.md
SECURITY.md

# --- Contributor (10) ---
CONTRIBUTING.md
agy-autotrain/CONTRIBUTING.md
clavity-classic/CONTRIBUTING.md
clavity-dotnet/CONTRIBUTING.md
commonmemory/CONTRIBUTING.md
ghidrust/CONTRIBUTING.md
.github/pull_request_template.md
.github/ISSUE_TEMPLATE/bug_report.md
.github/ISSUE_TEMPLATE/feature_request.md
CODE_OF_CONDUCT.md

# --- Umbrella / evaluator (3) ---
docs/README.md
clavity-classic/docs/how-it-works.md
clavity-classic/docs/launching-and-driving-agy.md
```

- [ ] **Step 2: Verify every path resolves (sanity, pre-check)**

Run:
```bash
while read -r p; do case "$p" in ''|\#*) continue;; esac; [ -f "$p" ] && echo "OK $p" || echo "MISS $p"; done < docs/user-facing-docs.txt
```
Expected: 25 `OK` lines, zero `MISS`.

- [ ] **Step 3: Commit**

```bash
git add docs/user-facing-docs.txt
git commit -m "feat(docs-audit): add canonical user-facing-docs.txt (25 files)"
```

---

## Task 2: `docs-spec.md` — promote the two evaluator docs + add the list pointer

**Files:**
- Modify: `docs/docs-spec.md` (voice table ~line 28; a pointer near the list-authority note ~line 7)

**Context (verified 2026-07-22):** `docs-spec.md:21` voices `<member>/docs/**` as "design/protocol depth — runbooks, transport notes, research logs; research logs may be long." That glob already *matches* `clavity-classic/docs/how-it-works.md` and `launching-and-driving-agy.md`, but assigns them the **internal-depth** voice. The 25-list classifies them as **user-facing evaluator** docs. This task gives them an explicit, more-specific row so Stage-2 (SP3) applies the right voice. Exclusions/specific rows do not change the do-not-touch set, so the check in Task 3 is unaffected.

- [ ] **Step 1: Add two explicit voice rows to the Docs table**

In `docs/docs-spec.md`, in the `## Docs (audience → voice)` table, immediately AFTER the existing `<member>/docs/**` row (currently `docs/docs-spec.md:21`), add:

```markdown
| `clavity-classic/docs/how-it-works.md`, `clavity-classic/docs/launching-and-driving-agy.md` | **User-facing evaluator docs** — someone deciding whether/how to run clavity-classic. More specific than the generic `<member>/docs/**` internal-depth row above; keep them terse and scannable, not research-log-long | terse-technical |
```

- [ ] **Step 2: Add a one-line pointer to the list**

In `docs/docs-spec.md`, in the "Two authorities this file defers to" bullet list (currently `docs/docs-spec.md:6-8`), add a third bullet:

```markdown
- **The user-facing subset the docs-rationalize tool targets** — [`docs/user-facing-docs.txt`](user-facing-docs.txt) (25 files; a subset of this table's audience, validated by `scripts/check-user-facing-docs.ps1`).
```

- [ ] **Step 3: Verify the two docs are now named in docs-spec.md**

Run:
```bash
grep -c "how-it-works.md\|launching-and-driving-agy.md" docs/docs-spec.md
```
Expected: `2` or more (previously `0` — measured 2026-07-22).

- [ ] **Step 4: Commit**

```bash
git add docs/docs-spec.md
git commit -m "docs(spec): give the two clavity-classic evaluator docs an explicit user-facing voice + point to user-facing-docs.txt"
```

---

## Task 3: The drift-guard check script (TDD)

**Files:**
- Create: `scripts/check-user-facing-docs.ps1`
- Test: `scripts/tests/check-user-facing-docs.Tests.ps1`

**Design (mirrors `scripts/check-member-docs.ps1`):** dot-sourceable functions; a `Read-DocList` parser; a `Test-IsDoNotTouch` matcher encoding `docs-spec.md`'s do-not-touch set (lines 53-89) as anchored regexes; a `Test-HasVoiceEntry` matcher encoding `docs-spec.md`'s voice-table shapes (lines 14-28) as anchored regexes; both are pinned by tests, exactly as `check-member-docs.ps1:18` pins the release regex "byte-identical on purpose". `Invoke-UserFacingDocsCheck($repoRoot, [string[]]$TrackedDocs = $null)` returns `{ExitCode; Failures; Warnings}`; a main-guard runs it only when invoked directly. The `$TrackedDocs` parameter is a **test seam** (mirrors SP2's parameter-injected philosophy): production leaves it `$null` and the check derives the tracked-doc list from `git ls-files` (guarded — see below); tests inject a fixed array so the (c) heuristic and the git-absent path are deterministic. Check semantics:
- (a) every listed path exists → else Failure.
- (b) each listed path (b1) does NOT match a do-not-touch glob AND (b2) DOES match a known voice-table shape → else Failure. **Both halves are required:** `docs-spec.md:94-95` states the in-table-XOR-excluded convention but explicitly allows a "neither" spec-gap case ("If a pass encounters one that is neither, that is a spec gap — report it rather than guessing"), so the check must *positively* confirm a voice-table shape (b2), not merely infer voicing from not-excluded. (b1) is the safety half (never audit a do-not-touch doc); (b2) is the voice-coverage half the spec's §List-storage (b) requires.
- (c) a tracked `.md` matching a user-facing *shape* that is NOT in the list and NOT do-not-touch → Warning (non-failing; a maintainer confirms — it cannot be a `docs-spec.md` cross-check).
- Vacuous-pass guard: an empty/whitespace-only list → Failure ("refusing to pass on an empty list").
- **git guard:** the (c) heuristic needs the tracked-doc set. Under `$ErrorActionPreference='Stop'`, a bare `& git ...` when git is absent throws a terminating `CommandNotFoundException` that bypasses `$LASTEXITCODE` and crashes the run — so the derivation is gated on `Get-Command git` AND wrapped in try/catch, and any failure leaves `$tracked = $null` so (c) is skipped silently (the check must fail only on real drift, never on environment).

- [ ] **Step 1: Write the failing tests**

Create `scripts/tests/check-user-facing-docs.Tests.ps1`:

```powershell
BeforeAll {
    # Dot-source: defines functions, does NOT run main (guarded by InvocationName -eq '.').
    . ([System.IO.Path]::Combine($PSScriptRoot, '..', 'check-user-facing-docs.ps1'))

    function New-ScratchListRepo {
        param([string[]]$ListLines, [hashtable]$Files = @{})
        $repoRoot = Join-Path $TestDrive ([System.Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $repoRoot 'docs') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repoRoot 'docs/user-facing-docs.txt') -Value ($ListLines -join "`n")
        foreach ($rel in $Files.Keys) {
            $abs = Join-Path $repoRoot $rel
            New-Item -ItemType Directory -Path (Split-Path $abs -Parent) -Force | Out-Null
            Set-Content -LiteralPath $abs -Value $Files[$rel]
        }
        return $repoRoot
    }
}

Describe 'Read-DocList' {
    It 'ignores comments and blank lines, returns trimmed paths' {
        $repo = New-ScratchListRepo -ListLines @('# hdr', '', 'README.md', '  SECURITY.md  ', '# tail')
        $paths = Read-DocList (Join-Path $repo 'docs/user-facing-docs.txt')
        $paths | Should -Be @('README.md', 'SECURITY.md')
    }
}

Describe 'Test-IsDoNotTouch' {
    It 'flags a SKILL.md at any depth' {
        Test-IsDoNotTouch 'clavity-classic/agy-mcp-bridge/SKILL.md' | Should -BeTrue
        Test-IsDoNotTouch 'x/plugin/skills/foo/SKILL.md'            | Should -BeTrue
    }
    It 'flags a CHANGELOG, a knowledge file, an archive doc, a fixtures README, and docs-spec itself' {
        Test-IsDoNotTouch 'clavity-dotnet/CHANGELOG.md'                 | Should -BeTrue
        Test-IsDoNotTouch 'agy-autotrain/knowledge/agy-observations.md' | Should -BeTrue
        Test-IsDoNotTouch 'clavity-classic/docs/archive/old.md'         | Should -BeTrue
        Test-IsDoNotTouch 'ghidrust/crates/x/tests/fixtures/README.md'  | Should -BeTrue
        Test-IsDoNotTouch 'docs/docs-spec.md'                           | Should -BeTrue
    }
    It 'does NOT flag any of the 25 user-facing shapes' {
        foreach ($p in @('README.md','clavity-classic/plugin/README.md','clavity-dotnet/CONTRIBUTING.md',
                         'SECURITY.md','CODE_OF_CONDUCT.md','.github/ISSUE_TEMPLATE/bug_report.md',
                         'docs/README.md','clavity-classic/docs/how-it-works.md',
                         'clavity-classic/installer/clavity-classic-MANUAL-SETUP.md')) {
            Test-IsDoNotTouch $p | Should -BeFalse -Because "$p is user-facing"
        }
    }
}

Describe 'Test-HasVoiceEntry' {
    It 'matches every one of the 25 user-facing shapes' {
        foreach ($p in @('README.md','agy-autotrain/README.md','clavity-classic/plugin/README.md',
                         'CONTRIBUTING.md','ghidrust/CONTRIBUTING.md','SECURITY.md','CODE_OF_CONDUCT.md',
                         '.github/pull_request_template.md','.github/ISSUE_TEMPLATE/feature_request.md',
                         'docs/README.md','clavity-classic/docs/how-it-works.md',
                         'clavity-classic/docs/launching-and-driving-agy.md',
                         'clavity-classic/installer/clavity-classic-bridge-README-FIRST.md')) {
            Test-HasVoiceEntry $p | Should -BeTrue -Because "$p is voiced in docs-spec.md's table"
        }
    }
    It 'does NOT match an unvoiced spec-gap path' {
        Test-HasVoiceEntry 'weird/nested/thing.md' | Should -BeFalse
    }
}

Describe 'Invoke-UserFacingDocsCheck' {
    It 'PASSES when every listed doc exists and none is do-not-touch' {
        $repo = New-ScratchListRepo -ListLines @('README.md','SECURITY.md') -Files @{ 'README.md'='# r'; 'SECURITY.md'='# s' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.Failures | Should -Be @()
        $r.ExitCode | Should -Be 0
    }
    It 'FAILS (a): a listed doc that does not exist' {
        $repo = New-ScratchListRepo -ListLines @('README.md','GONE.md') -Files @{ 'README.md'='# r' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'GONE.md.*does not exist'
    }
    It 'FAILS (b): a listed doc that is in the do-not-touch set' {
        $repo = New-ScratchListRepo -ListLines @('README.md','docs/docs-spec.md') -Files @{ 'README.md'='# r'; 'docs/docs-spec.md'='# spec' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'docs-spec.md.*do-not-touch'
    }
    It 'FAILS on an empty list rather than passing vacuously' {
        $repo = New-ScratchListRepo -ListLines @('# only a comment')
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'empty'
    }
    It 'FAILS (b2): a listed doc that exists and is not do-not-touch but matches no voice shape' {
        $repo = New-ScratchListRepo -ListLines @('README.md','weird/nested/thing.md') `
            -Files @{ 'README.md'='# r'; 'weird/nested/thing.md'='# w' }
        $r = Invoke-UserFacingDocsCheck $repo
        $r.ExitCode | Should -Be 1
        ($r.Failures -join "`n") | Should -Match 'weird/nested/thing.md.*spec gap'
    }
    It '(c) heuristic: warns (does NOT fail) on an unlisted user-facing-shaped tracked doc' {
        $repo = New-ScratchListRepo -ListLines @('README.md') -Files @{ 'README.md'='# r' }
        # Inject the tracked-doc set via the seam so the heuristic is deterministic (no git needed).
        $r = Invoke-UserFacingDocsCheck $repo -TrackedDocs @('README.md','ghidrust/CONTRIBUTING.md')
        $r.ExitCode  | Should -Be 0
        ($r.Warnings -join "`n") | Should -Match 'ghidrust/CONTRIBUTING.md.*absent'
    }
    It '(c) heuristic: a do-not-touch tracked doc absent from the list is NOT warned' {
        $repo = New-ScratchListRepo -ListLines @('README.md') -Files @{ 'README.md'='# r' }
        $r = Invoke-UserFacingDocsCheck $repo -TrackedDocs @('README.md','x/plugin/skills/foo/SKILL.md')
        $r.Warnings | Should -Be @()
    }
    It 'does NOT crash when git is unavailable / not a repo (TrackedDocs left to git in a non-repo TestDrive)' {
        $repo = New-ScratchListRepo -ListLines @('README.md') -Files @{ 'README.md'='# r' }
        { Invoke-UserFacingDocsCheck $repo } | Should -Not -Throw
        (Invoke-UserFacingDocsCheck $repo).ExitCode | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-user-facing-docs.Tests.ps1 -Output Detailed"`
Expected: FAIL — `check-user-facing-docs.ps1` does not exist / functions undefined.

- [ ] **Step 3: Write the check script**

Create `scripts/check-user-facing-docs.ps1`:

```powershell
#requires -Version 5.1
# Fail (exit 1) if docs/user-facing-docs.txt lists a path that does not exist, or that docs-spec.md
# classifies do-not-touch (a doc the docs-rationalize tool must never audit). WARN (non-failing) if a
# tracked user-facing-shaped .md is absent from the list. Mirrors check-member-docs.ps1's shape.
#
# The do-not-touch globs below mirror docs/docs-spec.md's "Do-not-touch" list (its lines 53-89) and are
# pinned by Pester tests. By docs-spec.md's in-table-XOR-excluded invariant (its lines 94-95), a listed
# doc that is NOT do-not-touch is necessarily voiced — so (b) is the voice-coverage guard without parsing
# the voice table.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

# Anchored regexes over a repo-relative, forward-slash path. Each maps to a docs-spec.md do-not-touch bullet.
$script:DoNotTouchPatterns = @(
    '(?i)\.(rs|cs|ps1|sh|yml|iss)$',          # code/script/workflow files
    '(?i)(^|/)LICENSE$',                       # legal text
    '(?i)(^|/)CHANGELOG\.md$',                 # release-injected
    '(?i)(^|/)knowledge/',                     # driver-owned SEED + learning-loop working files
    '(?i)(^|/)SKILL\.md$',                     # behavioural contracts
    '(?i)(^|/)docs/archive/',                  # frozen historical
    '(?i)(^|/)docs/superpowers/',              # working artifacts
    '(?i)(^|/)\.clavity/',                     # working artifacts
    '(?i)(^|/)tests/fixtures/',                # test data
    '(?i)(^|/)\.venv/|(^|/)node_modules/',     # vendored
    '(?i)^scripts/drain-knowledge-prompt\.md$',# a prompt, functionally code
    '(?i)^seed/golden-header\.md$',            # compiled SEED
    '(?i)^commonmemory/rules/commonmemory\.md$',                       # agy rule file
    '(?i)^agy-autotrain/verify/.*\.md$',                              # probe harness
    '(?i)^agy-autotrain/docs/fix-the-tool-backlog/',                  # generated append-only
    '(?i)(^|/)agy-mcp-bridge/VENDORED-FROM\.md$',                     # vendored provenance
    '(?i)^docs/(agy-assumptions|agy-capabilities)\.md$',             # pointer stubs
    '(?i)^clavity-classic/docs/agy-test-suite\.md$',                 # pointer stub
    '(?i)^docs/docs-spec\.md$',               # this file's own governing contract
    '(?i)^installer/_shared/register-plugin-hash\.iss$',            # generated (also caught by .iss)
    '(?i)(^|/)installer/marketplace\.install\.json$'               # generated
)

# A tracked doc "looks user-facing" if its filename is one of these (the (c) heuristic surface).
$script:UserFacingShapes = @(
    '(?i)(^|/)README\.md$', '(?i)(^|/)CONTRIBUTING\.md$', '(?i)^SECURITY\.md$',
    '(?i)^CODE_OF_CONDUCT\.md$', '(?i)^\.github/(pull_request_template|ISSUE_TEMPLATE/.+)\.md$'
)

# Voice-table shapes from docs-spec.md's "Docs (audience -> voice)" table (its lines 14-28). A listed doc
# MUST match one of these (b2) - positive voice confirmation, since docs-spec.md:94-95's XOR convention
# allows a "neither" spec-gap case and is therefore not a guarantee. Test-pinned like the do-not-touch set.
$script:VoiceEntryPatterns = @(
    '(?i)^README\.md$',                        # root README
    '(?i)^[^/]+/README\.md$',                   # <member>/README.md
    '(?i)^[^/]+/plugin/README\.md$',            # <member>/plugin/README.md
    '(?i)^CONTRIBUTING\.md$',                   # umbrella CONTRIBUTING
    '(?i)^[^/]+/CONTRIBUTING\.md$',             # <member>/CONTRIBUTING.md
    '(?i)^SECURITY\.md$',
    '(?i)^CODE_OF_CONDUCT\.md$',
    '(?i)^\.github/pull_request_template\.md$',
    '(?i)^\.github/ISSUE_TEMPLATE/.+\.md$',
    '(?i)^docs/.+\.md$',                        # docs/** (umbrella)
    '(?i)^[^/]+/docs/.+\.md$',                  # <member>/docs/** (incl. the two clavity-classic evaluator docs)
    '(?i)^clavity-classic/installer/.*(MANUAL-SETUP|README-FIRST)\.md$'  # installer operator docs (docs-spec.md:28)
)

function Read-DocList([string]$path) {
    # Contract: returns the trimmed, comment/blank-stripped list of repo-relative paths.
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $out = New-Object System.Collections.ArrayList
    foreach ($line in (Get-Content -LiteralPath $path)) {
        $t = $line.Trim()
        if ($t -eq '' -or $t.StartsWith('#')) { continue }
        [void]$out.Add(($t -replace '\\', '/'))
    }
    return $out.ToArray()
}

function Test-IsDoNotTouch([string]$relPath) {
    $p = $relPath -replace '\\', '/'
    foreach ($rx in $script:DoNotTouchPatterns) { if ($p -match $rx) { return $true } }
    return $false
}

function Test-LooksUserFacing([string]$relPath) {
    $p = $relPath -replace '\\', '/'
    foreach ($rx in $script:UserFacingShapes) { if ($p -match $rx) { return $true } }
    return $false
}

function Test-HasVoiceEntry([string]$relPath) {
    $p = $relPath -replace '\\', '/'
    foreach ($rx in $script:VoiceEntryPatterns) { if ($p -match $rx) { return $true } }
    return $false
}

function Get-TrackedMarkdown([string]$repoRoot) {
    # Returns tracked *.md paths, or $null if git is unavailable / this is not a repo. Guarded because,
    # under ErrorActionPreference='Stop', a bare `& git` with git absent throws CommandNotFoundException
    # (a terminating error that bypasses $LASTEXITCODE); the (c) heuristic must degrade to a silent skip.
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    try {
        Push-Location $repoRoot
        $out = & git ls-files '*.md' 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return @($out | ForEach-Object { $_ -replace '\\', '/' })
    } catch { return $null }
    finally { Pop-Location }
}

function Invoke-UserFacingDocsCheck([string]$repoRoot, [string[]]$TrackedDocs = $null) {
    $failed   = New-Object System.Collections.ArrayList
    $warned   = New-Object System.Collections.ArrayList
    $listPath = Join-Path $repoRoot 'docs/user-facing-docs.txt'

    if (-not (Test-Path -LiteralPath $listPath)) {
        [void]$failed.Add("docs/user-facing-docs.txt not found at $listPath")
        return [PSCustomObject]@{ ExitCode = 1; Failures = $failed.ToArray(); Warnings = @() }
    }

    $listed = Read-DocList $listPath
    if ($listed.Count -eq 0) {
        [void]$failed.Add('docs/user-facing-docs.txt is empty (all comments/blank) - refusing to pass vacuously.')
        return [PSCustomObject]@{ ExitCode = 1; Failures = $failed.ToArray(); Warnings = @() }
    }

    foreach ($rel in $listed) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $rel))) {
            [void]$failed.Add("listed doc '$rel' does not exist. Fix docs/user-facing-docs.txt.")
        } elseif (Test-IsDoNotTouch $rel) {
            [void]$failed.Add("listed doc '$rel' is in docs-spec.md's do-not-touch set - a docs-rationalize target must never be do-not-touch. Remove it from docs/user-facing-docs.txt.")
        } elseif (-not (Test-HasVoiceEntry $rel)) {
            [void]$failed.Add("listed doc '$rel' matches no docs-spec.md voice-table shape - it is a spec gap (unvoiced). Add a voice row in docs/docs-spec.md or remove it from the list.")
        }
    }

    # (c) heuristic: a tracked user-facing-shaped .md absent from the list. $TrackedDocs is a test seam;
    # production derives it from git (guarded). $null => skip silently (git unavailable / not a repo).
    $tracked = if ($null -ne $TrackedDocs) { $TrackedDocs } else { Get-TrackedMarkdown $repoRoot }
    if ($tracked) {
        $listedSet = @{}; foreach ($r in $listed) { $listedSet[$r] = $true }
        foreach ($t in $tracked) {
            $tn = $t -replace '\\', '/'
            if ($listedSet.ContainsKey($tn)) { continue }
            if (Test-IsDoNotTouch $tn) { continue }
            if (Test-LooksUserFacing $tn) {
                [void]$warned.Add("tracked doc '$tn' looks user-facing but is absent from docs/user-facing-docs.txt (heuristic - a maintainer confirms).")
            }
        }
    }

    $code = if ($failed.Count -gt 0) { 1 } else { 0 }
    return [PSCustomObject]@{ ExitCode = $code; Failures = $failed.ToArray(); Warnings = $warned.ToArray() }
}

# main-guard: run only when invoked directly (NOT when dot-sourced by Pester - InvocationName is '.').
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-UserFacingDocsCheck $root
    $result.Warnings | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    if ($result.ExitCode -ne 0) {
        Write-Host 'user-facing-docs gate FAILED:' -ForegroundColor Red
        $result.Failures | ForEach-Object { Write-Host "  - $_" }
        Write-Error 'docs/user-facing-docs.txt has a missing or do-not-touch entry.'
        exit 1
    }
    Write-Host "user-facing docs ok ($((Read-DocList (Join-Path $root 'docs/user-facing-docs.txt')).Count) listed; all exist; none do-not-touch)"
    exit 0
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-user-facing-docs.Tests.ps1 -Output Detailed"`
Expected: PASS — all Describe blocks green.

- [ ] **Step 5: Run the check against the REAL repo**

Run: `pwsh -File scripts/check-user-facing-docs.ps1`
Expected: exit 0, prints `user-facing docs ok (25 listed; all exist; none do-not-touch)`. Any `!` warnings are heuristic — inspect but they do not fail the gate.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-user-facing-docs.ps1 scripts/tests/check-user-facing-docs.Tests.ps1
git commit -m "feat(docs-audit): add check-user-facing-docs drift guard (exists + not-do-not-touch + heuristic warn)"
```

---

## Task 4: Wire the check into `just` and `lefthook`

**Files:**
- Modify: `justfile` (after the `check-member-docs` recipe, ~line 35)
- Modify: `lefthook.yml` (**pre-push** `commands`, alongside `member-docs:` at line 25-26 — verified NOT pre-commit)

- [ ] **Step 1: Add the `just` recipe**

In `justfile`, immediately AFTER the `check-member-docs` recipe (currently ends at `justfile:35`), add:

```make
# Verify docs/user-facing-docs.txt lists only existing, non-do-not-touch docs (docs-rationalize target).
check-user-facing-docs:
    pwsh -File scripts/check-user-facing-docs.ps1
```

- [ ] **Step 2: Add the lefthook pre-push command**

In `lefthook.yml`, in the **`pre-push.commands`** block that holds `member-docs:` / `run: just check-member-docs` (lines 25-26 — this check is a `pre-push` job, NOT pre-commit; the pre-commit block holds only `ruff`), add a sibling command right after `member-docs:` (match the surrounding 4-space key indent exactly):

```yaml
    user-facing-docs:
      run: just check-user-facing-docs
```

The pre-push header (lefthook.yml:11-18) mandates seconds-range jobs (git holds an SSH connection open); this check is Test-Path + regex over 25 paths + one `git ls-files`, well under a second, so it belongs here.

- [ ] **Step 3: Verify both wirings**

Run:
```bash
just check-user-facing-docs && echo "--- lefthook ---" && grep -A1 "check-user-facing-docs" lefthook.yml
```
Expected: the check prints its ok line and exits 0; grep shows the lefthook command.

- [ ] **Step 4: Run the full script test suite (nothing regressed)**

Run: `just test-scripts`
Expected: all `scripts/tests/*.Tests.ps1` pass, including the new `check-user-facing-docs.Tests.ps1` (auto-discovered).

- [ ] **Step 5: Commit**

```bash
git add justfile lefthook.yml
git commit -m "chore(docs-audit): wire check-user-facing-docs into just + lefthook pre-commit"
```

---

## Self-Review

**1. Spec coverage (against §Scope, §Voice-contract coverage, §List storage and drift, §Testing):**
- 25-doc list → Task 1. ✓
- Existence check (a) → Task 3 (Invoke-UserFacingDocsCheck existence loop). ✓
- Voice-coverage + safety (b) → Task 3: (b1) `Test-IsDoNotTouch` (never audit a do-not-touch doc) AND (b2) `Test-HasVoiceEntry` (positive voice-table confirmation — NOT the aspirational docs-spec.md:94-95 invariant, which admits a "neither" spec-gap case). ✓
- Heuristic (c) drift warning → Task 3 (`Test-LooksUserFacing` + `Get-TrackedMarkdown`, git-guarded, `-TrackedDocs` test seam). ✓
- docs-spec.md voice entries for the two clavity-classic docs → Task 2 (as a voice *promotion* off the generic `<member>/docs/**` glob — grounded correction to the spec's "names neither"). ✓
- docs-spec.md list pointer → Task 2. ✓
- Vacuous-pass guard → Task 3 (empty-list Failure), mirroring check-member-docs.ps1:126. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows complete code; every command has an expected result. ✓

**3. Type consistency:** `Invoke-UserFacingDocsCheck` returns `{ExitCode; Failures; Warnings}` consistently across script and tests; `Read-DocList`, `Test-IsDoNotTouch`, `Test-LooksUserFacing` signatures match their call sites. ✓

## Exhaustiveness self-audit

- **Contracts pinned:** list format (one path/line, `#` comments, `\`→`/` normalized); check output shape `{ExitCode:int; Failures:string[]; Warnings:string[]}`; do-not-touch regex set mirrors docs-spec.md:53-89 and is test-pinned.
- **Placeholders / TBD:** none.
- **Edges covered:** missing list file; empty (comment-only) list; a listed path that is absent; a listed path that is do-not-touch (docs-spec.md itself, a SKILL.md, a CHANGELOG); a listed path that is unvoiced (b2 spec-gap); the (c) heuristic warning (via `-TrackedDocs` seam) AND a do-not-touch tracked doc correctly NOT warned; git-unavailable / non-repo (heuristic skips silently via the `Get-Command git` + try/catch guard — the `CommandNotFoundException`-under-Stop crash agy caught); path-separator normalization; dot-source vs direct-invoke main-guard.
- **Requirements mapped:** every §Scope/§Voice/§List-storage/§Testing requirement maps to a Task above (see Self-Review §1).
- **Known non-goals (resolved elsewhere):** `$script:DoNotTouchPatterns` and `$script:VoiceEntryPatterns` are *pinned mirrors* of docs-spec.md's do-not-touch list and voice table, not a live parse of the markdown — an intentional single-responsibility choice (both sets are stable, and pinning tests catch drift). If docs-spec.md's do-not-touch set or voice table changes, update the corresponding pattern array and its test in the same commit. This is the one deliberate second-source; it trades a live parse of human-written markdown (fragile) for a test-locked mirror.
- **Deferred to SP2/SP3 (not this plan):** the `claude -p` audit, the log, the punch-list merge (SP2); the SKILL.md Stage-2 rewrite (SP3). SP2's detailed plan is authored once SP1 merges (its contracts live in the GREEN spec §Stage 1/§Testing); SP3's once SP2 merges.
