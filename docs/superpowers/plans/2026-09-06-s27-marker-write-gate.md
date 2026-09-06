# ROADMAP §27 — Marker-Write Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refuse to write a discipline's completion marker unless that discipline's ledger already records the sha being marked.

**Architecture:** A new sourced helper, `agy-ledger-lib.sh`, carries a ledger reader that locates a sha positionally in the ledger's range column. `agy-mark.sh`'s `head)` arm consults it before writing, and refuses with a diagnostic naming both the fix and the escape. The gate applies to a discipline **only if** `docs/<discipline>-ledger.md` exists, so it is inert in every repository that does not keep such ledgers — which is every repository but this one.

**Tech Stack:** bash (POSIX-ish, bash-only constructs already used by `agy-mark.sh`), `awk`, `git`, Pester 5 for tests, `just` for the runners.

**Spec:** `docs/superpowers/specs/2026-09-03-marker-write-gate-design.md` — reviewed over five AGY-AFTER rounds, closed `cap-reached` (NOT green), owner-shipped 2026-09-06. Read its `## TERMINAL DISPOSITION` before trusting any design claim here.

---

## Before you start: five facts about this repository that will bite you

1. **`agy-mark.sh` is a byte-identical pair.** `clavity-dotnet/plugin/hooks/agy-mark.sh` and `clavity-classic/plugin/hooks/agy-mark.sh` are 358 lines each and `cmp`-identical. `scripts/check-seed-artifacts-synced.sh` compares them by **discovery** (`find hooks skills knowledge -type f`, see its `:15-16`), so a new file in one half without the other **fails the gate automatically** — you do not have to enrol it anywhere. Every edit lands in **both halves in the same commit**.
2. **Pester suite registration is an explicit list, not a glob.** `justfile:108` (`test-scripts-slow`) names every slow suite by path. A new suite that is not added there is never run by `just test-scripts-slow` — this repository's "orphaned tests" class (ROADMAP §36).
3. **`scripts/tests/_partition.md` states a test COUNT per suite and that count is MECHANICALLY ENFORCED** by `scripts/tests/test-suite-registration.Tests.ps1:185` (`'every _partition.md row states the CURRENT test count for its suite'`). Add a test, update the row, or the gate goes red. `agy-mark.Tests.ps1`'s row is `_partition.md:677` and currently says **36 tests**.
4. **`scripts/README.md` does NOT need an entry.** `scripts/tests/scripts-readme-inventory.Tests.ps1:17` says "Top-level scripts only. Subdirectories (tests/, hooks/, lib/) have their own sections and are not" — the new helper lives in `plugin/hooks/`, so it is out of scope.
5. **`.clavity/` is gitignored.** Never `git add` anything under it. Stage explicit paths; never `git add -A`.

## File Structure

| File | Responsibility |
|---|---|
| `clavity-dotnet/plugin/hooks/agy-ledger-lib.sh` **(new)** | The ledger reader. Resolves the ledger path by convention, scans candidate records, resolves endpoints through git, answers FOUND/ABSENT. Sourced, never executed. |
| `clavity-classic/plugin/hooks/agy-ledger-lib.sh` **(new)** | Byte-identical twin. |
| `scripts/tests/agy-ledger-lib.Tests.ps1` **(new)** | Pester suite for the reader, run against throwaway git repos. |
| `clavity-dotnet/plugin/hooks/agy-mark.sh` **(modify)** | The `head)` arm gains the gate and the `--gate-override` flag. |
| `clavity-classic/plugin/hooks/agy-mark.sh` **(modify)** | Byte-identical twin. |
| `scripts/tests/agy-mark.Tests.ps1` **(modify)** | Rows for the new refusal path and the override. |
| `scripts/tests/_partition.md` **(modify)** | Counts for the changed and new suites. |
| `justfile` **(modify)** | Register the new suite in `test-scripts-slow`. |
| `clavity-{dotnet,classic}/plugin/skills/agy-capstone/SKILL.md` **(modify)** | State the row-before-marker ordering. |
| `clavity-{dotnet,classic}/plugin/skills/agy-test-audit/SKILL.md` **(modify)** | Same. |
| `scripts/tests/check-agy-discipline-skills.Tests.ps1` **(modify)** | Pin the ordering sentence in both halves mechanically, over a DISCOVERED roster of ledger-owning disciplines. |
| `docs/agy-disciplines-marker-contract.md` **(modify)** | Record the new refusal condition in the declared single source of truth. |

---

## Task 1: Teach the skills the ordering, and pin it mechanically

**This task lands FIRST and the order is load-bearing.** Panel round 3 asked which single stopping point would leave the repository worse than never having started, and named this one: a gate that arrives before the skills teach row-before-marker refuses every agent still following the old, unspecified ordering. Prose landing early is harmless; the gate landing early is not.

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md:375`
- Modify: `clavity-classic/plugin/skills/agy-capstone/SKILL.md` (same line content)
- Modify: `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md:331`
- Modify: `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` (same line content)
- Test: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

⚠ **`scripts/check-agy-discipline-skills.ps1` itself is NOT modified.** An earlier draft listed it here and then staged it in the commit step without any step editing it — a phantom requirement that would stall an implementer looking for the step they missed. The enforcement lives in the `.Tests.ps1`, which is where this repository's other cross-half assertions live.

- [ ] **Step 1: Read the four skill files and confirm the anchor text still exists**

Run:
```bash
grep -n 'Record the round in `docs/agy-capstone-ledger.md` before declaring the plan complete' \
  clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md
grep -n 'Record the audit in `docs/agy-test-audit-ledger.md` before this run may COMPLETE' \
  clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md
