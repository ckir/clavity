# Implementation sequencing for the open work - design

**Date:** 2026-08-18 · **Status:** owner-approved (sequence confirmed in-chat 2026-08-18)
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

**Must be true to start:** nothing. **Owner-decided 2026-08-18.**
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
**One prediction worth recording so it can be checked:** the pinned `yq` step has never executed. It is
the single likeliest first failure, and if it fails it proves the value of merging rather than argues
against it.

### 1. The four owner rulings, batched

**14f** (who owns `driver-cheatsheet.core.md`) · **14g** (inbox location) · **17a** (shield debounce key)
· **17b** (pre-push gates read the worktree).

**Must be true to start:** the owner is available.
**Why here:** all four are docs-only decisions - zero review cost by cost-model rule 3 - and three of them
gate later implementation. Resolving them just-in-time risks a ruling invalidating code already written.
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

### 3. 14g - unify the inbox paths

**Must be true to start:** 14g ruled in step 1.
**Why before step 4:** any drain executed first strands the other copy.
**Live confirmation 2026-08-18:** looking for the parked entries in the REPO copy found an empty file
(0 pending) while the INSTALLED copy held 71. The defect was reproduced by walking into it.

### 4. Section 18 - the two gating measurements, THEN the SEED/GROWTH split

Section 18's own text names two measurements as prerequisites; run them as step 4a, before any code:

- **Toxicity rate** - how many pending entries are steering hazards. If even one is, an ungated drain is
  the wrong design and the split must carry a gate.
- **Override behaviour** - append a deliberate contradiction to the current cheatsheet and measure
  whether the driver reliably privileges the newer rule. **If the driver prefers the SEED fact over the
  GROWTH rule, the split is fatally flawed** - the learning loop cannot steer, and step 4b must not start.

**Must be true to start 4b:** 14f and 14g complete; both measurements pass.
**Payoff:** unblocks the parked entries and takes the per-drain source toll to zero.

### 5. 17a + 19 together

**Must be true to start:** 17a ruled in step 1.
**Why together and only these two:** one blast radius (`agy-mark.sh:96` sources `agy-shield-lib.sh`), so
one review covers both. This satisfies 19's own stated trigger - execute "only when `agy-mark.sh` is next
opened for a FUNCTIONAL change that already pays the cost".
**Constraint carried from 19:** the two distinct stderr messages MUST survive the exit-code collapse.

### 6. 14h - multi-voice consults

**Must be true to start:** nothing; ready now.
**Why isolated:** independent of 17a/19, so giving it its own review keeps each surface small. Blast
radius 4 files (2 skills x 2 variants).
**Done means:** both skills seat a PALETTE rather than a single persona, the two plugin variants remain
byte-identical (assert it, do not assume it), and the change is reviewed. **Beware the measurement trap
this entry already sprang once:** a `grep -c palette` nearly promoted a third skill that was not
defective, because `agy-capstone` mandates seats correctly without ever using the word. Measure
COMPLIANCE, never vocabulary.

### 7. 17b - pre-push gates read the pushed commits, not the worktree

**Must be true to start:** 17b ruled in step 1, INCLUDING whether it is done at all.
**Flagged for the owner:** this is 10 gates and repo-wide churn for a defect that has not yet been
observed to bite. **KILL is a legitimate outcome** and should be considered explicitly at the step-1
ruling rather than assumed into the plan.
**Interaction worth weighing:** section 14e already records that on a long-lived local branch "CI is not a
safety net, it is a report you get later". If pre-push also measures the worktree, such a branch has
NEITHER gate reasoning about what will land. After step 0 the branch is merged, which reduces - but does
not remove - the exposure.

### 8. The policy gate

**Must be true to start:** the two paused owner items resolved.

**Reframing, and it supersedes the earlier reading.** The panel did NOT fail to converge over 19 rounds;
it converged on a verdict that has not been accepted. The gate decides using a path SCRAPED FROM PROSE,
and a Green-Check seat recorded that "that class never ends (4 silent bypasses in 2 rounds)"; round 17's
own optimisation reinstated the exact bypass it was closing. Each round closes one bypass and the next
finds another. **That is a design reporting an unbounded defect class, not review churn.**

**The structural fix** is a DECLARED seam parameter (`seam` on `agy_ask`, `--seam` on `clavity ask`),
which deletes the extraction surface entirely.

**Scoping measurement, run 2026-08-18 at the owner's direction, because the fix had been deferred as
"CHANGES A TOOL CONTRACT" without anyone pricing it:**

- dotnet: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:23` - `AgyAsk(AgyView view, string message,
  CancellationToken cancellationToken = default)` in a **67-line file**. One optional parameter.
- classic: `clavity-classic/src/main.rs:132-133` - `#[arg(long = "review-only")] review_only: bool`,
  threaded at `:279` and `:286`. One more clap arg on the same pattern.
- **An OPTIONAL parameter is additive, so existing callers keep working.** The contract change is small.
- **NOT yet proven, and it must be checked before this is relied on:** that this MCP SDK version emits an
  optional parameter as non-required in the generated schema. **The wiring - the gate consuming the
  declared seam, the skills passing it - is the real work, not the signature.**

### 9. Section 15 - workflow-position resilience

**Must be true to start:** 17a shipped (step 5), or 15 inherits the defective debounce contract.
Spec is complete and has been through six panel rounds; owner ranked it second priority.

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

## Open items this spec does NOT resolve

1. The four step-1 rulings, by construction. **17b's ruling explicitly includes "or kill it".**
2. The policy gate's two paused owner items.
3. Whether the MCP SDK emits an optional parameter as non-required (step 8, named above).
4. Section 19 executes as part of step 5 rather than standalone; if step 5 is dropped, 19 returns to
   deferred with its original trigger intact.
