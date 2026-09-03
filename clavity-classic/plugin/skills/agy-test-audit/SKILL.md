---
name: agy-test-audit
description: Use ONLY after AGY-CAPSTONE is GREEN and before declaring a development branch done - never mid-implementation. Convenes the live agy peer to audit the TEST SUITES for coverage exhaustiveness (untested reachable behaviours, vacuous/weak assertions, missing edge cases) over the branch diff, verifies every claimed gap by measurement, and surfaces verified gaps for the owner to scope. Distinct from the capstone's defect hunt: it asks "would the tests catch the next regression?". Ends with one ASCII [VERDICT] token. Best-effort prompt-discipline, manually invokable as /agy-test-audit; auto-fire is a separate marker-gated hook.
---

# agy-test-audit - audit the test safety-net before you call the branch done

## When to use
Invoke this skill at exactly one moment: **after AGY-CAPSTONE reports GREEN, before you declare a
development branch COMPLETE.** Its job is the question the capstone does NOT ask - not "are there defects
in the shipped code?" but "**would the tests catch the next defect?**" It hunts untested reachable
behaviours, vacuous or weak assertions, and missing edge cases in the committed test suites.

Do **not** fire it mid-implementation or on routine intermediate commits - that traps you in premature
completion breakpoints and burns a redundant paid consult. One audit per branch-finish, on the range the
branch produced, after the capstone is GREEN over that same range.

This is **best-effort prompt-discipline, not a sandbox.** The `[VERDICT]` token is self-reported; its
forcing functions make hollow compliance visible to your human. The bar is "materially better than
shipping an untested safety-net," not proof of completeness - a single-peer audit raises the coverage
FLOOR, it does not prove no gap remains.

## Transport (resolve to your own plugin)
Send every consult over your driver's review-ask transport, review-only:
- **clavity-dotnet:** the `agy_ask` MCP tool, after an `agy_status` idle-check (do not fire while the
  peer is busy).
- **clavity-classic:** `clavity ask --review-only` (subagents use the CLI form, not the MCP bus).

## Completeness checks the DRIVER runs on your reply (13b)

**NAME YOUR DISCIPLINE, AND NAME THE ARTIFACT.** On clavity-dotnet pass `discipline: "agy-test-audit"` and
`artifactPath: "<the file under review>"` to `agy_ask`. You supply NAMES only: the driver owns the
terminal-token table and reads the artifact itself to derive the line the peer must echo. So there is
nothing you can mistype into a silent opt-out, and no counting rule for you and the peer to resolve
differently.

**Demand the echo in your payload**, as the second-to-last instruction:

> Immediately before your terminal verdict, quote verbatim the last line of `<the artifact>` that carries
> at least 8 letters or digits. Quote it exactly.

A nonce would prove only that the peer read your brief; the artifact's own tail proves it reached the end
of the thing it was reviewing.

**What the driver reports back.** `[13b] TRUNCATED REPLY` - the mandated terminal token is missing or not
at the end. `[13b] ECHO MISSING` - the peer did not quote that line. `[13b] ECHO WEAK` - no line in the
artifact could prove anything, so the check was SKIPPED, not failed. `[13b] NO ECHO` - you named no
artifact. `[13b] UNCHECKED` - you named no known discipline; shown once per session.

**A flagged reply is INCOMPLETE, not empty.** Never read one as "no findings". Recover it with `agy_look`
against the peer's own trajectory - not from any local file - or re-ask AT MOST ONCE, then halt and ask
your human. An unbounded "re-ask until it passes" reproduces the same mismatch and burns a budget.

**Demand this in your payload too**, alongside the echo:

> Put nothing after the terminal token. It must be the LAST thing in your reply - no summary, no
> "standing by for your feedback", no offer of next steps. Every REQUIRED block comes immediately
> BEFORE it, in this order: your report, then any `[VERIFIED: ...]` block, then any closing
> disclosures, then the token.

