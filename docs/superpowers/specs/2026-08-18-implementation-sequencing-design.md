# Implementation sequencing for the open work - design

**Date:** 2026-08-18 · **Status:** owner-approved (sequence confirmed in-chat 2026-08-18); AGY-AFTER
panel rounds 1-2 folded 2026-08-18 - see "Review record". **One folded finding CHALLENGES the approved
step-0-first ordering and is flagged for the owner in step 2, not decided.**
**Type:** SPEC, deliberately not a line-level plan. Several steps depend on code that does not exist yet
and on four owner rulings that have not been made, so per PLAN vs SPEC DISCIPLINE the line-level plan for
each step waits until its predecessor lands.

## Goal

Order the open work to MINIMISE TOTAL COST TO GREEN, where cost is dominated by REVIEW, not by typing.

**Success criterion (how any competing sequence is judged):** fewer separate re-reviews of the
byte-identical plugin pair; the 60 parked inbox entries unblocked earlier; no step started whose shape an
open owner ruling could invalidate; and every step states what must be TRUE before it may begin.

## The cost model - and the measurement that inverted my first instinct

My opening position was to BATCH every byte-identical-pair edit into one carrier commit, paying the
re-capstone once. **That was wrong, and this repository had already measured why.**

`clavity-dotnet/ROADMAP.md:571-573` (verified verbatim 2026-08-18):

> the same 305 turns cost **$249 at ~380k context versus $47 at 40k**, and **a capstone at turn 500 pays
> ~5x the identical capstone at turn 50.** So section 8's framing had it backwards - *batching to the end
> is the expensive direction*; running the review early, at low context, is the cheap one.

**What those figures are measured OVER, because a reviewer got this wrong and the error is
instructive.** Both figures price **the same 305 turns** - they are a per-turn RATE at two context
levels, not the price of one review. `ROADMAP.md:569` supplies the mechanism: **"87.2% of spend is
context re-payment, not generation."** So splitting one body of review work into N smaller reviews does
NOT multiply cost by N; it lowers the rate every turn is charged at. A reader who sees only the ratio can
model this as "N reviews x $47" and conclude batching wins once N exceeds ~5 - a panel seat did exactly
that, and withdrew it on reading the full passage. **State the model, not just the ratio.**

**The one term that DOES grow with N, and is quantified nowhere:** the per-review fixed cost of
re-establishing context - system prompt, the peer re-reading the cited files, the do-not-re-raise ledger
inlined each round. Unbundling wins while that fixed cost stays below what the context multiplier saves.
This spec does not measure it and no step is sized against it, so treat the sequence as **directionally**
supported by the citation, not as an arithmetic proof.

So the governing rule is:

1. **Review cost scales with CONTEXT, not with change count.** Many small reviews at low context beat one
   large review at high context.
2. **Corollary - batch by BLAST RADIUS, never by convenience.** Two changes belong in one review only if
   they share one review surface. Two orthogonal domains in one review force the reviewer to hold the
   whole world in context, which is what produced the 50-round capstone recorded at
   `docs/agy-capstone-ledger.md:55` - a review that fabricated a row name and argued over mutation rows
   encoding opposite failure modes.
3. **Docs-only work (a ROADMAP ruling, a tracked-debt note) does NOT invalidate a capstone.** It is free
   in review terms. Put it first.
4. **Measurements are free too.** A measurement that decides a design is the cheapest artifact available.

## Verified dependencies

Each was checked by reading the cited line, not inferred.

