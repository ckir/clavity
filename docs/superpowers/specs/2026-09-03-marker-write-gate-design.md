# Gating the completion-marker write on a ledger row — design spec

> **Status:** SPEC, not a plan. The gate does not exist, so this carries intent, contracts and rulings
> — **no line numbers into code that has not been written.** As of 2026-09-06 every fork is closed and
> the line-level plan is unblocked; the plan is the artifact that may cite lines, and only into code that
> exists when it is written.

**ROADMAP item:** `clavity-dotnet/ROADMAP.md` §27, owner-accepted 2026-09-03.
**AGY-FIRST consult:** `.clavity/seams/agyfirst-s23-behavioural-gate.md`.
**AGY-AFTER:** round 1 folded 2026-09-05 (solo panel + agy escalation + one negotiation turn); forks
owner-ruled 2026-09-06 — see `## Resolved forks` and `## Review status`.

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
  `git rev-parse 'SP-B agy-capstone skill'` has no answer, so **a normaliser reading the range column
  needs a defined behaviour for an unresolvable token.** ▶ **F7's ruling removes that requirement rather
  than answering it: the gate never reads the range column at all.** This measurement is kept because it
  is the evidence FOR that ruling — delete it and the ruling looks arbitrary.

- 🔴 **A NAIVE SHA SEARCH ALREADY FALSE-PASSES ON TODAY'S FILE, WITH NO HOSTILE AUTHOR REQUIRED.** The
  panel's escalation round raised this as a hypothetical — someone writing "we audited 9ff0b10 but it
  failed" into the prose. It is not hypothetical. MEASURED 2026-09-05: the fold-commit shas cited in the
  *evidence* column — `2b634ca`, `113525c`, `b8e9a61`, `65b889a`, `f3ea3e9` — each appear in the ledgers
  **exactly once**, and **not one of them as a range right-endpoint**. A `grep "$sha"` gate would
  therefore authenticate a marker written at any fold commit, none of which was ever an audited tip. The
  gate must locate a sha **positionally**, in a known column of a known row — never by searching the file.

`docs/agy-test-audit-ledger.md` is, today, a single table (`:35`) — but it is the younger file, and
nothing keeps it that way.

**C2 — ~~A `round-cap` WAIVER MUST STILL PASS.~~ DISSOLVED 2026-09-06 — ITS PREMISE IS FALSE, MEASURED.**
`agy-capstone/SKILL.md:519` is correct that a round-cap waiver **also writes the `.head` marker** (a
`breach` waiver writes the audit line and **no** marker). The spec inferred from that a gate would block a
legitimate owner waiver. **It would not.** `agy-capstone/SKILL.md:375` requires the ledger row
unconditionally — *"Record the round in `docs/agy-capstone-ledger.md` before declaring the plan
complete"* — with **no waiver exemption anywhere in the file**, and the real round-cap-waived run bears
this out: `docs/agy-capstone-ledger.md:404` carries the row for `f5d98a1..7dd31a8`, the exact range whose
marker was written under `WAIVED reason=round-cap`.

So a waiver already owes a row and already has one; the gate passes it like any other terminal state.
**What C2 was actually protecting against is ORDERING** — a marker written before its row blocks every
terminal state equally, waived or clean. That is C9, and C9 is where the obligation now lives.

> ⚠ This constraint previously cited `:461`. That line sits inside the `[VERDICT: ALIGNED]` bullet and says
> nothing about waivers or markers; the rule is 58 lines further on. The claim was true and its anchor was
> false — corrected by the panel, and recorded because a spec that cites confidently is the artifact a plan
> will trust without re-checking. **The citation was the smaller error: the constraint built on it was
> load-bearing for a whole fork (F3), and both are gone.**

**C3 — IT MUST FAIL CLOSED, BUT NOT FAIL STUCK.** A gate that cannot read the ledger, cannot resolve a
sha, or meets an unparseable table must refuse rather than pass — a size-zero read certifying "fine" is
the shape this repository has been bitten by. But refusal must name the fix, because the operator hitting
it is mid-discipline. 🔴 **The refusal is terminal and has no recovery path today:** `head` refuses through
`_die_refuse` (exit 1), and `agy-mark.sh:52-59` records that every call site spells
`if ! bash …; then <echo>; exit 1; fi`. So a false refusal aborts a discipline that has already done its
work, and the only way out is editing the ledger until a parser is satisfied. **C3 is not satisfiable by
a good error message alone — it needs a named override.** ▶ **F6 names it: an explicit flag, loud and
auditable rather than restricted.** The refusal message must therefore name BOTH the fix (write the row)
and the escape (the flag), or the flag is a secret and C3 is unmet in practice.

