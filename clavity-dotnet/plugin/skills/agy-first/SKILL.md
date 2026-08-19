---
name: agy-first
description: Use when facing a design, scope, approach, or sequencing fork in subproject work (typically at the brainstorming approaches step). Runs a divergent, review-only consult of the live agy peer under forcing functions, verifies every factual claim by measurement before folding, negotiates on material disagreement, and ends with one ASCII [VERDICT] token. Best-effort prompt-discipline, manually invokable; auto-fire is added separately.
---

# agy-first - consult the peer on a fork before you commit to it

## When to use
Invoke this skill whenever you face a **design / scope / approach / sequencing fork** in subproject work
and are about to pick a direction - invoke it manually, or run it when the auto-fire hook (shipped
separately) injects its directive at the brainstorming approaches step. The value is not "ask agy" - the
peer is confidently wrong often enough that folding its advice unchecked would *degrade* the outcome. The
value is the discipline that wraps the consult: **verify every bare factual claim by measurement before
folding it, and negotiate a synthesis on material disagreement** rather than defer-to-peer or
dismiss-the-peer.

This is **best-effort prompt-discipline, not a sandbox.** The `[VERDICT]` token below is self-reported;
its forcing functions make hollow compliance visible to your human - do not make it impossible. The bar
is "materially better than deciding blind," not determinism.

Works with or without superpowers - superpowers only adds the auto-fire and its approval breakpoints.
You can always invoke this skill directly on a fork; when you do, **surface every result and decision to
your human in-chat** (there is no breakpoint to defer to).

## Transport (resolve to your own plugin)
Send the consult over your driver's review-ask transport, review-only:
- **clavity-dotnet:** the `agy_ask` MCP tool, after an `agy_status` idle-check (do not fire while the
  peer is busy).
- **clavity-classic:** `clavity ask --review-only` (subagents use the CLI form, not the MCP bus).

## Completeness checks the DRIVER runs on your reply (13b)

**NAME YOUR DISCIPLINE ON EVERY ASK.** On clavity-dotnet pass `discipline: "agy-first"` to `agy_ask`; the driver
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
A bare "review-only" once let the peer write to the tree anyway. Wrap each consult:
1. **Snapshot before** - capture `git status --short` (and reflog if the fork touches committed work).
2. **Forbidden-actions banner** - state in the payload: "REVIEW-ONLY. Do not edit, create, move, or
   delete any file. Do not run mutating commands. Respond with analysis only."
3. **Permission to pass** - the peer may decline or say it needs more; it must not act.
4. **Point at files, not summaries** - write the fork/options to `.clavity/seams/<topic>.md` and send
   the peer the PATH; let it read the artifact itself. Never consult it on a pasted summary of your own
   measurements. Prepare that directory through the shipped writer FIRST - it asserts the `.clavity/`
   shield before anything is written there, and it fails closed:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "seams/<topic>.md"; then
  # ABORT the discipline and say why. A skill that ignores this exit code converts a clean refusal
  # into a mid-run crash on the next write.
  echo "agy-first: ABORTING - could not prepare a shielded .clavity/ directory for seams/<topic>.md." >&2
  exit 1
