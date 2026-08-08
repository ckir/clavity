---
name: adversarial-panel-review
description: Use when a spec, plan, or other high-leverage artifact is drafted or materially edited and needs an adversarial multi-seat review before it is acted on. Convenes a team panel of distinct expert seats, each hunting a different defect-class, over one or more rounds; escalates high-leverage artifacts to the live agy peer; folds verified findings; emits a PANEL VERDICT.
---

# adversarial-panel-review — convene an adversarial panel to tear down an artifact

## When to use
Invoke this skill explicitly ("convene a panel review on `<file>`") whenever a spec, plan, or other
high-leverage artifact has just been drafted or materially edited and needs to be torn down before
anyone acts on it. It is also the skill an AGY-AFTER reminder points at: that reminder only surfaces
the suggestion to run a panel — it does not auto-invoke this skill with arguments, so a bare reminder
is never itself a completed review. A finished artifact review always starts from Step 0 below.

## Inputs & flags
- `target` — path to the artifact under review (a spec, plan, or comparable document).
- `leverage` — `high` or `low`, **defaults to `high`**. This default is fail-safe: an artifact with no
  explicit leverage marking gets the full multi-round treatment plus an agy escalation round, never a
  silently thinner review. Pass an explicit `--solo`/`--low` flag (the two are synonyms for the same
  bypass) to go straight to a single solo panel pass with **no forced question-and-answer step** — there
  is no mandatory prompt an operator could learn to blind-answer. The trigger-gate heuristic in Step 0 is guidance for *when* an operator
  should choose `--low`; it is never itself a mechanism that downgrades leverage on its own.
- **Non-interactive invocation.** A headless run (subagent, background task, or any other non-interactive
  context) still runs the solo panel and every round that needs no human. It ABORTs — rather than pausing
  for an operator who cannot answer — only when it reaches a point that genuinely requires an operator
  decision: the agy-escalation gate with agy down (reports `agy-required-but-unreachable`) or the hard round
  cap (reports `cap-reached`). It never hangs waiting on a human who is not there.

## Procedure

### Step 0 — Trigger gate
The default leverage is `high`, which means multi-round plus agy escalation runs unless told otherwise.
Before launching, answer one concrete question and record the answer: can you name the specific build or
spend this artifact drives? If you can, treat it as high-leverage and run the full treatment. If you plainly
cannot name one, that is the operator's cue to pass `--low`/`--solo` for a single-pass run.
This is a heuristic **cue**, not an automatic downgrade: absent an explicit `--low`/`--solo` flag, the
run stays high-leverage even when no build or spend is named. The fail-safe default is never silently
weakened by this heuristic.

### Step 1 — Solo panel (the floor)
This round always runs, regardless of leverage. Select the top-level persona and the seats for this
panel from the Seat & persona palette below, using its selection rule (the two core seats always seated,
plus every specialist seat whose trigger condition the artifact meets). Convene the selected seats in one
pass: each seat writes under its own heading, in its own voice, hunting a defect-class distinct from every
other seat's. A seat that finds nothing new says exactly that — "no new findings" — it never pads its
section with restated or trivial observations to look useful. Close every panel round, including this
one, with a single-line PANEL VERDICT summarizing the round's outcome.

### Step 2 — agy escalation (high-leverage)
For a high-leverage artifact only, route the artifact to the live agy peer for an independent second-model
panel. Precheck the peer is idle, then send the review request over your driver's review-ask transport using
filepath transport (clavity-dotnet: the `agy_ask` MCP tool, after an `agy_status` idle-check; clavity-classic:
`clavity ask --review-only`): the payload carries the artifact's path plus the panel instructions, not the
artifact's full text — agy reads the named file itself off the shared filesystem. The already-folded ledger
from Step 4, by contrast, has no file backing it and must be inlined as text into the payload. Bind the
scope in the payload as well: instruct agy to review ONLY this artifact, to assume the surrounding codebase
context is correct, and to do no global discovery — this keeps the escalation round from sprawling into an
open-ended codebase exploration.