MEASURED: several rounds had their ENTIRE report displaced by a closing pleasantry, because what the
driver collects is the peer's FINAL message - and a terminal token alone does NOT fix it, since every one
of those rounds already demanded one. The ordering half is not a style note either: where a discipline
requires a `[VERIFIED: ...]` block and rules a verdict INVALID without one, the observed habit is to place
it AFTER the verdict, so "nothing after the token" and "the verdict needs a VERIFIED block" would
otherwise instruct opposite things and a peer obeying one would breach the other.

**The `>` is load-bearing, not formatting.** MEASURED across all four of these skills: `> ` marks the one
thing that is verbatim payload text rather than prose addressed to YOU, and nothing else uses it. This
clause governs the PEER's reply, so unmarked it reads as a rule about your own output - which is neither
what it says nor what it is for, and in at least one of these disciplines contradicts a rule about when
you emit a token at all. `scripts/check-agy-discipline-skills.ps1` pins the marker, not just the words.

**Demand the JSON block in your payload too**, after the prose report and before the terminal token:

> Emit one fenced `json` block: an ARRAY of row objects, one per gap. These keys are DECLARED by this
> discipline and no others are accepted - `seat`, `id`, `file`, `line`, `quoted_line`, `claim-type`,
> `evidence`, `missing_test`, `severity`, `detail`. `file` and `quoted_line` are REQUIRED in every row.
> `quoted_line` must be a VERBATIM line from `file`; the driver locates by that text and treats `line` as
> untrusted. `evidence` is `measured` or `reasoned`. `missing_test` is the test's NAME and what it
> ASSERTS - a specification, never code, because the driver authors every test itself.

**`evidence` IS A POINTER, NEVER AUTHORITY. It buys the finding no credit, because the driver is required
to re-run every claim before folding it.** The field earns its place by naming WHICH MUTANT to run first,
not by attesting to anything. It is deliberately NOT called `confidence`: that word projects an epistemic
authority a peer's self-report cannot carry, and a prose rule telling the peer to ignore what the word
means would have to win that argument on every single run. `evidence: measured` states a PROCESS, which
is checkable.

The driver validates the block with
`python scripts/check-peer-reply-citations.py <reply.json> <sha> agy-test-audit`, which rejects any key
this discipline did not declare - so a peer cannot widen its own contract by inventing a field.

**`missing_test` is this discipline's slot, and `trigger` is the capstone's.** MEASURED: the checker
once hardcoded a single ten-key list including `trigger`, an audit brief used `missing_test`, every row
failed on SCHEMA, and the citation check silently never ran while the brief asserted citations were
"checked mechanically". That is why each discipline now declares its own keys.

**On clavity-classic neither parameter exists** - `clavity ask --review-only` does not carry them. Still
demand the echo, but verify it by eye: no automatic verdict will arrive.

## Safety envelope (every consult, no exceptions)
A bare "review-only" once let the peer write to the tree anyway. Wrap each consult:
1. **Snapshot before** - capture `git status --short`.
2. **Forbidden-actions banner** - state in the payload: "REVIEW-ONLY. Do not edit, create, move, or
   delete any file. Do not run mutating commands. Respond with analysis only."
3. **Permission to pass** - the peer may decline or say it needs more; it must not act.
4. **Point at files, not summaries** - write the audit brief + the exact file list to
   `.clavity/seams/<topic>.md` and send the peer the PATH; let it read the committed test+source files
   itself. Never consult it on a pasted summary of your own reading. Any measure-and-reproduce framing
   MUST name a scratch dir (`.clavity/scratch/<topic>/`) so the peer never writes to cwd.
   Prepare BOTH through the shipped writer before writing into them. Each takes a concrete FILE path,
   never a directory - passing `scratch/<topic>/` would create `.clavity/scratch` and not
   `.clavity/scratch/<topic>`, and the next write would fail mid-run:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "seams/<topic>.md"; then
  # ABORT the discipline and say why. A skill that ignores this exit code converts a clean refusal
  # into a mid-run crash on the next write.
  echo "agy-test-audit: ABORTING - could not prepare a shielded .clavity/ directory for seams/<topic>.md." >&2
  exit 1
fi
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "scratch/<topic>/notes.md"; then
  echo "agy-test-audit: ABORTING - could not prepare a shielded .clavity/ directory for scratch/<topic>/notes.md." >&2
  exit 1
