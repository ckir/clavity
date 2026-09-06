# Gating the completion-marker write on a ledger row — design spec

> **Status: REVIEWED AND SHIPPED 2026-09-06 — `cap-reached`, NOT GREEN.** Five AGY-AFTER rounds, none of
> them clean; the owner stopped the review at the hard cap and released the spec to planning. Every fork
> is ruled and every finding is dispositioned. This is a SPEC: it carries intent, contracts and rulings,
> and **no line numbers into code that does not exist.** The plan is the artifact that may cite lines,
> and it is owed a panel of its own. See `## TERMINAL DISPOSITION` before trusting any of this.

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
  needs a defined behaviour for an unresolvable token.** ▶ **F7 answers it: hex-validate BEFORE calling
  git, and skip anything that fails.** Measured, that drops all 21 non-sha values in the capstone ledger
  — separators, the header, the anomaly table's prose column and these three — without a single one
  reaching git.

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
**See C6: absence is not only a first-run state.** ▶ **F7's REVERSAL shrank this constraint to almost
nothing, and that is one of the reasons the reversal was taken.** The gate reads the existing range
column, so **all 42 historical rows across the two ledgers are visible on day one** — where the token
design would have seen zero until each was retrofitted. The gate never asks "does this ledger have any
rows?" anyway; it asks "does it record THIS sha?", and under C9 the current run has just written that
row. So the genuine bootstrap case is narrow: **a ledger file that exists but is empty**, for a
discipline whose first run has not yet written its row. Under F1/F5 an *absent* ledger means the gate
does not apply at all, so only the present-and-empty case remains.

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

🔴 **THE OVERRIDE'S STATUS TOKEN MUST BE NEW, AND REUSING `WAIVED` WOULD FORGE AN ATTESTATION.** Round 5
caught that the spec said "naming the override, exactly as the existing waivers do" without saying which
`<status>` token goes in the record — leaving the implementer to invent a contract. The obvious guess is
the dangerous one: `agy-mark.sh:91-93` records that **`skipped.log` is READ** — *"the ledger convention
corrected in `c5477ad` reads this file to decide whether a capstone was waived inside a given range, by
looking for a WAIVED line whose HEAD is in that range"*. A marker-gate override logged as `WAIVED` would
therefore manufacture a capstone-waiver attestation that nobody made. **The token is a distinct
`GATE-OVERRIDE`**, which is consistent with the varied tokens the file already carries
(`BREACH-REVERTED`, `CORRECTION`, `UNVERIFIED-ACCEPTED`, `PEER-ARM-UNREACHABLE`).

**If that audit line cannot be written, the override REFUSES** — round 2 caught that the override's own
logger had no error path, and that either answer looked bad: failing open makes the override silent
(defeating the auditability the ruling rests on), failing closed appears to strand the operator C3
protects. **Failing closed is nearly free here, and the reason is structural rather than a judgement
call:** `skipped.log` and the marker file live in the *same directory*, `.clavity/agy-marks/`, so a
filesystem that rejects the audit append rejects the marker write too. The operator was already blocked;
refusing does not add a stranding case, it just refuses honestly instead of writing an unlogged bypass.

**F7 — how the sha is located. ▶ RULED 2026-09-06, THEN REVERSED THE SAME DAY: NO TOKEN. THE GATE READS
THE RANGE COLUMN POSITIONALLY.** *The fork was found by the peer, and the reversal was too — its round-2
challenge that a per-row token is circular turned out to point at a design that is strictly cheaper.*

**The rule.** For each line beginning with `|`, take the **RANGE column — the second column a reader
sees**, strip backticks, take its **first** whitespace- or paren-delimited token, require that token to
match a hex range or bare sha, take the **right-hand endpoint**, resolve it through `git rev-parse` (with
stderr suppressed), and compare to the sha being marked. Anything failing hex validation is skipped
**before git is invoked**.

🔴 **"THE SECOND COLUMN" IS NOT "FIELD 2", AND ROUND 4 CAUGHT THIS SPEC SAYING THE WRONG ONE.** Under a
delimiter split — `awk -F'|'`, `cut -d'|'` — a leading `|` makes field 1 the **empty string before it**,
so the reader's *first* column is `$2` and the RANGE is **`$3`**. The previous wording said "field 2",
which a literal implementer would code as `$2` and get the **date**. Both consequences were measured:

