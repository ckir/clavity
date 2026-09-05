# Gating the completion-marker write on a ledger row — design spec

> **Status:** SPEC, not a plan. The gate does not exist, so this carries intent, contracts and open forks
> — **no line numbers into code that has not been written.** The line-level plan is owed only once this
> spec has been reviewed and the build is scheduled.

**ROADMAP item:** `clavity-dotnet/ROADMAP.md` §27, owner-accepted 2026-09-03.
**AGY-FIRST consult:** `.clavity/seams/agyfirst-s23-behavioural-gate.md`.
**AGY-AFTER:** panel round 1 (solo) folded 2026-09-05 — see `## Review status`.

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
- 🔴 **IT IS BLIND TO THE OPPOSITE FAILURE, AND THAT IS THE STATE THIS REPOSITORY IS IN RIGHT NOW.**
  A gate on the WRITE says nothing about a write that never happens. MEASURED 2026-09-05:
  `.clavity/agy-marks/agy-capstone.head` holds `7dd31a8db67c…` — the 2026-09-04 hook-emission capstone —
  while the newest capstone record in `docs/agy-capstone-ledger.md:456` covers `efdcb58..9ff0b10`, the
  Phase 2 conclusion of 2026-09-05. The marker is a day and an epic behind the ledger. Nothing detects
  that either, and this gate will not.
- 🔴 **IT IS BYPASSED ENTIRELY BY A MARKER WRITTEN BY HAND**, which is not hypothetical: the
  2026-09-05 test-audit row **and** its marker were both written by hand in one session.
  `agy-capstone/SKILL.md:496` says "never by hand", and prose is precisely what §27 exists to replace.
- **Its real value is narrower than "enforcement":** it converts a sin of OMISSION into a sin of
  COMMISSION. An agent forgets a step far more readily than it fabricates a record to defeat a hook. That
  is the whole claim, and it should be written into the code's comment, not just here.

## Constraints the implementation must satisfy

**C1 — THE LEDGER IS NOT A TABLE, AND SHA FORMS DO NOT MATCH.** This constraint began as the peer's
observation that the ledgers carry 7-character short SHAs and range syntax (`73efca8..eba63a8`) while
`agy-mark.sh head` is handed a 40-character sha, so a `grep "$sha"` finds nothing on a perfectly good
ledger. **The AGY-AFTER panel measured the file and found the shape is much further from a table than
that.** In `docs/agy-capstone-ledger.md`:

- **Four separator rows, so four tables** — `:40`, `:132`, `:338`, `:403` — and the one at `:132` is a
  **3-column Anomaly table** whose second column is prose, not a range. A parser scanning `^|` rows for a
  sha ingests 11 rows that were never capstone records.
- **The NEWEST record is not a table row at all.** It is a `##` heading section: `:456`,
  `## Phase 2 (ROADMAP §24 + §25) — efdcb58..9ff0b10 — CONCLUDED 2026-09-05`. A table parser misses the
  most recent capstone in the file.
- **The range column is free prose in 11 of 51 rows** — `SP-B agy-capstone skill`,
  `agy-test-audit discipline`, `clavity-ls channel resilience`, plus the 8 anomaly rows — and the rest mix
  backticked and bare ranges, trailing parentheticals, and `^..` syntax (`77aa257^..08254ab`).
  `git rev-parse 'SP-B agy-capstone skill'` has no answer, so **the normaliser needs a defined behaviour
  for an unresolvable token and this spec does not yet give it one.**

- 🔴 **A NAIVE SHA SEARCH ALREADY FALSE-PASSES ON TODAY'S FILE, WITH NO HOSTILE AUTHOR REQUIRED.** The
  panel's escalation round raised this as a hypothetical — someone writing "we audited 9ff0b10 but it
  failed" into the prose. It is not hypothetical. MEASURED 2026-09-05: the fold-commit shas cited in the
  *evidence* column — `2b634ca`, `113525c`, `b8e9a61`, `65b889a`, `f3ea3e9` — each appear in the ledgers
  **exactly once**, and **not one of them as a range right-endpoint**. A `grep "$sha"` gate would
  therefore authenticate a marker written at any fold commit, none of which was ever an audited tip. The
  gate must locate a sha **positionally**, in a known column of a known row — never by searching the file.

`docs/agy-test-audit-ledger.md` is, today, a single table (`:35`) — but it is the younger file, and
nothing keeps it that way.

**C2 — A `round-cap` WAIVER MUST STILL PASS.** `agy-capstone/SKILL.md:519` specifies that a round-cap
completion-gate waiver **also writes the `.head` marker** (a `breach` waiver writes the audit line and
**no** marker), and it exists precisely for the case where the owner accepts "done" with findings still
live. A gate that blocks it converts an owner decision into a dead end. Whatever is built must let the
waiver through without reopening the hole it closes.

