# AGY policy gate - implementation spec

**Status:** owner-approved 2026-08-13. **Build from THIS file.**
**Supersedes in part:** `2026-08-13-agy-role-enforcement-design.md`, now a frozen ADR. That document
records WHY; this one records WHAT. Where they differ, this file wins.

**This ships with the plugin to end-user machines.** Every requirement below is written for a stranger's
repository on a standard Windows box, not for the author's machine.

---

## 0. THE NORMATIVE SET - build from this section; the rest is why

**Round 8's Signal-to-Noise Auditor asked whether an implementer can still find the requirements in
here, and the answer was no.** Measured: **15% of this file is round-by-round fold history, and 39 more
lines inside the "normative" sections narrate a past state rather than state a requirement.** At least
one real constraint (`jq -r`) existed **only** inside a historical table. **A requirement an implementer
cannot find is a requirement that will not be built** - and this file's header says *"build from THIS
file"*.

**Everything below this section is rationale, provenance and correction history. This is the contract:**

| # | requirement | where the reasoning lives |
|---|---|---|
| N1 | A payload naming a path under `.clavity/seams/` ending `.md` requires a non-empty `PANEL-SEATS:` line in that file, else **block (exit 2)**. | 2 |
| N2 | **Check ALL named seams; any one violating blocks.** Guaranteed in dotnet, best-effort in classic. | 2, 3a |
| N3 | **Evaluate the skip token FIRST** - a valid `AGY-SKIP: ROLES <reason>` exits 0 - **but extract the seam anyway so the log names it.** | 4, 7 |
| N4 | A hook honours **only** a skip naming its own rule; a bare `AGY-SKIP:` never skips. | 7 |
| N5 | Infrastructure failure **never causes a block and never prevents one**. Every error path exits 0. | 4 |
| N6 | **Log every decision it can record**, with a reason code, TAB-delimited: `<iso8601-utc> <rule> <reason> <seam> <detail>`, empty fields as `-`. Failures of the logging substrate itself are unloggable. | 4a, 8 |
| N7 | `mkdir -p` and the shield run whenever a seam path was **named**; a payload naming none writes nothing. **The shield asserts CONTENT** (`grep -qx '\*'`), never `[ -f ]`. | 8a |
| N8 | Rotate at 500 lines, attempting only when `count % 100 < 5`. Best-effort; unbounded growth accepted where `mv` cannot succeed. | 8 |
| N9 | Resolve plugin paths with `dirname "$0"`. **Never `${CLAUDE_PLUGIN_ROOT}`.** | 5 |
| N10 | **Invoke `jq` with `-r`.** Without it the path arrives quoted, `[ -f ]` fails, and the gate fails open silently on every call. | 13 |
| N11 | Block message, in order: what is missing + the peer was not contacted; the literal path `adversarial-panel-review/SKILL.md`; what the check cannot do; the skip token. **Written per product.** | 6 |
| N12 | dotnet: a NEW entry matching `mcp__.*agy_ask` alone. classic: **no new entry** - the check joins the existing per-command hook, and **must not merge its control flow**. | 3, 3b |
| N13 | **`adversarial-panel-review/SKILL.md` must teach the `PANEL-SEATS:` line, shipping with or before the gate.** Measured: 0 skills teach it today. | 2 |
| N14 | The SessionStart reader surfaces counts by reason over `policy.log` **and** `policy.log.1`, and **skips lines it cannot parse** rather than failing the session. | 8, 11a |

## 1. What this builds

**ONE thing, plus the generic infrastructure a later tenant will reuse.**

1. **A policy gate** that refuses an AGY-* peer consult whose seam file names no adversarial roles. Its
   first and only rule in this build is `ROLES`.

**This section previously said "two things", the second being a productised POWER-FAILURE nudge. That is
no longer in this build** - it was extracted to its own design and then **deferred by the owner to a
future release** (2026-08-13). Sections 9 and 9a are retained as INPUT to that separate spec and are
marked DO-NOT-BUILD. **This paragraph exists because the summary sentence outlived the decision** - the
same drift that a sibling spec's scope line suffered, caught there in review.

The infrastructure - the skip token, the log, the SessionStart reader - is built
**generic from the start**, because further tenants are already named and deferred: `OPEN-PROPOSAL`,
`NEGOTIATED`, and a future stateless form of power-failure. Naming these artifacts generically now costs
nothing; renaming them later would migrate files users already have.

## 2. The predicate

> **If the tool payload names a path under `.clavity/seams/` ending in `.md`, that file MUST contain a
> non-empty `PANEL-SEATS:` line. If it does not, block.**

**What `PANEL-SEATS:` is, and which discipline owns it - because six panel rounds never said.** The
marker is the seat list required by **AGY-AFTER**, the `adversarial-panel-review` discipline: its palette
of adversarial seats, and its rule that a review names them rather than convening a panel from memory.
**This gate is AGY-AFTER's enforcement mechanism, and until the owner pointed it out this document named
the discipline exactly once - in a DO-NOT-BUILD section, as an aside about an unrelated migration.**

That gap was not cosmetic. It is why section 6's block message pointed at *"the consulting discipline's
own `SKILL.md`"* - a target the hook cannot derive - for six rounds: **a document that never names the
discipline it enforces cannot name the file that documents it.** Six rounds reviewed this spec against
itself; the gap was only visible from outside, by asking what the gate is FOR.

**The rule stays discipline-agnostic in its PREDICATE** - any seam under `.clavity/seams/` is checked,
whoever wrote it - **and discipline-specific in its REMEDY**, because there is exactly one place the
seat vocabulary is defined.

Nothing else is inferred. No discipline is detected, no keyword is matched, no prose is parsed beyond
one narrow path shape. This is deliberate and load-bearing: any predicate requiring the driver to label
the consult would fail exactly when the driver is working from memory, which is the failure being
guarded.

The predicate is total because a standing rule already constrains every consult - point the peer at
files, never at a pasted summary - so every AGY-* consult names a seam. A payload naming no seam path
**fails open**: that is a violation of a different rule and not this gate's business.

**Producing a seam without roles therefore means DELETING a line, not forgetting to add one** - **and
that sentence is FALSE until the convention ships. It is the most dangerous claim in this document.**

> **Measured, and it inverts the gate's risk profile:**
>
> ```
> shipped skills mentioning PANEL-SEATS      : 0     (both plugin trees, zero occurrences)
> seam files on disk                         : 564
> carrying a PANEL-SEATS line                : 6
> would BLOCK on day one                     : 558
> CONTROL - which 6 pass? exactly the six panel seams written while drafting THIS spec
> ```
>
> **No skill has ever told anyone to write that line.** So an author omitting it is not deleting a
> guard, they are failing to add a marker nobody taught them - **the exact "forgetting" failure mode
> this sentence claims is impossible.** As specified, enabling the gate would block essentially every
> consult on day one, for every user, including the author.
>
> **The control is the part worth keeping.** The only seams that pass are the ones written this session
> while dogfooding an unbuilt spec. **My own compliance manufactured the appearance of an existing
> convention**, which is why six adversarial rounds looked at this predicate and none asked whether the
> marker was something anyone actually writes.

**Two requirements follow, and they are sequencing requirements, not features:**

1. **The convention must SHIP BEFORE OR WITH the gate.** `adversarial-panel-review/SKILL.md` - and every
   discipline whose seams this predicate covers - must instruct the author to write a `PANEL-SEATS:`
   line, in the same release. A gate for a convention that does not exist is a trap, not a floor.
2. **Until a repository's seams carry the marker, the gate has nothing legitimate to enforce.** The
   build surface carries the skill edits (section 10); **they are not optional companions, they are the
   half that makes the other half safe.**

**Historical seams are not the problem the number suggests.** Each consult writes a NEW seam, so the 558
are mostly inert history that will never be re-consulted. The live risk is the first consult after
install, not a migration of the back catalogue - but a re-consult naming an old seam does block, and
that is stated rather than discovered.

## 3. Two hooks, and they are NOT byte-identical

This is the one place the two products genuinely diverge, and it is an owner ruling.

| product | matcher | how it finds the seam path |
|---|---|---|
| clavity-dotnet | a **NEW** entry matching `mcp__.*agy_ask` ALONE | `jq` over the MCP tool payload |
| clavity-classic | **no new entry** - the check is added to the hook already registered on `Bash\|PowerShell\|mcp__.*agy_ask` (section 3b) | exits 0 immediately unless the command is a `clavity ask`; then string-extracts the path |

**The dotnet entry must NOT extend the existing `Bash|PowerShell|mcp__.*agy_ask` entry**, which would
put this check on every shell command in the session.

**clavity-dotnet additionally changes its skills so subagents consult over `agy_ask`** rather than
`clavity ask --review-only`, which brings subagent consults under the matcher by construction.

**Measured, because the count matters to the edit list:** exactly **three** skills carry the subagent
parenthetical *"(subagents use the CLI form, not the MCP bus)"* - `agy-first`, `agy-capstone` and
`agy-test-audit`. **`adversarial-panel-review` does NOT** (zero occurrences); it names the classic CLI
transport generally, without routing subagents to it. So three skills need the subagent sentence
changed, and the fourth needs only its transport line checked for consistency - do not edit it blindly
to match the others.