```
Expected: four hits, one per file. **If any is missing, STOP and report `STATE_MISMATCH: <what>` rather than adapting** — the anchor moved and this plan's assumptions need re-checking.

- [ ] **Step 2: Write the failing test**

Add to `scripts/tests/check-agy-discipline-skills.Tests.ps1`, inside the existing top-level `Describe`:

```powershell
    Context 'the row-before-marker ordering (ROADMAP section 27)' {
        # MECHANICAL, not a process promise. The incomplete fold is this repository's dominant defect
        # class, and "edit the skill in both halves" is exactly the promise that gets kept in one half.
        #
        # THE ROSTER IS DISCOVERED, NEVER HARDCODED, and a panel round caught the first draft of this
        # test doing the opposite. A literal @('agy-capstone','agy-test-audit') array would be true only
        # today: the next discipline to adopt a ledger goes unchecked until a human remembers to append
        # it - which is the exact enumeration failure this test was written to eliminate, reintroduced
        # one layer up. Discovery is also what makes the test agree with the GATE, which decides
        # applicability the same way: by whether docs/<discipline>-ledger.md exists.
        $repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $ledgerOwners = @(
            Get-ChildItem -LiteralPath (Join-Path $repo 'docs') -Filter '*-ledger.md' -File |
                ForEach-Object { $_.BaseName -replace '-ledger$', '' }
        )
        # 🔴 PESTER 5 SCOPE, AND IT IS THE REASON FOR -ForEach. Variables assigned during DISCOVERY are
        # NOT visible inside an It body, which runs in a later phase. MEASURED during execution: a draft
        # that read the discovery variables directly inside the It failed all five rows - the roster
        # counted 0 and every path resolved to '<repo>//plugin/skills//SKILL.md'. Hand the data to each
        # row through -ForEach, the idiom the sibling suites already use (agy-mark.Tests.ps1:141), where
        # a hashtable's keys bind as bare variables in the body.
        $s27Rows = @(
            foreach ($h in @('clavity-dotnet', 'clavity-classic')) {
                foreach ($s in $ledgerOwners) { @{ Half = $h; Skill = $s } }
            }
        )

        # A discovery that finds nothing would make every row below vacuous, so fail loudly instead.
        It 'discovers at least one ledger-owning discipline' -ForEach @(@{ Found = $ledgerOwners.Count }) {
            $Found | Should -BeGreaterThan 0
        }

        It '<Skill> in <Half> states that the ledger row precedes the marker write' -ForEach $s27Rows {
            $p = Join-Path $script:RepoRoot "$Half/plugin/skills/$Skill/SKILL.md"
            Test-Path -LiteralPath $p | Should -BeTrue
            $text = Get-Content -LiteralPath $p -Raw
            # Assert the BEHAVIOUR is stated, not one exact sentence: the row must be described
            # as preceding the marker write, and the marker gate must be named as the reason.
            # PowerShell's -Match is case-INSENSITIVE (-cmatch is the case-sensitive one), so
            # these match the uppercase heading in Step 4's paragraph. Both needles must sit on
            # ONE line for the second pattern to hold - Step 4's text is written that way.
            $text | Should -Match 'BEFORE THE MARKER'
            $text | Should -Match 'agy-mark\.sh[^\r\n]*refuses'
        }
    }
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed -CI"
```
Expected: **FAIL**, 4 new tests red with `Expected regular expression 'BEFORE the marker' to match ...`. The pre-existing tests stay green.

- [ ] **Step 4: Add the ordering paragraph to all four skill files**

🔴 **EVERY SHIPPED `SKILL.md` IS ASCII-ONLY, AND THE LINTER ENFORCES IT.**
`scripts/check-agy-discipline-skills.ps1:130` fails with `contains N non-ASCII char(s)`. MEASURED during
execution: a first draft of this paragraph used a red-circle emoji and a `§` sign — **3 non-ASCII
characters per file** (the emoji is a surrogate PAIR, counting 2) — and reddened **5 pre-existing rows**
in a suite whose own new rows were all green. **Write no emoji, no `§`, no en dash, no curly quote.** The
rest of this plan uses those characters freely in its prose; the SKILL.md text is the one place they are
forbidden.

In **each** of the four `SKILL.md` files, immediately after the existing ledger-row bullet
(`agy-capstone/SKILL.md:375`, `agy-test-audit/SKILL.md:331`), insert this paragraph **verbatim and
identically**. Indent it two spaces in `agy-capstone` (it continues a bullet) and flush-left in
`agy-test-audit` (it follows a paragraph):

```markdown
**WRITE THIS ROW BEFORE THE MARKER, NOT AFTER.** Since ROADMAP section 27 the marker writer
`agy-mark.sh` **refuses** to write a completion marker whose sha the ledger does not already record.
The ordering was always the convention; it is now a precondition, and reversing it makes the writer
refuse a run that did everything else correctly. If you hit that refusal, the fix is to append the
row and re-run the write - not to bypass the gate.
```

⚠ **The two halves must be byte-identical.** Write the text once and copy the file, or run
`scripts/check-seed-artifacts-synced.sh` (Step 6) until it is silent.

⚠ **These files have MIXED line endings** — measured, `agy-test-audit/SKILL.md` has CRLF at the anchor
while the capstone anchor is LF. A scripted insert that hardcodes `\n` silently matches nothing in one
file and succeeds in the other. Detect the terminator that follows the anchor and reuse it.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed -CI"
```
Expected: **PASS**, `Tests Passed: 90` (was 85 — five new rows: two ledger-owning disciplines × two plugin halves, **plus** the `discovers at least one ledger-owning discipline` guard). 🔴 **Do not take 90 on trust — it is DERIVED from what the discovery finds.** If a third `docs/*-ledger.md` exists by the time you run this, the count is 92, and the number to write into `_partition.md` in Step 7 is whatever this run actually reports. **Read the number; do not assume it.**

🔴 **If the line reads `Tests Passed: 0`, or there is no `Tests Passed:` line at all, that is an ABORTED run, not a pass** — a `.ps1` parse error produces exactly that. Re-read the file and fix the syntax before continuing.

- [ ] **Step 6: Verify the pair is still byte-identical**

Run:
```bash
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
```
Expected: no `SEED-DRIFT` output, `exit=0`.

- [ ] **Step 7: Update the `_partition.md` count for the changed suite**

`scripts/tests/_partition.md` states a per-suite test count that `test-suite-registration.Tests.ps1:185` enforces. **The row is `_partition.md:722`** and reads `check-agy-discipline-skills.Tests.ps1   43,2s   85 tests   <- FAST, re-measured 2026-09-03` (verified 2026-09-06). Change `85 tests` to **the number Step 5 actually reported** — 90 if the discovery found the two ledgers that exist today — and leave the rest of the row alone.

Run:
```bash
grep -n 'check-agy-discipline-skills.Tests.ps1' scripts/tests/_partition.md
```
Expected: the row now reads the count Step 5 reported.

🔴 **This is the step that gets forgotten.** A count is DERIVED, so grepping for the subject never finds it — grep for the OLD NUMBER as a literal. This exact row-count gate has shipped stale twice in this repository.

- [ ] **Step 8: Run the registration gate**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed -CI"
```
Expected: **PASS**, `Failed: 0`.

- [ ] **Step 9: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-capstone/SKILL.md \
        clavity-classic/plugin/skills/agy-capstone/SKILL.md \
        clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md \
        clavity-classic/plugin/skills/agy-test-audit/SKILL.md \
        scripts/tests/check-agy-discipline-skills.Tests.ps1 \
        scripts/tests/_partition.md
git commit -m "feat(s27): the ledger row precedes the marker write, pinned in both halves"
```

---

## Task 2: The ledger reader helper

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-ledger-lib.sh`
- Create: `clavity-classic/plugin/hooks/agy-ledger-lib.sh`
- Create: `scripts/tests/agy-ledger-lib.Tests.ps1`
- Modify: `justfile:108`
- Modify: `scripts/tests/_partition.md`

### The record predicate, and why it is what it is

Every rule below was measured against the two real ledgers on 2026-09-06. Do not "simplify" them.

- **A candidate record is a line beginning with `|` with at least 7 delimiter fields**, whose **field 2** (the date column) matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}$` after trimming.
  - **The date test is what separates a RECORD from a header or a separator**, and it is why the `unparsed=` diagnostic is not noise. MEASURED 2026-09-06: it yields **40 records / 6 non-records** in the capstone ledger and **5 / 2** in the test-audit ledger, and the 6 and 2 are exactly the header rows and the `|---|` separators. Without it a header (`| date | range | ... |`) is a candidate whose range token is the word `range`, which fails hex validation and is then reported as an unparseable record on every single run.
  - The 40 reconciles with the endpoint measurement: **37 parse, and the 3 that do not are the genuinely prose-ranged historical rows** (`SP-B agy-capstone skill`, `agy-test-audit discipline`, `clavity-ls channel resilience`). So a refusal on the real capstone ledger reports `unparsed=3`, permanently and harmlessly.
  - `awk -F'|'` on `| a | b | c | d | e |` yields **7** fields: `$1` is the empty string *before* the leading pipe, `$2..$6` are the five columns, `$7` is empty after the trailing pipe. **So the range column a reader sees as second is `$3`, not `$2`.** Getting this wrong builds a gate that reads the DATE, which fails hex validation on every row and refuses every write forever.
  - MEASURED field-count distribution: the capstone ledger has 12 lines at NF=5, 43 at NF=7, 2 at NF=9, 1 at NF=12; the test-audit ledger has 7 at NF=7. **The NF=5 lines are the 3-column anomaly table at `docs/agy-capstone-ledger.md:132`**, which is not a capstone record at all — `NF >= 7` excludes it structurally. The NF=9/12 lines are records carrying unescaped pipes in their evidence prose; extra delimiters only add fields at the END, so `$3` is unaffected.
  - The dash test removes the `|---|---|` separator rows, which otherwise share NF=7 with real records.