| dependency | evidence | consequence |
|---|---|---|
| **14f before 18** | `ROADMAP.md:1321` core.md "is 100% SEED-shaped"; `:1088-1089` two artifacts disagree who may write it (`drain-lib.ps1:214` "must NEVER touch" vs the curate skill instructing the edit) | Cannot re-architect a file while its ownership is contested |
| **14g before any DRAIN** | `ROADMAP.md:1119` "the repo checkout copy held 30 pending entries and the INSTALLED copy 18, with ZERO overlap" | Draining before unifying paths STRANDS the other copy's entries permanently |
| **17a before 15** | `ROADMAP.md:1228-1229` section 15 "adds a debounce-marker contract to `adversarial-panel-review/SKILL.md` (writing `agy-panel.head`)" | Building 15 first makes it inherit the defective debounce key |
| **17a and 19 share ONE blast radius** | `agy-mark.sh:96` sources `agy-shield-lib.sh` | They are one review surface, so they ship together - this is NOT the batching the cost model forbids |

**Byte-identity verified 2026-08-18** across both plugin trees for all four targets:
`hooks/agy-shield-lib.sh`, `hooks/agy-mark.sh`, `skills/agy-first/SKILL.md`,
`skills/agy-test-audit/SKILL.md` - all IDENTICAL. Any edit to these costs a mirror plus a re-review.

## The sequence

### 0. Merge the branch to `main`

`feature/injected-context-governance`, 329 commits, became mergeable when Stage 2 was ruled GREEN
(2026-08-18). CI has NEVER run on it - every workflow is `branches: [main]` on push.

**Must be true to start:** the owner has authorised the push. CI only fires on push to `main` and the
standing rule is that the owner owns every push, so "nothing" was wrong. **Owner-decided 2026-08-18**
settles the sequencing, not the push itself.
**Why first:** the cost model says land work early rather than accumulate it. Every later step reviewed
on top of an unmerged 329-commit branch pays the high-context multiplier.
**Risk, stated:** CI fires for the first time across 329 commits, so failures arrive in a batch. That is
an argument for merging SOONER, not later - the batch only grows.
**Done means:** merged, CI has RUN, and its result has been READ - not merely that the push succeeded.
**If CI reds, it PREEMPTS the whole sequence.** A red CI on `main` is not a step-0 footnote to work
around; it is the highest-priority work in this document, because every later step's review assumes a
green baseline. Triage the failures, fix or revert, and only then start step 1. Do NOT begin step 1 with
`main` red on the theory that the failures are pre-existing - "pre-existing" is not a disposition
(see the standing rule that pre-existing defects are in scope).
**Fix and revert are not equals, and the slash above hid that.** Reverting a 329-commit merge is a
materially different operation from fixing forward: git records the merge as done, so re-landing the same
branch afterwards is not a repeat of step 0. Prefer fixing forward; if a revert is genuinely required,
treat re-landing as new work with its own review rather than as a retry.
**One prediction worth recording so it can be checked:** the pinned `yq` step has never executed. It is
the single likeliest first failure, and if it fails it proves the value of merging rather than argues
against it.

### 1. The four owner rulings, batched

**14f** (who owns `driver-cheatsheet.core.md`) · **14g** (inbox location) · **17a** (shield debounce key)
· **17b** (pre-push gates read the worktree).

**Must be true to start:** the owner is available.
**Why here:** all four are docs-only, so by cost-model rule 3 they do not invalidate a capstone. **That is
NOT the same as "zero review cost", and an earlier draft of this line conflated the two.** These are the
highest-leverage decisions in the document and three of them gate later implementation, so they warrant
real scrutiny even though they cost no capstone - the cheap thing about them is the review tax, not the
consequence of getting one wrong. Resolving them just-in-time risks a ruling invalidating code already
written.
**Note:** 14f's two candidate fixes are OPPOSITE edits to DIFFERENT files, which is why no spec can
resolve it and it must be a ruling.
**Done means:** all four rulings WRITTEN INTO the ROADMAP entry they belong to, each naming the chosen
option and the reason - not merely decided in conversation. A ruling that exists only in a chat log has
not been made, because the next session cannot see it. 17b's entry must record KILLED or its scope if
kept.

### 2. 13b - make a peer's ANSWER survive truncation

