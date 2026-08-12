# Enforcing named roles on every AGY-* peer consult

**Status:** design, owner-approved 2026-08-13. Build AFTER the in-flight capstone converges.
**Scope ruling (owner):** *"Roles should always be used at all your prompts to peer otherwise it
doesn't know what we are looking for."* This covers **every AGY-\* consult** - AGY-FIRST, AGY-AFTER,
AGY-CAPSTONE, AGY-TEST-AUDIT - not capstone rounds alone.

> 🔴 **WHAT THIS BUILD ACTUALLY COVERS IS NARROWER THAN THAT RULING, AND THE GAP IS UNRESOLVED.** The
> design gates the `agy_ask` MCP tool. It does **not** gate `clavity ask --review-only`, which is the
> transport three of the four disciplines name for subagents and the only transport clavity-classic
> has. See **residual 4** - it carries the measurement and three options, and needs an owner decision
> before this ships. Stated here because a reader who takes the ruling above at face value would
> believe the coverage is total.

## Why - the principle, which is not what I first thought it was

Named seats were treated here as a review-thoroughness device: rotate a lens, cover a new defect-class,
avoid circling one surface. That is real but it is the smaller benefit.

**The owner's framing is the load-bearing one: without a role, the peer does not know what it is being
asked to look for.** A consult that says "hunt reachable defects" delegates the choice of defect-class
to the peer, and a peer with no stated lens picks whatever the diff in front of it suggests - which is
the surface the driver just edited. The role is not decoration on the question; for a general-purpose
peer it is a substantial part of the question.

## The defect this prevents, measured

On 2026-08-13, every AGY-* consult sent in one session lacked any named role except the two consults
that were themselves *about* roles:

| consult | discipline | role mentions |
|---|---|---|
| `capstone-a2-audit-r1` .. `r10` | AGY-CAPSTONE | **0** in all ten |
| `test-audit-a2` | AGY-TEST-AUDIT | **0** |
| `a2-wiring-pin-fork` | AGY-FIRST | **0** |

For contrast, the previous capstone on the same branch averaged **14-31** role mentions per round.

**Root cause: the discipline was driven from memory instead of from its skill.**
`skills/agy-capstone/SKILL.md` requires named seats (six mentions; the selection instruction at `:93`).
The driver worked from the one-paragraph rule in `CLAUDE.md`, which says only "adversarial lenses".
Everything the skill carried beyond that paragraph was silently absent for ten consecutive rounds and
nothing anywhere noticed.

**Generalise it, because seats are only the visible symptom:** any discipline run from memory loses
whatever its skill carries that the driver's memory does not. Seats are what got noticed; they are
unlikely to have been the only thing lost.

## 1. The detection predicate - REPLACED after panel round 1, not patched

The first draft asked the hook to "identify the target as an AGY-* consult". The panel killed that, and
the killing argument generalises to any future version of this idea:

> **The gate would only trigger if the driver remembered to label the consult - which is the same
> memory that already failed.** A driver who forgets the roles is equally likely to forget the label,
> so the hook fails open exactly when it is needed. (Mechanism Gamer, round 1.)

Two further consequences of that draft, both real: a hook grepping for `AGY-` would block a benign
consult that merely ASKS about a discipline (Activation Auditor), and no specification was ever given
for how bash should recognise a discipline in prose (Literal Implementer).

**The replacement needs no semantic detection, because a standing owner rule already constrains every
consult** (`MEMORY.md:68`): *"Point agy at FILES, always - give agy real paths to read itself; never
consult it on a pasted summary of my own measurements."* Every AGY-* consult therefore names a seam.

So the predicate becomes mechanical and total:

> **If the payload names a path under `.clavity/seams/` ending in `.md`, that file must contain the
> role marker. If it names no such path, that is already a violation of the point-at-files rule.**

Nothing is inferred about which discipline is running. There is no label to forget, no keyword to
false-positive on, and no prose to parse beyond one narrow, stable path shape.

## 2. The marker, and why the check never reads the palette

**THE MARKER IS A CONVENTION, NOT A SHIPPED TEMPLATE FILE.** An earlier draft said "the seam template
ships the marker line", which contradicted sections 11 and 13: no new artifact type is introduced and
the build surface lists no template file. **The template evaporated once the block message became a
repair kit** - the block delivers the palette at the moment of failure, which is what a template would
have been for. Resolved in favour of no template: one fewer artifact to ship, mirror and keep in sync.

The seam carries a literal line - `PANEL-SEATS:` followed by the seated roles. The hook checks the
marker exists and is non-empty. **It does not parse the palette out of
`adversarial-panel-review/SKILL.md`**: the round-1 Dependency Cynic finding is correct that regexing
markdown for a valid-seat list breaks when a bullet style or heading changes, and that parse failure
would silently disable the gate. A generic marker check has no such coupling and stays correct when the
palette gains a seat.

Producing a seam without roles then means **deleting** the marker line, not forgetting to add it.

