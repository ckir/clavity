---
name: agy-curate
description: Periodic maintenance - drain the agy-observations inbox into the GROWTH region of the shared golden-header, dedupe against the driver-owned SEED, re-verify testable claims, and empty the inbox. Run when the inbox grows or before promoting knowledge to global.
---

# agy-curate - drain the inbox, extend the golden-header GROWTH region

Deliberate and offline. This is the optimiser of the loop. Under the **EXTEND** model it owns **only** the
GROWTH region of the shared golden-header - the driver owns the SEED (the baseline + the agy manuals), which
this skill reads as a floor but never edits.

**Inputs:**
- **The capture inbox** - exactly one path, no resolution order:

  ```
  <USERPROFILE or HOME>/.clavity/agy-observations.md
  ```

  It is user-local state, beside the golden-header files. **Do NOT resolve it relative to this file and
  do NOT consult `CLAUDE_PLUGIN_ROOT`** - this skill exists in the installed tree AND in every checkout
  and worktree, and a relative path resolves to whichever copy is running. Measured 2026-08-15, before
  the move: the repo and installed copies held 30 and 18 entries with **ZERO overlap**.

  **An inbox left behind in a plugin tree is DEAD.** Do not drain it, do not merge it. Migrating any such
  file is the installer's one-time job.

  **CLAIM THE INBOX BEFORE YOU READ IT - this is a race, not a formality.** `agy-learn` runs mid-task in
  OTHER sessions and appends to this same file, and a drain is long: read-now, rewrite-`## Pending`-later
  destroys every bullet appended in between, and that window is minutes, not milliseconds. So:

  1. **RENAME first, then read.** Move
     `<USERPROFILE or HOME>/.clavity/agy-observations.md` to
     `<USERPROFILE or HOME>/.clavity/agy-observations.processing-<unique>.md` - **`<unique>` is a per-run
     value (a pid or a guid), never a fixed name.** A fixed name races exactly when it matters: two
     overlapping drains would rename onto the same target and the second destroys the first run's
     in-flight batch. The rename is atomic within one filesystem, so a concurrent `agy-learn` simply
     finds no canonical file, creates a fresh one, and loses nothing.
  2. **Triage from the renamed file.**
  3. **Write the still-pending residue back by APPENDING to the canonical path** (creating it with the
     standard header if a concurrent capture has not already), **and only after `curate-commit` exits 0.**
     Appending, not overwriting: a capture that arrived during your drain is already in that file and a
     wholesale write would erase it.
  4. **Delete the processing file YOU renamed** - matched by that run's own `<unique>`, never a glob over
     all of them - **last**. Deleting it before a failed publish loses the entries.

  **The known hole, recorded rather than papered over:** a crash between the rename and the final delete
  strands that batch in the processing file, because each run reads only its own uniquely-named file and
  never globs. A glob would fix the strand and reintroduce the two-drain race; this is the trade, chosen
  deliberately. Recovery is manual and easy - the file is right there beside the inbox.

  **Print the resolved absolute path and its pending count before you drain anything**, and again after
  the residue is written back.
