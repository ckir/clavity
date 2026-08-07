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

Every finding raised in any round of any of the three disciplines resolves to **exactly one** of five
tokens. The set is **closed** — there is no sixth outcome, and no "noted".

**This taxonomy EXTENDS an existing vocabulary; it does not replace one.** `agy-capstone` already ships
two per-finding dispositions — `[VERDICT: REJECTED - <measured reason>]`, described at `SKILL.md:184-186`
as *"a **per-finding disposition**, not a terminus"*, and the `UNVERIFIED-ACCEPTED` audit line at
`SKILL.md:126-131`. An earlier draft of this spec invented `REFUTED` alongside `REJECTED` and omitted
`UNVERIFIED` entirely, which would have shipped a rival vocabulary for the same acts. The taxonomy below
adopts the existing names.

| Token | Meaning | Required evidence |
|---|---|---|
| `FOLDED: <what changed>` | Fixed inside the current work | The change itself |
| `REJECTED: <measured reason>` | The finding is false | A **measurement** — `file:line` or quoted stdout |
| `DISCARDED-BELOW-FLOOR: <target> unreachable because <guard>` | Contrived, exotic, or unreachable | The **structural guard, invariant, or precondition at `file:line`** that makes it unreachable |
| `DEFERRED-TO-ANOMALIES: <anchor> * <YYYY-MM-DD>[ * unverified]` | Reachable, not fixed now | The **already-appended** inbox entry |
| `UNVERIFIED-ACCEPTED: <finding>` | Neither provable nor refutable; owner accepted the risk | The `skipped.log` audit line, per `agy-capstone/SKILL.md:126-131` |

**Age is not a member of the set.** This is the mechanism, and its limit should be stated honestly: it
removes the *slot* for a provenance disposition, not the *ability to reason badly*. A reviewer can still
smuggle age into a reachability argument ("this predates the diff and nothing new reaches it"). What the
taxonomy buys is that such a claim now has to be **stated as a reachability claim**, which §4.5 makes
checkable and which a peer can contradict. It does not buy impossibility.

**Evidentiary parity.** `DISCARDED-BELOW-FLOOR` carries the same evidentiary bar as `REJECTED`: it must
cite the guard, invariant, or precondition at `file:line` that makes the defect unreachable. An earlier
draft required only "a reachability argument", which let a plausible prose assertion stand down a real
defect while a refutation needed quoted output — an asymmetry that pushed reviewers toward the cheaper
token precisely when the finding was uncomfortable.

**`DEFERRED-TO-ANOMALIES` payload grammar.** Three fields, matching `open-issues`' own entry format so
the two reconcile:

- `<anchor>` — the **source** location, `file:line`, or the literal `n/a` when the defect has no single
  line (a tool defect, an architectural omission). `open-issues/SKILL.md:111` already specifies
  *"`file:line` if it has one, `n/a` if it does not"*, and a grammar that cannot express `n/a` would
  force a fabricated line number.
- `<YYYY-MM-DD>` — identifies the inbox entry by **stable identity, never by line offset**. Inbox line
  numbers shift the moment triage deletes an entry, and `open-issues/SKILL.md:182-184` guarantees
  deletion happens. A committed review record citing `local-anomalies.md:15` goes stale by design.
- `unverified` — **required** when the captured entry is a `reported, unverified:` claim.
  `open-issues/SKILL.md:54-55` explicitly sanctions capturing what "cannot be checked cheaply" as a
  claim, so the token must not assert verification the entry does not carry.

**Deferral is bounded to defects outside the reviewed change.** `DEFERRED-TO-ANOMALIES` is available
**only** for a defect on a line the reviewed diff did not introduce or modify. A reachable defect in the
change's *own* new lines must be `FOLDED`, or must go through the existing `UNVERIFIED` path to an owner
ruling. Without this bound the token is a general-purpose escape hatch: an implementer could append their
own fresh bug to the inbox, satisfy the completeness gate, and ship it under a clean verdict — which
would invert the discipline into a way of *evading* review rather than widening it.

**Ordering constraint.** The driver appends to the inbox **first**, then emits the token. A token
pointing at an entry that was never written is the exact rot this replaces.

**Authorship constraint.** The peer never writes to the inbox. Per `open-issues/SKILL.md:29` —
*"A subagent REPORTS; the driver VERIFIES; the driver WRITES."* The peer's output is untrusted input;
this amendment does not create a write path for it.