## 3. Fail OPEN on error, fail CLOSED on a detected violation

The one point of disagreement with the peer, resolved by one negotiation turn.

It initially argued fail-closed outright: *"a gate that fails open is not a gate; it actively certifies
what it failed to check."* Against that stands this project's earned ruling - **a hook exit code of 2
is non-blocking on `SessionStart` but BLOCKING on `PreToolUse`, so new PreToolUse hooks here must fail
open**. The existing consult hook states its posture at `hooks/agy-consult-guard-pre.sh:4`:
*"Fail-open: any error -> exit 0"*.

Re-derived against that ruling it refined rather than conceded, and the refinement is the converged
answer:

- **Infrastructure failure -> exit 0.** No `jq`, unreadable file, a path that does not resolve, any
  parse failure. A broken hook must never paralyse every consult on the machine.
- **Positively-detected violation -> block.** The payload named a seam, the hook read it, the marker is
  absent or empty. That is policy, not error.

*Absence of evidence fails open; evidence of absence fails closed.*

## 4. Scope the matcher

The existing entry matches `Bash|PowerShell|mcp__.*agy_ask`, so anything registered there runs on
**every shell command in the session**. This check must be scoped to the consult tool alone: a
fail-closed check on the shell matcher would block ordinary work whenever the predicate misfired.

## 5. An escape hatch the AGENT can actually reach

A fail-closed gate without a hatch is a trap: a bug in the predicate leaves the driver unable to
consult the peer **at all - including to ask about the bug.**

**The first draft got the hatch wrong, and the round-2 panel was right to kill it.** It specified
`CLAVITY_SKIP_ROLE_CHECK=1`. But the agent invokes `agy_ask` as an **MCP tool with a JSON payload** and
has no way to set an environment variable for that call - the hatch was reachable only by a human in a
shell, i.e. a phantom for the exact actor it existed to rescue.

**The hatch is therefore IN-BAND: a line `ROLE-CHECK: SKIP <reason>` in the payload.** An agent can
write that as easily as any other text, the reason is mandatory, and unlike an env var it lands in the
log where a human can see how often it is used. The block message must name it verbatim.

## 6. Observability, bounded

With infrastructure failures exiting 0 silently, the gate can vanish and nobody learns. **Every
decision - pass, block, or skip-with-reason - appends ONE SHORT LINE to `.clavity/role-check.log`.**

Three constraints, each from a round-2 finding:

- **One short `printf` append, never read-modify-write.** The Resource Vampire seat is right that this
  file is written on every consult; the State Corruptor seat's claim that concurrent writers *corrupt*
  it is **refuted by this project's own documented behaviour** - the `open-issues` skill records that a
  single short append is atomic on POSIX, so concurrent writers interleave lines rather than scrambling
  them. That is why the append must stay one short line and never a read-modify-write.
- **Bounded by ROTATION, not truncation - round 3 caught these two bullets contradicting each other
  three lines apart.** The round-2 fold said "truncated to its last 500 lines", and truncation
  (`tail -n 500 f > tmp && mv tmp f`) **is** a read-modify-write - precisely what the bullet above
  forbids, and it drops any append that lands mid-shuffle. The atomicity argument that refuted the
  corruption claim was undone by the bound folded next to it. **Resolution: when the log exceeds 500
  lines, `mv` it to `.clavity/role-check.log.1` and let the next append create a fresh file.** A rename
  is atomic, at most two files ever exist, and **no line is ever lost** - a racing appender writes into
  the rotated inode, which is a line in `.log.1` rather than a line destroyed.
- **A degraded-mode sentinel, not a log line.** If `jq` is absent the hook cannot tell `agy_ask` from a
  routine `ls`, so it cannot log per-invocation without writing on every shell command - which is the
  Cascade Analyst finding that the round-1 blind spot returns exactly when infrastructure fails.
  Instead it touches `.clavity/role-check.degraded` **once**, and SessionStart surfaces that file's
  existence. Telemetry without spam.
- **The readers are part of the build, or none of this is observability.** Round 3: the round-2 fold was
  booked complete while its read half had no build row at all - a sentinel with a writer and no reader,
  and a log nothing surfaces. `.clavity/` is gitignored, so neither file is visible to review or to CI;
  three separate mechanisms (skip-token usage, block frequency, degraded mode) all terminated in
  artifacts nobody reads. **Both readers are now build rows in section 13.** The sentinel is surfaced by
  extending an existing SessionStart hook rather than adding a fourth; the log is surfaced only as a
  count of skip-token uses since the last session, which is the number that matters and the one that
  keeps the escape hatch honest.

## 7. The block message must not read as a channel failure

Every AGY-* discipline has an `agy-required-but-unreachable` terminal that halts and asks a human. A
blocked consult is **not** that, and a driver who misreads it halts for a channel failure that never
happened. The message must say in its first line that this is a local role check and the peer was never
contacted.

## 8. What this can and cannot be evidence of - say it in the message