- The **runtime SEED floor**: the shared `%USERPROFILE%\.clavity\golden-header.seed.md` that the driver
  actually injects (honor a `CLAVITY_GOLDEN_HEADER` **directory** override; default `%USERPROFILE%\.clavity\`).
  Read it to dedupe - a rule already stated in SEED must NOT be repeated in GROWTH. Resolve it at the RUNTIME
  shared path, NOT a repo-relative `../../../seed/...` path: once installed this skill lives under
  `{app}\plugins\agy-autotrain\...`, where a relative hop to `seed/` does not exist. If no `golden-header.seed.md`
  is present yet (a pre-seed install), treat the dedup floor as empty.
- `../../verify/assertions.md` - the probe harness (testable claims still gate here before entering GROWTH).

Under EXTEND you do **not** read or edit the `agy-assumptions.md` / `agy-capabilities.md` manuals - they are
driver-owned static SEED (they ship in each driver's `plugin/knowledge/`), refreshed only on a driver release.

## STEP ZERO - arm the in-progress marker, before anything else

**Before reading a single inbox entry**, create the marker file `.clavity/curate-in-progress` at the
repository root. Empty content; its existence is the whole signal. Create `.clavity/` first if absent.

**Delete it in exactly one place: the Finish step, once the run has completed normally.** Nowhere else.
Not on an abort, not in an error handler, not "to tidy up" - **every path that is not a normal completion
must leave it exactly where it is.**

**Why it is armed HERE and cleared THERE, rather than written when something goes wrong.** This skill
writes cheatsheet content into three repository files well before the human approval gate, so that the
human can read `git diff` while deciding. Anything that stops the run after that leaves unreviewed,
machine-distilled content sitting in the tree. The marker is the durable, machine-readable signal that
this happened, so a repository can enforce mechanically what this skill can otherwise only advise.

**Write the marker whether or not anything is currently reading it.** A repository that installs a
companion pre-commit guard will refuse to commit those files while the marker exists; one that does not
simply keeps a truthful record that a run is outstanding. **This skill ships to repositories it knows
nothing about, so it must not claim that a commit WILL be blocked** - it can only guarantee the signal.

Two things follow, and both are the reason for the inversion:

- **A marker written on failure requires the run to survive long enough to write it.** A killed process,
  an exhausted machine, or a power cut writes nothing, and the guard would then pass silently on exactly
  the endings that most deserve blocking. Armed first, the marker is already on disk before anything can
  go wrong.
- **There is no predicate to evaluate.** The rule at the top of the terminal-exit section below is one
  this file has recorded getting WRONG in five distinct formulations. Creating a file unconditionally, as
  the first act, cannot be got wrong; deleting it on the single normal path cannot either. **Do not
  re-derive the trigger from exit codes, and do not add a condition to either half.**

## First-pass triage gate (run BEFORE deciding promote/reinforce/contradict/drop - spec section 4/section 5.C-A)

For EACH pending entry, in order:

1. **Read the two-axis tag** (`(<audience>/<nature>)`, added by `agy-learn`). If an older entry lacks it,
   assign it now: **audience** = does this shape the peer (`peer`) or how you drive it (`driver`)?
   **nature** = a peer judgment tendency (`probabilistic`) or a reproducible tool/bridge behavior
   (`deterministic`)?

2. **Route by the matrix (no entry is ever dropped - spec section 4):**
   | audience \ nature | probabilistic | deterministic |
   |---|---|---|
   | **peer** | -> golden-header GROWTH (unchanged) | -> golden-header GROWTH (a peer behavior is P's, not our code - never "fix the tool") |
   | **driver** | -> driver cheatsheet (section "Compile the core driver-cheatsheet") | -> **fix-the-tool backlog** *iff* tool-fixable, else -> driver cheatsheet rule |

3. **The determinism refusal gate is MECHANICAL, not honor-system.** To route a `driver/deterministic`
   entry to `fix-the-tool`, you MUST be able to fill BOTH blocks of the backlog schema
   (`docs/fix-the-tool-backlog/_template.md`):
   - **Steps to Reproduce** - the exact reproduction on the owning variant's bridge.
   - **Code-level Mitigation** - the specific change to the bridge/tool *execution path* that removes it.

   If you CANNOT state a concrete **Code-level Mitigation** (the only fix is a *driving move*, e.g.
   "feed the peer ground truth"), then by construction it is NOT tool-fixable -> it stays a **driver
   cheatsheet rule**, never a backlog item. Determinism is a PER-VARIANT judgment: the SAME observation
   may be `fix-the-tool` on one variant (its transport exposes the needed signal) and a carried
   `driver` cheatsheet rule on another (its transport cannot) - record which.

4. **Emit the backlog item** for each tool-fixable `driver/deterministic` entry: one file per entry at
   `docs/fix-the-tool-backlog/<slug>.md` from `_template.md` (append-only; never a single shared file -
   offline curate runs on different branches would merge-conflict). Committing the file IS the routing;
   automated ingest into a tracker is a phase-2 hardening, not required here.

Only entries that survive the gate (peer entries, and `driver/probabilistic` + non-tool-fixable
`driver/deterministic` entries) proceed to the promote/reinforce/contradict/drop decision below.

### Retirement is conservative + manual (spec section 5.C-D)

Emitting a backlog item does NOT strip the corresponding rule from the driver cheatsheet. A carried
workaround rule may be deleted only when **BOTH gates hold (spec section 5.C-B + section 5.C-D / acceptance 5):**
1. a **permanent CI regression test** for the fixed quirk is **green AND committed** in the owning product,
   on **every variant the quirk reproduced on** (the standing test is what auto-resurfaces the rule if an
   agy update re-opens the quirk - deleting the rule without it would leave the driver blind on the next
   drift); AND
2. the fix is **widely adopted among end-users** (a rule costs ~1 line, so carrying it through the adoption
   tail is cheap and safe).

There is deliberately **no maintainer-side build-time version gate** (curate runs on the maintainer's box,
which always has the newest driver, so a local check would ship a stripped cheatsheet that still bites a
not-yet-updated end-user). Do not remove a carried rule as part of triage; retirement is a separate,
deliberate, later decision - and this MVP does not retire any current entry (neither the fixes nor their
CI regression tests are built yet, so gate 1 above cannot hold for any entry).

### Compile the core driver-cheatsheet (spec section 5.C-C)

The `driver/probabilistic` entries that survived the gate are the durable driver knowledge. Distil the
variant-agnostic core (peer psychology - identical for both drivers) into a lean cheatsheet - today
about 4.7 KB. The canonical text lives at `knowledge/driver-cheatsheet.core.md`; keep it in sync there.

**Do not treat that figure as the target.** It is a description of what the file currently is, and it has
been wrong before: it read "5 bullets and 2.5 KB" while the file was 4750B, so a reader checking their
work against this sentence would have concluded the artifact was fine when it was over budget. The
ENFORCED number is the one in the script named below, and that is the only one to size against.

**The budget is whatever `scripts/check-cheatsheet-budget.ps1` declares as its `-MaxBytes` default (6144 bytes at the time of writing), and it is ENFORCED** by that script (run in CI and
by `scripts/tests/check-cheatsheet-budget.Tests.ps1` under `just test-scripts-fast`). Above that the
checker fails and you must either consolidate or raise the default deliberately, in a committed edit. The
runtime hard cap is separate and much higher - `clavity-classic/src/driver_cheatsheet.rs:12` sets
`MAX_BYTES = 16 * 1024`, and a runtime file over it degrades to the compiled-in baseline floor with a
warning on stderr (`clavity-classic/src/driver_cheatsheet.rs:28-29`). That budget exists so drift is caught long before it reaches that cliff. **Do not restate the number here when it changes - the script's default is the single source of truth, and a copy in this prose is the unenforced duplicate F1 exists to remove.**

**[!] The two compiled-in pins are GENERATED OUTPUT and must never be hand-edited.** A pinning test in
each driver asserts its compiled-in baseline equals `driver-cheatsheet.core.md` (normalized CRLF->LF,
then trimmed), and a pre-commit hook now compares what is STAGED against freshly generated output.
Whoever edits `driver-cheatsheet.core.md` runs `just gen-cheatsheet-literals` and stages **all three
files together** - the hook compares the staged content, so staging the source without its regenerated
outputs is rejected, and so is hand-editing an output.
- generated: `clavity-classic/src/driver_cheatsheet.rs` -> `BASELINE_FLOOR` (single-line `\n` literal)
- generated: `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` -> `BaselineFloor` (multi-line `+ "...\n"` concatenation)

Oracles - run BOTH before committing a drain; a drain that reds these is not done:
- `cd clavity-classic && cargo test --all --features test-fakes`
  -> expect `test driver_cheatsheet::tests::baseline_floor_matches_canonical_core_source ... ok`
- `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`
  -> expect `DriverCheatsheetTests.BaselineFloor_matches_the_canonical_core_source` passing

**Compile the cheatsheet as pure ASCII**, for the same reason GROWTH is (see "Compile GROWTH as pure
ASCII" below). The inbox you distil FROM is the one file exempted to carry non-ASCII, so strip any
U+00B7 MIDDLE DOT, em dash, or arrow when you lift text out of it - the destination is NOT exempt and
non-ASCII there red-gates the injected-context check. Escape the remaining literals mechanically (an
embedded `"` is easy to corrupt by hand); do not retype the text through a terminal, whose codepage can
mangle characters.

Write the compiled core to the shared runtime path so every driver surface reads ONE file:
`<CLAVITY_GOLDEN_HEADER or %USERPROFILE%\.clavity>\driver-cheatsheet.md`, using the SAME atomic
`.tmp`->rename the golden-header uses (a reader must never see a half-written file). Prefer the binary's
`curate-commit` path if it grows a cheatsheet subcommand; otherwise write the file directly with an atomic
rename. Do NOT lengthen it to cover per-variant transport mechanics - those belong in each variant's
driving skill appendix, not the shared core.

## For each inbox entry - decide

Entries that survive the triage gate above (peer entries, and carried `driver` cheatsheet rules) get one of
these dispositions. A `driver/deterministic` entry already routed to the fix-the-tool backlog is done - it
does not re-enter here; a carried `driver` cheatsheet rule is appended to the cheatsheet, not GROWTH.

- **promote** - into the compiled GROWTH header, subject to the **promotion rubric** below, and only if the
  rule is not already stated in the SEED floor (dedupe - see Inputs).
- **reinforce** - already carried by a prior GROWTH run: GROWTH is regenerated wholesale each run, so just keep
  the strongest phrasing when you recompile.
- **contradict** - conflicts with a SEED claim: prefer **dropping** the candidate (SEED is the driver-owned
  floor) unless you have strong, verified evidence agy's behavior actually changed for the current version; if
  sources genuinely disagree, record a `[conflict]`.
- **drop** - noise, too specific, duplicate, or already covered by SEED. (Dropping a genuinely-noise candidate
  here is a deliberate curation decision; it does not violate the triage gate's no-drop invariant, which
  guarantees every observation is *routed and considered*, not silently lost.)

## Promotion rubric (curation-fatigue guard - do not skip)

- A **Heuristic** promotes only with **>=2 independent observations across different sessions**
  (one-off impressions stay in the inbox).
- An **Anti-Pattern** has no mechanical corroboration bar, and that is deliberate. Its bar is the
  **anti-poisoning circuit-breaker** below - "REJECT a self-reported 'learning' that is unverified,
  over-general, or a one-off impression" - which applies to every candidate regardless of class, plus the
  **human-review gate** before any runtime write and the **priority placement** first in GROWTH, where it
  gets the most scrutiny rather than the least. A count is the wrong epistemics here: this is the class
  agy-learn calls the highest-value one, and the capture discipline is "capture fast", so a bar requiring
  a known driver-breaking pattern to recur before it may promote would be actively harmful. A one-off you
  are not yet sure of is **rubric-parked** in the inbox, which the Finish step already permits for "any
  entry the promotion rubric explicitly parks there".
- An **Empirical Assumption** promotes only after a **100% pass in the verify harness**:

  > [STOP] STOP: before promoting any Empirical Assumption you MUST open `../../verify/run-verification.md`,
  > physically execute its synthetic `clavity ask` probe against the live agy, and record the real
  > outcome in `../../verify/assertions.md`. Never mark a probe "pass" from memory or assumption.
  > Recording the outcome means BOTH: the evidence in the narrative cell, AND the status cell for the
  > driver the probe actually ran under (`dotnet` or `classic`). They are one edit, not two - the hook
  > reads only the status cell and never the prose, so a status left stale is invisible drift.
  > Tokens: `PASS <ver>` * `FAIL <ver>` * `PARTIAL <ver>` (some parts unrun - always nags) *
  > `ACKED <ver>` (verified, unresolvable by us, disposition recorded) * `N/A` (not applicable to that
  > driver). A probe you did not run under the OTHER driver stays `PARTIAL` there - do not guess it.

  If a probe **fails**, that is drift: keep/return the item to the inbox and fix its probe alongside.

**SCOPE OF THIS RUBRIC - read before applying it.** It gates **promotion into GROWTH** and nothing else.
An entry the triage matrix routes to the **driver cheatsheet** or the **fix-the-tool backlog** never
reaches this rubric, so a stale verify harness does NOT block it, whatever its `[assumption]` class tag
says. Class (`assumption|heuristic|anti-pattern`) and audience (`peer|driver`) are independent axes:
the rubric keys on the DESTINATION, not on the class tag. Applying the harness gate to a driver-routed
entry strands it for no reason - MEASURED: the 2026-08-01 drain held 8 entries as harness-blocked when
only the 2 `peer`-audience ones were, the other 6 being `driver`-audience with a legal move available
the whole time.

### HELD - the fourth disposition, for an entry that is neither promotable nor droppable

An Empirical Assumption whose probe CANNOT BE RUN is not promotable (the rubric forbids it) and not
droppable (it may well be true). Before this state existed the skill had no legal move for it, and the
contradiction was not theoretical: **MEASURED on 2026-08-01, a drain took 79 entries in, routed 71, and
stranded 8** because `assertions.md` was stamped against agy 1.1.1 while the live peer was 1.1.9. The
Finish step said empty the inbox; the rubric said these may not promote; nothing said what to do.

An entry may be marked **HELD** only when all three hold:
1. it is `[assumption]` class **and routed to GROWTH** (i.e. `peer` audience - see the scope note above;
   a `driver`-routed entry is never HELD, because the harness does not gate it),
2. its probe could not be executed, and the reason is recorded verbatim, and
3. the RELEASE CONDITION is named - the specific thing that would let it promote.

Write it as a normal inbox bullet with a `held=` field appended:

    - [assumption] (peer/probabilistic) <the rule>  *  `[corpus]` * <date> * held=verify-harness-stale-1.1.1-vs-1.1.9

**HELD is not a parking space.** It is a claim that a NAMED blocker exists, and it expires when that
blocker clears. A HELD entry with no release condition, or one whose condition has since cleared, is a
drain that did not finish - treat it as pending on the next run.

## Compile + commit the GROWTH region (via the binary, never a raw edit)

**Migrate a pre-split flat header first (one-time - preserves upgrading users' wisdom, spec Acceptance #4).**
If a legacy flat `%USERPROFILE%\.clavity\golden-header.md` is present **and** no `golden-header.growth.md`
exists yet, this is an upgrading user whose accumulated learned wisdom lives in that flat file. **Before
compiling, read it and FOLD its learned rules into this first GROWTH compile** - dropping anything already
stated in the SEED floor (the old baseline is now driver-owned SEED; keep only the user's learned additions).
Once this run writes `golden-header.growth.md`, the binary stops reading the legacy file (read-precedence), so
this fold is what keeps the wisdom alive - do it with **no user action required**. Leave the legacy file in
place afterwards (do not rename it - panel agy-R3-c).

Compile the dense, payload-ready GROWTH header from the verified, newly-learned inbox rules (plus any folded
legacy wisdom above) - the ones NOT already in the SEED floor:

1. **`[[!] CRITICAL ANTI-PATTERNS]` first** for any newly-learned failure modes - knowing how *not* to prompt
   agy is the most actionable context.
2. The handful of newly-learned load-bearing **Empirical Assumptions**.
3. Keep it short - GROWTH is prepended (after SEED) to *every* ask; trim anything not decision-changing.

**GROWTH must fit the REMAINING budget.** The binary injects `SEED + GROWTH` only when their **combined** size
is within the 16 KB cap; over that it degrades to SEED-only, so a GROWTH that fits the per-file cap but
overflows the combined cap is written yet **never injected**. **That degrade is NOT silent** - both drivers
warn with the same message, "combined golden-header at {dir} exceeds the {MaxBytes}B cap - dropping GROWTH,
keeping SEED" (`clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:186`,
`clavity-classic/src/golden_header.rs:237`), so if you never saw that warning your GROWTH was injected.
Compile GROWTH to fit roughly `16 KB - (current size of golden-header.seed.md)`. **Measured 2026-08-11:
seed 5190 B + growth 7984 B = 13174 of 16384 - 80% full, with 3210 bytes of headroom.** Re-measure rather
than trusting that figure; it moves with every drain.

**[STOP] Human-review gate - before any runtime write.** This skill publishes directly to the **live** runtime
header; the standalone path has no separate maintainer `accept-drain` review step (that generation-vs-publish
split exists only in the dev repo flow). So the human review the EXTEND trust model relies on happens HERE:
before publishing, PAUSE, show the user the compiled GROWTH proposal (the anti-patterns and assumptions you
are about to make law for *every* future ask), and ask for explicit approval - "Reply `approve` to publish
to your runtime header, or request changes." **Do not publish until the user approves.** These are untrusted
machine-local captures about to become a live injection into every ask; the human gate is the safeguard the
model depends on, not a formality.

**READ THIS BEFORE THE BRANCHES BELOW - it applies to all of them, and to any exit added later.** If the
run **ends in any way other than completing normally** - the approval gate was not passed, or an error
struck at any point, **including inside the Finish step** - and has left **any repository file
modified**, then: leave those files in place, delete and revert nothing, and emit on **STDERR** every
dirty path together with the statement that they carry unreviewed content and must neither be COMMITTED
nor BUILT. Do this as part of ending the run, **before** the exit itself.

- **It is a message in its own right**, not an addition to another one - an error exit has no template to
  append to.
- **LEAVE `.clavity/curate-in-progress` EXACTLY WHERE IT IS.** You created it at Step Zero; you are now on
  a path that is not a normal completion, so it stays. It is what makes the warning above enforceable
  rather than advisory wherever a repository installs a guard that reads it - such a guard refuses the
  very commit this message is asking you not to make. **Removing it here, as cleanup or courtesy,
  silently converts a mechanical guard back into a message a human can miss** - which is the whole defect
  this pair was built to close. The next run re-arms it; there is nothing to tidy.
- **It is keyed on the run NOT COMPLETING NORMALLY.** Only a run that ran to a normal end produced those
  edits deliberately; every other ending may have left them half-made and unreviewed.
- **This rule has been written wrong FIVE times. Do not restate it as any of these:**
  1. **a list of codes** - goes stale the moment a code is added;
  2. **"any exit that did not publish"** - sweeps in exit 0, which also covers "nothing pending";
  3. **"any non-zero exit"** - would fire on a future published-with-warnings code;
  4. **"did not publish GROWTH"** - fires on a perfectly good run whose inbox held only carried `driver`
     rules (`:121` routes those to the cheatsheet, not GROWTH), which edits the pins, publishes nothing
     and ends normally;
  5. **"does not reach the Finish step"** - a run can REACH Finish and fail INSIDE it (a `curate-commit`
     error), which leaves the tree dirty and unpublished while the predicate reads false.

**No message in this section is "non-blocking".** That word belongs to the repository's HOOK convention,
which the note at the end of this section explicitly disclaims for this skill; every exit described here
is terminal, so "non-blocking" states the opposite of what happens.

**No interactive approval channel?** If this skill runs where no interactive approval can be obtained (a
headless or otherwise non-interactive session), do **NOT** publish. Emit a message - "no
interactive approval channel; the compiled GROWTH was NOT published. Re-run agy-curate interactively to
publish." - on **STDERR**, and **exit 2**.

**The human did not approve?** The gate above offers two answers that are NOT the same outcome, and they
do NOT take the same path:

- **A change request** - revise the proposal and **RETURN TO THE GATE**. This is iteration, not a
  terminal state: do not exit, and do not publish until an approval is actually given. A gate that
  invites "request changes" and then treats it as an abort is not a gate, it is a trap.
- **A refusal, or no answer at all** - do **NOT** publish. Emit on **STDERR** - "the human did not
  approve; the compiled GROWTH was NOT published." - and **exit 3**. **Write that exit-3 message out in
  full**, rather than deriving it from the exit-2 wording above: a substitution across two separate
  strings silently stops applying the moment either one is reworded, and the exit-2 message ends by
  telling the reader to re-run interactively, which is nonsense for a human who just declined in an
  interactive session.

**The exit code is the state, not just a pass/fail flag.** Every outcome below gets its own code, so a
caller can tell them apart without parsing any text. **A caller needs to act differently on 2 than on
3** - one means fix the environment, the other means edit the rules - so they must never share a code.
The table is the count; do not restate how many there are in prose:

| exit | state | inbox `## Pending` |
|------|-------|--------------------|
| 0 | ran to a normal end - GROWTH published, or nothing for GROWTH to publish (an empty inbox, or one holding only carried `driver` rules) | reset |
| 2 | NOT published - no interactive approval channel. Deliberate, not a fault | left intact |
| 3 | NOT published - the human reviewed it and did not approve. Deliberate, not a fault | left intact |
| 1 | error - something went wrong | left intact **unless the error struck after the Finish step's reset** - see below |

Exit 0 here would be actively misleading: it is indistinguishable from a successful publish to anything
reading only the status code, so a pipeline that expected GROWTH to land reports SUCCESS while nothing
was written. That is the silent-success blindspot this branch exists in the first place to avoid.

**Every gate abort path - currently exit 2 and exit 3 - ENDS the run here. Do not continue to the Finish
step below.** The inbox is left
intact because nothing ever reaches the code that would reset it - not because the reset rule evaluated and
declined. Those are different mechanisms and only the first one is true on this path: the Finish step
resets `## Pending` on `curate-commit` exit 0, and on this path `curate-commit` is never invoked at all.
Read this branch as terminal.

**What this run has ALREADY done by the time it reaches here, and does NOT undo.** A gate abort is
not a rollback, so state the partial effect rather than leaving an executor to guess at it:

| already happened | reverted when the run reaches this block? | where it lives |
|---|---|---|
| the compiled cheatsheet was written to `<CLAVITY_GOLDEN_HEADER or %USERPROFILE%\.clavity>\driver-cheatsheet.md` | **no** | user profile - **live, and read by both drivers** |
| `knowledge/driver-cheatsheet.core.md` and its two GENERATED pins may have been regenerated | **no** | **IN THE REPOSITORY - these are uncommitted edits in the working tree** |
| `golden-header.growth.md` (the GROWTH publish) | **never written** | - this is exactly what the gate withheld |
| the inbox `## Pending` section | untouched, per the paragraph above | - |

**This block describes the GATE's abort paths only** - the ones that arrive here, currently exit 2 and
exit 3. An error exit (1) can happen anywhere: before any of the writes above, or after the Finish step
has already reset `## Pending`. So it has no single working-tree state to state, and it is the one code
whose inbox row in the table above is conditional rather than absolute. **The dirty-path rule at the top
of this section still covers it** - that rule fires on any ending that is not a normal completion, which
is why it can protect a case this table cannot describe.

**What to DO about all of it is the rule at the top of this section, and is deliberately not restated
here** - restating it is how the two copies drift apart.

**`driver_cheatsheet.rs` and `DriverCheatsheet.cs` are COMPILED-IN baselines (`:93-95`)** - content left
in them is built by the next `cargo build` / `dotnet build` and shipped by the next `git commit -a`.

**The cheatsheet is outside the human gate's scope.** That gate shows the compiled GROWTH proposal
(`:224`). The cheatsheet is compiled from the `driver/probabilistic` entries (`:79`), and a carried
`driver` rule is appended to it rather than to GROWTH (`:121`); neither route reaches that gate. Moving
the write below it would not subject it to review. Gap recorded at
`docs/backlog/cheatsheet-reaches-live-path-before-the-human-gate.md`.

> This is the SKILL's exit contract and is unrelated to the `exit 2` convention used by the repository's
> **hooks** (see `clavity-classic/plugin/hooks/agy-liveness-check.sh`), where 2 means "advisory on stderr"
> and is non-blocking on SessionStart but BLOCKING on some other events. Nothing here is a hook; the codes
> above do not inherit that meaning.

Publishing unreviewed GROWTH is the one outcome this gate exists to
prevent, so this path fails **CLOSED**. **The inbox is deliberately left unreset and nothing is lost:** the
Finish ordering below resets `## Pending` only when `curate-commit` exits 0, so an unpublished run leaves
every entry in place and a later interactive run simply recompiles them. Only compute is wasted, and only
once. Do NOT add an inbox reset to this path - that would turn a safe abort into data loss.

Then, once approved, **commit it through the binary** so it lands at the resolved shared GROWTH path
(`%USERPROFILE%\.clavity\golden-header.growth.md`) with an atomic write + a `.sha256` **integrity** sidecar -
NOT a security control (anyone who can rewrite the header can equally rewrite or delete the sidecar); it exists
to catch torn writes, filesystem corruption, and a hand-edited header. It is **verified on read**: absent or
unreadable is accepted unchanged (a fresh install seeds SEED with no sidecar); mismatched or over its own 1 KiB
cap causes that region to be skipped with a warning. Only the binary knows `CLAVITY_GOLDEN_HEADER`.

**Publish via the binary's STDIN as RAW BYTES - never a shell redirect or pipe.** A multi-line markdown
header blows past command-line quoting/length limits (so it must go via STDIN, not an argument); and on
Windows a bare `curate-commit < file` is unsupported for external commands, while a text pipe
(`Get-Content file | curate-commit`, `printf '%s' "$growth" | curate-commit`) re-encodes the stream through
the console OEM code page (CP437) - corrupting non-ASCII (an em dash becomes the three characters U+0393 U+00C7 U+00F6), the exact mojibake
`curate-commit`'s raw-byte transport exists to reject. Feed the file's raw UTF-8 bytes to the process's
stdin base stream instead. GROWTH is **regenerated wholesale** each run, so the publish is idempotent:

**Compile GROWTH as pure ASCII.** This is a rule about what we WRITE, not a restriction on what the
transport may carry - `curate-commit` remains a faithful byte transport and will accept legitimate
non-ASCII. It carries a tripwire for known mojibake families, which is a heuristic and not a proof, so the
authoring policy is what covers the general case. GROWTH is a compiled, machine-generated artifact with no
present need for typography, and non-ASCII in it bought nothing while costing 13 days of silently corrupt
injection into every ask.

    # Resolve the driver (dotnet `clavity-ls` or classic `clavity`) and stream RAW bytes to its stdin.
    # Both variants' `curate-commit` write ONLY golden-header.growth.md (SEED untouched) - transport is identical.
    $exe = (Get-Command clavity-ls -EA SilentlyContinue) ?? (Get-Command clavity -EA SilentlyContinue)
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $exe.Source; $psi.ArgumentList.Add('curate-commit')
    $psi.RedirectStandardInput = $true; $psi.UseShellExecute = $false
    $bytes = [System.IO.File]::ReadAllBytes('compiled-growth.md')
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $proc.StandardInput.Close(); $proc.WaitForExit()   # 0 = ok; 2 = bad input/over-cap; 1 = IO

`curate-commit` (both variants) writes **only** `golden-header.growth.md`; it never touches the SEED. Do NOT edit
the shared files by hand, and do **not rename or remove** a legacy flat `%USERPROFILE%\.clavity\golden-header.md`
if one is present - the binary reads it as a one-time migration fallback (GROWTH present -> legacy ignored), and
renaming it would defeat that migration for an upgrading user.

**No driver installed?** If no clavity binary is on PATH, still compile and write `golden-header.growth.md`
(create the `.clavity` dir if absent) and emit a **non-blocking** warning - e.g. "no clavity driver detected;
the learned header won't be injected until a driver is installed." Do NOT hard-fail; the capture still has value.

**Variant-agnostic ONLY.** GROWTH carries cross-cutting agy *reasoning* wisdom (anti-patterns, load-bearing
assumptions) - forbid BOTH project nouns AND variant-specific driving mechanics (e.g. `agy_ask` argument shaping
vs `clavity ask` flags). Those belong in the per-variant core driving skill, not the shared header.

**Anti-poisoning circuit-breaker.** You (the curator) are the gate, not a transcriber. Critically evaluate each
candidate before compiling it into a law that shapes every future ask: REJECT a self-reported "learning" that is
unverified, over-general, or a one-off impression - a wrong heuristic frozen into the header poisons every
downstream call. When in doubt, leave it in the inbox.

## Finish

- **Order the mutation, and reset the inbox LAST.** Snapshot (the `agy-inbox-snapshot` hook does this
  automatically when this skill is invoked through the `Skill` tool; do it by hand if you got here another
  way), then compile GROWTH, then publish via `curate-commit`, and **only when `curate-commit` exits 0**
  perform the `## Pending` reset described in the next bullet (which is a reset to the still-pending
  entries, NOT to zero lines). Resetting first means a failed publish loses the entries and produces no
  GROWTH to show for them. If `curate-commit` returns non-zero, STOP and leave the inbox untouched.
- **Empty the inbox** - every entry must reach a terminal disposition: promoted into GROWTH, compiled into
  the driver cheatsheet, emitted as a fix-the-tool backlog item, dropped as noise, or marked **HELD** with
  a recorded blocker and release condition. Reset `## Pending` to contain the HELD entries **and any entry
  the promotion rubric explicitly parks there** - a one-off Heuristic awaiting a second independent
  observation is the case that exists today. **Capstone round 2 found this deadlock:** a single-observation
  `[heuristic]` cannot promote (the rubric says it stays in the inbox), is not noise so cannot be dropped,
  and is not `[assumption]` class so cannot be HELD. Wording that said "only the HELD entries" left it with
  no legal move at all - the same unsatisfiable shape this section was written to remove, reintroduced one
  layer down. A rubric-parked entry is dispositioned: its disposition is "wait for corroboration".
  **"Empty" means every entry is dispositioned, not that the file has zero lines** - the earlier wording
  was unsatisfiable whenever the verify harness was stale, which is a state this skill has no power to fix
  and therefore must be able to survive.
- If the loop has proven out in-project, this is the point to **promote** the skills + knowledge to the
  global config (the trial-then-globalise step).
- **LAST OF ALL, and only if everything above completed normally: delete `.clavity/curate-in-progress`.**
  This is the ONLY place that file is ever removed. It was created as Step Zero before any work began,
  and while it exists it is what lets a repository's own guard refuse cheatsheet content this run never
  got a human to approve.
  - **Delete it after the inbox reset, not before.** A failure between the two would leave the marker
    gone and the tree still dirty, which is precisely the state the marker exists to advertise. Last
    means last.
  - **If anything above failed, leave the marker alone and stop.** Do not delete it on the way out of an
    error path, and do not delete it "because the important part succeeded". The run either finished
    normally or it did not.
  - The next run arms it again at Step Zero, so there is no state to reconcile and nothing to clean up
    later.