Every round's review-ask payload inlines the full compact panel protocol (seat list, the "no new findings,
not padding" rule, the verdict format) — never an abbreviated pointer back to an earlier round. Do this on
every round, not just the first, because agy's own working context can be compacted or truncated mid-review,
so a shorthand reference to "the protocol from round 1" can point at something agy no longer has. Sending the
compact protocol whole every time is what keeps the round robust to that truncation.

Frame every question to agy **neutrally**: never embed your own conclusion, preferred option, or a
"confirm that X" premise in what you send — a leading frame biases the peer toward agreeing with you, which
forfeits the entire value of asking a second, independent model. State the open question's options evenly
and ask agy for its own call and reasoning; do not reveal your own lean on that open question until agy has
answered. Let the seats speak in their own voice rather than steering them toward a yes/no answer.

The running already-folded ledger you paste each round (see Step 4) is closed history, not your live
position on an open question, so pasting it does not itself violate neutral framing. Still, keep ledger
entries to the plain factual finding ("X was fixed" / "Y was decided") rather than your own rationale for
it, and present each new open fork on its own merits rather than as "consistent with what we already
decided" — a ledger of past decisions still nudges a peer toward agreeing with your overall direction, so
treat that as a mild, unavoidable bias rather than pretending the peer is a fully blind adversary by the
time you reach a later round.

If the artifact is high-leverage and agy is unreachable, stuck, or the channel is down, **halt and ask the
operator** to restore the channel or explicitly waive this round — never silently fall back to the solo
floor alone and call the review complete. Only the operator may waive an agy escalation. If there is no
operator present to ask (a non-interactive run), abort with a clear failure instead of hanging — a halt-and-
ask only makes sense when a human is actually on the other end of it.

### Step 3 — Fold with verification
Never rubber-stamp a finding. For every finding raised by any seat, verify any bare factual claim by
actual measurement before folding it in — agy in particular can state a false claim with full confidence,
and a panel does not self-check its own consistency, so seats (including across rounds) can flatly
contradict each other or an earlier round without noticing. This applies with special force to any FIX a
seat (or the peer) SUGGESTS, not only to its findings: a correct finding routinely arrives with a WRONG or
INCOMPLETE fix — one that regresses other behaviour or leaves an adjacent edge — so treat a suggested fix as
a fresh claim, verify its full effect before adopting it, and re-run a round after folding because the fix
spawns its own edges (proven live: a peer twice found a real defect while its proposed fix was wrong once and
incomplete the next).

Fold undisputed factual or correctness findings autonomously — do not ping-pong every single fold back to
the operator for approval. Reserve the operator's final call for the case where a finding challenges a
decision the operator has already explicitly settled; any seat may raise that challenge if it has a
substantive reason (a correctness problem, a safety problem, a materially better design, or a hidden
contradiction), but the challenge only gets surfaced to the operator — it is not resolved unilaterally.

When agy disagrees with your own read, you owe it exactly one negotiation turn: push back or counter its
point with something substantive — a specific reason to doubt the claim, a concrete counter-example, or an
alternative reading — and let it respond, then make a binding accept-or-reject call and record why (either
the measurement that settled it, or the reasoning that resolved the disagreement). A hollow "are you sure?"
does not count as that substantive counter-turn; using one to mechanically satisfy the obligation and then
folding anyway is the same rubber-stamping this step forbids in the other direction. Neither instant
capitulation (folding purely because agy asserted something) nor reflexive dismissal (waving a finding off
as "unverified" with no actual counter-argument) is acceptable — engage with genuine respect, but respect is
not the same thing as credulity. This one negotiation turn is a single extra exchange, not a full panel
round: it does not consume or reset the round budget tracked in Step 4/Step 5.

**Frame that counter-turn the way Step 2 frames the review: give it the FILE and LINE and ask what it
measures there — do not paste your own measurement and invite it to concede.** A peer handed your evidence
will agree with your evidence; a peer sent to the source can contradict you, which is the entire reason to
ask a second model. This applies to every consult, not just a panel round: send paths, not conclusions. The
failure mode is quiet and feels productive — you collect a string of concessions, each one confirming what
you already believed, and mistake it for verification. Two signs you are in it: the peer concedes without
citing anything it read, or its findings never surprise you. A peer that has actually opened the file will
sometimes tell you the thing your own review missed.