- **With dates as they are written today** (`2026-09-04`), `$2` fails hex validation, so **every row is
  skipped and the gate refuses every marker write, permanently.** A gate that fails closed on all inputs
  is not a gate; it is an outage.
- **With a date written without hyphens** (`20260904`), the value is **pure hex** — MEASURED, it passes
  the same validation a sha does — so if it resolved as a commit prefix the gate would confidently
  authenticate a **date** as the audited endpoint.

The measurement that produced the 42/42 figures used `$3`. **The numbers were right and the sentence
describing them was wrong**, which is exactly the failure a spec hands to an implementer intact. The plan
must state the column by NAME and the field index by MEASUREMENT, never by counting in prose.

**The first token is canonical, and later tokens in the cell are prose the gate ignores — deliberately.**
Round 4 proposed scanning every token in the cell so a second range could not be missed. **That fix is
rejected on a measurement:** the range cells at `docs/agy-capstone-ledger.md:69-70` carry parenthetical
prose containing *further* `..` ranges (`the folds this round produced run f9f2998..e60a…`), so scanning
every token would let a fold commit mentioned in passing authenticate a marker — a weaker rerun of the
C1 false pass this design exists to close. The finding is accepted as a documentation duty instead: **the
canonical range is the cell's first token; a record needing two ranges needs two rows.**

**Two invariants the parser depends on, now written down because round 4 found them unstated:**

- **Every ledger table row begins with `|`.** GFM permits a row without leading and trailing pipes; such
  a row renders correctly and is **invisible to the gate**. MEASURED: all 42 rows carry a leading pipe
  today, so this is true now and unenforced — it belongs in the ledger's own format note and in the
  linter.
- **A row must look like a record, not merely contain a sha.** A minimal fragment such as `| | <sha> |`
  appended anywhere would satisfy a parser that checks only for a leading pipe and a hex token. The gate
  should require the row to carry the ledger's full column count. This does not make forgery impossible —
  the spec has said from the start that a fabricated row passes — it keeps a forgery from being a
  one-line fragment.

### Why this is safe, measured on the real ledgers rather than on a fixture

| what was measured | `agy-capstone-ledger.md` | `agy-test-audit-ledger.md` |
|---|---|---|
| pipe-rows yielding an endpoint | 37 | 5 |
| of those, endpoints that RESOLVE as commits | **37 (100%)** | **5 (100%)** |
| endpoints that fail to resolve | **0** | **0** |
| rows correctly skipped | 21 | 2 |

**Every skipped value is genuinely non-sha** — the separator rows, the `range` header, the 3-column
anomaly table's prose second column, and the three prose ranges (`SP-B agy-capstone skill`,
`agy-test-audit discipline`, `clavity-ls channel resilience`). They fail hex validation and are dropped
**before git is ever invoked**, which is what makes this safe where ancestry was not: the objection that
killed ancestry was feeding scraped prose to git, and hex-validating first removes exactly that.

🔴 **ESCAPED AND EMBEDDED PIPES CANNOT REACH THE RANGE COLUMN, AND THE REASON IS STRUCTURAL — NOT, AS
THIS SPEC PREVIOUSLY GUESSED, A PROPERTY OF TODAY'S DATA.** The driver put it to round 4 that the design's
safety rested on escaped pipes happening to sit in field 5 rather than field 2, and invited the reviewer
to disagree. It did, correctly: **a delimiter shifts only the indices of fields AFTER it**, and the range
column precedes the evidence column that carries the prose. So no `\|` in evidence can move the range's
index, whatever the data does later. The measurement stands (2 escaped pipes in the capstone ledger, 1 in
the test-audit ledger, none in the first two columns, with a control showing the probe finds them in
field 5) — but it is now corroboration, not the argument.

🔴 **AND C1's FALSE PASS IS STRUCTURALLY UNREACHABLE, NOT MERELY UNLIKELY.** The fold-commit shas that
would authenticate a bogus marker live in the **evidence** column, field 5. MEASURED with a presence
control: each of `2b634ca`, `113525c`, `b8e9a61`, `65b889a`, `f3ea3e9` occurs **0 times in field 2** while
occurring in the file. A gate that reads field 2 and nothing else cannot see them. **No format change is
required to close C1** — reading the right column closes it.

### What the reversal costs, stated rather than buried