### 4.2 The completeness gate

**No verdict that COMPLETES a run may be proposed while any raised finding lacks a token.** The gate
binds to each skill's existing termini rather than introducing a new one — and it binds to **every**
completing terminus, not only the clean one:

| Skill | Completing termini it gates | Anchor |
|---|---|---|
| adversarial-panel-review | `GREEN` | `SKILL.md:236` |
| agy-capstone | `[VERDICT: ALIGNED]` | `SKILL.md:177` |
| agy-test-audit | `[VERDICT: EXHAUSTIVE]` **and `[VERDICT: GAPS FOUND]`** | `SKILL.md:131`, `SKILL.md:134-136` |

**Gating only the clean terminus would leave the hole wide open.** `agy-test-audit/SKILL.md:134-136`
defines `[VERDICT: GAPS FOUND]` as legitimately *"done"* once every gap is closed or recorded as deferred
debt, and `SKILL.md:154-155` has such a run **write the debounce marker** — so a `GAPS FOUND` run both
completes and disarms the next nudge. A driver who tokenized one gap and left three peer claims
unassigned could terminate through it untouched. Any terminus that completes a run and can write a
marker is a terminus this gate must cover.

This generalizes the mechanism already proven at `agy-test-audit:67-69` instead of inventing one.

**What the gate does not do.** It binds findings that were *recorded*. A finding never written down has
no unassigned token and cannot trip the gate. That hole is real and is not closable by this mechanism —
recording discipline stays a judgment rule that a peer review catches, which is why §4.4 keeps a
discarded-findings list rather than relying on the gate alone.

### 4.3 The age clause

One sentence, identical in all three skills, naming the forbidden phrasings **explicitly** rather than
gesturing at them — so that paraphrase has a named target to be measured against:

> A defect's age is never a disposition. "Pre-existing", "not introduced by this commit", and "out of
> scope for this change" are not admissible stand-down reasons, and neither is any paraphrase of them.
> The only admissible stand-down is the reachability floor, which is age-blind.

### 4.4 The anti-sweep device, generalized

All three skills adopt `agy-test-audit`'s existing requirement: each run lists the top 1-2 findings it
discarded below the floor.

The full list lands in the **ephemeral per-run report**. But a stand-down that exists *only* in a
gitignored scratch file is an audit black hole: a defect class repeatedly stood down across weeks leaves
zero durable trace, so a later incident cannot discover that anyone ever saw it. Each
`DISCARDED-BELOW-FLOOR` therefore also gets a **one-line summary in the run's durable record** — the
existing committed `docs/agy-capstone-ledger.md` row for a capstone, or the commit message otherwise.
This creates **no new surface**: both destinations already exist and are already written on every run.

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

The new file is `docs/accepted-boundaries.md`. It is **created, not renamed** — `docs/coverage-debt.md`
was specified at `agy-test-audit/SKILL.md:111` but never existed, so there is nothing to `git mv`. The
name differs because under the split the file no longer holds debt, and a name that lies is worse than
no file.

**It needs a schema, not free prose.** `agy-test-audit/SKILL.md:78-79` requires a *future* audit to
"re-validate the compensation still exists before honoring the do-not-re-raise" — an entry whose
compensation vanished is promoted back to a live gap. That re-validation cannot run against arbitrary
prose. The entry format mirrors `open-issues`' own, which is already terse and already parsed by eye:

```
- [boundary] <behaviour not covered> * <source/path.ext:LINE> * compensation=<what covers it instead, with its code anchor> * <YYYY-MM-DD>
```

One entry per line. `compensation=` must name a concrete artifact (a unit test, a catch scope, a
structural guarantee) **and** its anchor, because that anchor is exactly what the future audit
re-validates. An entry with no anchor is not honorable as do-not-re-raise and reverts to a live gap.

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

Add the taxonomy tokens to `$requiredVerdicts` in `check-agy-discipline-skills.ps1:18-21` for the
enrolled review skills, so a mirror that silently loses the amendment fails a gate rather than degrading
quietly. This checks that the contract **ships**, not that it is **obeyed** — obedience stays a judgment
rule a peer review catches. Claiming otherwise would be theater.

