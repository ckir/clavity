# Discipline efficacy — session-end reaching recorder

**Status:** design, approved in shape by the owner 2026-08-04. Implements ROADMAP `§0` step 1, as split by
the owner: **measure first, prompt later.**

**Goal.** Answer one question from recorded evidence, without asking any agent what it thinks happened:
**is the AGY-ANOMALIES discipline reaching a driver at all, and on which channel?**

**Explicit non-goal.** This does not measure conversion — whether a delivered nudge caused a capture. It
cannot, and pretending otherwise is the failure this whole item exists to remove. Conversion is answered
later by the outside-witness trial (ROADMAP `§0` step 3).

---

## The problem, as measured

Verified 2026-08-04 against `clavity-dotnet/plugin/hooks/hooks.json`, independently by the driver and by
the agy peer: **across every registered event, ZERO hooks prompt a driver working DIRECTLY — not
dispatching, not compacting — to capture an anomaly.**

- `PreCompact` fires only on compaction, so a short or medium session never reaches it.
- `Agent|Task` requires a dispatch.
- `SessionStart` carries drain/triage notices for anomalies that already exist, not a capture prompt.
- `agy-seam-inject.sh:54` matches only `*subagent-driven-development*|*executing-plans*`; `:55` is
  `*) exit 0` for every other skill.

v16 closed gap (a) only for sessions long enough to compact. **Nothing recorded that**, which is the
deeper defect: every gate measures presence, none measures arrival.

### Why the obvious fixes were unavailable, and what unblocked it