The hook can check that a marker names roles. It **cannot** check the palette's anti-gaming requirement
- which seat triggers actually fired, which were consciously dropped and why, whether the seated lenses
cover the real risk surface.

**So the hook is a floor, not proof.** It prevents memory-driven omission; it cannot prevent hollow
compliance - pasting the whole palette unpruned, or naming a seat then writing a prompt that ignores
what that seat hunts. The message must say so, for the same reason the test-audit discipline says it of
itself: a guard that overstates its reach manufactures the blind spot it claims to cover.

## 9. AGY-FIRST must ask the peer for ITS OWN solution, before showing it a menu

> **STATUS: DEFERRED - discipline only, NOT in this build.** Section 10's table always said so; this
> section did not, and stated a bare "Requirement" that reads as in scope. Round 3 measured it: lines
> 162-196 contained no deferral marker at all while section 15 claimed *"9 and 10 deferred - stated at
> each"*. An implementer reading in order would have built it.

**Owner observation, 2026-08-13: an AGY-FIRST consult was not asking the peer to propose its own
solution.** It was handed a numbered menu and asked to pick.

That is a subtler form of the leading frame the panel skill already forbids. The skill says to state
options evenly and not reveal a lean - but a menu *is* a lean about the shape of the solution space,
even when every option in it is described neutrally. The reason to ask a second model is partly that it
may propose something never conceived here; a menu forfeits exactly that.

**Measured on this session's own forks, and the result is stronger than expected:**

| fork | option space offered | what the peer returned |
|---|---|---|
| the wiring fork | closed: parse / behavioural / "a hybrid" | "hybrid" - one of the three |
| the seat-enforcement fork | A / B / **C: "something else, including a mechanism neither of us has named"** | "Option C" = A and B combined - still inside the menu |

**An explicit invitation to leave the frame did not produce an unprompted design.** The anchoring comes
from presenting the menu at all, not from closing the door at the end of it.

**Requirement: an AGY-FIRST consult asks the open question FIRST and reveals the menu SECOND.**

1. State the problem, the constraints, and the measured facts.
2. Ask: **"What would you build, and why?"** - with no options named.
3. Only after that answer is in hand, present the alternatives already considered and ask whether the
   peer's answer changes given them.

Step 3 is not optional politeness: the driver's options may contain constraints the peer could not
infer, and a proposal that ignores them still has to be reconciled. But it comes second, so what
arrives at step 2 is the peer's design rather than a selection from the driver's.

**This is NOT checkable by the mechanism the roles use, and the round-3 panel killed the claim that it
was.** The withdrawn sentence said a seam template carries an `OPEN-PROPOSAL:` block and the hook treats
"a fork seam that names options" without one like a missing role marker. Two independent defects:

1. **It invoked a template that section 2 had already deleted.** The template was removed there and the
   removal was never swept forward - the incomplete-fold failure this project has recorded as its
   dominant defect class, reproduced inside the document that records it.
2. **Deciding a seam "names options" requires parsing prose - the exact mechanism section 1 killed**
   (`:64` - *"no prose to parse beyond one narrow, stable path shape"*). Applied unconditionally instead,
   it would demand an `OPEN-PROPOSAL:` block on every capstone and audit seam, where the concept is
   meaningless.

**So `OPEN-PROPOSAL` has no enforcement design, and that is the honest status.** The requirement in this
section stands as a discipline; the mechanism is an open problem for its own cycle, alongside the
`NEGOTIATED` predicate in section 10a. Both share one unsolved question: how a hook distinguishes the
KIND of consult without reading prose. A plausible direction, unevaluated here: have the seam declare its
own kind in a marker the way `PANEL-SEATS:` does, so the classification is asserted rather than inferred.

## 10. The discipline: agent disagreements are settled by negotiation BEFORE the owner sees them

**Owner's statement of the principle, 2026-08-13:** *"disagreements between agents should be solved by
negotiation before presented to owner."*

This is **broader than the fork case that prompted it**, and the widening is the point. It covers every
shape of agent disagreement, not just a design fork:

- a design/approach/sequencing fork - the case that surfaced it;
- **a review finding the driver refutes** by measurement;
- **a finding the driver rules below a severity floor**;
- **a finding the driver accepts while rejecting the FIX proposed with it** - which happened five times
  in the capstone preceding this spec, each time settled unilaterally.

**The owner is the tie-break of last resort, not the referee of first instance.** An unresolved
disagreement between two agents must not be the owner's first sight of it.

### The boundary that must be written down, not assumed

**Genuine impasse stays presentable.** If this discipline is read as "never present a disagreement" it
inverts into something worse: a real deadlock stalls silently, or the driver manufactures agreement to
satisfy the rule. The existing `agy-first` skill already has the right shape - negotiate to a cap, then
declare IMPASSE and hand the human both positions **with their measured support**.

So the rule is: **negotiate first; present only what negotiation could not settle, and present it as
both positions rather than as a preference.** What is forbidden is handing the owner "agy says X, I say
Y" as an opening move.

