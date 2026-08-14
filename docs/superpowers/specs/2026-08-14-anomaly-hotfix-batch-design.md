# Anomaly hot-fix batch - design

**Status:** owner-approved 2026-08-14; **AMENDED the same day and re-panelled.** **This is a SPEC, not a
plan.** It carries intent, contracts and measured current state. The implementation plan re-derives every
line number (see "Citation drift" below).

**What the amendment changed, and why the AGY-AFTER GREEN at round 12 no longer covered it.** The plan's
Step 0 - the one measurement this spec deliberately deferred - ran, and its result invalidated section
4.2. That section specified item 14c entirely in terms of HOOKS; the measured set is one hook and four
SKILLS, which cannot be wired the way a hook can. The owner then decided the scope (a new shipped
executable rather than the narrower option), which changes what 14c IS. Sections 1, 2, 4.2, 5 and 6 were
amended together. **A GREEN is a statement about the artifact that was reviewed, not about this one** -
hence the re-panel.

**Deliberately NOT changed by the amendment:** section 4.1's helper contract. `agy-mark.sh` is a new
CALLER of that helper, not a change to it. Section 4.2's contract table states the one place the two
differ - fail-closed versus fail-open - and says why.

**Branch:** `feature/injected-context-governance` (checked out; well ahead of `origin/main` and **nothing
pushed**). **No ahead-count is recorded here on purpose** - an earlier draft pinned one, and its own
commit invalidated it. Read it live with `git rev-list --count origin/main..HEAD`; what matters to this
spec is only that the branch is unpushed, which is why CI cannot gate any of this.

---

## 1. What this is, and why now

Seven triaged defects sit OPEN in `clavity-dotnet/ROADMAP.md`. They are independent of the policy-gate
epic, blocked on nothing, and several land on the branch already checked out. This spec clears them as
ONE deliberate batch.

**The sequencing was decided by a measurement already in the ROADMAP, not by preference.** Section 8
(`ROADMAP.md:569-573`) records the owner ruling:

> **87.2% of spend is context re-payment**, not generation. ... **a capstone at turn 500 pays ~5x the
> identical capstone at turn 50.** So section 8's framing had it backwards - *batching to the end is the
> expensive direction*; running the review early, at low context, is the cheap one.

That decides review placement: this batch is a self-contained reviewable unit, capstoned immediately,
rather than folded into the epic's open range. Commit granularity follows from the same decision - the
batch forms one review boundary.

**What "clean before further implementation" does and does not mean here.** These items do not
destabilise the policy gate and are not a precondition for it. The honest rationale is (a) cost, per the
ruling above, and (b) one of them is a live data-leak path. Overstating it as risk to the gate would be
wrong, and the plan should not repeat that framing.

### In scope (7)

| item | one-line statement |
|---|---|
| 14d | the sole `.clavity/.gitignore` shield assertion is content-blind |
| 14c | five shipped artifacts write into `.clavity/` and none asserts the shield (one hook, four skills) |
| 14e | the only local gate on the three byte-pinned files checks provenance, not parity |
| 14a | `PrunedSegments` omits `.clavity` |
| 14b | `clavity-install.Tests.ps1` is an orphan suite |
| 13a | the gate promises unused-exemption reporting no code path can produce |
| 13c | a missing input is indistinguishable from a legitimately empty one |

### Explicitly OUT of scope

