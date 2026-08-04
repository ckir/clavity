# Discipline efficacy — session-end reaching recorder

**Status:** design, approved in shape by the owner 2026-08-04. Implements ROADMAP `§0` step 1, as split by
the owner: **measure first, prompt later.**

**Goal.** Answer one question from recorded evidence, without asking any agent what it thinks happened:
**do the AGY-ANOMALIES channels that SHIP TODAY — the `PreCompact` capture reminder and the `PreToolUse`
dispatch relay — reach a driver at all, and how often?**

**Read that scope precisely.** It is deliberately narrower than "is the discipline reaching a driver",
because the direct-driver case is already answered: no direct-driver channel exists (see the problem
statement below), so a recorder could only ever report zero for it, and would be reporting the absence of a
hook rather than a measurement. What v15 left genuinely unknown is whether the two channels that DO ship
arrive at anyone — which is what this records. When a direct trigger lands (`§0` step 1b) it gets its own
event-named field and becomes measurable the same way.

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

Instead: `SessionEnd` reads the session transcript and detects each nudge from the **typed record structure
a hook injection produces** — never from matching its text. No hook on a fail-open path writes anything.
Exactly one write happens, at session end, where nothing is blocked.

**This paragraph originally read "the nudge text carries a stamp, and `SessionEnd` greps the transcript for
it" — free-text matching, which round 1 then killed by measurement.** Three independent mechanisms rule it
out (context re-serialisation, authored content, and the transcript's self-referentiality — all three
detailed below). The detection signal is record structure; the stamp's surviving job is version provenance,
not delivery. **That structure has since been MEASURED (STEP 0 item 5): a typed `attachment` record
carrying `hookEvent` and `hookName`**, which identifies a specific hook by name with no text matching at
all — and therefore confirms, independently, that the stamp is not needed for detection.

**This appeared to reorder ROADMAP `§0` — and round 1 then overturned that.** The stamp looked like a
prerequisite of step 1 while delivery was to be detected by grepping for it. Once detection moved to
record structure, that justification vanished. See "The stamp's rationale was obsoleted" below: the stamp
is **parallel to** the recorder, not blocking it, and its surviving purpose is version provenance — which
is also why `§0`'s separate argument for stamping *before the witness trial* still stands untouched.

### What is recorded

One append-only record per session. **Reaching only — the recorder does not track captures at all.**

| field | type | meaning |
|---|---|---|
| `v` | int | schema version. Required. **`v: 1` is now fixed** — STEP 0 resolved counts-vs-booleans in favour of counts |
| `session_id` | string | correlation |
| `timestamp` | string | ISO-8601, UTC. Sourced from the hook's own clock at write time — NOT from any transcript record, whose timestamps belong to the session being observed, not the observation |
| `precompact_nudges` | int \| `null` | `hook_additional_context` records for the `PreCompact` capture reminder — its words REACHED the model |
| `dispatch_nudges` | int \| `null` | `hook_additional_context` records for the `PreToolUse` dispatch relay — its words REACHED the model |
| `precompact_fired` | int \| `null` | `hook_success` records for the same hook — it EXECUTED |
| `dispatch_fired` | int \| `null` | `hook_success` records for the same hook — it EXECUTED |
| `scan_status` | enum | `ok` \| `bounded_out` \| `transcript_unreadable` \| `transcript_not_found` |

**The `_fired` / `_nudges` pair is the design's most important output, and it exists only because STEP 0
item 5 was measured.** `hook_success` says the hook ran; `hook_additional_context` says its content was
injected into the conversation. **`fired > 0` with `nudges == 0` is the v15 failure captured in a single
record** — every gate green, the hook executing perfectly, and nothing reaching anyone. A recorder with
only one of these numbers could not tell that state from a hook that never ran, which is precisely the
blindness this whole item exists to remove. Counts are deduplicated by record `uuid` (measured: ≤2×
duplication, 87 of 1314).

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
short enough to append in one write.

