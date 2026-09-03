# ROADMAP section 23 - the AGY-TEST-AUDIT ledger - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax
> for tracking.

**Goal:** Give AGY-TEST-AUDIT a durable record of what it audited, so the question *"was this range
audited?"* has an answer, and bind that record to the discipline's existing completing gate so it cannot
rot.

**Architecture:** One new committed file, `docs/agy-test-audit-ledger.md`, mirroring
`docs/agy-capstone-ledger.md` column-for-column. One clause added to the audit skill's **existing**
Completeness gate requiring a row before either completing verdict may be emitted. One linter check that
the clause SHIPS, with a rejection row that reddens when it does not. No new hook, no new gate mechanism,
no rename.

**Tech Stack:** Markdown (`docs/`), the shipped `SKILL.md` payload in two byte-identical plugin halves,
PowerShell (`scripts/check-agy-discipline-skills.ps1`), Pester 6 (`scripts/tests/`).

---

## Why this shape, and what the owner ruled

**Owner ruling, 2026-09-03:** options 1 and 2 of the ROADMAP fork **together** - a ledger AND a row
requirement - not either alone. Recorded in `clavity-dotnet/ROADMAP.md` section 23 at commit `0c24373`.

AGY-FIRST was run before the ruling (brief `.clavity/seams/agyfirst-s23-ledger-fork.md`). The peer
proposed a fourth option, folding the record into the capstone's ledger as a column, and then conceded it
under measurement. Its concession is load-bearing for this plan and is **why a separate file is used**:

- Writing that row to satisfy the CAPSTONE's gate would leave the audit cell empty, and nothing would
  force it to be filled.
- `docs/agy-capstone-ledger.md` is referenced from **23 files**; renaming it to something honest is
  unacceptable churn.

**The counter-argument the owner overruled, recorded so it is not lost:** the peer's final position was
option 3, accept the limitation, on the grounds that the audit's durable outputs are the tests it forces
and `docs/accepted-boundaries.md`, so the range is "historical metadata". It is not metadata: the range
is the input to the capstone-invalidation loop (`capstone-green -> audit -> fix -> re-capstone ->
re-audit`), and you cannot tell whether a re-audit is owed without it.

---

## VERIFIED STATE - every anchor below was read at `0c24373` before this plan was written

| claim | verified how |
|---|---|
| The audit already HAS a completing gate at `agy-test-audit/SKILL.md:278-281` | read; text quoted in Task 2 |
| The capstone's mirror clause is at `agy-capstone/SKILL.md:375` | `grep -n "Record the round in"` |
| The two `agy-test-audit/SKILL.md` halves are byte-identical | `md5sum` on both -> one hash, count 2 |
| The capstone ledger's columns are `date \| range \| rounds \| verdict \| evidence` | `docs/agy-capstone-ledger.md:39-40` |
| **The capstone's own ledger clause is pinned by NO test** | `grep -rn "agy-capstone-ledger" scripts/tests/*.ps1` -> one hit, and it is a fixture in `agy-test-audit-reminder.Tests.ps1:92`, not a pin |
| A new `docs/` file needs no registration | `check-doc-stubs`, `check-user-facing-docs`, `check-member-docs` each name specific files; `agy-capstone-ledger.md` appears in none of them |
| A docs commit cannot age either marker | `agy-test-audit-reminder.sh:67` - `CODE_RE` matches only executable extensions plus `justfile` |

**That last row matters and is the reason this plan is safe.** The peer's objection to option 4 was that
committing a ledger row silences the nudge. Measured: `still_describes_head` only breaks on a file
matching `CODE_RE`, and `.md` is not in it - so committing the audit's own row cannot re-arm or suppress
anything it should not. The row is written after the marker, and neither affects the other.

---

## File Structure

| file | responsibility | status |
|---|---|---|
| `docs/agy-test-audit-ledger.md` | the record: one row per audit | **CREATE** |
| `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md` | the discipline; gains the row requirement | MODIFY |
| `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` | byte-identical mirror | MODIFY (identical bytes) |
| `scripts/check-agy-discipline-skills.ps1` | pins that the clause SHIPS | MODIFY |
| `scripts/tests/check-agy-discipline-skills.Tests.ps1` | pins the linter check, non-vacuously | MODIFY |
| `scripts/tests/_partition.md` | suite count, mechanically gated | MODIFY |