### The cost, stated honestly

Every refutation becomes a round-trip. In the capstone preceding this spec that would have added roughly
five extra consults - five real defects were reported with fixes that measurement showed were wrong or
incomplete, and each was corrected without going back to the peer. The discipline says that correction
should itself be negotiated, because a fix authored by one agent and unreviewed by the other is exactly
the unreviewed-code shape the capstone keeps finding.

**That cost is the argument FOR it, not against it:** the fix I write alone is no more trustworthy than
the fix the peer wrote alone, and this session produced repeated evidence of both being wrong.

### Enforcement - same family, different boundary

| requirement | boundary | status |
|---|---|---|
| `PANEL-SEATS` - roles on every consult | `mcp__.*agy_ask` | **in scope for this build** |
| `OPEN-PROPOSAL` - ask the peer first, menu second (section 9) | `mcp__.*agy_ask` | deferred, own cycle |
| `NEGOTIATED` - converge before presenting (this section) | **`AskUserQuestion`** | deferred, own cycle |

## 10a. Why it is a separate hook, and what it cannot yet decide

**Separate hook, by necessity.** It fires on a different tool at a different moment, and conflating it
with the role check would put a fail-closed gate on `AskUserQuestion` - the tool used to ask the human
for help. That is the one path that must stay open when everything else is broken.

**Measured, and this is why the gap existed at all:** no tool matcher covers `AskUserQuestion`.

**The first version of this measurement was wrong, and round 3 corrected it** - a completeness argument
resting on a miscount. It claimed "eight" entries and listed eight distinct matcher STRINGS. Re-measured
against `clavity-dotnet/plugin/hooks/hooks.json`: **nine entries**, because
`Bash|PowerShell|mcp__.*agy_ask` appears twice (`:17` PreToolUse and `:38` PostToolUse), and the
`UserPromptSubmit` entry at `:68-73` **has no `matcher` key at all** and was missing from the list
entirely. The conclusion survives - a matcher-less `UserPromptSubmit` entry fires on a prompt, not on a
tool, so `AskUserQuestion` is still unguarded - but the shape that was omitted is exactly the shape that
would falsify a completeness claim, which is why the correction is recorded rather than quietly applied.

The boundary
where a disagreement actually reaches the human is unguarded, while the obligation to negotiate is
written six times in `skills/agy-first/SKILL.md` and once in the driver's memory. **A documented rule
with no mechanism - the exact failure this document exists to close, appearing a third time.**

**Unresolved, and the reason this needs its own cycle rather than a paragraph here: what counts as a
disagreement worth negotiating.** Most `AskUserQuestion` calls follow no consult and must not require
one. A predicate that is too eager blocks routine questions, which is worse than the gap it closes; one
that is too lax reproduces the gap. Deciding it needs its own design pass, not an inline guess.

## 11. Where the role content lives - the peer's design, converged over two negotiation rounds

**The palette stays in `skills/adversarial-panel-review/SKILL.md`, wrapped in
`<!-- AGY_PALETTE_START -->` / `<!-- AGY_PALETTE_END -->`, and the hook extracts between those
delimiters with `sed` - structure-blind, never parsing markdown.**

This is the peer's own design, produced with **no menu offered** (per section 9). Verified before
accepting:

- **HTML comments are precedented, not novel** - `clavity-dotnet/plugin/skills/ls-driving/SKILL.md`
  already contains one.
- **Skills are not ASCII-constrained** - `adversarial-panel-review/SKILL.md` carries 64 non-ASCII lines,
  so the delimiters break no encoding rule.

### Why not a structured `palette.json`

The peer argued for it, then against it, and the reversal is recorded because it affects how much weight
this convergence deserves.

- **For:** the palette is genuinely structured - `grep -cE '^- \*\*[A-Z][a-z]+ [A-Z][a-z]+\*\*'` returns
  **11**, eleven uniform seats each carrying a name, a trigger and a defect-class.
- **The objection that turned out not to separate the options:** "it needs a new artifact type". Measured
  - **no hook reads any non-`.sh` file from the plugin today**, so the delimiter design is equally new in
  that respect. This measurement moved the driver toward the JSON, not away from it.
- **Against, and decisive:** JSON is a hostile medium for the prose whose teaching value *is* the
  content. The seats read *"hunts contradictory constraints, circular logic, unstated invariants"*; in
  JSON fields, with no comments and escaping required, those sentences shorten until they stop teaching.
  Keeping SKILL.md as the source with generated prose would need a generator plus a sync gate, mirrored
  into both products - unjustified for displaying eleven sentences.

⚠ **Weight this convergence less than a first-pass agreement.** The peer moved three times: delimiters
fine -> "dead-end debt, build JSON now" -> "delimiters are the terminal state". Each position carried a
substantive and *different* argument, so it is not pure capitulation, but it is a peer partly tracking
the driver's pushback.

### What the two mitigations do and do not do - stated as partial, per the peer's fair critique

