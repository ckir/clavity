# AGY-SCOPE Disposition Amendment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make a defect's age structurally unusable as a disposition, by inserting a closed five-token
disposition taxonomy into the three review skills and gating each skill's completing verdicts on it.

**Architecture:** One shared ASCII text block is authored once and inserted into three SKILL.md files,
each with a per-skill terminus sentence and a per-skill durable-record sentence. Four existing
enumerations that the new tokens must appear in are rewritten. A fourth skill (`open-issues`) gets an
intake-bar clarification and the monorepo ROADMAP routing rule. The checker gains the tokens as required
strings, and its mutation table gains a row per token so the new requirements are non-vacuous. Every
skill ships twice, byte-identically.

**Tech Stack:** Markdown skill bodies, PowerShell 7 (`check-agy-discipline-skills.ps1`), Pester 5.8.0,
bash (`check-seed-artifacts-synced.sh`), Git Bash on Windows.

**Spec:** `docs/superpowers/specs/2026-08-07-agy-scope-disposition-design.md` (AGY-AFTER GREEN at `5c54fa3`).

---

## CRITICAL CONSTRAINTS - read before Task 1

These are not style preferences. Each one has a gate that fails if you break it.

1. **ALL INSERTED TEXT MUST BE PURE ASCII.** `check-agy-discipline-skills.ps1:54-56` counts
   `[^\x00-\x7F]` and fails the build on the first one. Measured: `agy-capstone/SKILL.md` currently has
   **0** non-ASCII characters. No em-dash (use ` - `), no curly quotes, no ellipsis character, no
   non-breaking space. `adversarial-panel-review/SKILL.md` is not enrolled in that checker and already
   contains 69 non-ASCII characters, but **write ASCII there too** so the blocks stay identical.

2. **MIRROR BY COPY, NEVER BY RETYPING.** After editing a file under `clavity-dotnet/plugin/skills/`,
   mirror it with `cp`. `scripts/check-seed-artifacts-synced.sh:23-24` diffs `hooks skills knowledge`
   across both drivers and none of these four skills is in its exception list at `:29-33`. Retyping
   reliably produces a one-character difference that fails the gate.

3. **`docs/superpowers/*` IS GITIGNORED** (`.gitignore:32`). Committing this plan or the spec needs
   `git add -f`. **Never** force-add anything under `.clavity/` (`.gitignore:45`).

4. **Prefer explicit paths over `git add -A`.** It has swept unintended files into commits on this
   public repo before.

4a. **Do NOT push between Task 2 and Task 6.** Task 2 commits a deliberately partial-red test suite.
   Measured: `.git/hooks/pre-commit` runs ruff on staged Python only, so the red commit itself is not
   blocked; and `lefthook.yml:19-46` pre-push runs nine gates but NOT Pester, so a mid-sequence push is
   not blocked either - it just lands red in CI. The suite is green again only after Task 6 Step 5.
   The owner owns every push regardless.

5. **Do not enroll `adversarial-panel-review` in the checker.** Decided by measurement, not preference:
   it has 69 non-ASCII characters and 0 references to the `$markerConstant` the checker requires, so
   enrolling it fails two gates that have nothing to do with this amendment.

**Verification commands used throughout:**

```bash
# ASCII gate + verdict presence + marker constant, for the enrolled skills
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1

# The Pester suite that guards the above
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"

# Byte parity across both driver plugins
bash scripts/check-seed-artifacts-synced.sh
```

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `docs/accepted-boundaries.md` | committed ledger of do-not-re-raise boundaries, two entry modes | **Create** |
| `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md` | taxonomy block + `ALIGNED` enum rewrite | Modify |
| `clavity-classic/plugin/skills/agy-capstone/SKILL.md` | byte-identical mirror | Copy |
| `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md` | taxonomy block + `GAPS FOUND` / marker enums + Outputs reconciliation | Modify |
| `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` | byte-identical mirror | Copy |
| `docs/agy-disciplines-marker-contract.md` | hook contract doc restating the marker completion condition | Modify |
| `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md` | taxonomy block + Outputs enum | Modify |
| `clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md` | byte-identical mirror | Copy |
| `clavity-dotnet/plugin/skills/open-issues/SKILL.md` | intake-bar clarification + ROADMAP routing | Modify |
| `clavity-classic/plugin/skills/open-issues/SKILL.md` | byte-identical mirror | Copy |
| `scripts/check-agy-discipline-skills.ps1` | require the five tokens for the two enrolled review skills | Modify |
| `scripts/tests/check-agy-discipline-skills.Tests.ps1` | taxonomy presence across all four skills + mutation rows | Modify |
| `clavity-dotnet/ROADMAP.md` | mark section 7 shipped | Modify |

---

## THE SHARED BLOCK

Tasks 2, 3 and 4 each insert this. It is identical in all three files **except** the two bracketed
sentences, which are given per-task. Pure ASCII.