**That was an ASSERTION, and STEP 0 item 7 has now MEASURED it: the assertion holds.** The concern was that
Win32 `>>` in Git Bash lacks POSIX `O_APPEND` cross-process serialisation, so two sessions ending together
would collide or interleave. Measured across 9 rounds at three payload sizes, plus a round with fully
independent processes: **every append landed intact, every line parsed, no writer was lost.** No
serialisation strategy, per-session file, or advisory lock is required.

Cases the design must handle, each with its decided behaviour:

| case | behaviour |
|---|---|
| `.clavity/` absent entirely | create it; a fresh clone has no `.clavity/` |
| transcript unreadable (Windows write-lock at teardown), or path unresolvable | counts `null`, `scan_status` names which. **Never `0`** — an unknown recorded as a measured zero is this item's own thesis inverted |
| transcript scan hits the time budget | counts `null`, `scan_status: bounded_out`, **and the record still lands**. A missing record and a bounded-out record must not look alike |
| two sessions open in the same repo concurrently | both append; `session_id` disambiguates. With the capture field gone there is no cross-session arithmetic left to corrupt — reaching is per-session by construction |
| `SessionEnd` does not fire (abnormal exit) | no record. STEP 0 item 2. The consumer must therefore report *sessions recorded*, never *sessions run* |
| the write itself fails — `.clavity/` uncreatable, disk full, file locked by a concurrent session | no record, because the hook fails open. **This is indistinguishable from the row above**, and both are indistinguishable from a session where the recorder was never installed. `scan_status` cannot cover it: that field lives *inside* the record that did not get written. The consumer therefore cannot report a denominator at all, and any rate computed against "sessions run" is fabricated |

### ✅ THE SURVIVAL BIAS IS DISSOLVED — measured, and the reasoning that produced it is worth keeping

Rounds 1 and 2 built an elaborate defence here, and **STEP 0 dissolved the thing it defended against.**
The reasoning is preserved because it was not silly — it was correct given what was then known, and the
shape of the error is the lesson.

**What was argued.** Proving a nudge is ABSENT requires reading the whole transcript, and absence is the
hypothesis under test. So the sessions most likely to exhaust the time budget would be exactly the
zero-nudge sessions the item exists to detect: they would record `null` while nudge-bearing sessions
matched early and recorded cleanly. The dataset would systematically drop true zeros and retain non-zeros
— lying in the one direction that matters. A **tail scan** was then proposed as the fix, and round 2
observed that compaction would defeat it, so the two biases would compound.

**What is true.** A full structural scan of a 188 MB transcript costs **1.65 s** against a 10 s budget
(STEP 0 item 4). There is no need to bound the read at all in the normal case, so there is no
early-exit, no truncation, and **no survival bias** — the mechanism the whole argument rested on does not
arise. And compaction does not drop history from the FILE (item 6): it bounds the model's carried context,
while the JSONL retains every record. Both feared biases are artifacts of a bounded read that is not
needed.

**The tail scan is REJECTED** — not because compaction defeats it, but because it is both unnecessary and
badly wrong: a tail-1000 window sees 11 of 453 deliveries, a 97% under-count.

`scan_status: bounded_out` is retained purely as a safety valve for a pathological file far outside
measured sizes, and the consumer still reports those records separately. It is now an exception path
rather than the expected one.

**The lesson, which outlives this spec.** Three review rounds hardened a design against two hazards that
do not exist, and added a boolean fallback for a capability that turns out to be available. Review reasons
about what *could* be true; only measurement says what *is*. **When a design's central difficulty is an
unmeasured platform property, measure it before hardening against it** — the hardening is not free, and
here it would have shipped a 97%-wrong scan strategy as the primary path.

**So STEP 0 item 6 must test the compaction case specifically**, not merely "does a nudge persist" — the
procedure and the consequences of failure are defined in that item.

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

