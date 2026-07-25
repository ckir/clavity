---
name: agy-capstone
description: Use ONLY before declaring a plan or implementation COMPLETE - never on routine intermediate commits. Runs a convergent, rounds-until-green adversarial review of the already-COMMITTED code (executable code + tests, not the plan artifact): the peer reasons and cites file:line, the driver measures every finding before folding. A hard round cap plus human-adjudicated GREEN gate the completion claim. Ends with one ASCII [VERDICT] token. Best-effort prompt-discipline, manually invokable; auto-fire is added separately.
---

# agy-capstone - tear down the committed code before you call the plan done

## When to use
Invoke this skill at exactly one moment: **before you declare a plan or implementation COMPLETE.** Its
job is to catch **reachable behavioural defects in the code that actually shipped** - the class a
pre-execution spec/plan review structurally cannot, because that review never runs the code. Review the
**committed implementation** (the executable code and its tests), never the plan artifact.

Do **not** fire it on routine intermediate commits mid-plan - that traps you in premature completion
breakpoints and burns a redundant paid review. One capstone per completion, on the range the plan
produced.

This is **best-effort prompt-discipline, not a sandbox.** The `[VERDICT]` token below is self-reported;
its forcing functions make hollow compliance visible to your human - do not make it impossible. The bar
is "materially better than shipping un-reviewed," not determinism.

Works with or without superpowers - superpowers only adds the auto-fire and the completion breakpoint
where the human adjudicates GREEN. You can always invoke this skill directly; when you do, **surface
every round, finding, and GREEN adjudication to your human in-chat** (there is no breakpoint to defer
to).

## Transport (resolve to your own plugin)
Send every round's consult over your driver's review-ask transport, review-only:
- **clavity-dotnet:** the `agy_ask` MCP tool, after an `agy_status` idle-check (do not fire while the
  peer is busy).
- **clavity-classic:** `clavity ask --review-only` (subagents use the CLI form, not the MCP bus).

## Safety envelope (every consult, no exceptions)
A bare "review-only" once let the peer write to the tree anyway. Wrap each round's consult:
1. **Snapshot before** - capture `git status --short` (and reflog, since the capstone reviews committed
   work).
2. **Forbidden-actions banner** - state in the payload: "REVIEW-ONLY. Do not edit, create, move, or
   delete any file. Do not run mutating commands. Respond with analysis only."
3. **Permission to pass** - the peer may decline or say it needs more; it must not act.
4. **Point at files, not summaries** - write the review brief + the exact commit range to
   `.clavity/seams/<topic>.md` and send the peer the PATH; let it read the committed diff itself. Never
   consult it on a pasted summary of your own reading. Any measure-and-reproduce framing MUST name a
   scratch dir (`.clavity/scratch/<topic>/`) for the peer to work in, so it never writes to cwd.
5. **Diff after** - re-check `git status` AND `git rev-parse HEAD` (plus the reflog tip) against the
   before-snapshot. If the working tree changed, OR HEAD/history moved (a peer `git reset` /
   `git commit --amend` leaves `git status` clean yet mutates the very range under review), the peer
   breached review-only. Because the capstone is a **completion GATE**, a breach is handled more
   strictly than agy-first's advisory skip: (a) surface the breach loudly to your human; (b) revert
   **only the peer-touched paths that were CLEAN in the before-snapshot** (diff the after-state against
   the before-snapshot and restore exactly those) - **never** a blind `git reset --hard` /
   `git checkout -- .`, and **never auto-restore a path that was ALREADY dirty before** (restoring it to
   HEAD would destroy your own uncommitted work - surface such a path in the halt-and-ask instead);
   (c) then **HALT-AND-ASK the human** - do NOT
   auto-proceed and do NOT emit `[VERDICT: SKIPPED-UNREACHABLE]` (that token is reserved for a genuine
   connectivity failure and auto-proceeds the gate; a breach must not silently pass "done"). The human
   decides: re-run the capstone cleanly, or explicitly waive (which writes the WAIVED audit line below).