```markdown
## Disposition of findings (AGY-SCOPE)

Every finding raised in any round resolves to EXACTLY ONE of these five tokens. The set is closed -
there is no sixth outcome, and nothing may sit "noted" or "acknowledged".

- `FOLDED: <what changed>` - fixed inside the current work.
- `REJECTED: <measured reason>` - the finding is false, killed by a measurement you quote: a `file:line`
  or the tool stdout.
- `DISCARDED-BELOW-FLOOR: <target> unreachable because <guard>` - contrived, exotic or unreachable. You
  MUST cite the structural guard, invariant or precondition at `file:line` that makes it unreachable.
  Prose alone is not enough; this token carries the same evidentiary bar as `REJECTED`.
- `DEFERRED-TO-ANOMALIES: <anchor> * <YYYY-MM-DD>[ * unverified]` - reachable, not fixed now. `<anchor>`
  is the SOURCE location as `file:line`, or the literal `n/a` when the defect has no single line. The
  date identifies the inbox entry; never cite an inbox LINE NUMBER, because triage deletes entries and
  shifts them. Append ` * unverified` when the captured entry is a `reported, unverified:` claim.
- `UNVERIFIED-ACCEPTED: <finding>` - neither provable nor refutable, and the owner accepted the risk.

**A defect's age is NEVER a disposition.** "Pre-existing", "not introduced by this commit" and "out of
scope for this change" are not admissible stand-down reasons, and neither is any paraphrase of them. The
only admissible stand-down is the reachability floor, which is age-blind. This does not make a bad
stand-down impossible - it forces one to be stated as a falsifiable reachability claim that a peer can
open the file and contradict.

**Scope bound - age-blind reachability from the touched surface.** In scope: the reviewed diff or
artifact, plus the contracts, invariants, schemas and execution paths that INTERSECT it. Out of scope:
open-ended discovery in unrelated modules. If a path or contract touched by the change exposes a defect,
that defect is in scope regardless of when the faulty line was authored.

**Deferral is bounded by CAUSATION, not by line membership.** `DEFERRED-TO-ANOMALIES` is available only
for a defect already reachable BEFORE this change, whose failure mode this change did not induce. Any
failure this change causes must be `FOLDED`, regardless of which line the symptom appears on: a change at
`x.rs:50` that panics untouched `x.rs:120` was caused by the change and is not deferrable.

**A material deferral does not clear a completing verdict on your own authority.** A `MATERIAL` defect
disposed as `DEFERRED-TO-ANOMALIES` needs an owner ruling first, exactly like the UNVERIFIED path. A
`DISCARDED-BELOW-FLOOR` item clears on its own cited guard, because "not material" is what that token
asserts.

**Order matters.** Append to `.clavity/local-anomalies.md` FIRST, via the `open-issues` skill, then emit
the token citing it. A token pointing at an entry that was never written is the rot this replaces. The
peer never writes to that file: a subagent REPORTS, the driver VERIFIES, the driver WRITES.

**Completeness gate.** You may NOT propose a verdict that COMPLETES this run while any raised finding
lacks one of the five tokens. [TERMINUS SENTENCE]

**Anti-sweep.** Each run lists the top 1-2 findings it discarded below the floor, so a real defect cannot
be swept under the floor unseen. [DURABLE RECORD SENTENCE]
```

---

## Task 1: Create the accepted-boundaries ledger

**Files:**
- Create: `docs/accepted-boundaries.md`

- [ ] **Step 1: Confirm the file does not already exist**

```bash
ls docs/accepted-boundaries.md docs/coverage-debt.md
```

Expected: `No such file or directory` for **both**. If either exists, STOP and report
`STATE_MISMATCH: <which file exists>` - the spec was written against their absence.

- [ ] **Step 2: Create the file**

The outer fence below is FOUR backticks because the file content itself contains three-backtick fences.
Everything between the four-backtick markers is the literal file content, inner fences included.

````markdown
# Accepted boundaries

The do-not-re-raise ledger. One entry per line, section-partitioned by product. This file is COMMITTED,
because `agy-test-audit` re-validates every entry on a later run and a gitignored file cannot serve that.

Deferred debt does NOT live here - it rides `.clavity/local-anomalies.md` to a tracked `ROADMAP.md` item.
This file holds only boundaries that are deliberately, permanently not covered.

## Entry modes

**Compensated** - the normal case. Something else covers the behaviour, and a future audit re-validates
that the compensation still exists. An entry whose compensation has vanished is promoted back to a live
gap.

```
- [boundary] <behaviour not covered> * <source/path.ext:LINE> * compensation=<what covers it, with its code anchor> * <YYYY-MM-DD>
```

**Owner-accepted** - an `UNVERIFIED-ACCEPTED` finding: neither provable nor refutable, and the owner
accepted the risk. There is no compensating artifact by definition. A future audit re-validates such an
entry by confirming the cited source anchor still exists, not by hunting a compensation nobody claimed.

```
- [boundary] <finding> * <source/path.ext:LINE> * compensation=owner-accepted:<YYYY-MM-DD> <rationale> * <YYYY-MM-DD>
```

## Maintenance

Section-partitioned to keep merge conflicts survivable: a single flat file touched at every branch-finish
is a hotspot where a careless `--ours`/`--theirs` silently drops a teammate's entry. Sort by source path
within a section.

A periodic manual whole-tree garbage-collection pass reconciles this file against current code and drops
orphaned entries. A routine diff-scoped run cannot see deleted code, so it cannot prune stale entries.

## clavity-dotnet

_(none yet)_

## clavity-classic

_(none yet)_

## ghidrust

_(none yet)_

## agy-autotrain

_(none yet)_

## commonmemory

_(none yet)_

## shared

Root and cross-product code: `scripts/`, root `docs/`, CI workflows.

_(none yet)_
````

- [ ] **Step 3: Confirm it is NOT added to the user-facing docs roster**

```bash
grep -n "accepted-boundaries" docs/user-facing-docs.txt
```

Expected: no output (exit 1). This file is an internal engineering ledger. The precedent is
`docs/agy-capstone-ledger.md`, which is also absent from that roster.

- [ ] **Step 4: Commit**

```bash
git add docs/accepted-boundaries.md
git commit -m "docs(boundaries): create the accepted-boundary ledger with two entry modes"
```

---

## Task 2: agy-capstone - taxonomy block and ALIGNED enum

**Files:**
- Modify: `scripts/tests/check-agy-discipline-skills.Tests.ps1` (new Describe block)
- Modify: `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md:99-101` and `:177-179`
- Copy: `clavity-classic/plugin/skills/agy-capstone/SKILL.md`

- [ ] **Step 1: Verify the state matches this plan before editing**

```bash
awk 'NR>=99&&NR<=101{print NR"|"$0}' clavity-dotnet/plugin/skills/agy-capstone/SKILL.md
awk 'NR>=177&&NR<=179{print NR"|"$0}' clavity-dotnet/plugin/skills/agy-capstone/SKILL.md
```

Expected `:99-101`:

```
99|- **Reachability floor.** Stop nitpicking: a round producing only stylistic or contrived-edge
100|  observations - nothing touching correctness / safety / contract / completeness - counts as no live
101|  challenge.
```

Expected `:177-179`:

```
177|- `[VERDICT: ALIGNED]` - a **clean terminal round**: every finding across the run has a disposition -
178|  folded (fixed + measured clean), killed by measurement (`[VERDICT: REJECTED - ...]`), or explicitly
179|  human-accepted as an UNVERIFIED risk - and no material unrefuted defect remains. A run whose findings
```

If either differs, STOP and report `STATE_MISMATCH: <what differs>`. Do not adapt.

- [ ] **Step 2: Write the failing test**

Append this Describe block to the END of `scripts/tests/check-agy-discipline-skills.Tests.ps1`:

```powershell
Describe 'AGY-SCOPE disposition taxonomy' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
        $script:Tokens = @(
            'FOLDED: '
            'REJECTED: '
            'DISCARDED-BELOW-FLOOR: '
            'DEFERRED-TO-ANOMALIES: '
            'UNVERIFIED-ACCEPTED: '
        )
    }

    It 'ships every disposition token in <skill>' -ForEach @(
        @{ skill = 'agy-capstone' }
        @{ skill = 'agy-test-audit' }
        @{ skill = 'adversarial-panel-review' }
    ) {
        foreach ($driver in @('clavity-dotnet', 'clavity-classic')) {
            $p = Join-Path $script:RepoRoot "$driver/plugin/skills/$skill/SKILL.md"
            $raw = Get-Content -Raw $p
            foreach ($t in $script:Tokens) {
                $raw.Contains($t) | Should -BeTrue -Because "$driver/$skill must carry the token '$t'"
            }
        }
    }

    It 'forbids age as a disposition in <skill>' -ForEach @(
        @{ skill = 'agy-capstone' }
        @{ skill = 'agy-test-audit' }
        @{ skill = 'adversarial-panel-review' }
    ) {
        foreach ($driver in @('clavity-dotnet', 'clavity-classic')) {
            $p = Join-Path $script:RepoRoot "$driver/plugin/skills/$skill/SKILL.md"
            (Get-Content -Raw $p).Contains("A defect's age is NEVER a disposition.") |
                Should -BeTrue -Because "$driver/$skill must carry the age clause"
        }
    }
}
```

- [ ] **Step 3: Run the test to verify it FAILS**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"
```

Expected: **6 failures** in the new Describe (3 skills x 2 tests), each naming a missing token or the
missing age clause. The pre-existing tests must still pass. If the new tests PASS, STOP - the text is
already present and this plan's premise is wrong.

- [ ] **Step 4: Redirect the floor bullet, then insert the shared block as its own section**

`:99-101` is a BULLET IN THE MIDDLE OF A LIST - `:95` is "Forcing functions", `:102` is "Rotate seats
across rounds". Dropping a `##` heading at `:99` would orphan `:102` and split the list. So do two
separate edits.

**4a.** Replace the three-line bullet at `:99-101`:

```
- **Reachability floor.** Stop nitpicking: a round producing only stylistic or contrived-edge
  observations - nothing touching correctness / safety / contract / completeness - counts as no live
  challenge.
```

with:

```
- **Reachability floor.** Stop nitpicking: a round producing only stylistic or contrived-edge
  observations - nothing touching correctness / safety / contract / completeness - counts as no live
  challenge. Standing a finding down on that floor is the `DISCARDED-BELOW-FLOOR` disposition and carries
  its evidentiary bar - see "Disposition of findings (AGY-SCOPE)" below.
```

**4b.** Insert the SHARED BLOCK as a new section immediately BEFORE the line
`## Division of labor: peer REVIEWS, driver MEASURES (the spine)`, with these two substitutions:

`[TERMINUS SENTENCE]` becomes:

```
For this skill that means `[VERDICT: ALIGNED]`.
```

`[DURABLE RECORD SENTENCE]` becomes:

```
The full list goes in the ephemeral per-run report; a one-line summary of each goes in the committed
`docs/agy-capstone-ledger.md` row for this run. An `UNVERIFIED-ACCEPTED` is recorded as a durable line in
`.clavity/agy-marks/skipped.log`, in the existing format.
```

**The block does NOT replace the floor bullet.** It extends it: `DISCARDED-BELOW-FLOOR` IS the floor, now
with an evidentiary bar, and Step 4a leaves the bullet in place with a pointer appended. Deleting `:99-101`
would orphan `:102` ("Rotate seats across rounds") out of its list - do not do it.

- [ ] **Step 5: Rewrite the ALIGNED enumeration**

Replace exactly these three lines (`:177-179` before your Step 4 edit shifted them - find them by text,
not by number):

```
- `[VERDICT: ALIGNED]` - a **clean terminal round**: every finding across the run has a disposition -
  folded (fixed + measured clean), killed by measurement (`[VERDICT: REJECTED - ...]`), or explicitly
  human-accepted as an UNVERIFIED risk - and no material unrefuted defect remains. A run whose findings
```

with:

```
- `[VERDICT: ALIGNED]` - a **clean terminal round**: every finding across the run carries one of the five
  AGY-SCOPE disposition tokens above - `FOLDED`, `REJECTED`, `DISCARDED-BELOW-FLOOR`,
  `DEFERRED-TO-ANOMALIES` or `UNVERIFIED-ACCEPTED` - and no material unrefuted defect remains UNRULED: a
  material `DEFERRED-TO-ANOMALIES` needs the owner's ruling before this verdict, while a
  `DISCARDED-BELOW-FLOOR` clears on its own cited guard. A run whose findings
```

**Do not touch the following line**, which continues `were ALL refuted-by-measurement IS ALIGNED ...`.

- [ ] **Step 6: Verify pure ASCII before mirroring**

```bash
perl -CSD -ne '$n += () = /[^\x00-\x7F]/g; END{print "non-ASCII: $n\n"}' clavity-dotnet/plugin/skills/agy-capstone/SKILL.md
```

Expected: `non-ASCII: 0`. If nonzero, find and fix the character before continuing - the checker will
fail the build otherwise.

- [ ] **Step 7: Mirror to clavity-classic by copy**

```bash
cp clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md
cmp clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md && echo IDENTICAL
```

Expected: `IDENTICAL`.

- [ ] **Step 8: Run the tests and gates**

```bash
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"
bash scripts/check-seed-artifacts-synced.sh
```

Expected: the checker exits 0. Pester shows the `agy-capstone` rows of both new tests PASSING; the
`agy-test-audit` and `adversarial-panel-review` rows still FAIL (Tasks 3 and 4 fix those). Seed-sync
passes. **Read the counts, do not just check for absence of failure.**

- [ ] **Step 9: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-capstone/SKILL.md clavity-classic/plugin/skills/agy-capstone/SKILL.md scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "feat(agy-capstone): add the AGY-SCOPE disposition taxonomy and rewrite the ALIGNED enum"
```

This commit is deliberately partial-red on the two new data-driven tests: the other two skills do not
carry the block yet. Tasks 3 and 4 clear it. This matches the accepted pattern for this repo.

---

## Task 3: agy-test-audit - taxonomy, completion enums, and the debt-file reconciliation

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md:64-66`, `:111-118`, `:134-136`, `:154-155`
- Copy: `clavity-classic/plugin/skills/agy-test-audit/SKILL.md`

- [ ] **Step 1: Verify state**