- **The heading-section records are invisible to the gate.** `docs/agy-capstone-ledger.md:456` records
  Phase 2 as a `##` section, not a row, so its range is not in any field 2. This is a **convention
  obligation**, not a code one: a record that must be gate-visible has to be a table row. The token design
  had the identical limitation, so nothing was lost in the trade.
- **The gate calls `git rev-parse` per candidate row.** That is the git dependency C8 already names,
  arriving for real. It is bounded — 42 rows across both ledgers today — and every input is hex-validated
  first.
- **A hand-written row still passes**, exactly as the spec has said from the start. The gate proves a row
  exists, never that an audit happened.

### ⚠ F7 CHALLENGED AGAIN AT CAPSTONE ROUND 2, AND UPHELD BY THE OWNER (2026-09-06)

Having found a second and then a third input channel into the line-oriented parser, the reviewer argued
the FRAME is wrong: *"Attempting to parse markdown with a line-by-line regex tool like `awk` is
fundamentally flawed because `awk` lacks block scope awareness … the structural change that makes this
moot is to extract the ledger data using a proper markdown AST parser, or to strictly parse only the
final N lines."* Two rounds of evidence stand behind that — fenced blocks, tilde fences, nested fences,
and an unclosed fence that blinded the live set.

**The owner ruled: keep the parser and keep hardening.** The reasoning, recorded so a later reader can
judge it rather than trust it: every channel found is now closed and mutant-pinned; an unparseable file
fails CLOSED with a NAMED cause (`MALFORMED unclosed-code-fence`) rather than silently; the ledgers are
this repository's own artifacts rather than hostile input; and a third design for one gate in one session
would spend the remaining rounds writing new code instead of finding defects in what ships — the
capstone's actual job.

🔴 **THE HONEST COUNTER, KEPT BECAUSE IT MAY YET BE RIGHT:** the argument for hardening gets weaker with
every channel found. Two rounds produced three. If a later round finds a fourth in the same class, that
is the signal to reverse — **not** a fresh argument about elegance.

### What it saves, which is why the reversal was taken

No ledger format change. No writer. No format linter, so no diff-scoping problem. No migration, so none
of the half-migrated states round 3 called worse than never starting. **It works on all existing history
immediately** — 42 rows visible on day one, where the token design would have seen zero.

## Sequencing

**The line-level plan is UNBLOCKED as of 2026-09-06** — every fork is ruled, so a plan can cite real
lines in code that exists. The BUILD remains the owner's to schedule; §26 (the footprint analyzer) is
also spec-written and unbuilt, and the owner sequences the two.

**What the plan must carry, derived from the rulings rather than restated from them. 🔴 THE ORDER BELOW
IS LOAD-BEARING — round 3 found that the obvious order breaks the repository partway through.**

> ⚠ **The F7 reversal deleted this list's first step entirely.** It used to open with a ledger format
> change, its writer and a diff-scoped format linter. There is no format change any more, so there is
> nothing to migrate and nothing to lint — which is the single largest reason the reversal was worth
> taking. What survives is round 3's *ordering* lesson, which was never about the token.

1. **The discipline skills learn the ordering — row before marker (C9).** 🔴 **THIS MUST LAND BEFORE THE
   GATE, and round 3 is why.** A gate that arrives first refuses every agent still following the old,
   unspecified ordering, so the repository would spend the gap actively breaking compliant runs. Prose
   landing early is harmless; the gate landing early is not. Both plugin halves, a `writing-skills`
   change, twin mirrored in the same commit.
2. **A new sourced helper** (F4) beside `agy-shield-lib.sh` carrying the field-2 parser, plus its Pester
   suite, its `_partition.md` row, and its `justfile`/CI registration. **That registration is an explicit
   list, not a glob** — the orphaned-test class of §36. **Its suite must include the 21 rows the parser is
   required to SKIP**, not only the 37 it must read: a parser proven only on the rows it accepts has no
   evidence it rejects the anomaly table.
