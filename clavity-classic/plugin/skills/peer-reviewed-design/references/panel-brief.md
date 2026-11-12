# The adversarial panel over an artifact

Run a panel on every finished design doc, plan or roadmap, and on every material revision of one,
before the owner sees it. A panel is the review floor, not the ceiling: one round is never enough,
and a clean round is a coverage claim, not a result.

## Round structure

Round 1 is your own solo pass plus the peer's escalation. Run the builder check (a fresh subagent
with no conversation context, asked only for the questions a wrong guess would make matter) in the
same turn as the peer's round 1; they converge often, and their overlap is itself evidence of a
real gap. Each later round:

- rotates in at least one seat not used before, chosen for a defect class not yet covered,
- opens with a FOLD AUDITOR aimed only at the previous round's folds, enumerated (a), (b), (c), because
  a fix spawns its own edges and a generic "check recent fixes" does not find them,
- carries the full do-not-re-raise ledger as text in the payload (the peer's context can be
  truncated; a pointer to "the ledger" is not a ledger),
- ends when a round has no live challenge, or when the findings are only below the severity floor.

Hard cap: at round 6 halt and ask the owner whether to continue or ship. Never stop early to save
cost while a round still finds substance, and never under-seat a round to reach clean faster.

## Seat palette

Core, always: Axiom Breaker (contradictions, unstated invariants, decisions that will not survive
first use) and Cascade Analyst (unhandled failure paths, compounding errors). Specialists by trigger:
State Corruptor (races, staleness, idempotency), Boundary Smuggler (trust bypass, injection),
Resource Vampire (unbounded queues, repeated calls, quota), Protocol Pedant (schema and contract
drift, serialisation), Blindspot Auditor (irreversible footguns, missing observability), Dependency
Cynic (upstream drift, environment assumptions), Literal Implementer (what a builder must guess),
Mechanism Gamer (gates that pass without the intended effect), Activation Auditor (entry points and
triggers). Bespoke seats when the artifact needs a lens the palette lacks: Licensing Lawyer,
Compliance Buyer, Go-to-Market Skeptic, Option-Value Economist, Measurement Designer, Procedure
Walker (walks the artifact's own end-to-end scenario and reports the furthest step reachable
without guessing; reaching the end predicts the first clean round).

Ask each seat to cite the section for every finding and to give defect, mechanism, consequence and
severity (BLOCKING, MATERIAL, MINOR). State the severity floor explicitly: naming and wording are
below it; a mismatch a builder must resolve by guessing is above it.

## Payload

Same review-only banner and reply contract as the fork brief, with these differences:

- `discipline: adversarial-panel-review`, the artifact path, and the terminal line `PANEL VERDICT:`
  followed by `FINDINGS-N` or `CLEAN`. Do not ask for a bracketed verdict token in a panel round;
  on clavity-dotnet the language-server driver expects `PANEL VERDICT` and flags anything else as
  truncated, and on clavity-classic you check the last line by eye.
- State the md5 of the artifact when it changed since the peer last read it, and tell it to re-read
  from disk; a peer can answer from a stale copy.
- One open question at the end: "name what you examined LEAST and say whether a clean verdict means
  'checked and clean' or 'not looked at'". Read the answer as a list of your own unaudited areas.

## Dispositions

Every finding resolves to exactly one:

- `FOLDED: <what changed>`
- `REJECTED: <the measurement or clause that killed it>` (quote it)
- `DISCARDED-BELOW-FLOOR: <target> unreachable because <guard at location>`
- `DEFERRED-TO-ANOMALIES: <anchor> * <date>` after appending to `.clavity/local-anomalies.md`
- `UNVERIFIED-ACCEPTED: <finding>` only after the owner accepted the risk

"Pre-existing" and "out of scope" are not dispositions. A clean verdict cannot be proposed while any
finding lacks a token. Record every disposition in the artifact's own review ledger (an appendix) and
list stand-downs in a `## Stand-downs` section inside the artifact, because a clean round may
produce no commit and the artifact is the only durable record.

## Reading a clean round

Before accepting it: read the peer's discarded-below-floor list and its direct answers as carefully
as its findings (a real defect has been found there, filed as a note); check that the "where I
looked" census names files and sections that exist; and grep two or three of its citations. A round
that restates your own ledger is agreement, not review. When the peer's census is prose rather than
an enumerated table, do the spot-check yourself and say so in the report.

## Marker

When a panel concludes clean, write the marker through the marker writer
(`bash "<BASE>/../../hooks/agy-mark.sh" head "agy-panel" "$(git rev-parse HEAD)"`) so the recovery hook stops surfacing the
panel's seams at every session start. Name panel seams `.clavity/seams/<topic>-panel-r<N>.md`.
