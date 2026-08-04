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

**This reorders ROADMAP `§0`.** The stamp was listed as step 2; it is a **prerequisite of step 1**,
because it is what makes a delivery greppable.

### What is recorded

One append-only record per session:

| field | meaning |
|---|---|
| `session_id` | correlation |
| `timestamp` | ISO-8601, UTC |
| `direct_nudges` | count of stamped direct-capture deliveries found in the transcript |
| `dispatch_nudges` | count of stamped dispatch-relay deliveries found in the transcript |
| `anomalies_delta` | entries in `.clavity/local-anomalies.md` at session end minus the count at session start |

`anomalies_delta` needs a baseline, so `SessionStart` records the starting count. `SessionStart` already
has registered hooks, so no new event is introduced for it.

**Channel attribution is the point, not decoration.** The v16 defect is specifically that the *direct*
channel never fires. `direct_nudges == 0` across many sessions while `dispatch_nudges > 0` is unarguable
evidence of that, and no aggregate count would show it.

### Where it lives, and the cases the shape has to survive

**Location: `.clavity/discipline-reaching.jsonl`** — one JSON object per line, append-only, per repo.
`.clavity/` is gitignored runtime state (`.gitignore:45`), which is correct here: this is per-machine
observation, not a shipped artifact, and it must never be committed. One line per session keeps appends
atomic enough for the concurrency case below without a lock file.

Cases the design must handle, each with its decided behaviour:

| case | behaviour |
|---|---|
| `.clavity/local-anomalies.md` absent at session start | baseline is `0`; absence is not an error |
| `.clavity/` absent entirely | create it; a fresh clone has no `.clavity/` |
| transcript unreadable, or `transcript_path` absent and unreconstructible | record the session with `direct_nudges` and `dispatch_nudges` as `null`, **not `0`** — an unknown must never be recorded as a measured zero, which is this item's own thesis |
| two sessions open in the same repo concurrently | both append; `session_id` disambiguates. Deltas are per-session and may interleave — the baseline is read at that session's start, so a concurrent capture by the other session inflates one delta and not the other. **Accepted and stated**, not silently wrong: the record answers reaching, and reaching is per-session |
| a session captures an anomaly then deletes it | delta may be `0` or negative. Negative is legal and recorded as-is; clamping it would hide a triage that ran |
| `SessionEnd` does not fire (abnormal exit) | no record. This is STEP 0 item 2, and it biases every ratio derived from the file — so the consumer must report *sessions recorded*, never *sessions run* |
| **`SessionStart` baseline missing** (hook did not fire, or its write failed) | `anomalies_delta` is `null`, **not `0`**. Without a baseline the delta is unknown, and an unknown recorded as zero is this item's own thesis inverted |
| **transcript scan hits the time budget** | `direct_nudges`/`dispatch_nudges` are `null` and the record still lands, with a flag naming the reason. A missing record and a bounded-out record must not look alike |

Every record carries a **`v` schema version integer**. Fields will change once STEP 0 resolves whether the
counts are integers or booleans; without a version, old and new records mix silently in an append-only
file and the consumer averages incompatible shapes.

**Named consumer, stated now so this is not written and never read:** a `just` recipe that prints, over the
last N recorded sessions, `direct_nudges`, `dispatch_nudges` and `anomalies_delta` totals — with records
carrying `null` in any field counted and reported **separately**, so unknowns are never folded into zeros.

**The consumer MUST NOT print a ratio, and that is a contract, not a preference.** Recording deliveries
and captures side by side actively invites computing conversion from them, which this design explicitly
cannot support — the denominator problem is why the plausible-opportunity option was rejected. Printing
`captures / nudges` would manufacture exactly the confident wrong number ("0% conversion") that agy named
as this design's Quiet Zero failure mode. Totals only, each labelled with what it does and does not mean.

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
not a trustworthy count, then `direct_nudges` and `dispatch_nudges` become **booleans**, not integers.
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