### Step 4 — Additional rounds
One panel round is the floor, not the ceiling — keep running additional rounds, folding valid findings
between rounds, until a stop condition in Step 5 is met. Count rounds this way: Step 1's solo panel together
with its Step 2 agy escalation is round 1; each additional pass below is round 2, round 3, and so on. This
is the count the hard round cap in Step 5 applies to. Seat rotation across rounds is mechanical, not
free invention: each additional round must add at least one seat from the palette below that has not yet
been used in this review, chosen because it hunts a defect-class the review has not yet covered — it is not
a re-ordering of the same seats from round one, and it is not a bespoke persona invented outside the
palette (aside from the palette's own explicit escape hatch for a sharper bespoke seat when the artifact
genuinely needs one).

In every round, paste the running "already-folded — do-NOT-re-raise" ledger so each seat is hunting a new
defect-class rather than re-deriving something already settled. When the round is an agy escalation, this
ledger must be serialized directly into the review-ask payload text itself, not merely held in your own
working context — agy's context can be truncated over a long review, and a fresh cascade carries nothing
forward, so relying on agy to remember earlier rounds unaided is not safe.

### Step 5 — Stop conditions
Stop the review when any of the following holds:
- Findings dry up — a round produces nothing new worth folding.
- A reviewer's finding turns out to be reasoning from a superseded version of the artifact, and this is
  corroborated against the already-folded ledger (the re-raised point is provably already in that ledger)
  — never on a merely subjective "the reviewer must have misread it" call, which would let a round be waved
  away without real corroboration.
- A full panel round lands with no live challenge at all.

Apply a severity floor against runaway nitpicking: a round that produces only stylistic or trivial
observations — nothing touching correctness, safety, contract behavior, or completeness — counts as "no
live challenge" and stops the panel. The instruction to keep reviewing applies to substantive findings, not
to an unbounded back-and-forth over style between two models. Review is an investment, not a cost to be
minimized, so keep going as long as the panel is still finding substance — never stop early just to save
spend. Standing a finding down on that floor is the `DISCARDED-BELOW-FLOOR` disposition and carries its
evidentiary bar - see "Disposition of findings (AGY-SCOPE)" below.

Independent of the severity floor, apply a hard round cap: by default, at round 3, halt and ask the
operator directly — "still finding substance at round 3, continue or ship?" — rather than looping
unboundedly or silently stopping on your own. This keeps the cap a human decision rather than a spend-saving
auto-stop. (This is the same halt-and-ask mechanism as the agy-escalation gate in Step 2 — stop and ask a
human — but a distinct terminal outcome.) If there is no operator to ask (a non-interactive run), reaching
the cap is itself a hard stop, and the run reports "cap-reached" in its final disposition rather than
continuing or hanging.

## Disposition of findings (AGY-SCOPE)

Every finding raised in any round resolves to EXACTLY ONE of these five tokens. The set is closed -
there is no sixth outcome, and nothing may sit "noted" or "acknowledged".

- `FOLDED: <what changed>` - fixed inside the current work.
- `REJECTED: <measured reason>` - the finding is false, killed by a measurement you quote: a `file:line`
  or the tool stdout.
- `DISCARDED-BELOW-FLOOR: <target> unreachable because <guard>` - contrived, exotic or unreachable. You
  MUST cite the structural guard, invariant or precondition at `file:line` that makes it unreachable.
  Prose alone is not enough; this token carries the same evidentiary bar as `REJECTED`.
- `DEFERRED-TO-ANOMALIES: <anchor> * <YYYY-MM-DD>[ * unverified]` - reachable, not fixed now. `<anchor>`
  is the SOURCE location as `file:line`, or the literal `n/a` when the defect has no single line. The
  date identifies the inbox entry; never cite an inbox LINE NUMBER, because triage deletes entries and
  shifts them. Append ` * unverified` when the captured entry is a `reported, unverified:` claim.