**Blast radius: plugin-shipped, so class 2 -> BLOCKING.** The ROADMAP requires **panel, then capstone**
for this change. Do not skip to a quiet edit.

---

## Task 1: Create the ledger, with the one audit we can evidence

**Files:**
- Create: `docs/agy-test-audit-ledger.md`

- [ ] **Step 1: Write the file**

Columns are copied from `docs/agy-capstone-ledger.md:39-40` deliberately - a reader who knows one ledger
should not have to learn a second shape.

```markdown
# AGY-TEST-AUDIT ledger

One row per audit. Appended before an audit run may COMPLETE.

**Append the newest row at the BOTTOM of the table.** Say it here because the sibling ledger does not
settle it: `docs/agy-capstone-ledger.md`'s rows are NOT in date order (2026-08-08 sits between 07-31 and
08-01, and 08-16/08-17 precede 08-10/08-12), so "mirror the capstone" answers the shape of a row and not
the order of the file. A ledger two agents append to differently is a merge conflict per branch-finish;
appending at one end keeps the conflict trivial to resolve.

**This is a RECORD, not a proof.** Nothing prevents someone appending a row without running anything; a
self-asserted ledger is the same shape as the re-stamping defect the verify gate removed. Two things keep
it honest, neither a guarantee: the `evidence` column must cite something independently checkable (the
fold commits, or the brief in `.clavity/seams/`), and `none` is not a permitted value.

**Why this file exists.** The audit's marker `.clavity/agy-marks/agy-test-audit.head` is a NUDGE DEBOUNCE
holding ambient `HEAD` - `agy-test-audit/SKILL.md:313-314` - not a coverage attestation. Before this
ledger, no artifact in the repository recorded which range had been audited, so the question "is a
re-audit owed?" could not be answered from the tree. That question is the input to the
capstone-invalidation loop, which is why the record is not optional bookkeeping.

**What a row does NOT claim.** That the suite is now exhaustive. An audit raises the coverage FLOOR under
one set of lenses; it does not prove no gap remains.

| date | range | rounds | verdict | evidence |
|------|-------|--------|---------|----------|
| 2026-09-02 | `d33416c..d528328` | 1 | **GAPS FOUND** - 9 verified gaps folded, 2 REJECTED by measurement, 2 DISCARDED-BELOW-FLOOR | fold commit `f3ea3e9`; brief `.clavity/seams/testaudit-phase1-r1.md`. Every gap was established by a guard mutant - force the guard false, re-run, record what reddens - with baselines 18/0 and 59/0 and a failing control in the same campaign. One finding was a live SOURCE defect rather than a coverage gap: malformed JSON syntax reached `json.load` unguarded. Gates at the fold: 27/0 and 66/0. |
```

**Backfilling exactly one row is deliberate.** It is the only audit whose range, verdict and evidence can
be recovered from the tree today - the fold commit exists and the brief exists. Earlier audits are named
in commit subjects but their ranges are not recoverable without guessing, and a ledger that guesses is
worse than one that starts where the evidence starts. **Do not backfill anything you cannot cite.**

- [ ] **Step 2: Verify no gate objects to a new docs file**

```bash
pwsh -NoProfile -Command "& './scripts/check-doc-stubs.ps1'; 'stubs=' + \$LASTEXITCODE"
pwsh -NoProfile -Command "& './scripts/check-user-facing-docs.ps1'; 'user-facing=' + \$LASTEXITCODE"
```
Expected: both `0`. (Verified while writing this plan: neither script names `agy-capstone-ledger.md`, so
neither will name its sibling.)

- [ ] **Step 3: Commit**

```bash
git add docs/agy-test-audit-ledger.md
git commit -m "docs(s23): create the AGY-TEST-AUDIT ledger, backfilled with the one auditable range"
```

---