**Must be true to start:** nothing; ready now.
**Why here, ahead of visible progress:** this is the INSTRUMENT every later review depends on. A
truncated or self-truncated peer answer silently degrades every capstone in steps 4-9. Fixing the
measuring device before taking more measurements is worth the delay.
**Known refinement to fold:** the loss is not only transport truncation - the peer can truncate ITSELF
and then assert it did not, so "have the peer write to a file" is insufficient and often impossible for a
review-only peer. The remedy that measured well is driver-side capture plus byte-counting each reply
against that peer's own recent replies.
**Cost class:** touches the discipline skills = byte-identical pair = one re-review. Cheap here, at low
context; expensive if deferred to the end.
**Done means:** driver-side capture of each reply plus a byte-count against that peer's recent replies is
in place, AND a test proves a TRUNCATED reply is DETECTED - not merely that an intact reply passes. A
check that only ever sees whole replies cannot tell truncation from brevity, which is the failure this
step exists to end. **This step needs a failing control more than any other, because it is the step that
makes every later control trustworthy.**

**OPEN OWNER QUESTION - this challenges the already-settled step-0-first ordering, so it is flagged, not
decided.** Two independent readings reached the same conclusion, that 13b belongs BEFORE step 0:
- Step 0's own failure path is a red CI across 329 commits. Triaging and fixing that is code work, so it
  is capstone-gated - meaning step 0's remediation would itself be reviewed with the instrument step 2
  exists to repair.
- Every capstone GREEN already banked was obtained with the same unrepaired instrument, including the
  ones that made this branch mergeable. If a peer can truncate itself and then assert it did not, a clean
  round and a truncated round are indistinguishable from outside. The line above scopes the exposure to
  "steps 4-9"; that scoping is forward-only and unargued.

**What is NOT claimed:** that any specific prior GREEN was in fact truncated. Nobody has measured that.
The claim is only that the sequence currently repairs the instrument after relying on it.
**The exposure is not limited to step 0.** Steps 2 and 6 both declare "nothing; ready now", so nothing in
this document prevents step 6 - or any other step - from being reviewed before the instrument is repaired.
**Every review conducted before step 2 lands carries the same discount**, and the numbering is not a
precondition.
**The owner decides.** Keeping step 0 first stays defensible - it is a one-way door that gets cheaper the
sooner it opens, and nobody has measured that any specific prior GREEN was actually truncated - but it
should be an informed choice rather than an unnoticed one.

### 3. 14g - unify the inbox paths

**Must be true to start:** 14g ruled in step 1.
**Why before step 4:** any drain executed first strands the other copy.
**Live confirmation 2026-08-18:** looking for the parked entries in the REPO copy found an empty file
(0 pending) while the INSTALLED copy held 71. The defect was reproduced by walking into it.

**The unification MUST MIGRATE, not merely re-point.** Unifying by aiming the code at the repo copy would
silently orphan all 71 entries: the repo copy holds 0, so the code would work perfectly and the data would
be gone. **The INSTALLED copy is canonical.**
**Done means:** one inbox path remains; the pre-migration and post-migration totals are both MEASURED and
equal; and the abandoned copy is left in place rather than deleted until a later drain confirms no loss.
**That deferral needs a consumer, and step 4 is it** - see step 4's "Done means". A condition whose
trigger is written in one step and read by none is exactly the defect this document complains about
elsewhere, and the first draft of this line reproduced it.

### 4. Section 18 - the two gating measurements, THEN the SEED/GROWTH split

Section 18's own text names two measurements as prerequisites; run them as step 4a, before any code:

- **Toxicity rate** - how many pending entries are steering hazards. **Define the term before measuring:
  a steering hazard is an entry that, injected into every future ask, would bias the peer toward a WRONG
  answer - not merely a narrow or low-value one.** Classify every pending entry against that definition
  and record the count. If even one qualifies, an ungated drain is the wrong design and the split must
  carry a gate.
  **This classification is a DESIGN input, not a security boundary, and the distinction matters.** The
  entries are untrusted accumulated text, and an agent asked to read them and judge them can be
  instructed by them - an LLM classifying its own untrusted input cannot defend against injection into
  that input. The actual boundary is human approval, and it already exists: `agy-curate/SKILL.md:195-200`
  halts before any runtime write and requires explicit operator approval of the compiled GROWTH, with the
  anti-poisoning circuit-breaker at `:250`. **Step 4 must not be written as though the toxicity count
  were what keeps a poisoned entry out.** The count answers "does the split need a gate?"; the human gate
  answers "may this entry be published?".
- **Override behaviour** - append a deliberate contradiction to the current cheatsheet and measure
  whether the driver privileges the newer rule. **"Reliably" needs a number: run the probe 5 times and
  require 5 of 5.** Anything less is a coin flip dressed as a gate, and this measurement decides whether
  an architecture proceeds. **The number hardens the count, NOT the probe - and a weak contradiction
  passes 5 of 5 trivially.** So the probe needs a FAILING CONTROL: alongside the contradiction, run a
  variant the driver should demonstrably get WRONG, and confirm it does. A probe that cannot return its
  failing answer is not an oracle, and this gate is only as strong as the contradiction someone happened
  to write. **If the driver prefers the SEED fact over the GROWTH rule, the split is
  fatally flawed** - the learning loop cannot steer, and step 4b must not start.

**If a measurement fails, name the fallback rather than halting.** An earlier draft of this paragraph said
a bare halt leaves the entries "in a unified but undrainable file". **That was an overstatement and it is
corrected here:** step 3 migrates INTO the canonical installed copy, so after a halt the entries sit
exactly where they sit today - parked, awaiting the split, no less drainable than on day zero. The real
cost of a bare halt is not corruption, it is that the parked entries stay parked indefinitely with no
route named. So: on an override-behaviour failure the fallback is to keep the current single-region header
and drain manually with owner review per entry; on a toxicity failure the fallback is the gated split
named above. Neither is "stop" - name which applies before starting 4b.

**Must be true to start 4b:** 14f and 14g complete; both measurements pass.
**Payoff:** unblocks the parked entries and takes the per-drain source toll to zero.
**Done means:** both measurements RECORDED with their numbers, not merely their verdicts; the split
shipped or the named fallback adopted; the parked count re-measured after the drain; **and step 3's
abandoned inbox copy either deleted, now that this drain has confirmed no loss, or explicitly kept with a
reason.** Step 3 deferred that decision to "a later drain" and this is the later drain.

### 5. 17a + 19 together

**Must be true to start:** 17a ruled in step 1.
**Why together and only these two:** one blast radius (`agy-mark.sh:96` sources `agy-shield-lib.sh`), so
one review covers both. This satisfies 19's own stated trigger - execute "only when `agy-mark.sh` is next
opened for a FUNCTIONAL change that already pays the cost".
**Constraint carried from 19:** the two distinct stderr messages MUST survive the exit-code collapse.
**Done means:** both plugin variants still byte-identical (asserted, not assumed), both stderr messages
still emitted and still covered by a test, and the collapse reviewed as one surface with 17a.

### 6. 14h - multi-voice consults

**Must be true to start:** nothing; ready now.
**Why isolated:** independent of 17a/19, so giving it its own review keeps each surface small. Blast
radius 4 files (2 skills x 2 variants).
**Done means:** both skills seat a PALETTE rather than a single persona, the two plugin variants remain
byte-identical (assert it, do not assume it), and the change is reviewed. **Beware the measurement trap
this entry already sprang once:** a `grep -c palette` nearly promoted a third skill that was not
defective, because `agy-capstone` mandates seats correctly without ever using the word. Measure
COMPLIANCE, never vocabulary. **And here is the replacement, since forbidding the cheap measurement
without naming another is how "compliance measured" becomes self-certifying:** run each skill against a
fixture artifact carrying two clearly distinct defect classes, and assert the output contains findings
from at least two different personas. That tests the BEHAVIOUR - does it employ multiple lenses - rather
than the vocabulary.

