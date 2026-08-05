# Discipline-reaching capture moves to SessionStart

**Status:** design, 2026-08-05. Supersedes the `SessionEnd` registration in ROADMAP `§0` step 1a
(`docs/superpowers/specs/2026-08-04-discipline-efficacy-design.md`), which stands unchanged in every other
respect — the recorder's purpose, its schema discipline, and the deferred-analysis split are all retained.

**Goal.** Make the reaching recorder actually run on a user's machine. The design was correct; the
registration was not.

---

## The problem, from measurement rather than reasoning

A hook registered in the plugin manifest as `bash "${CLAUDE_PLUGIN_ROOT}/hooks/agy-discipline-reaching.sh"`
**fails at `SessionEnd`**, reporting `Hook cancelled` and writing nothing.

| registration | path form | outcome |
|---|---|---|
| plugin `hooks.json` | `${CLAUDE_PLUGIN_ROOT}` | **cancelled, 3 of 3** |
| plugin `hooks.json` | absolute | worked, 2 of 2 |
| `.claude/settings.local.json` | absolute | worked, 2 of 2 |

One variable changes across those rows: the path form. The same `${CLAUDE_PLUGIN_ROOT}` form works on this
plugin's `PreToolUse`, `PostToolUse`, `SessionStart` and `PreCompact` hooks, all of which fire in
production. `SessionEnd` is the sole failure.

**The three cancellations happened at 20,9s, 1,5s and 0,6s.** That matters because the first diagnosis was
DURATION, and three rounds of optimisation were spent on it — while a *slower* hook (1,24-1,39s), registered
elsewhere, survived. Duration was a confound: one axis was varied three times and the other never. The
optimisation was not wasted (a boot hook should be cheap, and it fixed real backslash/CR/pipe defects) but
it did not address the cause.

**Why an install-time fix is not available.** A committed absolute path is impossible (machine-specific),
and a path written into `hooks.json` by the installer is overwritten by a later plugin update — the owner
confirms both delivery paths are real. That failure would be **silent**, which is the exact class this item
exists to eliminate.

---

## The decision

**Register the capture on `SessionStart`, keeping `${CLAUDE_PLUGIN_ROOT}`.**

**Why this works, stated to match the root cause and not the discarded theory.** `${CLAUDE_PLUGIN_ROOT}`
**resolves** at `SessionStart`; that is the whole mechanism. It is tempting to write "there is no teardown
window, so there is nothing to cancel" — that sentence is the DURATION theory coming back in through the
side door, and this document has already established duration was a confound. Absence of teardown is not
why the fix works. If the reason is misstated here, the next person to touch this re-derives the wrong
model and re-runs the three rounds that were already wasted on it.

A genuine second benefit, independent of the cause: a row written at the beginning survives a session that
crashes or is killed, which a teardown-time write never could.

**MEASURED 2026-08-05 — the `SessionStart` payload carries everything needed**, captured live:

```
cwd, hook_event_name, model, session_id, source, transcript_path
```

`transcript_path` was the load-bearing unknown: the prior spec claimed it "Confirmed present on
`PreCompact` … and on `SessionStart`", but only the `PreCompact` half had been observed. The
`SessionStart` half was an assumption carried in the same sentence as a measured fact. It is now measured.

**Why this option only exists now.** `SessionStart` was rejected in the original design because v1 computed
an `anomalies_delta` needing a baseline at start and a write at end. **v2 is capture-only** — it names the
session and its transcript and stops. That objection died with v1, and the rejection outlived the reason
for it.

### Fire on all four `source` values — owner ruling

`startup`, `resume`, `clear`, `compact`. Capturing only `startup` would miss a session resumed after a
crash, which is exactly the population `SessionEnd` already fails to see. **This makes deduplication
mandatory rather than optional** (below).

---

## Schema `v:3`

| field | source | notes |
|---|---|---|
| `v` | constant `3` | |
| `session_id` | payload | correlation, and the dedup key |
| `timestamp` | hook clock | ISO-8601 UTC |
| `source` | payload | `startup` \| `resume` \| `clear` \| `compact`. Replaces `reason` |
| `model` | payload | recorded, deliberately NOT displayed — see below |
| `transcript_path` | payload | what the report later scans |
| `scan_status` | derived | `deferred`, or `transcript_not_found` when the payload names none |

