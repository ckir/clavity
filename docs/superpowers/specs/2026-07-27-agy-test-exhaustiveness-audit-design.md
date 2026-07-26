# AGY-TEST-EXHAUSTIVENESS-AUDIT — design

**Status:** design (spec). Line-level implementation plan waits on this spec's approval; the concrete
template already exists (`adversarial-panel-review`), so a plan is writable against it.

**One-line:** A standing, named agy discipline that — after AGY-CAPSTONE is GREEN — convenes the live agy
peer to audit the **test suites** for coverage exhaustiveness (untested reachable behaviors, vacuous/weak
assertions, missing edge cases), verifies each claimed gap by measurement, and surfaces the verified gaps
for the owner to scope.

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

- **Hook nudge at branch-finish**, sequenced **after AGY-CAPSTONE reports GREEN** — i.e. the same
  finish-a-development-branch moment the capstone nudge targets, one step later. The hook only *reminds*;
  invoking the skill is what runs it (a hook fires only if the covered skill is invoked, so the
  `CLAUDE.md` pointer is the backstop for branches finished without the skill).
- **Manual invocation** always available: `/agy-test-audit <suite paths>` (or "audit these test suites for
  exhaustiveness").
- **Non-interactive / headless:** the audit runs and produces its verified-gap list; if it reaches the
  owner-scoping decision (§5, step 5) with no operator present, it **ABORTS with the verified gap list**
  rather than auto-writing tests or hanging — mirroring `adversarial-panel-review`'s headless posture.

## 5. Procedure

0. **Precheck** the peer is idle (`agy_status`). Designate a scratch dir for any notes/repro.
1. **Point agy at the REAL files** — the test suites, the source under test, and the design specs — via
   filepath transport (agy reads them itself); **never** a pasted summary of the driver's own reading.
   Bind scope in the payload: audit ONLY these suites; assume the surrounding code is correct; no global
   discovery. Inline the running accepted-boundary ledger (§ step 4) as text each round (agy's context can
   truncate; a fresh cascade carries nothing forward).
2. **Ask for a coverage verdict** — `EXHAUSTIVE` or `GAPS FOUND` — enumerating each gap as: the untested
   behaviour, its source `file:line`, the concrete regression that would slip through, and the **specific
   test that should exist** (name + what it asserts). Apply a **severity floor** (skip trivial/contrived
   nits, e.g. "test the constructor assigns properties").
3. **VERIFY each claimed gap by measurement** before accepting it — read the cited test yourself. agy
   over-counts and states false gaps confidently (in the motivating run it claimed a "gap" that was already
   covered by an existing test; only reading it revealed the false positive). Discard unverified gaps.
4. **Maintain an ACCEPTED-BOUNDARY LEDGER** — behaviours deliberately *not* covered through the given
   harness because they are untestable-without-brittle-mocks **and** otherwise compensated (a unit test, a
   catch-scope, a structural guarantee). These are do-NOT-re-raise, the analog of the capstone's
   do-not-re-raise ledger and AGY-AFTER's already-folded ledger.
5. **Surface the VERIFIED gaps to the OWNER to scope** — which to close (all / high-severity only / defer).
   The discipline **does not auto-write tests**; the owner decides scope (AGY-FIRST "owner decides" ethos).
6. **Close the chosen gaps** — each new test **must be NON-VACUOUS**: it must FAIL if the guarded behaviour
   regresses (verify by a temporary revert of the guarded code where feasible, then restore). If the owner
   wants convergence, **re-audit** carrying the accepted-boundary ledger until the owner accepts.

## 6. Failure modes of the discipline itself, and their guards

| Failure mode | Guard |
|---|---|
| **Vacuous satisfaction** (checkbox: propose/write trivial low-value tests instead of the hard intersecting edge cases) | Severity floor in the ask + the **non-vacuousness requirement** (every closed gap's test must fail on a regression, verified by a temporary revert where feasible). |
| **Mock-heavy busywork trap** (flag behaviours untestable without brittle sprawling mocks, forcing low-value high-maintenance tests) | The **accepted-boundary ledger** + explicit allowance for **architectural/structural compensation** — a compensated boundary is recorded, not forced into a brittle test. |
| **agy over-counting** (confident false gaps) | Mandatory **verify-before-fold** (step 3). |
| **Scope creep** (audit unilaterally expands the diff) | The audit **reports**; the **owner scopes** which gaps to close (step 5). |

## 7. Relationship to the family (ordering)

> AGY-FIRST gates the **decision** · AGY-AFTER gates the **artifact** · AGY-CAPSTONE gates the **finished
> implementation** (defects) · **AGY-TEST-AUDIT gates the test safety-net (coverage)** · AGY-LEARN
> **captures**.

AGY-TEST-AUDIT runs **after AGY-CAPSTONE is GREEN**, at branch-finish. It never replaces the capstone's
defect hunt; it asks the orthogonal question — *would the tests catch the next defect?*

## 8. Outputs

- A **coverage verdict** (`EXHAUSTIVE` / `GAPS FOUND`) + a **verified-gap list** (each with `file:line`,
  the slip-through regression, and the missing test's name + assertion) + the **accepted-boundary ledger**.
- On close: the new **non-vacuous** tests + a re-audit verdict (up to the owner's convergence bar).
- Failure terminal for a headless run with no operator to scope: aborts reporting the verified-gap list.

## 9. Testing the discipline itself

- **Skill activation:** frontmatter `description` fires at branch-finish and is NOT over-eager
  mid-implementation (an Activation-Auditor lens on the glob/description).
- **Hook:** registered in `hooks.json`, fires on the finish-branch skill, silent otherwise; jq/bash-guard +
  `.no-agy` suppression parity with the sibling hooks; **seed-sync** between the two plugin copies
  (`check-seed-artifacts-synced.sh` extended to the new shared artifact).
- **Headless path:** aborts with the gap list rather than hanging for an absent operator.

## 10. Out of scope

- Auto-writing tests without owner scoping.
- Replacing AGY-CAPSTONE's defect hunt.
- Line-/branch-coverage **percentage** tooling — this is **behavioural-gap** auditing (would-a-defect-slip-through),
  not a coverage-% gate.
