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

## Completeness checks the DRIVER runs on your reply (13b)

**NAME YOUR DISCIPLINE ON EVERY ASK.** On clavity-dotnet pass `discipline: "agy-capstone"` to `agy_ask`; the driver
owns the terminal-token table and applies this discipline's checks itself. You never type the token, so you
cannot mistype it into a silent opt-out. An ask that names no known discipline comes back with a
`[13b] UNCHECKED` notice saying the checks did not run.

**Every payload that names a PRIMARY ARTIFACT must demand a SEMANTIC ECHO.** Add, as the second-to-last
instruction:

> Immediately before your terminal verdict, quote verbatim the LAST NON-BLANK LINE of
> `<the primary artifact path>` that carries actual content. Quote it exactly; do not paraphrase or
> summarise it.

Then pass that same line to the ask as `expectEcho`, having read it yourself from the same file. The
driver compares them and reports `[13b] ECHO MISSING` when they disagree.

**PICK A LINE WITH SUBSTANCE - a bare `}` proves NOTHING.** The literal last non-blank line of a SOURCE
file is almost always a closing brace, a fence, or a rule, and any peer can emit one without reading a
word. The driver rejects such a target: an expectation carrying fewer than 8 letters or digits is
reported as `[13b] ECHO WEAK` and the echo check is SKIPPED rather than failed - failing it would punish
the peer for a target YOU chose. So for a code artifact, walk back to the last line that says something,
or omit the echo and rely on the other checks. This is measured, not theoretical: it was found on the
first live consult that used the echo, where the artifact was a `.cs` file.

**Why this and not a nonce.** A nonce you invent proves only that the peer read your BRIEF. The
artifact's last line proves it reached the END of the thing under review - which is exactly what a
truncated or unread review cannot do.

**When there is no primary artifact** - a design question, a pasted fork with no file - omit the demand
and pass no `expectEcho`. The check degrades to satisfied rather than to failed, deliberately: a guard
that reds on consults it was never meant to cover gets disabled, and then it covers nothing.

**A reply the driver flags is INCOMPLETE, not empty.** Never read a `[13b] TRUNCATED REPLY` or
`[13b] ECHO MISSING` as "no findings" - recover the reply or re-ask.

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
   Prepare BOTH through the shipped writer before writing into them. Each takes a concrete FILE path,
   never a directory - passing `scratch/<topic>/` would create `.clavity/scratch` and not
   `.clavity/scratch/<topic>`, and the next write would fail mid-run:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "seams/<topic>.md"; then
  # ABORT the discipline and say why. A skill that ignores this exit code converts a clean refusal
  # into a mid-run crash on the next write.
  echo "agy-capstone: ABORTING - could not prepare a shielded .clavity/ directory for seams/<topic>.md." >&2
  exit 1
fi
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "scratch/<topic>/notes.md"; then
  echo "agy-capstone: ABORTING - could not prepare a shielded .clavity/ directory for scratch/<topic>/notes.md." >&2
  exit 1