### 7. 17b - pre-push gates read the pushed commits, not the worktree

**Must be true to start:** 17b ruled in step 1, INCLUDING whether it is done at all.
**Flagged for the owner:** this is 10 gates and repo-wide churn for a defect that has not yet been
observed to bite. **KILL is a legitimate outcome** and should be considered explicitly at the step-1
ruling rather than assumed into the plan.
**Interaction worth weighing:** section 14e already records that on a long-lived local branch "CI is not a
safety net, it is a report you get later". If pre-push also measures the worktree, such a branch has
NEITHER gate reasoning about what will land. After step 0 the branch is merged, which reduces - but does
not remove - the exposure.
**Done means:** the step-1 ruling executed - either the gates read the pushed commits and a test pins it,
or the entry is marked KILLED with its reason recorded. Both are legitimate closures; silence is not.

### 8. The policy gate

**Must be true to start:** the two paused owner items resolved. **They are NAMED here, because an earlier
draft referred to "the two paused owner items" without ever saying what they were - which made this step
unstartable from this document alone.** Both live at
`docs/superpowers/specs/2026-08-13-agy-policy-gate-implementation-spec.md:1306-1402`:
- **Item 1** - keep scraping the seam path out of prose, or stop.
- **Item 2** - is the document converging? Rounds 15-19 each produced a defect *caused by the previous
  round's fix*, and `:1373` records that **the sixth defect was found by writing up the fifth**, with no
  seat, no round and no new reviewer.
- `:1377-1381` states the two are **one decision seen twice** - every item-2 defect is a defect of the
  item-1 surface - so settling item 1 dissolves item 2.

**Reframing, and it supersedes the earlier reading.** The panel did NOT fail to converge over 19 rounds;
it converged on a verdict that has not been accepted. **Corroborated at `:1368-1375`**, where the round-19
Convergence Auditor says the document is not converging and the spec's own author agrees with it. The gate
decides using a path SCRAPED FROM PROSE, and a Green-Check seat recorded that "that class never ends (4
silent bypasses in 2 rounds)"; round 17's own optimisation reinstated the exact bypass it was closing.
**That is a design reporting an unbounded defect class, not review churn.**

**CORRECTION, and it is the most serious defect this review found. An earlier draft of this step called
the declared seam parameter "the structural fix" which "deletes the extraction surface entirely". THE
OWNER HAD ALREADY KILLED THAT ARGUMENT IN WRITING, and this step re-imported it from memory rather than
from the file.** `:1320-1333` records the correction: recommending the parameter because it removes the
surface is **"a plumbing argument dressed as a design argument"**. The gate's purpose is that **the ROLES
END UP IN THE AGENT'S CONTEXT**, and a declared parameter **"contributes NOTHING to that"** - it only
makes the hook's job of finding the file reliable. The section that serves the purpose is **N13: the skill
must teach the `PANEL-SEATS:` line, because measured, ZERO skills teach it today.** **Any plan for this
step that omits N13 optimises the plumbing and skips the feature.**

**There are THREE priced dispositions, not one** (`:1384-1397`); this spec previously presented only the
second, as though it were the answer:
1. **Fold and continue** - cheapest per round, needs no decision from anyone, and five rounds have not
   closed the class.
2. **Adopt the declared seam parameter** - ends item 2, costs a tool-contract change this spec does not
   own, creates a new compliance surface (callers must pass it), and **buys nothing for the gate's
   purpose**.
3. **Ship scraped, with the class named and BOUNDED** - state exactly which payload shapes the gate is
   guaranteed to catch and which it is known to miss, so a miss is a documented limit rather than a silent
   fail-open. The policy-gate spec's author leans here (`:1399`) while noting the call is not theirs.