- **A test row pinning the delimiters and asserting the extracted block is non-empty** protects the
  MAINLINE. It does **not** rescue an agent trapped at execution time by a broken delimiter in a dirty
  tree - a test fires at suite time, the trap springs at consult time.
- **A runtime fallback** naming the skill path when extraction is empty **relabels the trap as a
  detour**: the agent now needs a third attempt, straining the second-attempt criterion rather than
  meeting it.

- **THE THIRD STATE - extraction succeeds but returns the wrong thing - was asked about during the
  negotiation and never answered. Round 3 answered it.** Move the `END` delimiter a hundred lines down
  and the extraction is a large block of unrelated markdown. The test row passes, because it asserts
  non-empty. The fallback does not fire, because it triggers on empty. The agent is handed a wall of
  garbage inline, with zero signal that anything went wrong. **Empty is the only failure either
  mitigation can see.** Fix: bound the extraction - if it exceeds a sane line count, treat it exactly as
  an empty extraction (fallback + a log line), and give the test a row that reds when the block grows
  past the bound. A wrong-but-plausible extraction is the one case worth spending an assertion on,
  because it is the only one that fails silently.

All three are worth building. None is a seal, and the spec says so rather than implying otherwise.

## 12. The block message - a repair kit, per the owner's ruling

The owner's ruling was *"retry the consult with roles this time"*, which makes the block's purpose a
successful **retry**, not a refusal. The message therefore carries, in order:

1. One line naming what is missing and stating **this is a local role check - the peer was never
   contacted** (section 7).
2. The palette, extracted between the delimiters - **or, when extraction is empty OR over-long, the
   fallback text naming where the palette lives.** Round 3: this branch existed only in section 11's
   prose and was absent from the ordered list that specifies the message, so a literal build emitted an
   empty item 2 on a broken delimiter - the exact trap section 11 claims to mitigate.
3. The in-band skip token `ROLE-CHECK: SKIP <reason>` (section 5), **last, and named as an escape rather
   than an option.** Round 3, Boundary Smuggler: the block's cheapest exit is a 25-character skip line,
   against the work of pruning an eleven-seat palette, and the block message is required to spell that
   line out verbatim. The hatch stays - section 5's argument for it is sound and a trapped agent needs
   it - but its only counterweight was a log nobody read. That counterweight is now built (section 6),
   and ordering the token last keeps the palette, not the bypass, as the first thing read.

## 13. Build surface - measured, and larger than "a hook"

| artifact | why |
|---|---|
| `clavity-dotnet/plugin/hooks/<name>.sh` | the check |
| `clavity-classic/plugin/hooks/<name>.sh` | **byte-identical**; the two products ship the same hook set and parity is tested |
| both `hooks.json` files | a **NEW entry** matching `mcp__.*agy_ask` ALONE - not an extension of the existing `Bash\|PowerShell\|mcp__.*agy_ask` entry, which would put the check on every shell command. This retires section 4's concern by construction. |
| `adversarial-panel-review/SKILL.md` (both copies) | the two delimiter lines |
| an existing SessionStart hook, both products | **round 3** - surfaces `.clavity/role-check.degraded` and the skip-token count. Section 6's telemetry was written with no reader; extending an existing hook avoids a fourth SessionStart script |
| `scripts/tests/<name>.Tests.ps1` | every hook here has its own suite |
| `justfile` | suite registration is an explicit list, not a glob |
| `scripts/tests/_partition.md` | a measured row - **the census gate added this session now enforces this**, so omitting it reds the suite |

**On locating the palette file: use `"$(dirname "$0")/../skills/..."`, NOT `${CLAUDE_PLUGIN_ROOT}`.**
Round 3, and the measurement overturned this document's own stated residual. Residual 2 claimed
`${CLAUDE_PLUGIN_ROOT}` is safe "as the existing consult hook already assumes them" - measured,
`agy-consult-guard-pre.sh` contains **zero** occurrences of it, and only **1 of 13** hook bodies reads it
at all. The precedent did not exist. With the variable unset the path collapses to an absolute
`/skills/...`, extraction returns empty, and the fallback then hands the agent a path that cannot be
opened - a rescue that guarantees a second failure. The repo's actual idiom is
`agy-liveness-check.sh:126` (`"$(dirname "$0")/hooks.json"`), which resolves from the script's own
location and cannot be unset. Verified: that form resolves to a readable `SKILL.md`, and a deliberately
bogus sibling path does not resolve - the control fails for the right reason.

## 14. Testing

The suite must prove the gate BLOCKS, not merely that it parses - the same posture as the
`check-curate-in-progress` suite built this session, whose rows assert an exit code from a real
invocation rather than inspecting source text.

Rows, each with the mutant that must red it:

**Round 3 rewrote this table.** Two of the seven rows had no mutant that could red them - one was marked
`n/a` outright, the other named a mutant that reached only half of what the row asserted. **A hook whose
body was replaced with an unconditional `exit 0` passed both**, which is the failure mode this project
states as its own rule: ask which test goes RED if the guard is deleted, and if the answer is none, the
row certifies nothing. A fail-open assertion cannot be mutation-proved in isolation - `exit 0` is what it
expects - so its guard is that the SAME mutant must red a blocking row in the same suite. That coupling
is now written into the table instead of left implicit.