- `UNVERIFIED-ACCEPTED: <finding>` - neither provable nor refutable, and the owner accepted the risk.

**A defect's age is NEVER a disposition.** "Pre-existing", "not introduced by this commit" and "out of
scope for this change" are not admissible stand-down reasons, and neither is any paraphrase of them. The
only admissible stand-down is the reachability floor, which is age-blind. This does not make a bad
stand-down impossible - it forces one to be stated as a falsifiable reachability claim that a peer can
open the file and contradict.

**Scope bound - age-blind reachability from the touched surface.** In scope: the reviewed diff or
artifact, plus the contracts, invariants, schemas and execution paths that INTERSECT it. Out of scope:
open-ended discovery in unrelated modules. If a path or contract touched by the change exposes a defect,
that defect is in scope regardless of when the faulty line was authored.

**Deferral is bounded by CAUSATION, not by line membership.** `DEFERRED-TO-ANOMALIES` is available only
for a defect already reachable BEFORE this change, whose failure mode this change did not induce. Any
failure this change causes must be `FOLDED`, regardless of which line the symptom appears on: a change at
`x.rs:50` that panics untouched `x.rs:120` was caused by the change and is not deferrable.

**A material deferral does not clear a completing verdict on your own authority.** A `MATERIAL` defect
disposed as `DEFERRED-TO-ANOMALIES` needs an owner ruling first, exactly like the UNVERIFIED path. A
`DISCARDED-BELOW-FLOOR` item clears on its own cited guard, because "not material" is what that token
asserts.

**Order matters.** Append to `.clavity/local-anomalies.md` FIRST, via the `open-issues` skill, then emit
the token citing it. A token pointing at an entry that was never written is the rot this replaces. The
peer never writes to that file: a subagent REPORTS, the driver VERIFIES, the driver WRITES.

**Completeness gate.** You may NOT propose a verdict that COMPLETES this run while any raised finding
lacks one of the five tokens. For this skill that means `GREEN`. Note the interaction with the stop
conditions above: those stop the ROUNDS, this gate blocks the VERDICT. A run that stops with findings
untokenized reports the open-findings disposition instead, never `GREEN`.

**Anti-sweep.** Each run lists the top 1-2 findings it discarded below the floor, so a real defect cannot
be swept under the floor unseen. The full list goes in the ephemeral per-run report; a one-line summary of
each goes in a `## Stand-downs` section written into the REVIEWED ARTIFACT itself. This discipline reviews
a pre-implementation artifact and a clean round may produce no commit at all, so the artifact is the only
durable record available. An `UNVERIFIED-ACCEPTED` goes in that same section.