3. **The `head` arm gains the gate and the F6 override flag, LAST**, mirrored byte-identically into
   `clavity-classic/plugin/hooks/` in the SAME commit (C5), with `check-seed-artifacts-synced.sh` green.
   **The refusal message must distinguish its two causes** — no row for this sha at all, versus a row
   whose range column could not be parsed or resolved. Round 3's Blindspot seat noted that "write the
   row" is a misleading diagnostic for an operator looking straight at the row they just wrote.
   🔴 **ROUND 5 ARGUED THIS IS MECHANICALLY IMPOSSIBLE, AND IT IS — UNDER THE RULE AS THE SPEC STATED IT.**
   A row skipped by hex validation is indistinguishable from a separator, so a gate that only skips
   cannot report what it skipped. **The mechanism it needs was already required one step earlier and the
   spec simply never connected them:** round 4's row-shape rule (a row must carry the ledger's full column
   count) is exactly what separates a MALFORMED RECORD from a separator or a prose line. So the
   classification is: a line with the full column count whose range token fails to parse or resolve is a
   **malformed record** and is REPORTED; anything else is **not a record** and is skipped silently.
   Without that connection the requirement really would be unmeetable, which is what the round found.
4. 🔴 **THE DOCUMENTS AND TESTS THIS CHANGE MAKES STALE — round 5's whole subject, and the class this
   repository loses most work to.** None of these were in the blast radius before:
   - **`docs/agy-disciplines-marker-contract.md`** declares itself at `:3` the *"Single source of truth
     for the debounce marker"*, and `:55` states the skill writes the marker **"only at that discipline's
     terminal state"**. That stays true and stops being *sufficient*: after the gate, a terminal state is
     necessary and a ledger row is also required. A document that calls itself the single source of truth
     and omits a refusal condition is the False Safety Promise shape this spec already names elsewhere.
     ⚠ It also records at `:56` that `agy-first` writes a marker — and `agy-first` owns **no ledger**, so
     under F1/F5 the gate correctly does not apply to it. That consistency must survive the edit.
   - **`scripts/tests/agy-mark.Tests.ps1`** was never named in this plan. The `head` arm gains a refusal
     path and an override flag; both need rows there, not only in the new helper's suite.
     ✅ **The EXISTING rows survive unchanged, and that is a measured consequence of F1/F5:** the suite
     builds its fixture as a temp directory with a `.clavity/` and **no `docs/`**, so no ledger exists, so
     the gate does not apply and every current row still passes.
     🔴 **The corollary is the vacuity trap: the NEW rows must CREATE a ledger in the fixture**, or they
     exercise the not-applicable path and prove nothing while looking green. Every new row is
     mutant-proven with the ledger present.
   - **`agy-mark.sh:57`'s own header comment** says a refusal means *"this script's own caller is
     malformed"* and that both failures are *"terminally fatal with no programmatic recovery"*. After
     this change a refusal can also mean the ledger lacks a row, and the F6 flag **is** a programmatic
     recovery. The comment is load-bearing documentation in a file whose header is explicitly "the entire
     contract" — it must be edited in the same commit.
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
  The decision the finding exposed was real; the claim that one answer was compelled is what is rejected.
  ⚠ Superseded in substance by the F7 reversal — there is no token to write, and the gate expands the
  ledger's existing 7-char endpoint through git, which is the very move this stand-down said was open.`
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
- **The token's format was undefined and was pinned here**, including the choice of a tool-written 40-char
  sha over a hand-written short one. ⚠ **SUPERSEDED — there is no token any more.** Round 3 killed this
  format by measurement and the owner then reversed F7 entirely; the bullets in this round-2 block are
  kept as the record of how the design got there, not as a description of what is being built.
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

**▶ F7 REVERSED BY THE OWNER, 2026-09-06, ON ROUND 2's CHALLENGE.** The driver put the challenge up with
both options costed; the owner dropped the token and took the range-column parse. **The review process
paid for itself here rather than in any single finding:** round 2 questioned the ruling, round 3 killed
the fix that ruling produced, and the reversal removed a format change, a writer, a linter and a
four-step migration from the plan — replaced by a parser measured at **42/42 endpoints resolvable, 0
false positives, 21/21 non-sha values correctly skipped before git is called.**

**AGY-AFTER round 4 — folded 2026-09-06.** Brief `.clavity/seams/panel-s27-r4.md`. Rotated onto a third
bespoke seat, **Parser Adversary** — "what input makes this parser answer confidently and incorrectly" —
plus Mechanism Gamer, Cascade Analyst, Axiom Breaker and Blindspot Auditor. Five findings; citations again
verified mechanically, **`0 problem(s) across 5 row(s)`** against `bd629fb`. Envelope clean.

