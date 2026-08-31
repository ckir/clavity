# ROADMAP implementation sequence - design

**Date:** 2026-08-31. **HEAD at authoring:** `e5179a5`.
**Status:** owner-approved sequence. Each phase still needs its own spec-or-plan before execution.

**Goal:** decide the ORDER and BATCHING of the remaining open ROADMAP work. This document does not
design any of that work - every item is already owner-accepted or owner-open, and several carry their
own committed detail. It decides only what is built in what order, in which batches, and why.

**Consulted:** the live agy peer under AGY-FIRST (`.clavity/seams/roadmap-sequencing.md`, reply at
`.clavity/scratch/roadmap-sequencing/reply.md`). Its central reframing was adopted; three of its
supporting claims were checked by measurement and two did not survive. Both outcomes are recorded below,
because the refuted ones are the reason two owner decisions went against its recommendation.

---

## 1. The verified state - and why the ROADMAP itself cannot be trusted as the index

**Before sequencing anything, the index was reconciled against git.** Three sections carry headers that
contradict what shipped:

| section | header says | git says |
|---|---|---|
| §17 | `▶ OPEN` | §17a shipped `99910c0`, capstone GREEN (ledger `eb26709`); §17b RULED KILLED |
| §18 | `▶ OPEN` | shipped, capstone GREEN after 7 rounds (ledger `519833f`) |
| §19 | `DECIDED, DEFERRED` | shipped `64d5be4`, same capstone GREEN |

This is a recurrence of a recorded failure - §13b read `▶ OPEN` seven days after shipping - and the rule
earned from it is that **whoever closes an item writes its closing sha in the same commit.** That rule
was not followed for these three.

**Sequencing from those headers would have scheduled work that is already done.** Reconciling the index
is therefore Phase 0, not a tidy-up.

**§16 is a PATTERN, not schedulable work** (it records the transient-Pester edit-verification approach for
future plans and changes nothing shipped).

**§14a-e and §14g shipped. §14h is open. §14f needs one check, and my first draft of this document got it
wrong.** §14f was not shipped - it was RULED on 2026-08-19 as "ANSWERED BY §18 and sequenced behind it",
on the reasoning that once §18 ships, `core.md` becomes the pinned driver-owned FLOOR and the growth
region becomes curator-owned, so the ownership contradiction "dissolves rather than being adjudicated".
**§18 has since shipped, but nobody has verified the dissolution actually happened.** A ruling that an
item will resolve as a consequence of other work is not evidence that it did. **Phase 0 must check it and
close or reopen §14f explicitly** - the same discipline this document applies to §17, §18 and §19.

**The genuinely open set:** §14h, §15, §20, §21, §22, §23, §24, §25, plus three items promoted from the
anomalies file at the 2026-08-31 triage.

---

## 2. The batching axis - the decision that shapes everything else

The obvious axis is **shared files**. Five items all edit the same four byte-identical `SKILL.md` pairs:

| item | edits |
|---|---|
| §14h - two skills prescribe a single persona | `agy-first`, `agy-test-audit` |
| §21 - the peer reply contract | all four |
| §23 - AGY-TEST-AUDIT has no ledger | `agy-test-audit` + a new `docs/` ledger |
| §24 - AGY-FIRST mandatory when a capstone develops new code | `agy-capstone` |
| §25 - a negotiation discipline | all four |

Since a plan on plugin-payload code costs a full panel -> capstone -> test-audit cycle, and recent
capstones ran **7, 8 and 11 rounds**, batching by file looks like it saves four review cycles.

**That axis was rejected, and the reasoning is the peer's.** Grouping by file is grouping by storage
location, not by what the instructions DO. These skills are the procedure the capstone itself executes,
so a batch that changes both the review's **output format** and its **conduct rules** forces the capstone
to review its own new rules using its own new rules - and a defect in the JSON contract becomes
indistinguishable from a defect in the negotiation rules. The round cannot converge because it cannot
attribute its own failures.

**The adopted axis is COGNITIVE DOMAIN:**
- **OUTPUT** - what the peer must WRITE DOWN. Mechanical text generation, verifiable by a script.
- **CONDUCT** - how the review is CARRIED OUT. Changes the agent's reasoning and compliance, verifiable
  only by observing behaviour across rounds.

**A caveat the peer did not state, and it applies to the adopted shape too:** any change to the review
disciplines is reviewed *by* those disciplines. Splitting into two batches REDUCES the self-reference; it
does not remove it. Each phase below must therefore state which discipline version reviews it - the one
before its own change, or the one after.

---

## 3. The sequence

### Phase 0 - reconcile the ROADMAP index (prerequisite, not a phase of work)

Correct the §17, §18 and §19 headers to CLOSED with their closing shas, per the earned rule, and
**resolve §14f** - verify by measurement whether §18 shipping actually dissolved its ownership
contradiction, then close it with its evidence or reopen it as live work. No code changes.