**The scoping measurement below prices option 2 only. It is NOT an argument for option 2.** Run 2026-08-18
at the owner's direction, because option 2 had been deferred as "CHANGES A TOOL CONTRACT" without anyone
pricing it:

- dotnet: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:23` - `AgyAsk(AgyView view, string message,
  CancellationToken cancellationToken = default)` in a **67-line file**. One optional parameter.
- classic: `clavity-classic/src/main.rs:132-133` - `#[arg(long = "review-only")] review_only: bool`,
  threaded at `:279` and `:286`. One more clap arg on the same pattern.
- **An OPTIONAL parameter is additive, so existing callers keep working** - and that is exactly why it does
  NOT "delete the extraction surface entirely". If callers may omit it, the gate must still resolve the
  seam when it is absent, which is the prose-scraping path. **Optional makes the surface CONDITIONAL, not
  absent.** Deleting it requires either a REQUIRED parameter or a hard failure when it is missing, and
  both are larger decisions than the signature.
- **Caller population, measured 2026-08-18:** `agy_ask` has **zero programmatic callers** - the only
  caller is the driving agent reading the tool schema, and the consult-guard hook matches on the tool NAME
  without invoking it. So "existing callers keep working" is a smaller consideration than it sounds, in
  both directions.
- **NOT yet proven, and it must be checked before this is relied on:** that this MCP SDK version emits an
  optional parameter as non-required in the generated schema. **The wiring - the gate consuming the
  declared seam, the skills passing it, and N13's `PANEL-SEATS:` teaching - is the real work, not the
  signature.**

**Done means:** the owner has chosen among the three dispositions and the choice is written into the
policy-gate spec; **and N13 ships regardless of which one is chosen.** An earlier draft conditioned N13 on
dispositions 2 or 3, which was wrong: N13 is what gets the seats into the agent's context, and that is
independent of how the gate locates the seam file. Under disposition 1 it is the only part that improves
the feature at all.

### 9. Section 15 - workflow-position resilience

**Must be true to start:** 17a shipped (step 5), or 15 inherits the defective debounce contract.
Spec is complete and has been through six panel rounds; owner ranked it second priority.
**Done means:** section 15 implemented against the POST-17a debounce contract, with a test pinning the
marker key it writes.

## Corrections to fold while executing

- **Section 18 says 64 parked entries. MEASURED 2026-08-18: 60** (`parked=seed-growth-split-roadmap-18`
  in the INSTALLED inbox). The installed copy also holds 71 pending in total.
- **Section 14g's "30 repo / 18 installed" is now 0 repo / 71 installed.** Both figures are stale; the
  entry's CONCLUSION still holds and is in fact stronger.
- Any step that re-states one of these counts must re-measure it. Every number is stale.

## The AGY-FIRST consult - what it changed, and what was killed

Consulted 2026-08-18, review-only, tree verified unchanged before and after; marker written at `ece919c`.

**Folded (the peer was right and I was wrong):**

- The anti-batching cost model above. My batching instinct was the exact position section 8 had already
  inverted, and the peer found the citation I had missed. **This is the consult earning its cost.**
- "Batch by blast radius, not by convenience" - the distinction that keeps 17a+19 together while keeping
  14h apart.
- Two of the three dependencies in the table above (14f-before-18, 17a-before-15).

**Killed by measurement:** the peer diagnosed the policy gate as stuck because "you are capstoning prose"
and advised stopping agy-capstone against it. **MEASURED: it was PANELLED, not capstoned** - 114 commits
mention "panel round", the policy-gate commits read "fold policy-gate panel round 1..4", and only one
commit pairs a capstone with a spec. Panel is the CORRECT discipline for a spec. Its supporting quote
(ledger:55) was real but belonged to a different artifact - **a true lesson transferred to the wrong
target.** The corrected diagnosis is in step 8 and is sharper than either opening position.