**Three versions remain readable, and the `v` field is why it exists.** `v:1` (counts computed at
`SessionEnd`) SHIPPED in v17, so real machines may hold those rows. `v:2` (SessionEnd capture) never
shipped — only this development machine has any. The report reads each by its own version rather than
guessing, exactly as the null discipline demands.

**`reason` is lost.** `source` says how a session BEGAN, not how it ended; it is related data, not the same
data. STEP 0 item 2 ("does `SessionEnd` fire on every exit path?") becomes moot — nothing depends on that
event any more.

**`model` is recorded but not reported, and that asymmetry is deliberate.** There is no question it answers
today, and this report does not print numbers nobody can interpret. But capture is the one irreversible
half: a field not written at session N is unrecoverable at session N+1, while a field written and ignored
costs a few bytes. So it is recorded against a future efficacy question — plausibly "does reaching differ
by model?" — and the report displays nothing until such a question is actually posed. If that question is
never posed, the field stays unread, which is the cheap outcome.

**The report's version dispatch must be extended — this is REQUIRED WORK, not an implication.**
`scripts/discipline-reaching-report.ps1:132` reads
`elseif ($v -ne $SCHEMA_ANALYSED) { $unsupported++; continue }`. A `v:3` row therefore takes the
`unsupported` branch and is dropped from every total, reported only as a skipped-row count. Shipping the
new schema without this change would make the recorder write rows that the only consumer discards —
exactly the silent zero this whole item exists to remove, reintroduced at the other end of the pipe.

---

## Deduplication — new code, not existing behaviour

The report must collapse rows by `session_id`: **keep the earliest**, and report the `source` distribution
across all rows separately as context.

**Dedup runs BEFORE the `-Last` slice, and getting that order wrong silently redefines the parameter.**
Today `discipline-reaching-report.ps1:120` slices raw LINES
(`if ($Last -gt 0 -and $raw.Count -gt $Last) { $raw = $raw[-$Last..-1] }`) and its help text at `:26`
promises "the last N recorded SESSIONS". Those coincided only because one session meant one row. Once a
compaction-heavy session emits many rows, slicing first makes `-Last 20` return however many distinct
sessions happen to fall in the last 20 lines — possibly three. The number stays plausible while its
meaning changes, which is the failure mode this report is built to refuse. Parse and collapse first, then
take the last N sessions.

**This is new.** `session_id` appears NOWHERE in `scripts/discipline-reaching-report.ps1` today. It was
claimed during review that the report "already deduplicates by session_id"; it does not, and that claim was
used to dismiss the multi-fire cost as trivial. Verified by measurement before folding.

🔴 **An assumption this rests on, stated so it is not laundered into a fact: whether repeated `SessionStart`
fires within one session share a `session_id` is UNMEASURED.** Only `source=startup` has been observed so
far. If `clear`/`compact` mint a NEW id, dedup is a harmless no-op; if they reuse it, dedup is load-bearing.
Implementing it is safe under both, so this does not block — but the first `clear` or `compact` row that
lands should be checked against this, and the answer written down here.

---

## Registration — state the exact form, because "all four" has two encodings

The manifest offers two ways to say "every source", and they are **not proven equivalent**:
`clavity-{dotnet,classic}/plugin/hooks/hooks.json:68` registers `SessionEnd` with **no matcher at all**,
while `:51` registers `startup|resume|clear|compact` **explicitly**. Whether an omitted matcher means "all"
on `SessionStart` is unmeasured, and an unmeasured equivalence is exactly what produced this spec.

**Write the explicit form.** Add the hook to the existing `startup|resume|clear|compact` block at `:51`,
alongside `agy-anomaly-reminder.sh` and `agy-anomaly-model-notice.sh`. Those two hooks are observed firing
in production under that matcher, so the block is proven, and reusing it means the registration under test
is one already known to work rather than a new one.

## What this does NOT change

The hook body keeps its **structure**: no subprocesses (bash regex instead of jq, `printf %()T` instead of
`date`, in-shell `.git` walk instead of `git rev-parse`), plus the three fixes worth keeping — byte-exact
Windows paths, CR stripping, and pipe-safe stdin. Boot is not teardown and there is no cancellation
pressure, but a hook that runs at every session start should still be cheap.

