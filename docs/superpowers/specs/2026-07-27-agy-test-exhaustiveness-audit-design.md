# AGY-TEST-EXHAUSTIVENESS-AUDIT — design

**Status:** design (spec). Line-level implementation plan waits on this spec's approval; the concrete
template already exists (`adversarial-panel-review`), so a plan is writable against it.

**One-line:** A standing, named agy discipline that — after AGY-CAPSTONE is GREEN — convenes the live agy
peer to audit the **test suites** for coverage exhaustiveness (untested reachable behaviors, vacuous/weak
assertions, missing edge cases), verifies each claimed gap by measurement, and surfaces the verified gaps
for the owner to scope — tracking any deferred debt in a single rolling committed file.

---

## 1. Purpose & the gap it fills

The existing family gates four different things:

| Discipline | Gates | Home |
|---|---|---|
| AGY-FIRST | a **decision** / design-fork | global `CLAUDE.md` (always-on backstop) |
| AGY-AFTER | an **artifact** (a just-written spec/plan) | clavity plugin: `adversarial-panel-review` skill + `agy-after-reminder.sh` hook |
| AGY-CAPSTONE | a **finished implementation** (reachable defects in shipped code) | global `CLAUDE.md` backstop; execution skills nudge it |
| AGY-LEARN | **knowledge** about the peer | agy-autotrain plugin (`agy-learn`/`agy-curate` + knowledge files) |

None of them gates **whether the tests would catch a future regression**. AGY-CAPSTONE hunts defects *in
the code*; it does not evaluate whether the *test safety-net* is complete. This is a real, separate move:
in the run that motivated this spec, a full capstone went GREEN over the committed code and did **not**
surface the coverage gaps — a behaviour that had been fixed repeatedly had **no test that would fail if it
regressed**, and an existing test was **vacuous** (it asserted a status string via a server-side throw,
bypassing the real client-side plumbing it was named to guard). Those gaps only came to light when the
owner explicitly asked for a test audit.

**AGY-TEST-EXHAUSTIVENESS-AUDIT** (short: **AGY-TEST-AUDIT**) fills that gap: gate the test suite's
coverage, distinct from and after the capstone's defect hunt.

## 2. Why distinct from AGY-CAPSTONE (not a sub-step)

Consulted agy first (AGY-FIRST). Both agy and the driver converge on **a distinct named discipline run
strictly after AGY-CAPSTONE is GREEN**, not a capstone sub-step:

- **For separate (decisive): attention-splitting.** Hunting logic defects and evaluating safety-net
  coverage require different adversarial mindsets. Folded into one step, the model over-indexes on finding
  code bugs and gives the tests a cursory checkbox glance. A separate discipline forces a dedicated context
  window whose entire focus is hunting test gaps and vacuous assertions. Our own capstone run confirmed
  this: it was defect-focused and missed the coverage gaps.
- **Against separate (accepted cost): context duplication.** Both disciplines read the same source, diff,
  and specs, so a separate step roughly doubles the read cost and adds another branch-finish hurdle. We
  accept this: a fresh agy cascade for the audit is cheap relative to shipping an untested safety-net, and
  the different lens is the whole point.

## 3. Placement (home)