fi
```

`<BASE>` is this skill's own base directory, as the harness supplies it at invocation time. It is NOT
`$0` and NOT `${BASH_SOURCE[0]}`: measured, in an agent-run shell snippet those give `/usr/bin` and the
empty string, so a path built from them resolves nowhere.
5. **Diff after** - re-check `git status` AND `git rev-parse HEAD` (plus the reflog tip) against the
   before-snapshot. If the working tree changed, OR HEAD/history moved (a peer `git reset` /
   `git commit --amend` leaves `git status` clean yet mutates the very range under review), the peer
   breached review-only. Because the capstone is a **completion GATE**, a breach is handled more
   strictly than agy-first's advisory skip: (a) surface the breach loudly to your human; (b) make a
   **best-effort** revert of the peer's changes to paths that were CLEAN in the before-snapshot (diff the
   after-state against the before-snapshot; `git checkout --` a peer-MODIFIED tracked path, and delete
   (recursively if a directory, in your shell's own idiom - NOT a hardcoded `rm -rf`, which a non-POSIX
   shell like PowerShell rejects) a peer-CREATED untracked path) - **never** a blind `git reset --hard` / `git checkout -- .`, and
   **never auto-restore a path that was ALREADY dirty before** (that would destroy your own uncommitted
   work - surface it in the halt-and-ask instead). This revert is **best-effort, not guaranteed**: the
   envelope is review-only prompt-discipline, NOT a sandbox, so a determined breach (a destructive
   `reset` / `amend`, or a mutation of an already-dirty file that the status-only snapshot cannot fully
   diff) may not be cleanly recoverable - that accepted residual is why the peer is review-only-TRUSTED
   and the human is HALTED, not a reason to build a sandbox;
   (c) then **HALT-AND-ASK the human** - do NOT
   auto-proceed and do NOT emit `[VERDICT: SKIPPED-UNREACHABLE]` (that token is reserved for a genuine
   connectivity failure and auto-proceeds the gate; a breach must not silently pass "done"). The human
   decides: re-run the capstone cleanly, or explicitly waive the breach - a **SKIP-equivalent**: it
   proceeds WITHOUT a clean capstone, writes a `WAIVED ... reason=breach` audit line but **NO completion
   marker** (so the gate re-arms next trigger), and does NOT mark the plan reviewed. A breach-waiver is
   therefore NOT a way to pass "done"; only a clean GREEN or a round-cap gate-waiver passes the gate.

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
  challenge. Standing a finding down on that floor is the `DISCARDED-BELOW-FLOOR` disposition and carries
  its evidentiary bar - see "Disposition of findings (AGY-SCOPE)" below.
- **Rotate seats across rounds.** Each additional round seats at least one lens not used in a prior
  round, so the loop surfaces NEW defect-classes instead of re-deriving covered ones.

Send the peer the committed range + this framing + the do-not-re-raise ledger; ask it to enumerate
reachable defects citing file:line. **Commit before the next round:** the peer reviews COMMITTED code, so
`git commit` every measurement-verified fold-fix BEFORE re-capturing `HEAD` and launching the next round
- a fix left uncommitted sends the peer the identical broken diff and it re-raises the defect.

Intermediate fold-and-loop rounds report progress and loop; they emit **no** token. You emit a
`[VERDICT]` token only at a terminal disposition or completion proposal (below).

**Every payload MUST carry THREE to FOUR OPEN QUESTIONS the peer answers in its own words** - never a
checkbox, never a yes/no, and never a question whose expected answer is stated in the payload. One
question is not enough: it lets the peer answer the easiest and stop. Draw them from these four shapes,
each of which produced a real finding on 2026-08-19:

1. **Disagree with my guess.** State where YOU think the weakness is, then ask the peer where IT thinks
   it is and to say plainly if you are wrong. (Produced an 8-row case matrix, and a correction that a
   proposed fix would have destroyed the property it was fixing.)
2. **A disposition I have not named.** "Is there an option neither this artifact nor I have named?" A fork
   stated as N options is often really N+1. (Produced a third disposition that dissolved a ruling.)
3. **Reject the frame.** "Is the signal / metric / approach I have chosen even the right one?" (Produced
   the largest single design change of that session - the chosen signal was wrong and the peer said so.)
4. **Permit ignorance explicitly.** "If you cannot explain this, say so plainly rather than constructing a
   story." (Produced an honest known-unknown instead of a confident fabrication - the peer had already
   fabricated once that day.)

**A payload whose questions all have knowable answers is not asking anything.** If you can predict every
answer, you are seeking agreement, not review.

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
lacks one of the five tokens. For this skill that means `[VERDICT: ALIGNED]`.

**Anti-sweep.** Each run lists the top 1-2 findings it discarded below the floor, so a real defect cannot
be swept under the floor unseen. The full list goes in the ephemeral per-run report; a one-line summary of
each goes in the committed `docs/agy-capstone-ledger.md` row for this run. An `UNVERIFIED-ACCEPTED` is
recorded as a durable line in `.clavity/agy-marks/skipped.log`, in the existing format.

## Division of labor: peer REVIEWS, driver MEASURES (the spine)
The peer must **never run the test suite** - execution is driver-side, once.
- **Peer role:** reads the committed diff and reasons - enumerates reachable defects, cites file:line,
  predicts what breaks under what input/state. It does not execute tests or the code.
- **Driver role:** for every peer finding, **you** run the relevant test / probe and **quote the measured
  stdout** (or the file line) that confirms or kills the finding *before folding it*. A fold with no
  quoted measurement is visibly hollow. The peer states false claims with full confidence; your
  measurement is what makes a fold safe.

**Unmeasurable findings.** If a finding can be neither run nor resolved by reading the cited line, FIRST
attempt a targeted repro/probe in the scratch dir (`.clavity/scratch/<topic>/`) to make it measurable.
Prepare that directory through the shipped writer first, passing a concrete FILE inside it - never the
directory itself, which would create `.clavity/scratch` and not `.clavity/scratch/<topic>`:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "scratch/<topic>/notes.md"; then
  # ABORT the discipline and say why. A skill that ignores this exit code converts a clean refusal
  # into a mid-run crash on the next write.
  echo "agy-capstone: ABORTING - could not prepare a shielded .clavity/ directory for scratch/<topic>/notes.md." >&2
  exit 1
fi
```

