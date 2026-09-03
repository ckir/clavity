# Gating the completion-marker write on a ledger row — design spec

> **Status:** SPEC, not a plan. The gate does not exist, so this carries intent, contracts and open forks
> — **no line numbers into code that has not been written.** The line-level plan is owed only once this
> spec has been reviewed and the build is scheduled.

**ROADMAP item:** `clavity-dotnet/ROADMAP.md` §27, owner-accepted 2026-09-03.
**AGY-FIRST consult:** `.clavity/seams/agyfirst-s23-behavioural-gate.md`.

---

## The problem, as a measurement

§23 shipped a ledger and a clause requiring a row before an audit may COMPLETE, enforced by a linter that
proves **the clause ships**. Measured 2026-09-03:

- **Nothing in the repository reads both `.clavity/agy-marks/agy-test-audit.head` and
  `docs/agy-test-audit-ledger.md`.** One file mentions the marker — `agy-test-audit-reminder.sh` — and it
  never opens the ledger.
- A run that advances the marker and writes no row is therefore **mechanically indistinguishable from a
  correct one**. The reminder goes quiet; the linter passes; the tree looks right.

**So §23's own promotion trigger cannot fire.** It waits for "an audit found to have completed with no
row", and that finding has no mechanism behind it.

## What is being built

**One gate, at one chokepoint: `agy-mark.sh`'s `head)` branch.** It refuses to write a completion marker
for a ledger-owning discipline unless that discipline's ledger already records the sha being marked.

Not a new hook. `agy-mark.sh` is already the single writer every discipline calls, already validates its
discipline and sha arguments, and already has a refusal path.

## What this does NOT prove — say it here, or the spec ships a False Safety Promise

- **It does not prove an audit happened.** It proves a row exists. A fabricated row passes.
- **It does not judge the row's quality** — evidence, verdict and range are prose, and no gate reads
  prose honestly.
- **Its real value is narrower than "enforcement":** it converts a sin of OMISSION into a sin of
  COMMISSION. An agent forgets a step far more readily than it fabricates a record to defeat a hook. That
  is the whole claim, and it should be written into the code's comment, not just here.

## Constraints the implementation must satisfy

**C1 — SHA FORMS DO NOT MATCH, and a naive gate breaks every CORRECT run.** The ledgers carry
7-character short SHAs and range syntax (`73efca8..eba63a8`); `agy-mark.sh head` is handed a
40-character sha. A `grep "$sha"` finds nothing on a perfectly good ledger. The gate must normalise —
resolve ledger tokens through git rather than comparing strings. **This constraint came from the peer and
neither the driver nor the ROADMAP entry had seen it.**

**C2 — A `round-cap` WAIVER MUST STILL PASS.** `agy-capstone/SKILL.md:461` specifies that a round-cap
completion-gate waiver **writes the marker**, and it exists precisely for the case where the owner
accepts "done" with findings still live. A gate that blocks it converts an owner decision into a dead
end. Whatever is built must let the waiver through without reopening the hole it closes.

**C3 — IT MUST FAIL CLOSED, BUT NOT FAIL STUCK.** A gate that cannot read the ledger, cannot resolve a
sha, or meets an unparseable table must refuse rather than pass — a size-zero read certifying "fine" is
the shape this repository has been bitten by. But refusal must name the fix, because the operator hitting
it is mid-discipline.

**C4 — BOOTSTRAPPING.** The first marker for a new ledger-owning discipline is written against an empty
or absent ledger. That case must be reachable without disabling the gate.

**C5 — BYTE-IDENTICAL PAIR.** `agy-mark.sh` ships in both plugin halves and is gated by
`check-seed-artifacts-synced.sh`. Every change mirrors, and the blast radius is class 2: plan → panel →
capstone → audit.

## Open forks — for the owner, at plan time

**F1. Which disciplines does the gate cover?** `agy-test-audit` alone (the §23 subject), or every
discipline that owns a ledger — which today also means `agy-capstone`. Covering both is consistent with
how §23's linter check was scoped; covering one is a smaller blast radius.

**F2. What does "the ledger records this sha" MEAN?** Exact endpoint match against a range's right-hand
side? Ancestry (`git merge-base --is-ancestor`) so a marker at a descendant of an audited tip still
passes? The two differ precisely in the case that matters — a marker written after a fold commit.

**F3. How does C2's waiver path signal itself?** An env var the waiver sets, a separate `head --waived`
mode, or the audit log consulted as the authority. Each leaks the waiver concept into a different file.

**F4. Does the gate live in `agy-mark.sh` or beside it?** In-script is one chokepoint and no new file;
a sourced helper keeps a 261-line script from growing a ledger parser. C5 makes both changes ship, so
this is about readability, not surface.

## Sequencing

**Build deferred.** §26 (the footprint analyzer) is now unblocked by §23 shipping, and both are
spec-written and unbuilt. The owner sequences them.

## Review status

🔴 **This spec has NOT been reviewed.** AGY-AFTER is owed before a line-level plan is written. The
AGY-FIRST consult that produced the ruling is not that review — it decided the fork; a panel tests the
artifact.