## Task 2: Ship the row requirement into both plugin halves

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md`
- Modify: `clavity-classic/plugin/skills/agy-test-audit/SKILL.md`

- [ ] **Step 1: Read the anchor and confirm it matches**

```bash
grep -n "Completeness gate" clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md
```
Expected: `278:**Completeness gate.** You may NOT propose a verdict that COMPLETES this run while any raised finding`

**If the line number differs, that is fine - anchor on the TEXT.** If the TEXT differs, STOP and report
`STATE_MISMATCH: the Completeness gate paragraph is not as the plan describes`.

- [ ] **Step 2: Add the clause immediately after that paragraph**

The paragraph ends with the line `marker - so gating only the clean verdict would leave the hole wide
open.` Insert directly after it, separated by one blank line:

```markdown
**Record the audit in `docs/agy-test-audit-ledger.md` before this run may COMPLETE.** One row: date,
audited range, round count, verdict, and evidence that is independently checkable - the fold commits, or
the brief in `.clavity/seams/`. `none` is not a permitted evidence value: a run that found nothing still
produced a brief, so cite it. This binds to the SAME completing verdicts as the paragraph above, both of
them, for the same reason - gating only the clean verdict would leave the hole wide open.

Without this row the marker is the only trace an audit ever ran, and the marker is a debounce holding
ambient `HEAD`, not a record of what was audited. The question the loop above depends on - is a re-audit
owed? - then has no answer in the tree.
```

**ASCII ONLY.** The linter fails the file on any non-ASCII character
(`check-agy-discipline-skills.ps1`, the `$nonAscii` branch). Write `-` not an em dash.

- [ ] **Step 3: Mirror byte-for-byte into classic**

```bash
cp clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md \
   clavity-classic/plugin/skills/agy-test-audit/SKILL.md
md5sum clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md \
       clavity-classic/plugin/skills/agy-test-audit/SKILL.md | awk '{print $1}' | uniq -c
```
Expected: `2` on one hash.

- [ ] **Step 4: Re-measure the file and update the ROADMAP's line-count claim IN THE SAME COMMIT**

🔴 **This step is not optional and it is the one this plan originally missed.**
`clavity-dotnet/ROADMAP.md:1242` claims `` `agy-test-audit/SKILL.md` (377 lines) ``, and
`scripts/check-roadmap-claims.ps1` validates every such claim against the tracked file
(`check-roadmap-claims.ps1:12`, section A). Step 2 grows the file, so the claim goes FALSE the moment
this task lands. **This is the identical failure that reddened CI on 2026-09-02** when section 21 grew
all four SKILL.md files and the table was not updated (fixed at `b464db2`).

**Do not hardcode the new number from this plan - measure it:**

```bash
wc -l clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md
```
Then edit that one number inside `` `agy-test-audit/SKILL.md` (N lines) `` at `ROADMAP.md:1242` to match.
(For orientation only, and NOT to be pasted: at plan time the file was 377 lines and the clause block is
9 lines plus one blank separator, so expect 387. **If `wc -l` disagrees, `wc -l` wins.**)

- [ ] **Step 5: Run the gates this touches**

```bash
bash scripts/check-seed-artifacts-synced.sh; echo "seed=$?"
pwsh -NoProfile -Command "& './scripts/check-agy-discipline-skills.ps1'"
pwsh -NoProfile -Command "& './scripts/check-roadmap-claims.ps1'; 'roadmap=' + \$LASTEXITCODE"
```
Expected: `seed=0`, `agy-discipline skills OK`, and `roadmap=0`. **The third command is the one that
proves Step 4 landed.** If it reports a stale count, Step 4 was skipped or mis-measured - fix it here,
not later, because Task 4 runs this same gate and would only rediscover it.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md clavity-dotnet/ROADMAP.md
git commit -m "feat(s23): require a ledger row before an audit run may complete"
```

---

## Task 3: Pin the clause mechanically - TDD, test first

**Files:**
- Modify: `scripts/tests/check-agy-discipline-skills.Tests.ps1`
- Modify: `scripts/check-agy-discipline-skills.ps1`

**Why this task exists at all.** The capstone has carried the identical clause since it was written and
**no test pins it** - verified: `grep -rn "agy-capstone-ledger" scripts/tests/*.ps1` returns one hit and
it is a fixture, not an assertion. A rule with no implementation is worse than no rule, so this task pins
the SET - both disciplines that own a ledger - rather than only the one section 23 names.