fi
```

`<BASE>` is this skill's own base directory, as the harness supplies it at invocation time. It is NOT
`$0` and NOT `${BASH_SOURCE[0]}`: measured, in an agent-run shell snippet those give `/usr/bin` and the
empty string, so a path built from them resolves nowhere.
5. **Diff after** - re-check `git status` against the before-snapshot; if the tree changed, the peer
   breached review-only: surface it loudly and best-effort revert peer-touched paths that were clean
   before (never a blind `git checkout -- .`), then halt-and-ask your human.

## Scope (what the peer audits) - forked by trigger
- **Hook-nudged (branch-finish):** scope to the files in the branch diff and their *immediate* test
  counterparts + directly-relevant source - the same range the capstone reviewed.
- **Manually invoked (`/agy-test-audit <paths>`):** scope to the explicitly provided `<paths>`. A manual
  run on a clean working tree has an EMPTY diff, so the diff-bound must NOT be applied or it audits
  nothing.
Either way: NOT the whole suite or repo (context blow-up, cost, peer timeout). Bind scope in the payload:
audit ONLY these files; assume the surrounding code is correct; no global discovery. Inline the running
accepted-boundary ledger (below) as text each round - the peer's context can truncate; a fresh cascade
carries nothing forward.

**The audit is itself a heavy peer consult** and inherits the peer's own latency/timeout failure modes -
a long consult can hit the peer's idle-wait timeout and be backgrounded. Poll status to idle then retrieve
the completed reply; **NEVER** read a timed-out or errored consult as "no gaps found" (that is a silent
false pass - treat it as peer-unreachable, below).

## The audit round (what to ask, how to check)

**Seat the audit, do not send one voice.** Frame the consult with named adversarial seats drawn from
the adversarial-panel-review palette, seating those whose trigger the diff meets and naming the ones
you dropped - Axiom Breaker (unstated invariants), Cascade Analyst (unhandled failure paths),
Mechanism Gamer (a test that passes without asserting the behaviour), Protocol Pedant (contract and
serialization coverage), State Corruptor (out-of-order and re-entrant paths), Boundary Smuggler
(untrusted input), and the rest. Each seat asks "what would MY defect-class slip past this suite?"
under its own heading; a seat with nothing new writes "no new findings" rather than padding. **On a
re-audit, rotate seats** - each further round seats at least one lens no earlier round used, so the
audit surfaces new gap-classes instead of re-deriving covered ones. This reuses the persona
vocabulary; it is not a code dependency on the panel skill.

1. **Ask for a coverage verdict in a parseable form** the driver checks before accepting: a terminal token
   `[VERDICT: EXHAUSTIVE]` or `[VERDICT: GAPS FOUND]`, plus a machine-checkable `[VERIFIED: <file>, ...]`
   block naming every file the peer actually read. Each gap is enumerated as: the untested behaviour, its
   source `file:line`, the concrete regression that would slip through, and the **specific test that should
   exist** (name + what it asserts). Apply a **severity floor** (skip trivial/contrived nits) - and require
   the audit to **list the top 1-2 gaps it discarded below the floor**, so a real gap cannot be swept under
   the floor unseen. Standing a gap down on that floor is the `DISCARDED-BELOW-FLOOR` disposition and
   carries its evidentiary bar - see "Disposition of findings (AGY-SCOPE)" below.
   - An `[VERDICT: EXHAUSTIVE]` is **valid only if the `[VERIFIED: ...]` block is present and non-empty** -
     regex-reject a bare or malformed EXHAUSTIVE (a silent-success path) and re-ask. A bare "looks
     complete" is not a valid EXHAUSTIVE.
2. **VERIFY each claimed gap by measurement** before accepting it - read the cited test yourself and grep
   for a sibling that already exercises the path. The peer over-counts and states false gaps with full
   confidence (in the motivating run it claimed a "gap" already covered by an existing test; only reading
   it revealed the false positive). Discard unverified gaps. This defends against false *positives* only -
   see the stated limitation below on false negatives.
3. **Maintain an ACCEPTED-BOUNDARY LEDGER** - behaviours deliberately not covered through this harness
   because they are untestable-without-brittle-mocks AND otherwise compensated (a unit test, a catch-scope,
   a structural guarantee). These are do-NOT-re-raise. Each entry records its **specific compensation** +
   a code anchor; a future audit **re-validates the compensation still exists** before honoring the
   do-not-re-raise (an entry whose compensation vanished is promoted back to a live gap).
4. **Surface the VERIFIED gaps to the OWNER to scope** - all / high-severity only / defer. The discipline
   **does not auto-write tests**; the owner decides scope (the AGY-FIRST "owner decides" ethos). Any gaps
   the owner **defers must be logged as tracked debt** on the anomalies conveyor
   (`.clavity/local-anomalies.md`, promoted to a tracked `ROADMAP.md` item) - NOT in the rolling committed
   file below, which holds accepted boundaries only. A GAPS-FOUND-but-all-deferred outcome is legitimate
   only if recorded, so a defer-everything habit is visible in one place and the discipline cannot degrade
   into run-then-defer theater.
5. **Close the chosen gaps - the DRIVER authors each test itself.** The peer's "suggested test" is a
   *specification* (name + what to assert), never code to paste-and-run: the peer's output is untrusted
   input, gated by verify-before-fold (2) and owner-scoping (4), so a confused/compromised peer cannot
   inject executable code via a "gap." Each new test **must be NON-VACUOUS** - it must FAIL if the guarded
   behaviour regresses. Prove non-vacuousness with a **temporary LOGIC MUTANT** of the guarded code (flip a
   boolean, drop a conditional, break a calculation) - NOT a structural/signature break (deleting a
   property/method), which only fails to *compile* and proves the symbol was referenced, not that the
   runtime assertion catches a behavioural slip. Confirm the **specific newly-added test** is the one that
   went red under the mutant - not merely that the suite returned non-zero (a coincidental flaky test could
   satisfy that). If a single-point mutant does NOT turn the test red, that may indicate **defense-in-depth**
   (multiple independent guards), not a vacuous test - widen the mutant or accept a multi-guard regression
   target rather than concluding "vacuous."

   **This bar is not audit-only.** It applies to EVERY test authored in this repo, including tests written
   during ordinary implementation that no audit ever asked for - that is the PINNING-ASSERTION-STRENGTH
   discipline, and the `assertion-strength-reminder.sh` hook nudges it on the first touch of each test file
   per session. It convenes no peer, so it carries no `AGY-` prefix. Three structural smells produce a
   GREEN test over broken code and are worth a deliberate check every time: (1) CARDINALITY over an ordered
   or filtered collection - a count is invariant under any permutation before truncation, so assert
   boundary IDENTITY, never count alone; (2) a DUAL-PATH FALLBACK masked by the ambient environment - strip
   the primary dependency to force the fallback branch to run; (3) a STRUCTURED-TOKEN matcher with no
   DISTRACTOR case - show it REJECTS a near-miss, not only that it accepts the real thing. A fourth,
   measured on this very hook: never assert a bare substring that also appears in the artifact's own PATH -
   the suite passed with no hook on disk because `bash`'s "No such file or directory" error contains the
   filename, and the matcher matched that.

**Every payload MUST carry THREE to FOUR OPEN QUESTIONS the peer answers in its own words** - never a
checkbox, never a yes/no, and never a question whose expected answer is stated in the payload. One
question is not enough: it lets the peer answer the easiest and stop. Draw them from these four shapes,
each of which produced a real finding on 2026-08-19:

1. **Disagree with my guess.** State where YOU think the weakness is, then ask the peer where IT thinks
   it is and to say plainly if you are wrong.
2. **A disposition I have not named.** "Is there an option neither this artifact nor I have named?" A fork
   stated as N options is often really N+1.
3. **Reject the frame.** "Is the signal / metric / approach I have chosen even the right one?" (Produced
   the largest single design change of that session - the chosen signal was wrong and the peer said so.)
4. **Permit ignorance explicitly.** "If you cannot explain this, say so plainly rather than constructing a
   story."

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
lacks one of the five tokens. For this skill that means BOTH `[VERDICT: EXHAUSTIVE]` AND
`[VERDICT: GAPS FOUND]`. GAPS FOUND is a COMPLETING terminus - it ends the run and writes the debounce
marker - so gating only the clean verdict would leave the hole wide open.

**Record the audit in `docs/agy-test-audit-ledger.md` before this run may COMPLETE.** One row: date,
audited range, round count, verdict, and evidence that is independently checkable - the fold commits, or
the brief in `.clavity/seams/`. `none` is not a permitted evidence value: a run that found nothing still
produced a brief, so cite it. This binds to the SAME completing verdicts as the paragraph above, both of
them, for the same reason - gating only the clean verdict would leave the hole wide open.

Without this row the marker is the only trace an audit ever ran, and the marker is a debounce holding
ambient `HEAD`, not a record of what was audited. The question the loop above depends on - is a re-audit
owed? - then has no answer in the tree.

**Anti-sweep.** Each run lists the top 1-2 findings it discarded below the floor, so a real defect cannot
be swept under the floor unseen. The full list goes in the ephemeral per-run report; a one-line summary of
each goes in the branch-finish commit message. An `UNVERIFIED-ACCEPTED` is recorded in
`docs/accepted-boundaries.md` under its owner-accepted mode.

## Capstone-invalidation rule (the discipline's sharpest edge)
Closing a coverage gap sometimes reveals the code is **untestable as written** (hard-wired dependency,
missing seam) and needs an **implementation-source refactor** to test it. Any such source change
**invalidates the prior AGY-CAPSTONE GREEN**: re-run AGY-CAPSTONE over the new code before the branch is
declared done. The audit is NOT a strictly one-way gate - the loop is
`capstone-green -> audit -> (owner-scoped test/refactor) -> if source changed, re-capstone -> re-audit`.
This loop **terminates**: it is owner-gated, the gap set is finite, and a re-capstone reads only the delta.

## Outputs (two distinct artifacts)
- **A per-run report - EPHEMERAL** (scratch dir or a `.gitignore`d path, NOT committed): the coverage
  verdict, the `[VERIFIED: ...]` block, the verified-gap list (each with `file:line`, the slip-through
  regression, and the missing test's name + assertion), and the discarded-below-floor items. Committing one
  per branch-finish would pollute the repo with point-in-time files operators learn to ignore.
- **A single, stable, ROLLING COMMITTED file** - default `docs/accepted-boundaries.md` (a project may
  override the path) - holding ONLY the **accepted-boundary ledger**: the do-not-re-raise list, each entry
  with its compensation + anchor, or under the owner-accepted mode for an `UNVERIFIED-ACCEPTED` finding.
  Closed entries are removed. **Owner-deferred gaps do NOT live here** - they are deferred debt and ride
  `.clavity/local-anomalies.md` to a tracked `ROADMAP.md` item like every other deferral, so this file does
  not become a second backlog. Structure it append-only / section-partitioned to minimize merge conflicts
  (a single file touched every branch-finish is a conflict hotspot where a careless `--ours`/`--theirs`
  silently drops a teammate's entry). A periodic **manual whole-tree garbage-collection pass** reconciles
  it against current code and drops orphaned entries - the routine diff-scoped run cannot see deleted code
  to prune stale entries.

## If the peer is unreachable
No live peer / no auth / the idle-check never clears, or a consult times out / errors: **halt and ask your
human** to restore the channel or explicitly waive the audit - MUST NOT silently skip (a silently-skipped
audit reads as "the tests are exhaustive" - false confidence). In a non-interactive run with no operator,
**abort** emitting `[VERDICT: agy-required-but-unreachable]` and leave the gap list in the run report / CI
logs (NOT the committed debt file - a write just before a non-zero exit in an ephemeral container is lost).
Never a silent pass.

**A CLEAN ROUND IS A COVERAGE CLAIM, NOT A RESULT.** Before accepting one, ask what was NOT examined -
which files went unread, which behaviours were never exercised, which lens was not applied. A round that
finds nothing has told you about its own coverage, not about the artifact.

## The [VERDICT] tokens (ASCII only, emitted by disposition)
ASCII only - no em-dash or other non-ASCII (mojibake risk; this project has hit corruption). You (the
driver) emit these:
- `[VERDICT: EXHAUSTIVE]` - a clean audit: the peer read a non-empty `[VERIFIED: ...]` set and, after your
  measurement, no verified gap survives above the severity floor. Proposes the safety-net is adequate; the
  human still owns the gate.
- `[VERDICT: GAPS FOUND]` - one or more verified gaps remain; each carries one of the five AGY-SCOPE
  disposition tokens above. A GAPS-FOUND run is legitimately "done" only when EVERY gap carries such a
  token - closed now (`FOLDED`), refuted by measurement (`REJECTED`), stood down on a cited reachability
  guard (`DISCARDED-BELOW-FLOOR`), deferred and logged as tracked debt (`DEFERRED-TO-ANOMALIES`), or
  owner-accepted as unverifiable (`UNVERIFIED-ACCEPTED`).
- `[VERDICT: agy-required-but-unreachable]` - the consult could not run (genuine connectivity failure or a
  timed-out/errored heavy consult) and no operator waived it. Never a silent pass.

## Stated limitation - false negatives
Every guard above defends against false *positives* (the peer claiming a gap that isn't one). NONE defends
against a false *negative* - the peer silently missing a real gap. A single-peer audit is a **floor, not
proof of completeness**, and does not replace good test design or the author's own coverage judgement.
The seat rotation required by "The audit round" above is what mitigates this in practice: a lens that
never rotates cannot discover the modality it was never pointed at. It is a mitigation, not a cure -
a rotated panel still proves no completeness.

## Debounce marker (hook contract - written here, read by the auto-fire hook)
Record that the audit ran so the marker-gated reminder hook (shipped separately) does not re-nudge for the
same `HEAD`. Write the marker through the shipped writer, never by hand: it asserts the `.clavity/`
shield BEFORE the write and creates the directory it writes into.

```bash
bash "<BASE>/../../hooks/agy-mark.sh" head "agy-test-audit" "$(git rev-parse HEAD)"
```

- **Path:** `.clavity/agy-marks/agy-test-audit.head` - a single discipline-keyed marker, no `<plugin-id>`
  prefix (Option S, as for agy-first/agy-capstone). See `docs/agy-disciplines-marker-contract.md`.
- **Content:** ambient `HEAD`, exactly as the command above writes it. If HEAD cannot resolve, skip
  writing (the discipline re-fires next trigger - safe).

  > This line said "the audited sha ... not ambient HEAD" until 2026-08-26, which CONTRADICTED the command
  > four lines above it - and the command is the half an agent actually runs. Each half read as correct on
  > its own, which is how it survived nineteen review rounds. Ambient `HEAD` is the right content: the
  > reminder hook goes quiet when the audit marker STILL DESCRIBES HEAD - it either equals HEAD, or is an
  > ancestor of it with nothing executable landed since - so writing anything else leaves it nudging
  > forever after a completed audit. (This paragraph said `audit-marker == HEAD` until 2026-08-26. That
  > was the rule when it was written and was relaxed one round later, by a fold that changed no
  > `SKILL.md` - the same fact, one artifact further on.) The case the old wording worried about - closing gaps advanced HEAD - is
  > already handled elsewhere and more strictly: executable changes after the capstone's reviewed tip make
  > the capstone GREEN stale, the hook falls silent on its own, and this skill's own capstone-invalidation
  > rule requires a re-capstone before the branch is done.
- **Written ONLY on a completed audit** - an `[VERDICT: EXHAUSTIVE]`, or a `[VERDICT: GAPS FOUND]` whose
  gaps ALL carry an AGY-SCOPE disposition token. An `agy-required-but-unreachable`
  abort writes NO marker (the discipline re-fires next trigger). If closing gaps advanced HEAD by touching
  executable code, the capstone GREEN no longer describes HEAD - do not paper over that by choosing a
  different sha to record; re-run AGY-CAPSTONE, per the capstone-invalidation rule above.

`.clavity/` is runtime state and is gitignored - never commit a marker.