**C4 — BOOTSTRAPPING, AND IT ARRIVES ON DAY ONE.** The first marker for a new ledger-owning discipline is
written against an empty or absent ledger, and that case must be reachable without disabling the gate.
**See C6: absence is not only a first-run state.** ▶ **F7's ruling makes the empty-history state
universal but harmless, and the distinction matters.** The gate reads only rows carrying the
machine-readable token, and no existing row has one, so from the gate's point of view every ledger is
empty the day it ships. That is **not** a bootstrap problem, because the gate never asks "does this
ledger have any rows?" — it asks "does it record THIS sha?", and under C9 the current run has just
written that row. The genuine bootstrap case is narrower than the spec first stated: **a ledger file that
exists but is empty**, for a discipline whose first run has not yet written its row. Under F1/F5 an
*absent* ledger means the gate does not apply at all, so only the present-and-empty case remains.

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

## Resolved forks — OWNER-RULED 2026-09-06

Every fork below is closed. The reasoning that produced each is kept because a later reader needs to
judge the ruling, not merely obey it. Where the owner ruled against the driver, that is said plainly.

**F1 + F5 — how the gate learns what it applies to. ▶ RULED: DERIVE FROM THE LEDGER'S PRESENCE.**
The gate applies to a discipline **iff** that discipline's ledger exists at the convention path. No
roster, no config file, no caller argument — so there is nothing an agent can forget to pass and no
enumeration whose next member is never added. In a repository with no ledger the gate does not apply and
passes silently, which answers C6's population without a notice in every foreign repo.

*Both reads agreed these are ONE fork; the peer put it sharpest — "the real fork is F5; F1 is a ghost".*
*They differed on the mechanism.* The peer proposed a repository-local config declaring
discipline→ledger, to avoid baking a path convention into a shipped hook. **Two things decided it against
that.** Its own example location cannot exist — MEASURED with a passing and a failing control,
`git check-ignore -v --no-index .clavity/ledgers.conf` resolves to `.gitignore:45:.clavity/` while
`docs/agy-capstone-ledger.md` returns exit 1, and the root `.gitignore:26-31` documents that a negation
cannot resurrect a file beneath an excluded directory. And a config file is itself a thing a repository
can simply never write, which is the omission failure the gate exists to remove, moved one level up.
**The accepted cost is real and is stated here rather than argued away:** a path convention now ships to
every user. It is inert for them — no ledger, no gate — but it is this repository's shape in their tree.

**F2 — what "the ledger records this sha" means. ▶ EXACT ENDPOINT MATCH, positionally located.**
Not ancestry. Both reads independently reached this, and the peer named the mechanical reason the driver
had only felt: ancestry forces the gate to feed a token it scraped out of prose to
`git merge-base --is-ancestor`, and C1 proves the prose contains tokens like `SP-B agy-capstone skill`
that resolve to nothing. **Discount the agreement — the driver framed the options.** The peer also named
F2 as the fork most likely to be answered *wrongly*: ancestry "looks right conceptually but is a
mechanical trap", because it matches the forgiving rule the reminder hook already uses.

⚠ **The divergence from `agy-test-audit-reminder.sh:43` is now DELIBERATE and must be stated in the
code.** The write-gate asks "was this exact sha recorded?"; the reminder asks "is this marker still good
enough to stay quiet?". Two questions, two rules, one marker — and nothing in the tree currently says so.

**F3 — how the waiver signals itself. ▶ DISSOLVED. There is no fork.** See C2: a round-cap waiver already
owes a ledger row and the real waived run has one, so the gate passes it unaided. No `--waived` mode, no
env var, no reading the audit log. **This is the second thing this review removed rather than answered**,
and both removals came from checking a premise instead of designing against it.

**F4 — where the gate lives. ▶ A SOURCED HELPER beside `agy-mark.sh`.** Both reads agreed; again
discount, the options were the driver's. `agy-mark.sh` is 358 lines of unusually dense
comment-as-contract, and a positional ledger parser belongs beside `agy-shield-lib.sh` rather than inside
the mode switch. C5 makes both halves ship regardless, so this buys readability and unit-testability, not
surface.