- [ ] **Step 1a: Write the failing test for the ledger check**

Append inside the `Context 'rejection cases (each perturbs one skill; the other stays valid)'` block:

```powershell
        It 'REJECTS <skill> when its ledger path is stripped' -ForEach @(
            @{ skill = 'agy-capstone';   ledger = 'docs/agy-capstone-ledger.md' },
            @{ skill = 'agy-test-audit'; ledger = 'docs/agy-test-audit-ledger.md' }
        ) {
            # Both disciplines own a ledger and both REQUIRE a row before a completing verdict. The
            # capstone's clause shipped unpinned for weeks; this row closes the SET, not the instance.
            $scratch = New-ScratchRoot
            $target  = & $script:SkillPath $scratch $skill
            $real = Get-Content -Raw $target
            $real.Contains($ledger) | Should -BeTrue -Because "the fixture needs $ledger present in $skill before it can be stripped"
            $body = $real.Replace($ledger, 'docs/some-other-file.md')
            $body | Should -Not -Be $real -Because 'the strip must take effect'
            Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            # Escape the needle: the path carries regex metacharacters, and an unescaped '.' would let a
            # near-miss message satisfy this row.
            (Get-LintText $out) | Should -Match ([regex]::Escape("never names '$ledger'"))
            Remove-Item -Recurse -Force $scratch
        }
```

- [ ] **Step 1b: Write the failing test for the map's fail-closed reconciliation**

The map is consulted with `ContainsKey`, so a misspelled key raises nothing - it silently checks nothing.
That is the fails-open shape, and this repository has an existing home for exactly this defect class.
Append inside `Context 'AGY-CAPSTONE 2026-09-02: the roster itself, which nothing reconciled'`:

```powershell
        It 'fails closed when the ledger map names a discipline that is not linted' {
            # Perturb the LINTER, not a skill, so this row needs a staged copy rather than a scratch root
            # alone. New-TempLinter copies the real checker beside it, which three branches require.
            $original = Get-Content -Raw $script:Lint
            $src = $original.Replace(
                "'agy-capstone'   = 'docs/agy-capstone-ledger.md'",
                "'agy-capstoneX'  = 'docs/agy-capstone-ledger.md'")
            $src | Should -Not -Be $original -Because 'the typo must actually take effect in the copy'
            $lint    = New-TempLinter -Source $src
            $scratch = New-ScratchRoot
            $out = & $lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            (Get-LintText $out) | Should -Match 'is not a linted discipline'
            Remove-Item -Recurse -Force $scratch
        }
```

- [ ] **Step 2: Run them and watch them FAIL**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -FullNameFilter '*ledger*' -Output Minimal"
```
Expected: **3 failed**. The two `-ForEach` rows fail on `Expected 1, but got 0` - the linter has no such
check yet, so stripping the path changes nothing. The reconciliation row fails on its
`Should -Not -Be $original` self-check, because the map it perturbs does not exist yet; that is the
fixture proving its own precondition, not a broken test.

⚠ **`-FullNameFilter` EXITS 0 ON NO MATCH.** Read the COUNT in the output, never the exit code alone.

- [ ] **Step 3: Add the guard to the linter**

In `scripts/check-agy-discipline-skills.ps1`, immediately before the `foreach ($skill in $skills)` loop,
add the map:

```powershell
# The two disciplines that own a ledger, and the file each must name. A discipline with a completing
# verdict and no recorded range leaves "was this range reviewed?" unanswerable in the tree - which is
# ROADMAP section 23, ruled by the owner on 2026-09-03.
$ledgerFor = @{
    'agy-capstone'   = 'docs/agy-capstone-ledger.md'
    'agy-test-audit' = 'docs/agy-test-audit-ledger.md'
}
# FAIL CLOSED ON A TYPO. This map is keyed by discipline name and consulted with ContainsKey, so a
# misspelled key does not error - it silently checks nothing, and the guard certifies exactly what it
# stopped checking. Reconcile it against the roster that is actually iterated.
foreach ($k in $ledgerFor.Keys) {
    if ($skills -notcontains $k) {
        Fail "check-agy-discipline-skills : ledger map names '$k', which is not a linted discipline - its ledger check would never run"
    }
}
```

Then, inside the `foreach ($skill in $skills)` loop, add the check **at the END of the loop body** -
immediately after the closing brace of the `if ($skill -eq 'agy-capstone') { ... }` block that ends with
`Fail "$rel : missing the claim-type sentence - the PEER-side axis must be named claim-type"`, and
immediately before the loop's own closing brace:

```powershell
    # (i) section 23: a discipline that owns a ledger must NAME that ledger's path. The letters in this
    # loop run in source order, so this one goes last; inserting it after (f) would leave them reading
    # f, i, g, h.
    #
    # WHAT THIS MEASURES, EXACTLY: that the path string appears somewhere in the skill. It does NOT
    # measure that a row is required, and it does NOT measure that the ledger file exists - see the
    # limits section of the section-23 plan. Pinning the requirement SENTENCE verbatim was considered and
    # rejected: every rewording would be a false RED, which this repository folded twice in the section
    # 21 capstone. The check asserts the diagnostic, not the wording, and the message below says only
    # what was measured.
    if ($ledgerFor.ContainsKey($skill)) {
        if (-not $raw.Contains($ledgerFor[$skill])) {
            Fail "$rel : never names '$($ledgerFor[$skill])', so a completing verdict records nothing"
        }
    }