```bash
awk 'NR>=64&&NR<=66{print NR"|"$0}' clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md
awk 'NR>=134&&NR<=136{print NR"|"$0}' clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md
awk 'NR>=154&&NR<=155{print NR"|"$0}' clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md
```

Expected `:134-136`:

```
134|- `[VERDICT: GAPS FOUND]` - one or more verified gaps remain; each is owner-scoped (closed now, or deferred
135|  and logged as tracked debt). A GAPS-FOUND run is legitimately "done" only when every gap is either closed
136|  or recorded as deferred debt.
```

Expected `:154-155`:

```
154|- **Written ONLY on a completed audit** - an `[VERDICT: EXHAUSTIVE]`, or a `[VERDICT: GAPS FOUND]` whose
155|  gaps are all owner-dispositioned (closed or logged as deferred debt). An `agy-required-but-unreachable`
```

If either differs, STOP and report `STATE_MISMATCH: <what differs>`.

- [ ] **Step 2a: Redirect the existing floor language**

`:64-66` sits inside numbered item 1 of "The audit round" - do NOT put a heading there. Replace only this
sentence fragment:

```
Apply a **severity floor** (skip trivial/contrived nits) - and require
   the audit to **list the top 1-2 gaps it discarded below the floor**, so a real gap cannot be swept under
   the floor unseen.
```

with:

```
Apply a **severity floor** (skip trivial/contrived nits) - and require
   the audit to **list the top 1-2 gaps it discarded below the floor**, so a real gap cannot be swept under
   the floor unseen. Standing a gap down on that floor is the `DISCARDED-BELOW-FLOOR` disposition and
   carries its evidentiary bar - see "Disposition of findings (AGY-SCOPE)" below.
```

- [ ] **Step 2b: Insert the shared block as its own section**

Insert the SHARED BLOCK as a new section immediately BEFORE the line `## Capstone-invalidation rule (the discipline's sharpest edge)`, with these substitutions:

`[TERMINUS SENTENCE]` becomes:

```
For this skill that means BOTH `[VERDICT: EXHAUSTIVE]` AND `[VERDICT: GAPS FOUND]`. GAPS FOUND is a
COMPLETING terminus - it ends the run and writes the debounce marker - so gating only the clean verdict
would leave the hole wide open.
```

`[DURABLE RECORD SENTENCE]` becomes:

```
The full list goes in the ephemeral per-run report; a one-line summary of each goes in the branch-finish
commit message. An `UNVERIFIED-ACCEPTED` is recorded in `docs/accepted-boundaries.md` under its
owner-accepted mode.
```

- [ ] **Step 3: Reconcile the rolling committed file at `:111-118`**

Replace this bullet:

```
- **A single, stable, ROLLING COMMITTED file** - default `docs/coverage-debt.md` (a project may override the
  path) - holding ONLY what must persist: **unresolved tracked debt** (owner-deferred gaps) and the
  **accepted-boundary ledger** (the do-not-re-raise list, each with its compensation + anchor). Closed gaps
  are removed. Structure it append-only / section-partitioned to minimize merge conflicts (a single file
  touched every branch-finish is a conflict hotspot where a careless `--ours`/`--theirs` silently drops a
  teammate's entry). A periodic **manual whole-tree garbage-collection pass** reconciles it against current
  code and drops orphaned entries - the routine diff-scoped run cannot see deleted code to prune stale
  entries.
```

with:

```
- **A single, stable, ROLLING COMMITTED file** - default `docs/accepted-boundaries.md` (a project may
  override the path) - holding ONLY the **accepted-boundary ledger**: the do-not-re-raise list, each entry
  with its compensation + anchor, or under the owner-accepted mode for an `UNVERIFIED-ACCEPTED` finding.
  Closed entries are removed. **Owner-deferred gaps do NOT live here** - they are deferred debt and ride
  `.clavity/local-anomalies.md` to a tracked `ROADMAP.md` item like every other deferral, so this file does
  not become a second backlog. Structure it append-only / section-partitioned to minimize merge conflicts
  (a single file touched every branch-finish is a conflict hotspot where a careless `--ours`/`--theirs`
  silently drops a teammate's entry). A periodic **manual whole-tree garbage-collection pass** reconciles
  it against current code and drops orphaned entries - the routine diff-scoped run cannot see deleted code
  to prune stale entries.
```

- [ ] **Step 3b: Fix the FIFTH restatement, at `:82` - the one that now contradicts Step 3**

Step 3 just redefined the rolling committed file as boundaries-ONLY and said in so many words that
owner-deferred gaps do NOT live there. But numbered item 4 of "The audit round", ~30 lines ABOVE it, still
routes deferred gaps INTO that same file. Left alone, this task ships a skill that contradicts itself
within one screen. Find it by text, not by number - Step 2a and 2b have already shifted this file.

Verify state first:

```bash
grep -n "in the rolling debt file (below)" clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md
```

Expected: exactly ONE hit. If zero or more than one, STOP and report `STATE_MISMATCH: <count>`.

Replace:

```
   the owner **defers must be logged as tracked debt** in the rolling debt file (below) - a
   GAPS-FOUND-but-all-deferred outcome is legitimate only if recorded, so a defer-everything habit is
   visible in one place and the discipline cannot degrade into run-then-defer theater.
```

with:

```
   the owner **defers must be logged as tracked debt** on the anomalies conveyor
   (`.clavity/local-anomalies.md`, promoted to a tracked `ROADMAP.md` item) - NOT in the rolling committed
   file below, which holds accepted boundaries only. A GAPS-FOUND-but-all-deferred outcome is legitimate
   only if recorded, so a defer-everything habit is visible in one place and the discipline cannot degrade
   into run-then-defer theater.
```

- [ ] **Step 4: Rewrite the GAPS FOUND completion condition**

Replace:

```
- `[VERDICT: GAPS FOUND]` - one or more verified gaps remain; each is owner-scoped (closed now, or deferred
  and logged as tracked debt). A GAPS-FOUND run is legitimately "done" only when every gap is either closed
  or recorded as deferred debt.
```

with:

```
- `[VERDICT: GAPS FOUND]` - one or more verified gaps remain; each carries one of the five AGY-SCOPE
  disposition tokens above. A GAPS-FOUND run is legitimately "done" only when EVERY gap carries such a
  token - closed now (`FOLDED`), refuted by measurement (`REJECTED`), stood down on a cited reachability
  guard (`DISCARDED-BELOW-FLOOR`), deferred and logged as tracked debt (`DEFERRED-TO-ANOMALIES`), or
  owner-accepted as unverifiable (`UNVERIFIED-ACCEPTED`).
```