**No partitioning of the checker is required, and none should be added.** `$requiredVerdicts` is already
keyed per skill — `check-agy-discipline-skills.ps1:15` states *"The required ASCII [VERDICT] forms PER
SKILL (each discipline has its own vocabulary)"*, and `agy-test-audit` already carries a set disjoint
from the other two. Adding tokens to the review-skill entries therefore cannot affect `agy-first`, which
is a consult discipline and is deliberately absent from §5's file list. A round-1 finding proposed
splitting the map into `$consultVerdicts` / `$reviewVerdicts` to prevent that breakage; the breakage
cannot occur, and the split would refactor a structure that already partitions. **Rejected by
measurement.**

**Enrollment of `adversarial-panel-review` is deferred to the plan.** It is absent from
`check-agy-discipline-skills.ps1:13` and uses `GREEN` rather than a `[VERDICT: …]` token, so enrolling it
means either teaching the checker a second grammar or changing the skill's terminus. That is a real
decision with its own blast radius, and it is not free.

### 4.9 The conveyor's terminus

`open-issues/SKILL.md:182-184` requires every inbox entry to be PROMOTED to a tracked item or DELETED
with a recorded reason. "Promoted to a tracked ROADMAP item" is under-specified in a monorepo: **four
`ROADMAP.md` files exist** — `clavity-dotnet/`, `clavity-classic/`, `agy-autotrain/`, `commonmemory/` —
while `agy-anomaly-reminder.sh:110-111` resolves a **single** inbox at the repo root. A defect found
during a `clavity-dotnet` review can live in any product.

**Rule:** a promoted entry lands in the `ROADMAP.md` of the product that **owns the defective file**, not
the product under review. Where a defect spans products or belongs to none (shared `scripts/`, root
`docs/`), it lands in `clavity-dotnet/ROADMAP.md`, which is the repo's de-facto primary and already
carries the cross-cutting sections including §7 itself.

This is the only sanctioned backlog. It is not a new surface: the ROADMAPs are committed, owner-curated,
priority-ordered, and already the place work is scoped. The standing ruling against backlog *mechanisms*
is a ruling against untracked parking lots, and `:182-184` forbids exactly that by construction.

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
  skill carries all five tokens and the age clause.
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

### 8.1 Accepted limitations — holes this design does not close

Named because an unnamed limitation reads as a claim of coverage.

1. **The amendment binds only when the SKILL is invoked.** AGY-CAPSTONE also exists as a self-contained
   rule in the global `CLAUDE.md`, and a capstone driven from that rule alone never loads the taxonomy.
   §8 puts that file out of bounds, so this hole is by construction, not by oversight. Mitigation is
   social: the rule already points at the discipline family.
2. **The conveyor's forcing function degrades silently without `jq`.** `agy-anomaly-reminder.sh:55`
   emits *"guard inactive: missing jq - cannot check for untriaged anomalies"* and the triage demand
   never fires. Deferred entries then sit in the inbox unannounced. Pre-existing, not introduced here,
   and out of scope to fix — but the F4 answer rests on that gate, so its failure mode is stated.
3. **The inbox is destroyed by `git clean -fd`.** `.gitignore:45` makes `.clavity/` untracked. Entries
   deferred but not yet triaged are lost without trace. The window is one session by design, because
   `:182-184` forbids parking — but the window is real.
4. **The gate cannot see an unrecorded finding** (§4.2). Recording discipline stays a judgment rule.

## 9. Success criterion

Take a reachable defect demonstrably older than the diff under review. There must be **no wording a
reviewer can write that stands it down** without either (a) a reachability argument citing the guard that
makes it unreachable, or (b) an owner ruling recorded somewhere durable. If "pre-existing" remains
sayable as a terminal reason, this failed.

Note the bar deliberately: it is that a bad stand-down must be **stated as a falsifiable reachability
claim**, not that a bad stand-down becomes impossible (§4.1). A claim a peer can open the file and
contradict is the achievable goal; an unfoolable gate is not.

## 10. Open questions carried to the plan

1. Enrollment of `adversarial-panel-review` in the discipline checker (§4.8) — second grammar vs. changed
   terminus.
2. Whether the five in-memory coverage gaps are backfilled inside this work or as a follow-on (§7).
3. Whether `docs/accepted-boundaries.md` is user-facing for roster purposes (§6).

Each is a bounded decision with a named resolution point. None blocks writing the plan.