fi
```
5. **Diff after** - re-check `git status` against the before-snapshot. If the tree changed, the peer
   breached review-only. A breach is a **security event, not a routine skip** - do NOT proceed silently
   and do NOT fold anything: (a) surface the breach loudly to your human and get confirmation before
   continuing; (b) revert **only the paths the peer touched** (diff the after-state against your
   before-snapshot and restore exactly those files) - **never** a blind `git reset --hard` /
   `git checkout -- .`, which would also destroy your own legitimate uncommitted work captured in the
   snapshot; (c) then emit `[VERDICT: SKIPPED-UNREACHABLE]` (the peer's advice is discarded). The
   "proceed, never hang" rule below is for a genuinely *unreachable* peer, NOT a detected breach.

## The consult (divergent, forcing-function driven)
Frame the fork as a GOAL + a checkable SUCCESS CRITERION with full method latitude - NOT a vague "be
creative" dial (the peer converts that into superficial novelty). Shape divergence with vectors as
needed: invert the core constraint (solve it WITHOUT the main assumed component); the extreme-resource
version (1 hour / $0, or the opposite); the dumbest brute-force baseline that still works; a cross-domain
analogy. Each alternative must stay USEFUL against the goal and note its real tradeoffs.

**Seat a panel, not a persona.** A single voice returns a single lens. Seat the
adversarial-panel-review personas - Axiom Breaker (contradictions / unstated invariants), Cascade
Analyst (unhandled failure paths), Literal Implementer (what an executor would have to guess), State
Corruptor (out-of-order / stale state), Blindspot Auditor (irreversible footguns / missing
observability), Mechanism Gamer (gameable gates / false-GREEN), and the rest - seating those whose
trigger THIS fork meets, and NAMING the seats you consciously dropped and why, so an under-seated
panel is visibly under-seated rather than quietly thin. Each seat answers under its own heading in
its own voice; a seat with nothing new writes "no new findings" instead of padding. Override with a
sharper bespoke lens when the fork calls for it. This reuses the persona vocabulary; it is not a code
dependency on the panel skill. **On a multi-round consult, rotate seats** - each further round seats
at least one lens no earlier round used.

The peer is empowered to CHALLENGE your own settled decision when it has a
substantive reason (correctness, safety, a materially better design, a hidden contradiction) - you keep
the final call.

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

## Verify before you fold (the spine)
Before folding ANY factual claim the peer makes, **verify it by measurement and quote the measured
output** - the tool stdout or the file line you relied on - in your writeup. A fold with no quoted
measurement is visibly hollow to your human. The peer states false claims with identical confidence to
true ones; an unverified fold is how a confabulation enters your design.

## AGY-NEGOTIATE (conditional sub-protocol)
Engage negotiation ONLY on a **material** disagreement - one that changes **architecture, performance,
or security**. Style, naming, and trivia never qualify (those resolve to `ALIGNED`; you yield). Trigger:
your consult emits `[VERDICT: NEGOTIATE - <reason>]`.

- **Round cap:** `MAX_NEGOTIATE_ROUNDS = 2` (tunable). Round 1: you present measured evidence, the peer
  counters. Round 2: you attempt a synthesis that takes the best of both.
- **Impasse (no forced synthesis):** if not converged at the cap, declare **IMPASSE**, document both
  positions plainly in-chat (each with its measured support), and hand your human the tie-break directly.
  If running under superpowers its approval breakpoint is the natural place to adjudicate, but never rely
  on a breakpoint that may not exist (manual invocation has none). Do not fabricate agreement.
- **Manual backstop:** your human can type "negotiate with agy" to trigger this protocol on any observed
  disagreement, regardless of the emitted token.

**A CLEAN ROUND IS A COVERAGE CLAIM, NOT A RESULT.** Before accepting one, ask what was NOT examined -
which files went unread, which behaviours were never exercised, which lens was not applied. A round that
finds nothing has told you about its own coverage, not about the artifact. Measured 2026-08-19: of two
clean rounds in one session, both later proved to have missed a real defect that hand-enumeration found.

## End with exactly one [VERDICT] token (ASCII only)
ASCII only - no em-dash or other non-ASCII (mojibake risk; this project has hit corruption). Emit exactly
one, as the last line:
- `[VERDICT: ALIGNED]` - you and the peer agree; proceed.
- `[VERDICT: REJECTED - <measured reason>]` - the peer is factually wrong, killed by measurement; you
  override without negotiation and quote the measurement that killed it.
- `[VERDICT: NEGOTIATE - <one-line material reason>]` - a material disagreement remains; run
  AGY-NEGOTIATE above.
- `[VERDICT: SKIPPED-UNREACHABLE]` - the consult could not run.

## If the peer is unreachable
No live peer / no auth / the idle-check never clears: emit `[VERDICT: SKIPPED-UNREACHABLE]` and
**proceed** - never hang, never hard-block. Surface the skip on BOTH channels: (a) tell your human
in-chat that the consult was skipped and name the fork it skipped; (b) append one durable audit line
through the shipped marker writer, which owns the timestamp and the line format and creates the
directory it writes into:

```bash
bash "<BASE>/../../hooks/agy-mark.sh" log "agy-first" "SKIPPED-UNREACHABLE" "$(git rev-parse HEAD)"
```

so it is not lost if the chat summary drops it. Do NOT write the consulted marker (below), so the next trigger
retries. (The log is a gitignored breadcrumb - it survives normal operation; only a deliberate
`git clean -fd` wipes it, which is an accepted level for a skip breadcrumb, so the in-chat notice is the
immediate signal and the log the durable backstop.)

## Debounce marker (hook contract - written here, read by the auto-fire hook)
Only AFTER a consult actually completes (any of ALIGNED / REJECTED / NEGOTIATE-resolved), record it so
the auto-fire hook does not re-inject this discipline for the same cycle. Write it through the shipped
marker writer, never by hand: it asserts the `.clavity/` shield BEFORE the write and creates the
directory it writes into.

```bash
bash "<BASE>/../../hooks/agy-mark.sh" head "agy-first" "$(git rev-parse HEAD)"
```

`<BASE>` is this skill's own base directory, as the harness supplies it at invocation time. It is NOT
`$0` and NOT `${BASH_SOURCE[0]}`: measured, in an agent-run shell snippet those give `/usr/bin` and the
empty string, so a path built from them resolves nowhere.

- **Path:** `.clavity/agy-marks/agy-first.head` - a single discipline-keyed marker, no `<plugin-id>`
  prefix (**DECIDED: Option S**; AGY-AFTER solo panel + agy escalation ALIGNED, owner ratifies). The
  byte-identical skill body cannot carry a per-plugin literal, and the two drivers are mutually exclusive
  (only one `clavity` plugin installed; both-installed is a transient migration state where a shared
  marker correctly debounces the shared phase and *prevents* a duplicate paid consult). See the marker
  contract doc, docs/agy-disciplines-marker-contract.md.
- **Content:** the output of `git rev-parse HEAD` at consult time, nothing else. **If `git rev-parse
  HEAD` cannot resolve** (not a git repo / a repo with no commits), skip writing the marker entirely -
  the discipline simply re-fires next trigger, which is safe.
- **Lifecycle:** a new commit (new HEAD sha) or a later fork on the same branch changes the content and
  re-arms the discipline. A `SKIPPED-UNREACHABLE` or a review-only breach writes NO marker (see above),
  so the next trigger retries. If you ignore the injected directive entirely, no marker is written and
  the next trigger re-fires - non-compliance self-heals to a retry.

`.clavity/` is runtime state and is gitignored - never commit a marker.