> ⚠ This constraint previously cited `:461`. That line sits inside the `[VERDICT: ALIGNED]` bullet and says
> nothing about waivers or markers; the rule is 58 lines further on. The claim was true and its anchor was
> false — corrected by the panel, and recorded because a spec that cites confidently is the artifact a plan
> will trust without re-checking.

**C3 — IT MUST FAIL CLOSED, BUT NOT FAIL STUCK.** A gate that cannot read the ledger, cannot resolve a
sha, or meets an unparseable table must refuse rather than pass — a size-zero read certifying "fine" is
the shape this repository has been bitten by. But refusal must name the fix, because the operator hitting
it is mid-discipline. 🔴 **The refusal is terminal and has no recovery path today:** `head` refuses through
`_die_refuse` (exit 1), and `agy-mark.sh:52-59` records that every call site spells
`if ! bash …; then <echo>; exit 1; fi`. So a false refusal aborts a discipline that has already done its
work, and the only way out is editing the ledger until a parser is satisfied. **C3 is not satisfiable by
a good error message alone — it needs a named override, and naming it is fork F6.**

**C4 — BOOTSTRAPPING.** The first marker for a new ledger-owning discipline is written against an empty
or absent ledger. That case must be reachable without disabling the gate. **See C6: absence is not only a
first-run state.**

**C5 — BYTE-IDENTICAL PAIR.** `agy-mark.sh` ships in both plugin halves and is gated by
`check-seed-artifacts-synced.sh` (verified `cmp`-identical 2026-09-05). Every change mirrors, and the
blast radius is class 2: plan → panel → capstone → audit.