- **13b** (no discipline requires a peer's ANSWER to survive truncation) - a design change, not a hot fix.
  Including it would turn a debt sweep into an epic.
- **Section 15** (workflow-position resilience) - parked by owner decision 2026-08-13.
- **The `core.md` ownership contradiction** - found while specifying 14e, triaged 2026-08-14 and promoted
  to ROADMAP section 14f. It needs an owner ruling, not a fix. See section 7. **Its one decision-free
  consequence IS in scope** - the `agy-curate/SKILL.md` companion change in section 4.3.

---

## 2. Measured current state

Every row below was measured on 2026-08-14 at `6d14940`, with a passing control where one was available.
**The plan must re-measure rather than trust this table** - it is evidence that the defects were real,
not a substitute for Step 0.

| item | measurement | result |
|---|---|---|
| 14a | `PrunedSegments` contents, `scripts/check-injected-context.ps1:91-92` | lists `.worktrees`; **`.clavity` absent** |
| 14b | `clavity-install.Tests.ps1` occurrences in root `justfile` | **0**; control (a registered suite) = 1 |
| 14b | `Invoke-Pester clavity-dotnet/install/clavity-install.Tests.ps1` | **Passed 12, Failed 0**, 4.77s |
| 14c | artifacts writing into `<repo>/.clavity/`, traced to the resolved target | **1 hook + 4 skills**, enumerated by name in section 4.2 (measured 2026-08-14; ROADMAP's "7 hooks" is wrong in kind and in count) |
| 14d | four shield states in a throwaway repo | see the matrix in section 4.1 |
| 14e | sizes/hashes of the three "byte-pinned" files | **3515 / 11544 / 7801 bytes, three distinct hashes** |
| 13a | occurrences of `unused` in the gate script | **exactly 1** - inside the false message itself |
| 13a | does anything actually catch a stale exemption | **yes** - `scripts/tests/check-injected-context.Tests.ps1:666` |
| 13c | `Get-RawBytes` on a missing path, `scripts/check-growth-budget.ps1:26` | returns **0**, silently |

### Citation drift - a standing hazard for the plan

`ROADMAP.md` section 13a cites the offending message at `scripts/check-injected-context.ps1:701`. It is
**at :932**. The quote is correct; the line number has drifted. Sections 14a, 14d and 14e were re-checked
and their citations still hold.

**Therefore: the plan re-derives every line number it cites, and cites nothing it has not opened.** A
plan is a set of claims about real code.

---

## 3. Global rules that bind every item

These are not per-item; they apply to the whole batch and to the plan built from it.

1. **A control before the fix.** Every item gets a test that FAILS against current `HEAD` and passes
   after. Writing the failing control first is the habit that correlated with fixes that did not need a
   follow-up.
2. **Mutation, not presence.** For every guard added, answer: *which test goes RED if I delete this
   guard, or NONE?* A guard whose deletion leaves the suite green has not been tested. Asserting that a
   detector EXISTS is not asserting that the gate EMITS it - this repository has already shipped 16
   detector rows with zero emission assertions, where a `-and $false` mutant kept the suite green.
3. **Byte-identical pair discipline.** Any change to a shipped `plugin/` artifact must mirror to the
   other product and pass `plugin-hooks-payload.Tests.ps1` and `check-seed-artifacts-synced.sh`.
4. **Sweep the fact, not the line.** When an item's fix changes a FACT, grep the whole repository for
   that fact in several wordings before calling it done. The dominant fold defect here is an incomplete
   fold, and a paraphrase evades a phrase-shaped grep.
5. **A ZERO EXIT IS NOT EVIDENCE THAT WORK HAPPENED.** Two concrete instances, one live in this batch and
   one guarding a rejected option:
   - **Live (14e):** if the generator crashes, the working tree is untouched, so `git diff --quiet`
     returns **0** and the hook passes. The zero means "nothing differed", which is indistinguishable
     from "nothing ran".
   - **Guarding the rejected option:** `dotnet test --filter` exits **0** when its filter matches nothing,
     so a gate shelling out to a filtered test run must assert the test COUNT. **No item in this batch
     does that** - 14e chose generation over shelling out to the suites - so this half is a warning
     against reintroducing it, not a requirement on any current item. It is kept because that option was
     seriously considered and its trap is easy to walk back into.

   The shared rule is that a gate must establish its precondition ran, then read its result. **Both cases
   are a false-positive ZERO**; an earlier wording of this rule invited reading the 14e case as being
   about the generator's non-zero exit, which is the FIX rather than the hazard.
6. **EVERY file this batch creates or edits inside a `$DomainRoots` tree inherits the injected-context
   invariants, and this batch touches governed trees in SEVEN distinct places.** Measured at
   `scripts/check-injected-context.ps1:40-53`, the governed roots include `clavity-dotnet/plugin`,
   `clavity-classic/plugin` and `agy-autotrain`. Every entry below is governed: it must be pure ASCII,
   and everything under `clavity-*/plugin/` must additionally satisfy the twin-plugin byte-identical rule
   the same canonicaliser enforces.

   | governed thing this batch creates or edits | item | mirrored? |
   |---|---|---|
   | the shield helper (`agy-shield-lib.sh`) | 14d | yes, both plugins |
   | `agy-mark.sh` | 14c | yes, both plugins |
   | `agy-discipline-reaching.sh` (the hook wiring) | 14c | yes, both plugins |
   | `agy-first/SKILL.md` | 14c | yes, both plugins |
   | `agy-capstone/SKILL.md` | 14c | yes, both plugins |
   | `agy-test-audit/SKILL.md` | 14c | yes, both plugins |
   | `agy-curate/SKILL.md` | 14e | no - single copy |

   `core.md` is governed too, which section 4.3 already says.

   **THE TOTAL IS DELIBERATELY NOT STATED, because every draft that stated one got it wrong.** The first
   said "three of them do" and named only `core.md`'s neighbours. The 14c amendment then added an
   executable, a hook edit and three skill edits without touching the count. Round 2 changed it to "six"
   and round 3 changed the skill count underneath it, leaving "six" describing a list that no longer had
   six anything - and a bullet that said "the four 14c SKILL.md edits" while listing three skills plus a
   bash script. **A running total in prose is a claim that has to be re-derived on every edit and silently
   rots when it is not. The table is the enumeration; count it if you need a number.**

   **The author of a rule is not exempt from it, and neither is the amender** - this repository has
   already had a commit rejected by the very ASCII gate that commit was shipping. Run
   `just check-injected-context` (or the script directly) before committing ANY row above, and treat a
   rejection as expected feedback rather than a surprise.

---

## 4. Per-item specification

### 4.1 Item 14d - the shield assertion must test the effect, not the text

**Current behaviour.** The sole assertion is `[ -f "$R/.clavity/.gitignore" ]` (shipped byte-identically
at `open-issues/SKILL.md:79` in both products). It restores a DELETED shield and nothing else. Its own
adjacent comment claims it covers "the file was created by hand", which is precisely what it misses.

**Measured, in a throwaway repo, all four states:**

| shield state | `[ -f ]` (shipped) | `grep -qx '*'` (recorded fix) | `git check-ignore` (effect) |
|---|---|---|---|
| `*` (correct) | TRUE - leaves alone, correct | 0 - passes, correct | 0 - ignored, correct |
| `*` then `!local-anomalies.md` | TRUE - **wrong** | 0 - **passes, wrong** | 1 - **not ignored, correct** |
| emptied (0 bytes) | TRUE - **wrong (the 14d defect)** | 1 - restores, correct | 1 - not ignored, correct |
| correct `*`, file already TRACKED | TRUE - **wrong** | 0 - **passes, wrong** | 1 - not ignored, **see below** |

The negation state is a REACHABLE leak in any repository that does not already ignore `.clavity/` at its
root - which is exactly the repositories this skill ships to. (In THIS repository the root `.gitignore`
covers `.clavity/` and git cannot re-include a file whose parent directory is excluded, so the leak is
masked locally. A control that does not account for that reports a false pass.)

**Required behaviour - a shared helper implementing this decision tree:**

**Two INDEPENDENT concerns, and conflating them is what an earlier draft got wrong.** Stage A protects the
DIRECTORY and runs unconditionally. Stage B verifies the EFFECT for one named path. The state of any single
file must never suppress Stage A.

**Stage A - shield integrity, unconditional:**

A0. **Validate the inputs. On failure: WARN LOUDLY on stderr, then return 0 without writing** - the
    warning is not optional and is never debounced, because a bad argument means the CALLER is broken and
    is about to write private data anyway. (Stated here as well as in the contract table deliberately: an
    implementer translating this tree into code reads THIS line, and an earlier draft said only "return 0
    without writing", which yields a silent no-op that hides a broken caller.) The root must be an
    existing directory, and the path must resolve UNDER `<root>/.clavity/`. Both matter: the helper repairs
    `<root>/.clavity/.gitignore` and nothing else, so a path outside that directory cannot be fixed by
    repairing that shield. Restoring it and reporting success for, say, `docs/secret.md` would be a
    false GREEN for a file left fully exposed.
A1. **`mkdir -p <root>/.clavity`.** Every restoring step appends, and an append into a missing directory
    fails `No such file or directory` on a fresh clone. If the `mkdir` fails, return 0 - never hard-block.
A2. **Ensure the shield text is present**, in THREE cases, not two. The two-case version of this step
    silently destroyed the very intent the spec's second residual promises to preserve - see the
    measurement below.

    - **a bare `*` line is present** (`grep -qx '*' "<shield>" 2>/dev/null` exits 0): done, append
      nothing. **Both the redirection and treating ANY non-zero as absent are required, and measured:**
      on a missing file `grep` exits **2** (not 1) **and writes `No such file or directory` to stderr**.
      Without `2>/dev/null` the helper leaks grep's error on every fresh clone, breaking the contract's
      "silent unless it acted or found a fault"; without treating 2 like 1, an implementer who keys on
      `exit 1` alone fails to restore a shield that does not exist - the original 14d defect,
      reintroduced.
    - **no bare `*`, but the file contains at least one `!` line**: **PREPEND `*` as the FIRST line,
      preserving everything already in the file.** Do not append, and do not report - Stage B3 is the
      reporting branch and will still fire for the negated path.

      **A prepend is not an append, and POSIX gives you no atomic one - so the mechanism is part of the
      contract.** Write the new content (the `*` line followed by the existing bytes) to a temp path
      that is **unique per invocation AND created inside `<root>/.clavity/` itself**, then `mv` it over
      the shield: a rename within one filesystem is atomic, so a concurrent reader sees either the old
      file or the new one and never a truncated one.

      **The temp file's LOCATION is load-bearing, not a detail.** `mv` is atomic only WITHIN a
      filesystem; across a boundary it degrades to copy-then-delete and the atomicity guarantee is
      silently gone. `mktemp` with no argument defaults to `$TMPDIR`, which on a normal machine is a
      different mount from the repository - so the obvious implementation defeats the very property this
      paragraph exists to buy, and does so invisibly, because copy-then-delete still produces the right
      bytes whenever nothing races. Create the temp beside the shield.
      **Do not read-modify-write the shield in place**, and do not use a fixed temp name - two sessions
      can be open on the same repository, and a fixed name races exactly when the guard matters. **On any
      failure path, remove the temp file**; on success the `mv` consumes it. Without this stated, an
      implementer picks between a leak (unique names never cleaned up) and a race (a fixed name), which
      is the trap that made this worth writing down.
    - **no bare `*` and no `!` line** (missing, empty, or unrelated content): append `*`.

    **Why the middle case exists - MEASURED 2026-08-14 in a throwaway repo, with a discriminating
    control.** `.gitignore` is last-match-wins, so appending `*` to the END of a file that begins with a
    negation INVERTS that negation:

    | shield content | `check-ignore -q` on the NAMED file | on ANOTHER file in the directory |
    |---|---|---|
    | `!local-anomalies.md` alone | **1** - not ignored | **1** - not ignored |
    | after a blind APPEND: `!local-anomalies.md` then `*` | **0** - now IGNORED | 0 |
    | **PREPEND: `*` then `!local-anomalies.md`** | **1** - not ignored | **0** - protected |

    So a blind append **silently overrides a line a human deliberately wrote**, and it does so invisibly:
    `check-ignore` then returns 0, B2 says "done", and **the negation report at B3 is never reached.**
    That is precisely the destructive-footgun class the second known residual below refuses to commit,
    arriving through the restore path instead of through a rewrite. It also means the negation residual
    was only ever reachable in ONE of the two orderings, which is why twelve rounds did not surface it.

    **PREPENDING is what satisfies both obligations at once, and the first attempt at this fix did not.**
    Re-panel round 1 corrected the append to "do not write anything", which preserved the human's intent
    and **left the entire directory exposed to protect one file** - measured, `git add -A` then staged
    `.clavity/other-marker.md` and `.clavity/local-anomalies.md` alike. That is the same inversion the
    tracked-file callout below spends a whole paragraph forbidding: **a per-file condition suppressing a
    per-directory guarantee**, re-created by the fix for a different per-file condition. It also broke
    Stage B's premise: with no `*` present, an untracked file the negation never named ALSO returns 1, so
    B3 fires and blames a negation line for a file it has nothing to do with - a false root cause.

    **Prepending fixes all of it, because `.gitignore` is last-match-wins:** the human's `!` line still
    wins for the file it names (measured: exit 1, and `git add -A` stages exactly that one file), while
    `*` covers everything else (measured: exit 0). Stage A's guarantee "a bare `*` line is always present
    afterwards" is restored, so B1's and B3's wording below remains true as written.

    **This step runs regardless of the state of any individual FILE in the directory** - that is what
    makes Stage A a per-directory guarantee and why Stage B may never skip it. Conditioning on the
    SHIELD'S OWN CONTENT is a different thing and is not a weakening: the shield is the artifact this
    step maintains, not one of the files it protects.

**Stage B - effect verification for the named path** (adds detection Stage A cannot do alone):

B1. **Not inside a git work tree** (`git rev-parse --is-inside-work-tree` non-zero): stop here. The effect
    check cannot run - `git check-ignore` returns 128 outside a repo, indistinguishable from a genuine
    error. Stage A has already guaranteed the shield text. Isolate this case exactly as
    `scripts/check-core-integrity.ps1:39-46` does for the same ambiguity.
B2. **`check-ignore` exit 0**: the path is ignored. Done.
B3. **`check-ignore` exit 1**: AMBIGUOUS - disambiguate with `git ls-files --error-unmatch <path>`:
    - exit 0 => the path is **TRACKED**. Stage A has already secured the directory; this file cannot be
      fixed by any shield edit, because git ignores `.gitignore` for tracked paths. **Report the
      `git rm --cached` remedy (debounced). Do not treat this as a shield fault.**
    - non-zero => untracked and still not ignored **after Stage A restored the shield text**. The only
      way to reach this is a negation line (`!...`) inside the shield. **Report loudly; do NOT silently
      rewrite.** See the residual below.
B4. **`check-ignore` exit 128 inside a work tree**: a real git error. Stage A has already done what it
    can, which is the safe direction for a data-leak guard. Say so and stop.

    **How this branch is REACHED is a real problem for its test, and "mock git" is not an acceptable
    answer.** Measured 2026-08-14: `git check-ignore -q` returns **128** with a genuine `fatal:` for a
    path outside the repository root, for an absolute path outside it, and for no pathspec at all -
    control, a normal ignored path, returns 0. So 128 is trivially producible with a real git binary.
    **But A0 rejects every one of those inputs before Stage B runs**, so none of them can reach B4
    through the helper's front door. The honest position: **through the public entry point, B4 is
    reachable only by genuine repository corruption**, which no hermetic test should manufacture. The
    plan must therefore either (a) exercise B4 through an internal entry point that skips A0, naming
    that as a test-only seam, or (b) record B4 as a defensive branch with no honest oracle and delete
    its test row rather than write one that passes by mocking the git binary. **Option (b) is
    acceptable; a mocked `git` is not** - it would satisfy "the row turns RED" while proving nothing
    about behaviour against a real filesystem, which is the false-GREEN class this spec exists to
    remove. **What is NOT acceptable is leaving the row as written**, because it currently reads as
    though a straightforward test exists.

> **Why Stage A is unconditional - measured, with a control.** With `local-anomalies.md` TRACKED,
> `check-ignore` on it returns **1 whether the shield is intact or emptied** - the two are
> indistinguishable from that probe. An earlier draft therefore said "do NOT rewrite the shield" in the
> tracked case, which meant **one tracked file disabled protection for the whole directory**. Measured in
> a throwaway repo: tracked file exit 1 in both states, while a second, untracked file in the same
> directory went from **0 (protected)** to **1 (leaking)**, and `git add -A` then staged
> `.clavity/other-marker.md`. **A per-file condition was suppressing a per-directory guarantee.**

**Why B3 splits on tracked-ness.** Measured: with a correct `*` shield and the file force-tracked,
`check-ignore` returns **1** and `git add -A` **stages the file anyway**. Without the split, a naive
"non-zero implies the shield is broken" helper would keep rewriting a correct shield and never surface
the only remedy that works.

> **Refuted, twice, and recorded so it is not raised a third time:** a reviewer twice claimed
> `check-ignore` returns **0** for a tracked file matching the pattern - which would route the tracked
> case to B2 ("done") and make it a silent false-GREEN. **It returns 1.** Measured with a control in a
> throwaway repo: tracked file matching `*` -> **exit 1**; untracked control in the same directory ->
> **exit 0**. The tracked case is reached by B3, which handles it. The concern is real and folded; the
> mechanism claimed for it is not.

**Helper contract.** The plan chooses the exact path; the CONTRACT is fixed here:

| aspect | contract |
|---|---|
| form | a POSIX `sh` **function**, defined in a sourceable file - the hooks are `.sh` and run under the agent's shell |
| input | **three arguments: the repository root, the path to protect** (relative to that root), **and a debounce key** (the caller's session id, or empty to disable debouncing). It must NOT re-derive the root - callers already have it, and two derivations can disagree. The path is an argument, not a baked-in constant, because branches 2-3 both test a specific file. **The debounce key must be passed IN because the helper cannot derive it**: sibling hooks parse `session_id` out of the hook's stdin payload (`agy-anomaly-capture-reminder.sh:61`), and a sourced function has no payload of its own |
| **the DEBOUNCE KEY is validated too - it lands in a filename** | The key is interpolated into the marker path (`.clavity-shield-<class>-<key>`), so an unvalidated key is a path-traversal primitive: `AGY_SESSION_ID=../../something` escapes `$TMPDIR` and writes wherever it resolves. **The helper validates root and path but an earlier draft did not validate the key at all.** **An EMPTY key is LEGAL and must not be validated** - it is the sanctioned way to disable debouncing. Validate only a NON-empty key, rejecting any that is not `[A-Za-z0-9._-]+`, and on rejection treat it as empty: debouncing off, warning every time, rather than refusing to run - a malformed session id must never disable a data-leak guard. **An earlier draft ran the regex over every key, and `[A-Za-z0-9._-]+` requires at least one character, so the legal empty key failed it - and since a validation failure is a loud, NEVER-debounced fault, the sanctioned input would have printed an error on every single call, breaking the silent-path contract outright** |
| input validation | **the root must be an existing directory and the path must resolve under `<root>/.clavity/`, or the helper WARNS LOUDLY on stderr and returns 0 without writing.** An unvalidated root is a footgun: the contract forbids re-deriving it, so an empty or wrong value is silently trusted, and `mkdir -p "$1/.clavity"` with an empty `$1` would create a directory at the filesystem root |
| **bad-argument output is NOT optional** | A bad argument means the CALLER is broken, and the caller is about to write private data. Silence here is a fail-open: a hook that passes the wrong path gets a clean return, proceeds to write its anomaly, and the file is unshielded with nothing reported. **A validation failure is a FAULT for output purposes** - it is loud, it is NOT debounced (a broken caller must not be silenced by a marker), and it names the argument it rejected |
| effect | **inside the repository:** may create `<root>/.clavity/`; may create, APPEND TO, or PREPEND TO `<root>/.clavity/.gitignore`; and may create **one transient temp file inside `<root>/.clavity/`**, consumed by the prepend's `mv` or removed on failure. That temp file is a deliberate exception to "nothing else" - the prepend's atomicity requires it to sit on the same filesystem as the shield - and it is named here because an earlier draft's "nothing else" would have forbidden the only correct implementation. **Prepending is a third write shape, not a kind of appending** - an earlier draft of this row said "create or append", which contradicted A2's middle case and would have sent an implementer back to the append that inverts a negation. **Outside it:** may write ONE debounce marker under `$TMPDIR` or `$HOME/.clavity-tmp`, exactly as the sibling hooks do. An earlier draft said "touches nothing else" while also requiring a seen-marker, which is unsatisfiable - the marker cannot live in the repository, because a marker inside `.clavity/` would be a file the shield is supposed to be protecting |
| output | a single human-readable line on stderr **only when it acted or found a fault**; silent on the healthy path, because it runs on every capture. **Three fault classes, and the debounce differs by class:** (a) **PERSISTENT** (tracked file, negation line) - debounced per key, because it is a true state a human fixes once; (b) **VALIDATION** (bad root, path outside `.clavity/`) - **never** debounced, because the CALLER is broken and must be visible on every call; (c) **ENVIRONMENT** (B4: `check-ignore` fails 128 inside a work tree; **and A1's `mkdir` failure**) - debounced per key like (a), because it is a condition of the machine rather than of the caller. **Every branch that REPORTS falls into exactly one class; the branches that report nothing are named explicitly rather than left to inference: A1-success, A2 (all three cases), B1 and B2 are SILENT.** An earlier wording said "every branch of the tree falls into exactly one class", which was false the moment any branch was silent - it left A1's failure path with no class at all, and made A2's new prepend case look like an omission rather than a decision |
| A1 `mkdir` failure | returns 0 without writing, reports as class ENVIRONMENT, and does NOT hard-block. Listed as its own row because the decision tree and the test table both carried this branch while this table did not |
| B1, outside a git work tree | Stage A has already run to completion; Stage B is skipped entirely and NOTHING is reported. Listed for the same reason - the branch existed in the tree and the test table and was absent here |
| return | **`return 0`, ALWAYS - never `exit`.** See the sourcing hazard below |
| tracked-file case (B3, tracked) | emits the `git rm --cached` remedy on stderr, debounced; returns 0. Stage A has already secured the shield, so this is a notice, not a repair |
| negation-line case (B3, untracked) | the path is still unignored after Stage A restored the shield text, so a `!` line is overriding it. Emits a loud notice naming the file and the offending line, debounced; **returns 0 and does NOT rewrite the shield**. Present in the contract because an earlier draft described it only in prose - an implementer reads this table for return states |
| **`-q` decides, `-v` only explains - never one invocation for both** | **Measured: `git check-ignore -v` exits 0 on a file that is NOT ignored** (it prints the matching `!` line and treats having output as success), while `git check-ignore -q` exits **1** on that same file. So the DECISION must come from a `-q` call and the message text from a separate `-v` call. Reusing a single `-v` invocation for both inverts B2 and B3: a leaking file would be read as ignored, and the guard would pass on exactly the state it exists to catch |

**EVERY probe redirects stderr, not just the `grep` - and this was an incomplete fold until round 8.**
Round 7 added `2>/dev/null` to A2's `grep` and stopped there. The same fault class sits in the git probes,
measured 2026-08-14:

| probe | on which branch | what it writes to stderr unredirected |
|---|---|---|
| `git rev-parse --is-inside-work-tree` | **B1 - outside a repo** | `fatal: not a git repository (or any of the parent directories): .git` |
| `git ls-files --error-unmatch <path>` | **B3 - the ordinary UNTRACKED case** | `error: pathspec '<path>' did not match any file(s) known to git` **plus** `Did you forget to 'git add'?` |
| `grep -qx '*' <shield>` | A2 on a fresh clone | `No such file or directory` (folded in round 7) |

**Both git cases fire on NORMAL paths, not error paths.** B1 is the expected state for a skill that ships
into directories which are not repositories at all, and B3-untracked is the routine "shield was broken,
restore it" case. Worse, `ls-files` volunteers *"Did you forget to `git add`?"* - advice exactly backwards
here, since the entire point is that the file must NOT be added. **Every probe in this helper redirects
stderr and is judged by its exit code alone.** The helper's own messages are the only thing it may print.

> **NOT a defect - checked, and recorded so a later round does not re-derive it:** I suspected the
> unescaped `grep -qx '*'` pattern was a portability hazard, since a BRE treats a leading `*` as literal.
> Measured against a line containing exactly `*`, with a passing negative control: `grep -qx '*'`,
> `grep -qx '\*'` and `grep -qxF '*'` **all return 0**, and `-F` correctly returns 1 on a non-matching
> line. Any of the three is fine; the spec need not mandate one.

**`return`, NEVER `exit` - measured, and it would have shipped.** The helper is SOURCED into the calling
hook, so `exit` terminates the CALLER, not the helper. Measured in a throwaway script: a sourced snippet
containing `exit 0` ended the parent before its next line ran - the parent's remaining guards were
silently skipped and the parent still reported success. **A helper written to "always exit 0" would
therefore disable every check that follows it in every hook that sources it** - the exact fail-open class
this batch exists to remove. The intent behind "always 0" stands: these hooks fail open by design and a
shield fault must never hard-block an agent (`exit 2` on PreToolUse is BLOCKING). The mechanism is
`return`.

**It must create the directory, and that is not a contract violation.** An earlier draft said the helper
"touches NOTHING else" while requiring it to append into `<root>/.clavity/` - which is unsatisfiable on a
fresh clone, where the directory does not exist and a bare `>>` fails `No such file or directory`. The
shipped snippet already does `mkdir -p "$R/.clavity"` (`open-issues/SKILL.md:69`) before its append, for
exactly this reason. The helper does the same, and the contract above now says so.

**Output debounce.** In the tracked-file case the fault persists until a human runs `git rm --cached`, so
an undebounced helper prints the same remedy on EVERY capture forever, and a permanent unsuppressible nag
is how an operator learns to ignore the channel. It emits that line at most once per debounce key, using
the same seen-marker approach the sibling hooks already use (`agy-anomaly-capture-reminder.sh` and
`assertion-strength-reminder.sh` both do this).

**The key is an ARGUMENT, and an earlier draft of this section made that impossible.** It said "once per
session" while the contract gave the helper only the root and the path. The session id lives in the hook's
stdin payload, which a sourced function does not see, so the requirement was unimplementable as written.
The caller has already parsed it; it passes it in. **An empty key disables debouncing rather than failing** -
a caller with no session context still gets the warning, just every time, which is the safe direction for
a data-leak notice.

**Temp files must not collide - AND they must not accumulate. Uniqueness without a lifetime is a leak.**
Two sessions can be open on the same repository at once - the open-issues skill already designs for that -
so any scratch path the helper or the 14e generator uses must be unique per invocation, never a fixed
name. **Unique-per-invocation plus no cleanup is unbounded growth**, and both obligations bind here:

- **The 14e hook's generated temp file** is created on every commit that stages one of the three pinned
  paths. It must be removed on EVERY exit path, including the failure paths, not only the happy one.
- **The 4.1 helper's debounce markers** are one file per session per fault class under `$TMPDIR` or
  `$HOME/.clavity-tmp`, and nothing in this spec ever deletes them. **Both sibling hooks that use this
  exact mechanism already prune** - `agy-anomaly-capture-reminder.sh:107` and
  `assertion-strength-reminder.sh:125` each run `find "$_cand" -maxdepth 1 -name '<prefix>-*' -mtime +30
  -delete`, and each does so at most once per session rather than on the hot path. The helper adopts the
  same prune, with the same once-per-session gating and the same `-mtime +30` window. **Inventing a
  different retention here would be drift, not a decision.**
- **The marker PREFIX must be its own, and the spec has to name it or the prune is dangerous.** The
  siblings prune `-name '.clavity-anomaly-*'` and `-name '.clavity-assert-*'` respectively; the shield
  helper uses **`.clavity-shield-*`** and prunes only that. A helper that reused a sibling's prefix would
  delete the sibling's markers on its own schedule, and one that pruned a broader glob would delete them
  all. **A prune instruction with an undefined prefix is worse than no prune**, which is why it is fixed
  here rather than left to the implementer.
- **The A2 prepend's temp file** is unique per invocation, consumed by the `mv` on success, and removed
  on every failure path. **But a cleanup trap does not survive a SIGKILL, and that file lives INSIDE
  `<root>/.clavity/` where neither prune reaches it** - the marker prune runs over `$TMPDIR` and
  `$HOME/.clavity-tmp`, not the repository. So it needs a recognisable name and its own sweep: name it
  `.gitignore.tmp.<unique>` beside the shield, and have A1 remove any `.gitignore.tmp.*` older than the
  same `-mtime +30` window - **AFTER its `mkdir`, never before it, and with stderr redirected.** The
  ordering is not cosmetic: on a fresh clone `<root>/.clavity/` does not exist, so a sweep that runs
  first fails `No such file or directory`, and **A1 is a SILENT branch whose test asserts stderr is
  empty** - so the sweep would redden the A1-success row on every fresh clone. An earlier wording said
  "before it does anything else", which is exactly backwards. **Without that, an interrupted prepend leaks
  permanently into the exact directory this helper exists to protect** - and a `git status` in a repo
  whose shield is briefly broken would show them.

**Tests. The four-state matrix is the STARTING point, not the whole set - the decision tree grew past it.**
An earlier draft said "all four states above", which was written when the tree had four branches. It now
has seven, and three of them have no row in that matrix. The required set:

| case | asserts |
|---|---|
| shield `*`, untracked | helper leaves it untouched (control - it must not churn a healthy shield) |
| shield emptied, untracked | shield restored |
| shield `*` + `!<name>`, untracked | reported loudly, shield NOT rewritten (the negation residual, ordering 1) |
| **shield is `!<name>` ALONE, no bare `*`, untracked** | `*` is PREPENDED as the first line and the human's `!` line survives unchanged BELOW it. **Assert all three properties, because each one failed in a different draft of this branch:** (a) `check-ignore -q` on the NAMED file still exits **1** - the human's intent survives, which the blind-append version destroyed; (b) `check-ignore -q` on ANOTHER file in the same directory exits **0** - the directory is protected, which the write-nothing version broke; (c) the `!` line is still present and unmodified. **Asserting only "a fault was reported" passes against BOTH broken versions** |
| **mutation: change the prepend back to an append** | property (a) must turn RED |
| **mutation: change the prepend to writing nothing** | property (b) must turn RED. Two mutations, because one fix here already re-broke what the other fixed |
| shield `*`, path TRACKED | `git rm --cached` remedy emitted, shield still intact afterwards |
| **shield emptied, path TRACKED** | **shield restored anyway** - the Stage A regression test. This is the case that was broken until round 2; without it the fix is unpinned |
| **root argument empty or not a directory** | returns 0, writes NOTHING, creates no directory, **and WARNS on stderr** |
| **path argument outside `<root>/.clavity/`** | returns 0, writes NOTHING, **and WARNS on stderr** - no false "repaired" report, and no silence either |
| **outside a git work tree** | text fallback runs; no `check-ignore` invoked |
| ~~**`check-ignore` fails with 128 INSIDE a work tree (B4)**~~ | **DELETED, deliberately - option (b) of the choice the B4 paragraph above sets out.** Through the public entry point B4 is reachable only by genuine repository corruption, because A0 rejects every cheap way of producing a 128. The two ways to keep a row were a test-only seam that bypasses A0 - new surface in a shipped guard, to reach a branch that only reports - or a mocked `git`, which the spec forbids. **B4 is therefore a defensive branch with NO oracle, and this table says so instead of implying one exists.** An earlier version left the row in place while the prose above declared leaving it "NOT acceptable"; the table and the prose now agree |
| **fresh clone: no `.clavity/` directory at all (A1)** | the directory is created and the shield written. Every other row assumes the directory already exists, so **A1 was untestable by the rest of the matrix** - and A1 is the branch that exists because a bare `>>` fails `No such file or directory` |
| **`mkdir` fails (A1 failure path)** | returns 0, writes nothing, does not hard-block |
| **persistent fault repeated with the SAME debounce key** | emitted once, not twice |
| **validation failure repeated with the same key** | emitted BOTH times - validation is never debounced, and only a repeat test can tell the two policies apart |
| idempotence | three consecutive runs leave exactly one `*` line |
| **every SILENT branch asserts stderr is EMPTY** | A1-success, A2 (all three cases), B1 and B2 are silent by contract, and **an effect-only assertion cannot detect a branch that started talking**. A helper that emits on the healthy path runs on every capture and trains the operator to ignore the channel - the same failure the debounce exists to prevent. Without an empty-stderr assertion the "silent unless it acted or found a fault" row has no oracle at all |
| **A1 `mkdir` failure reports class ENVIRONMENT** | assert the message appears once, and NOT twice for the same debounce key. The existing row asserts only "returns 0, writes nothing" - which passes whether the branch is debounced, undebounced, or silent, so the fault CLASS is unpinned |
| **the A2 prepend leaves no temp file behind** | after a prepend, and after a prepend forced to fail mid-write, no `.clavity`-adjacent temp path survives. This is the row that catches the leak-versus-race trap named above |

**Plus one mutation control per branch** - deleting any branch must turn at least one row RED. If deleting
a branch leaves the suite green, that branch is untested regardless of how many rows exist.

**The plan verifies this MECHANICALLY, as a cross-product, not by reading.** Every branch of the tree
(A0, A1 and its failure path, A2, B1, B2, B3-tracked, B3-negation, B4) must appear in ALL FOUR of: the
decision tree, the helper contract, this test table, and the output fault-class taxonomy. **Two rounds of
this review found the same defect class - a branch present in one table and absent from another** (B4 had
a branch and no test; A1 had a branch and no test because every other row presupposed the directory it
creates). A reading pass keeps missing it; a cross-product does not. Build the grid and show it filled.

**Known residual, stated rather than discovered later.** The helper protects the shield; it does not
un-track an already-tracked file. B3 reports rather than repairs, deliberately - automatic
`git rm --cached` is a destructive action a guard should not take unattended.

**Second known residual: a negation line is reported, never removed, and never overridden - in BOTH
orderings.** Two shapes reach it, and an earlier draft handled only the first:

- **`*` then `!<something>`:** A2's first case matches (a bare `*` IS present), nothing is appended, and
  B3's untracked branch fires.
- **`!<something>` with no bare `*`:** A2's MIDDLE case PREPENDS `*` and B3's untracked branch fires.
  **Before the middle case existed, A2 APPENDED `*` here, git's last-match-wins silently made the file
  ignored, B3 was unreachable, and the human's intent was destroyed with no report.**

In both shapes the helper **never deletes, edits or reorders a line a human wrote**, and it never lets a
negation outrank the `*`. Auto-deleting a deliberate line is the destructive-footgun class: a missing
shield is trivially restorable, a destroyed intent is not. **What the helper does NOT do is close the
leak for the negated path** - that file stays visible to git until a human acts, which is why B3's report
must be loud. **If that trade is wrong, it is an owner call to invert** - the alternative is the helper
rewriting the shield to exactly `*`, which closes the leak automatically at the cost of discarding a user
edit to a file we created.

**What prepending costs, stated so it is not discovered as a surprise:** the helper writes into a file a
human has edited, changing its first line. That is a real mutation of user content and it is not free -
but it is ADDITIVE and order-preserving, and the alternative measured in round 1 (write nothing) exposed
every other file in the directory. **The narrow, honest statement of the residual is therefore: the
negated path leaks until a human acts; nothing else in the directory does.**

**And that residual is NARROWER than this section alone would suggest - it reaches only files sitting
DIRECTLY in `.clavity/`.** Measured 2026-08-14: git cannot re-include a file whose parent directory is
excluded, and the bare `*` excludes every subdirectory, so a negation naming a NESTED path is inert -
`check-ignore` on `.clavity/seams/x.md` returns **0, still ignored**, under a shield of `*` plus
`!seams/x.md`, while the top-level control returns 1. **So `local-anomalies.md` and the other top-level
files are the only ones this residual can touch; `seams/`, `scratch/` and `agy-marks/` are protected
absolutely, negation line or not.** The measurement is recorded again in section 4.2 where it also
governs `prepare`; it is repeated here because this is where the residual is DEFINED, and a reader who
only reaches this paragraph would otherwise generalise it to the whole directory.

### 4.2 Item 14c - Step 0 is DONE, and it changed what this item IS

**AMENDED 2026-08-14, after the plan's Step 0 ran.** The previous text of this section specified "every
hook that writes into `.clavity/` calls the 4.1 helper" and left the count open. Step 0 has now run, and
**both halves of that framing were wrong**: the count was wrong, and so was the CATEGORY. The section
below replaces it. The original obligation - "a count with no stated predicate is not a measurement" -
was correct and is what surfaced this.

**The predicate, stated.** A shipped plugin artifact that CREATES or WRITES a path under
`<repo-root>/.clavity/`, traced through variable assignments to the resolved target - not by proximity of
a write construct to the token `.clavity`.

**The enumeration, by name.** Identical in both products (every file below is a byte-identical pair,
verified by `git hash-object`):

| artifact | write sites | asserts the shield today |
|---|---|---|
| `plugin/hooks/agy-discipline-reaching.sh` | `:96-97` (`mkdir`), `:108-109` (appends `discipline-reaching.jsonl`) | **no** |
| `plugin/skills/agy-first/SKILL.md` | `:37` (`.clavity/seams/<topic>.md`), `:93`, `:96` (`agy-marks/`, `skipped.log`), `:105` (the `.head` marker) | **no** |
| `plugin/skills/agy-capstone/SKILL.md` | `:41` (`.clavity/seams/<topic>.md`), `:43` and `:174` (`.clavity/scratch/<topic>/`), `:179-180`, `:252-253` (`skipped.log`), `:265` (the `.head` marker) | **no** |
| `plugin/skills/agy-test-audit/SKILL.md` | `:36` (`.clavity/seams/<topic>.md`), `:38` (`.clavity/scratch/<topic>/`), `:221-222` (the `.head` marker) | **no** |
| `plugin/skills/open-issues/SKILL.md` | `:69` (`mkdir`), `:86`, `:88` (appends `local-anomalies.md`) | weakly, at `:79` - **this is item 14d** |

**Excluded, with the reason:** `adversarial-panel-review/SKILL.md:203` names the path but delegates the
write ("via the `open-issues` skill"), so it is not an independent writer. The six other hooks that
mention `.clavity` write to `${TMPDIR:-/tmp}` or `$HOME/.clavity-tmp` - a DIFFERENT directory, and they
say so themselves (`agy-anomaly-capture-reminder.sh:49`, `assertion-strength-reminder.sh:9`: the marker
"must never live in `.clavity/agy-marks/`"). `agy-consult-guard-lib.sh:49-50` and
`agy-consult-guard-pre.sh:41` write under `${TMPDIR:-/tmp}/claude-agy-consult-guard`.

**So ROADMAP section 14c is wrong in KIND as well as in count: the set is five artifacts, and four of
them are SKILLS, not hooks.** Its "7 shipped hooks" came from a proximity predicate, stated in its own
sentence as hooks that "reference `.clavity/` with a write construct". **Owner decision 2026-08-14: that
entry is REWRITTEN IN PLACE**, not annotated with a correction, so no future reader meets the wrong
sentence at all. The follow-up at ROADMAP `:991` ("section 14c's seven hooks") is part of the same fact
and must be swept with it - global rule 4.

#### The contract problem, and why it decides the design

Four of the five callers are `SKILL.md` files. **A skill is markdown an agent reads, not an executable.**
`agy-first/SKILL.md:93-96` does not run; it TELLS an agent to create a directory and append a line. Two
consequences, and they are one decision, not two:

1. **Prose cannot satisfy a wiring contract.** "The caller invokes the helper" has no referent when the
   caller is a language model reading instructions. It may write the marker with a shorter command of its
   own and never touch the helper.
2. **No non-vacuous oracle exists for a prose caller.** The only available test is a regex asserting the
   `.md` file CONTAINS the instruction. The mutation that must turn it red - the model ignoring the
   instruction at runtime - leaves the string sitting in the file. That is exactly the presence-not-mutation
   anti-pattern global rule 2 forbids.

**This argument applies equally to `open-issues/SKILL.md:79`**, the shield line the whole batch exists to
improve, which is itself a fenced snippet inside a skill. That was raised as a reason to keep 14c narrow -
adopting a fix here changes the shield's DELIVERY MODEL, not just this item. **Owner decision 2026-08-14:
proceed anyway, with the full fix.** The delivery-model change is accepted deliberately and is no longer
grounds for deferral.

#### Required behaviour - the caller becomes an executable

**A new shipped executable, `plugin/hooks/agy-mark.sh`, becomes the sanctioned way for the four SKILLS to
write under `<repo>/.clavity/`.** It is hard-wired to call the 4.1 shield helper before every write.

**It is NOT "the only sanctioned writer", and an earlier wording of this line said so wrongly.** Two other
sanctioned writers remain by design, and the contradiction matters because an implementer reading "only"
would go looking for a third thing to change:
- `open-issues/SKILL.md` keeps its own inline snippet. That file is **item 14d**, whose whole job is to
  fix that snippet in place; routing it through `agy-mark.sh` is not in this batch.
- `agy-discipline-reaching.sh` sources the 4.1 helper **directly**, as a hook already can
  (`agy-consult-guard-pre.sh:14` is the precedent). It does not need the wrapper.

The wrapper exists for the callers that are markdown, and for nothing else.

That turns an untestable prose contract into a testable executable one: the oracle runs `agy-mark.sh`
against a broken shield and asserts restoration, and neutering its call to the helper turns that test RED.

**The seam and scratch writes are the largest exposure in the set, and an earlier enumeration missed them
entirely.** Beyond markers and log lines, three of the four skills write `.clavity/seams/<topic>.md`
(`agy-first:37`, `agy-capstone:41`, `agy-test-audit:36`) and two write into `.clavity/scratch/<topic>/`
(`agy-capstone:43`, `:174`, `agy-test-audit:38`). **A seam file carries a review brief, a commit range,
file paths and quoted source - far more sensitive than a SHA or a timestamp**, and any severity argument
that weighed only markers and logs was ranking an incomplete set. It is also arbitrary multi-kilobyte
markdown, so it **cannot travel through `argv`**, and no content-carrying mode should be invented for it.

**Because the shield is per-DIRECTORY, it does not need to.** The skill calls
`agy-mark.sh prepare seams/<topic>.md` (or `prepare scratch/<topic>/<name>`) naming the FILE it is about
to write; the script creates and shields the parent directory and verifies the effect for that exact
path, then the skill writes the file with its ordinary tooling. Stating this explicitly is required: without it an implementer either invents a `file` mode that
takes content on the command line, or leaves the highest-exposure writes unshielded because no mode
covered them.

**It lives in `plugin/hooks/` even though it is not a hook.** That is the existing precedent, not a
category error: `agy-consult-guard-lib.sh` is a non-hook file in the same directory, sourced by
`agy-consult-guard-pre.sh:14` as `. "$(dirname "$0")/agy-consult-guard-lib.sh"`. Placing it there also
means it is picked up automatically by the two gates that matter - `check-seed-artifacts-synced.sh:63-64`
enumerates `hooks skills knowledge` in both plugins and requires byte-identity, and
`plugin-hooks-payload.Tests.ps1` asserts pure ASCII (`:32`) and cross-driver byte-identity (`:47`) over
the same glob. **No registration in `hooks.json` is required or wanted** - it is not an event hook.

| aspect | contract |
|---|---|
| form | an EXECUTABLE `.sh` (not sourced), so `exit` is correct here - the opposite of the 4.1 helper's `return`-only rule, and the difference is load-bearing |
| root | resolved with `git rev-parse --show-toplevel`. A subprocess is affordable here because this runs once per discipline event, not per turn. **If it cannot resolve, REFUSE and exit non-zero** |
| modes | `head <discipline> <sha>` (write `.clavity/agy-marks/<discipline>.head`), `log <discipline> <status> <sha> [text...]` (append one line to `.clavity/agy-marks/skipped.log`), `prepare <relpath>` (create the parent directory of `.clavity/<relpath>` and shield it, for the `seams/` and `scratch/` cases) |
| **EVERY mode creates the directory it writes into - `head` and `log` included** | Stage A1 of the 4.1 helper creates `<root>/.clavity/` and **nothing below it**, so `.clavity/agy-marks/` does not exist on a fresh clone. `prepare` was told to create its parent; `head` and `log` were not, and **this batch simultaneously removes the `mkdir` instructions the skills carried for themselves** - so on a fresh clone both modes would fail `No such file or directory` on the first discipline that ran. The very failure the shipped `open-issues` snippet already guards against at its own `:69` |
| **`head`'s PAYLOAD is already contracted elsewhere - cite it, do not invent it** | the file contains **the bare sha and nothing else**. `docs/agy-disciplines-marker-contract.md:18` states it: "the commit sha from `git rev-parse HEAD` at consult time, and nothing else". An earlier draft of this table named the PATH and left the CONTENT undefined, which is not enough to implement from - `touch`ing the file and ignoring the argument would satisfy the words. **A trailing newline happens to be tolerated** because the reader compares `"$(cat "$marker")"` against `"$(git rev-parse HEAD)"` (`agy-seam-inject.sh:125`) and command substitution strips trailing newlines from both sides - but write it bare regardless, because the contract says "nothing else" and the tolerance is a property of the current reader, not a promise |
| **`prepare` takes the FILE path, not the directory** | An earlier draft called it `dir` and passed `seams`, which throws the filename away so the helper's Stage B evaluates the DIRECTORY and never the file. `git check-ignore` accepts paths that do not exist yet (**measured**: a not-yet-written path under a shielded directory returns 0, and the control - a not-yet-written path outside it - returns 1), so passing the eventual file path costs nothing. **What it buys is the TRACKED-file check (B3), not the negation check** - see the correction below |
| **The negation leak CANNOT reach a nested path, and the earlier rationale for this mode was wrong** | An earlier draft justified `prepare` by saying a `!seams/<topic>.md` line would otherwise go undetected. **Measured 2026-08-14: it cannot leak at all.** With the shield at `*` plus `!seams/not-written-yet.md`, `check-ignore` on `.clavity/seams/not-written-yet.md` returns **0 - still ignored** - because git cannot re-include a file whose PARENT DIRECTORY is excluded, and `*` excludes `seams/` itself. The top-level control behaves oppositely and is what section 4.1's residual describes: `*` plus `!local-anomalies.md` on a file directly in `.clavity/` returns 1. **So the negation residual applies ONLY to files at the top level of `.clavity/`; every nested payload - seams, scratch, agy-marks - is protected absolutely.** The mode is still right, because B3 also distinguishes a TRACKED file, which a nested path certainly can be. The conclusion survived; the reason did not |
| **the script owns the log LINE FORMAT** | `log` emits `<iso-8601>  <discipline>  <status>  HEAD=<sha>[  <text>]`, generating the timestamp and the `HEAD=` prefix itself. **The callers must NOT pass a preformatted line.** TWO of the three rewritten skills document that shape in their own prose today (`agy-first:96`, `agy-capstone:180` and `:253`; `agy-test-audit` writes only a `.head` marker and never uses `log`); moving it into the script is the entire point of having a script, and leaving it in the callers keeps copies of a format that must agree |
| **it validates its OWN arguments - it cannot delegate that** | `<discipline>` and `<relpath>` are interpolated into a path, so a value containing `/` or `..` escapes the directory. **The 4.1 helper cannot catch this for it:** that helper returns 0 on a validation fault BY CONTRACT, so `agy-mark.sh` receives success and would proceed to write. It must therefore reject any `<discipline>` that is not `[A-Za-z0-9._-]+`, and any `<relpath>` containing `..` or a leading `/`, BEFORE calling the helper and before any write |
| shield | calls the 4.1 helper BEFORE any write, on every mode, with no way to skip it. The helper's return value carries no information (always 0) and must not be branched on |
| exit codes | `0` wrote successfully; `1` refused, NOTHING written (bad argument, helper unloadable, root unresolvable); `2` wrote partially or the write itself failed. **A caller must be able to tell "refused" from "wrote", and a single non-zero cannot express that** |
| **failure direction - and it is NOT uniform across modes** | `head` and `prepare` **fail CLOSED**: write nothing, exit 1. That is safe precisely because an absent marker makes the discipline RE-FIRE next trigger, which every one of these skills already documents (`agy-test-audit/SKILL.md:225`: "If HEAD cannot resolve, skip writing (the discipline re-fires next trigger - safe)"). **`log` has NO such re-fire path** - `skipped.log` is a durable audit breadcrumb, and `agy-first/SKILL.md:99-101` describes it as surviving normal operation - so a refused `log` write destroys a record with nothing to recreate it. **`log` must therefore emit BOTH the line it could not write AND the reason it could not write it to STDERR**, then exit non-zero. Emitting only the payload leaves the operator holding a log line with no idea why it never reached disk - the environmental fault that caused the refusal is exactly what they need in order to fix it. **This obligation is tied to the RECORD NOT REACHING DISK, not to a particular exit code**: it binds on exit 1 (refused before writing) AND on exit 2 (the write itself failed partway - a full disk, a permissions change). An earlier draft attached it to exit 1 alone, which lets a failed `printf` drop the line silently into the void, where the data is exactly as lost as in the case the rule was written for. An earlier draft justified fail-closed for all three modes with the re-fire argument, which is true only for two of them, and a later one degraded the payload without the diagnosis |
| **`prepare` fails closed too, but the caller must ACT on it - the re-fire argument does not cover this either** | `prepare` creates the directory a discipline is about to fill with a seam or a scratch file. If it refuses, the directory does not exist, and the agent's very next write fails with `No such file or directory` **in the middle of the discipline** rather than re-firing cleanly. Refusing is still correct - creating an unshielded directory for a review brief is the leak this item exists to stop - but **the three rewritten skills must check the exit status and ABORT the discipline with a named reason**, exactly as they already do for an unreachable peer. A skill that invokes `prepare` and ignores its exit code converts a clean refusal into a mid-run crash |
| **all three modes are the OPPOSITE of the 4.1 helper's fail-open rule, deliberately** | the helper runs inside a PreToolUse chain where a non-zero exit BLOCKS an agent; this script is invoked directly by a skill, where a refusal blocks nothing. **Do not harmonise them** |
| concurrency | `log` appends with ONE `printf ... >>`, never read-modify-write. Two sessions can be open on the same repository at once - `open-issues/SKILL.md:80-85` already reasons about exactly this - and a single short append is atomic on POSIX, so concurrent writers interleave lines rather than corrupting them |
| debounce key | `${AGY_SESSION_ID:-}` from the environment, forwarded to the helper. Empty disables debouncing, which is the safe direction for a leak notice |

#### How a skill LOCATES the script - the one thing that can make this item unbuildable

**This is a Step 0 measurement, not an assumption, and the fallback space is narrower than it looks.**
`$CLAUDE_PLUGIN_ROOT` is set for HOOK invocations; whether it resolves in a skill-context shell call is
**unmeasured**, and this repository has already been bitten by that exact variable failing to resolve in
one lifecycle event and not another (`agy-discipline-reaching.sh:9-12`: it "DOES NOT RESOLVE at
SessionEnd", measured 3/3). Writing it into three shipped skills on the strength of it working for hooks
would be the same class of error this spec has already corrected twice.

**And a hand-rolled fallback is blocked by an invariant this repository has already recorded.** The skills
are byte-identical pairs, so **the skill body cannot carry a per-plugin literal** - `agy-first/SKILL.md:111-112`
states exactly that constraint and its reason: "the byte-identical skill body cannot carry a per-plugin
literal, and the two drivers are mutually exclusive (only one `clavity` plugin installed; both-installed
is a transient migration state ...)". So the obvious fallback - a glob across both product trees - is
ambiguous **precisely in the migration state that same line declares supported**, and would resolve to two
paths.

**The outcome is therefore bounded HERE rather than left to the plan's invention:**

| measurement | consequence |
|---|---|
| `$CLAUDE_PLUGIN_ROOT` RESOLVES in a skill-context shell call | the invocation uses it; 14c proceeds as specified |
| it does NOT resolve | **14c's SKILL half is BLOCKED and returns to the owner as a scoping decision.** The HOOK half does not need it and still ships. **The plan does NOT invent a glob, a search path, or a hardcoded install location** |

An earlier wording said only "define the fallback if it does not resolve", which invited exactly the glob
the byte-identity invariant forbids.

#### Tests

**For the hook** (`agy-discipline-reaching.sh`): (a) set up a repo with a BROKEN shield, (b) run the hook,
(c) assert the shield was restored - an observable effect, (d) mutation: remove the hook's call and assert
the same test goes RED. **The test must break the shield first**, because the helper is silent on the
healthy path by contract, so a run against a healthy repository observes nothing and would pass while
asserting nothing.

**And it must assert the hook PASSES ITS DEBOUNCE KEY** - shield restoration alone cannot detect a broken
one. Stage A runs unconditionally and ignores the key entirely, so a hook passing an empty or hard-coded
key restores the shield, passes every test above, and ships with its debounce silently wrong. The hook
already parses `session_id` (`agy-discipline-reaching.sh:42`); assert it forwards THAT value, and a
mutation replacing the argument with an empty string must turn a test RED.

**That mutation cannot turn ANY of the rows above red, and saying so is the point.** Stage A runs
unconditionally and ignores the key entirely, so an empty key still restores the shield - and shield
restoration is the only observable those rows assert. **A demand for a red that no listed row can
produce is an unimplementable instruction**, and an implementer meeting it either invents an oracle or
quietly drops the requirement. The oracle it needs is stated here instead: **run the hook TWICE against
a repository in a PERSISTENT fault state** (the tracked-file case, which reports on every call until a
human intervenes) and **count the helper's lines on stderr**. With the real `session_id` forwarded the
fault is reported ONCE; with an empty key it is reported TWICE. That difference is the only thing that
distinguishes a correct forward from a broken one, and it needs the persistent fault - against a healthy
shield the helper is silent under both.

**For `agy-mark.sh`**: one row per mode against a broken shield asserting restoration plus the correct
write; the fail-closed rows (helper unloadable, root unresolvable) asserting NOTHING is written and the
exit is non-zero; and the mutation control - neuter the helper call and every restoration row must go RED.

**Plus one row per remaining CONTRACT row, because a contract line with no oracle is a suggestion.** A
completeness pass over the contract table found four rules stated and untested:

| case | asserts |
|---|---|
| **`<discipline>` containing `/` or `..`, and `<relpath>` containing `..` or a leading `/`** | REFUSED, exit 1, **nothing created anywhere** - and specifically nothing outside `.clavity/`. The contract requires `agy-mark.sh` to validate these ITSELF because the helper returns 0 on a validation fault; without this row that requirement is unenforced and a traversal payload writes wherever it likes |
| **a write that fails partway** | exits **2**, not 1. The two codes mean different things to a caller - refused-nothing-written versus wrote-something-and-failed - and a suite that only ever sees 1 cannot tell they were ever distinguished |
| **`log` refused (root unresolvable)** | stderr carries BOTH the log line it could not write AND the reason. Asserting only "nothing written, non-zero" passes against a silent refusal, which is exactly the record-destroying behaviour the contract added this rule to prevent |
| **`agy-mark.sh` forwards `${AGY_SESSION_ID:-}` to the helper** | with the variable set, a repeated persistent fault emits once; with it empty, it emits every time. The hook's own forwarding is already pinned; **the wrapper's was not**, and it is a separate code path |

**For the three rewritten skills there is deliberately NO behavioural test, and the plan says so rather than writing
a weak one.** The strongest available oracle would assert the `.md` contains the invocation string, which
cannot fail against a model that ignores it. The executable is where the strength lives; the skills are
its callers and are covered by the residuals below. **Writing a presence-grep here and calling the skills
covered would be the fifth vacuous oracle this review has removed.**

**But "no behavioural test" leaves a DIFFERENT hole, and it is not the same one.** Nothing at all would
detect that a skill edit was simply **not made** - a task skipped, or three of four files edited. The
existing gates do not close it: `check-seed-artifacts-synced.sh` and `plugin-hooks-payload.Tests.ps1:47`
compare the two PRODUCTS against each other, so a skill left unedited in BOTH passes byte-identity
happily. **A presence-grep is a vacuous oracle for "does the model obey the instruction" and a sound one
for "was the file edited at all"** - these are different questions, and conflating them is what would
otherwise leave the omission undetected. The plan therefore carries an explicit per-file completion check
over the six paths (three skills times two products), stated as a checklist item and NOT dressed up as coverage of the skills' runtime
behaviour.

#### Residuals, stated rather than discovered later

- **The skills are still prose.** `agy-mark.sh` is invocable, not compulsory; a model may still write a
  marker by hand. The change narrows the unshielded surface from four described writes to one described
  INVOCATION, and makes the thing invoked correct by construction. It does not make invocation certain.
- **`agy-discipline-reaching.sh` runs at SessionStart, before any skill can run**, so in the common case
  it creates and shields `.clavity/` first and every later marker write lands in an already-shielded
  directory. **That is a mitigation, not the fix**, and it has a named hole: the hook exits early when
  `.no-agy` is present (`:53`, `:87`) or there is no `.git` (`:81`), and a user can still invoke
  `agy-capstone` by hand in that state.
- **The 4.1 helper's debounce key is `<session>-<fault-class>`, not per-path**, so a second distinct file
  with the same fault class in the same session is suppressed. Accepted; the alternative needs a
  subprocess to sanitise a path into a filename.

**The set is fixed BEFORE 14e exists, so 14e must not join it after the fact.** 14c lands before 14e; if
14e's pre-commit check wrote its scratch output under `.clavity/`, it would become a writer that 14c's
sweep never saw - shipped un-wired and unprotected, and the 14c tests would still pass because its set was
closed. **14e's scratch path therefore must NOT be inside `.clavity/`** (a system temp location, unique
per invocation per the note in 4.1). Stated as a constraint rather than solved by re-ordering, because the
set has to close somewhere and the rule holds for the NEXT writer too, not just this one.

### 4.3 Item 14e - make parity structural by generating the literals

**Current behaviour.** `lefthook.yml:78-82` globs exactly the three pinned paths, and its own comment at
`:63` says they "are pinned byte-identical to each other" - then runs `check-curate-in-progress.ps1`,
which asserts whether an agy-curate run was left mid-flight. Provenance, not parity. Commit `b2a6cc0`
staged `core.md`, fired that hook, passed it, and committed diverged pins; both suites stayed red from
2026-08-09 to 2026-08-14.

**The lefthook comment is loose and must not be built on.** The three files are 3515 / 11544 / 7801 bytes
with three distinct hashes and can never be identical: one is markdown, one a Rust source containing a
single-line escaped literal, one a C# source containing a concatenated multi-line literal. **The real
invariant is: the DECODED literal equals the markdown file's content.** Both existing tests unescape
before comparing. Any gate built on file-level hash equality could never pass.

**Required behaviour.** `agy-autotrain/knowledge/driver-cheatsheet.core.md` becomes the single source of
truth. A `just` task regenerates both literals from it. Divergence becomes **uncommittable** rather than
merely detectable, and no literal-unescaping logic is written a third time.

**The pre-commit check is NON-DESTRUCTIVE and checks TWO things, not one.** An earlier draft said only
"runs the generator and asserts the tree is clean", which is wrong twice over:

1. **It must not regenerate in place, and it must compare against the INDEX - not HEAD.** Writing into
   the working tree during a commit hands the author files they did not edit and can collide with
   deliberate work in progress, so the hook generates to a TEMPORARY location and compares. **It compares
   against the STAGED content** (`git show :<path>`), because a pre-commit hook runs while the author is
   committing: someone who legitimately edits `core.md` and stages the regenerated literals would be
   REJECTED by a comparison against the committed (HEAD) versions - the hook would block precisely the
   correct workflow it exists to enforce. It reports the difference; it does not silently repair it.
   Repair is the author running the `just` task deliberately.

   **BOTH SIDES MUST COME FROM THE INDEX - input as well as output. In the hook, the generator is fed
   `git show :<core.md path>`.** The hook validates what is about to be COMMITTED, and the index is the
   only faithful statement of that.

   **Feed it as RAW BYTES, never through a PowerShell text pipeline - this repository has already paid
   for that lesson once.** The hook runs under `pwsh`, and piping `git show` output into the generator as
   text re-decodes the stream through the host console encoding and re-encodes it on the way out,
   normalising line endings and mangling any byte the code page cannot represent. The `agy-curate` skill
   documents the identical trap for `curate-commit`: a text pipe "re-encodes the stream through the
   console OEM code page (CP437)". `core.md` is pure ASCII today (measured: 0 bytes above 127), so the
   character-mangling half is latent rather than live - **the line-ending half is not**, and it lands
   directly on the LF-versus-CRLF invariant this whole item turns on.

   **DO NOT USE `>` FOR THIS, and the reason is measured rather than argued.** In PowerShell `>` is not
   a byte redirect - it is `Out-File`, which decodes the stream and re-encodes it. Measured 2026-08-14
   with `git show :<core.md>` on both engines:

   | engine | `git show ... > file` |
   |---|---|
   | pwsh 7 | 3508 bytes, 0 CRLF, 7 LF - **byte-identical to the index blob** |
   | Windows PowerShell 5.1 | **7032 bytes** (exactly double), 0 CRLF - **UTF-16LE** |

   So the hazard is real but it is an ENCODING hazard, not the line-ending one you would predict: 5.1's
   `>` defaults to Unicode and silently doubles the file. **pwsh 7 happens to be byte-exact today**, and
   `lefthook.yml:82` does invoke the hook as `pwsh`, so the shipped path is currently safe - **which is
   exactly the kind of incidental safety this spec already refused to rely on for CRLF.** A future
   `powershell.exe` invocation, or a change in `Out-File`'s defaults, breaks it silently.

   **Use an explicit byte-exact mechanism:** start git through `ProcessStartInfo` with
   `RedirectStandardOutput`, and copy `StandardOutput.BaseStream` straight into a `FileStream`. This is
   the mirror image of the transport the `agy-curate` skill already mandates in the other direction
   (writing raw bytes into a process's `StandardInput.BaseStream` rather than piping text), so it is an
   established pattern here, not a new one. Never interpolate the content through a variable, a pipe, or
   `>`.

   **THIS BINDS EVERY INDEX EXTRACTION THE HOOK MAKES, NOT ONLY THE GENERATOR'S INPUT - and scoping it
   to the input alone GUARANTEES the comparison fails.** Parity compares the generator's byte-exact
   output against the **STAGED LITERALS**, which the hook must also read out of the index
   (`git show :<literal path>`). If that second extraction goes through ordinary stdout capture it is
   re-encoded by the same mechanism - UTF-16LE under Windows PowerShell 5.1, measured above - while the
   generated side is byte-exact. **The two sides would then be produced by different transports, and
   parity is an EXACT comparison** (only remedy 1's diagnosis normalises). That is not a risk of a
   mismatch, it is a certainty of one on the affected engine. **Extract both sides the same way.**

   **A STAGED DELETION of `core.md` must be handled BEFORE the generator runs, or the hook traps the
   operator in a loop they cannot exit.** Measured 2026-08-14: with `core.md` deleted and the deletion
   staged, `git show :<path>` fails with `fatal: path 'core.md' does not exist (neither on disk nor in
   the index)` and exits **128**. Per the exit-status rule below, a non-zero generator exit fails the
   hook outright - so an operator legitimately deleting or renaming the file is blocked on every attempt,
   with a message about parity that has nothing to do with what they did. **The hook must first ask
   whether `core.md` is present in the index at all.** If it is absent because its deletion is staged,
   there is no canonical source and therefore no parity to assert: the hook PASSES the parity check and
   says plainly that it is skipping because the canonical source is being removed. Deleting the pinned
   source is a real decision, but it is the pinning TESTS' job to fail on it, not this hook's.

   **The original rationale for this rule is now STALE, and saying so matters because a stale rationale
   invites someone to delete the rule.** It was introduced to stop partial commits being falsely blocked.
   Case 3 later made partial staging fail outright and is evaluated FIRST, so past Case 3 the worktree and
   index agree on `core.md` except in line endings - which the generator normalises anyway. **On that
   path, reading the worktree would produce identical output, so the rule is no longer load-bearing for
   the reason it was written.** It is kept because it is free, because it states precisely what is being
   validated, and because Case 3's own detection could regress. What it is NOT is a fix for partial
   commits; that is Case 3's job now.
2. **It must assert the generator's own exit status FIRST.** If the generator crashes, the working tree
   is untouched, so a bare `git diff --quiet` returns 0 and the hook PASSES - committing diverged
   literals with a green check. **A generator that failed to run is not evidence of parity.** This is
   global rule 5 applied here: **`git diff --quiet`'s ZERO is the false-positive zero** - it reports
   "nothing differed", which is indistinguishable from "nothing ran". So a non-zero GENERATOR exit fails
   the hook outright, and only after a zero generator exit does the diff carry any information.

**Why generation is right here specifically, stated WITHOUT presuming the ownership answer.** An earlier
draft justified this by asserting "`core.md` is driver-owned" - which **contradicts section 7 and ROADMAP
14f**, where that ownership is exactly what is unresolved and awaiting an owner ruling. The spec must not
settle in 4.3 the question it defers in section 7.

The correct argument does not need the answer: **the generator only ever READS `core.md`, so it is
correct under EITHER resolution of 14f.** Whoever turns out to own the file, generation removes the manual
multi-file mirroring that made a mistaken edit dangerous - it narrows the hand-edited surface from three
files to one, which is an improvement regardless of who is permitted to make that edit.

**Tests - the generator-control pattern.** Fed the PRE-change input, the generator must reproduce the
CURRENT artifact byte-for-byte; only then is it fed the new input and shown to differ by exactly the
expected delta. Both existing pinning tests stay and must remain green - they are the oracle the
generator is proven against, and are not to be edited to match generator output.

**The HOOK needs its own tests, and an earlier draft tested only the generator.** Every rule added to the
hook above is a branch that can silently invert, and none of them is exercised by testing the generator
alone:

| case | asserts |
|---|---|
| generator exits non-zero | hook FAILS - it must not pass on an untouched tree |
| **`core.md` DELETION staged** | hook PASSES, with a message naming the skip reason. **Measured: `git show :<path>` exits 128 there**, so without this the hook fails every attempt to delete or rename the canonical source and the operator cannot get past it |
| **the hook is run against a fixture `core.md` containing a byte a pwsh text pipeline would alter** | the hook's generated output reproduces that byte EXACTLY. A hook that pipes the content as text turns this RED; a hook using raw-byte transport passes. **The fixture is constructed in a throwaway repo, so the ASCII rule that governs the real `core.md` does not constrain it** |
| **hook temp file after every exit path, including the failure paths** | no temp file survives the run |
| `core.md` staged, literals staged and correct | hook PASSES (the correct workflow is not blocked) |
| `core.md` staged, literals stale in the index, **correct output already in the worktree** | hook FAILS with **remedy 1** - says `git add` the literals and does NOT name the `just` task (re-running it is a no-op) |
| `core.md` staged, literals stale in the index **and in the worktree** | hook FAILS with **remedy 2** - names the `just` task |
| **partial stage: `core.md` hunks split with `git add -p`, literals generated from the WORKTREE** | hook FAILS, **and its message says partial staging of `core.md` is unsupported** - see the remedy rules below. Parity fails first (the `just` task read the full worktree text), and case 3 is what names the real cause. An earlier draft claimed this PASSES, which was wrong |
| **literals staged, `core.md` edited but NOT staged at all** | hook FAILS with the "you staged the generated literals but not `core.md` itself" message, **not** the partial-staging one. Assert the message TEXT, not merely that it failed - both branches fail, and only the text distinguishes a correct diagnosis from a misleading one |
| **`core.md` staged complete, literals staged and correct, then FURTHER unstaged edits made to `core.md`** | hook **PASSES**. This is an ordinary iterative workflow and the staged content is self-consistent, which is the only thing the hook validates. **A draft that evaluated case 3 before parity rejected this**, and a gate that rejects a correct commit teaches its users `--no-verify` |
| worktree `core.md` CRLF, index LF, literals correct | hook PASSES. **This does NOT prove the hook reads the index** - see below; it is a regression pin against CRLF breaking the run, nothing more |
**There is deliberately NO end-to-end row proving the hook reads the index, because no such row can
exist.** Round 10 added one requiring a CONTENT difference between index and worktree. It is unreachable:
**Case 3 is evaluated FIRST and aborts on exactly that state**, so a correct hook never reaches generation
there - only a hook with a BROKEN Case 3 could reach it and pass. And a line-ending-only difference is
erased by the generator's normalisation before anything can observe it. **Case 3 excludes every state in
which reading the worktree would differ from reading the index**, so the property is unobservable through
the hook's behaviour by construction.

This is consistent with the rule's status, not a hole: reading the index is retained as belt-and-braces
(it states precisely what is being validated, and Case 3's detection could regress), and it is explicitly
**not separately testable end to end**. If it ever needs pinning, it must be asserted at the call site -
that the generator is invoked with `git show :<path>` - not through observed hook output. **A row that
cannot fail against a correct implementation is exactly what the other four vacuous oracles this review
removed looked like**; adding one back to cover a non-load-bearing rule would be the same mistake.
| hook run twice | working tree unchanged both times (it must never write in place) |

**The text-pipe row above was rewritten at re-panel round 2, and the shape it replaced is worth naming
because it is easy to write again.** The first version asserted "output fed through a text pipe DIFFERS
from the raw-byte path". That is a true statement about PowerShell and a useless one about this hook: a
correct hook never uses a text pipe, so the assertion cannot be run against it at all, and the only way to
make the row green is a detached fixture that pipes something through `Out-String` and confirms pwsh
mutates it. **The developer then satisfies the table in full while shipping a hook that still uses a
pipeline.** The rule is general: **a row must assert something about the ARTIFACT UNDER TEST, exercised
through its real entry point.** A row that demonstrates a property of the toolchain is documentation
wearing a test's clothes.

**The CRLF test belongs on the `just` task, NOT here - and putting it here would have been a vacuous
oracle.** An earlier draft of this table asserted "`core.md` CRLF in the worktree -> generated literals
contain no `\r`" as a HOOK test. The hook feeds the generator `git show :<path>`, and an index blob is
already LF, so the worktree's line endings are invisible to it: **that row would pass even if the
generator's CRLF handling were entirely deleted.** The hook row above is the correct one - it pins that
the hook reads the index. The CRLF assertion moves to the `just` task's tests:

| `just` task case | asserts |
|---|---|
| **a FIXTURE file whose bytes explicitly contain `\r\n`** | generated literals contain no `\r` |
| mutation: delete the CRLF normalisation | the row above turns RED |

**The fixture must be CONSTRUCTED, never the live `core.md`.** Its line endings depend on the host: CRLF
on this Windows checkout, **LF on Linux and in CI**. A test that feeds the live file processes LF there,
emits LF, and stays green - and so does the mutant with normalisation deleted. **The test and its own
mutation control would both pass on CI while proving nothing**, which is the worst kind of green: it is
platform-dependent, so it would look correct on the machine where it was written. Write `\r\n` bytes into
a temp fixture and feed that.

This split matters because the two entry points genuinely differ: **the hook reads the index (always LF),
the `just` task reads the working tree (CRLF on Windows today, measured).** Only the second can exercise
constraint 1b.

**Mutation control:** neuter the generator's exit-status assertion and the "generator crashed" row must
turn RED. If it stays green, the assertion is decorative.

**The failure MESSAGE is part of the contract, because a wrong remedy is a trap, not an inconvenience.**
"Run the `just` task" is the wrong advice in two of the three failure modes, and following it produces an
identical second failure - the user runs a no-op and is rejected again with the same text. The hook
distinguishes three cases and names the remedy that actually works:

**PARITY IS EVALUATED FIRST, AND IT IS THE ONLY THING THAT CAN PASS THE HOOK. The three cases below are
DIAGNOSIS, reached only after parity has already failed.** An earlier draft tested case 3 first and
short-circuited on it, which **blocks a correct commit**: `git diff --quiet -- <core.md>` compares the
worktree to the index, so it fires whenever the author has staged a complete change and then started
follow-up edits to `core.md` before typing `git commit` - an ordinary iterative workflow. In that state
the staged literals may agree perfectly with the staged `core.md`, which is the only thing the hook is
entitled to validate. **A gate that rejects a valid commit because of unstaged work it is not validating
will not survive first real use, and the first thing its users will learn is `--no-verify`.**

So: generate from the staged `core.md`, compare against the staged literals, and if they agree, **PASS
and stop** - whatever the worktree looks like. Only when they DISAGREE does the hook need to tell the
author why, and only then do the overlapping cases below matter.

**Within the diagnosis, the order is part of the contract - case 3 is tested FIRST and short-circuits.**
A partial stage also satisfies case 1 or case 2, so a hook that checks them in table order emits "`git
add` the literals" or "run `just <task>`" to a user whose real problem is the partial stage. Following
that advice stages full literals against a partially-staged `core.md` and fails again - the exact loop
this table exists to prevent. **Diagnosis order: 3, then 1, then 2.**

| # | what the hook observes | message must say |
|---|---|---|
| **3** (evaluated FIRST in the diagnosis) | **staged `core.md` differs from worktree `core.md`.** **Detect with `git diff --quiet -- <core.md>`, NEVER a byte comparison** - see below. **Then SPLIT on whether `core.md` is staged at all**: `git diff --cached --quiet -- <core.md>` exits 0 when the index matches HEAD, i.e. nothing was staged | **two messages, because one misdiagnoses the commoner case.** If `core.md` IS staged (a genuine partial stage): "**partial staging of `core.md` is not supported.** The literals are generated from the STAGED text, and the `just` task reads the WORKTREE, so the two cannot agree. Stage `core.md` in full **together with the regenerated literals**." **Never advise committing `core.md` on its own** - an earlier wording did, and parity is evaluated FIRST, so a commit carrying a changed `core.md` without its regenerated literals fails parity and is rejected anyway. Advice the hook itself blocks is worse than no advice: it costs the operator a second rejection to discover. If `core.md` is NOT staged at all: "**you staged the generated literals but not `core.md` itself.** `git add` it." Telling someone their staging is "partial" when they staged nothing is a misdiagnosis that makes the hook look broken - and forgetting the source file while staging its generated output is the likelier mistake of the two |
| 1 | staged literals differ from generated, and the GENERATED output equals the literal as it sits in the WORKTREE. **This comparison is temp-file-to-worktree, so `git diff` cannot make it** - see below. Normalise both sides CRLF->LF and compare the normalised text | "regenerated output is already in your worktree - **`git add` the two literals**" (running the task again changes nothing) |
| 2 | staged literals differ from generated, worktree literals also stale | "**run `just <task>`, then `git add` the two literals**" |

The third case is the one an earlier draft got wrong by asserting it would pass. It cannot: the hook
compares index-to-index, so valid staged literals must be generated from the STAGED `core.md`, and the
`just` task - which reads the working tree - cannot produce those. **Detecting it and saying so plainly
is the fix; silently failing with generic advice is the trap.**

**Case 3 MUST be detected with `git diff --quiet`, and a byte comparison would block every commit in this
repository.** Measured 2026-08-14: worktree `core.md` is **3515 bytes**, the index blob is **3508** -
**not byte-equal**, because `core.autocrlf` stores LF and checks out CRLF. They ARE equal after LF
normalisation. So a naive "does `git show :<path>` differ from the file on disk" check evaluates TRUE on
every commit, firing Case 3 unconditionally and telling every user their commit is an unsupported partial
stage. `git diff --quiet -- <core.md>` returns **0** on that same state (measured), because git compares
through the same normalisation it applies on checkout. **This is the CRLF hazard of constraint 1b
reappearing in the DETECTION path rather than the generation path** - the same trap, one layer over.

**But that rule is specific to Case 3, and generalising it to remedy 1 makes an impossible demand.**
`git diff` can compare CRLF-agnostically only between two things git TRACKS - worktree against index,
or index against HEAD - because the normalisation comes from the repository's own attributes. Remedy 1
needs a different comparison: **a generated TEMP file against the worktree literal.** Neither form of
`git diff` can express it. `git diff --quiet -- <literal>` compares the worktree to the STALE INDEX and
says nothing about the generator's output; `git diff --no-index <temp> <literal>` steps outside the
repository entirely, so no `.gitattributes` normalisation applies and an LF temp file against a CRLF
worktree file reports as different. **For remedy 1, read both sides, normalise CRLF->LF, and compare the
normalised text** - which is exactly what both existing pinning oracles already do
(`DriverCheatsheetTests.cs:92` reads the file and applies `.Replace("\r\n", "\n").Trim()` before
comparing). The "never raw bytes" instruction belongs to Case 3 and to Case 3 only.

**Generator constraints - these are design-level, not plan-level, because they eliminate candidates:**

1. **It must run on Windows and in CI**, in both products' pipelines. **The surviving candidate is
   PowerShell (`pwsh`)** - it is already required by `lefthook.yml`, by every script in `scripts/`, and by
   the drain flow, so it adds no dependency. Python exists in this tree only for the classic bridge's
   linting and is not a build dependency of either product; Rust and C# would each run in only one of the
   two. The plan may choose otherwise only by naming what makes `pwsh` unsuitable. **A constraint list
   that eliminates candidates without naming the survivor is not actionable** - this line exists because
   an earlier draft did exactly that.

1a. **PIN ALL THREE FILES TO `eol=lf` IN `.gitattributes` - this kills the whole CRLF class at its root,
   and the repository already uses exactly this mechanism.** Measured 2026-08-14: `core.autocrlf` is
   **true**, and `git check-attr text eol` reports **`unspecified`** for both `driver-cheatsheet.core.md`
   and `driver_cheatsheet.rs`. So nothing pins them, and **a fresh clone checks out all three as CRLF**.
   The existing `.gitattributes` already does this for `*.sh` ("*.sh text eol=lf") for the same reason -
   a CRLF byte breaking a consumer that expects LF.

   **This also corrects a measurement that looked reassuring and was not.** Today the two literals ARE LF
   in this working tree (measured byte-equal to the index), which suggests there is no hazard. That is an
   artifact of THIS tree - the files were last written by an editor, not re-checked-out - and it would
   not hold on a fresh clone or in CI. **A control run in the current working tree reports a false pass
   here**, exactly as it does for the shield when the root `.gitignore` masks a broken one.

   **The pin governs FUTURE checkouts and does NOT rewrite an existing working tree - measured, with a
   control.** In a throwaway repo with `core.autocrlf=true`: adding `*.md text eol=lf` left a CRLF file
   **unchanged**; `git add --renormalize .` normalised the **INDEX** blob to LF but left the **WORKTREE
   still CRLF**. So the sequence matters and the verification must be by bytes, not by assumption:

   0. **PRECONDITION, and it is not optional: the three paths must be CLEAN in the working tree before
      step 3 runs.** Step 3 overwrites the working tree from the index, so a developer who runs this
      sequence mid-edit **silently destroys their own uncommitted changes to `core.md` or a literal**.
      Check `git status --short -- <the three paths>` and refuse to proceed if any is dirty; commit or
      stash first. This repository already carries the narrower version of that rule - a targeted
      per-file `git checkout`, never a broad one - and the destructive step here is exactly the case it
      exists for.
   1. add the attribute lines;
   2. `git add --renormalize` the three paths (fixes what the repo stores);
   3. **force the working tree to be re-checked-out** for those paths, naming each path explicitly and
      never a directory, then **measure the bytes** - do not infer that it worked;
   4. confirm the pinning suites are still green afterwards, because step 3 changes files they compare.

   **This is why the normalisation stays load-bearing rather than belt-and-braces on any tree that
   predates the pin** - including this one, where `core.md` is CRLF today. An implementer who applies the
   pin, measures `core.md`, still sees CRLF and concludes the pin failed would be reading a correct
   result wrongly. Keep the generator's normalisation and every CRLF-agnostic comparison regardless: the
   pin protects new clones, the normalisation protects every tree that already exists.

1b. **NORMALISE CRLF TO LF BEFORE ESCAPING - this is live on this machine, not hypothetical.** Measured
   2026-08-14: `core.md` is **CRLF in the working tree** (7 CRLF, 0 bare LF) and **LF as committed**
   (0 CRLF, 7 LF), because `core.autocrlf` is in effect. The pinning tests normalise only the FILE side -
   `DriverCheatsheetTests.cs:92` reads `File.ReadAllText(...).Replace("\r\n", "\n").Trim()` and compares
   it to the literal AS-IS. So a generator that reads the working-tree copy and escapes newlines naively
   bakes `\r\n` into both literals, the file side is normalised to `\n`, and **the pinning test fails -
   the generator would redden the exact gate it exists to protect.** Normalise, then escape.
2. **`core.md` is inside the ASCII-gated domain** - `agy-autotrain` is one of `$script:DomainRoots` in
   `scripts/check-injected-context.ps1`. The generator must therefore preserve pure ASCII and must not
   introduce any non-ASCII escape of its own. This is the exact rule `b2a6cc0` was enforcing when it
   created the divergence this item exists to prevent.
3. **Escaping is per-target and mechanical**: backslash, double-quote and newline, into a single-line
   `\n`-escaped Rust literal and a concatenated multi-line C# literal. It must never be retyped through a
   terminal, whose code page mangles bytes in transit.

   **THE ORDER IS PART OF THE CONTRACT, not an implementation detail. Backslash FIRST, always.** Escaping
   the newline before the backslash means the generator escapes its OWN output: `LF` becomes the two
   characters `\n`, and a subsequent backslash pass turns that into `\\n`, which both compilers read as a
   literal backslash followed by `n` rather than a newline. The literal then compiles cleanly and fails
   the pinning test with a diff no one can see at a glance. Order: backslash, then double-quote, then
   newline.

   **The C# target needs LINE-BOUNDARY logic that a whole-string replace cannot produce, and the spec
   must say so rather than leaving it to be discovered.** Measured against the current artifact: the
   first segment carries no `+` (`DriverCheatsheet.cs:31`), every middle segment is `+ "...\n"`
   (`:32-36`), and the LAST segment has **no trailing `\n` and ends with `;`** (`:37`). So the generator
   splits on LF and treats first and last specially; a single `.Replace()` over the whole text produces
   either a dangling `+` or a trailing `\n` the file side does not have. The Rust target has the opposite
   shape - one line, no splitting - which is why "escaping is mechanical" is true per-target and
   misleading if read as one shared routine.
4. **The generator is itself covered by a test** - it is new code in the trust path of a pinned artifact,
   and an unproven generator is a worse failure mode than the manual mirroring it replaces.
5. **The generator writes ONE LF-joined string, and must NOT emit a line ARRAY.** The escaped content
   being LF is not sufficient - the container file's own line endings matter, because the hook compares
   its output against an LF index blob. Measured on this machine with pwsh 7:

   | how the file is written | result |
   |---|---|
   | `Set-Content -Value <single string containing LF>` | **LF preserved**, 0 CRLF |
   | `Out-File <single string containing LF>` | **LF preserved**, 0 CRLF |
   | `[System.IO.File]::WriteAllText(<single string>)` | **LF preserved**, 0 CRLF |
   | `Set-Content -Value @("line1","line2","line3")` | **3 CRLF** - the array form joins with the PLATFORM newline |

   So the hazard is specifically the ARRAY form, not pwsh in general: build the whole artifact as one
   string joined with `"`n"` and write it once. A generated file that is CRLF would mismatch the LF index
   blob on every commit - the same class as Case 3's byte comparison, in the output path instead of the
   input path. **A test asserting the generated temp file contains no `\r` is the pin.**

**REQUIRED companion change - `agy-curate/SKILL.md`.** Generation makes an existing instruction wrong,
and shipping one without the other is an incomplete fold:

| line | says today | after 14e |
|---|---|---|
| `SKILL.md:124` | "If you change `driver-cheatsheet.core.md` you **MUST also update**" both pins | wrong - the generator produces them; hand-editing them is now the error the hook catches |
| `SKILL.md:122-123` | "THREE files are pinned byte-identical ... editing `core.md` alone RED-GATES both binaries" | must instead say: **whoever edits `core.md`** runs the generator and **stages all three together** - the hook compares what is STAGED |
| `SKILL.md:339` | documents core.md "and its two byte-identical pins may have been edited" as expected uncommitted state | still true, but the pins are now generated output rather than hand-edits |
| `SKILL.md:112` | "keep it in sync there" | unchanged - `core.md` remains the canonical text, and is now the ONLY hand-edited one |

**Do not widen this into the ownership question - and mind the grammar, because it is easy to widen it by
accident.** Whether the curator may edit `core.md` AT ALL is tracked separately as ROADMAP section 14f and
needs an owner ruling. This change is narrower and decision-free: *given* that someone edits `core.md`,
they must run the generator instead of hand-editing two literals. That holds under either resolution.

**The replacement text must therefore be written in the third person - "whoever edits `core.md` must ..."
- not the second person addressed to the curator.** `SKILL.md` is the CURATOR's document, so wording like
"edit `core.md`, then run the generator" tells the curator it may edit that file, which is precisely what
14f leaves open. That is the same defect this spec already fixed once in the paragraph above, recurring
one layer down in the document it edits. The mechanical instruction is what changes; **who is entitled to
trigger it is not this batch's to say.**

**Known cost.** This is the largest blast radius in the batch: it touches both products' builds, and now
one shipped skill document. `agy-curate/SKILL.md` is a SINGLE copy (measured - not a byte-identical pair),
so this does not incur the mirror cost.

### 4.4 Item 14a - `.clavity` joins `PrunedSegments`

Add `.clavity` to the array at `scripts/check-injected-context.ps1:91-92`, alongside `.worktrees`.

**Tests.** A `.clavity/...` path is pruned, and a control path that must NOT be pruned still is not.
**The control must be LEXICALLY ADJACENT, not arbitrary** - a control like `src/foo.md` proves nothing
about the new entry, because it would pass before the change too. Use a near-miss that only an exact
segment match rejects, e.g. `.clavity-tmp/foo.md` or `x.clavity/foo.md`: `PruneRx` is built as
`(?:^|/)<segment>/`, so a prefix or suffix variant must NOT prune. Pruning is relative to the repository
root, never absolute - the existing comment at `:55-58` records why, and the test must not regress it.

> **NOT a defect - checked, and recorded so a later round does not re-derive it.** A reviewer argued the
> near-miss controls are gameable because an unescaped `.` in `.clavity` would act as a wildcard, letting
> a broken regex pass `x.clavity/foo.md` while wrongly pruning `xclavity/foo.md`. **That state is
> unreachable: the escaping is applied by the regex BUILDER, not per entry.**
> `scripts/check-injected-context.ps1:99` reads
> `$script:PruneRx = '(?:^|/)(?:' + (($script:PrunedSegments | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/'`,
> so every segment added to the array is escaped by construction and there is nowhere to add one
> unescaped. The two named controls are sound as written.

### 4.5 Item 14b - register the orphan suite

Add `clavity-install.Tests.ps1` to the explicit registration list in the root `justfile`. Registration is
an explicit list, not a glob, enforced by `test-suite-registration.Tests.ps1`.

**That covers the LOCAL gates and NOT CI, and the difference has to be stated because this item's whole
purpose is "it never runs in any gate".** Measured 2026-08-14: CI does not use the fast/slow partitions
at all - `.github/workflows/ci-scripts.yml:155` runs `Invoke-Pester scripts/tests` over the whole
DIRECTORY in one invocation - and **no workflow anywhere references `clavity-install.Tests.ps1`** (grep
across `.github/workflows/` returns nothing). The suite lives at `clavity-dotnet/install/`, outside that
glob. So adding it to the `justfile` makes it run in the inner loop and leaves it **invisible to CI**.

**A registered-but-CI-invisible suite is the same fail-open shape this section already refuses for a
registered-but-skipped one.** Settled 2026-08-14 by a two-round negotiation plus a measurement, and
**owner-accepted including the CI-config widening**: 14b is THREE parts, and shipping any subset leaves
the item's own premise true.

**Part 1 - the `paths:` filter, and this is not optional; it is the repository's own written rule.**
`.github/workflows/ci-scripts.yml:21-25` states it once, for exactly this situation: "EVERY FILE THE
SCRIPTS SUITE READS AND ASSERTS AGAINST MUST APPEAR BELOW. A suite can only gate what CI actually runs it
on, so a file the suite asserts against but the filter omits produces the worst outcome available - the
assertion reds on a developer's machine and the same edit merges with a green check, because no job ever
ran." `clavity-dotnet/install/**` is absent from both the `push` and the `pull_request` lists (`:44-58`).
**Add it to BOTH.** `:32` records this precise omission happening once already - "MISSED when the first
was added, in the very commit that added the row reading it" - so it is a known repeat, not a
hypothetical.

**Part 2 - the engine, and it is MEASURED rather than argued.** `:3` states the split is "by where the
code actually RUNS, not by folder taste", and `:5-9` puts the installer on "an END-USER Windows box,
where only Windows PowerShell 5.1 is guaranteed" - which is an argument for the 5.1 job. Against that,
the suite had only ever been run under pwsh 7. **So it was run under both.** Measured 2026-08-14:

| engine | result |
|---|---|
| pwsh 7 | Passed 12, Failed 0, 4.77s |
| Windows PowerShell 5.1 (`5.1.26100.9168`) | **Passed 12, Failed 0, 6.49s** |

It holds under either engine, so `:15`'s existing precedent applies exactly - "register-plugin.Tests.ps1
runs in BOTH jobs on purpose: it must hold under either engine." **Run it in both.** No disclaimer about
5.1 coverage is needed or wanted: the coverage is real and measured, and pinning it to pwsh 7 alone would
have left a blindspot on the exact runtime the installer targets.

**"Run it in both" is NOT symmetrical, and reading it as symmetrical silently skips one of the two.** The
two jobs invoke Pester differently: `installer-5-1` names a specific FILE (`:93`,
`Invoke-Pester scripts/tests/register-plugin.Tests.ps1`), so adding the suite there is another named
invocation. **`dev-scripts` SWEEPS A DIRECTORY** (`:155`, `Invoke-Pester scripts/tests`), and the orphan
suite lives in `clavity-dotnet/install/`, which that sweep will never reach. **So the pwsh 7 half needs a
NEW explicit step; it is not covered by the existing sweep, and assuming it is produces a green job that
ran nothing.** That assumption is the same shape as the defect 14b exists to fix, one level up.

**Part 3 - the `justfile` registration**, as described above.

**The registration guard cannot see it either, and that is by design - do not widen it.**
`test-suite-registration.Tests.ps1:52` matches only `scripts/tests/<name>.Tests.ps1`, so an entry naming a
path outside that directory is invisible to every row in that file: it is neither certified nor rejected.
The file's own header at `:3-6` says the scope is deliberate and that "widening the scope is a decision
about other products' suites, not a fold". **So the plan adds a narrow pin instead of widening it** - a
row asserting that the recipes name `clavity-dotnet/install/clavity-install.Tests.ps1` AND that the file
exists on disk. Without the first half the pin passes when the entry is deleted; without the second it
passes when the file is renamed.

**No contingency is needed.** The suite was run: **Passed 12, Failed 0** in 4.77s. It is a pure unit
suite - it mocks, dot-sources the installer so `main` never runs, and makes no mutating calls. It is
registered as-is. **A registered-but-skipped suite is not an acceptable outcome**: a guard that fails open
certifies what it stopped checking.

**Placement, and the partition's runtime must be MEASURED after adding - not assumed.** The suite takes
**4.77s** (measured). `test-scripts-fast` is already **cap-adjacent** against the 600s ceiling, and two
Pester suites must never run concurrently (file-lock false red). So "pick a partition" is not the whole
task: the plan states which partition, why, **and the measured wall-clock of that partition WITH the suite
added.** Registering a suite that pushes its partition over the cap converts a coverage gain into an
aborted run - and an aborted run has no `Tests Passed:` line at all, which is not a pass, so the failure
would present as a mystery rather than as this change.

**It goes in the SLOW partition, and the reasoning is on the record rather than left to the plan.** The
fast half is the agent inner-loop recipe and `scripts/tests/_partition.md` measures it at **429,46s solo
and 665,4s under contention against a 600s foreground cap**, with its own instruction to "treat the fast
half as cap-adjacent, not cap-safe". The suite costs 4,77s under pwsh 7 and 6,49s under 5.1 - small, but
spent on every inner-loop run to gate an INSTALLER, which is not code the agent loop edits. The slow half
is already backgrounded and well past the foreground cap, so it absorbs this at no cost to the loop.
**The plan still measures the slow partition's wall-clock WITH the suite added** - backgrounded, blocking
on its `Tests completed` line, never on a process count - because a partition figure that is asserted
rather than measured is exactly what this paragraph exists to forbid.

> **NOT a defect - checked, and recorded so a later round does not re-derive it.** A reviewer read the
> "two Pester suites must never run concurrently" constraint as meaning the fast and slow partitions run
> in parallel in CI, so that moving a suite between them would still collide. **They are not run in
> parallel; they are not run in CI at all.** `.github/workflows/ci-scripts.yml:155` invokes
> `Invoke-Pester scripts/tests` as a single sequential run over the directory. The partitions exist for
> the local agent loop and the 600s foreground tool cap, which is a constraint on the DRIVER, not on CI.
> The concurrency rule is about not starting two Pester processes on one machine by hand.

### 4.6 Item 13a - replace the false promise

**Current behaviour.** The gate prints, at `scripts/check-injected-context.ps1:932`:

> `an exemption whose file stops failing its invariant is reported as unused and must be deleted.`

The gate has no unused-exemption reporting at all - `unused` occurs exactly once in the script, in that
message.

**Required behaviour - REPLACE, do not delete.** Deleting removes true information along with the false
claim: an operator still needs to know a stale exemption is caught. It IS caught, by
`scripts/tests/check-injected-context.Tests.ps1:666`:

> `It 'every exemption is still NEEDED - the file must fail the invariant without it'`

**The replacement must say the test suite FAILS, not that it "reports".** It fails a test; it does not
emit a report. Saying "reports" substitutes one loose promise for another.

**Proposed wording** (the plan may improve it; it may not weaken the distinction):

> `an exemption whose file stops failing its invariant is no longer needed. This gate does not detect`
> `that - the test suite does, by failing 'every exemption is still NEEDED'.`

Two properties are required of whatever wording lands: it states that THIS gate does not detect the
condition, and it names where the detection actually lives. A sentence that only deletes the false claim
satisfies neither.

**Tests - and the obvious test is VACUOUS, measured.** The message lives inside the violations block:
`scripts/check-injected-context.ps1:920-934` opens with `"$($v.Count) violation(s)"` and closes with
`exit 1`. **It is printed ONLY when there is at least one violation.** So a test that runs the gate over a
clean tree and asserts "the output does not contain the false claim" passes against ANY implementation -
the string never appears on that path, whether or not it was ever fixed.

The test must therefore:

| step | requirement |
|---|---|
| setup | construct a state that PRODUCES a violation (the block is unreachable otherwise) |
| assert | the printed guidance does NOT contain the old claim |
| assert | it DOES name the test suite as the enforcement point |
| assert | exit code is still **1** - the block ends in `exit 1` and this item changes text, not behaviour |
| mutation | revert the message to its old wording; the first assertion must turn RED |

**No behaviour change** - the reporting feature is explicitly not built (owner-scoped 2026-08-14).

**Known residual, and it is inherent to declining the feature rather than a flaw in the wording.** The
replacement sentence lives inside the violations block, which prints only when there is at least one
violation. **A stale exemption produces ZERO violations** - that is precisely what "the file stopped
failing its invariant" means - so the guidance about stale exemptions is never shown at the moment a
stale exemption exists. It appears only alongside some unrelated failure. This item **corrects a false
claim; it does not make the guidance reachable at the time of the fault**, and it cannot, because
reaching it would require the unused-exemption detection that 13a explicitly declines to build. Stated
here so the residual is a recorded decision rather than something a later reader discovers and mistakes
for an oversight.

### 4.7 Item 13c - name which input is missing

**Current behaviour.** `Get-RawBytes` (`scripts/check-growth-budget.ps1:26`) returns 0 for a missing path,
silently, so "the GROWTH proposal is absent" and "the GROWTH proposal is empty" print identically. Absence
is a LEGITIMATE state - a docs-only drain has nothing to publish - so this is a reporting defect, not a
fail-open.

**Required behaviour.** Distinguish the two in the message, and **for GROWTH still exit 0** - absence is
legitimate there.

> **REFUTED 2026-08-14, and the refuted sentence was mine.** This section previously read: "Turning this
> into a hard failure would break the drain", citing the script's header at `:7`
> (`drain-knowledge.ps1 runs this WARN-only (breach does not abort the drain)`). **That is not what
> WARN-only means here.** Measured at source: `scripts/drain-knowledge.ps1:144-147` invokes the gate,
> tests `if ($LASTEXITCODE -ne 0)`, prints a warning, and **continues**. The drain is ALREADY built to
> absorb a non-zero exit from this script - that is exactly what makes it warn-only - so a non-zero exit
> cannot break it. A grep confirms `drain-knowledge.ps1:144` is the only production caller; no CI
> workflow invokes the script. **The constraint I built this item's disposition on did not exist.**

**`Get-RawBytes` has TWO call sites, and the second one is NOT the same case.** Measured:
`scripts/check-growth-budget.ps1:30-31` calls it for the SEED (`seed/golden-header.md`) as well as for
the GROWTH proposal. For GROWTH, absence is legitimate - a docs-only drain has nothing to publish, which
is why this item is a reporting defect and not a fail-open. **For SEED it is not legitimate at all.** A
missing seed silently measures 0, `$combined` becomes 0, `:39` compares `0 -gt 16384`, and `:44` prints
`check-growth-budget: OK - SEED (0B) + GROWTH (0B) = 0B <= 16384B` and exits 0. **The gate reports a
clean pass having measured nothing** - which IS the fail-open shape, sitting on the call site nobody
looked at because the anomaly was captured against the other one.

**Why the seed case is worse than a bad message, and it is not merely cosmetic.** With the seed measured
at 0, the budget arithmetic certifies a GROWTH proposal of up to the FULL cap (`0 + 16384 <= 16384`
passes at `:39`). The binary then combines the REAL seed with that proposal, overflows, and silently
drops GROWTH - which is the exact failure this gate exists to prevent. **The gate does not merely report
badly; it validates a falsified equation and returns green.**

**So this item covers both call sites, and they get DIFFERENT dispositions:**

| call site | absence is | disposition |
|---|---|---|
| GROWTH (`:31`) | legitimate - a docs-only drain has nothing to publish | distinct message, **exit 0** |
| SEED (`:30`) | never legitimate while a budget check is meaningful | distinct message, **exit NON-ZERO** |

**The MECHANISM is named here, because "emit distinct messages" is not implementable against the current
signature.** `Get-RawBytes` returns `0` for a missing path (`:26`) and also `0` for a present-but-empty
one, so a caller handed `0` cannot tell them apart - the spec would be asking for a distinction the
function has already destroyed. **The call sites test `Test-Path` themselves before calling
`Get-RawBytes`, and `Get-RawBytes` is left alone.** Changing it to return `-1` or `$null` for a missing
path would push a sentinel into the arithmetic at `:36-37`, where `$seedBytes -gt 0` and the addition
both silently accept it; changing it to throw would turn a WARN-only gate into a crashing one. Testing
presence at the call site costs one `Test-Path` per path and touches nothing else.

**Part two, and without it part one produces a confidently wrong diagnosis:** `drain-knowledge.ps1:146`
prints a single hardcoded warning for ANY non-zero from this gate - *"SEED + GROWTH exceeds the 16 KiB
combined cap; GROWTH would not be injected. Trim docs/agy-golden-header.growth.md and re-drain."* For a
missing seed the cap has NOT been exceeded, and trimming the proposal does nothing to restore the seed.
**The caller must stop asserting a cause it has not established** - either by distinguishing the two, or
by deferring to the gate's own message rather than substituting its own.

**Named residual 1, from the negotiation:** on a sparse checkout that excludes `seed/`, the operator now
sees a non-zero on every drain and may normalise it, dulling the signal for a genuine overflow. Two
DISTINCT messages are what keep that signal alive - a missing seed and an overflow must never print the
same line, which is precisely what part two fixes.

**Named residual 2, and it is the reason part two carries the whole weight.** Making the gate exit
non-zero does NOT stop the drain, and this item deliberately does not change that. Measured:
`drain-knowledge.ps1:145-147` warns and continues, then `:169` prints a GREEN
`drain-knowledge: done (run <id>)...` banner and `:175` exits **0**. So on a missing seed the operator
still ends with a green banner over a GROWTH proposal whose budget was never validly checked. **The
warning is the only signal there is**, which is exactly why it must name the real cause rather than
inherit the overflow text. **Making the drain ABORT on a missing seed is a larger behaviour change than
13c is scoped for** - 13c was scoped as a reporting fix - so it is recorded here as tracked debt rather
than absorbed. If the owner wants the drain to stop, that is a separate item with its own blast radius.

**Tests.** Distinct messages for missing vs present-but-empty at BOTH call sites, and **the exit codes now
DIFFER by call site, so a row asserting "0 everywhere" would contradict the table above**:

| state | message | exit |
|---|---|---|
| GROWTH missing | names it as absent, not empty | 0 |
| GROWTH present but empty | names it as empty, not absent | 0 |
| SEED missing | names the missing seed, never an overflow | non-zero |
| SEED present but empty | names it as empty | non-zero |
| both present, over cap | the existing overflow message | non-zero (unchanged) |
| both present, under cap | the existing OK line | 0 (unchanged) |

Plus two mutation controls, **and they belong to DIFFERENT suites** - an earlier wording put both on the
gate's tests, where the second cannot possibly fire:
- **On the gate's suite:** collapse the missing and empty branches back into one, and at least one row
  above must turn RED.
- **On the CALLER's suite** (`scripts/tests/drain-knowledge.Tests.ps1` - **it already exists**: 6.8 KB,
  registered once in the slow partition, `_partition.md` records 40,5s / 7 tests. A reviewer objected
  that this control demanded building an integration harness from scratch; measured, the home for it is
  already there): a test that runs the drain with the seed absent and
  asserts the operator-visible text names a missing seed rather than an overflow. Restoring
  `drain-knowledge.ps1:146`'s single hardcoded warning must turn THAT row red. **A mutation in the
  caller can never redden a unit test of the gate** - the two are separate scripts with separate
  suites - so demanding it of the gate's table is an instruction no implementer can satisfy without
  inventing an integration harness the spec never asked for.

---

## 5. Ordering and commit unit

**Two forced dependencies, not one.**

1. **14d before 14c.** 14c wires hooks to the helper 14d builds. ROADMAP `:991` states it directly - fix
   14d first, or 14c's hooks inherit the weak idiom.
2. **14a FIRST, before everything.** An earlier draft listed it last as "independent, small". It is
   neither: `.clavity` is absent from `PrunedSegments`, so the injected-context gate walks that directory
   today - which is the whole reason 14a exists - and **this batch actively creates content there**
   (consult seams, discipline markers, the anomalies file). Global rule 6 requires running that gate over
   every governed artifact in global rule 6's table - which the 14c amendment grew substantially.
   Landing 14a last means every gate run during the batch is taken
   over a tree the gate is mis-scanning. It is one array entry; doing it first removes a class of
   spurious failures from the rest of the work.

Revised order:

1. **14a** (one array entry; unblocks clean gate runs for everything after it)
2. 14d (helper + its Stage A/B tests, mirrored across the pair)
3. 14c (the new `agy-mark.sh` executable, the hook wiring, the THREE skill rewrites - `agy-first`,
   `agy-capstone`, `agy-test-audit`; `open-issues` is item 14d and is NOT rewritten here - and the
   ROADMAP section 14c rewrite; set fixed at Step 0, enumerated in 4.2)
4. 14e (generator + build task + hook assertion + the `SKILL.md` companion change)
5. 14b, 13a, 13c (independent, small)

**Revert order is the inverse, and it is NOT free - state it before it is needed.**

- **14d cannot be reverted while 14c stands.** 14c's hook sources the helper and `agy-mark.sh` calls it;
  removing the helper leaves both sourcing a function that no longer exists. Revert 14c first, or revert
  both together.
- **14c is now FOUR things that revert together**, and reverting a subset is worse than reverting none:
  `agy-mark.sh`, the hook wiring, the THREE skill rewrites, and the ROADMAP section 14c rewrite.
  Reverting the script while the skills still invoke it leaves three shipped skills naming an executable
  that does not exist - a hard failure on a path that previously worked. Reverting the skills while the
  script stands is harmless but pointless. **Revert all four parts or none.**
- **14e's two halves revert together.** The generator and the `agy-curate/SKILL.md` companion change are
  one unit: reverting the generator while the skill still says "run the generator" recreates the
  incomplete fold this batch exists to avoid, pointed the other way.
- 14a and 13a are independently revertible.
- **14b is independently revertible but is THREE files** - the root `justfile`, `.github/workflows/ci-scripts.yml`
  (both the job steps and both `paths:` lists), and the narrow registration pin. Reverting the workflow
  while the pin stands leaves a test asserting a CI wiring that no longer exists.
- **13c is independently revertible but is TWO files** - `scripts/check-growth-budget.ps1` and
  `scripts/drain-knowledge.ps1`. Reverting the gate while the caller's warning stays split is harmless;
  reverting the CALLER while the gate distinguishes a missing seed restores the confidently-wrong
  "exceeds the cap" advice for a state that is not an overflow.

**Commit unit.** The batch forms ONE review boundary, per the section 8 ruling. Individual commits within
it are fine; the AGY-CAPSTONE runs over the batch as a range, immediately on completion, at low context.

---

## 6. Risks

| risk | mitigation |
|---|---|
| Shield helper is new SHIPPED surface in both plugins | byte-identical mirror + `plugin-hooks-payload.Tests.ps1` + `check-seed-artifacts-synced.sh` |
| Generator touches both products' builds - largest blast radius | generator-control pattern; both existing pinning tests stay green as the oracle |
| 14c's writer set is unknown until Step 0 | RESOLVED - Step 0 ran, stated its predicate and enumerated 5 artifacts by name (4.2). ROADMAP section 14c's "7 hooks" was wrong in kind and in count |
| 14c grew from "wire N hooks" to a new shipped executable plus three skill rewrites | accepted by owner decision 2026-08-14 after a three-round negotiation. It is a change to the shield's DELIVERY MODEL, not only to this item - see 4.2. The batch is no longer purely a debt sweep, and the capstone range grows accordingly |
| `agy-mark.sh` fails CLOSED while the 4.1 helper fails OPEN - an implementer may "harmonise" them | the two run in different places and the difference is the point: the helper runs inside a PreToolUse chain where non-zero BLOCKS an agent; the script is invoked by a skill, where a refusal only makes the discipline re-fire. **Both directions are stated in 4.2's contract table; changing either is a design change, not a tidy-up** |
| Four shipped skills gain an invocation of a path they must locate at runtime | `$CLAUDE_PLUGIN_ROOT` is measured for HOOKS only. **The plan measures it FIRST, and the outcome is bounded in 4.2: if it does not resolve, 14c's skill half is BLOCKED and returns to the owner** - the byte-identity invariant (`agy-first/SKILL.md:111-112`) forbids a per-plugin literal, and a glob is ambiguous in the both-installed migration state that line declares supported |
| The A2 restore step silently inverted a human's deliberate `!` line | FOUND at re-panel round 1 and folded into 4.1: A2 now has THREE cases and appends nothing when a negation is present with no bare `*`. Measured with a control - a blind append flipped `check-ignore` from 1 to 0 and made the B3 report unreachable |
| The largest-exposure writes (`.clavity/seams/`) were missing from the 14c enumeration | FOUND at re-panel round 1. Enumeration corrected; handled by `agy-mark.sh dir`, because a multi-kilobyte seam cannot travel through `argv` and no content-carrying mode should be invented for it |
| A skill edit is simply NOT MADE, and no gate notices | the cross-product gates compare the two products to each other, so a file left unedited in BOTH passes. Closed by an explicit per-file completion check over the six paths (three skills times two products), stated as a checklist item rather than dressed up as behavioural coverage |
| **A count in the amendment said "four skills" where three are rewritten** | FOUND at re-panel round 3. The WRITER set is five artifacts (one hook, four skills); the REWRITE set is three, because `open-issues` is item 14d and is explicitly carved out. Ten sites carried the wrong number. **Both counts are now stated with their scope attached wherever either appears** - a bare "four" was what let the error propagate |
| Nothing is pushed, so CI cannot gate any of this | run the oracles locally BY NAME; never infer a gate from a marker |
| **14b now edits `.github/workflows/ci-scripts.yml`, and that edit cannot be exercised before merge** | owner-accepted 2026-08-14. The two risks it carries were retired by measurement rather than by argument: the engine choice is settled (the suite passes 12/0 under BOTH pwsh 7 and Windows PowerShell 5.1, so `:15`'s both-jobs precedent applies), and the `paths:` entry is mandated by the workflow's own rule at `:21-25`. What remains unexercised is YAML correctness, which the plan checks by reading, not by pushing |
| **13c now changes an exit code, on a gate the drain treats as warn-only** | measured: `drain-knowledge.ps1:144-147` already tests `$LASTEXITCODE -ne 0` and continues, so the drain cannot be broken by this. The spec's previous claim that it would be was refuted at re-panel round 5 - it had survived every prior round |
| The generator bakes CRLF into the literals and reddens the pinning gate | normalise CRLF->LF before escaping; `core.md` is CRLF in the worktree TODAY (measured) |
| A sourced helper using `exit` silently kills its calling hook | contract mandates `return`; measured - a sourced `exit 0` ended the parent before its next line |
| The pre-commit generator check passes because the generator CRASHED | assert the generator's exit status BEFORE trusting any diff |
| Fixes land on a branch with an OPEN capstone | accepted deliberately - section 8 says early review at low context is the cheap direction |
| Editing an LF file can silently convert it to CRLF | **When judging BY HAND whether an edit changed a file's line endings**, read what is COMMITTED (`git show HEAD:<f>`) and never "normalise" a clean file. **This is a human diagnostic and is NOT the hook's comparison basis** - 14e's hook compares INDEX to INDEX, never HEAD, and building it against HEAD would reject the correct staged workflow (4.3, rule 1). The two uses of HEAD are unrelated: one asks "did I accidentally rewrite this file", the other asks "do the staged artifacts agree" |

---

## 7. Deferred: the `core.md` ownership contradiction

Found while checking whether `core.md` can legally serve as 14e's generator source. Two shipped artifacts
disagree about who owns it:

- `scripts/drain-lib.ps1:214` - "Driver-owned files the curator must NEVER touch (asserted byte-unchanged
  by `check-core-integrity.ps1`)", listing `driver-cheatsheet.core.md` at `:223`.
- `scripts/drain-knowledge-prompt.md:4` - "never the seed, never `driver-cheatsheet.core.md`", and `:56` -
  "any `driver-cheatsheet.core.md` edit you WANT but **may not auto-apply**".
- The `agy-curate` skill nonetheless instructs the curator to edit `core.md` and mirror it into both
  literals.

**And the gate cannot catch it.** `check-core-integrity.ps1` is invoked from exactly one place -
`scripts/drain-knowledge.ps1:126`, the in-repo `just drain-knowledge` flow. The standalone skill path,
which is the one that actually edits these files, never invokes it. Verified: drain commit `fc968fb`
modified `core.md` and no gate fired.

**TRIAGED 2026-08-14 and PROMOTED to `clavity-dotnet/ROADMAP.md` section 14f.** It was explicitly assessed
for folding into this batch and is NOT foldable: the two candidate resolutions are OPPOSITE edits to
DIFFERENT files (either the skill proposes rather than applies, or the protected list is scoped to the
in-repo flow and the standalone path invokes the gate). That needs an owner ruling, and a spec cannot
specify "do one of these".

**Deferring is safe, on a narrower ground than "the generator only reads it".** The generator does only
read `core.md`, but 14e still changes the surrounding workflow - which is why section 4.3 now carries a
REQUIRED companion change to `agy-curate/SKILL.md`. That companion change is **decision-free**: given that
someone edits `core.md`, they must run the generator instead of hand-editing two literals, and that holds
under either resolution of 14f. The batch therefore depends on the ownership question having AN answer
eventually, but not on WHICH answer.

**The protected-file gate gap is the same class as 14e** - `check-core-integrity.ps1` exists and never
fires on the path that edits protected files. It is tracked in 14f rather than fixed here because its fix
is entangled with the ownership ruling, unlike 14e's.

---

## 8. Provenance

Six of the seven dispositions were settled through an AGY-FIRST consult plus two negotiation rounds, with
every factual claim verified at source before folding. **14c's was settled TWICE**, and the second time
is the one that governs: after the plan's Step 0 measurement invalidated it, a further three-round
negotiation converged on the narrower option (wire the hook, track the skills), and **the owner overruled
that convergence in favour of the full fix** - a new shipped executable with three skill rewrites. So the
provenance of 14c is: consult, negotiation, measurement, re-negotiation, owner override. Recorded because
the reasoning matters more than the conclusions, and because "agreed with the peer" was NOT the final
input on this one:

- The peer's first recommendation on 14d (text check) was **inverted** by the four-state matrix; it
  reversed, then contributed the already-tracked state that neither of us had tested.
- Its first proposal for 14e (compare file hashes) was **killed by measurement** - three distinct hashes.
  Its second (generation) is what this spec adopts.
- Its position on 13a (delete) reversed to REPLACE once the CI enforcement was measured.
- Its suggestion for 14b (skip-with-reason) was made moot by running the suite.
- It correctly declined to guess 14c's count, and gave the reason.

**Nothing in this spec rests on an unverified peer claim.**