**But that surviving purpose is currently UNREALISED, and saying it survives is not the same as capturing
it.** The recorder detects structure and never reads the stamp, and the schema has no field for a hook
build. So a session driven by a stale v15 hook and one driven by a current hook emit **identical**
records — the provenance benefit is claimed in prose and delivered nowhere. Two honest resolutions, to be
chosen in the plan rather than left implicit: either the recorder reads the stamp *in addition to*
structure and records it in a `hook_version` field, or provenance is explicitly declared out of scope for
the recorder and answered another way. **What must not happen is the spec continuing to claim a benefit
its own schema cannot produce.**

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
from** — **NOT the environment**: `CLAUDE_SESSION_ID` is measured `UNSET` in hooks, so `session_id` must be
read from the payload, which carries it (STEP 0 item 1),
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

**`SessionEnd` is a NEW EVENT KEY, not a new entry under an existing one.** Measured 2026-08-04:
`SessionEnd` appears **zero times** in either driver's `hooks.json` — the registered events are
`PreToolUse`, `PostToolUse`, `SessionStart` and `PreCompact`. Adding a top-level key is a structural change
to both manifests, so the plan must account for three gates that a same-event addition would not have
touched: the whole-`.hooks` deny-list comparison in `check-seed-artifacts-synced.sh`, the payload parity
suite, and the v16 registration suite's *ships no hook file reachable from nowhere* test. It also means
this event has **never fired in this plugin**, so STEP 0 item 2 is not a formality — nothing here has ever
observed it.

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

## STEP 0 — measured 2026-08-04. SEVEN items: FIVE RESOLVED, two instrumented and pending.

**Four of the five resolved items overturned a conclusion this spec had reached by reasoning.** Three
rounds of adversarial review produced a design defended against two hazards that do not exist, and a
fallback for a capability that turns out to be available. That is the case for measuring before reviewing,
and it is recorded here rather than quietly folded.

| item | status | result |
|---|---|---|
| 1 — how does the hook LOCATE the transcript? | **HALF RESOLVED / pending** | ✅ the env fallback is **DEAD** — `CLAUDE_SESSION_ID` measured `UNSET`. ⏳ so everything rests on `SessionEnd`'s payload carrying `transcript_path` (2 of 2 other events do) |
| 2 — does `SessionEnd` fire on every exit path? | **INSTRUMENTED, pending** | same instrument, needs several exit kinds |
| 3 — does injected hook context reach the transcript? | ✅ resolved earlier | yes |
| 4 — can the transcript be read inside the budget? | ✅ **RESOLVED** | yes, with the right strategy — **1.65 s** on 188 MB |
| 5 — what is the injection record's structure? | ✅ **RESOLVED** | a typed `attachment` record carrying `hookEvent` + `hookName` |
| 6 — does a pre-compaction nudge survive? | ✅ **RESOLVED** | yes on disk; **the tail hypothesis is dead** |
| 7 — do concurrent appends serialise? | ✅ **RESOLVED** | yes, at every size tested, including independent processes |

**A cross-reference is not a definition** — if a later round adds an item, it is added HERE.

### Item 5 — RESOLVED. The record structure, and the distinction the spec had not drawn.

Measured on a **closed** transcript (`a72c5696…`, 27 MB, mtime 2026-07-11) so the search could not
contaminate its own evidence. A hook firing produces a typed `attachment` record:

| `.attachment.type` | count in specimen | meaning |
|---|---|---|
| `hook_success` | 1297 | the hook **executed** — carries `exitCode`, `stdout`, `stderr`, `durationMs` |
| `async_hook_response` | 567 | async execution result |
| `hook_cancelled` | 65 | the hook was **cancelled**, carries `timedOut`, `timeoutMs` |
| **`hook_additional_context`** | **39** | the hook's content was **INJECTED into the conversation** |

Every one of them carries **`hookEvent`** and **`hookName`**, so a specific hook is identifiable
structurally, by name, with no text matching whatsoever.