**Gap found in the peer's sequence:** it gave 17b an owner ruling and then never an implementation step.
Step 7 exists because of that omission.

**Citation accuracy:** 10 of 10 resolved exactly when grepped - materially better than this project's
recorded norm, and worth noting as evidence that the per-finding quote rule works.

## Conditions that apply to every step

**Every step must state what happens under an ADVERSE ruling.** Only 17b is currently granted an explicit
KILL. If a step-1 ruling kills or reshapes 14f, 14g or 17a, then steps 3, 4 and 9 lose their preconditions
and this document says nothing about what follows. Before starting step 1, write the adverse branch for
each of the four rulings, even if it is one line.

**Steps 3 and 4 operate on MACHINE-LOCAL state.** The 60-parked / 71-pending figures come from an
installed-program directory outside the repository, outside git, invisible to CI and absent on a fresh
clone. No successor on another machine can reproduce them and nothing in the sequence makes that state
durable. Re-measure on the machine that executes the step; never carry one of these numbers across
machines.

**And "re-measure" is NOT a sufficient mitigation - as first written it CAUSED the failure it warns
about.** A fresh operator resuming at step 4 on a different machine follows that instruction, measures
zero, and drains an empty inbox, permanently stranding the canonical entries on the original machine
while every check passes. **A measurement of 0 here is indistinguishable from a completed drain and from
the wrong machine.** So steps 3 and 4 carry a HANDOFF BOUNDARY: before executing either, record which
machine holds the canonical inbox and its entry count, and **treat a measured 0 as a STOP-AND-VERIFY, never
as "nothing to do"** - the one number that must never be read at face value is the empty one.

**Nothing outside this document reads any of these conditions.** No gate, hook or test notices a step
declared done that is not done. That is the same failure this branch just spent a session closing - the
Stage 2 merge gate stood open for eight days because its completion condition existed only in the artifact
that opened it. **This spec reproduced that shape immediately after the lesson was recorded:** as first
committed it declared ten preconditions and three completion conditions. The "Done means" lines added
across this review are a mitigation, not a mechanism.

**And the round-1 fold's own check that it had closed them was VACUOUS.** It counted occurrences of the
substring "Done means" and reached ten - but one of those ten was this section's own prose REFERRING to
the Done-means lines, so only NINE steps actually had one and step 2 had none. The check confirmed a
number, not a property. **A verification that counts a string rather than the thing the string is meant
to indicate will confirm whatever it is asked to confirm** - and it reads as more trustworthy than no
check at all, because a number was produced. Round 2 caught it by counting line-anchored headings per
step. Step 2's condition is now written. If this sequence is worth enforcing, the enforcement
has to live somewhere a machine looks.

## Review record - AGY-AFTER panel

**Round 1 (solo panel + agy escalation), 2026-08-18.** Persona: relentless-adversarial-auditor. Seats:
Axiom Breaker, Cascade Analyst, Literal Implementer, Mechanism Gamer, Resource Vampire, Protocol Pedant,
Blindspot Auditor, Dependency Cynic.

**Folded in round 1:** the cost model stated rather than cited as a bare ratio; step 0's push
precondition and the fix/revert asymmetry; step 1's "docs-only = zero review cost" conflation; the step-2
ordering challenge (flagged to the owner, not decided); step 3's migrate-don't-re-point requirement;
definitions, a threshold and a fallback for step 4's two gating measurements; a mechanical compliance
check for step 6; step 8's rewrite; and the missing completion conditions.

**Rejected by measurement - all three withdrawn by the peer when sent back to the source:**
- The peer modelled review cost as `N x $47` and concluded batching wins once N exceeds ~5.3. Refuted at
  `ROADMAP.md:570` - both figures price **"the same 305 turns"**, a rate rather than a per-review constant
  - and `:569`, **"87.2% of spend is context re-payment, not generation."** Sent back to the passage, the
  peer withdrew the model *and supplied the term this spec was actually missing*: the per-session fixed
  cost of re-establishing context, which does grow with N. **A wrong claim produced a right correction.**