- [ ] **Step 5: Rewrite the marker-writing condition**

Replace:

```
- **Written ONLY on a completed audit** - an `[VERDICT: EXHAUSTIVE]`, or a `[VERDICT: GAPS FOUND]` whose
  gaps are all owner-dispositioned (closed or logged as deferred debt). An `agy-required-but-unreachable`
```

with:

```
- **Written ONLY on a completed audit** - an `[VERDICT: EXHAUSTIVE]`, or a `[VERDICT: GAPS FOUND]` whose
  gaps ALL carry an AGY-SCOPE disposition token. An `agy-required-but-unreachable`
```

**Do not touch the following line**, which continues `abort writes NO marker ...`.

- [ ] **Step 5b: Fold the SAME enumeration where it is restated OUTSIDE the skill**

`docs/agy-disciplines-marker-contract.md:66-69` is the hook CONTRACT doc - the authority a hook implementer
reads - and it restates the marker condition Step 5 just rewrote, in the same closed binary that has no slot
for `UNVERIFIED-ACCEPTED`. It also names "the rolling debt file", which Step 3 just redefined as
boundaries-only. Leaving it is the incomplete-fold defect this repo keeps re-earning.

Verify state first:

```bash
awk 'NR>=66&&NR<=69{print NR"|"$0}' docs/agy-disciplines-marker-contract.md
```

Expected:

```
66|- `agy-test-audit` writes `agy-test-audit.head` only on a **completed audit**: an `[VERDICT: EXHAUSTIVE]`,
67|  or a `[VERDICT: GAPS FOUND]` whose every gap is owner-dispositioned (closed or logged as deferred debt
68|  in the rolling debt file). An `[VERDICT: agy-required-but-unreachable]` abort writes NO marker (re-fires
69|  next trigger). Content is the audited `git rev-parse HEAD`.
```

If it differs, STOP and report `STATE_MISMATCH: <what differs>`. Then replace those four lines with:

```
- `agy-test-audit` writes `agy-test-audit.head` only on a **completed audit**: an `[VERDICT: EXHAUSTIVE]`,
  or a `[VERDICT: GAPS FOUND]` whose every gap carries one of the five AGY-SCOPE disposition tokens
  (`FOLDED`, `REJECTED`, `DISCARDED-BELOW-FLOOR`, `DEFERRED-TO-ANOMALIES`, `UNVERIFIED-ACCEPTED`); a
  material `DEFERRED-TO-ANOMALIES` needs the owner's ruling first. An
  `[VERDICT: agy-required-but-unreachable]` abort writes NO marker (re-fires
  next trigger). Content is the audited `git rev-parse HEAD`.
```

This file is under `docs/`, so it is neither ASCII-gated nor seed-synced - no mirror step, no ASCII check.
`:64`'s existing "capstone's WAIVED / UNVERIFIED-ACCEPTED distinctions live in the log" needs NO change: it
already uses the token in the sense this amendment formalises.

- [ ] **Step 6: Verify ASCII, then mirror**

```bash
perl -CSD -ne '$n += () = /[^\x00-\x7F]/g; END{print "non-ASCII: $n\n"}' clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md
cp clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md
cmp clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md && echo IDENTICAL
```

Expected: `non-ASCII: 0` then `IDENTICAL`.

- [ ] **Step 7: Confirm no stale reference to the old debt file survives**

```bash
grep -rn "coverage-debt" clavity-dotnet/plugin clavity-classic/plugin scripts docs --include=*.md --include=*.ps1 --include=*.sh
```

Expected: no output. The dominant fold defect in this repo is an INCOMPLETE fold; this is the sweep that
catches it. If anything is found, fix it in the same task **and add its path to Step 9's `git add` line** -
Step 9 names explicit paths, so a fix outside those paths would otherwise sit unstaged and be swept into a
later task's commit unlabelled.

- [ ] **Step 8: Run the gates**

```bash
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"
bash scripts/check-seed-artifacts-synced.sh
```

Expected: checker exits 0; the `agy-test-audit` rows of both new tests now PASS; only the
`adversarial-panel-review` rows still fail.

- [ ] **Step 9: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md docs/agy-disciplines-marker-contract.md
git commit -m "feat(agy-test-audit): disposition taxonomy, completion enums, and the boundaries-file split"
```

---

## Task 4: adversarial-panel-review - taxonomy and the Outputs enum

**Files:**
- Modify: `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md:149-154` and `:231-240`
- Copy: `clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md`

- [ ] **Step 1: Verify state**

```bash
awk 'NR>=149&&NR<=154{print NR"|"$0}' clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md
awk 'NR>=231&&NR<=240{print NR"|"$0}' clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md
```

Expected `:231-240` to be the `## Outputs` section, ending with the `cap-reached` bullet. If it differs,
STOP and report `STATE_MISMATCH: <what differs>`.

- [ ] **Step 2a: Redirect the existing floor language**

`:149-154` is a standalone paragraph in the Step 5 stop-conditions section. Append one sentence to the
end of it, after `...never stop early just to save spend.`:

```
Standing a finding down on that floor is the `DISCARDED-BELOW-FLOOR` disposition and carries its
evidentiary bar - see "Disposition of findings (AGY-SCOPE)" below.
```

- [ ] **Step 2b: Insert the shared block as its own section**

Insert the SHARED BLOCK as a new section immediately BEFORE the line `## Seat & persona palette`, with
these substitutions:

`[TERMINUS SENTENCE]` becomes:

```
For this skill that means `GREEN`. Note the interaction with the stop conditions above: those stop the
ROUNDS, this gate blocks the VERDICT. A run that stops with findings untokenized reports the open-findings
disposition instead, never `GREEN`.
```

`[DURABLE RECORD SENTENCE]` becomes:

```
The full list goes in the ephemeral per-run report; a one-line summary of each goes in a `## Stand-downs`
section written into the REVIEWED ARTIFACT itself. This discipline reviews a pre-implementation artifact
and a clean round may produce no commit at all, so the artifact is the only durable record available. An
`UNVERIFIED-ACCEPTED` goes in that same section.
```

- [ ] **Step 3: Extend the Outputs enumeration**

Insert this bullet into `## Outputs`, immediately after the `A running ledger of folded findings` bullet
and before the `A final disposition` bullet:

```
- A `## Stand-downs` section written into the reviewed artifact, listing each `DISCARDED-BELOW-FLOOR` and
  `UNVERIFIED-ACCEPTED` on one line with its citation. This is the durable record for this discipline,
  which has neither a ledger file nor a guaranteed commit.
```

- [ ] **Step 4: Mirror**

```bash
cp clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md
cmp clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md && echo IDENTICAL
```

Expected: `IDENTICAL`. (No ASCII check here - this skill is not enrolled in the checker and already
carries 69 non-ASCII characters. Do not "fix" those; that is out of scope and would balloon the diff.)

- [ ] **Step 5: Run the gates**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"
bash scripts/check-seed-artifacts-synced.sh
```

Expected: **both new tests now pass all three rows**. Read the counts.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md
git commit -m "feat(panel-review): disposition taxonomy and the stand-downs output"
```

---

## Task 5: open-issues - intake bar and ROADMAP routing

**Files:**
- Modify: `clavity-dotnet/plugin/skills/open-issues/SKILL.md:14-15` and `:177-178`
- Copy: `clavity-classic/plugin/skills/open-issues/SKILL.md`

- [ ] **Step 1: Verify state**

```bash
awk 'NR>=14&&NR<=15{print NR"|"$0}' clavity-dotnet/plugin/skills/open-issues/SKILL.md
awk 'NR>=177&&NR<=178{print NR"|"$0}' clavity-dotnet/plugin/skills/open-issues/SKILL.md
```

Expected:

```
14|> Capture any reachable code defect, tool misbehavior, or operational blocker that actively degrades or
15|> prevents the agent/owner workflow.
177|1. **PROMOTE** it to a tracked item with an owner and a slot - a `ROADMAP.md` entry, or a plan, or an
178|   immediate fix if it is cheap enough to just do. Then delete the line.
```

If either differs, STOP and report `STATE_MISMATCH: <what differs>`.

- [ ] **Step 2: Clarify the intake bar**

Replace lines 14-15 with:

```
> Capture any reachable code defect; or any tool misbehavior or operational blocker that actively
> degrades or prevents the agent/owner workflow.
```

The semicolon makes the qualifier attach only to the latter two. Without it, a reachable defect in
shipped product code - exactly what a capstone finds and defers here - arguably fails the bar and could
not legitimately be captured, which would break `DEFERRED-TO-ANOMALIES` on its commonest case. The
opinion-exclusion two paragraphs below is untouched and still does the narrowing.

- [ ] **Step 3: Add the monorepo ROADMAP routing rule**

Replace lines 177-178 with:

```
1. **PROMOTE** it to a tracked item with an owner and a slot - a `ROADMAP.md` entry, or a plan, or an
   immediate fix if it is cheap enough to just do. Then delete the line. **Which `ROADMAP.md`:** this is a
   monorepo and several exist. Promote into the ROADMAP of the product that OWNS the defective file. For
   shared or root-level code (`scripts/`, root `docs/`, CI workflows), use `clavity-dotnet/ROADMAP.md`,
   which already carries the cross-cutting sections.
```

- [ ] **Step 4: Mirror**

```bash
cp clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md
cmp clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md && echo IDENTICAL
```

- [ ] **Step 5: Run the gates**

```bash
bash scripts/check-seed-artifacts-synced.sh
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed"
```

Expected: seed-sync passes; the anomaly-capture suite still passes (it exercises the hooks that read this
inbox, and this task changes the skill that writes to it).

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md
git commit -m "feat(open-issues): disambiguate the intake bar and route promotions by product ownership"
```

---

## Task 6: Mechanical enforcement, made non-vacuous

**Files:**
- Modify: `scripts/check-agy-discipline-skills.ps1:18-22`
- Modify: `scripts/tests/check-agy-discipline-skills.Tests.ps1:43-47`

- [ ] **Step 1: Verify state**

```bash
awk 'NR>=18&&NR<=22{print NR"|"$0}' scripts/check-agy-discipline-skills.ps1
awk 'NR>=43&&NR<=47{print NR"|"$0}' scripts/tests/check-agy-discipline-skills.Tests.ps1
```

Expected checker `:18-22`:

```
18|$requiredVerdicts = @{
19|    'agy-first'      = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
20|    'agy-capstone'   = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
21|    'agy-test-audit' = @('[VERDICT: EXHAUSTIVE]', '[VERDICT: GAPS FOUND]', '[VERDICT: agy-required-but-unreachable]')
22|}
```

Expected test `:43-47`:

```
43|        It 'fails when a required [VERDICT] form is missing from <skill>' -ForEach @(
44|            @{ skill = 'agy-first';      token = '[VERDICT: SKIPPED-UNREACHABLE]' },
45|            @{ skill = 'agy-capstone';   token = '[VERDICT: SKIPPED-UNREACHABLE]' },
46|            @{ skill = 'agy-test-audit'; token = '[VERDICT: EXHAUSTIVE]' }
47|        ) {
48|            $scratch = New-ScratchRoot
```

If either differs, STOP and report `STATE_MISMATCH: <what differs>`.

- [ ] **Step 2: Add the mutation rows FIRST, so they fail**

Replace the `-ForEach` data at `:44-46` with:

```powershell
            @{ skill = 'agy-first';      token = '[VERDICT: SKIPPED-UNREACHABLE]' },
            @{ skill = 'agy-capstone';   token = '[VERDICT: SKIPPED-UNREACHABLE]' },
            @{ skill = 'agy-test-audit'; token = '[VERDICT: EXHAUSTIVE]' },
            @{ skill = 'agy-capstone';   token = 'FOLDED: ' },
            @{ skill = 'agy-capstone';   token = 'REJECTED: ' },
            @{ skill = 'agy-capstone';   token = 'DISCARDED-BELOW-FLOOR: ' },
            @{ skill = 'agy-capstone';   token = 'DEFERRED-TO-ANOMALIES: ' },
            @{ skill = 'agy-capstone';   token = 'UNVERIFIED-ACCEPTED: ' },
            @{ skill = 'agy-test-audit'; token = 'FOLDED: ' },
            @{ skill = 'agy-test-audit'; token = 'REJECTED: ' },
            @{ skill = 'agy-test-audit'; token = 'DISCARDED-BELOW-FLOOR: ' },
            @{ skill = 'agy-test-audit'; token = 'DEFERRED-TO-ANOMALIES: ' },
            @{ skill = 'agy-test-audit'; token = 'UNVERIFIED-ACCEPTED: ' }
```