- **The range token is the FIRST whitespace- or paren-delimited word of field 3**, with backticks stripped. Later tokens are prose and are ignored **deliberately**: `docs/agy-capstone-ledger.md:69-70` carry parenthetical prose containing further `..` ranges, so scanning every token would let a fold commit mentioned in passing authenticate a marker.
- **Hex-validate before calling git.** A token must match `^[0-9a-fA-F]{7,40}(\^?\.\.[0-9a-fA-F]{7,40})?$`. This is what makes the design safe: prose like `SP-B agy-capstone skill` never reaches `git`.
- **Compare the RIGHT-hand endpoint**, resolved through `git rev-parse --verify --quiet <tok>^{commit}`, against the 40-char sha being marked.

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/agy-ledger-lib.Tests.ps1`:

```powershell
# agy-ledger-lib.sh is SOURCED by agy-mark.sh. These tests exercise it through a tiny bash driver in a
# throwaway git repo, because its answers depend on real commits: the reader resolves ledger tokens
# through git, and a fixture with no objects cannot tell a correct resolution from a failed one.
Describe 'agy-ledger-lib.sh' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Lib = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-ledger-lib.sh'

        function New-LedgerRepo {
            param([string]$LedgerBody, [string]$Discipline = 'agy-capstone')
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ("agl-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            Push-Location $d
            try {
                # Pin the fixture's git config: never inherit the host's. autocrlf would rewrite the
                # ledger's line endings and quotepath governs how paths come back out of git.
                & git init --quiet . 2>&1 | Out-Null
                & git config core.autocrlf false
                & git config core.quotepath true
                & git config user.email 'test@example.invalid'
                & git config user.name 'Test'
                Set-Content -LiteralPath (Join-Path $d 'seed.txt') -Value 'seed' -NoNewline
                & git add seed.txt; & git commit --quiet -m 'seed' 2>&1 | Out-Null
                $sha = (& git rev-parse HEAD).Trim()
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'docs') | Out-Null
                $body = $LedgerBody.Replace('<<SHORT>>', $sha.Substring(0,7)).Replace('<<FULL>>', $sha)
                Set-Content -LiteralPath (Join-Path $d "docs/$Discipline-ledger.md") -Value $body
            } finally { Pop-Location }
            [pscustomobject]@{ Dir = $d; Sha = $sha }
        }

        function Invoke-Lookup {
            param([string]$Dir, [string]$Discipline, [string]$Sha)
            $libPosix = $script:Lib -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
            $dirPosix = $Dir     -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
            $script = ". '$libPosix'; cd '$dirPosix'; agy_ledger_lookup '$dirPosix' '$Discipline' '$Sha'; echo ""rc=`$?"""
            $out = & bash -c $script 2>&1 | Out-String
            # Strip ANSI before matching. A blank read is NOT a pass.
            ($out -replace "`e\[[0-9;]*m", '').Trim()
        }
    }

    $goodLedger = @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..<<SHORT>>` | 1 | GREEN | fold `deadbee` |
'@

    It 'answers FOUND when a row records the sha as its range right-endpoint' {
        $r = New-LedgerRepo -LedgerBody $goodLedger
        try { Invoke-Lookup -Dir $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha | Should -Match 'FOUND' }
        finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }

    It 'answers ABSENT when no row records the sha' {
        $r = New-LedgerRepo -LedgerBody @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` | 1 | GREEN | fold `deadbee` |