This is a prerequisite rather than housekeeping because every later phase cites ROADMAP sections, and a
plan that cites a stale header is a plan built on a false claim about the repository.

### Phase 1 - OUTPUT: §21 then §23

**§21 - the peer reply contract.** The owner has already fixed its internal order and it is committed in
the ROADMAP; it is NOT re-litigated here:
1. the anti-wrap-up clause, shipped standalone into all four skills' closers;
2. the peer-side table shipped as **`claim-type`, not "disposition"** - the payload already ships a
   5-token AGY-SCOPE disposition set at `agy-capstone/SKILL.md:191`, a different axis under the same word;
3. `confidence` shipped as a POINTER with its measured false rate written in;
4. the JSON shipped INLINE plus a checker, separately.

**§23 - the AGY-TEST-AUDIT ledger.** The audit records no audited range anywhere. Note the ROADMAP entry
records that this item's original capture premise was FALSE and the corrected finding is larger; read the
section, do not re-derive it.

**Why OUTPUT goes first, and the reason is stronger than the peer's.** The peer argued §21 is a multiplier
that makes later capstones mechanically verifiable. **Measured 2026-08-31: that multiplier does not exist
yet.** Two findings, both from live consults today:

- **The checker is schema-rigid.** `scripts/check-peer-reply-citations.py:12` hardcodes a ten-key schema
  including `trigger`. The AGY-TEST-AUDIT brief used `missing_test` for that slot - a reasonable
  per-discipline variation - and every row failed on SCHEMA, so **the citation check silently never ran**.
  A control on a capstone reply using `trigger` passed 4/4, so the checker works; it just cannot survive
  a discipline using different keys. **This is a requirement for §21 step 4, discovered by measurement.**
- **The inline reply channel truncates.** The sequencing consult that produced this design returned only
  its `## Anomalies noticed` block and the verdict token; the entire body was lost. It survived solely
  because the peer wrote `reply.md` unprompted. **This is direct evidence for §21's dual prose/JSON file
  output** and against relying on the inline channel.

So every round run before §21 lands is a round whose brief asserts citations are "checked mechanically"
while they are not. That is a False Safety Promise in our own instructions, and it argues for OUTPUT
first more strongly than the multiplier argument does.

**Reviewed by:** the CURRENT discipline versions. Phase 1 changes no conduct rule, so the reviewer is
unchanged by its own subject matter.

### Phase 2 - CONDUCT: §14h, then §24, then §25

**§14h - two skills prescribe a single persona**, so their consults are single-voice by instruction.
`agy-first/SKILL.md:54-56` names one default persona with three ad-hoc alternatives; `agy-test-audit`'s
only lens language is an optional, singular line in a footer section. The ROADMAP entry specifies the
insertion point (`agy-test-audit/SKILL.md`, after the `## The audit round` heading, not the footer) -
follow it.

**§24 - AGY-FIRST becomes mandatory when a capstone round develops new code.** Trigger is mechanical: a
new file, a new function/class declaration, or a whole-function rewrite, in non-test shipped code. It
PAUSES the fold rather than aborting the round.

**§25 - a negotiation discipline in all four review-only skills**, with AGREEMENT explicitly NOT the
criterion; the criterion is EXHAUSTION OF EVIDENCE - one measured round each, then straight to the human.

**Internal order: §14h first.** The peer argued §14h must precede §24 because its seats supply the
independence that defeats §24's rubber-stamp problem. **That justification is overstated and the
conclusion still holds.** A persona is the same model in the same cascade under a different framing; it
is not reviewer independence, and §24's stated problem is about *who* reviews ("the SAME peer ... a design
it endorsed"), not in what voice. But seats demonstrably produce independent findings - the ROADMAP
records the peer finding three defects in a shape it had itself just chosen - so seats MITIGATE. Having
them in place before §24 makes §24 systematically safer, which is reason enough for the order.

**§25 stays in this batch. The owner rejected the peer's recommendation to defer it, on measurement.**
The peer's Resource Vampire objection targets unbounded multi-turn negotiation. The committed §25 is
explicitly bounded - "AGREEMENT is the wrong criterion", "one evidence round each, then straight to the
human". It is arguing against a design that was already refined away, **and the refinement exists because
this same peer argued for it in the previous consult.** A fresh cascade carries no memory of its own
contribution. Its accompanying "15+ rounds" estimate for the rejected shape is speculation, not
measurement, and is recorded as such.

**THE OPEN QUESTION THIS PHASE MUST CLOSE.** §24's STRUCTURAL INDEPENDENCE PROBLEM is owner-deferred to
plan time, and this is plan time: **may the design consult and the review rounds be the same peer?**
§14h shipping first does not answer it - it only softens it. The Phase 2 spec must put this to the owner
explicitly rather than inheriting it.

**Reviewed by:** a discipline version this phase is itself changing. State in the Phase 2 plan whether
each round runs under the pre-change or post-change rules, and do not let a round silently switch.

### Phase 3 - HOOKS: §22 + two promoted backlog items