## Seat & persona palette
Pick seats and the panel's overall persona from this palette by rule — never free-invent a seat outside
it except through its own explicit escape hatch. This is the single palette both Step 1 (the first, solo
panel) and Step 4 (each additional round's rotation) draw from.

**Top-level persona (pick one for the panel's overall stance):**
- `relentless-adversarial-auditor` — the default stance for a review of a spec or plan that is still under
  construction.
- `merge-gate-adversarial-auditor` — the stance for a final pre-merge or pre-PR gate, whose job is
  specifically to block the merge if the artifact does not hold up.
- Override with a sharper bespoke persona when the artifact plainly calls for one (a performance skeptic, a
  crypto auditor, and so on).

**Core seats (always seated, every panel):**
- **Axiom Breaker** — hunts contradictory constraints, circular logic, unstated invariants or assumptions,
  scope creep, and decisions that will not survive first real use. Use-when: always.
- **Cascade Analyst** — hunts unhandled failure paths, silent drops, and errors that compound or leak once
  something upstream fails or hangs. Use-when: always.

**Specialist seats (seat each one whose trigger condition the artifact meets; drop the rest):**
- **State Corruptor** — hunts data races, cache staleness, idempotency failures, and out-of-order events.
  Use-when: the artifact manages state, concurrency, async flows, or caching.
- **Boundary Smuggler** — hunts trust bypass, injection, payload spoofing, and unauthorized mutation.
  Use-when: the artifact crosses a trust zone, handles auth, or reads untrusted input.
- **Resource Vampire** — hunts unbounded queues, connection or handle-pool leaks, un-paginated data, and
  quota exhaustion. Use-when: the artifact iterates collections, makes network calls, allocates resources,
  or drives repeated LLM/API calls.
- **Protocol Pedant** — hunts schema mismatch, serialization loss, silent truncation, and rigid parsing.
  Use-when: the artifact defines or consumes a wire contract, API, data schema, or CLI signature.
- **Blindspot Auditor** — hunts misleading logs, irreversible destructive footguns, and missing
  observability. Use-when: a human must configure, deploy, operate, or debug the artifact, especially
  during an outage.
- **Dependency Cynic** — hunts upstream drift, brittle version pinning, missing lockfiles, and environment
  assumptions. Use-when: the artifact introduces a new library or toolchain, or relies on local machine
  state.
- **Literal Implementer** — hunts hand-wavy instructions, deferred "TBD" decisions, un-sized placeholders,
  and non-actionable steps that force the reader to guess. Use-when: the artifact is a spec, plan,
  checklist, or procedural guide meant for an agent or human to execute.
- **Activation Auditor** — hunts broken file globs, regex misfires, vague or over-eager frontmatter
  descriptions, and unreachable or over-eager triggers that stop a component firing (or make it spam).
  Use-when: the artifact defines a skill, git hook, CI trigger, CLI command, or any other auto-discovered
  or auto-routed component.
- **Mechanism Gamer** — hunts rules or gates that are trivially satisfiable without producing the intended
  effect: bypassable checks, gameable quotas, false-GREEN outcomes, and compliance theater. Use-when: the
  artifact defines a rule, gate, quota, or process an agent or human must follow.

**Selection rule:**
1. Pick the top-level persona for the panel's overall stance.
2. Always seat both core seats.
3. Seat every specialist seat whose use-when condition the artifact actually triggers; drop the rest.
   Three to six seats total is the typical range, not a cap — it describes most artifacts. When more
   than that many use-when conditions genuinely fire, seat them all: never drop a seat whose condition
   really triggers just to stay under six. Coverage of a real risk surface always wins over the count.
4. Every additional round (Step 4) must add at least one seat not yet used this review — mechanical
   rotation onto an uncovered defect-class, not a re-ordering of prior seats.
5. The palette is a floor, not a cage: swap in a sharper bespoke seat when the artifact needs a lens the
   palette does not cover. A seat with nothing new to add says so plainly rather than padding its section.
6. Anti-gaming guard: state which use-when triggers actually fired, and which specialist seats were
   consciously dropped and why — declaring "no specialist triggered" on a rich artifact should be visibly
   wrong if it is wrong. A thin panel — only the two core seats, or a rotation seat that is obviously
   irrelevant to the artifact — is not a valid basis for a GREEN verdict (a clean "no live challenge"
   disposition; see Outputs); a GREEN requires that the seated lenses actually cover the artifact's real
   risk surface. Each rotation must add a seat that is genuinely
   relevant — a defect-class plausibly present in the artifact — never the most-irrelevant seat chosen
   just to clear a round quickly. Under-seating a panel to reach GREEN faster is exactly as forbidden as
   padding a panel to look thorough.

## Outputs
- A per-round report: each seated persona's findings under its own heading, closing with a one-line PANEL
  VERDICT for that round.
- A running ledger of folded findings, which feeds directly into the next round's
  "already-folded — do-NOT-re-raise" list.
- A `## Stand-downs` section written into the reviewed artifact, listing each `DISCARDED-BELOW-FLOOR` and
  `UNVERIFIED-ACCEPTED` on one line with its citation. This is the durable record for this discipline,
  which has neither a ledger file nor a guaranteed commit.
- A final disposition — one of: **GREEN** (a full panel round landed with no live challenge); a list of the
  open findings together with the fold decisions made on them; or a failure terminal —
  `agy-required-but-unreachable` (a high-leverage run could not reach agy, and no operator was available to
  waive the escalation) or `cap-reached` (a non-interactive run hit the hard round cap while still finding
  substance).
