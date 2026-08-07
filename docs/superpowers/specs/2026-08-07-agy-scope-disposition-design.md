# AGY-SCOPE — the disposition half, as a cross-cutting amendment

**Date:** 2026-08-07 · **ROADMAP:** clavity-dotnet §7 (`ROADMAP.md:494-554`) · **Status:** spec, approved for planning

Every citation below was read against `HEAD = 542a016` before being written. This is a SPEC — it fixes
intent and contracts. Line-level insertion points belong to the implementation plan.

---

## 1. The defect

Every review discipline in the family produces findings, and none of them says what a finding's **age**
means. In practice the driver reaches for *"pre-existing / not introduced by this commit / out of scope
for this change"* as a **disposition** — which is not a severity argument at all. Two independent axes
get collapsed:

- **severity / reachability floor** — the legitimate stand-down, for contrived, exotic or unreachable
  edges, **whatever their age**;
- **provenance** — how old the defect is, which carries **zero** dispositional weight.

Collapsing them silently drops reachable defects, and mirrors the error onto new code: a contrived
new-code edge gets folded because it is "in scope" while a reachable old one gets dropped because it is
not.

**Evidence it is real, not theoretical** (`ROADMAP.md:521-525`): two findings from the agy-test-audit
epic were "surfaced to the owner" and were still open, untracked and unplanned days later. A third was
very nearly filed under the severity floor for its *age* rather than its *reachability*. Surfacing
without a tracked plan is not a disposition either.

## 2. Measured prior state

| Fact | Measurement |
|---|---|
| No mechanism exists anywhere | `"pre-existing"` occurs **once** across all five plugin skills — `open-issues/SKILL.md:191`, and it is a *pointer* deferring the disposition half to AGY-SCOPE |
| The concept is spelled three ways in three places | `adversarial-panel-review/SKILL.md:149` "severity floor against runaway nitpicking" · `agy-capstone/SKILL.md:99` "**Reachability floor.** Stop nitpicking" · `agy-test-audit/SKILL.md:64` "severity floor (skip trivial/contrived nits)" |
| One anti-sweep device already ships | `agy-test-audit/SKILL.md:64-66` requires the audit to "list the top 1-2 gaps it discarded below the floor, so a real gap cannot be swept under the floor unseen" |
| One terminal-token gate already ships | `agy-test-audit/SKILL.md:67-69` — `[VERDICT: EXHAUSTIVE]` is "valid only if the `[VERIFIED: ...]` block is present and non-empty" |
| The specced debt file was never created | `agy-test-audit/SKILL.md:111` names `docs/coverage-debt.md`; `ls` returns `No such file or directory` |
| The capture half is shipped and forcing | `open-issues/SKILL.md:182-184` — "There is no third outcome. Nothing may sit 'acknowledged' or 'noted'… An entry that is real but not worth doing now is PROMOTED as tracked debt, not left in the file" |
| Two SessionStart hooks drain it | `hooks.json:53-54` registers `agy-anomaly-reminder.sh` (human-facing, stderr) **and** `agy-anomaly-model-notice.sh` (model-facing) |
| The inbox is a conveyor, not a store | `.gitignore:45` = `.clavity/`; `git ls-files --error-unmatch .clavity/local-anomalies.md` → *"did not match any file(s) known to git"* |
| One of the three targets is unguarded | `check-agy-discipline-skills.ps1:13` enrolls `@('agy-first', 'agy-capstone', 'agy-test-audit')` — **`adversarial-panel-review` is absent** |
| Skills must ship byte-identically | `check-seed-artifacts-synced.sh:23-24` diffs `hooks skills knowledge` across both drivers; its exception list (`:29-33`) covers only the transport twins |

## 3. Owner rulings this spec is built on

1. **Shape** — a **cross-cutting amendment** to the three review skills, **not** a fourth standalone
   discipline. (Ruled 2026-08-07; question 1 of §7 is closed.)
2. **Debt destination** — *split it*: deferred debt rides the existing conveyor; a committed file is
   created **only** for the accepted-boundary ledger.
3. **Mirror scope** — both drivers in one plan, since the parity gate is already enforced and splitting
   would leave it red in between.

## 4. Design

### 4.1 The disposition taxonomy (the core)

Every finding raised in any round of any of the three disciplines resolves to **exactly one** of four
tokens. The set is **closed** — there is no fifth outcome, and no "noted".