**Its FIELDS do change, and "the body stays as rewritten" must not be read as forbidding that.**
`agy-discipline-reaching.sh:43` extracts `"reason"`; schema `v:3` needs `"source"`, and the literal `"v":2`
in the `printf` at `:79` becomes `"v":3`. The invariant being preserved is the process count and the
escaping strategy — not the field list.

The deferred-analysis split stays. The report still refuses to fold a `null` into a zero, refuses to print
a ratio, and reports sessions RECORDED rather than RUN.

---

## What the move costs — three consequences of writing at boot instead of exit

**More writers, and now concurrent ones.** `SessionEnd` produced one appender per session. Two Claude
sessions started in the same repo at once now append simultaneously. A single short `>>` line is expected
to be atomic, but that is an assumption inherited rather than measured, and it is recorded here so a
corrupt interleaved row is diagnosed rather than puzzled over.

**More rows, and no retention story.** Rows per session goes from 1 to `1 + clears + compactions`. The file
is append-only, never rotated, and the report reads it whole. Nothing needs building now — dedup keeps the
REPORTED counts honest regardless of row count — but the growth rate is no longer one line per session, and
whoever first sees this file at a few thousand lines should find that stated here rather than treat it as a
defect.

**A missing row still cannot be distinguished from a session that never happened.** This move fixes the
KNOWN instance of the silent zero; it does not make the class detectable. That gap is deliberate and left
open: the honest detector is the owner-run outside-witness protocol in the prior spec, not another
self-report from the same machinery that would be failing.

## Before this item may be called complete — one measurement, not an inference

Every claim that `${CLAUDE_PLUGIN_ROOT}` resolves at `SessionStart` currently rests on OTHER hooks working
there (`agy-anomaly-reminder.sh`, `agy-anomaly-model-notice.sh`, `agy-liveness-check.sh`). That is strong
inductive evidence and it is not a measurement of THIS hook.

**Required:** after the manifest change ships into the installed plugin, start a session and confirm a real
row lands. Round-1 rationale in the prior spec was wrong for three rounds precisely because a plausible
inference went unmeasured; the same shape of reasoning appears above, so it gets the same treatment.

## Testing

- Retarget `scripts/tests/agy-discipline-reaching.Tests.ps1` at the `SessionStart` payload shape; keep every
  existing regression (Windows path byte-exactness, CR stripping, pipe-safe stdin, fail-open, `.no-agy`,
  append, cross-driver parity, no non-zero exit).
- Add: the manifest registers `SessionEnd` **nowhere** and `SessionStart` for this hook — the defect being
  fixed is a registration defect, so registration needs an assertion.
- Add: the report deduplicates by `session_id` and still totals correctly across `v:1`/`v:2`/`v:3`.
- Add: a `v:3` row is COUNTED, not routed to `unsupported`. Assert the total, not merely the absence of a
  skip line — the current code path fails by silently incrementing a counter, which a loose assertion passes.
- Add: `-Last N` returns N distinct SESSIONS when the file holds a session with many rows. Construct the
  fixture so slicing-before-dedup gives a different answer than dedup-before-slicing; a fixture where both
  orders agree tests nothing.
- **Fixtures must use real Windows paths with backslashes.** Forward-slash fixtures are what hid two
  shipped defects; a green suite over unrealistic fixtures is a test lying in the worst direction.

---

## The one thing that cannot be proven from inside this repo

Whether `${CLAUDE_PLUGIN_ROOT}` fails at `SessionEnd` on OTHER machines, or only this one. Every
measurement here is single-machine. The move to `SessionStart` is robust either way — it does not depend on
the cause — but the underlying platform behaviour is stated as observed, not as universal.

Corroboration, and its limit: ECC avoids `${CLAUDE_PLUGIN_ROOT}` in **0 of 28** hook commands across every
event, resolving the plugin root itself in-line. That shows a major plugin distrusts the variable
generally. It was initially cited as evidence of a `SessionEnd`-specific defect; re-measurement showed it is
not that, and the claim was withdrawn. It corroborates the pattern, not the diagnosis.