**F6 — C3's override. ▶ RULED AGAINST THE DRIVER: AN EXPLICIT OVERRIDE FLAG EXISTS.**
The driver argued for no override at all — a refusal names the missing row, writing it takes seconds, and
every override is a bypass an agent will reach for. The owner ruled for the peer's position: an operator
stranded by a parser problem, possibly caused by *someone else's* malformed row, needs a mechanical way
out.

🔴 **THE DRIVER'S OBJECTION IS NOT WITHDRAWN AND CONSTRAINS THE BUILD.** `agy-mark.sh` runs as a plain
process with **no owner identity available to it**, so "owner-only" is not implementable as stated: any
flag a human can pass, an agent can pass. The ruling is therefore implemented as a flag that is
**loud and auditable rather than restricted** — every use appends a durable line to
`.clavity/agy-marks/skipped.log` naming the override, exactly as the existing waivers do, so a bypass is
a recorded act rather than a silent one. That converts the residual hole from invisible to visible, which
is the same trade the whole gate is built on.

**If that audit line cannot be written, the override REFUSES** — round 2 caught that the override's own
logger had no error path, and that either answer looked bad: failing open makes the override silent
(defeating the auditability the ruling rests on), failing closed appears to strand the operator C3
protects. **Failing closed is nearly free here, and the reason is structural rather than a judgement
call:** `skipped.log` and the marker file live in the *same directory*, `.clavity/agy-marks/`, so a
filesystem that rejects the audit append rejects the marker write too. The operator was already blocked;
refusing does not add a stranding case, it just refuses honestly instead of writing an unlogged bypass.

**F7 — how the sha is located. ▶ RULED: A MACHINE-READABLE TOKEN PER ROW.** *Found by the peer, and it
was right that this is the mechanical core the spec had deferred.* Each new ledger row carries a
canonical token the gate reads, and the gate reads nothing else — no exposure to the
four-tables-and-prose shape C1 measured.

### The token, pinned — because round 2 proved that leaving it abstract broke the ruling

Round 2 caught the ruling contradicting C1 in the artifact's own words: the previous draft said the gate
does "no table walking, no column counting", which — read literally, and it is right to read it literally
— leaves nothing but **searching the file**, the one thing C1 forbids. A token pasted into evidence prose
would then authenticate a marker exactly as a bare sha does today. **The resolution is that the token is
positional at the LINE level, which needs no table semantics at all:**

🔴 **ROUND 3 KILLED THE FIRST VERSION OF THIS FORMAT BY MEASUREMENT, AND THE REPLACEMENT IS BELOW.**
The draft above placed the token on **its own physical line** beneath its row. Two independent defects,
both confirmed:

- **It destroys the table it annotates.** MEASURED 2026-09-06 with `mdcat` and BOTH controls: a clean
  3-row table renders whole; the same table with a blank line between rows truncates after row 1 with the
  remainder falling out as raw text (the failing control, proving the probe can see breakage); and **the
  HTML-comment-between-rows case renders identically to the blank-line case.** An HTML comment is a
  block-level construct, so it terminates the table exactly as a blank line does.
- **It does not close the bypass it claimed to close.** The line anchor keeps a token out of a table
  *cell*, but the ledgers are mostly free prose — a token on its own line inside an evidence paragraph or
  a heading section matches just as well. The claim that the anchor was "structural" was wrong.

**The format, corrected — and measured before being written down this time:**

- **Shape:** the token is an HTML comment occupying a **dedicated leading CELL** of the ledger row:
  `| <!-- agy-mark: <discipline> <40-hex-sha> --> | date | range | … |`.
- **How the gate finds it:** the line must begin with `|`; the gate takes **field 1** and matches the
  token pattern there. Field 1 and nowhere else.
- 🔴 **WHY THIS IS BOTH POSITIONAL AND UNSPOOFABLE, measured rather than argued.** The table renders
  **intact** — all rows, one table — and the token is **invisible**, `grep -c agy-mark` over the rendered
  output returning **0**. Positional means *field 1 of a pipe-anchored line*, which is column counting,
  and column counting was never what C1 forbade — **C1 forbids SEARCHING**. And a spoof can no longer
  hide: to be read it must be field 1 of a line beginning with `|`, which **is** a table row, so a forged
  token renders as a visible extra row in the ledger rather than as invisible prose. The bypass moves
  from "paste a string in a comment" to "add a fake row to a table people read".