| Token | Meaning | Required evidence |
|---|---|---|
| `FOLDED: <what changed>` | Fixed inside the current work | The change itself |
| `REFUTED: <falsification>` | The finding is false | A **measurement** — `file:line` or quoted stdout |
| `DISCARDED-BELOW-FLOOR: <argument>` | Contrived, exotic, or unreachable | A **reachability** argument |
| `DEFERRED-TO-ANOMALIES: <path>:<line>` | Reachable, verified, not fixed now | The **already-appended** inbox line |

**Age is not a member of the set**, so it cannot be written as an outcome. `DISCARDED-BELOW-FLOOR` is
the only stand-down, and it must carry a reachability argument — never a provenance one.

**Ordering constraint.** `DEFERRED-TO-ANOMALIES` cites a line that must already exist: the driver
appends to the inbox **first**, then cites it. A token pointing at an unwritten line is the exact rot
this replaces.

**Authorship constraint.** The peer never writes to the inbox. Per `open-issues/SKILL.md:29` —
*"A subagent REPORTS; the driver VERIFIES; the driver WRITES."* The peer's output is untrusted input;
this amendment does not create a write path for it.

### 4.2 The completeness gate

**No terminal clean verdict may be proposed while any raised finding lacks a token.** This binds to each
skill's existing terminus rather than introducing a new one:

| Skill | Terminus it gates | Anchor |
|---|---|---|
| adversarial-panel-review | `GREEN` | `SKILL.md:236` |
| agy-capstone | `[VERDICT: ALIGNED]` | `SKILL.md:177` |
| agy-test-audit | `[VERDICT: EXHAUSTIVE]` | `SKILL.md:132` |

This generalizes the mechanism already proven at `agy-test-audit:67-69` instead of inventing one.

### 4.3 The age clause

One sentence, identical in all three skills, naming the forbidden phrasings **explicitly** rather than
gesturing at them — so that paraphrase has a named target to be measured against:

> A defect's age is never a disposition. "Pre-existing", "not introduced by this commit", and "out of
> scope for this change" are not admissible stand-down reasons, and neither is any paraphrase of them.
> The only admissible stand-down is the reachability floor, which is age-blind.

### 4.4 The anti-sweep device, generalized

All three skills adopt `agy-test-audit`'s existing requirement: each run lists the top 1-2 findings it
discarded below the floor. This lands in the **ephemeral per-run report**, not a committed file, so it
creates no new surface.

### 4.5 Scope boundary

*"Always in scope"* does not mean auditing the tree on every review. The bound is **age-blind
reachability from the touched surface**:

- **In scope** — the reviewed diff or artifact, plus the contracts, invariants, data schemas, and
  execution paths that **intersect** it.
- **Out of scope** — open-ended discovery in unrelated modules.
- **The age-blind rule** — if a path or contract touched by the diff exposes a defect, that defect is in
  scope **regardless of when the faulty line was authored**.

### 4.6 The agy-test-audit reconciliation

Under the owner's *split it* ruling, `agy-test-audit/SKILL.md:111-117` currently specifies one file
holding **two different things**. They separate:

- **Unresolved tracked debt** (owner-deferred gaps) → rides the conveyor like every other deferral.
  `:111` stops naming a debt file.
- **The accepted-boundary ledger** (do-not-re-raise entries, each with its compensation + code anchor)
  → needs a **committed** home, because `:78-79` requires a *future* audit to re-validate that each
  compensation still exists. A gitignored file cannot serve that.

The new file is `docs/accepted-boundaries.md` — renamed from the specced-but-absent `docs/coverage-debt.md`
because under the split it no longer holds debt, and a name that lies is worse than no file.

### 4.7 The intake-bar amendment (a fourth skill is touched)

The conveyor's intake bar must admit the cargo the taxonomy routes to it. `open-issues/SKILL.md:14-15`
reads:

> Capture any reachable code defect, tool misbehavior, or operational blocker that actively degrades or
> prevents the agent/owner workflow.

It is **genuinely ambiguous** whether *"that actively degrades or prevents the agent/owner workflow"*
qualifies all three nouns or only "operational blocker". Under the first reading a reachable defect in
shipped product code — exactly what a capstone finds — fails the bar and cannot legitimately be
appended, which would break `DEFERRED-TO-ANOMALIES` on its most common case.

**Resolution:** amend `:14-15` to make the qualifier attach only to `operational blocker`, so a reachable
code defect qualifies on its own reachability. This is a clarification of intent, not a widening — the
opinion-exclusion at `:19-21` is untouched and still does the narrowing work.