| row | mutant that must red it |
|---|---|
| a seam WITH a role marker passes | remove the marker -> must block |
| a seam WITHOUT one blocks | add a marker -> must pass |
| a payload naming no seam fails OPEN | **replace the hook body with `exit 0`** -> this row still passes, but the two blocking rows above RED. The suite, not the row, is the oracle |
| missing `jq` fails OPEN | same coupling: `exit 0` reds the blocking rows |
| missing `jq` touches the degraded sentinel | remove the sentinel write -> row reds |
| the block message contains the extracted palette | break a delimiter -> extraction empties, fallback text appears |
| **the extracted block is NON-EMPTY** | move `END` above `START` -> extraction empties -> row reds |
| **an over-long extraction is treated as a failure** | move `END` 100 lines down -> block exceeds the bound -> fallback must appear, not the wall of text |
| the delimiters exist in BOTH shipped SKILL.md copies | delete one -> row reds |
| the skip token passes with a reason | omit the reason -> must block |
| **a skip reason containing a newline logs ONE line** | feed a two-line reason -> unsanitised, the log gains a forged line -> row reds |

## 15. Exhaustiveness self-audit - run before handing this over

Owner ruling: **details get resolved at the plan stage.** So gaps are named here with where each is
settled, rather than guessed at now. One was a contradiction and was closed in-document instead.

**CLOSED HERE (a contradiction, not a detail):** section 2 said a seam TEMPLATE ships the marker, while
sections 11 and 13 introduce no new artifact and list no template file. The template had quietly
evaporated once the block message became a repair kit. Resolved in favour of **no template**.

**RESOLVED AT PLAN TIME - each has an owner and a home:**