**The clavity plugin, co-located with `adversarial-panel-review`** — its closest sibling (both "convene
agy to adversarially review an artifact"). Concretely:

- **Skill:** `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md`, **mirrored** to
  `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` (the two driver plugins mirror shared skills; the
  existing `check-seed-artifacts-synced.sh` seed-sync guard must cover the new shared artifact).
- **Hook:** `clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh` (mirrored), registered in the plugin
  `hooks.json`, that **nudges** the discipline on the branch-finish step (see §4). It follows the existing
  hook conventions: jq/bash-runtime guard, stderr + exit-2 advisory emission, silent when not applicable,
  suppressible under the project's `.no-agy` opt-out.
- **`CLAUDE.md`:** a **one-line pointer** in the agy-discipline enumeration noting AGY-TEST-AUDIT ships with
  the plugin (mirroring how the AGY-AFTER note points out of `CLAUDE.md`) — **no rule body** in `CLAUDE.md`.
  This keeps the discrete, heavy, lifecycle-boundary transaction out of always-on ambient config (which
  would add token noise and risk premature mid-implementation firing), while still leaving a backstop
  breadcrumb.

Rationale for not placing it as a `CLAUDE.md` rule (like AGY-CAPSTONE): the capstone is a backstop that
must bind even when a plan is executed without a nudging skill; the test-audit is a bounded pre-merge
review whose value is concentrated at one lifecycle point, so the AGY-AFTER packaging (skill + hook, in the
plugin) fits better — it installs/updates/uninstalls cleanly and is disableable per project.

## 4. Trigger (when it fires)

- **Hook nudge at branch-finish**, intended to run **after AGY-CAPSTONE reports GREEN**. Two important
  bounds (panel S1/S2/B4):
  - **The ordering is driver-enforced, not hook-enforceable.** A hook cannot know the capstone is GREEN; it
    only nudges when the branch-finish skill is invoked. So the hook *reminds*, and the driver is
    responsible for having run the capstone first — exactly as AGY-CAPSTONE itself is a nudged-but-rule-
    backstopped discipline. The `CLAUDE.md` pointer (not a rule body) is the backstop for branches finished
    without the skill.
  - **The trigger is scoped to branch-FINISH only, and gated on the diff.** It must NOT copy the capstone
    hook's broad execution-skill matcher (`subagent-driven-development` / `executing-plans` /
    `finishing-a-development-branch`), or it fires mid-implementation, contradicting §2. And even at
    branch-finish it must **inspect the branch diff and exit silently when no executable code or test files
    changed** — a docs/config/spec-only branch (like the branch that wrote *this* spec) must not nudge a
    test audit.