### 4.8 Mechanical enforcement

Add the four taxonomy tokens to `$requiredVerdicts` in `check-agy-discipline-skills.ps1:18-21` for the
enrolled skills, so a mirror that silently loses the amendment fails a gate rather than degrading
quietly. This checks that the contract **ships**, not that it is **obeyed** — obedience stays a judgment
rule a peer review catches. Claiming otherwise would be theater.

**Enrollment of `adversarial-panel-review` is deferred to the plan.** It is absent from
`check-agy-discipline-skills.ps1:13` and uses `GREEN` rather than a `[VERDICT: …]` token, so enrolling it
means either teaching the checker a second grammar or changing the skill's terminus. That is a real
decision with its own blast radius, and it is not free.

## 5. Files touched

| File | Change |
|---|---|
| `{dotnet,classic}/plugin/skills/adversarial-panel-review/SKILL.md` | taxonomy + gate + age clause + anti-sweep + scope boundary |
| `{dotnet,classic}/plugin/skills/agy-capstone/SKILL.md` | same |
| `{dotnet,classic}/plugin/skills/agy-test-audit/SKILL.md` | same, plus the §4.6 reconciliation |
| `{dotnet,classic}/plugin/skills/open-issues/SKILL.md` | §4.7 intake-bar clarification |
| `scripts/check-agy-discipline-skills.ps1` | `$requiredVerdicts` additions |
| `scripts/tests/check-agy-discipline-skills.Tests.ps1` | pinning tests |
| `docs/accepted-boundaries.md` | **new** |
| `clavity-dotnet/ROADMAP.md` | §7 marked shipped |

Eight skill files, four logical bodies, each shipping twice byte-identically.

## 6. Testing strategy

- **Byte parity** — `check-seed-artifacts-synced.sh` already covers `skills`; the four amended skills are
  not in its exception list (`:29-33`), so parity is enforced without new work.
- **Contract presence** — new assertions in `check-agy-discipline-skills.Tests.ps1` that each enrolled
  skill carries all four tokens and the age clause.
- **Non-vacuity is mandatory.** Each new assertion must be proven with a deliberate mutation of the
  guarded text, and the **specific newly-added test** must be the one that goes red — not merely that
  the suite returned non-zero.
- **Roster** — if `docs/accepted-boundaries.md` is user-facing it needs enrolling in
  `docs/user-facing-docs.txt`; `just docs-audit` silently intersects that roster, so an unenrolled doc
  audits as "0 docs" rather than failing. The plan decides enrollment explicitly.

## 7. Consequences, stated not buried

The five verified coverage gaps currently held in memory are **deferred debt**, so under this design they
belong on the conveyor. Appending them makes `open-issues/SKILL.md:182-184` bind: they **block the next
session until triaged**, each either PROMOTED to a tracked ROADMAP item or DELETED with a recorded reason.
That is the mechanism working as designed, but the cost lands immediately rather than later. Whether the
backfill happens inside this work or as a follow-on is a plan-time decision.

## 8. Non-goals

- **The AGY-CAPSTONE rule body in `~/.claude/CLAUDE.md`.** Outside the repo, invisible to git, out of
  bounds. The amendment ships in the skill only; the global rule keeps its current text.
- **Factoring a shared adversarial-review core.** Deferred to its own epic. Landing a new contract across
  eight byte-identical files while simultaneously restructuring them is two risks at once, and the peer
  and I converged independently on sequencing it after.
- **A review-output linter.** A regex hunting the literal string "pre-existing" is trivially defeated by
  paraphrase. The closed taxonomy achieves the goal by removing the slot, not by policing the wording.
- **Auto-fixing deferred defects.** The driver surfaces and plans; the owner scopes.

## 9. Success criterion

Take a reachable defect demonstrably older than the diff under review. There must be **no wording a
reviewer can write that stands it down** without either (a) a reachability argument, or (b) an owner
ruling recorded somewhere durable. If "pre-existing" remains sayable as a terminal reason, this failed.

## 10. Open questions carried to the plan

1. Enrollment of `adversarial-panel-review` in the discipline checker (§4.8) — second grammar vs. changed
   terminus.
2. Whether the five in-memory coverage gaps are backfilled inside this work or as a follow-on (§7).
3. Whether `docs/accepted-boundaries.md` is user-facing for roster purposes (§6).

Each is a bounded decision with a named resolution point. None blocks writing the plan.