If
it is still genuinely unmeasurable, surface it to your human as **UNVERIFIED** - never silently fold it
as verified, never silently drop it. A material UNVERIFIED finding blocks a clean `[VERDICT: ALIGNED]`
until the human rules. The ruling is a **per-finding disposition, distinct from the global waiver below**:
either (a) direct a fix (folded next round), or (b) explicitly ACCEPT the risk, recorded as a durable
audit line through the shipped marker writer - the same audit log the skip and waiver paths use. The
script owns the timestamp and the line format; pass the finding as trailing text:

```bash
bash "<BASE>/../../hooks/agy-mark.sh" log "agy-capstone" "UNVERIFIED-ACCEPTED" "$(git rev-parse HEAD)" "<finding>"
```

This line does NOT write the completion marker and does NOT abort the capstone - the loop continues and
can still reach ALIGNED.

## Do-not-re-raise ledger
Keep a running list of already-folded and already-refuted findings, and **inline it into every round's
brief** (the peer's context can truncate across a long review; a shorthand "see round 1" can point at
something it no longer holds). Ledger entries are plain factual findings, not your rationale.

## Round cap + human-adjudicated GREEN + override re-entry
- **`MAX_CAPSTONE_ROUNDS = 6` (tunable).** At the cap, **halt and ask your human** ("still finding
  substance at round 6 - continue or ship?") rather than looping or silently stopping.
- **GREEN is human-adjudicated** - you cannot self-declare it. A self-reported clean round is a proposal
  the human confirms or rejects at the superpowers completion breakpoint (or in-chat under manual
  invocation, which has no breakpoint).
- **Write on resume, not on the proposal.** Your session persists across the adjudication pause. AFTER
  the human confirms GREEN, resume and write the marker (below) as your next action; do NOT stop dead at
  the proposal, and do NOT write on an unconfirmed proposal. **Write the sha you REVIEWED, not ambient
  HEAD:** capture `git rev-parse HEAD` at the ALIGNED proposal and write THAT sha. If HEAD MOVED during
  the adjudication pause (the human committed while you waited), that new commit is UNREVIEWED - do NOT
  write the marker; re-enter a capstone round on the new HEAD instead. Writing ambient HEAD would green an
  unreviewed commit.
- **Record the round in `docs/agy-capstone-ledger.md` before declaring the plan complete.** One row:
  date, commit range, round count, verdict, and evidence that is independently checkable (fold commits,
  or the review transcript). `none` is not a permitted evidence value - a clean first round still
  produces a transcript, so cite it. Without this row a green capstone is indistinguishable from one
  that never ran, which is precisely the gap this ledger exists to close.
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

**A CLEAN ROUND IS A COVERAGE CLAIM, NOT A RESULT.** Before accepting one, ask what was NOT examined -
which files went unread, which behaviours were never exercised, which lens was not applied. A round that
finds nothing has told you about its own coverage, not about the artifact. Measured 2026-08-19: of two
clean rounds in one session, both later proved to have missed a real defect that hand-enumeration found.

## The [VERDICT] tokens (ASCII only, emitted by disposition)
ASCII only - no em-dash or other non-ASCII (mojibake risk; this project has hit corruption). You (the
driver) emit these, keyed to disposition, not a fixed count:
- `[VERDICT: ALIGNED]` - a **clean terminal round**: every finding across the run carries one of the five
  AGY-SCOPE disposition tokens above - `FOLDED`, `REJECTED`, `DISCARDED-BELOW-FLOOR`,
  `DEFERRED-TO-ANOMALIES` or `UNVERIFIED-ACCEPTED` - and no material unrefuted defect remains UNRULED: a
  material `DEFERRED-TO-ANOMALIES` needs the owner's ruling before this verdict, while a
  `DISCARDED-BELOW-FLOOR` clears on its own cited guard. A run whose findings
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
in-chat that the completion **gate was skipped** and name the range it did not review; (b) append one
durable audit line through the shipped marker writer, which owns the timestamp and the line format and
creates the directory it writes into:

```bash
bash "<BASE>/../../hooks/agy-mark.sh" log "agy-capstone" "SKIPPED-UNREACHABLE" "$(git rev-parse HEAD)"
```

(c) write NO consulted marker, so the next trigger retries.

**A review FAILURE is not an unreachable peer.** `[VERDICT: SKIPPED-UNREACHABLE]` is reserved for a
genuine connectivity failure. A review that fails because the diff is **too large to review** (context /
API overflow), or any other non-connectivity crash, is NOT that - treating it as skip-and-proceed would
let a diff-bomb silently BYPASS the completion gate. **Halt-and-ask the human** instead (chunk the
review, or the human decides); never auto-proceed.

## Debounce marker (hook contract - written here, read by the auto-fire hook)
Record the terminal state so the auto-fire hook (shipped separately) does not re-inject the capstone for
the same `HEAD`. Write the marker through the shipped writer, never by hand: it asserts the `.clavity/`
shield BEFORE the write and creates the directory it writes into.

```bash
bash "<BASE>/../../hooks/agy-mark.sh" head "agy-capstone" "$(git rev-parse HEAD)"
```

- **Path:** `.clavity/agy-marks/agy-capstone.head` - a single discipline-keyed marker, no `<plugin-id>`
  prefix (Option S, as for agy-first: the byte-identical body cannot carry a per-plugin literal and the
  two drivers are mutually exclusive). See `docs/agy-disciplines-marker-contract.md`.
- **Content:** the REVIEWED sha - the `git rev-parse HEAD` captured at the human-confirmed GREEN (or
  round-cap waiver) for the range that was ACTUALLY reviewed, nothing else - NOT an ambient HEAD
  re-sampled at write time if code was committed during the adjudication pause (see the mid-adjudication
  rule above). If HEAD cannot resolve, skip writing the marker (the discipline re-fires next trigger - safe).
- **Written ONLY on a GATE-SATISFIED terminal state** - human-confirmed GREEN, or an explicit human
  **completion-gate waiver** (`round-cap`: the human accepts "done" despite still-live findings). A
  self-declared round-ALIGNED not yet confirmed, an override re-entry still in progress, a
  `[VERDICT: SKIPPED-UNREACHABLE]`, **or a review-only breach (waived or not)** writes **no** marker - a
  `breach` waiver is a SKIP-equivalent (the human chose to proceed without a clean review; the gate is
  NOT satisfied), so it re-arms next trigger. This closes the bypass where a peer forces a trivial breach
  to smuggle unreviewed code past a waive. A new commit (new HEAD) re-arms the gate.
- **Every human WAIVER appends a durable audit line** to the same log the skip path uses
  (`<iso-8601>  agy-capstone  WAIVED  HEAD=<sha>  <reason>`, `<reason>` = `round-cap` | `breach`). A
  `round-cap` completion-gate waiver ALSO writes the `.head` marker (it accepts "done", like a confirmed
  GREEN); a `breach` waiver writes ONLY this audit line and **NO marker** (a skip-equivalent - the gate
  is not satisfied and re-arms next trigger). So a mechanically-verified GREEN, a gate-waiver, and a
  breach-waiver stay distinguishable in the durable record. The marker content
  stays the bare sha (the auto-fire hook reads `content == current HEAD`; encoding `WAIVED` into the
  marker would break that read).

`.clavity/` is runtime state and is gitignored - never commit a marker.
