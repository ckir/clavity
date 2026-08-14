# Anomaly hot-fix batch - design

**Status:** owner-approved 2026-08-14. **This is a SPEC, not a plan.** It carries intent, contracts and
measured current state. The implementation plan re-derives every line number (see "Citation drift" below)
and establishes the one count this spec deliberately leaves open.

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
| 14c | hooks write into `.clavity/` and none assert the shield |
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
| 14c | hooks writing into `.clavity/` | **NOT ESTABLISHED** - see section 4.2 |
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
5. **Read the count, not the exit code.** `dotnet test --filter` exits 0 when its filter matches nothing.
   Any gate that shells out to a filtered test run must assert the test COUNT.

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

A0. **Validate the inputs, or return 0 without writing.** The root must be an existing directory, and the
    path must resolve UNDER `<root>/.clavity/`. Both matter: the helper repairs
    `<root>/.clavity/.gitignore` and nothing else, so a path outside that directory cannot be fixed by
    repairing that shield. Restoring it and reporting success for, say, `docs/secret.md` would be a
    false GREEN for a file left fully exposed.
A1. **`mkdir -p <root>/.clavity`.** Every restoring step appends, and an append into a missing directory
    fails `No such file or directory` on a fresh clone. If the `mkdir` fails, return 0 - never hard-block.
A2. **Ensure the shield text is present** (`grep -qx '*'`; append `*` if absent). **This runs regardless
    of the state of any individual file.** It is the only step that protects the OTHER files in the
    directory, and it is why Stage B may never skip it.

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
B4. **`check-ignore` exit 128 inside a work tree**: a real git error. Stage A has already restored the
    shield text, which is the safe direction for a data-leak guard. Say so and stop.

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
| input validation | **the root must be a existing directory, or the helper returns 0 immediately without writing.** An unvalidated root is a footgun: the contract forbids re-deriving it, so an empty or wrong value is silently trusted, and `mkdir -p "$1/.clavity"` with an empty `$1` would create a directory at the filesystem root |
| effect | **inside the repository:** may create `<root>/.clavity/` and create or append to `<root>/.clavity/.gitignore`, and nothing else. **Outside it:** may write ONE debounce marker under `$TMPDIR` or `$HOME/.clavity-tmp`, exactly as the sibling hooks do. An earlier draft said "touches nothing else" while also requiring a seen-marker, which is unsatisfiable - the marker cannot live in the repository, because a marker inside `.clavity/` would be a file the shield is supposed to be protecting |
| output | a single human-readable line on stderr **only when it acted or found a fault**; silent on the healthy path, because it runs on every capture. **Subject to the debounce below** |
| return | **`return 0`, ALWAYS - never `exit`.** See the sourcing hazard below |
| tracked-file case | emits the `git rm --cached` remedy on stderr and returns 0 without writing |

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

**Temp files must not collide.** Two sessions can be open on the same repository at once - the open-issues
skill already designs for that - so any scratch path the helper or the 14e generator uses must be unique
per invocation, never a fixed name.

**Tests.** All four states above, each asserted, plus a control proving the helper leaves a correct
shield untouched. Idempotence: three consecutive runs leave exactly one line. Plus one mutation test per
branch of the decision tree - deleting any branch must turn a test RED.

**Known residual, stated rather than discovered later.** The helper protects the shield; it does not
un-track an already-tracked file. B3 reports rather than repairs, deliberately - automatic
`git rm --cached` is a destructive action a guard should not take unattended.

**Second known residual: a negation line is reported, not removed.** If the shield reads `*` followed by
`!<something>`, Stage A's text check passes (a `*` line IS present) and B3's untracked branch fires. The
helper reports it loudly and does NOT rewrite the file. Auto-deleting a line a human deliberately wrote is
the destructive-footgun class: a missing shield is trivially restorable, a destroyed intent is not. The
leak persists until a human acts, which is why the report must be loud rather than silent. **If that trade
is wrong, it is an owner call to invert** - the alternative is the helper rewriting the shield to exactly
`*`, which closes the leak automatically at the cost of overwriting user edits to a file we created.

### 4.2 Item 14c - one shared helper, and the count is a Step 0 obligation

**Required behaviour.** Every hook that writes into `.clavity/` calls the 4.1 helper. **One shared
implementation, not N copies.** Duplicating the assertion into each hook re-creates the propagation
problem 14d exists to end, and is the choice that fails if the number of such hooks grows.