```

- [ ] **Step 4: Run them and watch them PASS**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -FullNameFilter '*ledger*' -Output Minimal"
```
Expected: `Tests Passed: 3, Failed: 0`.

- [ ] **Step 5: Prove EACH guard is non-vacuous against a LOGIC mutant - one at a time**

**One mutant at a time, and confirm the SPECIFIC row that reddens.** Two mutants at once cannot attribute
a red to a guard, which is the whole point of the exercise.

```bash
mkdir -p .clavity/scratch/s23
cp scripts/check-agy-discipline-skills.ps1 .clavity/scratch/s23/lint.bak
```

**Mutant A - neuter the ledger check's condition, not its subject:** change
`if ($ledgerFor.ContainsKey($skill)) {` to `if ($false) {`, then:

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -FullNameFilter '*ledger*' -Output Minimal"
cp .clavity/scratch/s23/lint.bak scripts/check-agy-discipline-skills.ps1
```
Expected: **2 failed** (the two `-ForEach` rows), **1 passed** (the reconciliation row, which this mutant
does not touch - that asymmetry is the attribution).

**Mutant B - neuter the reconciliation:** change `if ($skills -notcontains $k) {` to `if ($false) {`,
then re-run the same command.
Expected: **1 failed** (the reconciliation row), **2 passed**.

```bash
cp .clavity/scratch/s23/lint.bak scripts/check-agy-discipline-skills.ps1
md5sum scripts/check-agy-discipline-skills.ps1 .clavity/scratch/s23/lint.bak | awk '{print $1}' | uniq -c
```
Expected: `2` on one hash after the final restore. **Restore with the `cp` backup, never
`git checkout --`.** `.clavity/` is gitignored, so the backup never enters a commit - and **never
`git add -f` anything under it.**

- [ ] **Step 6: Run the whole suite**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Minimal"
```
Expected: `Tests Passed: 78, Failed: 0` (75 before this task, plus the three rows above). **A run with no
`Tests Passed:` line was ABORTED, not passed.**

- [ ] **Step 7: Commit**

```bash
git add scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "test(s23): pin the ledger row requirement in BOTH disciplines that own a ledger"
```

---

## Task 4: Reconcile the count and run every gate

**Files:**
- Modify: `scripts/tests/_partition.md`

- [ ] **Step 1: Update the row**

The current row, at `scripts/tests/_partition.md:716`, reads:
```
check-agy-discipline-skills.Tests.ps1            40,5s   75 tests   <- FAST, re-measured 2026-09-02
```
Change `75 tests` to `78 tests`. **Re-measure the runtime rather than copying 40,5s** - run the suite
once and use what it prints, and say the box was not idle.

**The count is mechanically gated**, so a wrong number here is caught rather than believed:
`test-suite-registration.Tests.ps1:185` - *"every `_partition.md` row states the CURRENT test count for
its suite"* - discovers the real count per suite. The RUNTIME is not gated; treat the seconds as
indicative.

- [ ] **Step 2: Run the gate that reads that number**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/test-suite-registration.Tests.ps1 -Output Minimal"
```
Expected: `Tests Passed: 9, Failed: 0`. **This gate EXITS 0 ON NO MATCH if filtered - read the COUNT.**

- [ ] **Step 3: Run every gate this change touches**

```bash
pwsh -NoProfile -Command "& './scripts/check-agy-discipline-skills.ps1'"
pwsh -NoProfile -Command "& './scripts/check-roadmap-claims.ps1'"
bash scripts/check-seed-artifacts-synced.sh; echo "seed=$?"
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Minimal"
```
Expected: `agy-discipline skills OK`; `check-roadmap-claims: OK`; `seed=0`; payload suite green.

**And run the SLOW half before pushing.** On 2026-09-02 a push went red on `check-roadmap-claims`, which
lives in the slow half and which no local run had covered. Four targeted gates are not "the gates".

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/_partition.md
git commit -m "docs(s23): reconcile the discipline-suite count, 75 -> 77"
```

---

## Task 5: Close section 23 in the ROADMAP with its SHAs

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md`

- [ ] **Step 1: Change the section 23 header**

The header is at `clavity-dotnet/ROADMAP.md:2088` and reads, verbatim (it carries em dashes - this file is
NOT ASCII-gated, so keep them):

```
### §23 — AGY-TEST-AUDIT has no ledger, so no audited range is recorded anywhere — ▶ **OPEN, promoted from the anomalies file 2026-08-30**
```

Replace the trailing state marker only, leaving the title untouched:

```
### §23 — AGY-TEST-AUDIT has no ledger, so no audited range is recorded anywhere — ✅ **SHIPPED 2026-09-03** — `<task1-sha>` the ledger · `<task2-sha>` the row requirement + the ROADMAP line-count · `<task3-sha>` the pins · `<task4-sha>` the suite count
```

**Substitute the four real SHAs from `git log --oneline -5`.** Do not invent them: Step 2's gate
validates closure shas as well as line counts.

**The earned rule: whoever closes an item writes its CLOSING SHA in the same commit.** Section 21 shipped
and its header still read `OPEN` a day later, which is the failure the sequencing spec's own section 1
table catalogues for sections 17, 18, 19 and 14h.

- [ ] **Step 2: Verify the claims gate**

```bash
pwsh -NoProfile -Command "& './scripts/check-roadmap-claims.ps1'"
```
Expected: `check-roadmap-claims: OK - every line-count claim and closure sha ... holds`. **This checker
validates closure shas as well as line counts**, so a fabricated sha fails here.

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): close section 23 - the AGY-TEST-AUDIT ledger shipped"
```

---

## WHAT THIS DOES NOT PROVE - state it, or the plan ships a False Safety Promise

**The linter check proves the ledger PATH is named in the skill. It proves nothing else.** Three distinct
things it does NOT establish, each stated because a comment that overclaims a guard is itself a defect
class this repository classes as BLOCKING:

1. **It does not prove any audit ever writes a row.** Same inherent gap section 21 hit: these are
   best-effort prompt-disciplines, not sandboxes, and the only mechanical enforcement available at commit
   time is that the contract text is present.
2. **It does not prove the clause REQUIRES a row.** A skill that named the file in passing prose would
   pass. Pinning the requirement sentence verbatim was rejected deliberately - every rewording becomes a
   false RED, which this repository folded twice in the section 21 capstone.
3. **It does not prove `docs/agy-test-audit-ledger.md` EXISTS.** Delete the ledger and the linter stays
   green. The obvious fix - also assert the file exists under `-Root` - was **tried and refuted**:
   `check-agy-discipline-skills.Tests.ps1:26-38` stages a scratch root containing only four `SKILL.md`
   files and no `docs/` tree, so that assertion would redden every rejection row in the suite. Resolving
   the ledger from `$PSScriptRoot` instead would work, and is not worth a second resolution rule for a
   file whose deletion would be visible in any diff.

**A stronger gate was considered and is NOT in this plan.** A hook could refuse to write
`agy-test-audit.head` unless the ledger's newest row cites the sha being marked. It is deliberately out of
scope: it is new machinery in a hook, the owner's ruling was a ledger plus a row requirement, and the
capstone has run 37 recorded times on the prose clause alone. **If a future audit is found to have
completed with no row, that is the evidence that promotes this from out-of-scope to necessary** - and it
would be visible precisely because this plan creates the file where the absence shows.

---

## Self-review

**1. Coverage.** Owner ruling has two halves: the ledger (Task 1) and the row requirement (Task 2). The
"cannot rot" property the ruling depends on is Task 3. Tasks 4-5 are the repo's own hygiene gates. No
part of the ruling is unimplemented.

**2. Placeholders.** None **now**. The first draft claimed this while Task 5 Step 1 elided the ROADMAP
header behind two `...` and named it "section 23" when the file says `### §23 —`; the panel caught it and
the header is now quoted verbatim from `ROADMAP.md:2088`. Two numbers are deliberately NOT to be copied,
and both say so at the point of use: the runtime in Task 4, and the new SKILL.md line count in Task 2
Step 4 (`wc -l` wins over the plan).

**3. Consistency.** `docs/agy-test-audit-ledger.md` is spelled identically in Tasks 1, 2, 3 and in the
`$ledgerFor` map. The column set `date | range | rounds | verdict | evidence` matches
`docs/agy-capstone-ledger.md:39-40` exactly.

**4. Known limits, stated rather than hidden.** The linter needle is **the ledger PATH, and nothing
else** - the first draft said "the PATH plus the requirement sentence" in both the self-review and the
linter's own comment, which was false against the code it specified and would have shipped a comment
asserting a guard that does not exist. The three things the check does not prove are enumerated in the
section above. **The row asserts the diagnostic, not the wording.**

**5. Panel round 1 (solo) folded eight findings.** One BLOCKING: Task 2 grows `agy-test-audit/SKILL.md`
past the `(377 lines)` claim that `check-roadmap-claims.ps1` validates, so the plan as first written went
RED at its own Task 4 gate - the identical failure that reddened CI at `b464db2`. The rest: a linter
comment asserting a needle the code does not have; a fails-open `$ledgerFor` typo hole; an elided ROADMAP
header; `/tmp` in place of the shielded scratch dir; unstated ledger row order; a mutant step that could
not attribute its red; and one refuted fix, recorded in the limits section above.

**6. Scope note for the owner.** Task 3 pins BOTH disciplines that own a ledger, not only
`agy-test-audit`. Section 23 names only the audit; the capstone's identical clause has been unpinned
since it was written. Closing the set costs one extra hashtable entry and one extra `-ForEach` case. **If
you want this narrowed to the audit alone, drop the `agy-capstone` line from `$ledgerFor` and the first
`-ForEach` case.**

---

## Stand-downs

The durable record for the panel discipline, which has no ledger file of its own.

- `DISCARDED-BELOW-FLOOR: "referenced from 23 files" is now 24` - measured `git grep -l agy-capstone-ledger | wc -l` -> 24 at `d14d18b`; it was 23 when the peer measured it and the ledger row commit `f9f8aa4` added one. The claim is rationale for NOT renaming the file, and that argument is identical at 23 or 24, so the number is not load-bearing. Volatile figures in static prose rot by construction; this one is left as-written rather than pinned.
- `DISCARDED-BELOW-FLOOR: check-plugin-drift will report drift after Task 2 until the plugin is reinstalled` - unreachable as a gate failure because nothing invokes it: `grep -rn "check-plugin-drift.ps1" justfile .github/workflows lefthook.yml` returns no hit, so it is a manual operator tool, not a gate this plan can redden.
- `REJECTED: check-growth-budget could overflow on a larger SKILL.md` - measured `scripts/check-growth-budget.ps1:55-110`: it measures the knowledge SEED and GROWTH proposal only, and names no skill payload. A SKILL.md edit cannot move that budget.