**C6 — 🔴 THE GATE'S DATA SOURCE DOES NOT EXIST IN MOST REPOSITORIES WHERE THIS SCRIPT RUNS.**
`agy-mark.sh` is plugin-shipped: it executes in whatever repository the user drives, and
`git ls-files '*ledger*'` returns the two ledgers **only in this repository**. For every external install
the ledger is absent **permanently**, not transiently. C4 frames absence as bootstrap; it is the steady
state for the majority population. That forces a choice this spec must make explicitly rather than
inherit: *absent means pass* turns the gate off for every external user (and C4's "reachable without
disabling the gate" becomes unachievable as written), while *absent means refuse* breaks discipline
completion for them. This is the class ROADMAP §31 already tracks — shipped hooks misbehaving in
repositories that are not clavity.

> **The escalation round sharpened this, and the sharper form is the one that binds.** The problem is not
> only that the FILE is absent elsewhere — it is that **any path convention the gate hardcodes is
> clavity-specific**. A gate that resolves `docs/<discipline>-ledger.md` at the git root has injected this
> repository's layout into a hook that ships to everyone. So C6 is not answered by handling absence
> gracefully; it is answered only by deciding where the ledger location comes from at all.

**C7 — 🔴 THE GATE NEEDS A SECOND ANCHOR, AND THE FIRST ONE IS LOAD-BEARING.** `agy-mark.sh:140` sets
`root=$PWD`, and the header at `:7-12` **forbids git-toplevel by name**: the reader
(`agy-seam-inject.sh:124`) resolves `"$cwd_path/.clavity/agy-marks/<discipline>.head"`, so a toplevel
writer against a cwd reader defeats the debounce in any session launched from a subdirectory. The ledgers,
however, exist only at the git root — MEASURED: `clavity-dotnet/docs/agy-capstone-ledger.md` does not
exist. So the gate must resolve the LEDGER by a different anchor than the MARKER it gates, inside one
arm, or a session launched from `clavity-dotnet/` refuses every legitimate marker write under C3.

**C8 — 🔴 THIS MAKES `head` GIT-DEPENDENT, AND AN OPEN BACKLOG ITEM ALREADY OWNS THAT QUESTION.**
`agy-mark.sh` invokes git exactly once today, at `:348` in the `stamp` arm, wrapped `|| echo unknown` — the
script is deliberately git-OPTIONAL. C1 requires resolving ledger tokens through git on the `head` path,
whose failure mode is a hard refusal. Separately, `docs/backlog/agy-mark-accepts-a-nonexistent-sha.md`
(**OPEN**, promoted 2026-08-31) proposes adding `git cat-file -e <sha>^{commit}` to this same arm, and
closes on this: *"whether the check should run when the marker is written **outside a repository** …
and whether that case should refuse or pass through."* Same three lines, same arm, same unanswered
question. **The two must be planned together or they will contradict each other.**

**C9 — THE ROW MUST PRECEDE THE MARKER, AND NOTHING SAYS SO TODAY.** The gate reads the ledger at
marker-write time, so under it the row-then-marker ordering stops being a convention and becomes a
precondition. No skill instructs that order. Making it mandatory means amending the discipline
`SKILL.md` files across both plugin halves — a blast-radius item this spec had not listed.

## Open forks — for the owner, at plan time

**F1. Which disciplines does the gate cover?** `agy-test-audit` alone (the §23 subject), or every
discipline that owns a ledger — which today also means `agy-capstone`. Covering both is consistent with
how §23's linter check was scoped; covering one is a smaller blast radius. **Panel note:** three
disciplines call `head` — `agy-capstone`, `agy-first`, `agy-test-audit` (`SKILL.md:500`, `:213`, `:416`,
both plugin halves) — and `agy-first` owns no ledger, so the gate must discriminate somehow. **If it
discriminates from a hardcoded roster, that roster is an explicit enumeration whose next member is never
added — the failure class that bit this repository four separate times on 2026-09-05 alone
(`_partition.md` rows, a `-ForEach` arm, a `$skills` list, `scripts/README.md`).** Deriving the roster
from the ledger files that exist is an option this fork had not named.

**F2. What does "the ledger records this sha" MEAN?** Exact endpoint match against a range's right-hand
side? Ancestry (`git merge-base --is-ancestor`) so a marker at a descendant of an audited tip still
passes? The two differ precisely in the case that matters — a marker written after a fold commit.

> 🔴 **THIS FORK IS ALREADY ANSWERED TWICE IN SHIPPED CODE, AND THE TWO ANSWERS DISAGREE.** MEASURED
> 2026-09-05, quotes verified verbatim:
>
> - `agy-seam-inject.sh:125` — `[ "$(cat "$marker" 2>/dev/null)" = "$head" ]` — **strict equality.** Any
>   commit at all invalidates the marker and the seam re-injects.
> - `agy-test-audit-reminder.sh:43` — `git merge-base --is-ancestor "$sha" "$head"`, then
>   `:45-46` diff the range and forgive it unless something matching the executable-code pattern landed —
>   **ancestry, conditionally forgiven.**
>
> Both are deliberate: the reminder's header at `:24-29` records that relaxing only the capstone marker
> once punished the driver who did the right thing. **So F2 is not a free choice — the gate either picks
> one of the two live rules and diverges from the other consumer, or a third and diverges from both.**
> Whichever is chosen, the divergence must be stated in the code, not discovered later.

**F3. How does C2's waiver path signal itself?** An env var the waiver sets, a separate `head --waived`
mode, or the audit log consulted as the authority. Each leaks the waiver concept into a different file.
🔴 **Panel note on the third option:** `.clavity/agy-marks/skipped.log` currently contains **four
fabricated rows** — `agy-first  SKIPPED-UNREACHABLE  HEAD=deadbeef…` — written by the agy peer against
this live repository during capstone rounds 10 and 12, and annotated as fabricated in the file itself.
Making that file the waiver authority would let anything that can append to it mint a waiver.

**F4. Does the gate live in `agy-mark.sh` or beside it?** In-script is one chokepoint and no new file;
a sourced helper keeps a **358-line** script (measured 2026-09-05; this spec previously said 261) from
growing a ledger parser. C5 makes both changes ship, so this is about readability, not surface.

**F5 — NEW, from the panel. What does the gate do where no ledger exists?** C6 makes this the majority
case rather than an edge. Candidate answers, none yet chosen: pass silently when the ledger file is
absent (the gate is then clavity-only in effect); pass with a one-line stderr notice; require an opt-in
marker file in the repository; or derive applicability from the ledger's own presence, which collapses F5
into F1's roster question. **This fork governs whether §27 ships a gate or a gate-shaped no-op for most
users**, so it outranks F2 and F4 in sequencing.

> **A fifth option was proposed in the escalation round and then withdrawn by its own author, which is
> why it is recorded here rather than listed above.** The proposal: the caller passes `--ledger-path=…`,
> and the gate passes silently when the flag is absent. Asked what stops an agent from simply omitting the
> flag, the peer answered that nothing does, and that the hole is **worse** than the one the spec already
> accepts — *"My fifth option introduces a new sin of omission: the agent simply forgets the
> `--ledger-path` argument, the gate silently passes, and the marker is written without a ledger row. This
> completely defeats the purpose of the gate."* **Any F5 answer whose applicability depends on something
> the CALLER remembers to say inherits this**, so the withdrawn option survives as a constraint on the
> others.

**F6 — NEW. What is C3's override, and who may use it?** C3 requires the gate to fail closed without
failing stuck, and the refusal is terminal for the discipline. So there must be a named way past it for
the operator who is legitimately blocked — and every candidate is equally a way past it for an agent that
simply wants the marker written. Candidates: an environment variable; an owner-only flag; a `skipped.log`
audit line, the way the existing waivers already work; or **no override at all**, on the reasoning that a
refusal should be answered by writing the missing row rather than by bypassing the gate. **This fork
cannot be deferred to implementation** — an implementer with no override named will invent one, which is
the worst outcome on the list.

## Sequencing

**Build deferred.** §26 (the footprint analyzer) is now unblocked by §23 shipping, and both are
spec-written and unbuilt. The owner sequences them.

## Stand-downs

- `DISCARDED-BELOW-FLOOR: Resource Vampire seat not seated — no unbounded iteration, no network call and
  no allocation in the proposed change; the larger ledger is 546 lines, read once per marker write.`
- `REJECTED: .clavity/.gitignore holds three bare-star lines, which looked like an unbounded per-call
  prepend. It is not — agy-shield-lib.sh:193 short-circuits when a bare star is already present and
  appends nothing, so the extra lines are historical, not growing.`
- `REJECTED: the escalation round's stated mechanism for the short-sha hazard — "Git dynamically scales
  short SHAs beyond 7 characters" — is not reproducible here. All 373 hex tokens across both ledgers are
  exactly 7 characters, and git rev-parse --short HEAD returns 7 against 2002 objects. The FINDING it
  supported (no safe string-equality path) survives on other grounds and is folded into C1; only the
  mechanism is rejected.`
- `REJECTED: the escalation round's finding that the write path is the wrong chokepoint, retracted by its
  own author after measurement — agy-seam-inject.sh:125 re-injects on any marker that is not exactly HEAD,
  and agy-test-audit-reminder.sh:43-46 re-fires on an ancestor marker once executable code has landed. An
  omitted marker is therefore already caught by the system; what nothing catches is a marker written
  WITHOUT a row, which is what a write-gate stops. Peer's words: "My original claim does not survive …
  The write-gate is indeed the correct chokepoint."`

## Review status

**AGY-AFTER round 1 (solo panel) — folded 2026-09-05.** Persona `relentless-adversarial-auditor`; seats
Axiom Breaker, Cascade Analyst, Mechanism Gamer, Protocol Pedant, Boundary Smuggler, Literal Implementer,
Activation Auditor, Dependency Cynic, Blindspot Auditor, State Corruptor. Resource Vampire consciously
dropped (see Stand-downs). Findings folded above as C1 (rewritten), C2 (citation corrected), C3
(extended), C6, C7, C8, C9, the F1/F3/F4 notes, F5 (new), and two new bullets under "What this does NOT
prove".

**AGY-AFTER round 1 (agy escalation) — folded 2026-09-05.** Brief `.clavity/seams/panel-s27-r1.md`;
reply `.clavity/seams/panel-s27-r1-REPLY.md`. Five seats returned, all self-classed BLOCKING, all
`evidence: reasoned`. Envelope clean — HEAD, branch, reflog tip and scratch dir unmoved.

- **CONFIRMED and strengthened:** the naive-sha-search false pass. The peer argued it from a hypothetical
  comment; measurement found five fold-commit shas already sitting in the evidence prose, none of them an
  audited endpoint. Folded into C1.
- **CONFIRMED:** the ledger-path convention is clavity-specific, not merely absent elsewhere. Folded into
  C6.
- **CONFIRMED:** C3's undefined override blocks a plan. Promoted to fork F6 rather than left as a gap.
- **CONCLUSION CONFIRMED, MECHANISM REJECTED:** the short-sha hazard. See Stand-downs — a true finding
  arriving with an unmeasured mechanism, the fourth time this pattern has been recorded here.
- **RETRACTED BY THE PEER after one negotiation turn:** that the write path is the wrong chokepoint. Sent
  to the consumer files rather than handed a conclusion, it measured both, quoted both deciding lines
  correctly, and withdrew. See Stand-downs.

🔴 **DRIVER-FOUND DURING VERIFICATION, and the peer could not have seen it** — it reported reading only
the spec and `agy-mark.sh`. **F2 is already answered twice in shipped code, incompatibly**
(`agy-seam-inject.sh:125` strict, `agy-test-audit-reminder.sh:43` ancestral). Folded into F2.

🔴 **ROUND 2 IS OWED, BUT F1–F6 GATE IT.** Six forks are open and four of them change what the gate *is*;
a further round would review a shape the owner has not chosen. **The panel is PAUSED for owner rulings,
not concluded** — this spec has no GREEN, and its terminal disposition is "open findings, fold decisions
recorded". The palette is nearly exhausted for rotation (ten of twelve seats used), so round 2 should
seat a bespoke **Consumer Coherence Auditor** — the lens that found the F2 divergence, which no palette
seat covers.