- The peer found that a drain failing halfway could delete entries without publishing them. Refuted at
  `agy-curate/SKILL.md:257-261` - the procedure already mandates snapshot, compile, publish, and reset the
  inbox **only** on a zero exit.
- The peer claimed a required parameter would break "all existing callers", and this restated the spec's
  own open item 3. Measured: `agy_ask` has zero programmatic callers.

**The sharpest finding came from a GAP, not from a seat.** Both panels noticed that "the two paused owner
items" were referenced and never named. Chasing that gap into the source found that step 8 had re-imported
a rationale the owner had already corrected in writing, presented one of three priced dispositions as if
it were the only one, and omitted N13 - the section the owner identified as the one that actually serves
the gate's purpose. **No seat found this. The missing citation did.** The general lesson: **a spec that
cites a decision without quoting it has not read it, and the unnamed citation is where to look first.**

**Round 2, 2026-08-18** - rotation seats State Corruptor, Activation Auditor and Boundary Smuggler joined
the two core seats, targeting round 1's own fixes. **Three of those fixes were wrong or incomplete:**
- The fallback paragraph in step 4 claimed a halt would leave entries "unified but undrainable". False:
  they sit in the canonical copy, exactly where they sit today. Corrected in place.
- "Re-measure on the machine that executes the step" **caused** the failure it warned about - a fresh
  operator elsewhere measures 0 and drains an empty inbox. Replaced with a handoff boundary and a
  stop-and-verify on a measured zero.
- Step 3's "until a later drain confirms no loss" was a condition with no consumer - the exact defect
  this document complains about, reproduced inside its own fix in the same commit. Step 4 now reads it.
Also folded: the toxicity classification is a design input, not a security boundary (the human-approval
gate at `agy-curate/SKILL.md:195-200` is); N13 belongs under all three dispositions, not just 2 and 3; the
5-of-5 threshold needed a failing control; and the pre-step-2 review discount applies to every step, not
only step 0.

**Round 2's last finding was against round 2 itself, and no seat produced it** - see the vacuous-count
note in "Conditions that apply to every step". A post-fold measurement found it. That is the standing
point restated: a fix is unreviewed work, and the check that blesses a fix is unreviewed too.

**Rejected in round 2:** a seat argued that keeping step 0 first "cannot logically be defensible". That is
an argument for one side of a decision the artifact already surfaces to the owner, not a defect - and its
premise overstates, since nobody has measured that any prior GREEN was truncated. Surfaced, not resolved,
is the correct disposition. A second seat read disposition 2 as buying "absolutely nothing"; it buys the
end of item 2, which the artifact already states.

**Citation accuracy:** 12 of 12 numbered quote-checks across both rounds resolved exactly, including a
deliberate no-such-line control (line 420 of a 388-line file), which the peer correctly reported as
non-existent rather than inventing content for it. One misattribution: a quote genuinely present in this
spec at `:342-343` was cited as `ROADMAP.md:342-343` - right text, wrong file. Every seat finding carried a
matching quote. The quote-or-discarded rule continues to hold citation quality well above this project's
recorded norm.

## Open items this spec does NOT resolve

1. The four step-1 rulings, by construction. **17b's ruling explicitly includes "or kill it"**, and the
   adverse branch for the other three is not written (see "Conditions that apply to every step").
2. The policy gate's two paused owner items.
3. Whether the MCP SDK emits an optional parameter as non-required (step 8, named above) - and, prior
   to that, WHICH of step 8's three dispositions the owner picks, since the SDK question only matters
   under disposition 2.
4. Section 19 executes as part of step 5 rather than standalone; if step 5 is dropped, 19 returns to
   deferred with its original trigger intact.