**The count is deliberately NOT fixed in this spec.** ROADMAP section 14c records "7 hooks". A naive grep
for the string gives 8. Two attempts at a precise write-predicate probe failed outright (one returned 0,
one classified 8 of 8). The peer consulted on this returned "cannot determine a defensible count via
static grep" and gave the reason: hooks write indirectly through variables, e.g.
`agy-discipline-reaching.sh:96-97`:

```
out="$root/.clavity"
[ -d "$out" ] || mkdir -p "$out" 2>/dev/null || exit 0
```

**Step 0 of the plan MUST establish the set by stating its predicate and enumerating the matches by
name.** A count with no stated predicate is not a measurement. Both products' hook directories are in
scope.

**Tests.** For each hook in the established set, assert the hook ACTUALLY INVOKES the shield check with
effect - not that the helper exists, and not that the hook merely sources it. Neutering the call site must
turn a test RED.

**The test must BREAK the shield first, and the earlier wording hid that.** The helper is silent on the
healthy path by contract, so a test run against a healthy repository observes nothing and would pass while
asserting nothing - a false GREEN that looks like coverage. Each hook's test therefore: (a) sets up a repo
with a BROKEN shield, (b) runs the hook, (c) asserts the shield was restored (an observable effect), and
(d) as the mutation control, removes the hook's call to the helper and asserts the same test goes RED.
"Asserts the hook emits something" is not a testable predicate against a helper designed to stay quiet.

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
2. **It must assert the generator's own exit status FIRST.** If the generator crashes, the working tree
   is untouched, so a bare `git diff --quiet` returns 0 and the hook PASSES - committing diverged
   literals with a green check. **A generator that failed to run is not evidence of parity.** This is
   global rule 5 ("read the count, not the exit code") applied to this item: a non-zero generator exit
   fails the hook, and only after a zero exit is the comparison meaningful.

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

**Generator constraints - these are design-level, not plan-level, because they eliminate candidates:**

1. **It must run on Windows and in CI**, in both products' pipelines. **The surviving candidate is
   PowerShell (`pwsh`)** - it is already required by `lefthook.yml`, by every script in `scripts/`, and by
   the drain flow, so it adds no dependency. Python exists in this tree only for the classic bridge's
   linting and is not a build dependency of either product; Rust and C# would each run in only one of the
   two. The plan may choose otherwise only by naming what makes `pwsh` unsuitable. **A constraint list
   that eliminates candidates without naming the survivor is not actionable** - this line exists because
   an earlier draft did exactly that.

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
4. **The generator is itself covered by a test** - it is new code in the trust path of a pinned artifact,
   and an unproven generator is a worse failure mode than the manual mirroring it replaces.

**REQUIRED companion change - `agy-curate/SKILL.md`.** Generation makes an existing instruction wrong,
and shipping one without the other is an incomplete fold:

| line | says today | after 14e |
|---|---|---|
| `SKILL.md:124` | "If you change `driver-cheatsheet.core.md` you **MUST also update**" both pins | wrong - the generator produces them; hand-editing them is now the error the hook catches |
| `SKILL.md:122-123` | "THREE files are pinned byte-identical ... editing `core.md` alone RED-GATES both binaries" | must instead say: edit `core.md`, then RUN THE GENERATOR; the hook asserts the tree is clean |
| `SKILL.md:339` | documents core.md "and its two byte-identical pins may have been edited" as expected uncommitted state | still true, but the pins are now generated output rather than hand-edits |
| `SKILL.md:112` | "keep it in sync there" | unchanged - `core.md` remains the canonical text, and is now the ONLY hand-edited one |

**Do not widen this into the ownership question.** Whether the curator may edit `core.md` AT ALL is
tracked separately as ROADMAP section 14f and needs an owner ruling. This change is narrower and is
decision-free: *given* that someone edits `core.md`, they must now run the generator instead of
hand-editing two literals. That is true under either resolution of 14f.

**Known cost.** This is the largest blast radius in the batch: it touches both products' builds, and now
one shipped skill document. `agy-curate/SKILL.md` is a SINGLE copy (measured - not a byte-identical pair),
so this does not incur the mirror cost.

### 4.4 Item 14a - `.clavity` joins `PrunedSegments`

Add `.clavity` to the array at `scripts/check-injected-context.ps1:91-92`, alongside `.worktrees`.

**Tests.** A `.clavity/...` path is pruned; a control path that must NOT be pruned still is not. Pruning
is relative to the repository root, never absolute - the existing comment at `:55-58` records why, and
the test must not regress it.