- **Manual invocation** always available: `/agy-test-audit <suite paths>` (or "audit these test suites for
  exhaustiveness").
- **Peer unreachable (panel S3).** If the peer is down / the channel is dead / the peer is stuck when the
  audit would run, the discipline **halts and asks the operator** to restore the channel or explicitly
  waive the audit — it MUST NOT silently skip, because a silently-skipped audit reads as "the tests are
  exhaustive" (false confidence). In a non-interactive run with no operator, it **aborts** reporting
  `agy-required-but-unreachable`, never a false pass.
- **Non-interactive / headless:** the audit runs and produces its verified-gap report (§8); if it reaches
  the owner-scoping decision (§5 step 5) with no operator present, it **aborts** leaving the report as
  tracked debt rather than auto-writing tests or hanging — mirroring `adversarial-panel-review`'s posture.

## 5. Procedure

**Load-bearing core vs. operational refinements (panel E2).** This spec accreted many guards under
adversarial review; do not read all of them as required for v1. The **load-bearing core** is four steps:
point agy at the diff's files (step 1) → **verify each claimed gap by measurement** (step 3) → **owner
scopes** which to close (step 5) → **close non-vacuously** (step 6). Everything else — the parseable-token
schema, the discarded-below-floor list, the rolling-debt-file staleness/GC/merge mechanics, the
headless-emit path, the capstone-invalidation loop — are **operational refinements the implementation plan
right-sizes**; a v1 can implement the core and land the refinements incrementally. Building the core first
delivers the value (catching untested reachable behaviours); the refinements harden it against the failure
modes in §6.

0. **Precheck** the peer is idle (`agy_status`) and reachable (§4 unreachable-handling). Designate a scratch
   dir for any notes/repro.
1. **Point agy at the REAL files** — via filepath transport (agy reads them itself); **never** a pasted
   summary of the driver's own reading. **Bound the read scope, forked by trigger (panel C1 + D2):** when
   nudged by the branch-finish **hook**, scope to the files in the branch diff and their *immediate* test
   counterparts + directly-relevant source; when invoked **manually** (`/agy-test-audit <paths>`), scope to
   the explicitly provided `<paths>` (a manual run on a clean working tree has an EMPTY diff — the diff-bound
   must NOT be applied, or it audits nothing). Either way, NOT the entire suite or repo, which would blow the
   context window, cost a fortune, and time the peer out (the capstone scopes to the diff for the same reason). Bind scope in the payload: audit ONLY these files;
   assume the surrounding code is correct; no global discovery. Inline the running accepted-boundary ledger
   (step 4) as text each round (agy's context can truncate; a fresh cascade carries nothing forward).
   **The audit is itself a heavy peer consult (panel R2-2)** and inherits the peer's own latency/timeout
   failure modes — a long consult can hit the peer's idle-wait timeout and be backgrounded. The driver must
   poll-then-retrieve a backgrounded/timed-out consult (status-poll to idle, then retrieve the completed
   reply) and MUST NEVER read a timed-out or errored consult as "no gaps found" (that is a silent false pass;
   treat it like S3 peer-unreachable).
2. **Ask for a coverage verdict** in a **parseable form the driver checks before accepting (panel C4)** —
   a fixed terminal token `[VERDICT: EXHAUSTIVE]` or `[VERDICT: GAPS FOUND]`, plus a machine-checkable
   `[VERIFIED: <file>, <file>, …]` block naming what was read. Each gap is enumerated as: the untested
   behaviour, its source `file:line`, the concrete regression that would slip through, and the **specific
   test that should exist** (name + what it asserts). Apply a **severity floor** (skip trivial/contrived
   nits). Anti-rubber-stamp requirements (panel S5/B5/C4):
   - An `[VERDICT: EXHAUSTIVE]` is **only valid if the `[VERIFIED: …]` block is present and non-empty** — the
     driver regex-rejects a bare or malformed EXHAUSTIVE (which would otherwise be a silent-success path) and
     re-asks. A bare "looks complete" is not a valid EXHAUSTIVE (the capstone's substantive-GREEN rule).
   - The audit must also **list the top 1–2 gaps it discarded as below the severity floor**, so a peer
     cannot sweep a real gap under the floor unseen and the driver can recalibrate the floor.
3. **VERIFY each claimed gap by measurement** before accepting it — read the cited test yourself (and grep
   for a sibling that already exercises the path). agy over-counts and states false gaps confidently (in the
   motivating run it claimed a "gap" already covered by an existing test; only reading it revealed the false
   positive). Discard unverified gaps. **This guard defends against false *positives* only** — see the §6
   limitation on false negatives.
4. **Maintain an ACCEPTED-BOUNDARY LEDGER** — behaviours deliberately *not* covered through the given
   harness because they are untestable-without-brittle-mocks **and** otherwise compensated (a unit test, a
   catch-scope, a structural guarantee). These are do-NOT-re-raise, the analog of the capstone's
   do-not-re-raise ledger and AGY-AFTER's already-folded ledger.
5. **Surface the VERIFIED gaps to the OWNER to scope** — which to close (all / high-severity only / defer).
   The discipline **does not auto-write tests**; the owner decides scope (AGY-FIRST "owner decides" ethos).
   Any gaps the owner **defers must be logged as tracked debt** in the single rolling debt file (§8) — a
   GAPS-FOUND-but-all-deferred outcome is legitimate only if recorded there, so a habit of always-deferring
   is visible in one place and the discipline cannot degrade into run-then-defer theater (panel S4/S5).
6. **Close the chosen gaps** — the **driver authors each test itself**; the peer's "suggested test" is a
   *specification* (name + what to assert), never code to paste-and-run — the peer's output is untrusted
   input, gated by verify-before-fold (step 3) and owner-scoping (step 5), so a confused/compromised peer
   cannot inject executable code via a "gap" (panel E1). Each new test **must be NON-VACUOUS**: it must FAIL
   if the guarded behaviour regresses. Prove non-vacuousness with a **temporary LOGIC MUTANT** of the guarded code — flip a boolean,
   drop a conditional, break a calculation — **not** a structural/signature break (deleting a property or
   method), which only fails to *compile* and proves the symbol was referenced, not that the runtime
   assertion catches a behavioural slip (panel S6/B2). Confirm the **specific newly-added test** is the one
   that went red under the mutant — not merely that the suite returned non-zero, which a coincidental **flaky**
   test could satisfy, falsely "proving" non-vacuousness (panel C2). If a single-point mutant does NOT turn
   that test red, that may indicate **defense-in-depth** (multiple independent guards), not a vacuous test —
   widen the mutant or accept a multi-guard regression target rather than concluding "vacuous." If the owner
   wants convergence, **re-audit** carrying the accepted-boundary ledger until the owner accepts.

**Capstone-invalidation rule (panel B1 — the discipline's sharpest edge).** Closing a coverage gap
sometimes reveals the code is *untestable as written* (hard-wired dependency, missing seam) and requires an
**implementation-source refactor** to test it. Any such source change **invalidates the prior AGY-CAPSTONE
GREEN**: AGY-CAPSTONE must be **re-run** over the new code before the branch is declared done. The audit is
NOT a strictly-downstream one-way gate — it can feed back into the capstone, and the loop is
`capstone-green → audit → (owner-scoped test/refactor) → if source changed, re-capstone → re-audit`.
**This loop terminates (panel R2-1):** it is owner-gated, not autonomous — the gap set is finite, the owner
scopes (and may defer) each cycle, and a re-capstone reads only the delta (§5 step 1 diff-scope), so it
cannot ping-pong headlessly. It is a bounded feedback edge, not an unbounded machine loop.

## 6. Failure modes of the discipline itself, and their guards

| Failure mode | Guard |
|---|---|
| **Vacuous satisfaction** (checkbox: propose/write trivial low-value tests instead of the hard intersecting edge cases) | Severity floor + the **non-vacuousness LOGIC-MUTANT requirement** (step 6): every closed gap's test must go red under a behavioural mutant, not a compile break. |
| **Mock-heavy busywork trap** (flag behaviours untestable without brittle sprawling mocks, forcing low-value high-maintenance tests) | The **accepted-boundary ledger** + explicit allowance for **architectural/structural compensation** — a compensated boundary is recorded, not forced into a brittle test. |
| **agy over-counting** (confident false-positive gaps) | Mandatory **verify-before-fold** (step 3). |
| **Rubber-stamp verdict / severity-floor gaming** (bare `EXHAUSTIVE`; "all below floor") | Require the audit to enumerate what it verified AND list the top discarded below-floor gaps (step 2). |
| **Run-then-defer theater** (run the audit, defer every gap, call it done) | Deferred gaps logged as tracked debt in the single rolling debt file (step 5, §8). |
| **Scope creep** (audit unilaterally expands the diff) | The audit **reports**; the **owner scopes** which gaps to close (step 5). |
| **Testability↔implementation cycle** (closing a gap needs a source refactor that staled the capstone) | The **capstone-invalidation rule** (§5): a source change re-runs AGY-CAPSTONE. |

**Stated limitation — false negatives (panel meta).** Every guard above defends against false *positives*
(the peer claiming a gap that isn't one). **None defends against a false *negative*** — the peer silently
missing a real gap. A single-peer audit is therefore a **floor, not proof of completeness**, and does not
replace good test design or the author's own coverage judgement. Optional mitigations a plan may adopt:
rotate the audit's lens across runs (a "what modality/behaviour did I not look at?" completeness-critic
pass), or diversify the seats — but the discipline explicitly does not *claim* completeness, only that it
raises the floor.

## 7. Relationship to the family (ordering)

> AGY-FIRST gates the **decision** · AGY-AFTER gates the **artifact** · AGY-CAPSTONE gates the **finished
> implementation** (defects) · **AGY-TEST-AUDIT gates the test safety-net (coverage)** · AGY-LEARN
> **captures**.

AGY-TEST-AUDIT runs **after AGY-CAPSTONE is GREEN**, at branch-finish. It never replaces the capstone's
defect hunt; it asks the orthogonal question — *would the tests catch the next defect?* The two are **not a
strict one-way pipeline**: if the audit's remediation changes implementation source, it re-invokes the
capstone (§5 capstone-invalidation rule).

## 8. Outputs

Two distinct artifacts, so debt cannot hide in a sea of stale per-branch files (panel B3 + its C3
correction):

- **A per-run report — EPHEMERAL** (scratch dir or `.gitignore`d, NOT committed). It is the working output
  the owner scopes from: the **coverage verdict** (`[VERDICT: EXHAUSTIVE]` / `[VERDICT: GAPS FOUND]`), the
  `[VERIFIED: …]` block, the **verified-gap list** (each with `file:line`, the slip-through regression, and
  the missing test's name + assertion), and the **discarded-below-floor** items. Committing one of these per
  branch-finish would pollute the repo with hundreds of point-in-time files operators learn to ignore — so
  it is deliberately not committed.
- **A single, stable, ROLLING committed file** (e.g. `coverage-debt.md` at a plan-chosen path) holding ONLY
  the two things that must persist: **unresolved tracked debt** (gaps the owner deferred, so a
  defer-everything habit is visible and the debt is findable in one place) and the **accepted-boundary
  ledger** (so future audits inherit the do-not-re-raise list). Closed gaps are removed from it. Three
  persistent-state hazards it must be designed against (panel R3-1/D1):
  - **Ledger staleness:** each accepted-boundary entry records its *specific compensation* (the unit test /
    catch-scope / structural guarantee that justified not covering it) + a code anchor; a future audit
    **re-validates the compensation still exists** before honoring the do-not-re-raise — an entry whose
    compensation vanished is promoted back to a live gap (like the capstone ledger's "unless reachable").
  - **Ghost debt:** because the audit is diff-scoped (C1), it cannot see deleted/refactored code to prune
    its stale entries, so the file inflates monotonically. A **periodic global garbage-collection pass**
    (manual, whole-tree) reconciles the file against current code and drops orphaned entries — the routine
    diff-bound run cannot do this.
  - **Merge-conflict attrition:** a single file touched at every branch-finish is a conflict hotspot where a
    careless `--ours`/`--theirs` silently drops a teammate's entry. Structure it to minimize conflicts —
    append-only log or module-partitioned sections — not one hand-merged block.

- On close: the new **non-vacuous** tests + the rolling debt file updated (deferred gaps in, closed gaps out)
  + a re-audit verdict (up to the owner's convergence bar).
- Failure terminals: `[VERDICT: agy-required-but-unreachable]` (peer down, no operator to waive) or a
  headless run aborting with its gap list — never a silent pass. **In a headless/CI run the gap list is
  emitted to stdout/stderr / the CI step summary (build logs), NOT written to the rolling debt file** (panel
  D3): modifying a tracked file just before a non-zero exit in an ephemeral container is a no-op — the
  container is destroyed and the write is lost, so the debt would silently vanish. Persisting to the rolling
  file requires a live workspace (an interactive/local run that then commits).

## 9. Testing the discipline itself

- **Skill activation:** frontmatter `description` fires at branch-finish and is NOT over-eager
  mid-implementation (an Activation-Auditor lens on the glob/description).
- **Hook:** registered in `hooks.json`, fires on the finish-branch skill only (not the broad execution set),
  **exits silently when the branch diff has no code/test changes**, silent otherwise; jq/bash-guard +
  `.no-agy` suppression parity with the sibling hooks; **seed-sync** between the two plugin copies
  (`check-seed-artifacts-synced.sh` extended to the new shared artifact).
- **Headless / unreachable paths:** aborts with the report (or `agy-required-but-unreachable`) rather than
  hanging or silently passing.

## 10. Out of scope

- Auto-writing tests without owner scoping.
- Replacing AGY-CAPSTONE's defect hunt (though it can re-invoke it — §5).
- Line-/branch-coverage **percentage** tooling — this is **behavioural-gap** auditing (would-a-defect-slip-through),
  not a coverage-% gate.
- Claiming completeness — the audit raises the coverage floor; it is not proof no gap remains (§6 limitation).