This test mutates a scratch copy by replacing the token with `[VERDICT: GONE]` and asserts the checker
exits 1. The ten new rows are the NON-VACUITY PROOF: without them, a token could be added to
`$requiredVerdicts` and nothing would prove the checker actually enforces it.

- [ ] **Step 3: Run and verify the ten new rows FAIL**

```bash
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"
```

Expected: **exactly the 10 new rows fail** with `$LASTEXITCODE` being 0 instead of 1 - the checker does
not yet require those tokens, so removing one does not fail it. The 3 original rows pass. **Confirm the
specific new rows are the failing ones by name; a bare non-zero count is not proof.**

- [ ] **Step 4: Add the tokens to the checker**

Replace `$requiredVerdicts` at `:18-22` with:

```powershell
# The AGY-SCOPE disposition taxonomy (spec 2026-08-07). Required for the two review disciplines ENROLLED
# in this checker. agy-first is excluded on purpose: it is a consult discipline and raises no findings to
# dispose of. adversarial-panel-review DOES carry the taxonomy but is not enrolled in $skills at all (it
# has 69 non-ASCII chars and no marker constant); it is pinned instead by the
# 'AGY-SCOPE disposition taxonomy' Describe in scripts/tests/check-agy-discipline-skills.Tests.ps1.
$dispositionTokens = @(
    'FOLDED: '
    'REJECTED: '
    'DISCARDED-BELOW-FLOOR: '
    'DEFERRED-TO-ANOMALIES: '
    'UNVERIFIED-ACCEPTED: '
)
$requiredVerdicts = @{
    'agy-first'      = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]')
    'agy-capstone'   = @('[VERDICT: ALIGNED]', '[VERDICT: REJECTED - ', '[VERDICT: NEGOTIATE - ', '[VERDICT: SKIPPED-UNREACHABLE]') + $dispositionTokens
    'agy-test-audit' = @('[VERDICT: EXHAUSTIVE]', '[VERDICT: GAPS FOUND]', '[VERDICT: agy-required-but-unreachable]') + $dispositionTokens
}
```

Note `'REJECTED: '` and `'[VERDICT: REJECTED - '` are distinct substrings and do not collide: one ends
`: `, the other `- `.

- [ ] **Step 5: Run and verify ALL rows now pass**

```bash
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"
```

Expected: checker exits 0; **13 rows pass** on the mutation test, plus the taxonomy Describe from Task 2.
Read the counts.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "feat(checker): require the disposition tokens, with a mutation row per token"
```

---

## Task 7: Enumeration re-sweep, full gate, and ROADMAP

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md:494`

- [ ] **Step 1: Re-sweep for enumerations the amendment must appear in**

This defect class produced 5 of the spec's findings and one instance survived four review rounds
undetected. Sweep before declaring done:

**The sweep MUST reach beyond the skills.** The enumeration this class hides in has already been found on a
NON-skill surface once (`docs/agy-disciplines-marker-contract.md:66-69`, folded into Task 3 Step 5b). A sweep
scoped to `plugin/skills/` is scoped to miss exactly the case it exists to catch. Grep `docs/` and `scripts/`
too, and match case-insensitively - the shared block writes "EXACTLY ONE of" in caps.

```bash
grep -rni "one of:\|exactly one of\|is legitimately\|A final disposition\|owner-dispositioned\|deferred debt\|rolling debt file" \
  clavity-dotnet/plugin/skills docs scripts \
  --include=*.md --include=*.ps1 --include=*.sh --include=*.txt --include=*.json
```

Exclude hits under `docs/superpowers/` (specs and plans are point-in-time records, not live contracts) and
`docs/agy-capstone-ledger.md` (append-only history). For every other hit, decide whether the five tokens
must appear in that list. The five known ones are handled by Tasks 2-5 and Task 3 Step 5b. If a NEW one is
found, fold it in this task before continuing, mirror it if it lives under `plugin/`, and stage it
explicitly in Step 6's `git add`.

- [ ] **Step 2: Confirm the mirrors are still byte-identical**

```bash
for s in agy-capstone agy-test-audit adversarial-panel-review open-issues; do
  cmp clavity-dotnet/plugin/skills/$s/SKILL.md clavity-classic/plugin/skills/$s/SKILL.md && echo "$s IDENTICAL"
done
bash scripts/check-seed-artifacts-synced.sh
```

Expected: four `IDENTICAL` lines and a clean seed-sync.

- [ ] **Step 3: Run the fast suite**

```bash
just test-scripts-fast
```

Expected: a `Tests Passed:` line with `Failed: 0`. **A log with no `Tests Passed:` line is an ABORTED
run, not a pass.** Do not run both suite halves at once; fast is cap-adjacent.

- [ ] **Step 4: Run the slow suite in the background**

```bash
just test-scripts-slow
```

Block on its own `Tests completed` line, never on a process count. Expected: `Failed: 0`.

- [ ] **Step 5: Mark ROADMAP section 7 shipped**

**The dash in line 494 is an EM-DASH (U+2014), not a hyphen** - measured, and `ROADMAP.md` is not under
the ASCII gate so it is legitimately there. An exact-string replace typed with ` - ` will NOT match. Copy
the line from the file rather than retyping it.

Change line 494 from:

```
### 7. AGY-SCOPE — "pre-existing defects are always in scope" as a shipped discipline (BRAINSTORM FIRST)
```

to:

```
### 7. AGY-SCOPE — "pre-existing defects are always in scope" as a shipped discipline · ✅ **SHIPPED 2026-08-07**
```

Then replace the `⏸️ NO DISPOSITION RECORDED` blockquote at `:498-510` with:

```
> ### ✅ SHIPPED as a CROSS-CUTTING AMENDMENT, not a fourth discipline
>
> Owner ruled the shape 2026-08-07. The disposition half ships as a five-token taxonomy inserted into
> `adversarial-panel-review`, `agy-capstone` and `agy-test-audit`, gated on each skill's completing
> verdicts, plus an intake-bar and routing clarification in `open-issues`. Pinned by the
> `AGY-SCOPE disposition taxonomy` Describe and the per-token mutation rows in
> `scripts/tests/check-agy-discipline-skills.Tests.ps1`.
>
> Design questions 2-5 are answered in
> `docs/superpowers/specs/2026-08-07-agy-scope-disposition-design.md`; question 1 was the owner's shape
> ruling. Deferred deliberately: enrolling `adversarial-panel-review` in the discipline checker (it
> carries 69 non-ASCII characters and no marker constant, so it fails two unrelated gates), and
> backfilling the five known coverage gaps onto the conveyor.
```

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): record AGY-SCOPE section 7 as shipped"
```

- [ ] **Step 7: Run AGY-CAPSTONE over the committed range**

This is a binding rule, not an option. Send the peer the full committed range from Task 1 through Task 6
(exclude the ROADMAP commit - it is documentation of the work, not the work). Verify every finding AND
every proposed fix by measurement before folding, re-run a fresh round after each fold, and repeat until
a full round is GREEN. Then write `.clavity/agy-marks/agy-capstone.head` with the REVIEWED tip - not
ambient HEAD - and append a row to `docs/agy-capstone-ledger.md`.

---

## Out of scope, with the reason

- **Backfilling the five known coverage gaps onto the conveyor.** Separable, and appending them blocks
  the next session until triaged. Follow-on work, owner-scoped.
- **Enrolling `adversarial-panel-review` in the discipline checker.** Measured: 69 non-ASCII characters
  and no `$markerConstant` reference. Fixing those is a different change.
- **The AGY-CAPSTONE rule body in `~/.claude/CLAUDE.md`.** Outside the repo, invisible to git.
- **Factoring a shared adversarial-review core.** Its own epic, deliberately sequenced after this.

---

## Self-review

**Spec coverage.** 4.1 taxonomy -> Tasks 2-4 shared block. 4.2 completeness gate -> the terminus
sentences plus the `ALIGNED` / `GAPS FOUND` / marker rewrites in Tasks 2-3. 4.3 age clause -> shared
block, pinned by the Task 2 test. 4.4 anti-sweep + durable records -> the per-task durable-record
sentences. 4.5 scope bound -> shared block. 4.6 boundaries file -> Tasks 1 and 3. 4.7 intake bar ->
Task 5. 4.8 mechanical enforcement -> Task 6. 4.9 ROADMAP routing -> Task 5 Step 3. Section 6 testing ->
Tasks 2 and 6. Section 10 open questions -> all three answered above by measurement.

**Placeholders.** None. The only bracketed tokens are `[TERMINUS SENTENCE]` and
`[DURABLE RECORD SENTENCE]`, and every task that uses them supplies the literal replacement text.

**Type consistency.** The five token strings are spelled identically in the shared block, the Task 2
test, and the Task 6 checker and mutation rows: `FOLDED: `, `REJECTED: `, `DISCARDED-BELOW-FLOOR: `,
`DEFERRED-TO-ANOMALIES: `, `UNVERIFIED-ACCEPTED: ` - each with a trailing space, which is what makes them
distinct from `[VERDICT: REJECTED - ` and what the mutation test relies on.

**Known residual risk.** Every Step-1 state verification cites line numbers read at `5c54fa3`. Tasks 2-5
each shift the line numbers of the file they edit, which is why later steps within a task say to find
text by content rather than by number.

**Panel round 1 (solo) folded into this revision.** Six findings, all measured: the marker-contract doc
restating the rewritten enumeration (new Task 3 Step 5b); the Task 7 re-sweep being scoped to `plugin/skills/`
and so unable to catch it (Step 1 widened to `docs/` + `scripts/`, case-insensitive); ROADMAP:494 carrying an
em-dash where Task 7 Step 5 quoted a hyphen, which would have failed the exact replace; Task 2 Step 4's
closing sentence contradicting Step 4a by claiming the block replaces the floor bullet; Task 1 Step 2's file
content nesting three-backtick fences inside a three-backtick fence; and Task 3 Step 7's "fix it here"
instruction outrunning Step 9's explicit `git add`. Refuted by measurement and NOT folded: `perl` unavailable
(5.42.2 present), `coverage-debt` leaking past the two SKILL files (confined to them), the roster exclusion
being unsafe (`check-user-facing-docs.ps1` warns, never fails, on absent-from-list).

**Panel round 2 folded.** The live peer returned GREEN on both its seats and produced a 25-row table
asserting zero verification mismatches. That GREEN was FALSE. Running the plan's own Task 7 Step 1 sweep -
rather than reasoning about it - surfaced `agy-test-audit/SKILL.md:82`, a FIFTH restatement of the debt
routing, inside the very file Task 3 edits and about 30 lines above the section Step 3 rewrites. Left
alone, Task 3 would have shipped a skill contradicting itself within one screen. Now Task 3 Step 3b.
The peer also misquoted that sweep (it reported an `-E` form with escaped `\|` alternation, which the plan
does not contain and which would silently match nothing) and then greened its own misquote - so its row
verdicts are not evidence. Seventh instance of this epic's signature defect class, and the second one that
only a RUN, never a reading, could find.

**Panel round 3 - GREEN, and the review is closed.** Bespoke Post-State Coherence Auditor (derived from
exactly how round 2's defect hid: a statement OUTSIDE every edited range, inside an edited file) plus a
Dependency Cynic rotation. Both seats returned no new findings. Independently, the round-2 technique was
generalised and run against EVERY other fact this plan changes - the anti-sweep floor rule, the
`UNVERIFIED-ACCEPTED` recording sites, the `ALIGNED` definition, and the `open-issues` intake bar - each
swept repo-wide with the superpowers and ledger paths excluded. All four came back with no un-updated
restatement. The new Step 3b gate was control-checked: its grep returns exactly 1 in both mirrors, a
deliberately-wrong pattern returns 0, and all four skill pairs remain byte-identical.

Peer reliability, recorded: round 3's reply truncated before its second seat, which was re-asked alone and
answered cleanly - the verdict-first instruction preserved the verdict through the truncation. Its claimed
end-of-file line numbers were actual+1 for all four files, a systematic offset rather than invention, so
its claim to have read to EOF is credible. But two of its post-edit quotes were fabricated: it quoted an
`open-issues:14-15` rewrite this plan does not specify (the real fix is a semicolon restructure), and it
substituted `agy-capstone`'s `skipped.log` sentence for `adversarial-panel-review`'s `## Stand-downs` one.
Both were marked CONSISTENT. Treat its coherence table as a prompt to measure, never as evidence.

FINAL PANEL DISPOSITION: **GREEN** at plan tip `0e89e51` + this record. Three rounds, seven findings folded,
zero open. Of the seven, six came from the solo floor and one from running a command; none came from a peer
seat - though the peer's round-1 anchor answers did independently confirm the ROADMAP em-dash and surfaced
two non-skill surfaces worth checking, one of which was already folded and one of which measured clean.