This epic's own spec disposed of both natural homes for a direct-driver prompt —
`docs/superpowers/specs/2026-08-04-agy-anomaly-capture-gap-design.md:65` withdrew a `Stop` hook
(*"Fires 100+ times in a long session and would manufacture exactly the blind-answering that
`adversarial-panel-review`'s `--low` bypass exists to avoid"*) and `:67` rejected firing on tool output
(*"Misses the quiet cases, fires on ordinary debugging"*).

**The blocker turned out to be an incomplete enumeration, not a real tension.** `SessionEnd`,
`UserPromptSubmit` and `PostToolUseFailure` appear **zero times** in this epic's spec, plan, or the
ROADMAP, yet all three are real, shipping Claude Code events — `SessionEnd` and `PostToolUseFailure` at
`~/.claude/plugins/cache/ecc/ecc/2.0.0/hooks/hooks.json:338` and `:248`, `UserPromptSubmit` in
Anthropic's own official marketplace (`plugins/hookify/hooks/hooks.json:37`).

`SessionEnd` occupies the slot the epic assumed was empty: **fires once, reaches every session including
short ones, and fires after the driver has demonstrably done work.**

| event | frequency | reaches a short direct session | fires after work is done |
|---|---|---|---|
| `SessionStart` | 1x | yes | no — too early |
| `Stop` | 100+x | yes | yes — and that frequency is what disqualified it |
| `PreCompact` | 0–1x | **no** | yes |
| **`SessionEnd`** | **1x** | **yes** | **yes** |

---

## Design

### Shape

`SessionEnd` **reads**; it does not ask the nudge hooks to report. This is the load-bearing choice.

The obvious design — have each nudge hook increment a counter — reintroduces the exact hazard the marker
contract already settled: `docs/agy-disciplines-marker-contract.md:55` and `:80-82` establish that **the
skill writes and the hook never does**, and the dispatch reminder in particular sits on a path where a
non-zero exit blocks every subagent dispatch in the session. A best-effort write there is still a write on
a fail-open path.

Instead: the nudge text carries a **stamp**, and `SessionEnd` greps the session transcript for it. No hook
on a fail-open path writes anything. Exactly one write happens, at session end, where nothing is blocked.

**This appeared to reorder ROADMAP `§0` — and round 1 then overturned that.** The stamp looked like a
prerequisite of step 1 while delivery was to be detected by grepping for it. Once detection moved to
record structure, that justification vanished. See "The stamp's rationale was obsoleted" below: the stamp
is **parallel to** the recorder, not blocking it, and its surviving purpose is version provenance — which
is also why `§0`'s separate argument for stamping *before the witness trial* still stands untouched.

### What is recorded

One append-only record per session. **Reaching only — the recorder does not track captures at all.**

| field | type | meaning |
|---|---|---|
| `v` | int | schema version. Required; the shape below is not final until STEP 0 resolves counts-vs-booleans |
| `session_id` | string | correlation |
| `timestamp` | string | ISO-8601, UTC |
| `precompact_nudges` | int \| bool \| `null` | stamped deliveries of the `PreCompact` capture reminder |
| `dispatch_nudges` | int \| bool \| `null` | stamped deliveries of the `PreToolUse` dispatch relay |
| `scan_status` | enum | `ok` \| `bounded_out` \| `transcript_unreadable` \| `transcript_not_found` |

**Channels are named by EVENT, never by an interpretive label like "direct".** This is not pedantry: the
only capture-side hook that exists today fires on `PreCompact`, so a field called `direct_nudges` would
read `> 0` whenever a session merely compacted — and an evaluator would conclude direct-driver reaching
works when it demonstrably does not. The field name must not carry the conclusion the data is supposed to
establish. When a genuine direct-driver trigger is later added (`§0` step 1b), it gets its own
event-named field.

`scan_status` is required, never omitted. **A `null` count with `scan_status: ok` is impossible by
construction**; a `null` always carries the reason it is null, so an unknown can never be read as a zero
and a bounded-out scan can never be mistaken for a missing record.

### No capture field, and no SessionStart write — decided, with reasons

An earlier draft recorded an `anomalies_delta` (entries at session end minus a `SessionStart` baseline).
**Both are removed.** Three independent defects killed them, and dropping the field collapses all three:

- **Triage arithmetic erases captures.** A session that triages 3 pending anomalies and captures 2 new
  ones records `-1`. Totalled across sessions, triage deletions cancel new captures — a week with 10
  triaged and 10 captured reports *zero capture activity*.
- **It contradicted this design's own axiom.** "Exactly one write, at session end" is false if
  `SessionStart` must also write.
- **It coupled two lifecycle events.** The recorder would need `SessionStart` AND `SessionEnd` to both
  succeed, and per-session baseline files would be orphaned in `.clavity/` by every crashed or killed
  session, with no cleanup owner.

The deeper reason is scope: a capture count is the **numerator of a conversion ratio this design cannot
compute**, because it has no trustworthy denominator — zero captures in a clean session is the correct
true-negative outcome, and nothing here can distinguish that from five missed defects. Conversion is
measured by the outside-witness trial (`§0` step 3) against known injected ground truth, or not at all.

With the capture field gone, the axiom is literally true again: **no hook writes on any path except
`SessionEnd`, which blocks nothing, and the recorder is self-contained in that one hook.**

### Where it lives, and the cases the shape has to survive

**Location: `.clavity/discipline-reaching.jsonl`** — one JSON object per line, append-only, per repo.
`.clavity/` is gitignored runtime state (`.gitignore:45`), which is correct here: this is per-machine
observation, not a shipped artifact, and it must never be committed. One line per session keeps appends
atomic enough for the concurrency case below without a lock file.

Cases the design must handle, each with its decided behaviour:

| case | behaviour |
|---|---|
| `.clavity/` absent entirely | create it; a fresh clone has no `.clavity/` |
| transcript unreadable (Windows write-lock at teardown), or path unresolvable | counts `null`, `scan_status` names which. **Never `0`** — an unknown recorded as a measured zero is this item's own thesis inverted |
| transcript scan hits the time budget | counts `null`, `scan_status: bounded_out`, **and the record still lands**. A missing record and a bounded-out record must not look alike |
| two sessions open in the same repo concurrently | both append; `session_id` disambiguates. With the capture field gone there is no cross-session arithmetic left to corrupt — reaching is per-session by construction |
| `SessionEnd` does not fire (abnormal exit) | no record. STEP 0 item 2. The consumer must therefore report *sessions recorded*, never *sessions run* |

### 🔴 R1 — the survival bias, and why bounding the read is not merely an optimisation

Bounding the scan is usually a performance concern. Here it is a **correctness** one, and in the worst
possible direction.

An early-exit scan stops as soon as it finds a nudge. But **proving a nudge is ABSENT requires reading the
whole transcript** — and absence is precisely the hypothesis under test. So the sessions most likely to
exhaust the time budget are exactly the zero-nudge direct sessions this whole item exists to detect.
Those record `null`; nudge-bearing sessions match early and record cleanly. **The dataset would
systematically drop true zeros and retain non-zeros — it would lie in the one direction that matters.**

`scan_status: bounded_out` makes the loss visible rather than silent, and the consumer reporting
bounded-out records separately is what stops the bias being read as data. That is mitigation, not a fix.

**The candidate fix, which is a HYPOTHESIS and remains UNMEASURED (STEP 0 item 6):** the same property
that invalidated counting may rescue absence-detection. Because the JSONL re-serialises conversation
context, a nudge delivered early may appear again in later records, in which case a bounded **tail** scan
of the last N records establishes presence-or-absence at fixed cost, making the read O(1) in session
length.

**An attempt to measure this on 2026-08-04 was CONFOUNDED and must be redone — see the contamination
finding below.** Do not record it as validated; it is not.

### 🔴 THE STAMP'S RATIONALE WAS OBSOLETED BY THE STRUCTURAL-DETECTION FOLD — resolve before planning

Round 1 concluded that detection must key on the transcript's **record structure**, not on text. That fold
spawned its own edge, and it lands on `§0`'s sequencing.

The stamp was justified twice, and structural detection removes one of the two justifications:

- **As a delivery marker — now redundant.** Its original job was to make a nudge greppable and to separate
  nudge text from authored text. Structural detection does that better, and text-matching is ruled out by
  three measured mechanisms. **The stamp buys nothing for detection.**
- **As version provenance — still needed, and unaffected.** Distinguishing a *stale installed* hook from a
  *current* one is a different question that structure cannot answer: a record's shape says a hook fired,
  not which build emitted it. That was the original §0 rationale ("makes a stale install distinguishable
  from a silent one") and it survives intact.

**Consequence for `§0`:** the stamp is NOT a prerequisite of the recorder, as this spec claimed before
round 1. The recorder can be built and shipped without it. The stamp remains worth doing for provenance,
but it is **parallel to** step 1 rather than blocking it — and if the recorder ships first, its records
simply cannot answer "which build" until the stamp lands. **Update `§0` when this spec is ratified;
leaving both documents claiming a prerequisite that no longer exists is exactly the incomplete fold this
project keeps paying for.**

### Record-file lifecycle — unbounded by default

`.clavity/discipline-reaching.jsonl` is append-only, one line per session, forever, per repo. Nothing in
this design prunes or rotates it. At a few hundred bytes per line this is slow-growing rather than
dangerous, but "slow-growing and never examined" is how the `_partition.md` counts decayed. **Decide a
retention rule in the plan** — a line cap, an age cap, or an explicit "unbounded, and here is why that is
acceptable". Do not leave it unstated.

Two identifiers the spec has not sourced, both needed before implementation: **where `session_id` comes
from** (the same STEP 0 unknown as the transcript path — `CLAUDE_SESSION_ID` is a candidate, unverified),
and **what `v` is set to for this first shape**, plus what a consumer does with a version it does not
recognise (recommended: count it separately rather than parsing it, mirroring the `null` discipline).

### 🔴 THE TRANSCRIPT IS SELF-REFERENTIAL — measured, and it constrains every text-based approach

**Measured 2026-08-04.** A control string invented at the keyboard and never emitted by any hook
(`ZZZ-NEVER-EMITTED-STRING`) was searched for in a live transcript. It returned 1 hit immediately, and
**11 hits** moments later. The transcript's mtime was 10 seconds old: it is written live, and **the act of
searching for a string writes that string into the corpus being searched**, via the tool-call record.

Three consequences, all load-bearing:

1. **It confounded the tail-scan measurement above.** The tail hits could not be distinguished from the
   query that looked for them. Any STEP 0 measurement of the tail hypothesis must be designed so the
   measuring command's own text cannot match — for example by measuring a transcript that is definitively
   closed, or by keying on structure rather than text.
2. **It is a third independent reason text-matching cannot work**, alongside context re-serialisation and
   authored content. Free-text detection has a *feedback loop*: the detector pollutes its own evidence.
   **Detection must key on the transcript's typed record STRUCTURE for a hook injection. This is no longer
   a preference; three separate measured mechanisms rule out the alternative.**
3. **It taints the earlier 470-occurrence figure.** That number was real evidence that counting is invalid,
   and remains so — but the specific magnitude is contaminated by the measurer and must not be quoted as a
   delivery count.

The general lesson, worth carrying beyond this spec: **a probe needs a control that must fail, and here
the control did fail — which is the only reason this was caught rather than shipped as a validated
hypothesis.**

**Named consumer, stated now so this is not written and never read:** a `just` recipe that prints, over the
last N recorded sessions, `precompact_nudges` and `dispatch_nudges` totals — with records carrying `null`
counted and reported **separately, broken down by `scan_status`**, so unknowns are never folded into zeros
and the bounded-out survival bias stays visible rather than becoming silent data loss.

**The ratio prohibition is now STRUCTURAL rather than a stated rule, and that is strictly better.** An
earlier draft forbade the consumer from printing `captures / nudges`, because that number would
manufacture the confident-wrong "0% conversion" (the Quiet Zero failure mode). With the capture field
removed there is no numerator in the record at all — **the forbidden number is unconstructible from this
data.** A prose prohibition depends on every future reader obeying it; an absent field does not. Keep the
reasoning recorded here so a later change does not reintroduce the numerator without understanding what it
costs.

**The recorder ships to BOTH drivers, byte-identically**, like every other hook in this repo — mirrored
into `clavity-classic/plugin/hooks/`, enforced by `scripts/tests/plugin-hooks-payload.Tests.ps1` and the
whole-`.hooks` comparison in `scripts/check-seed-artifacts-synced.sh`. It therefore cannot carry a
per-driver literal (Option S, `docs/agy-disciplines-marker-contract.md:13`), which constrains anything
identifying the emitting driver in the record.

### Scope, and what was rejected

Recording is deliberately limited to reaching. Two richer options were considered and rejected:

- **A plausible-opportunity denominator** (count sessions where a tool failed, or that exceeded N turns,
  as "had something to capture"). Rejected: tool failures are routine task work — a TDD red phase, an
  expected compile error, a grep miss. Ten failing tests in a normal session would be recorded as
  "10 opportunities, 0 captured", a fabricated 0% conversion; while a silent defect that exits 0 has
  denominator zero and disappears. A guessed proxy manufactures the appearance of rigour and pollutes the
  signal with false negatives.
- **Full multi-discipline telemetry.** Rejected as building the presence-checking infrastructure this item
  exists to stop building, before the smallest version is shown to work.

---

## STEP 0 — measure before building. Two assumptions are unverified.

Neither is safe to assume, and both are cheap to settle. **The implementation plan starts here, and if
either fails the design changes rather than the finding being written down as a caveat.**

1. **Does the `SessionEnd` payload carry `transcript_path`?** Confirmed present on `PreCompact` (observed
   live in a real payload this session) and on `SessionStart`. NOT confirmed for `SessionEnd`. The one
   shipping handler inspected (`ecc`'s `session-end-marker.js`) reads neither `transcript_path` nor
   `session_id` from stdin — it resolves identity from the `CLAUDE_SESSION_ID` environment variable — so
   it is not evidence either way.
   **Fallback if absent:** the transcript path is reconstructible from session id plus cwd. The fallback
   itself rests on `CLAUDE_SESSION_ID` actually being set in the hook environment, which is **also
   unverified** — it was only observed as a default parameter in third-party code, never measured.
2. **Does `SessionEnd` fire reliably on every exit path** — a normal end, `/clear`, a closed terminal, a
   killed process? A recorder that silently misses the abnormal exits under-counts sessions and biases
   every ratio derived from it.
3. ✅ **RESOLVED BY MEASUREMENT 2026-08-04 — injected hook context DOES appear in the transcript.** A real
   transcript in `~/.claude/projects/C--Users-user-Development-Rust-clavity/` contains the
   `PreToolUse:Agent` relay text, the `PostToolUse` AGY-AFTER text and the bottom-up-gating text. Reading
   the transcript is therefore a viable delivery signal **in principle**. See the defect it exposed below.

### 🔴 THE COUNTING MECHANISM IS INVALID AS ORIGINALLY SPECIFIED — measured, not theorised

The first draft said `SessionEnd` greps the transcript and counts occurrences. **Measured: the relay text
occurs 470 times in a single session's transcript against ONE actual dispatch.** Two independent causes,
either of which alone breaks a count:

1. **The JSONL re-serialises conversation context**, so one injection appears in many subsequent records.
   The number is "records containing this text", not "times it was delivered".
2. **The same text appears in AUTHORED content** — my own messages, the hook source, this spec. In this
   repository the nudge text *is* the subject matter, so authored occurrences are not an edge case, they
   are guaranteed. No choice of stamp string escapes this, because any stamp gets written into the docs
   that describe it.

**Consequence:** delivery must be detected from the transcript's **record STRUCTURE** — the typed entry a
hook injection produces — never from free-text matching anywhere in the file. That structure is unknown
and becomes STEP 0 item 5.

**And it may reduce the contract:** if structure yields a reliable *occurred / did not occur* signal but
not a trustworthy count, then `precompact_nudges` and `dispatch_nudges` become **booleans**, not integers.
That still answers the v15 question exactly — reaching is a 0-vs-N question — and a boolean is immune to
the inflation measured above. **Decide this from the STEP 0 measurement; do not assume a count is
obtainable.**

4. **Does `SessionEnd` impose a timeout, and can the transcript be read inside it?** `ecc` registers its
   `SessionEnd` hook with `"timeout": 10`
   (`~/.claude/plugins/cache/ecc/ecc/2.0.0/hooks/hooks.json:338-353`). **Measured: a real transcript in
   this project is 134 MB.** A full-file scan inside a 10-second budget is not obviously feasible, and
   failing it produces no record *silently, for exactly the long sessions most likely to contain a nudge*
   — a bias in the worst possible direction. **The read must be bounded** (tail-N records, or an early
   exit on first structural match if the signal degrades to a boolean).
5. **What is the transcript's record structure for an injected hook context?** Required by the defect
   above. Also unresolved: **how the hook locates the transcript at all.** Measured: the task-directory id
   observed at runtime is NOT the transcript filename, and 131 `.jsonl` files sit in this project's
   transcript directory with no observed way to pick the current one. So the STEP 0 item 1 fallback
   ("reconstructible from session id plus cwd") is **weaker than first written** — it collapses entirely
   unless `transcript_path` is in the payload or `CLAUDE_SESSION_ID` is genuinely set.

---

## Failure modes this design must be read against

- **The Quiet Zero.** Thirty sessions with `nudges: 30, captures: 0` in a clean environment reads as
  "0% conversion, the prompt is ignored" when it may be thirty true negatives. The dangerous response is
  making prompts louder, which manufactures the fatigue reflex below. **Mitigation: the record answers
  reaching, and any conversion claim from it is out of contract.** State that where the data is read, not
  only here.
- **The "Anomalies noticed: none" reflex.** A model learning to append a canned `none` to satisfy the
  structure. It makes the relay read 100% compliant while capturing nothing, and it is the reason the
  high-frequency events were disqualified. This recorder does not prompt, so it does not create the
  reflex — but it also cannot detect it, and must not be cited as evidence against it.
- **Recorder rot.** A record nobody reads is presence-checking with extra steps. The record must have a
  named consumer and a stated question before it is worth writing.

---

## Testing

- Pester suites, matching the existing hook suites' conventions (`scripts/tests/*.Tests.ps1`).
- Assertions follow the discipline earned in v16: **every negative, equality or count assertion must first
  assert its subject exists and is non-empty**, and any non-vacuity proof must show the mutation both
  landed *and* left the artifact executable.
- Cross-driver parity is a requirement, not a follow-up: anything shipped here ships byte-identically to
  `clavity-classic`, enforced by `scripts/tests/plugin-hooks-payload.Tests.ps1` and the whole-`.hooks`
  comparison in `scripts/check-seed-artifacts-synced.sh`. A stamp cannot carry a per-driver literal —
  see Option S at `docs/agy-disciplines-marker-contract.md:13`.

## Deferred, with where each resolves

- **Where the direct-driver prompt eventually goes** (`UserPromptSubmit`, `PostToolUseFailure`, or a
  derived trigger) — deferred deliberately by the owner's split, to be decided from this recorder's data
  rather than guessed. ROADMAP `§0` step 1b.
- **The outside-witness trial** — ROADMAP `§0` step 3. Carries its own named failure mode, synthetic trial
  overfitting: a loud induced defect resembling the prompt's own examples proves nothing about the subtle
  real ones.
- **The firing counter as originally conceived** — dropped. This recorder supersedes it, without any hook
  writing on a fail-open path.