### 4.5 Item 14b - register the orphan suite

Add `clavity-install.Tests.ps1` to the explicit registration list in the root `justfile`. Registration is
an explicit list, not a glob, enforced by `test-suite-registration.Tests.ps1`.

**No contingency is needed.** The suite was run: **Passed 12, Failed 0** in 4.77s. It is a pure unit
suite - it mocks, dot-sources the installer so `main` never runs, and makes no mutating calls. It is
registered as-is. **A registered-but-skipped suite is not an acceptable outcome**: a guard that fails open
certifies what it stopped checking.

**Placement.** It must join a partition that respects the suite cadence: `test-scripts-fast` is
cap-adjacent, and two Pester suites must never run concurrently (file-lock false red). The plan states
which partition and why.

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

**Tests.** Assert the gate's output does not contain the false claim, and does name the suite as the
enforcement point. **No behaviour change** - the reporting feature is explicitly not built (owner-scoped
2026-08-14).

### 4.7 Item 13c - name which input is missing

**Current behaviour.** `Get-RawBytes` (`scripts/check-growth-budget.ps1:26`) returns 0 for a missing path,
silently, so "the GROWTH proposal is absent" and "the GROWTH proposal is empty" print identically. Absence
is a LEGITIMATE state - a docs-only drain has nothing to publish - so this is a reporting defect, not a
fail-open.

**Required behaviour.** Distinguish the two in the message. **Still exit 0.** The script's own header at
`:7` states: `drain-knowledge.ps1 runs this WARN-only (breach does not abort the drain)`. Turning this
into a hard failure would break the drain.

**Tests.** Distinct messages for missing vs present-but-empty; exit code 0 in both.

---

## 5. Ordering and commit unit

**One forced dependency: 14d before 14c.** 14c wires hooks to the helper 14d builds. ROADMAP `:991`
states it directly - fix 14d first, or 14c's hooks inherit the weak idiom.

Everything else is independent. Suggested order, cheapest-risk last:

1. 14d (helper + its four-state tests, mirrored across the pair)
2. 14c (wire the established hook set; count fixed at Step 0)
3. 14e (generator + build task + hook assertion)
4. 14a, 14b, 13a, 13c (independent, small)

**Commit unit.** The batch forms ONE review boundary, per the section 8 ruling. Individual commits within
it are fine; the AGY-CAPSTONE runs over the batch as a range, immediately on completion, at low context.

---

## 6. Risks

| risk | mitigation |
|---|---|
| Shield helper is new SHIPPED surface in both plugins | byte-identical mirror + `plugin-hooks-payload.Tests.ps1` + `check-seed-artifacts-synced.sh` |
| Generator touches both products' builds - largest blast radius | generator-control pattern; both existing pinning tests stay green as the oracle |
| 14c's hook set is unknown until Step 0 | Step 0 must state its predicate and enumerate by name; a bare count is rejected |
| Nothing is pushed, so CI cannot gate any of this | run the oracles locally BY NAME; never infer a gate from a marker |
| The generator bakes CRLF into the literals and reddens the pinning gate | normalise CRLF->LF before escaping; `core.md` is CRLF in the worktree TODAY (measured) |
| A sourced helper using `exit` silently kills its calling hook | contract mandates `return`; measured - a sourced `exit 0` ended the parent before its next line |
| The pre-commit generator check passes because the generator CRASHED | assert the generator's exit status BEFORE trusting any diff |
| Fixes land on a branch with an OPEN capstone | accepted deliberately - section 8 says early review at low context is the cheap direction |
| Editing an LF file can silently convert it to CRLF | judge by what is COMMITTED (`git show HEAD:<f>`), never "normalise" a clean file |

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

The seven dispositions were settled through an AGY-FIRST consult plus two negotiation rounds, with every
factual claim verified at source before folding. Recorded because the reasoning matters more than the
conclusions:

- The peer's first recommendation on 14d (text check) was **inverted** by the four-state matrix; it
  reversed, then contributed the already-tracked state that neither of us had tested.
- Its first proposal for 14e (compare file hashes) was **killed by measurement** - three distinct hashes.
  Its second (generation) is what this spec adopts.
- Its position on 13a (delete) reversed to REPLACE once the CI enforcement was measured.
- Its suggestion for 14b (skip-with-reason) was made moot by running the suite.
- It correctly declined to guess 14c's count, and gave the reason.

**Nothing in this spec rests on an unverified peer claim.**