## Review range (what the peer reviews)
Review the range of commits the just-finished plan produced: `<plan-base>..HEAD`. Resolve `<plan-base>`
from the plan's recorded start - the durable execution index or the plan doc; absent that (a cold manual
invocation), the merge-base with the integration branch, or the last release tag. State the resolved
range explicitly in the brief. Bind the peer's scope: review ONLY that diff, assume the surrounding code
is correct unless it is obviously flawed, no open-ended global discovery.

- **Exclude generated / vendored files.** Drop lockfiles, minified or generated assets, and generated
  manifests from the reviewed diff (a git pathspec `:(exclude)` or a documented exclude list). They are
  not human-authored behaviour; a large generated diff both buries real findings and can overflow the
  reviewer's context.
- **Re-extend the range after every fold.** Each round's folded fixes are themselves new committed code,
  so re-capture `HEAD` and extend the range to cover the fix commits. The final clean round MUST cover
  those fix commits before you may declare GREEN - otherwise you green a `HEAD` whose newest commits (its
  own fixes) were never reviewed. The marker records that post-fold reviewed `HEAD`.

## The convergent round (creative-adversarial teardown)
The loop converges (rounds-until-green), but the **defect discovery inside each round must be creatively
adversarial**, or the capstone degrades into a rote checklist that misses the non-obvious reachable
defect that is its entire reason to exist. Frame each round's consult with named adversarial seats +
forcing functions, not a flat "find bugs":

- **Seats (defect-class lenses).** Seat the proven adversarial-panel-review personas - Axiom Breaker
  (contradictions / unstated invariants), Cascade Analyst (unhandled failure paths), Mechanism Gamer
  (gameable gates / false-GREEN), Protocol Pedant (contract / serialization), State Corruptor, Boundary
  Smuggler, and the rest - pointing each at the COMMITTED CODE, seating those whose trigger the diff
  meets. Override with a sharper bespoke lens when the diff calls for it. This reuses the persona
  vocabulary; it is not a code dependency on the panel skill.
- **Forcing functions (creative, not checklist).** Each seated persona must produce a **reachable**
  defect citing **file:line** - invert the happy path (what input / state / sequence breaks this?), the
  hostile or malformed input, the concurrent / re-entrant / out-of-order case, the boundary / empty /
  zero / overflow case, a cross-domain failure analogy - never a contrived or exotic edge.
- **Reachability floor.** Stop nitpicking: a round producing only stylistic or contrived-edge
  observations - nothing touching correctness / safety / contract / completeness - counts as no live
  challenge.
- **Rotate seats across rounds.** Each additional round seats at least one lens not used in a prior
  round, so the loop surfaces NEW defect-classes instead of re-deriving covered ones.

Send the peer the committed range + this framing + the do-not-re-raise ledger; ask it to enumerate
reachable defects citing file:line. **Commit before the next round:** the peer reviews COMMITTED code, so
`git commit` every measurement-verified fold-fix BEFORE re-capturing `HEAD` and launching the next round
- a fix left uncommitted sends the peer the identical broken diff and it re-raises the defect.

Intermediate fold-and-loop rounds report progress and loop; they emit **no** token. You emit a
`[VERDICT]` token only at a terminal disposition or completion proposal (below).

## Division of labor: peer REVIEWS, driver MEASURES (the spine)
The peer must **never run the test suite** - execution is driver-side, once.
- **Peer role:** reads the committed diff and reasons - enumerates reachable defects, cites file:line,
  predicts what breaks under what input/state. It does not execute tests or the code.
- **Driver role:** for every peer finding, **you** run the relevant test / probe and **quote the measured
  stdout** (or the file line) that confirms or kills the finding *before folding it*. A fold with no
  quoted measurement is visibly hollow. The peer states false claims with full confidence; your
  measurement is what makes a fold safe.