**🔴 THIS IS THE DISTINCTION THIS SPEC HAD COLLAPSED, AND IT IS THE WHOLE POINT OF THE ITEM.**
`hook_success` means *the hook ran*. `hook_additional_context` means *its words reached the model*. A hook
that executes and exits 0 while its content never becomes `hook_additional_context` is **precisely the v15
failure** — every gate green, nothing delivered. The recorder must therefore record **both**, because the
gap between them is the signal, and a design that recorded only "did it run" would have reproduced the
exact blindness this item exists to remove. `hook_cancelled` is a third outcome neither field would
otherwise capture.

**Counting is exact, and the boolean fallback is unnecessary.** In the specimen, structural deliveries for
`PreToolUse:Agent` = **3**, against a ground truth of **3** `Agent`/`Task` tool uses counted independently
from the assistant records. Duplication is bounded and small: 87 uuids appear exactly twice, 1227 once,
never more — **dedup by `uuid`** removes it.

**The self-referentiality hazard is defeated, and this was proven with a control that had to fail.** A
three-line fixture where all three lines contain the marker string but only one is a genuine delivery
record: naive text counting returned **3**; the two-stage structural filter returned **1**. Contaminating
records — a command that searched for the marker, a document that describes it — are `user`/`assistant`
records, not typed attachments, so structural validation rejects them.

### Item 4 — RESOLVED. The budget is affordable, but only one strategy fits.

Measured on a closed **188 MB** transcript, 28,531 records:

| strategy | elapsed | verdict |
|---|---|---|
| naive full `jq` parse of every record | **10.76 s** | **FAILS** the 10 s budget — the spec's fear was correct *for this strategy* |
| `grep` prefilter → `jq`-validate only the candidate lines | **1.65 s** | passes with ~6× headroom |

The two-stage scan is what makes a **full** scan affordable, and a full scan is what item 6 shows is
required. `scan_status: bounded_out` survives as a safety valve for a pathological file, not as the
expected path.

### Item 6 — RESOLVED. Compaction truncates CONTEXT, not the FILE.

The design feared that compaction "summarises and drops earlier turn history", so a session that
dispatched before compacting would end with no trace of it. **Measured: false.** In a specimen containing
**12 compactions** (`isCompactSummary` records at 1053, 2439, 4768, 8905, 10047, 11439, 13512, 14631,
18795, 22034, 23968, 26473), `hook_additional_context` deliveries appear from record **7** through record
**28,485**, straddling every boundary. The JSONL is append-only; compaction bounds what the model carries
forward, not what is on disk.

**But the tail hypothesis is dead.** A tail-1000 window on that file starts at record 27,531 and would see
**11** of ~453 deliveries — a **97% under-count**, and it would report zero for exactly the session whose
only nudge arrived early. Tail scanning is removed from the design; the full two-stage scan replaces it.

### Item 7 — RESOLVED. Appends serialise.

20 concurrent writers, payloads of 300 B / 8 KB / 64 KB, three repeats each: **9 of 9 rounds clean** —
20/20 lines, zero unparseable, 20 distinct writers every time. Repeated with 20 **fully independent**
`bash -c` processes (a truer model of two sessions ending together): clean. Both validator controls fired
first — a malformed line was detected as unparseable, a short file was detected by count — so the passes
are meaningful rather than vacuous. **No serialisation strategy is needed.**

*(The first version of this probe had a single control that "failed" on line count while reporting zero
unparseable lines: its two fragments happened to concatenate into valid JSON, so the corruption check was
never exercised. A control that fails for the wrong reason is not a control.)*

### Item 1 — HALF RESOLVED, and the half that resolved was the fallback. It is DEAD.

Measured 2026-08-04 by a temporary `PostToolUse` probe (since removed):