- **40 characters, and written by a tool, never by hand.** Round 2 argued that exact matching against the
  40-char sha `head` receives would force humans to hand-write 40-char shas. That does not follow — a
  token is validated hex, so unlike C1's prose cells it is safe to expand through git. **The spec chooses
  the tool-written full sha anyway**, because it removes the transcription step entirely rather than
  making it recoverable, and this repository has already had a marker corrupted by exactly one
  hand-transcribed sha (`docs/backlog/agy-mark-accepts-a-nonexistent-sha.md`).
- **The pairing is what the format linter checks:** every ledger row is followed by exactly one token
  line, and no token line is an orphan. ⚠ **This does NOT prove the token agrees with the prose in its
  row** — round 2 named that split-brain honestly and it is not fully closed. What closes it in practice
  is that both are emitted by one writer, so divergence requires a hand edit, and the token sits directly
  under the row a human reads rather than in a second file.

**The accepted consequence, stated because it is the kind of thing that surfaces later as a surprise:**
pre-existing rows carry no token, so **the gate sees an empty ledger for all history** and only rows
written after the change are visible to it. Per C4 that is harmless — the gate asks only whether THIS
sha is recorded — but it does mean the gate cannot retroactively validate an old marker, and must not
pretend to.

⚠ **F7 IS UNDER CHALLENGE AND THE OWNER OWNS THE ANSWER.** Round 2's reviewer argued the whole mechanism
is circular — *"the agent writes a string solely so the bash script can find it, while a separate linter
is required solely to ensure the agent wrote the token."* The driver may not reopen a ruling, so this is
recorded rather than acted on. Its force is reduced but not removed by the fold above: a line-anchored,
tool-written token is not something an agent writes at all, so the circularity is between two tools
rather than between an agent and a linter.
## Sequencing

**The line-level plan is UNBLOCKED as of 2026-09-06** — every fork is ruled, so a plan can cite real
lines in code that exists. The BUILD remains the owner's to schedule; §26 (the footprint analyzer) is
also spec-written and unbuilt, and the owner sequences the two.

**What the plan must carry, derived from the rulings rather than restated from them. 🔴 THE ORDER BELOW
IS LOAD-BEARING — round 3 found that the obvious order breaks the repository partway through.**