**Unmeasurable findings.** If a finding can be neither run nor resolved by reading the cited line, FIRST
attempt a targeted repro/probe in the scratch dir (`.clavity/scratch/<topic>/`) to make it measurable. If
it is still genuinely unmeasurable, surface it to your human as **UNVERIFIED** - never silently fold it
as verified, never silently drop it. A material UNVERIFIED finding blocks a clean `[VERDICT: ALIGNED]`
until the human rules. The ruling is a **per-finding disposition, distinct from the global waiver below**:
either (a) direct a fix (folded next round), or (b) explicitly ACCEPT the risk, appended as a durable
audit line to `.clavity/agy-marks/skipped.log` (the same audit log the skip and waiver paths use; create
`.clavity/agy-marks/` first if absent): `<iso-8601>  agy-capstone  UNVERIFIED-ACCEPTED  HEAD=<sha>  <finding>`.
This line does NOT write the completion marker and does NOT abort the capstone - the loop continues and
can still reach ALIGNED.

## Do-not-re-raise ledger
Keep a running list of already-folded and already-refuted findings, and **inline it into every round's
brief** (the peer's context can truncate across a long review; a shorthand "see round 1" can point at
something it no longer holds). Ledger entries are plain factual findings, not your rationale.

## Round cap + human-adjudicated GREEN + override re-entry
- **`MAX_CAPSTONE_ROUNDS = 3` (tunable).** At the cap, **halt and ask your human** ("still finding
  substance at round 3 - continue or ship?") rather than looping or silently stopping.
- **GREEN is human-adjudicated** - you cannot self-declare it. A self-reported clean round is a proposal
  the human confirms or rejects at the superpowers completion breakpoint (or in-chat under manual
  invocation, which has no breakpoint).
- **Write on resume, not on the proposal.** Your session persists across the adjudication pause. AFTER
  the human confirms GREEN, resume and write the marker (below) as your next action; do NOT stop dead at
  the proposal, and do NOT write on an unconfirmed proposal.
- **Override re-entry.** If the human rejects a proposed GREEN or names an unaddressed defect, **re-enter
  capstone rounds on that defect** rather than closing the book. A human "continue" / re-entry answer
  AUTHORIZES that ordered work; the cap does NOT re-halt inside the authorized extension. The
  halt-and-ask re-triggers only if, after the authorized extension, findings are STILL live and no fresh
  override is given - so the ceiling holds without trapping you in an instant re-prompt loop.

## AGY-NEGOTIATE (auto-fires on material disagreement)
When a **material** disagreement (architecture / performance / security - never style / naming / trivia)
surfaces inside a round, run AGY-NEGOTIATE **immediately** - the moment a
`[VERDICT: NEGOTIATE - <reason>]` is emitted or you reject a peer finding you deem material. Do NOT wait
for the human to ask, and do NOT kick the raw disagreement to the human as a fork-question.
- **Round cap:** `MAX_NEGOTIATE_ROUNDS = 2`. Round 1: you present measured evidence, the peer counters.
  Round 2: you attempt a synthesis taking the best of both.
- **Impasse:** if not converged at the cap, declare IMPASSE, document both positions in-chat (each with
  its measured support), and hand the human the tie-break. Do not fabricate agreement.
- The human is brought in only on IMPASSE, or is shown the already-CONVERGED result. "negotiate with agy"
  stays a manual backstop.

## The [VERDICT] tokens (ASCII only, emitted by disposition)
ASCII only - no em-dash or other non-ASCII (mojibake risk; this project has hit corruption). You (the
driver) emit these, keyed to disposition, not a fixed count:
- `[VERDICT: ALIGNED]` - a **clean terminal round**: every finding across the run has a disposition -
  folded (fixed + measured clean), killed by measurement (`[VERDICT: REJECTED - ...]`), or explicitly
  human-accepted as an UNVERIFIED risk - and no material unrefuted defect remains. A run whose findings
  were ALL refuted-by-measurement IS `ALIGNED` (a peer hallucination you kill does not block completion,
  else "run until green" with an eager peer loops forever inventing fresh refuted findings). This
  PROPOSES completion; the human adjudicates GREEN. It **MAY RECUR** - if the human rejects it and you
  re-enter rounds, you propose `ALIGNED` again after the next clean round.
- `[VERDICT: REJECTED - <measured reason>]` - a **per-finding disposition**, not a terminus: a specific
  peer finding killed by your measurement, quoted and ledgered. It does NOT halt the loop; the run still
  terminates as `[VERDICT: ALIGNED]` once a round is clean.
- `[VERDICT: NEGOTIATE - <material reason>]` - a material disagreement remains at impasse; run
  AGY-NEGOTIATE above. A peer merely REPORTING defects is NOT this - that is the normal case you verify,
  fold, and loop on.
- `[VERDICT: SKIPPED-UNREACHABLE]` - the consult could not run (genuine connectivity failure only; below).

**GREEN is a human-adjudicated meta-state, not a token.** A terminal `[VERDICT: ALIGNED]` is a proposal;
GREEN is reached only when the human confirms the clean terminal round.

## If the peer is unreachable
No live peer / no auth / the idle-check never clears: emit `[VERDICT: SKIPPED-UNREACHABLE]` and
**proceed** - never hang, never hard-block "done". Make the skip loud and durable: (a) tell your human
in-chat that the completion **gate was skipped** and name the range it did not review; (b) create
`.clavity/agy-marks/` if absent (gitignored runtime state - a bare `>>` append would fail on a fresh
clone), then append one durable line to `.clavity/agy-marks/skipped.log`
(`<iso-8601>  agy-capstone  SKIPPED-UNREACHABLE  HEAD=<sha>`, where `<sha>` is `git rev-parse HEAD` or
the literal `none` if HEAD cannot resolve); (c) write NO consulted marker, so the next trigger retries.

**A review FAILURE is not an unreachable peer.** `[VERDICT: SKIPPED-UNREACHABLE]` is reserved for a
genuine connectivity failure. A review that fails because the diff is **too large to review** (context /
API overflow), or any other non-connectivity crash, is NOT that - treating it as skip-and-proceed would
let a diff-bomb silently BYPASS the completion gate. **Halt-and-ask the human** instead (chunk the
review, or the human decides); never auto-proceed.

## Debounce marker (hook contract - written here, read by the auto-fire hook)
Record the terminal state so the auto-fire hook (shipped separately) does not re-inject the capstone for
the same `HEAD`. Create `.clavity/agy-marks/` first if it does not exist.
- **Path:** `.clavity/agy-marks/agy-capstone.head` - a single discipline-keyed marker, no `<plugin-id>`
  prefix (Option S, as for agy-first: the byte-identical body cannot carry a per-plugin literal and the
  two drivers are mutually exclusive). See `docs/agy-disciplines-marker-contract.md`.
- **Content:** the output of `git rev-parse HEAD` at the terminal state, nothing else. If HEAD cannot
  resolve, skip writing the marker (the discipline re-fires next trigger - safe).
- **Written ONLY on the terminal state** - human-confirmed GREEN **or** explicit human waiver. A
  self-declared round-ALIGNED not yet confirmed, an override re-entry still in progress, or a
  `[VERDICT: SKIPPED-UNREACHABLE]` / breach writes **no** marker. A new commit (new HEAD) re-arms the
  gate.
- **A human WAIVER also appends a durable audit line** to the same log the skip path uses
  (`<iso-8601>  agy-capstone  WAIVED  HEAD=<sha>`), so a mechanically-verified GREEN and a human waiver -
  which write the same bare-sha marker - stay distinguishable in the durable record. The marker content
  stays the bare sha (the auto-fire hook reads `content == current HEAD`; encoding `WAIVED` into the
  marker would break that read).

`.clavity/` is runtime state and is gitignored - never commit a marker.
