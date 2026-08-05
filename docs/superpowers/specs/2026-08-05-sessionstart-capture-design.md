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

This is not a workaround for the cancellation; it removes the failure class. There is no teardown window,
nothing to cancel, and sessions that crash or are killed are captured because the row is written at the
beginning.

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
| `model` | payload | new signal, free from this payload |
| `transcript_path` | payload | what the report later scans |
| `scan_status` | derived | `deferred`, or `transcript_not_found` when the payload names none |

**Three versions remain readable, and the `v` field is why it exists.** `v:1` (counts computed at
`SessionEnd`) SHIPPED in v17, so real machines may hold those rows. `v:2` (SessionEnd capture) never
shipped — only this development machine has any. The report reads each by its own version rather than
guessing, exactly as the null discipline demands.

**`reason` is lost.** `source` says how a session BEGAN, not how it ended; it is related data, not the same
data. STEP 0 item 2 ("does `SessionEnd` fire on every exit path?") becomes moot — nothing depends on that
event any more.

---

## Deduplication — new code, not existing behaviour

The report must collapse rows by `session_id`: **keep the earliest**, and report the `source` distribution
across all rows separately as context.

**This is new.** `session_id` appears NOWHERE in `scripts/discipline-reaching-report.ps1` today. It was
claimed during review that the report "already deduplicates by session_id"; it does not, and that claim was
used to dismiss the multi-fire cost as trivial. Verified by measurement before folding.

🔴 **An assumption this rests on, stated so it is not laundered into a fact: whether repeated `SessionStart`
fires within one session share a `session_id` is UNMEASURED.** Only `source=startup` has been observed so
far. If `clear`/`compact` mint a NEW id, dedup is a harmless no-op; if they reuse it, dedup is load-bearing.
Implementing it is safe under both, so this does not block — but the first `clear` or `compact` row that
lands should be checked against this, and the answer written down here.

---

## What this does NOT change

The hook body stays as rewritten: **no subprocesses** (bash regex instead of jq, `printf %()T` instead of
`date`, in-shell `.git` walk instead of `git rev-parse`). Boot is not teardown and there is no cancellation
pressure, but a hook that runs at every session start should still be cheap, and the rewrite also carries
three fixes worth keeping — byte-exact Windows paths, CR stripping, and pipe-safe stdin.

The deferred-analysis split stays. The report still refuses to fold a `null` into a zero, refuses to print
a ratio, and reports sessions RECORDED rather than RUN.

---

## Testing

- Retarget `scripts/tests/agy-discipline-reaching.Tests.ps1` at the `SessionStart` payload shape; keep every
  existing regression (Windows path byte-exactness, CR stripping, pipe-safe stdin, fail-open, `.no-agy`,
  append, cross-driver parity, no non-zero exit).
- Add: the manifest registers `SessionEnd` **nowhere** and `SessionStart` for this hook — the defect being
  fixed is a registration defect, so registration needs an assertion.
- Add: the report deduplicates by `session_id` and still totals correctly across `v:1`/`v:2`/`v:3`.
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