| gap | where |
|---|---|
| the hook's filename | plan, task 1 - must not collide with the existing `agy-consult-guard-*` pair |
| exact marker syntax: line-anchored? case? what counts as non-empty? | plan, with the test row that pins it |
| the seam-path regex, concretely | plan - the peer's sketch was `\.clavity/seams/[^"'\s]+\.md`; it needs a Windows-path case, since consult payloads here carry `C:/Users/...` forms |
| log line format and field order | plan - one short line, format fixed there. **Round 3 adds a hard requirement rather than leaving it to taste: every agent-authored field (the seam path, the skip reason) must be newline-stripped and length-capped before it is logged.** Both are free text an agent controls, and the log is the only audit trail for the escape hatch - an unsanitised reason forges lines in the record of its own use |
| the over-long-extraction bound, concretely | plan - section 11's third state needs a number |
| when `.clavity/role-check.degraded` is CLEARED | plan - an uncleared sentinel becomes permanent noise, the same overstay failure this project has hit before |
| ~~truncation mechanism for the 500-line bound~~ | **RESOLVED IN SECTION 6 by round 3, no longer a plan-time gap** - rotation by `mv`, because truncation was the read-modify-write the adjacent bullet forbids |
| a payload naming MULTIPLE seam paths | plan - check all, or the first? unresolved and reachable |
| a seam path that does not exist yet at PreToolUse time | plan - falls under fail-open, but the ordering deserves an explicit row |

**REQUIREMENT COVERAGE:** owner's scope ruling (roles in every AGY-* prompt) -> sections 1-2; fail-closed
and self-repairing -> 3, 5, 12; roles-only scope with 9 and 10 deferred -> stated at each; two-driver
mirror -> 13; test posture -> 14.

**KNOWN AND ACCEPTED, not gaps:** the hook proves syntactic compliance only (section 8); a seam outside
`.clavity/seams/` escapes the block (residual 3); all three mitigations in section 11 are partial.

**NOT ACCEPTED - BLOCKS THE BUILD UNTIL THE OWNER RULES:** residual 4, the `clavity ask` transport gap.
Everything else above is either folded or scoped to the plan; this one changes what the build is for.

**ROUND-3 CORRECTION TO THIS SELF-AUDIT.** The audit above declared the template contradiction "CLOSED
HERE" after fixing one of its two sites, and declared sections 9 and 10 deferred "stated at each" when
section 9 stated no such thing. **A self-audit that greps for the symptom it just fixed will find it
fixed.** What caught both was a panel that had never seen the sections - which is the argument for
running the panel on the whole artifact rather than on the parts believed to be new.

## Deliberately NOT in scope

- **A `clavity capstone init` CLI.** The peer proposed one to own the framing. Heavier than needed: the
  plugin already ships `agy-seam-inject.sh`, which injects seam content on skill invocation.
- **Gating on seat APPROPRIATENESS.** Out of reach of any mechanism here; that is what human review of
  the seam is for.
- **Detecting which discipline is running.** Deleted by design - see section 1.

## Round-1 panel findings and their disposition

| seat | finding | disposition |
|---|---|---|
| Axiom Breaker | inlining the question bypasses the gate entirely | **folded** - inlining already violates the point-at-files owner rule; the predicate keys on the seam path |
| Mechanism Gamer | the trigger depends on the memory that already failed | **folded** - no label to remember; the path shape is the trigger |
| Activation Auditor | a consult merely ASKING about a discipline gets blocked | **folded** - no keyword matching survives |
| Literal Implementer | no specification for recognising a discipline in prose | **folded** - the requirement is deleted, not specified |
| Protocol Pedant | bash cannot extract a filepath from a natural-language payload | **partly folded** - reduced from arbitrary extraction to one narrow pattern; residual accepted and fails open |
| Dependency Cynic | parsing the palette out of markdown breaks on formatting drift | **folded** - the palette is never parsed |
| Blindspot Auditor | zero telemetry when the gate silently breaks | **folded** - section 6 |
| Cascade Analyst | no new findings | - |
| *solo panel* | matcher over-breadth; no escape hatch; block misreadable as a channel failure | **folded** - sections 4, 5, 7 |

**Round 1 verdict was BLOCK and its buildability objection was correct against the draft as written.**
The predicate it objected to no longer exists.

## Known residuals, stated rather than discovered later

1. **Path extraction can still miss** - an unusual quoting of the seam path. It fails open, so the worst
   case is an unchecked consult, never a blocked one.
2. **`jq` is assumed** - and the existing consult hook does assume it, at
   `agy-consult-guard-pre.sh:11`, where it guards it fail-open (`command -v jq ... || exit 0`). **The
   half of this residual about `${CLAUDE_PLUGIN_ROOT}` was FALSE and is withdrawn** (round 3): that hook
   contains zero occurrences of the variable, so there was no precedent to lean on. Section 13 now
   specifies `dirname "$0"` instead, which removes the assumption rather than documenting it.
3. **A seam authored outside `.clavity/seams/` escapes the BLOCK.** The round-2 Mechanism Gamer seat
   sharpened this fairly: a driver working from memory is exactly the one who writes `capstone-r1.md`
   to the repo root, so keying the gate on a path convention leaves a gap shaped like the failure it
   exists to catch. **Mitigated rather than accepted:** the hook also notices a `.md` path named
   anywhere else in the payload and, if that file carries no marker, **logs a warning and passes** -
   fail-open outside the canonical directory, fail-closed inside it. That closes most of the gap
   without re-opening the keyword false-positive surface, and the warning is visible in the log rather
   than silent. It remains a gap, not a seal.
4. **THE GATE COVERS ONE OF THE TWO TRANSPORTS, AND IS INERT IN ONE OF THE TWO PRODUCTS.** Round 3,
   Mechanism Gamer, and this is the largest gap in the document because it sits directly against the
   scope ruling at the top ("every AGY-* consult"). Measured: all four disciplines name two transports -
   `agy_ask` (clavity-dotnet) and `clavity ask --review-only` (clavity-classic) - and three of them add
   the same parenthetical, **"(subagents use the CLI form, not the MCP bus)"**: `agy-first/SKILL.md:29`,
   `agy-capstone/SKILL.md:31`, `agy-test-audit/SKILL.md:27`. Section 13 requires the new entry match
   `mcp__.*agy_ask` ALONE, and section 4 refuses the `Bash` matcher for a good reason. The consequences:
   - **every subagent consult passes ungated**, because subagents are told to use the CLI form;
   - **clavity-classic is entirely ungated**, since its transport is a shell command. The mirrored hook
     installs there and can never fire - and `clavity-classic/plugin/hooks/hooks.json:17,38` already
     carry an `mcp__.*agy_ask` matcher, so the parity test section 13 cites will pass on a dead hook.

   **Not resolved here, because the honest options trade against section 4's ruling and that is an
   owner-level call, not an implementer's.** Three exist: (a) accept it and narrow the document's scope
   claim from "every consult" to "every MCP consult from the main thread"; (b) add a second, separately
   scoped check on the `Bash` matcher that greps only for a `clavity ask` invocation - narrow enough
   that section 4's "do not put a fail-closed check on every shell command" objection may not apply,
   since a non-matching command exits 0 immediately; (c) move the enforcement out of the hook layer
   into the transport itself. **What must NOT happen is shipping this while the document still claims
   to cover every AGY-* consult** - that is a guard certifying what it never checked, which is the
   failure this project has already paid for.

## Round-2 panel findings and their disposition

| seat | finding | disposition |
|---|---|---|
| Axiom Breaker | the env-var escape hatch is unreachable by an MCP agent | **folded** - hatch is now the in-band `ROLE-CHECK: SKIP <reason>` line |
| Cascade Analyst | missing `jq` produces zero telemetry, restoring the round-1 blind spot | **folded** - one-time `.clavity/role-check.degraded` sentinel surfaced at SessionStart |
| Resource Vampire | the log is unbounded and a retrying agent spams it | **folded** - bounded at 500 lines. ⚠ **The truncation MECHANISM chosen here was overturned in round 3** - it was a read-modify-write; see section 6 |
| Mechanism Gamer | the path convention is itself a memory item | **folded as a mitigation** - warn-and-pass outside the canonical directory; residual 3 |
| State Corruptor | concurrent appends corrupt the log | **REFUTED in part** - the `open-issues` skill records that a single short append is atomic on POSIX and interleaves rather than scrambling. The valid residue is folded: the append must stay one short `printf`, never read-modify-write. |

**Round 2 withdrew the round-1 buildability objection after re-deriving it against the rewritten
predicate** - *"the design is buildable as written"* - which is the clearest evidence the round-1 fold
worked rather than merely moving the problem.

## Round-3 panel findings and their disposition

**Rounds 1 and 2 reviewed sections 1-8 only. Sections 9-15 had never been reviewed by anyone** - they
were written after round 2 and shipped straight into the self-audit. Round 3 seated nine lenses,
rotating in **Boundary Smuggler**, the one palette seat the review had never used. Sixteen findings; all
folded above. The peer was sent the file, the palette, the do-not-re-raise ledger and a quote-check
control, and **none of the driver's own findings** - so agreement below is corroboration, not echo.

| seat | finding | source | disposition |
|---|---|---|---|
| Axiom Breaker | `:193` still invoked the template section 2 deleted; the self-audit booked the contradiction CLOSED having fixed only one of two sites | **both** | **folded** - section 9's enforcement claim withdrawn entirely |
| Mechanism Gamer | enforcing `OPEN-PROPOSAL` needs the hook to recognise "a fork seam that names options" - prose parsing, which section 1 killed at `:64` | **peer only** | **folded** - the deeper defect; the driver's panel found the symptom (section 9 unmarked) and missed the cause |
| Mechanism Gamer | the gate misses `clavity ask`, so every subagent consult and all of clavity-classic pass ungated | driver only | **folded as residual 4, unresolved by design** - the fix trades against section 4 and is an owner call |
| Cascade Analyst | `${CLAUDE_PLUGIN_ROOT}` unset makes the fallback hand over an unopenable path - the rescue guarantees a second failure | **peer only** | **folded, and the measurement went further than the finding**: residual 2's precedent claim was false (zero occurrences in that hook); `dirname "$0"` removes the assumption |
| Cascade Analyst | section 12's ordered message had no fallback branch, so a literal build emits an empty palette | driver only | **folded** - branch written into the list |
| Activation Auditor | the 500-line bound mandates the read-modify-write forbidden three lines above it | **both** | **folded** - rotation by `mv` instead of truncation; no line is lost |
| Activation Auditor | section 10a's enumeration miscounted entries and omitted a matcher-less one | driver only | **folded** - re-measured; conclusion survives, count corrected |
| Blindspot Auditor | a displaced `END` yields a large WRONG extraction that is non-empty, so neither the test nor the fallback sees it | **peer only** | **folded** - the third state the negotiation asked about and section 11 never answered; bounded, with a test row |
| Blindspot Auditor | the sentinel had a writer and no reader; the log had no reader at all | driver only | **folded** - both readers are build rows now |
| Boundary Smuggler | the block message spells out a 25-character bypass at the moment of correction, counterweighted only by an unread log | driver only | **folded** - hatch kept, ordered last, counterweight built |
| Boundary Smuggler | agent-authored fields are logged unsanitised, forging lines in the escape hatch's own audit trail | driver only | **folded** - sanitisation is a requirement plus a test row |
| Literal Implementer | two of seven test rows had no mutant; an `exit 0` hook passed both | driver only | **folded** - table rewritten, fail-open rows coupled to blocking rows |
| Literal Implementer | section 11 demanded a non-empty assertion that section 14 never carried | driver only | **folded** - now a row |

**Quote-check control: 4 of 5 byte-exact**, including a line dense with escaped pipes - the peer
demonstrably read the artifact rather than pattern-matching its summary. The fifth asked for line 436 of
a 435-line file and required the literal `DOES NOT EXIST`; the peer answered *"(empty line)"*. Not a
fabrication, but not a report of absence either, and worth recording: **this control has caught a
confident answer about content past the end of a file before.**

**Where the two panels diverged is the useful part.** The peer found three defects the driver's panel
missed, and every one of them was a place where a fold had created a NEW defect - the semantic-parsing
requirement that arrived with section 9, the fallback that arrived with section 11, the truncation bound
that arrived with round 2. The driver found ten the peer missed, mostly coverage and mutation gaps. The
overlap was two. **Neither panel alone would have produced this round.**

## Open, for the implementer

- Whether the check extends `agy-consult-guard-pre.sh` or ships as a sibling hook. A sibling keeps the
  mutation guard's fail-open posture uncomplicated and is the current preference.
- Whether the block message injects the palette inline - preferred, since that fixes the round in
  flight rather than only naming the failure.