'@
        try { Invoke-Lookup -Dir $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha | Should -Match 'ABSENT' }
        finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }

    It 'answers NO-LEDGER when the discipline owns no ledger file' {
        $r = New-LedgerRepo -LedgerBody $goodLedger
        try { Invoke-Lookup -Dir $r.Dir -Discipline 'agy-first' -Sha $r.Sha | Should -Match 'NO-LEDGER' }
        finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }

    It 'does NOT match a sha that appears only in the evidence column' {
        # This is the C1 false pass the whole design exists to close: fold shas live in the evidence
        # prose, and a whole-file grep would authenticate them.
        $r = New-LedgerRepo -LedgerBody @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` | 1 | GREEN | fold `<<FULL>>` |
'@
        try { Invoke-Lookup -Dir $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha | Should -Match 'ABSENT' }
        finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }

    It 'ignores a 3-column table, which has too few fields to be a record' {
        # The real capstone ledger carries a 3-column anomaly table whose second column is prose.
        $r = New-LedgerRepo -LedgerBody @'
# ledger

| n | anomaly |
|---|---------|
| 1 | <<SHORT>> |

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` | 1 | GREEN | fold `deadbee` |
'@
        try { Invoke-Lookup -Dir $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha | Should -Match 'ABSENT' }
        finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }

    It 'ignores tokens after the first, so a range quoted in the cell prose does not match' {
        $r = New-LedgerRepo -LedgerBody @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-06 | `aaaaaaa..bbbbbbb` (the folds run ccccccc..<<SHORT>>) | 1 | GREEN | fold `deadbee` |
'@
        try { Invoke-Lookup -Dir $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha | Should -Match 'ABSENT' }
        finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }

    It 'reports the line numbers of candidate records it could not parse' {
        $r = New-LedgerRepo -LedgerBody @'
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-07-25 | SP-B agy-capstone skill | 4 | GREEN | folds `deadbee` |
'@
        # unparsed is a COUNT; lines carries the LINE NUMBERS. The fixture's prose row is the 5th line
        # of the file, so the answer is `unparsed=1 lines=5` - assert BOTH, and do not conflate them.
        try {
            $r2 = Invoke-Lookup -Dir $r.Dir -Discipline 'agy-capstone' -Sha $r.Sha
            $r2 | Should -Match 'unparsed=1'
            $r2 | Should -Match 'lines=5'
        }
        finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }

    It 'never exits the calling shell - it is sourced, not executed' {
        # A helper that calls exit would kill agy-mark.sh mid-run. Prove the caller survives.
        $r = New-LedgerRepo -LedgerBody $goodLedger
        try {
            Invoke-Lookup -Dir $r.Dir -Discipline 'agy-first' -Sha 'not-a-sha-at-all' | Should -Match 'rc=0'
        } finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-ledger-lib.Tests.ps1 -Output Detailed -CI"
```
Expected: **FAIL**, 8 tests red — `agy_ledger_lookup: command not found`, because the helper does not exist yet.

- [ ] **Step 3: Write the helper**

Create `clavity-dotnet/plugin/hooks/agy-ledger-lib.sh`:

```bash
#!/usr/bin/env bash
# The ledger reader for the ROADMAP §27 marker-write gate.
#
# SOURCED, NEVER EXECUTED. It must not call `exit`: agy-mark.sh sources it, and an exit here kills the
# caller mid-run. This is the same rule agy-shield-lib.sh follows and the opposite of agy-mark.sh's own,
# which IS a process. DO NOT HARMONISE THEM.
#
# WHAT THIS PROVES, AND WHAT IT DOES NOT. It proves a ledger row records a sha. It does NOT prove an
# audit happened - a fabricated row passes, and the spec says so from its first section. The value is
# narrower and real: it converts a sin of OMISSION (forgetting the row) into a sin of COMMISSION
# (writing a decoy), and agents forget far more readily than they fabricate.
#
# WHY THE RANGE COLUMN IS FIELD 3 AND NOT FIELD 2. `awk -F'|'` on `| a | b | c | d | e |` yields SEVEN
# fields: $1 is the empty string BEFORE the leading pipe, $2..$6 are the five columns a reader sees, and
# $7 is empty after the trailing pipe. The range column a reader calls "second" is therefore $3. Reading
# $2 gets the DATE, which fails hex validation on every row, and the gate then refuses every marker write
# forever. MEASURED, and it is the defect a panel round caught in this design's own prose.
#
# WHY ONLY THE FIRST TOKEN OF THE CELL. Range cells carry trailing parenthetical prose, and that prose
# contains further `..` ranges (docs/agy-capstone-ledger.md:69-70). Scanning every token would let a fold
# commit mentioned in passing authenticate a marker - a weaker rerun of the false pass this closes.
#
# WHY HEX-VALIDATE BEFORE CALLING GIT. Range cells are sometimes prose ("SP-B agy-capstone skill").
# Feeding scraped prose to git is exactly what made an ancestry-based design unsafe. Validating first
# means git only ever sees hex.

# agy_ledger_path <git-root> <discipline>
# Echoes the convention path. Performs NO existence check.
agy_ledger_path() {
    printf '%s/docs/%s-ledger.md' "$1" "$2"
}

# agy_ledger_lookup <cwd> <discipline> <sha>
# Echoes exactly one of:
#   NO-LEDGER                     - this discipline owns no ledger here, so the gate does not apply
#   FOUND                         - a record's range right-endpoint resolves to <sha>
#   ABSENT unparsed=<n> lines=<l> - no record matched; <n> candidate records could not be parsed
# ALWAYS returns 0. The caller decides what to do; this function only answers.
agy_ledger_lookup() {
    local _agl_cwd=$1 _agl_disc=$2 _agl_sha=$3
    local _agl_root _agl_file _agl_n _agl_tok _agl_ep _agl_unparsed=0 _agl_lines=''

    # The MARKER is cwd-anchored (agy-mark.sh:140 and its header at :7-12 forbid git-toplevel by name,
    # because agy-seam-inject.sh:124 reads the marker relative to cwd). The LEDGER is not: it exists only
    # at the git root. Two anchors, deliberately. If there is no git root - no repo, or no git on PATH -
    # there is no ledger to find, so the gate does not apply and agy-mark.sh stays git-optional.
    _agl_root=$(git -C "$_agl_cwd" rev-parse --show-toplevel 2>/dev/null) || { printf 'NO-LEDGER'; return 0; }
    [ -n "$_agl_root" ] || { printf 'NO-LEDGER'; return 0; }

    _agl_file=$(agy_ledger_path "$_agl_root" "$_agl_disc")
    [ -f "$_agl_file" ] || { printf 'NO-LEDGER'; return 0; }

    # awk emits one "<line-number><TAB><token-or-dash>" per CANDIDATE RECORD. A candidate is a pipe-
    # anchored line with at least 7 fields whose field 3 is neither empty nor all dashes. A dash token
    # means "this looked like a record but its range did not parse" - that is what makes the refusal
    # able to distinguish a missing row from a malformed one.
    while IFS="$(printf '\t')" read -r _agl_n _agl_tok; do
        [ -n "$_agl_n" ] || continue
        if [ "$_agl_tok" = '-' ]; then
            _agl_unparsed=$((_agl_unparsed + 1))
            _agl_lines="${_agl_lines:+$_agl_lines,}$_agl_n"
            continue
        fi
        _agl_ep=$(git -C "$_agl_root" rev-parse --verify --quiet "${_agl_tok}^{commit}" 2>/dev/null) || _agl_ep=''
        if [ -z "$_agl_ep" ]; then
            _agl_unparsed=$((_agl_unparsed + 1))
            _agl_lines="${_agl_lines:+$_agl_lines,}$_agl_n"
            continue
        fi
        if [ "$_agl_ep" = "$_agl_sha" ]; then
            printf 'FOUND'
            return 0
        fi
    done <<EOF
$(awk -F'|' '
    /^\|/ && NF >= 7 {
        # THE DATE COLUMN DECIDES WHETHER THIS IS A RECORD AT ALL. Without this test a header row
        # ("| date | range | ...") is a candidate whose range token is the word "range", which fails
        # hex validation and is then reported as an unparseable record on every run. MEASURED: with it,
        # 40 records / 6 non-records in the capstone ledger, the 6 being 3 headers and 3 separators.
        d = $2
        gsub(/^[ \t]+|[ \t]+$/, "", d)
        if (d !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) next
        cell = $3
        gsub(/`/, "", cell)
        gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (cell == "") next
        split(cell, w, /[ \t(]/)
        tok = w[1]
        if (tok ~ /^[0-9a-fA-F]{7,40}\^?\.\.[0-9a-fA-F]{7,40}$/) {
            i = index(tok, "..")
            printf "%d\t%s\n", NR, substr(tok, i + 2)
        } else if (tok ~ /^[0-9a-fA-F]{7,40}$/) {
            printf "%d\t%s\n", NR, tok
        } else {
            printf "%d\t-\n", NR                # a record whose range did not parse
        }
    }
' "$_agl_file")
EOF

    printf 'ABSENT unparsed=%d lines=%s' "$_agl_unparsed" "${_agl_lines:--}"
    return 0
}
```

- [ ] **Step 4: Mirror the helper into the classic half**

Run:
```bash
cp clavity-dotnet/plugin/hooks/agy-ledger-lib.sh clavity-classic/plugin/hooks/agy-ledger-lib.sh
cmp clavity-dotnet/plugin/hooks/agy-ledger-lib.sh clavity-classic/plugin/hooks/agy-ledger-lib.sh && echo IDENTICAL
```
Expected: `IDENTICAL`.

- [ ] **Step 5: Syntax-check both copies before running anything**

Run:
```bash
bash -n clavity-dotnet/plugin/hooks/agy-ledger-lib.sh && bash -n clavity-classic/plugin/hooks/agy-ledger-lib.sh && echo "syntax ok"
```
Expected: `syntax ok`. **A shell file that does not parse produces test failures that look like logic failures** — this repository has lost a measurement run to exactly that.

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-ledger-lib.Tests.ps1 -Output Detailed -CI"
```
Expected: **PASS**, `Tests Passed: 8, Failed: 0`.

- [ ] **Step 7: STAGE THE NEW FILES BEFORE MUTATING THEM**

🔴 **This step exists because the restore in Step 8 cannot work without it, and skipping it costs the whole task.** `git checkout -- <path>` restores a path **from the index**. A brand-new file is not in the index, so the command fails with `error: pathspec ... did not match any file(s) known to git` and leaves you holding a mutated helper with no way back. Staging first also means the restore reads back exactly the bytes you wrote.

```bash
git add clavity-dotnet/plugin/hooks/agy-ledger-lib.sh clavity-classic/plugin/hooks/agy-ledger-lib.sh
git status --short clavity-dotnet/plugin/hooks/agy-ledger-lib.sh
```
Expected: `A  clavity-dotnet/plugin/hooks/agy-ledger-lib.sh` — the `A` means added to the index, which is what makes Step 8 reversible.

- [ ] **Step 8: Prove the suite is NOT vacuous with a logic mutant**

Break the field index — the exact defect a panel round caught in the spec's own prose — and confirm the suite reddens:

```bash
sed -i 's/        cell = \$3/        cell = $2/' clavity-dotnet/plugin/hooks/agy-ledger-lib.sh
grep -n 'cell = \$2' clavity-dotnet/plugin/hooks/agy-ledger-lib.sh   # CONTROL: prove the mutant landed
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-ledger-lib.Tests.ps1 -Output Detailed -CI"
```
Expected: the grep prints a hit, and the suite **FAILS** with the `FOUND` row red.

🔴 **If the grep prints NOTHING the mutant did not apply and the run proves nothing.** The likeliest cause is shell quoting: `$3` must reach `sed` literally, which is why the pattern is in **single** quotes. In double quotes or unquoted, the shell expands `$3` to the empty string and the pattern silently becomes `        cell = `, matching nothing. Re-check the quoting rather than concluding the test is weak.

Restore **from the index** — which now works, because Step 7 staged the file:
```bash
git checkout -- clavity-dotnet/plugin/hooks/agy-ledger-lib.sh
cmp clavity-dotnet/plugin/hooks/agy-ledger-lib.sh clavity-classic/plugin/hooks/agy-ledger-lib.sh && echo IDENTICAL
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-ledger-lib.Tests.ps1 -Output Detailed -CI"
```
Expected: `IDENTICAL`, then back to `Tests Passed: 8, Failed: 0`.

- [ ] **Step 9: Register the suite in the runner**

`justfile:108` (`test-scripts-slow`) is an explicit list. Add `'scripts/tests/agy-ledger-lib.Tests.ps1'` to it, immediately after `'scripts/tests/agy-shield-lib.Tests.ps1'`.

Run:
```bash
grep -c 'agy-ledger-lib.Tests.ps1' justfile
```
Expected: `1`.

- [ ] **Step 10: Add the `_partition.md` row**

Add to `scripts/tests/_partition.md`, next to the `agy-shield-lib` entry, following the existing row format:

```
agy-ledger-lib.Tests.ps1                          8 tests   <- SLOW, NEW 2026-09-06. ROADMAP section 27:
                                                              the ledger reader behind the marker-write gate.
```

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed -CI"
```
Expected: **PASS**, `Failed: 0`.

- [ ] **Step 11: Verify pair sync and commit**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
git add clavity-dotnet/plugin/hooks/agy-ledger-lib.sh \
        clavity-classic/plugin/hooks/agy-ledger-lib.sh \
        scripts/tests/agy-ledger-lib.Tests.ps1 \
        scripts/tests/_partition.md justfile
git commit -m "feat(s27): a ledger reader that locates a sha positionally, never by searching"
```
Expected: `exit=0` and no `SEED-DRIFT`.

---

## Task 3: The gate and the override in `agy-mark.sh`

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-mark.sh:181-187` (helper loading) and `:192-206` (the `head)` arm)
- Modify: `clavity-classic/plugin/hooks/agy-mark.sh` (byte-identical twin)
- Test: `scripts/tests/agy-mark.Tests.ps1`
- Modify: `scripts/tests/_partition.md:677`

**Why the existing suite keeps passing.** `scripts/tests/agy-mark.Tests.ps1` builds its fixture as a temp directory containing a `.clavity/` and **no `docs/`**. No ledger file means `agy_ledger_lookup` answers `NO-LEDGER`, the gate does not apply, and every current row is unaffected. 🔴 **The corollary is the trap: the NEW rows must CREATE a ledger in the fixture**, or they exercise the not-applicable path and prove nothing while looking green.

- [ ] **Step 1: Confirm the `head)` arm still matches this plan**

Run:
```bash
sed -n '192,206p' clavity-dotnet/plugin/hooks/agy-mark.sh
```
Expected: the arm reads `head)`, `discipline=${2:-}; sha=${3:-}`, `_check_discipline`, the `[ -n "$sha" ]` guard, `_check_sha`, `rel=`, `agy_shield`, `mkdir -p`, the `printf '%s' "$sha" ... > "$root/$rel"` write, `exit 0`. **If it differs, STOP and report `STATE_MISMATCH: <what>`.**

- [ ] **Step 2: Write the failing tests**

Add to `scripts/tests/agy-mark.Tests.ps1`, inside the existing `Describe`:

```powershell
    Context 'the ROADMAP section 27 ledger gate' {
        # THE FIXTURE MUST CARRY A LEDGER. Every other fixture in this file is a bare temp dir with no
        # docs/, which means NO-LEDGER, which means the gate does not apply - a row written against one
        # of those would pass no matter what the gate does.
        function New-GatedRepo {
            param([switch]$WithRow)
            $d = Join-Path ([System.IO.Path]::GetTempPath()) ("agm27-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            Push-Location $d
            try {
                & git init --quiet .
                & git config core.autocrlf false
                & git config user.email 'test@example.invalid'
                & git config user.name 'Test'
                Set-Content -LiteralPath (Join-Path $d 'seed.txt') -Value 'seed' -NoNewline
                & git add seed.txt; & git commit --quiet -m seed 2>&1 | Out-Null
                $sha = (& git rev-parse HEAD).Trim()
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'docs') | Out-Null
                $row = if ($WithRow) { "| 2026-09-06 | ``aaaaaaa..$($sha.Substring(0,7))`` | 1 | GREEN | e |" } else { '' }
                Set-Content -LiteralPath (Join-Path $d 'docs/agy-capstone-ledger.md') -Value @"
# ledger

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
$row
"@
            } finally { Pop-Location }
            [pscustomobject]@{ Dir = $d; Sha = $sha }
        }

        It 'REFUSES the marker write when the ledger has no row for the sha' {
            $r = New-GatedRepo
            try {
                $out = & bash -c "cd '$($r.Dir -replace '\\','/')' && bash '$script:Mark' head agy-capstone $($r.Sha) 2>&1; echo rc=`$?"
                ($out | Out-String) | Should -Match 'rc=1'
                ($out | Out-String) | Should -Match 'REFUSED'
                Test-Path (Join-Path $r.Dir '.clavity/agy-marks/agy-capstone.head') | Should -BeFalse
            } finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
        }

        It 'WRITES the marker when the ledger records the sha' {
            $r = New-GatedRepo -WithRow
            try {
                $out = & bash -c "cd '$($r.Dir -replace '\\','/')' && bash '$script:Mark' head agy-capstone $($r.Sha) 2>&1; echo rc=`$?"
                ($out | Out-String) | Should -Match 'rc=0'
                Get-Content -LiteralPath (Join-Path $r.Dir '.clavity/agy-marks/agy-capstone.head') -Raw | Should -Be $r.Sha
            } finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
        }

        It 'the refusal names BOTH the fix and the escape' {
            $r = New-GatedRepo
            try {
                $out = (& bash -c "cd '$($r.Dir -replace '\\','/')' && bash '$script:Mark' head agy-capstone $($r.Sha) 2>&1") | Out-String
                $out | Should -Match 'docs/agy-capstone-ledger\.md'
                $out | Should -Match '--gate-override'
            } finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
        }

        It '--gate-override writes the marker AND a GATE-OVERRIDE audit line' {
            $r = New-GatedRepo
            try {
                $out = & bash -c "cd '$($r.Dir -replace '\\','/')' && bash '$script:Mark' head agy-capstone $($r.Sha) --gate-override 2>&1; echo rc=`$?"
                ($out | Out-String) | Should -Match 'rc=0'
                Get-Content -LiteralPath (Join-Path $r.Dir '.clavity/agy-marks/agy-capstone.head') -Raw | Should -Be $r.Sha
                $log = Get-Content -LiteralPath (Join-Path $r.Dir '.clavity/agy-marks/skipped.log') -Raw
                $log | Should -Match 'GATE-OVERRIDE'
                # NEVER 'WAIVED': agy-mark.sh:91-93 records that skipped.log is READ for WAIVED lines to
                # decide whether a capstone was waived in a range. Reusing that token would forge an
                # attestation nobody made.
                $log | Should -Not -Match 'WAIVED'
            } finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
        }

        It 'is INERT in a repository that owns no such ledger' {
            $r = New-GatedRepo
            try {
                Remove-Item -LiteralPath (Join-Path $r.Dir 'docs/agy-capstone-ledger.md') -Force
                $out = & bash -c "cd '$($r.Dir -replace '\\','/')' && bash '$script:Mark' head agy-capstone $($r.Sha) 2>&1; echo rc=`$?"
                ($out | Out-String) | Should -Match 'rc=0'
                # ASSERT THE MARKER REACHED DISK, not merely that the process exited 0. A panel round
                # caught these two rows asserting the exit code alone: a gate that silently exited 0
                # without writing anything would have passed them while the behaviour they name is broken.
                Get-Content -LiteralPath (Join-Path $r.Dir '.clavity/agy-marks/agy-capstone.head') -Raw | Should -Be $r.Sha
            } finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
        }

        It 'is INERT for a discipline that owns no ledger, even where other ledgers exist' {
            $r = New-GatedRepo -WithRow
            try {
                $out = & bash -c "cd '$($r.Dir -replace '\\','/')' && bash '$script:Mark' head agy-first $($r.Sha) 2>&1; echo rc=`$?"
                ($out | Out-String) | Should -Match 'rc=0'
                # ASSERT THE MARKER REACHED DISK, not merely that the process exited 0. A panel round
                # caught these two rows asserting the exit code alone: a gate that silently exited 0
                # without writing anything would have passed them while the behaviour they name is broken.
                # NOTE the filename: this row marks agy-first, so the marker is agy-first.head. Asserting
                # agy-capstone.head here would fail for the wrong reason and read as a gate defect.
                Get-Content -LiteralPath (Join-Path $r.Dir '.clavity/agy-marks/agy-first.head') -Raw | Should -Be $r.Sha
            } finally { Remove-Item -Recurse -Force $r.Dir -ErrorAction SilentlyContinue }
        }
    }
```

✅ **VERIFIED 2026-09-06:** `scripts/tests/agy-mark.Tests.ps1:12` already sets
`$script:Mark = (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-mark.sh') -replace '\\','/'`
— **it is already POSIX-normalised**, so use it bare. Re-normalising it inside the test string is a
double-escape and produces a path bash cannot open, which surfaces as "No such file or directory" — and
this repository has recorded a suite passing green with no hook on disk because bash's error text
contains the filename the assertion was matching. Confirm with
`grep -n 'script:Mark' scripts/tests/agy-mark.Tests.ps1` before writing the rows; if the name has
changed, report `STATE_MISMATCH` rather than introducing a second variable.

- [ ] **Step 3: Run the tests to verify they fail**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-mark.Tests.ps1 -Output Detailed -CI"
```
Expected: **FAIL** — the refusal rows red (the gate does not exist, so the marker is written), and `--gate-override` red (`unknown mode` or an ignored argument).

- [ ] **Step 4: Load the ledger helper beside the shield helper**

In **both** copies of `agy-mark.sh`, immediately after the `command -v agy_shield ...` line (`:187`), insert:

```bash
# Load the ledger reader. Same contract as the shield helper: sourced, never executed, and its answers
# are advisory strings rather than exit codes. ROADMAP §27.
_ledger_lib="$(dirname "$0")/agy-ledger-lib.sh"
[ -f "$_ledger_lib" ] || _die_refuse "ledger helper not found beside this script: [$_ledger_lib]"
# shellcheck source=agy-ledger-lib.sh
. "$_ledger_lib" 2>/dev/null || _die_refuse "ledger helper could not be sourced: [$_ledger_lib]"
command -v agy_ledger_lookup >/dev/null 2>&1 || _die_refuse "ledger helper loaded but agy_ledger_lookup is not defined: [$_ledger_lib]"
```

- [ ] **Step 5: Add the gate to the `head)` arm**

Replace the `head)` arm's body (currently `agy-mark.sh:192-206`) with:

```bash
    head)
        discipline=${2:-}; sha=${3:-}; _gate_override=${4:-}
        _check_discipline "$discipline"
        [ -n "$sha" ] || _die_refuse 'head requires a sha argument'
        _check_sha "$sha"
        # ROADMAP §27: a completion marker may not advance past a ledger that does not record it.
        # THE GATE IS INERT WHERE NO SUCH LEDGER EXISTS - which is every repository but this one, since
        # this file ships in a plugin. NO-LEDGER is the overwhelmingly common answer in the wild.
        _gate=$(agy_ledger_lookup "$root" "$discipline" "$sha")
        case "$_gate" in
            NO-LEDGER|FOUND) : ;;
            *)
                if [ "$_gate_override" = '--gate-override' ]; then
                    # AUDIT FIRST, WRITE SECOND. An override nobody can see is the silent bypass this
                    # gate exists to prevent, so if the audit line cannot be written the override is
                    # refused. That costs nothing: skipped.log and the marker live in the same
                    # directory, so a filesystem rejecting one rejects the other.
                    # THE TOKEN IS 'GATE-OVERRIDE', NEVER 'WAIVED' - see :91-93, skipped.log is READ for
                    # WAIVED lines to decide whether a capstone was waived inside a range, so reusing
                    # that token would manufacture an attestation nobody made.
                    mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || _die_refuse 'could not create .clavity/agy-marks'
                    printf -v _go_ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || _go_ts=$(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
                    [ -n "$_go_ts" ] || _go_ts=unknown
                    printf '%s  %s  GATE-OVERRIDE  HEAD=%s  %s\n' "$_go_ts" "$discipline" "$sha" "$_gate" \
                        >> "$root/.clavity/agy-marks/skipped.log" 2>/dev/null \
                        || _die_refuse 'GATE-OVERRIDE could not be recorded, so the marker was NOT written'
                else
                    _die_refuse "docs/$discipline-ledger.md does not record $sha ($_gate). Append the row for this run FIRST, then write the marker. If the ledger itself is unparseable and you must proceed, re-run with --gate-override, which records the bypass in .clavity/agy-marks/skipped.log."
                fi
                ;;
        esac
        rel=".clavity/agy-marks/$discipline.head"
        agy_shield "$root" "$rel" "$_key"
        # EVERY mode creates the directory it writes into. The helper's Stage A1 creates .clavity/ and
        # NOTHING BELOW IT, and this batch removes the skills' own mkdir instructions, so without this
        # a fresh clone fails "No such file or directory" on the first discipline that runs.
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || _die_refuse 'could not create .clavity/agy-marks'
        # BARE sha and nothing else (docs/agy-disciplines-marker-contract.md:18).
        printf '%s' "$sha" 2>/dev/null > "$root/$rel" || { printf 'agy-mark: write FAILED for %s - the filesystem rejected it\n' "$rel" >&2; exit 1; }
        exit 0
        ;;
```

- [ ] **Step 6: Mirror to classic, syntax-check both**

```bash
cp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
bash -n clavity-dotnet/plugin/hooks/agy-mark.sh && bash -n clavity-classic/plugin/hooks/agy-mark.sh && echo "syntax ok"
cmp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh && echo IDENTICAL
```
Expected: `syntax ok` then `IDENTICAL`.

- [ ] **Step 7: Run the tests to verify they pass**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-mark.Tests.ps1 -Output Detailed -CI"
```
Expected: **PASS**, `Tests Passed: 42, Failed: 0` (was 36; six new rows).

- [ ] **Step 8: STAGE THE GATE CODE BEFORE MUTATING IT**

🔴 **Do not skip this, and do not reorder it after the mutant. A panel round found that the original plan destroyed the implementer's own work here.** The gate code written in Steps 4 and 5 is an **unstaged modification**. `git checkout -- <path>` restores from the index, and the index still holds the *pre-task* `agy-mark.sh` — so running it before staging silently reverts every line of the gate, and the plan then walks you into committing a branch with the feature missing.

```bash
git add clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
git status --short clavity-dotnet/plugin/hooks/agy-mark.sh
```
Expected: `M  clavity-dotnet/plugin/hooks/agy-mark.sh` — note the `M` is in the **first** column (staged), not the second.

- [ ] **Step 9: Prove the gate rows are not vacuous**

Neuter the gate and confirm the right rows redden:

```bash
sed -i 's/            NO-LEDGER|FOUND) : ;;/            NO-LEDGER|FOUND|ABSENT*) : ;;/' clavity-dotnet/plugin/hooks/agy-mark.sh
grep -n 'ABSENT\*) : ;;' clavity-dotnet/plugin/hooks/agy-mark.sh   # CONTROL: prove the mutant landed
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-mark.Tests.ps1 -Output Detailed -CI"
```

Expected: the grep prints a hit, and **THREE rows go red by name** —

1. `REFUSES the marker write when the ledger has no row for the sha`
2. `the refusal names BOTH the fix and the escape`
3. `--gate-override writes the marker AND a GATE-OVERRIDE audit line`

**The third one is not collateral damage; it is the mutant working.** Widening the `case` arm to swallow `ABSENT*` means the `*)` fallback never runs, so the override branch never executes and `skipped.log` is never written. An earlier draft of this plan predicted "exactly two" and warned that extra red rows mean something else broke — which would have made an implementer abandon a correct validation. **Read WHICH rows went red and check them against this list of three; a non-zero suite on its own still proves nothing.**

Restore **from the index**, which works because Step 8 staged it:
```bash
git checkout -- clavity-dotnet/plugin/hooks/agy-mark.sh
cp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
cmp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh && echo IDENTICAL
pwsh -NoProfile -c "Invoke-Pester scripts/tests/agy-mark.Tests.ps1 -Output Detailed -CI"
```
Expected: `IDENTICAL`, then back to `Tests Passed: 42, Failed: 0`. 🔴 **If instead the six new gate rows fail here, the restore reverted too far** — you staged nothing in Step 8 and the index handed back the pre-task file. Re-apply Steps 4 and 5.

- [ ] **Step 10: Update the enforced count and re-run the registration gate**

`scripts/tests/_partition.md:677` currently reads `36 tests` for `agy-mark.Tests.ps1`. Change it to `42 tests`.

```bash
grep -n 'agy-mark.Tests.ps1' scripts/tests/_partition.md
pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed -CI"
```
Expected: the row reads `42 tests`; the registration suite passes with `Failed: 0`.

- [ ] **Step 11: Verify pair sync and commit**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -NoProfile -c "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed -CI"
git add clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh \
        scripts/tests/agy-mark.Tests.ps1 scripts/tests/_partition.md
git commit -m "feat(s27): the head arm refuses a marker the ledger does not record"
```

⚠ The `git add` here is deliberately repeated even though Step 8 already staged the two hook files — Steps 9 and 10 touched the test suite and `_partition.md`, which are not yet in the index, and re-staging an unchanged path is a no-op.
Expected: `exit=0`, no `SEED-DRIFT`, payload suite green.

---

## Task 4: The documents this change makes incomplete

Panel round 5's whole subject, and this repository's dominant defect class: a correct change landed in one place and not the other four.

**Files:**
- Modify: `docs/agy-disciplines-marker-contract.md:55`
- Modify: `clavity-dotnet/plugin/hooks/agy-mark.sh:52-59` (header comment) + classic twin
- Modify: `docs/backlog/agy-mark-accepts-a-nonexistent-sha.md`

- [ ] **Step 1: Update the marker contract**

`docs/agy-disciplines-marker-contract.md:3` declares this file the *"Single source of truth for the debounce marker"*, and `:55` says the skill writes the marker **"only at that discipline's terminal state"**. That stays true and stops being sufficient. Immediately after the `:55` bullet block, insert:

```markdown
- 🔴 **A TERMINAL STATE IS NECESSARY AND NO LONGER SUFFICIENT (ROADMAP §27).** For a discipline that owns
  a ledger — today `agy-capstone` and `agy-test-audit`, discovered as `docs/<discipline>-ledger.md` —
  `agy-mark.sh` **refuses** the write unless that ledger already records the sha being marked. The row
  precedes the marker. A refusal names the ledger and the `--gate-override` escape, and the override
  records a `GATE-OVERRIDE` line in `.clavity/agy-marks/skipped.log`.
  ⚠ `agy-first` owns no ledger, so the gate does not apply to it — this file's own note above that
  `agy-first` writes a marker after a completed consult is unchanged.
```

- [ ] **Step 2: Correct `agy-mark.sh`'s header comment, which this change falsifies**

`agy-mark.sh:52-59` currently asserts that both failures are *"terminally fatal with no programmatic recovery"* and that a refusal means *"this script's own caller is malformed"*. Both become false. In **both** copies, append to that paragraph:

```bash
# ROADMAP §27 ADDED A THIRD REFUSAL CAUSE AND THE FIRST PROGRAMMATIC RECOVERY, so the sentence above is
# no longer the whole story: `head` also refuses when the discipline's ledger does not record the sha,
# which is an ENVIRONMENT fault rather than a malformed caller, and `--gate-override` recovers from it
# programmatically while recording the bypass. Kept rather than rewritten because the original sentence
# is still true of the other two causes.
```

- [ ] **Step 3: Resolve the backlog collision, in this plan rather than after it**

`docs/backlog/agy-mark-accepts-a-nonexistent-sha.md` proposes a `git cat-file -e <sha>^{commit}` check on this same `head` arm, and closes on the same question this plan answered: what happens when the marker is written **outside a repository**. Append to that file:

```markdown
## ▶ ANSWERED IN PART BY ROADMAP §27 (2026-09-06)

§27's gate resolves the design question this stub left open. **Outside a repository, or with no git,
`agy_ledger_lookup` answers `NO-LEDGER` and the gate does not apply** — `agy-mark.sh` stays git-optional,
which was the property this stub was unsure whether to break.

**This stub is NOT closed.** §27 gates the marker against the LEDGER; it still performs no existence
check on the sha itself, so a fabricated 40-character string is written verbatim exactly as recorded
here — *unless* it happens to be absent from the ledger, which is a different guard catching a different
mistake. The three-line `git cat-file -e` fix remains owed, and it is now cheaper: the `head` arm already
resolves git and already has a refusal path with a two-cause diagnostic.
```

- [ ] **Step 4: Verify pair sync and run the doc gates**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
pwsh -NoProfile -File scripts/check-roadmap-claims.ps1
pwsh -NoProfile -File scripts/check-user-facing-docs.ps1
```
Expected: `exit=0`, no `SEED-DRIFT`, both checkers `OK`.

- [ ] **Step 5: Commit**

```bash
git add docs/agy-disciplines-marker-contract.md \
        docs/backlog/agy-mark-accepts-a-nonexistent-sha.md \
        clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
git commit -m "docs(s27): the marker contract records the gate, and the backlog stub gets its answer"
```

---

## Task 5: The full sweep, before anyone calls this done

🔴 **The last push of a §-item turned CI red with 37 rows, every one reproducible locally, because only the suites that had been edited were run.** `test-suite-registration` passing proves REGISTRATION, never that suites PASS.

- [ ] **Step 1: Run the whole scripts suite**

Run:
```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests -Output Detailed -CI"
```
Expected: a `Tests Passed: <n>, Failed: 0` line, with `<n>` equal to the previous sweep total plus 14 (8 new in `agy-ledger-lib`, 6 new in `agy-mark`, 4 new in `check-agy-discipline-skills`, minus none removed — reconcile the arithmetic against the actual number rather than assuming it).

🔴 **No `Tests Passed:` line, or `Tests Passed: 0`, is an ABORTED run that reads like a pass.** Strip ANSI before grepping the output; a blank read is not a pass.

- [ ] **Step 2: Run the two .NET suites**

```bash
cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests; cd ..
```
Expected: both green. `Integration.Tests` is CI-run (`ci-dotnet.yml:32`) but is **not** in `just dotnet::test`, so the local default gate is weaker than CI.

- [ ] **Step 3: Hand the branch to the owner**

Do **not** push. The owner owns every push. Report: the commit range, the sweep totals, and that AGY-CAPSTONE over the range is the next gate — this plan's changes are executable code in a shipped, byte-identical pair, which is class 2: plan → panel → capstone → audit.

---

## Self-review

**Spec coverage.** C1 → Task 2's record predicate. C3 → Task 3 Step 5's two-cause refusal naming fix and escape. C4 → Task 3 Step 2's `is INERT` rows. C5 → the `cmp`/`check-seed-artifacts-synced.sh` step in every task. C6 → `NO-LEDGER`. C7 → the helper's two-anchor comment and its `rev-parse --show-toplevel`. C8 → Task 4 Step 3. C9 → Task 1. F1/F5 → convention path plus `NO-LEDGER`. F2 → right-endpoint exact match. F4 → the sourced helper. F6 → `--gate-override` + `GATE-OVERRIDE`. F7 → the range-column parser.

**Known gaps, stated rather than hidden.**

1. **The `unparsed=` diagnostic reports line numbers, not "your row".** The gate cannot know which row is the operator's. On the real capstone ledger three historical rows carry prose ranges and will always be counted. That is noise the refusal message tolerates deliberately; the alternative is guessing.
2. **The heading-section record at `docs/agy-capstone-ledger.md:456` is invisible to the gate** — it is a `##` section, not a table row. A record that must be gate-visible has to be a row. This is a convention obligation with no mechanical enforcement in this plan.
3. **No test covers a ledger with CRLF line endings.** `awk`'s `$3` would carry a trailing `\r` on the last field only, which is field 7, not field 3 — so the parser should be unaffected. **This is reasoned, not measured**, and is the first thing to check if the gate misbehaves on a Windows-authored ledger.
4. **The override is not owner-only**, because `agy-mark.sh` has no owner identity: any flag a human can pass, an agent can pass. The owner ruled for the flag with that objection on the record; auditability is the compensation, not restriction.

---

## Review status — AGY-AFTER round 1 on this PLAN, folded 2026-09-06

Brief `.clavity/seams/panel-s27-plan-r1.md`. Seats: bespoke **Execution Realist** (what breaks when
someone actually RUNS these steps), Literal Implementer, Mechanism Gamer, Axiom Breaker, Cascade Analyst.
Seven findings, three BLOCKING. Citations verified mechanically: **`0 problem(s) across 5 row(s)`** against
`51a3433`.

🔴 **THIS ROUND EARNED ITS COST TWICE OVER — THE PLAN AS WRITTEN WOULD HAVE DESTROYED THE IMPLEMENTER'S OWN
WORK.** Both mutant steps restored with `git checkout -- <path>` while the code under test was unstaged.
In Task 2 that fails outright (the helper is untracked, so git reports a pathspec error). In Task 3 it
succeeds and is worse: the gate written in Steps 4–5 is reverted to HEAD and silently lost. **Fixed by
staging before mutating** in both tasks, which also makes the restore read back exactly the bytes written.

- **`unparsed=5` conflated a COUNT with a LINE NUMBER.** The helper emits `unparsed=1 lines=5`. Fixed —
  and it exposed a real design gap: without a date-shape test on the date column, header rows are
  candidate records whose range token is the word `range`, reported as unparseable on every run. The
  predicate now requires a date, MEASURED at 40 records / 6 non-records (capstone) and 5 / 2 (test-audit).
- **The mutant expectation was wrong and the warning around it was actively harmful.** It predicted
  "exactly two" red rows and told the implementer that extra red rows mean something else broke. The
  mutant reddens **three** — swallowing `ABSENT*` also bypasses the override branch. An implementer
  obeying the old warning would have abandoned a correct validation.
- **The two `is INERT` rows asserted only `rc=0`** and would have passed against a gate that exited 0
  without writing anything. They now assert the marker's contents — and the `agy-first` row asserts
  `agy-first.head`, not `agy-capstone.head`.
- **A phantom `git add scripts/check-agy-discipline-skills.ps1`** appeared in Task 1's commit step with no
  step modifying that file. Removed from the step, the file list and the File Structure table.
- **The roster in Task 1's new test was hardcoded** — reintroducing the exact enumeration failure the test
  exists to prevent. It now **discovers** `docs/*-ledger.md`, which is also how the gate itself decides
  applicability, plus a guard row so a discovery finding nothing fails loudly instead of vacuously.

**One claim was REJECTED as overstated.** The round's answer to "name a step whose Expected line could
print while the step failed" said Task 3's post-restore run would print `Tests Passed: 42, Failed: 0`.
It would not: reverting past the gate makes the six new gate rows FAIL, so the implementer sees red, not a
false pass. The underlying finding — that `git checkout --` destroys unstaged work — is true and is
folded; its stated symptom is not. **Fourth time this session a true finding arrived with a wrong
mechanism.**

⚠ **A review-only envelope breach occurred during this round** and is recorded in
`.clavity/agy-marks/skipped.log` as `BREACH-REVERTED`. Four scratch files reached the repository root; all
were deleted, and HEAD, branch and reflog were unmoved throughout. The cause is worth keeping: the peer
placed its script correctly in `.clavity/scratch/panel-s27/` but the script wrote its output **relative to
CWD** and was run from the root. **Naming a scratch directory does not confine writes — bind the working
directory.** The brief also invited a file-creating check while forbidding all writes, which is the same
self-undercutting shape as the four earlier breaches.

**This plan has no GREEN.** One round ran; it found BLOCKING defects; they are folded. A second round is
owed before execution, or the owner may accept the risk and execute — that is the owner's call, not the
driver's.