- 🔴 **The round found the spec describing its own measurement wrongly.** "Field 2" under a delimiter
  split is the DATE, not the range — `$1` is the empty string before a leading `|`. The measurement had
  used `$3` and was right; the sentence was wrong, and a literal implementer would have built a gate that
  **refuses every marker write, permanently.** Both failure modes measured, including that an unhyphenated
  date is pure hex.
- **One proposed fix was REJECTED on a measurement** — scanning every token in the range cell would let a
  fold commit quoted in that cell's parenthetical prose authenticate a marker
  (`agy-capstone-ledger.md:69-70` carry exactly that shape). The finding was accepted as a documentation
  duty instead. **Third time this session a true finding arrived with a wrong fix.**
- **Two unstated invariants are now written down:** every row begins with `|` (GFM does not require it,
  and a row without one is invisible to the gate), and a row must carry the full column count so a
  one-line fragment cannot authenticate a sha.
- 🔴 **THE DRIVER'S OWN GUESS WAS WRONG AND THE PEER CORRECTED IT.** Asked where the design was weakest,
  the driver proposed that escaped-pipe safety rested on today's data. It does not: a delimiter shifts
  only *subsequent* field indices, and the range column precedes the prose column. That upgraded a
  measured coincidence into a structural argument — the single best outcome available from a
  "disagree with my guess" question.

**AGY-AFTER round 5 — folded 2026-09-06.** Brief `.clavity/seams/panel-s27-r5.md`. Rotated onto a fourth
bespoke seat, **Obligation Auditor** — "what else does shipping this oblige, that nobody has written
down" — plus Literal Implementer, Protocol Pedant and Blindspot Auditor. Four findings; citations
verified mechanically, **`0 problem(s) across 4 row(s)`** against `efa398d`. Envelope clean.

- **The round's subject was this repository's dominant defect class, and it found three unlisted
  obligations** — the marker contract, `agy-mark.Tests.ps1`, and `agy-mark.sh`'s own header comment.
  All three are now in the plan list.
- 🔴 **One MATERIAL finding turned out to be worse than the round argued.** It said the override's
  `skipped.log` status token was undefined. Measured, the obvious guess is actively unsafe:
  `agy-mark.sh:91-93` records that the file **is read** for `WAIVED` lines to decide whether a capstone
  was waived in a range, so logging the override as `WAIVED` would forge an attestation. The token is
  `GATE-OVERRIDE`.
- **One BLOCKING finding was true against the spec and dissolved on connection rather than on argument.**
  The two-cause refusal message *is* impossible under a rule that only skips — but round 4's row-shape
  requirement already supplies the distinction, and the spec had simply never joined them.

## ✅ TERMINAL DISPOSITION — `cap-reached`, owner-ruled 2026-09-06. **NOT GREEN.**

🔴 **FIVE ROUNDS. NONE CLEAN. EVERY ONE BLOCKING.** Rounds 2, 3 and 4 each found their defect in the
previous round's fold or its description; round 5 found what the folds did not say. At the discipline's
hard cap of 6 the driver halted and asked, and **the owner ruled: ship the spec, write the plan.**

**This review closes as `cap-reached`, NOT as `GREEN`, and the distinction is the record's whole value.**
GREEN would mean a full round landed with no live challenge. That never happened. What is claimed is
narrower and true: **every finding raised across five rounds carries a disposition** — folded, or rejected
on a quoted measurement, or stood down below the floor with its guard cited — and the driver's
recommendation to stop rested on the shape of the findings changing, not on their supply drying up.
Round 5 produced **no design defect at all**; it produced three obligations the spec had not listed. That
is plan-shaped work, and a plan is the better instrument for it, because it forces each obligation into a
numbered step with a file path instead of a paragraph.

⚠ **What a later reader must NOT take from this section.** Not that the spec is proven correct — five
rounds of BLOCKING findings are evidence against any such reading. Not that review was exhausted — it was
stopped. The honest summary is that the design survived four rounds of adversarial attack on its
correctness and a fifth on its completeness, was rebuilt twice along the way, and is now good enough to
plan against **with the plan itself owed a review of its own.**

**AGY-AFTER is therefore SATISFIED for this artifact and RE-ARMS for the plan.** The plan is a new
artifact; it gets its own panel.