1. **The ledger format lands first** (F7's token cell), in both ledgers, together with the writer that
   emits it and its format linter.
   🔴 **THE LINTER MUST BE DIFF-SCOPED, NOT A STATIC FILE SCAN.** Round 3 caught this: pre-existing rows
   carry no token and are never retrofitted, so a linter that scans the whole file fails on every
   historical row the moment it lands — it would break the build on arrival. It must check only rows
   **added in the range under test**. That pattern already exists in this repository:
   `scripts/check-capstone-new-code.ps1:13` takes a mandatory `-BaseRef` for exactly this reason.
2. **The discipline skills learn the ordering — row before marker (C9) — and the token.** 🔴 **THIS MUST
   LAND BEFORE THE GATE, and round 3 is why.** A gate that arrives first refuses every agent still
   following the old, unspecified ordering, so the repository would spend the gap actively breaking
   compliant runs. Prose landing early is harmless; the gate landing early is not. Both plugin halves, a
   `writing-skills` change, twin mirrored in the same commit.
3. **A new sourced helper** (F4) beside `agy-shield-lib.sh`, plus its Pester suite, its `_partition.md`
   row, and its `justfile`/CI registration. **That registration is an explicit list, not a glob** — the
   orphaned-test class of §36.
4. **The `head` arm gains the gate and the F6 override flag, LAST**, mirrored byte-identically into
   `clavity-classic/plugin/hooks/` in the SAME commit (C5), with `check-seed-artifacts-synced.sh` green.
   **The refusal message must distinguish its two causes** — no row at all, versus a row present whose
   token is absent or does not match. Round 3's Blindspot seat noted that "write the row" is a misleading
   diagnostic for an operator looking straight at the row they just wrote.
5. **C8's collision is resolved in the same plan, not after it:**
   `docs/backlog/agy-mark-accepts-a-nonexistent-sha.md` proposes a `git cat-file -e` check on these same
   three lines and asks the same out-of-repository question. Either fold it in or record why it waits.

**The stopping-point test, which is what makes the order above more than a preference:** asked which
single landing would leave the repository *worse than never having started*, round 3 named the gate
arriving before the skills — the state where the mechanism is live and nothing has taught anyone to
satisfy it. Every step above is safe to stop after, in this order.

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
- `REJECTED: round 2's claim that exact endpoint matching FORCES humans to hand-write 40-character shas
  into the token. The forcing step does not hold — a token is validated hex, so it is safe to expand
  through git, which is exactly what made ancestry unsafe for the PROSE cells and does not transfer here.
  The decision the finding exposed was real and is made (tool-written 40-char sha); the claim that one
  answer was compelled is what is rejected.`
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

**OWNER RULINGS 2026-09-06 — all seven forks closed.** Presented as both reads side by side, per
AGY-FIRST. The owner took the driver's call on F1/F5 and F7, and **the peer's call on F6, against the
driver's recommendation** — recorded in `## Resolved forks` with the driver's unwithdrawn objection and
the auditability requirement it forces. F2 and F4 were concurrences and are discounted as such: the
driver framed the options. F3 was not ruled but **dissolved** — its premise failed a measurement taken
while folding the rulings.

**AGY-AFTER round 2 — folded 2026-09-06.** Brief `.clavity/seams/panel-s27-r2.md`; reply
`.clavity/seams/panel-s27-r2-REPLY.md`. Rotated onto a bespoke **Consumer Coherence Auditor** (no palette
seat covers "two consumers of one artifact applying different rules"; ten of twelve palette seats were
already spent in round 1) plus Mechanism Gamer, Protocol Pedant, Literal Implementer, Cascade Analyst and
Activation Auditor. Five findings, four self-classed BLOCKING. Envelope clean.

🔴 **CITATIONS WERE VERIFIED MECHANICALLY, NOT BY EYE** —
`python scripts/check-peer-reply-citations.py <reply.json> 06948b5 adversarial-panel-review` returned
**`0 problem(s) across 5 row(s)`**. Every `quoted_line` is verbatim.

- **The round's best finding was a contradiction inside this artifact.** F7's "no table walking, no column
  counting" left the gate nothing to do but SEARCH — precisely what C1 forbids — so the ruling as drafted
  re-introduced the false pass it was chosen to remove. Folded by anchoring the token to a line boundary,
  which is positional without needing table semantics.
- **The token's format was undefined and is now pinned**, including the choice of a tool-written 40-char
  sha over a hand-written short one.
- **The override's own logger had no error path.** Folded: it refuses, and the refusal costs nothing
  because both files live in one directory.
- **One conclusion was REJECTED as overstated** — that exact matching forces humans to hand-write 40-char
  shas. It does not follow; a validated hex token is safe to expand through git, unlike the prose cells
  that killed ancestry. See `## Stand-downs`.
- **The split-brain the Consumer Coherence seat named is NOT fully closed**, and the spec says so rather
  than claiming otherwise: the linter proves pairing, not agreement between token and prose.

**AGY-AFTER round 3 — folded 2026-09-06.** Brief `.clavity/seams/panel-s27-r3.md`. Rotated onto a second
bespoke seat, **Migration Auditor** — "what does the transition break, and what is left half-migrated if
it stops partway" — the palette having been exhausted; plus Axiom Breaker, Boundary Smuggler, State
Corruptor and Blindspot Auditor. Five findings, four BLOCKING. Citations again verified mechanically:
**`0 problem(s) across 5 row(s)`** against `9ebcdf5`. Envelope clean.

🔴 **ROUND 3 KILLED ROUND 2's FIX.** The token-on-its-own-line format was confirmed dead by measurement —
it breaks the markdown table, and its "structural" anti-spoof property was false because the ledgers are
mostly prose. Replaced by a token CELL, measured intact and invisible before being written down. **Two
rounds in a row found their defect in the previous round's fold**, which is the pattern the capstone
discipline records as normal rather than alarming.

- **The migration itself had never been reviewed, and it broke twice.** A static format linter would fail
  on all historical rows the day it lands; the gate landing before the skills would refuse compliant
  agents. Both folded into an explicit, load-bearing landing order.
- **The refusal message must distinguish "no row" from "row with a bad token"** — otherwise the operator
  debugs the wrong component while looking at the row they just wrote.

🔴 **ROUND 4 IS OWED, AND ONE ITEM STILL NEEDS THE OWNER.** Round 2's challenge to F7-as-circular is a
ruled decision the driver may not reopen; it is with the owner. **This spec still has no GREEN, and no
round has yet been clean.**