Three items share a blast radius - plugin hook pairs (`.sh`), mechanical, each with an already-measured
mechanism, and **none touches review-discipline semantics**, so this batch is immune to the
self-reference problem that split Phases 1 and 2:

- **§22** - the leaking redirect order across 16 sites in four plugin hooks. `CMD > "$f" 2>/dev/null` does
  not suppress a failure to OPEN `$f`, because redirections apply left to right; the ROADMAP carries the
  full paired-control table.
- **`agy-mark.sh` accepts a non-existent sha** (`docs/backlog/agy-mark-accepts-a-nonexistent-sha.md`) -
  `head` mode writes any 40-character string with rc=0, so a debounce marker can hold a phantom commit.
  A guard that fails open.
- **Census the executable bit under `scratch/`**
  (`docs/backlog/peer-scratch-dir-contains-executable-session-hooks.md`) - record mode, not content, so a
  new `755` file in the peer's write zone is visible without sanctioned note-writing raising false alarms.

**Why third:** it is independent of the tangle, so it can wait safely, and waiting lets it run under
§21's fixed reply contract and §14h/§25's improved conduct.

**A live instance argues for the third item.** During the AGY-TEST-AUDIT the peer wrote **654 files /
12 MB** into `.clavity/scratch/` and the guard's 8-axis fingerprint did not move at all. That is by
design - `scratch` is censused by name only - but combined with three mode-755 scripts having been wired
as live session hooks from that directory, the write zone is demonstrably both unmonitored and a
code-execution surface. The hooks were un-wired on 2026-08-31, which closed the exposure and not the
question.

### Phase 4 - §15, workflow-position resilience

Spec complete and through **six adversarial panel rounds, all folded**
(`docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md`, committed `4adab8b`). It was
deprioritised, not cancelled, and it was gated on §17a - which has since shipped, so **it is now
unblocked**. Do not restart the design; read the spec. It inherits at least one unresolved gate: the
discipline's NAME waits on a measurement of whether bare `sync` actually flushes on this platform, and at
what cost under concurrent load.

### Phase 5 - §20, a mockable clock (`TimeProvider`) in `AgyView`

C#, touches none of the above. Genuinely independent; ordered last because nothing depends on it and
nothing about it is time-sensitive.

### UNSCHEDULED - `agy_status` misreports an idle peer as working

`docs/backlog/agy-status-reports-working-for-an-idle-peer.md`. This is the third item promoted at the
2026-08-31 triage, and it is **deliberately not given a phase**, for a reason that is itself the finding:
**it is intermittent and does not reproduce on demand.** It answered correctly throughout the whole
AGY-TEST-AUDIT session; the captured evidence is two polls with an unchanged `TotalSteps` returning
`working` while a `flaui` read showed the CLI idle at its prompt.

It is placed here rather than in a phase because scheduling a FIX for a defect with no reproduction is how
a plan acquires an open-ended task. **What it needs first is a reproduction or an instrumented capture** -
and until then it is not plannable, only watchable.

It matters more than its position suggests: it blocks the precheck-idle gate that ALL FOUR review
disciplines open with, and the realistic failure is not waiting forever but learning to ignore the gate -
which then also defeats it for the cases where the peer really is busy. The backlog file records a cheap
interim mitigation available to the driver today, with no code change: **treat an unchanged `TotalSteps`
across two polls as evidence of idleness regardless of the reported state**, which is precisely the
inference that identified the defect.

---

## 4. What this sequence deliberately does NOT decide

- **The content of any phase.** Each carries its own committed ROADMAP section or backlog file.
- **§24's structural independence question.** Named as Phase 2's gating decision, for the owner.
- **Whether §15's naming measurement changes its design.** That belongs to Phase 4.
- **The installed-plugin drift** (`docs/backlog/installed-plugin-drifts-under-an-unchanged-version.md`).
  It caused a real wrong action today - the audit followed a 159-line installed skill whose marker
  contract contradicts the 332-line repo copy, and wrote the wrong marker as a result. It is a live
  hazard for EVERY phase below, because an agent verifies against the instructions it was handed. It is
  not scheduled here, and that is a gap the owner should close deliberately rather than by omission.

## 5. Risks

- **Self-reference is reduced, not removed.** Phases 1 and 2 both edit the disciplines that review them.
  Each plan must state which version reviews it.
- **Phase 2 is the expensive one.** Three items, all four skill pairs, and the only phase whose subject
  matter is the reviewer's own reasoning. If any phase overruns its round budget it will be this one.
- **Phase 1 must actually fix the checker**, not merely ship JSON. If step 4 lands a checker that is still
  schema-rigid, the multiplier that justifies OUTPUT-first never materialises and later phases inherit a
  gate that reports SCHEMA failures instead of checking citations.
- **The peer's advice was 1 of 3 correct on its supporting claims** while its central reframing was
  sound. Later consults in these phases should be read the same way: adopt the reasoning, measure the
  facts.