**Ordering is a requirement, not an implementation detail (round 1's Resource Vampire).** The classic
hook fires on **every** `Bash|PowerShell` command in the session. It **MUST** do the cheap in-process
command test first and `exit 0` before it spends a subprocess or touches the filesystem - **no
`git rev-parse`, no `mkdir`, no shield assertion, no log** until the command is known to be a
`clavity ask`. Section 8a's "re-assert on every invocation" means every invocation **this gate is
responsible for**, not every shell command the user runs. Getting this backwards puts a `git` process
on the critical path of every `ls`.

**The dotnet hook has no such exposure** - its matcher selects the MCP tool directly, so every
invocation is already a consult.

### 3a. What each product can actually GUARANTEE - the requirements are not equally satisfiable

Round 3 seated an auditor to walk every requirement against both hook forms, and it found rules written
as absolutes that only one product can meet. **A requirement one product cannot satisfy is not a
requirement; it is a latent implementation divergence.**

| requirement | dotnet (MCP payload, `jq`) | classic (arbitrary shell command, string test) |
|---|---|---|
| find the seam path | **reliable** - a structured field | **best-effort** - already conceded as "knowingly leakier" |
| **CHECK ALL seam paths** (round 1) | **guaranteed** | **BEST-EFFORT ONLY.** Shell strings carry quoting, flags and interpolation; no substring pass reliably isolates every `.md` path. **So the multi-seam smuggle is CLOSED in dotnet and MITIGATED in classic** - say so rather than writing CHECK ALL as absolute in both |
| identify the invocation as a consult | **by matcher** - certain | **by string test** - see the shape below |
| the skip token | **in the payload TEXT** - the `message` string of the `agy_ask` call, not a separate JSON key | **goes in the payload TEXT itself** - inside the existing `clavity ask "<payload>"` string, alongside the prose. Never as an extra argument, and never appended bare after the closing quote |

**The command test's SHAPE was never specified, and left loose it corrupts the metric.** A bare
substring match for `clavity ask` fires on `echo "run clavity ask"` and on
`history | grep 'clavity ask'`. Harmless on its own - but section 4a now logs a `no-seam` outcome for a
consult with no path, so **every false positive would record a bypass that never happened and inflate
the exact count section 4a asks a human to trust.**

> **Classic matches `clavity` and `ask` as ADJACENT COMMAND WORDS, wherever they appear** - never as a
> free substring inside a longer word. Residual false positives are accepted and **must not** be chased
> with a shell parser.
>
> **And classic logs `no-seam` ONLY for an invocation it identified as a consult by that test.** A
> command that merely mentions the string is not a consult and writes nothing.

**The earlier version anchored to the START of the command (or just after a `;`, `&&`, `||` or `|`), and
round 5 showed that leaks.** Any leading word defeats it, and the ones a stranger's box supplies are
ordinary: `time clavity ask`, `sudo clavity ask`, `env FOO=1 clavity ask`, `nice clavity ask`, or a
shell alias or function that prepends anything at all. **A wrapped consult would evade the gate
silently and log nothing** - no block, no `no-seam`, no trace.

> **Do not name a specific wrapper here, and do not use one as a fixture.** An earlier version of this
> paragraph justified the rule with a command-rewriting wrapper that exists on the AUTHOR's machine.
> **Section 9a of this same document already forbids that** - *"a shipped hook must assume no such
> wrapper exists"* - so the requirement was right and its justification imported the exact assumption
> the document had banned. **The rule stands on wrappers that ship with the OS**; anything narrower is
> an author-machine assumption wearing a rationale.

> **The trade is deliberate and it goes toward VISIBILITY.** A looser test admits some false positives,
> each of which writes one `no-seam` line a human can inspect. A tighter test admits silent bypasses,
> which write nothing. **Section 4a's entire argument is that a bypass must be countable, so a rule that
> trades a visible false positive for an invisible miss contradicts it.** Prefer the noisy failure.

**The block message must therefore show the token in the form the reader's product needs** (section 6):
one static message per product, not one string shared by both. This is the same divergence section 3
already accepts for the hooks themselves.

**Consequences to handle, not discover:**
- `plugin-hooks-payload.Tests.ps1` asserts byte-identity for the shipped hook pair. **It must change** to
  exempt this pair, and the exemption must be explicit and named, never a loosened glob.
- **clavity-classic's gate is knowingly leakier.** Extracting a path from an arbitrary shell command is
  fragile against piping, aliases and quoting. It fails open when extraction fails. This is accepted;
  state it in the classic hook's header comment so the next reader does not treat it as a bug.

### 3b. The LATENCY budget - measured, and it changes the classic registration

**Five panel rounds folded 27 findings and not one asked what this gate COSTS.** The owner did. Measured
on this box with the driver idle (N=40 per row), because a prior attempt run while the driver was busy
produced numbers inflated enough to be useless:

| | ms/call |
|---|---|
| control floor - no process at all | **28** |
| `bash -c 'exit 0'` | **379** (and a repeat of the identical row: **293**) |
| classic fast path: startup + string test + exit | **521** |
| + `git rev-parse` | 496 |
| + `jq` on a payload | 520 |

**Read the ratio, not the milliseconds.** The two identical baseline rows differ by 86ms, so no single
figure here is precise. What is unambiguous is the shape: **a registered hook costs roughly 10-13x the
harness floor before it does anything**, process startup is 60-75% of the total, and **every row that
does real work is within noise of the row that does none.** The repository's own prior measurement
agrees - `agy-liveness-check.sh:128-129` records *"bash itself is ~455ms and each additional fork
~126ms"* - and `agy-discipline-reaching.sh:2` declares *"CAPTURE ONLY, NO SUBPROCESSES"* for this reason.

**Two consequences, and the second changes the build:**

1. **Section 3's ordering rule is nearly cosmetic on Windows, and must not be sold as a performance
   fix.** Doing the cheap string test before spending a subprocess saves a *fork* (~126ms) out of a
   ~400ms floor the hook has already paid by existing. It is still correct - a fork saved is a fork
   saved - but the dominant cost is incurred at registration, not at branch time.
2. **clavity-classic must NOT add a second script on a matcher it already occupies.** It already runs
   `agy-consult-guard-pre.sh` on `Bash|PowerShell|mcp__.*agy_ask`. A second hook on the same trigger
   means **two full interpreter startups on every shell command in the session** - the largest single
   cost in this design, doubled, to run a test that is free once bash is up.

> **Requirement: in clavity-classic the ROLES check is added to the EXISTING per-command hook, not
> registered as a new one.** Section 10's build surface reflects this. **dotnet keeps its own new
> script**, because it fires only on consults - where a peer round-trip already costs seconds and a
> hook startup is invisible. **Not because the slot is empty; it is not (below).**

**Two integration facts round 7 established by reading the registrations, and the first corrects the
paragraph above:**

```
clavity-dotnet  PreToolUse  matcher "Bash|PowerShell|mcp__.*agy_ask"  -> agy-consult-guard-pre.sh
clavity-classic PreToolUse  matcher "Bash|PowerShell|mcp__.*agy_ask"  -> agy-consult-guard-pre.sh
```

1. **dotnet ALREADY has a hook on `mcp__.*agy_ask`.** So a new dotnet entry means **two hooks fire on
   every dotnet consult**, not one. The latency conclusion still holds - a consult costs seconds, so a
   second ~400ms startup is invisible there, which is exactly why dotnet can afford a separate script
   and classic cannot. **But "its matcher fires only on `agy_ask`" implied the slot was empty, and it
   was not.** The two hooks write different files and do not race; the requirement is simply that the
   implementer knows both will run.
2. **Merging the ROLES check into `agy-consult-guard-pre.sh` must not short-circuit that script's own
   logic.** It categorises the call (`agy_guard_category`) and writes a VCS baseline for consults,
   exiting 0 at `:27` for everything else. **An early `exit 0` for "not a `clavity ask`" placed at the
   top would skip the baseline write for calls the guard does care about** - the ROLES test and the
   guard's categorisation are different predicates and neither may gate the other.

> **Requirement: the ROLES check runs as an INDEPENDENT stage that cannot prevent the existing guard
> from running, and the existing guard cannot prevent it.** The only shared early exit is the one both
> already agree on: not a tool this hook handles at all. **A merge that saves a process must not merge
> the control flow.**

**This is the same principle section 10 already applies to SessionStart** (*"Extend one rather than
adding a fourth script"*), which the classic gate was quietly violating.

## 4. Fail OPEN on error, fail CLOSED on a violation

- **An infrastructure failure never CAUSES a block - and never PREVENTS one.** No `jq`, unreadable file,
  unresolvable path, a `bash` that is not Git Bash, a seam that does not exist yet at PreToolUse time.
  On its own, each exits 0: a broken hook must never paralyse a stranger's session.
  - **The earlier wording was "ANY infrastructure failure exits 0", and round 4's Absolutes Auditor
    falsified it with the precedence rule below**: a payload naming a violating seam AND an unreadable
    one exits **2**, so an infrastructure failure demonstrably does not always exit 0. **The rule was
    never about the failure's exit code; it was about the failure not being allowed to decide.** Stated
    that way it survives the counter-example - and it is the fourth absolute in this document to need
    scoping.
  - **`sed` was in this list and is struck.** Round 2's census flagged it as an unlogged fail-open path;
    it is not a path at all - **the only thing that used `sed` was the palette extraction section 6
    deleted**, and this line outlived it. A dependency listed in an error table that the design no
    longer has is worse than harmless: an implementer adds a probe for it, and a reviewer counts a
    branch that will never execute.
- **A positively-detected violation blocks.** The payload named a seam, the hook read it, the marker is
  absent or empty. That is policy, not error.

*Absence of evidence fails open; evidence of absence fails closed.*

**Precedence when one payload produces BOTH verdicts - round 2 found this unresolved and it is not a
detail.** A payload can name two seams: one that exists and lacks the marker (a positive violation,
which mandates block) and one that does not exist (an infrastructure failure, which mandates exit 0).
The two rules gave contradictory instructions and the document did not say which won.

> **A positive violation on ANY named seam BLOCKS, whatever the other seams did.** Missing, unreadable
> or out-of-repo seams contribute a log line and **never veto a block**. This follows from the axiom
> rather than overriding it: a seam that was read and lacks the marker IS evidence of absence, and no
> amount of *unknown* about a sibling path turns known-bad into unknown.

**And it closes the smuggle the multi-seam rule exists to prevent.** If a missing seam could force
exit 0, naming one alongside a real consult would be a two-character bypass - which is the same hole
round 1 closed by requiring all seams to be checked, reopened through a different door.

**A valid skip token BEATS a positive violation. That is what a hatch is, and the document never said
it.** Round 4's narrator walked a consult carrying both - a seam with no marker AND a well-formed
`AGY-SKIP: ROLES <reason>` - and found two rules giving opposite instructions with no precedence
between them:

| rule | says |
|---|---|
| section 4 | *a positive violation on ANY named seam BLOCKS* |
| section 7 | the hook *MUST honour* a skip naming its own rule |

> **Order of evaluation, stated once so no implementer guesses: check the skip token FIRST.** A valid
> `AGY-SKIP: ROLES <reason>` short-circuits to `exit 0` and is logged as `skip`, whatever the seams
> would have said. **A hatch that a violation can override is not a hatch** - it would open only when
> nothing was wrong, which is precisely when nobody needs it.
>
> **But the DECISION short-circuits, not the RECORD.** Round 8: extracting the seam path is cheap and
> already done, and a `skip` line logging `-` for the seam **loses the only fact that makes the skip
> count actionable - WHICH review was waved through.** Extract the seam, then skip: the log names it.

**This makes the skip count in section 8 load-bearing rather than decorative**, which section 6 already
anticipated when it accepted that a static block message makes the token relatively cheaper.

### 4a. Every fail-open outcome is LOGGED with its own reason code

Round 1 found two silent bypasses, and neither needs the axiom above to change - **they need the
outcome to stop being invisible.**

- **A named seam that does not exist on disk** exits 0 today. An agent that names
  `.clavity/seams/ghost.md` - by hallucination, by typo, or deliberately - passes the gate with no
  trace. (The consult is broken either way, since the peer is meant to read that file, but the *gate*
  was still bypassed.)
- **A payload naming no seam at all** exits 0 by design (section 2), and that is correct - it is
  another rule's business. **But it is also the cheapest bypass in the design**, and nothing recorded it.

> **Requirement: the hook writes a log line for EVERY decision it is able to record, with a reason code
> distinguishing them** - at minimum `pass`, `block`, `skip`, `no-seam`, `seam-missing`,
> `seam-unreadable`, `outside-repo`, `no-jq`, `no-git-bash`. The SessionStart reader (section 8)
> surfaces counts by reason, not only skips.

**Any failure of the LOGGING SUBSTRATE ITSELF is unloggable, and no count of such paths should be
asserted.** The log lives in `.clavity/`, so `mkdir -p "$R/.clavity"` failing leaves nowhere to write
the record of that failure. **"EVERY decision" was unsatisfiable as written** - it collided with the
`|| exit 0` that the same round-1 fold introduced.

> **The unloggable set is "the logging substrate failed", not an enumerated list.** It includes at
> least: `mkdir` failure, and an append that fails because `policy.log` is locked (ordinary on Windows)
> or its permissions changed. All exit 0 and are invisible. **A repository where this happens has
> larger problems than this gate.**

> **THE THIRD FALSE ABSOLUTE IN THIS DOCUMENT, AND THE PATTERN IS THE FINDING.** Round 1 struck *"the
> log must not be forgeable by the thing it audits"*; round 2 struck *"a log line for EVERY decision"*;
> round 3 struck *"EXACTLY ONE fail-open path cannot be logged"* - **which was itself round 2's
> replacement for the previous absolute.** Each was written to sound rigorous and each was falsified by
> one counter-example. **Prefer a scoped claim with its exceptions named over a total one that reads
> better**; in a document about a gate that fails open, an overstated guarantee is the exact failure
> mode being guarded against.

**What countability actually buys, scoped honestly.** The gate cannot stop an agent that omits the seam
path; nothing local can. Logging makes the omission **countable**, so a driver that routinely bypasses
shows up as a number a human reads at session start.

> **Round 2's Axiom Breaker is right that this is no answer to an ADVERSARIAL agent** - it owns the
> filesystem and can delete the log before anyone reads it, which section 8 already concedes. **The
> claim is therefore scoped to the actor this gate was actually built for: a driver working from memory
> who omits the roles without meaning to.** Negligence leaves the count; malice removes it. Calling
> countability "the design's real answer to gaming" - as an earlier draft of this paragraph did - was
> the second overclaim in this document, and section 12 already concedes the adversarial case.

**Exit code 2 BLOCKS on PreToolUse.** That is the mechanism, and it is why every error path above must
reach `exit 0` instead.

## 5. Locating plugin files - use `dirname "$0"`, never `${CLAUDE_PLUGIN_ROOT}`

Resolve any plugin-relative path from the script's own location:

```sh
here="$(dirname "$0")"
```

**Do not use `${CLAUDE_PLUGIN_ROOT}` in a hook body.** Measured: `agy-consult-guard-pre.sh` contains
zero occurrences of it, and only 1 of 13 hook bodies reads it at all - there is no precedent to lean on.
Unset, it collapses a path to an absolute `/skills/...` that cannot be opened. The repo's own idiom is
`agy-liveness-check.sh:126`. `dirname "$0"` cannot be unset.

## 6. The block message - a repair kit, in this order

1. **One line stating what is missing AND that this is a local role check - the peer was never
   contacted.** Every AGY-* discipline has an `agy-required-but-unreachable` terminal that halts and asks
   a human; a driver who misreads a block as a channel failure halts for an outage that never happened.
2. **A static pointer to where the seats are defined:** the literal path
   `clavity-*/plugin/skills/adversarial-panel-review/SKILL.md`, hardcoded.

   > **This said "the consulting discipline's own `SKILL.md`" and that is not implementable.** The
   > payload carries a seam path, not a skill; the hook is deliberately generic and cannot know which
   > discipline is consulting. **Round 6 found it underivable and the owner found the reason: this
   > document never names AGY-AFTER at all.**
   >
   > **`AGY-AFTER` - the `adversarial-panel-review` discipline - is what defines `PANEL-SEATS:`, and it
   > is the only correct target.** The gate exists to enforce that discipline's seat requirement, so the
   > pointer is static, fixed, and the same for every consult regardless of which discipline sent it.
   > That is exactly what section 6 already demanded when it deleted the palette extraction for
   > hardcoding one skill's path - **the right fix was to hardcode the one skill that owns the
   > vocabulary, not to derive a skill the hook cannot see.**
3. **One line saying what this check does NOT do**  *(the message is written PER PRODUCT, but NOT because the token differs - round 6 made the token identical prose in both. It differs because the surrounding EXAMPLE does: an `agy_ask` message field versus a `clavity ask "..."` command line. Round 7 caught section 6 still giving the superseded reason while section 7 stated the opposite.)* - it verifies a marker is present and non-empty, and
   **cannot** tell whether the seats are appropriate or the panel is real.
4. **The skip token, last** (section 7).

**Item 3 was missing and section 12 already required it.** Round 1's Blindspot Auditor put the two side
by side: section 12 states *"The block message must say so"* about the gate being a floor, and this
enumeration - which says *"in this order"*, so a literal implementer treats it as complete - listed only
three items and not that one. **A spec that mandates a disclaimer in one section and omits it from the
authoritative list manufactures exactly the blind spot it claims to prevent.**

**The block does NOT extract or inject a palette.** An earlier design extracted one between HTML-comment
delimiters. It is deleted, with its delimiters, its `sed`, its over-long bound and its empty-extraction
fallback. The reason is shipping: the palette path was hardcoded to one skill while the predicate covers
every seam, so a user running a different or custom discipline would be blocked and handed an
irrelevant repair kit. A static pointer is correct for every discipline, shipped or custom, and removes
roughly 60% of the implementation surface.

**Accepted cost, stated because it is real:** the seats no longer land in the terminal, so the driver
reads one file. That makes the skip token relatively cheaper, which is precisely why the skip count in
section 8 is load-bearing rather than decorative.

## 7. The skip token - generic, and honoured only by its own rule

**Format: `AGY-SKIP: <rule> <reason>`**, in-band in the payload. Example:
`AGY-SKIP: ROLES verifying the gate blocks`.

- **In-band means inside the PAYLOAD TEXT in BOTH products** - the `message` string of the `agy_ask` call in dotnet, and the existing `clavity ask "<payload>"` string in classic. **Round 6 caught that "a JSON field" in dotnet named no key**, which would have had the hook and the skill author each guess a different one and silently break every skip. There is no separate key: the token is prose inside the message, which is also why one static block message describes it correctly for both - `clavity ask "...prose... AGY-SKIP: ROLES <reason>" --review-only`. **Verified: `clavity ask`'s first positional IS the payload**, so a token inside that string is inert. Round 4 argued this would crash the CLI by being read as a file path; that requires appending it as a SEPARATE argument, which this rule forbids. **The claim is refuted, and the wording was tightened anyway because it was ambiguous enough to be misread.**
- **In-band, not an environment variable.** The agent invokes an MCP tool with a JSON payload and cannot
  set an env var for that call; an env-var hatch is reachable only by a human in a shell, which is a
  phantom for the actor it exists to rescue.
- **The reason is mandatory.** A token with a rule and no reason does not skip.
- **The skip is evaluated BEFORE the seams** (section 4). A valid token short-circuits to `exit 0` and
  logs `skip`, whatever the seams would have said - stated here too because an implementer reading only
  this section would otherwise have to infer the order.
- **A hook MUST honour only a skip naming ITS OWN rule.** A bare `AGY-SKIP:`, or one naming a different
  rule, does not skip this gate. Without this, one token disables every present and future gate at once
  - a wildcard bypass, and the more dangerous failure direction than a hatch that fails to open.
- The block message names the token verbatim, including the rule name.

## 8. Observability - generic artifacts, and the readers are part of the build

A fail-open gate that dies silently certifies what it stopped checking. Every decision - pass, block, or
skip - appends **one short sanitised line** to `.clavity/policy.log`.

- **One `printf` append. Never a read-modify-write.** A single short append is atomic on POSIX, so
  concurrent writers interleave lines rather than scrambling them.
- **Sanitise every agent-authored field** - the seam path and the skip reason - by stripping ALL control
  characters and whatever delimiter the record uses, then length-capping. Newline-stripping alone stops
  vertical forging and leaves horizontal forging open: a literal tab shifts every column of a
  tab-delimited record.

  > **Correction from round 1, because the original sentence overclaimed.** It read *"the log is the only
  > audit trail for the escape hatch, so it must not be forgeable by the thing it audits"*. **It IS
  > forgeable by the thing it audits** - the gate runs in the agent's own environment, and the agent has
  > shell write access to `.clavity/policy.log`; it can truncate, delete or rewrite it without going
  > near this hook. **Sanitisation buys record INTEGRITY, not tamper-resistance:** it stops an
  > agent-authored field from silently forging a *column or a row* in a record the hook itself writes.
  > A determined agent is out of scope for anything local, and saying otherwise manufactures the
  > confidence this document elsewhere warns against.
- **Bound by ROTATION, not truncation.** At 500 lines, `mv` the log to `.clavity/policy.log.1` and let
  the next append create a fresh file. Truncation (`tail -n 500 f > tmp && mv tmp f`) is a
  read-modify-write and drops any append landing mid-shuffle.
  - **Rotation is BEST-EFFORT.** On Windows, renaming a file another handle holds open fails rather than
    succeeding atomically. Attempt it, ignore failure, never let it fail the hook. The honest guarantee
    is "bounded on POSIX, best-effort on Windows".
  - **A failed rotation must not retry on every invocation.** Round 1's Dependency Cynic: if `mv` fails,
    the file is still over the bound, so the next call attempts the same doomed rename, and the next -
    **the "bound" is violated AND a subprocess is spent on every consult to violate it.**

    > **Attempt rotation when the line count is at least the bound AND `count % 100 < 5`.** That is the
    > whole rule. It caps wasted renames at ~5% of invocations, needs no clock, no session id and **no
    > state file**, and it stops entirely the moment a rotation succeeds.
    >
    > **The window is 5 lines wide, not an exact multiple, and round 6 is why.** This log is designed
    > for CONCURRENT atomic appends, so two writers can take the count from 99 to 101 and an
    > exact-match trigger is skipped entirely - **the rotation silently never fires for that cycle, in
    > exactly the concurrent case the append design exists to support.** A single append cannot step
    > over a 5-wide window.

    **Three rounds were spent inventing a session-scoped guard that this deletes.** Round 2 keyed
    rotation on "older than the current session" (a `PreToolUse` hook cannot observe that); round 3
    rekeyed it on the payload's `session_id` in a `.clavity/policy.rot` file (which trapped on the
    literal `default` when `jq` was missing, disabling rotation for ever); round 4 exempted the unknown
    case (which reinstated the original retry loop for degraded sessions). **Round 5's Simplification
    Auditor observed that round 4's modulo bound, applied universally, subsumes all of it.** The
    `policy.rot` file, the `session_id` read and every special case are **deleted**.

    **State the resulting guarantee honestly: on a host where rotation cannot succeed, the log grows
    unbounded and the design accepts that** rather than pretending a bound it cannot enforce.
- **There is NO degraded sentinel. `.clavity/policy.degraded` is deleted from this design.** It existed
  because a single hook on the combined `Bash|PowerShell|mcp__.*agy_ask` matcher could not tell a
  consult from a routine command without `jq`, so it could not log per-invocation without writing on
  every command. **Section 3 forbids that hook shape.** Under the split, each hook knows what it is
  looking at - dotnet by its matcher, classic by its string test - so **both can simply log `no-jq` to
  `policy.log` like any other outcome**, and the reader already parses that file.

  > Deleting it removes an artifact, a write path, a read path, a clearing rule, and **the race that
  > cost round 1 a finding** - a healthy agent deleting the sentinel a degraded sibling had just raised.
  > **The race is gone because the thing that raced is gone.** Nothing else changes: a human still
  > learns `jq` is missing, from a `no-jq` count in the same reader that surfaces the skips.
- **The RECORD FORMAT, pinned here rather than deferred, because section 8's sanitisation depends on the
  delimiter and the reader depends on the fields.** One line, TAB-delimited, fixed order:

  ```
  <iso8601-utc>\t<rule>\t<reason-code>\t<seam-or-->\t<detail-or-->
  2026-08-13T19:28:40Z    ROLES   block   .clavity/seams/x.md     -
  ```

  TAB is the delimiter, so **TAB is among the characters stripped** from the two agent-authored fields
  (section 8), and a field that would be empty is written as a literal `-` so the column count never
  varies. The timestamp uses `date -u +%Y-%m-%dT%H:%M:%SZ`, which needs no `jq`.

- **The SessionStart reader is a build row, not a someday.** It surfaces **counts grouped by reason code
  over the retained log**, and **it must read BOTH `policy.log` and `policy.log.1`**, or a mid-session
  rotation zeroes the count exactly when the hatch is being used most.

  > **It does NOT claim "since the last session", and an earlier draft did.** Round 5's Axiom Breaker
  > showed that claim was unsatisfiable: nothing in the record identified a session, so the reader could
  > not separate today's lines from months-old ones in the rotated file. **The fix is to correct the
  > claim, not to build machinery for it** - a session-scoped count would need either a session id in
  > every line (unavailable without `jq`) or a last-seen marker file, and the retained window answers
  > the operator's real question ("is this hatch being leaned on?") with no state at all.

### 8a. The `.clavity/.gitignore` shield is mandatory and re-asserted on EVERY invocation

```sh
R="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
mkdir -p "$R/.clavity" || exit 0
grep -qx '\*' "$R/.clavity/.gitignore" 2>/dev/null || printf '%s\n' '*' >> "$R/.clavity/.gitignore"
```

**Assert the CONTENT, not the FILE - round 8, and the shipped idiom has this bug.** The version this was
copied from (`open-issues/SKILL.md:79`) tests `[ -f ]`, which **passes on a zero-byte file**. Measured:
an emptied `.gitignore` leaves `[ -f ]` true while `grep -qx` correctly reports the shield missing, with
a properly shielded file as the control. So a shield emptied by hand, by a merge or by a tool is **never
restored, and the directory stays git-visible for ever** - the exact failure that
"re-assert on every invocation" exists to prevent. **Testing the container instead of the claim is how a
guard certifies what it stopped checking.** The shipped occurrence is captured for separate triage.

**But the gate must NOT create `.clavity/` for an outcome that changes nothing** - round 6's Cost
Auditor priced a footprint nobody had. Classic's consult test is deliberately loose (section 3a), so
`git commit -m "fix clavity ask"` is identified as a consult, finds no seam, and would - under a naive
reading - **create a `.clavity/` directory and a `policy.log` in the repository of a user who has never
consulted a peer and never will.** A gate that leaves litter in the repos of people it does not serve
has a cost they never agreed to.

> **`mkdir -p` runs whenever the payload NAMED a seam path at all** - block, skip, pass, missing,
> unreadable or outside-repo. Round 8 caught the first draft restricting it to a "real seam", which
> would also have dropped `seam-missing` and `outside-repo` - **two bypass modes - on day zero.**
> Naming a seam path is the signal that this user is using the workflow; only a payload naming **no**
> seam leaves no trace. A `no-seam` outcome is
> logged **only if `.clavity/` already exists**; if it does not, the hook exits 0 and writes nothing.
> The count section 4a relies on is preserved exactly where it means something - a repository already
> using the disciplines - and is silently absent where it would be noise about a feature nobody uses.
>
> **The blind spot this buys, stated because round 7 is right that it exists:** a driver who NEVER
> completes one compliant consult never creates the directory, so **100% of their bypasses go
> unrecorded** - the observability depends on the user succeeding once before it can count their
> failures. **It is bounded and it is the right trade:** one compliant consult arms the counting for
> good, and the alternative is littering the repositories of people who never use the feature. **But it
> is a real hole in section 4a's countability argument and must not be sold as complete coverage.**

**The `mkdir -p` is not decoration and it was missing.** Round 1's Axiom Breaker found that this spec
never created `.clavity/` anywhere, while three separate requirements append into it. On a stranger's
repository the directory is absent on day zero, so `>>` fails `No such file or directory`, section 4
sends that to `exit 0`, and **the gate silently fails open on its very first real use** - the exact
population it ships for. The same omission was caught and fixed in the sibling workflow-position spec;
`open-issues/SKILL.md` has carried the two-line idiom (`mkdir -p` at `:69`, the shield at `:79`) all
along, and both specs quoted only the second line.

`.clavity/` is gitignored **in this repository**, which is a property of this repo's `.gitignore` and
not of the directory name. On a repository we do not control it is git-visible unless this shield
exists. Without it the hook drops seam paths and agent-authored skip reasons into a stranger's
repository, where a routine `git add .` publishes them.

**Re-assert on every invocation, not only at creation** - a shield deleted by hand or by `git clean -Xdf`
would otherwise leave the directory exposed forever after. One `stat` per invocation.

**The shield is `*` - the WHOLE directory - and narrowing it is a regression, not a fix.** It also
covers `.clavity/seams/`, which is correct: nothing under `.clavity/` has ever been tracked
(`git ls-files .clavity/` is empty), seams are runtime state, and they carry consult payloads and local
filesystem paths. Recorded because the next reader will want to narrow it.

**Resolve the repository root, never a relative path** - `git rev-parse --show-toplevel`, falling back
to `pwd`. A relative path writes into whatever subdirectory the caller happened to be in.

## 9. POWER-FAILURE - EXTRACTED. DO NOT BUILD SECTIONS 9 OR 9a FROM THIS FILE.

> 🔴 **These two sections are OUT OF SCOPE for this build.** Their own spec now exists -
> `2026-08-13-workflow-position-resilience-design.md` - and the owner has **deferred it to a future
> release as second priority** (2026-08-13; tracked in `clavity-dotnet/ROADMAP.md`). So this text is
> input to an artifact that is itself parked: **nothing here is on anyone's critical path.**
>
> Owner ruling: calling this a *productisation* was wrong. A productisation moves a working
> thing; this changed **the detection mechanism** (command-text grep -> `HEAD` moved), **the trigger
> gating** (always-on -> marker opt-in) and **the index-location contract** (the author's auto-memory
> path -> "whatever the host provides"). That is a new design, and a new design earns its own
> brainstorm, its own spec and its own review rather than riding in as a subsection of an unrelated gate.
>
> It is also a different *kind* of thing: this document specifies a stateless, syntactic check on a file
> named in a payload. Power-failure resilience is a stateful discipline about surviving session death.
> They share only the `.clavity/` infrastructure this build already provides.
>
> **What this build still owes it:** nothing but the generic infrastructure in sections 7 and 8 -
> `.clavity/policy.log` and the `AGY-SKIP: <rule> <reason>` token - which
> exist so a future tenant does not reinvent them. **No power-failure artifact ships from this plan.**
>
> The text below is preserved verbatim as INPUT to that separate design, not as a requirement here.

### (retained as input only) POWER-FAILURE as a nudge, never a gate

Move the discipline out of the personal, unshipped
`~/.claude/hooks/power-failure-index-reminder.sh` and into the plugin, so it installs, updates and
uninstalls with it - the same migration AGY-AFTER already made.

**It ships as a reminder and MUST NOT become a gate.** Its predicate is stateful and semantic - *if
meaningful work landed, the index must have been updated* - where the role check is stateless and
syntactic. A hook cannot distinguish "I forgot the index" from "no update was warranted", so a gate
would fire on read-only exploration and make dummy index updates the cheapest compliance. It would also
gate a stranger's session on a file in their home directory tied to a memory feature they may not use.

### 9a. How the nudge detects a commit - do NOT port the personal hook's approach unexamined

The personal hook greps the agent's shell command for `git commit` as a word. **An earlier draft of this
spec listed "rtk-prefix tolerance" among the properties to preserve. That was wrong and is struck.**
`rtk` is a command-rewriting wrapper on the AUTHOR's machine, not a property of this discipline, and a
shipped hook must assume no such wrapper exists. Measured, the regex
`git[[:space:]]+commit([[:space:]]|$)` behaves like this:

| command | matches? | |
|---|---|---|
| `git commit -m x` | yes | intended |
| `rtk git commit -m x` | yes | not a designed accommodation - the pattern is simply unanchored |
| `sudo git commit` | yes | same reason |
| `echo remember to git commit later` | **yes** | **false positive** - it nudges on a command that commits nothing |
| `git commit --dry-run` | **yes** | which is why the second exclusion grep is load-bearing |
| `git commit-graph write` | no | already rejected by the trailing-whitespace requirement, so the `commit-graph` exclusion term is **redundant** |

**Requirement: detect the EFFECT, not the command text.** The nudge fires when `HEAD` actually moved -
compare `git rev-parse HEAD` against the value stored at the previous invocation. This removes every row
of the table above at once: no wrapper assumptions, no false positive on a command that merely mentions
committing, no `--dry-run` special case (a dry run does not move `HEAD`), and no `commit-graph` term.
It also catches a commit made by any route the string match would miss, such as an amend or a
`git rebase --continue`.

**Stated limit either way:** a `PostToolUse` hook only observes commits made through the agent's own
shell tool. A commit the human makes in another terminal is invisible to it. That is inherent to the
mechanism, is true of the personal hook today, and is acceptable for a nudge - but it must not be
described as complete coverage.

**Preserve these, which are measured and were nearly lost in the move:**
- **The message addresses the orchestrator explicitly and says so.** The hook fires in every context
  that runs a commit, including inside a dispatched subagent. Measured 2026-08-07: a haiku subagent
  obeyed it and wrote a memory file outside its dispatch's FILES list, while two sonnet subagents
  declined as out of scope - **compliance was tier-dependent**. Memory files live outside the worktree,
  so that write is invisible to BOTH verification axes (`git status --short` and `git log --stat`). There
  is no reliable payload signal for "am I a subagent", so **the message must carry the addressing** rather
  than the hook attempting detection.
- **Fail-open**: any error exits 0.

**New, required by shipping - the nudge is OPT-IN per project.** It fires only when
`.clavity/power-failure.enabled` exists; absent, it exits 0 silently. Firing on every commit in every
repository a user owns would be intrusive noise for people who never adopted the discipline. Marker-gated
nudges are established practice in this plugin - `agy-test-audit-reminder.sh` already works this way. The
marker is created when the discipline is adopted, by its skill.

**The shipped skill must NOT hardcode `~/.claude/projects/...`.** It describes the discipline and the
index's required CONTENT - each task with its commit SHA, the single resume point, in-flight state a
successor cannot derive from git - and points at whatever durable store the host provides. The author's
own auto-memory layout is not a contract for anyone else.

**Removing the personal residue is the owner's call**, not this build's: the personal hook and the
`CLAUDE.md` section stop being needed once the plugin ships them, but both are the owner's files.

## 10. Build surface

| artifact | why |
|---|---|
| `clavity-dotnet/plugin/hooks/agy-policy-roles-pre.sh` | the gate, MCP form. Name must not collide with the existing `agy-consult-guard-*` pair |
| **`clavity-classic/plugin/hooks/agy-consult-guard-pre.sh` - EXTENDED, not a new script** | the gate, shell form. Section 3b: classic already runs this hook on `Bash\|PowerShell\|mcp__.*agy_ask`, and a second script on the same trigger doubles the largest cost in the design (~300-400ms of interpreter startup on **every** shell command). **The ROLES check is added here** |
| `clavity-dotnet/plugin/hooks/hooks.json` | a NEW `mcp__.*agy_ask` entry. **Classic's `hooks.json` does NOT change** - it already registers the hook the check now lives in (section 3b) |
| an existing SessionStart hook, both products | surfaces the per-reason-code counts over the retained log. Extend one rather than adding a fourth script |
| **`clavity-*/plugin/skills/adversarial-panel-review/SKILL.md` - TEACH THE `PANEL-SEATS:` LINE** | **the half that makes the gate safe, and it was missing.** Measured: **zero** shipped skills mention `PANEL-SEATS`, so nothing has ever instructed an author to write it. The skill must state the line's exact form and that a consult payload naming a seam requires it. **This ships in the same release as the gate or before it - never after** |
| the other multi-round disciplines' `SKILL.md` | same convention, stated where each seam is written |
| `clavity-dotnet/plugin/skills/{agy-first,agy-capstone,agy-test-audit,adversarial-panel-review}/SKILL.md` | subagents consult over `agy_ask`, not the CLI. **See the OPEN item in section 13a - this edit is under challenge** |
| `scripts/tests/<name>.Tests.ps1` | every hook here has its own suite |
| `plugin-hooks-payload.Tests.ps1` | **must change** - an explicit, named byte-identity exemption for the gate pair |
| `justfile` | suite registration is an explicit list, not a glob |
| `scripts/tests/_partition.md` | a measured row; the census gate reds the suite if omitted |

## 11. Tests - every row names the mutant that reds it

The suite must prove the gate **blocks**, by asserting an exit code from a real invocation - not by
inspecting source text.

| row | mutant that must red it |
|---|---|
| a seam WITH a non-empty marker passes | remove the marker -> must block |
| a seam WITHOUT one blocks | add a marker -> must pass |
| a seam with an EMPTY marker (`PANEL-SEATS:` and nothing) blocks | give it content -> must pass |
| a payload naming no seam fails OPEN | **replace the hook body with `exit 0`** -> this row still passes, but every blocking row REDS. The suite, not the row, is the oracle |
| missing `jq` fails OPEN | same coupling: `exit 0` reds the blocking rows |
| **`.clavity/` is created when absent, and the gate still works on a repo that has never had one** | drop the `mkdir -p` -> the day-zero fixture fails open silently -> row reds. **Assert the gate's DECISION, not just that it exited 0** - exit 0 is what the bug looks like |
| **a payload naming TWO seams, one compliant and one not, BLOCKS** | check only the first -> row reds. This is the smuggling row |
| **the block message says what the check cannot do** | drop the floor disclaimer -> row reds. Section 6 item 3 |
| **every fail-open outcome writes a log line with its own reason code** | drop the logging on the no-seam path -> the bypass leaves no trace -> row reds. Cover `no-seam`, `seam-missing`, `seam-unreadable`, `outside-repo`, `no-jq` and `no-git-bash` as separate rows sharing one fixture |
| **a payload naming a MARKERLESS seam and a MISSING seam BLOCKS** | let the missing seam force exit 0 -> row reds. **Pins the round-2 precedence rule; without it the multi-seam check reopens as a two-character bypass** |
| **classic does NOT treat `echo "run clavity ask"` as a consult** - no log line, no subprocess | use a bare substring match -> the fixture records a phantom `no-seam` bypass -> row reds |
| **classic DOES treat `foo && clavity ask "..."` as a consult** | anchor only to start-of-string -> row reds. **Both directions, or the test pins nothing** |
| **the classic block message shows the skip token inside the payload string** | ship the dotnet message text in classic -> the token reads as bare positional arguments -> row reds |
| **a valid skip token beats a positive violation** - a payload with BOTH exits 0 and logs `skip` | evaluate the seams first -> the fixture blocks despite a well-formed token -> row reds. **Pins round 4's precedence rule; a hatch a violation can override opens only when nothing is wrong** |
| **a payload with a violating seam AND an unreadable one exits 2** | let an infrastructure failure force exit 0 -> row reds. Pins that a failure never PREVENTS a block |
| **a session with a permanently failing `mv` attempts rotation on ~1% of appends, not all of them** | remove the modulo bound -> the fixture counts one attempt per invocation -> row reds |
| **the hook still resolves its own directory when `${CLAUDE_PLUGIN_ROOT}` is UNSET** | replace `dirname "$0"` with the variable -> run the fixture with it unset -> the path collapses, the hook fails open, and a seam with no marker PASSES -> row reds. **Section 5 mandated this for five rounds with no row; a silent bypass would have been certified** |
| **a `no-jq` outcome appears in `policy.log` with its reason code** | reintroduce a sentinel-only path -> the reader reports nothing -> row reds |
| **every log line has exactly 5 TAB-separated fields, empty ones written as `-`** | let an empty field collapse -> a fixture with no detail shifts every later column -> row reds |
| **the reader counts by reason code over BOTH `policy.log` and `policy.log.1`** | read only the live file -> a fixture that rotates mid-run undercounts -> row reds |
| **classic detects `sudo clavity ask "..."`, `time clavity ask "..."` and `env FOO=1 clavity ask "..."`** | anchor the test to start-of-command -> the wrapped fixtures evade the gate silently -> row reds. **Fixtures must use wrappers that exist on a stranger's box** - naming a tool specific to the author's machine would make the suite pass for the wrong reason there and be meaningless everywhere else |
| **classic does NOT add a second PreToolUse registration** | register a new script instead of extending the existing hook -> assert the classic `hooks.json` PreToolUse entry count is unchanged -> row reds. **Pins section 3b: a second hook doubles a ~300-400ms per-command cost** |
| **dotnet's gate entry matches `mcp__.*agy_ask` ALONE, not a `Bash`-bearing matcher** | merge it into the existing combined entry -> assert the new entry's matcher string -> row reds. **Section 3 mandated this from the start and no row pinned it: an implementer could put the gate on every shell command and the suite would pass** |
| **all three subagent-routing skill edits are present** | ship the hooks without the skill edits -> assert none of `agy-first`, `agy-capstone`, `agy-test-audit` still tells subagents to use the CLI form -> row reds. **Without the edits, subagent consults never reach the dotnet matcher and the gate is invisible to exactly the actor it was built for** |
| **the block message names `adversarial-panel-review/SKILL.md` literally** | derive the path from the payload -> there is nothing to derive from -> row reds. Pins the section 6 correction |
| **`adversarial-panel-review/SKILL.md` contains the `PANEL-SEATS:` instruction** | ship the gate without the skill edit -> row reds. **This is a CONVENTION-EXISTS row, and it is the one that stops the gate shipping as a trap: measured, 0 skills teach the marker and 558 of 564 seams on disk lack it** |
| **a seam written by following the updated skill PASSES the gate** | change either side without the other -> row reds. **Couples the two halves: it fails if the skill teaches a form the hook does not accept, which no single-sided row can catch** |
| **a `no-seam` outcome does NOT create `.clavity/` when it is absent** | `mkdir -p` unconditionally -> a fixture repo with no `.clavity/` gains one from a command that merely mentions the string -> row reds |
| **rotation fires when the count lands anywhere in the 5-line window, not only on the exact multiple** | require an exact multiple -> a fixture with two concurrent appends stepping 99 to 101 never rotates -> row reds |
| **classic: a non-`clavity ask` command spawns NO subprocess and touches NO file** | resolve the repo root before the command test -> assert on a fixture that would fail if `git` ran (a non-repo cwd, or a `PATH` with no `git`) -> row reds. **A timing assertion would be flaky; assert the observable side effect instead** |
| the block message names the discipline's SKILL.md path | remove the pointer -> row reds |
| the block message states the peer was not contacted | remove that line -> row reds |
| `AGY-SKIP: ROLES <reason>` passes | omit the reason -> must block |
| **a bare `AGY-SKIP:` does NOT skip** | honour it -> row reds. This is the wildcard-bypass guard |
| **`AGY-SKIP: OTHERRULE <reason>` does NOT skip ROLES** | honour any rule -> row reds |
| a skip reason containing a newline logs ONE line | drop sanitisation -> the log gains a forged line -> row reds |
| a skip reason containing the record delimiter does not shift columns | sanitise newlines only -> row reds |
| the `.clavity/.gitignore` shield is restored before the first write | remove the re-assertion -> row reds |
| the log rotates at the bound and the reader still counts | make the reader read only `policy.log` -> the count drops after rotation -> row reds |
| classic: a non-`clavity ask` shell command exits 0 without reading anything | make it parse every command -> row reds |

## 11a. Rollout, upgrade and uninstall - the artifact's whole life

Round 7 walked it and found the document only ever described the middle.

- **Install and first consult.** The gate is inert until a seam is named. **It must ship with the skill
  that teaches `PANEL-SEATS:` (section 2), or it blocks the first consult a user ever makes.**
- **Upgrade.** The log format is pinned (section 8). **The reader must SKIP a line it cannot parse and
  continue, never fail the session** - a format change in a later version would otherwise break session
  start for everyone holding an older log. There is no legacy format today, which is precisely when
  this costs one `continue` instead of a migration.
- **Uninstall.** Removing the plugin removes the hooks; it leaves `.clavity/policy.log`,
  `policy.log.1` and the `.gitignore` shield in every repository the user consulted from.
  **This is accepted and stated rather than solved:** the files are small, gitignored and inert, and a
  hook cannot clean up after its own removal. **What is NOT acceptable is leaving them somewhere the
  user never opted in** - which is why section 8a creates nothing for a `no-seam` outcome in a
  repository that has no `.clavity/`.

## 12. What this is and is not

**It is a floor.** It proves syntactic compliance: a marker exists and is non-empty. It **cannot** check
the palette's anti-gaming requirement - which triggers fired, which seats were dropped and why, whether
the seated lenses cover the real risk surface. It prevents memory-driven omission; it cannot prevent
hollow compliance. **The block message must say so**, for the same reason the test-audit discipline says
it of itself: a guard that overstates its reach manufactures the blind spot it claims to cover.

**Known and accepted:**
- A seam authored outside `.clavity/seams/` escapes the block. Mitigated, not sealed: a `.md` path named
  elsewhere in the payload that carries no marker is **logged as a warning and passed**.
- **An agent that omits the seam path, or names one that does not exist, bypasses the gate.** Nothing
  running locally can prevent this. **It is made COUNTABLE rather than prevented** (section 4a): every
  such outcome is logged with its own reason code and surfaced at SessionStart. The design's honest
  claim is that a routine bypasser becomes visible as a number, not that bypass is impossible.
- **The log is not tamper-resistant.** The agent has shell write access to it. Sanitisation protects the
  record format from agent-authored fields; it does not defend against an agent that edits the file.
- clavity-classic's extraction is fragile and fails open more often than dotnet's. **Its CHECK-ALL guarantee is best-effort**, so the multi-seam smuggle is closed in dotnet and only mitigated in classic (section 3a).
- **Classic's extraction is not merely unreliable, it is STEERABLE, and that is a stronger claim.** An agent that writes the path in a form the parser misses - `--file=".clavity/seams/x.md"`, an unusual quoting, a variable - produces a `no-seam` outcome and passes. The gate is a floor in dotnet and a speed bump in classic; **section 4a's counting is what remains, and for classic it is most of the value.**
- **Classic's consult test admits residual false positives** by design; chasing them with a shell parser is explicitly rejected.
- Rotation is best-effort on Windows.
- The skip token is honest but cheap; the per-rule skip count is its only counterweight.

## 13. Resolved at plan time

| item | note |
|---|---|
| exact marker syntax - line-anchored? case-sensitive? what counts as non-empty? | pin it with the test row that asserts it |
| the seam-path regex, concretely | needs a Windows-path case: payloads here carry `C:/Users/...` forms |
| ~~the log record format and field order~~ | **RESOLVED in section 8** - TAB-delimited, `<iso8601-utc> <rule> <reason> <seam> <detail>`, empty fields written as `-`. Deferring it made the reader's "since the last session" claim unfalsifiable for five rounds |
| the over-long / length cap for sanitised fields | a number |
| ~~a payload naming MULTIPLE seam paths~~ | **RESOLVED by round 1 - a design hole wearing a plan-time label. CHECK ALL; BLOCK IF ANY LACKS THE MARKER - GUARANTEED in dotnet, BEST-EFFORT in classic (section 3a).** Checking only the first is a one-line bypass: name a compliant seam first and smuggle the real consult behind it. Deferring it would also have shipped two implementations, one of which enforces nothing |
| **`jq` is invoked with `-r`** | pin it. Without `-r` the extracted path arrives wrapped in literal double quotes, `[ -f ... ]` fails, and section 4 sends that to a silent `exit 0` - **the gate would fail open on every single invocation while looking healthy.** The repo idiom is already `jq -r` (`agy-consult-guard-pre.sh:16-19`) |
| is the `<rule>` in `AGY-SKIP:` case-sensitive? | pin it with the row that asserts a non-matching rule does not skip |
| a seam path that resolves OUTSIDE the repository root | fails open under section 4, but the ordering deserves an explicit row so it is not discovered later |
| the seam file exists but is unreadable (permissions) | fails open under section 4; name it so the implementer does not add a fail-closed branch for it |
| which existing SessionStart hook is extended, per product | dotnet and classic have different SessionStart sets |

## 13a. Panel rounds on THIS document

The four rounds in the ADR reviewed its predecessor. **This file's own review starts here.**

### Round 1 - 11 seats, 11 findings: 9 folded, 1 refuted, 1 pinned

| finding | disposition |
|---|---|
| **the spec never creates `.clavity/`** while three requirements append into it | **folded.** Zero `mkdir` in the whole document, measured. On a stranger's box the first `>>` fails and section 4 turns that into a silent `exit 0` - **the gate fails open on its first real use, in the exact population it ships for** |
| **section 6's block-message list omits the disclaimer section 12 mandates** | **folded.** Verified verbatim: section 12 says the message *"must say so"*; section 6 says *"in this order"* and lists three items without it. A spec that requires a thing in one section and omits it from the authoritative list manufactures the blind spot it warns about |
| a named seam that does not exist bypasses the gate silently | **folded as 4a** - the axiom stays, the invisibility goes. Logged with its own reason code |
| a payload naming no seam bypasses with no audit trail | **folded as 4a.** Nothing local can prevent it; **4a makes it countable**, which is a different object |
| the log is not forgery-proof - the agent owns the filesystem | **folded as an honesty correction.** The original sentence claimed the log *"must not be forgeable by the thing it audits"*. It is. Sanitisation buys record integrity, not tamper-resistance |
| a failed `mv` rotation retries forever and the bound is never met | **folded** - rotation is attempted only on a crossing, and the guarantee is stated honestly for hosts where it cannot succeed |
| the degraded sentinel is raced away by a healthy sibling agent | **folded, and it is the sharpest finding.** Clearing on any healthy invocation means a capable agent deletes the sentinel a degraded one just raised - **the observability artifact destroyed by the condition it reports.** The SessionStart READER now clears it, after surfacing it |
| multiple seam paths in one payload was deferred to plan time | **folded - it was a design hole wearing a plan-time label.** CHECK ALL, BLOCK IF ANY FAILS. Checking the first is a one-line smuggle. **Round 3 later scoped this per product - see section 3a; classic's guarantee is best-effort** |
| `git rev-parse` before the command test on every shell command | **folded as an ordering REQUIREMENT** in section 3. Classic fires on every `Bash|PowerShell` call; a `git` process on the critical path of every `ls` is not acceptable |
| `jq` without `-r` returns quoted paths | **pinned in section 13.** The finding is conditional - the spec never said to omit `-r` - but the failure mode it describes is real and silent, so the flag is now explicit rather than idiomatic |
| **the `mcp__.*agy_ask` matcher is a typo; real MCP tools use a single underscore** | **REFUTED by measurement.** The live tool on this host is `mcp__plugin_clavity_clavity-ls__agy_ask` - **double** underscore - and `mcp__.*agy_ask` is already shipped and working at `clavity-dotnet/plugin/hooks/hooks.json:17` and `:38`. Had this been folded it would have broken a matcher that works today |

**The one that would have cost most if folded is the one that was false.** Nine of eleven findings were
real and two of those were silent fail-open paths; the eleventh was a confident claim about a matcher
this repository has been shipping for months.

### Round 2 - 4 bespoke seats, 7 findings, all folded. THREE were caused by round 1's own fixes

| finding | disposition |
|---|---|
| **`mkdir -p ... \|\| exit 0` created a fail-open that CANNOT be logged**, contradicting 4a's "EVERY decision" | **folded.** Round 1 added both rules and they cannot both hold - the log lives in the directory that failed to exist. Named as the single unloggable outcome rather than contradicted two sections apart |
| **"BLOCK IF ANY FAILS" collided with "a missing seam exits 0"** | **folded as an explicit precedence rule.** A positive violation on any seam blocks; missing or unreadable siblings never veto it. **Without this the multi-seam rule round 1 added reopens as a two-character bypass** - name a nonexistent seam beside the real one |
| **rotation keyed on "older than the current session", which a `PreToolUse` hook cannot observe** | **folded.** An unevaluable condition is worse than none. Rekeyed on the `session_id` the payload already carries - **verified present** at `agy-consult-guard-pre.sh:19` - so rotation is attempted at most once per session with no clock |
| **countability is no defence against an adversarial agent** | **folded as a scoping correction - the second overclaim in this document.** The agent owns the log file, as section 8 concedes. The claim now names the actor it is actually for: a driver working from memory. **Negligence leaves the count; malice removes it** |
| `sed` listed as an error path | **folded - it is not a path at all.** The only consumer of `sed` was the palette extraction section 6 deleted; the failure line outlived it. A phantom dependency makes an implementer add a probe and a reviewer count a branch that never runs |
| a non-Git-Bash `bash` had no reason code | folded into 4a's code list (`no-git-bash`) |
| a missing `jq` raised the sentinel but had no log reason | folded into 4a's code list (`no-jq`) |

**Three of round 2's seven findings were defects in round 1's fixes.** The pattern holds from the
sibling spec: a fix is unreviewed code, and the round after a fold is the highest-yield one.

### Round 3 - 4 bespoke seats, 5 findings, all folded. The pattern held a THIRD time

| finding | disposition |
|---|---|
| **the `session_id` rotation guard permanently disables rotation in degraded environments** | **folded - round 2's fix carried the disease it was fixing.** Without `jq` the id degrades to the literal `default` (`agy-consult-guard-pre.sh:19` and again at `:20`), so the first degraded invocation writes `default` and **every degraded invocation in every future session matches it and skips rotation for ever.** A one-session retry loop became permanent silent disablement. Now: when the id is unknown, do not write the guard and do not skip |
| **"EXACTLY ONE fail-open path cannot be logged" is false** - a locked or permission-denied `policy.log` is another | **folded, and the PATTERN is the real finding.** This is the **third** absolute this document has asserted and had falsified: the unforgeable log (round 1), "EVERY decision" (round 2), and "exactly one unloggable path" - **which was round 2's own replacement for the previous absolute.** The unloggable set is now "the logging substrate failed", stated without a count |
| **classic cannot guarantee CHECK ALL** - shell strings resist reliable multi-path extraction | **folded as section 3a.** CHECK ALL was written as an absolute in round 1 and only dotnet can meet it. **A requirement one product cannot satisfy is a latent implementation divergence, not a requirement.** The multi-seam smuggle is CLOSED in dotnet, MITIGATED in classic, and the document now says which |
| **the skip token appended bare to a shell command becomes positional arguments** | **folded.** It must sit inside the quoted payload argument in classic, and the block message is therefore per-product - the same divergence section 3 already accepts for the hooks |
| **classic's consult test was never given a SHAPE**, so a substring match fires on `echo "run clavity ask"` | **folded, and it mattered because of round 1's own fix.** Harmless alone - but 4a now logs `no-seam`, so **every false positive would record a bypass that never happened and inflate the count 4a asks a human to trust.** Now anchored to a command word, with `no-seam` logged only for identified consults |

**Three consecutive rounds have each found real defects in the previous round's fixes** - eight such
regressions in total. The document is converging, but it has not yet produced a round whose findings
were all about the ORIGINAL design rather than the repairs.

### Round 4 - 4 bespoke seats, 4 findings: 3 folded, 1 refuted

| finding | disposition |
|---|---|
| **"ANY infrastructure failure exits 0" is false** - a violating seam beside an unreadable one exits 2 | **folded, and the Absolutes Auditor seat earned its place.** The rule was never about the exit code; it was about the failure **not being allowed to decide**. Restated as "never CAUSES a block, never PREVENTS one", which survives the counter-example. **Fourth absolute in this document to need scoping** - and the seat also reported one claim it tried and could NOT falsify, which is what makes the pass credible |
| **skip token versus positive violation had no precedence** | **folded - a genuine hole, not a detail.** Section 4 said any violation blocks; section 7 said the hook MUST honour a valid skip. **The skip wins and is evaluated first:** a hatch a violation can override opens only when nothing is wrong, which is exactly when nobody needs it |
| **round 3's rotation fix reinstated round 1's retry loop** for degraded sessions | **folded.** "No session id -> always attempt" means a locked log retries the doomed `mv` on every consult. **A session-scoped guard needs a session, so with no id, bound the COST instead of the attempts** - attempt only on line counts divisible by 100, capping waste at 1% with no clock and no new state |
| **the classic skip token would crash `clavity ask` as an unresolvable file path** | **REFUTED by measurement.** `clavity ask "<payload>" --review-only` takes the **payload** as its first positional, so a token inside that string is inert. The crash needs the token as a SEPARATE argument, which the rule forbids. **The wording was tightened anyway** - it was ambiguous enough that a careful reader misread it, which is its own defect |

**Four rounds, and the fix-regression rate is falling** - three regressions in round 2, three in round
3, one in round 4. The absolutes pass found the fourth and, more usefully, reported what it could not
break.

### Round 5 - 4 bespoke seats, 5 findings, all folded. The round that DELETED things

| finding | disposition |
|---|---|
| **the `policy.rot` session guard can be deleted entirely** | **folded, and it retires three rounds of work.** Round 4's modulo-100 bound, applied universally, subsumes the guard, the `session_id` read and every special case. Rounds 2, 3 and 4 each rewrote a session-scoped rotation rule and each was defective; **the stateless version was sitting inside round 4's own exception all along** |
| **the `policy.degraded` sentinel can be deleted entirely** | **folded.** It existed only because a single hook on the combined matcher could not tell a consult from a routine command without `jq` - a shape section 3 forbids. Both hooks can log `no-jq` like any other outcome. **This also deletes the race that cost round 1 a finding: the thing that raced is gone** |
| **"skip count since the last session" is unsatisfiable** - nothing in the record identifies a session | **folded by correcting the CLAIM, not by building machinery.** The reader reports counts over the retained log. The record format is now pinned (TAB-delimited, timestamped) instead of deferred - it had been deferred for five rounds while a section elsewhere depended on fields it did not define |
| **the `sed` test row was vacuous** - it asserted source text, which section 11's own preamble forbids | **folded: row deleted.** A behavioural test cannot detect a redundant probe on a host that has `sed`. **A vacuous row is worse than a missing one - it certifies what it fails to test** |
| **`${CLAUDE_PLUGIN_ROOT}` was mandated in section 5 with NO test row** | **folded: row added.** The failure mode is a collapsed path, an infrastructure failure and a silent bypass - **exactly the class this suite exists to catch, uncovered for five rounds** |

### Round 6 - 4 bespoke seats, 7 findings: 6 folded, 1 OPEN for the owner

| finding | disposition |
|---|---|
| **the block message's pointer target is underivable** - the payload has a seam path, not a skill | **folded, and it is the same defect the owner found from outside** (below). Fixed to the literal `adversarial-panel-review/SKILL.md` |
| **no test row for the three subagent-routing skill edits** | **folded.** Ship the hooks without the skill edits and subagent consults never reach the dotnet matcher - **the gate would be invisible to the exact actor it was built for, and the suite would pass** |
| **no test row for dotnet's registration isolation** | **folded.** Section 3 mandated it from round zero; an implementer merging it into the combined entry would put the gate on every shell command and go green |
| **repository pollution for a user who never consults** | **folded.** Classic's loose test means `git commit -m "fix clavity ask"` would create `.clavity/` and a log in a stranger's repo. `mkdir` now runs only for outcomes that matter, and `no-seam` is logged only where `.clavity/` already exists |
| **the exact-multiple rotation trigger is skipped by concurrent appends** | **folded.** Two writers step 99 to 101 and the trigger never fires - **in exactly the concurrent case the atomic-append design exists to support.** The window is 5 lines wide now |
| **the dotnet skip token named "a JSON field" but never a key** | **folded.** There is no separate key: the token is prose inside the `message` string in both products, which is also why one static block message describes it correctly for both |
| **routing subagents onto `agy_ask` may pop a blocking modal and freeze them** | **OPEN - surfaced, not folded.** This challenges an owner ruling, and the existing skills say the opposite (*"subagents use the CLI form, not the MCP bus"*) without stating why. **I could not verify the modal claim cheaply, and folding or dismissing it unilaterally would both be wrong.** See below |

### Round 5a and 6a - the OWNER's findings, which six rounds of panel never asked

**5a: what does the gate COST?** Nobody had measured it. Section 3b now carries the numbers and the
consequence: **classic must extend its existing per-command hook rather than register a second one**,
because process startup is the dominant cost and a second registration doubles it on every shell
command. The first attempt at this measurement was discarded - it ran while the driver was busy, and
this project has measured its own load moving its own benchmarks by up to 6x.

**5b: `rtk` had become a shipped prerequisite.** Round 5's anchor fix justified itself with a
command-rewriting wrapper that exists on the author's machine and used it as a test fixture - in a
document whose section 9a already says *"a shipped hook must assume no such wrapper exists"*. The
requirement was right; the justification imported the banned assumption. **Fourth author-machine leak on
these specs, and the first where the document already contained the ruling forbidding it.**

**6a: this document never named AGY-AFTER.** The gate enforces the seat requirement of the
`adversarial-panel-review` discipline, and until the owner asked, **`AGY-AFTER` appeared exactly once in
the whole spec - in a DO-NOT-BUILD section, as an aside about an unrelated migration.** Section 2 now
states what `PANEL-SEATS:` is and who owns it, and section 6's pointer resolves to a real file.

> **The pattern across all three: six panel rounds reviewed this document against ITSELF and found
> internal contradictions well. Every finding that required standing outside it - what it costs, what it
> assumes about the machine, what it is FOR - came from the owner.** A panel is bounded by the frame the
> payload gives it.

### Round 7 - 4 bespoke seats, 8 findings: 6 folded, 1 sharpened, 1 partly refuted

| finding | disposition |
|---|---|
| **section 6 and section 7 contradicted each other on the block message** | **folded - and round 6 created it.** Unifying the token into payload prose removed the stated reason for a per-product message while section 6 still gave it. The message IS per-product, for a different reason: the surrounding example differs |
| **dotnet already has a hook on `mcp__.*agy_ask`** | **folded.** Verified in both `hooks.json` files. Two hooks now fire on every dotnet consult. The latency conclusion survives - a consult costs seconds - but *"its matcher fires only on `agy_ask`"* implied an empty slot that was never empty |
| **merging the ROLES check into the shared classic hook can disable that hook's own logic** | **folded, and it is the sharpest.** `agy-consult-guard-pre.sh` categorises the call and writes a VCS baseline, exiting 0 at `:27` otherwise. An early "not a `clavity ask`, exit 0" at the top would skip baselines the guard needs. **A merge that saves a process must not merge the control flow** |
| **the footprint rule blinds the telemetry for a user who never complies once** | **folded as a stated hole.** Bounded - one compliant consult arms counting for good - but it is a real gap in section 4a's countability argument and is no longer sold as complete |
| **no upgrade story for the pinned log format** | folded into new section 11a: the reader SKIPS unparseable lines. Costs one `continue` today; costs a migration later |
| **no uninstall story** | folded into 11a: the litter is accepted and stated, because a hook cannot clean up after its own removal - **but only in repositories the user actually consulted from** |
| **the block hands over the skip token while moving the seats behind a file read, making bypass cheaper than compliance** | **sharpened rather than folded.** Section 6 already accepted this trade when it deleted the palette; round 7 states it more honestly than the original did. The counterweight remains the skip count, and section 4a's blind spot above makes that counterweight weaker than it read |
| **a seam drafted outside `.clavity/seams/` bypasses the gate** | **PARTLY REFUTED, and the contrast is the point.** Measured: **3 shipped skills teach the `.clavity/seams/<topic>.md` convention; 0 teach `PANEL-SEATS`.** So the directory convention is genuinely established and this failure mode is far weaker than the marker gap - which is exactly why the marker gap mattered |

### Round 8 - 4 bespoke seats, 6 findings: 5 folded, 1 partly refuted

| finding | disposition |
|---|---|
| **an implementer cannot find the requirements in here** | **folded as new section 0, and it is the most useful change of the round.** Measured: 15% of the file is fold history and 39 further lines narrate a past state inside the normative sections. **`jq -r` existed ONLY in a historical table.** Section 0 is now the contract; everything else is why |
| **the shield tests `[ -f ]`, so an EMPTIED `.gitignore` is never restored** | **folded, and the shipped idiom has the same bug.** Measured with a control: `[ -f ]` passes on a zero-byte file while `grep -qx` correctly reports the shield missing. **Testing the container instead of the claim is how a guard certifies what it stopped checking.** The occurrence in `open-issues/SKILL.md:79` is captured for separate triage |
| **skipping short-circuits before the seam is extracted, so the log records `-`** | **folded.** The DECISION short-circuits; the RECORD must not. A `skip` line that does not name the review it waved through **loses the only fact that makes the skip count actionable** |
| **the footprint rule also drops `seam-missing` and `outside-repo` on day zero** | **folded, and it widens what round 7 stated.** Those are two bypass modes, not tidy edge cases. `mkdir` now runs whenever a seam path was NAMED at all; only a payload naming none writes nothing |
| **the generic `<rule>` token and log column pre-pay for tenants that may never arrive** | **PARTLY REFUTED.** The `<rule>` in the token is not future-proofing: **it is the wildcard-bypass guard** - without it, one `AGY-SKIP:` disables every present and future gate at once, which section 7 folded long before a second tenant was contemplated. The log's `<rule>` column is genuinely near-free generality and stays. **The challenge was right to ask; the answer is that this piece earns its place today** |

### OPEN for the owner - one round-6 finding I did not fold

**Routing subagent consults over `agy_ask` (section 3) may freeze them.** The claim is that MCP tool
calls surface a blocking modal, which a background subagent cannot answer. **What is verifiable:** the
three skills currently say *"subagents use the CLI form, not the MCP bus"* - so the CLI routing is
deliberate and its reason is nowhere recorded. **What is not:** whether the modal behaviour is real
here. **The change is an owner ruling, so it is surfaced rather than folded or dismissed.** If the modal
risk is real, section 3's subagent routing needs a different mechanism and the three skill edits come
out of the build; if it is not, the reason the skills say the opposite should be written down before it
is reversed a second time.

## 14. Provenance

Every requirement above was earned, most of them adversarially. The reasoning - four panel rounds, ~20
findings, the arguments for and against a `palette.json`, the delimiter design and why it was abandoned
- lives in the ADR: `2026-08-13-agy-role-enforcement-design.md`. Read it when asking "why is this like
this"; do not build from it.