- **`CLAUDE_SESSION_ID` is `UNSET` in the hook environment.** The spec previously called this "unverified —
  observed only as a default parameter in third-party code, never measured". It is now measured, and it is
  absent. **The "reconstructible from session id plus cwd" fallback is therefore not weak, it is
  unavailable.** (`CLAUDE_PROJECT_DIR` *is* set, but a project dir cannot pick one file out of 112.)
- **The payload carries `transcript_path` directly.** Observed keys: `cwd`, `duration_ms`, `effort`,
  `hook_event_name`, `permission_mode`, `prompt_id`, `session_id`, `tool_input`, `tool_name`,
  `tool_response`, `tool_use_id`, **`transcript_path`**. That is two events out of two observed —
  `PreCompact` carried it too.

**Consequence: the design now rests on a single point of failure.** With no env fallback, everything
depends on `SessionEnd`'s payload carrying `transcript_path`. Two of two observed events carry it, so this
is *likely* — but it is the one unmeasured fact that can still invalidate the recorder outright, and it
must not be assumed. If `SessionEnd` omits it, the hook cannot locate the transcript and the design needs a
different home for the read.

**Operational fact worth recording: hooks ARE hot-reloaded from `settings.local.json` mid-session.**
Verified by registering a probe and firing it without restarting. This matters for the pending measurement
below — the `SessionEnd` probe registered during this session *will* fire at this session's end, so an
empty probe file is genuine evidence that `SessionEnd` did not fire, not an artifact of late registration.

### Items 1 (remaining half) and 2 — INSTRUMENTED, pending a real firing

Neither can be answered by reading source. A local, gitignored `SessionEnd` hook
(`.clavity/scratch/discipline-efficacy/probe12-sessionend.sh`, registered in `.claude/settings.local.json`)
records one line per firing: the verbatim payload, and whether `CLAUDE_SESSION_ID` / `CLAUDE_PROJECT_DIR`
are set. It always exits 0 and writes nothing else. A malformed payload is still recorded, as a string, so
a bad payload is evidence rather than a lost line. **Item 2 needs several exit kinds** — a normal end,
`/clear`, a closed terminal, a killed process — so it resolves over days, not in one run.

**The still-live half of item 1 is not "does the payload have a field" — it is HOW THE HOOK FINDS THE FILE
AT ALL.** Measured: the task-directory id observed at runtime is NOT the transcript filename, and this
project's transcript directory holds **112 `.jsonl` files** with no observed way to pick the current one.
So the "reconstructible from session id plus cwd" fallback needed `CLAUDE_SESSION_ID` — **which is now
measured `UNSET` in the hook environment, so that fallback is gone.** Everything rests on `SessionEnd`'s
payload carrying `transcript_path`. **If it does not, the recorder cannot be built as designed**, and that
is the one remaining result that can still invalidate it.

### 🔴 TEXT-COUNTING IS INVALID — and structural counting is EXACT. Both measured.

These are two different questions and the spec previously conflated them into a single pessimism.

**Text-counting is invalid.** The relay text occurs **470 times** in one session's transcript against ONE
actual dispatch. Three independent causes, any one of which alone breaks a count:

1. **The JSONL re-serialises conversation context**, so one injection appears in many subsequent records.
   The number is "records containing this text", not "times it was delivered".
2. **The same text appears in AUTHORED content** — messages, the hook source, this spec. In this repository
   the nudge text *is* the subject matter, so authored occurrences are guaranteed, not an edge case. No
   choice of stamp string escapes this, because any stamp gets written into the docs that describe it.
3. **The transcript is self-referential** — searching for a string writes it into the corpus being
   searched.

**Structural counting is exact.** Measured against ground truth: 3 detected deliveries, 3 actual
`Agent`/`Task` uses. The three mechanisms above all attack *text*; none of them survives a filter that
requires a record to BE a typed attachment with the right `hookEvent` and `hookName`. The control proved
it: a fixture where all three lines contained the marker returned 3 by text and 1 by structure.

**So the boolean fallback is withdrawn.** `precompact_nudges` and `dispatch_nudges` are integers.

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
