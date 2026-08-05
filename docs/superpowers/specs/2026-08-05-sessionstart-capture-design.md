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

**MEASURED 2026-08-05 on TWO of the four sources — `startup` and `compact`** (`resume` and `clear` remain
unobserved). Both carry every field this design needs:

```
cwd, hook_event_name, model, session_id, source, transcript_path
```

`transcript_path` was the load-bearing unknown: the prior spec claimed it "Confirmed present on
`PreCompact` … and on `SessionStart`", but only the `PreCompact` half had been observed. The
`SessionStart` half was an assumption carried in the same sentence as a measured fact. It is now measured —
**for `startup` and `compact`.** Extending that to `resume` and `clear` is an extrapolation, and it is
recorded as one rather than quietly promoted. The design is safe under a failed extrapolation: a payload
missing `transcript_path` produces a row with `scan_status: transcript_not_found`, which is a named,
visible degradation and not a zero. The first `resume` and `clear` rows to land should be checked against
this and the answer written here.

**Why this option only exists now.** `SessionStart` was rejected in the original design because v1 computed
an `anomalies_delta` needing a baseline at start and a write at end. **v2 is capture-only** — it names the
session and its transcript and stops. That objection died with v1, and the rejection outlived the reason
for it.

### Fire on all four `source` values — owner ruling

`startup`, `resume`, `clear`, `compact`. **This makes deduplication mandatory rather than optional**
(below).

**The original justification for `resume` was wrong, and correcting it does not change the ruling.** This
spec previously argued that capturing only `startup` "would miss a session resumed after a crash". It would
not: a session that crashed had already fired `SessionStart(source=startup)` at birth and had already
written its row. Resuming it writes a SECOND row which dedup then discards. That reasoning confused how a
session ENDED with how it BEGAN — the same conflation that made `reason` look interchangeable with
`source`.

What firing on all four actually buys, stated accurately:
- `resume` uniquely captures only sessions that began BEFORE the hook was installed, or whose `startup`
  write failed. A small population, but a real one, and it is the population that is invisible by
  construction to every other event.
- `clear` and `compact` are not about capturing new SESSIONS at all. They record that a long session went
  through those transitions, which is the `source` distribution the report prints as context.

---

## Schema `v:3`

| field | source | notes |
|---|---|---|
| `v` | constant `3` | |
| `session_id` | payload | correlation, and the dedup key |
| `timestamp` | hook clock | ISO-8601 UTC |
| `source` | payload | `startup` \| `resume` \| `clear` \| `compact`. Replaces `reason` |
| `model` | payload | a plain STRING (measured); recorded, deliberately NOT displayed — see below |
| `transcript_path` | payload | what the report later scans |
| `scan_status` | derived | `deferred`, or `transcript_not_found` when the payload names none |

**Three versions remain readable, and the `v` field is why it exists.** `v:1` (counts computed at
`SessionEnd`) SHIPPED in v17, so real machines may hold those rows. `v:2` (SessionEnd capture) never
shipped — only this development machine has any. The report reads each by its own version rather than
guessing, exactly as the null discipline demands.

**`reason` is lost.** `source` says how a session BEGAN, not how it ended; it is related data, not the same
data. STEP 0 item 2 ("does `SessionEnd` fire on every exit path?") becomes moot — nothing depends on that
event any more.

**`model` is a plain string and its FORM varies — measured, both fires.** The two captured payloads carry
`"model":"claude-opus-5"` and `"model":"claude-opus-5[1m]"`, the latter marking the 1M-context variant. The
existing `[^"]*` extractor handles both, and an absent or non-string value would simply leave the field
empty — which the hook already treats as "not named" rather than as a zero. No special handling is needed,
and none should be added on speculation about shapes that have not been observed.

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

**That distribution counts HOOK INVOCATIONS, and must be labelled as such.** `startup: 10, compact: 20` is
thirty firings across ten sessions, not thirty sessions — and printed under a heading that does not say so,
it reads as the latter. Worse, `compact: 20` sits next to the existing `compactions:` figure the report
derives from `isCompactSummary` in the transcript (`discipline-reaching-report.ps1:83`). Those two numbers
count different things and WILL diverge — a compaction before the plugin was installed appears in one and
not the other — so a reader who assumes they should agree will treat a correct report as broken. Label the
breakdown as invocations, keep it out of the session totals, and say plainly that it is not the same
measurement as `compactions`.

**Legacy rows have no `source` at all.** `v:1` and `v:2` carry `reason` (an EXIT reason: `prompt_input_exit`
and the like). Those values must never be bucketed into the `source` distribution — they answer a different
question and would silently contaminate it. Count legacy rows in their own bucket.

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

✅ **MEASURED 2026-08-05 — a `compact` fire REUSES the session's `session_id`, so dedup is load-bearing,
not a no-op.** Settled from a captured payload
(`.clavity/scratch/discipline-efficacy/sessionstart-payload.txt:4`): a `source=compact` fire carried
`session_id c359e435-163a-416d-8e01-00a105d030d7`, the id of the session it compacted, corroborated
independently by that session's own `PreCompact` payload.

⚠️ **A NARROWER claim than this document first made, and the correction is worth keeping visible.** An
earlier draft said `transcript_path` was "byte-identical across the two fires". It is not what the evidence
shows: the two captured payloads are **different sessions** (`b289efb2` at `startup`, `c359e435` at
`compact`), so nothing there compares one session's `startup` row against its own `compact` row. That
comparison has NOT been made.

What holds instead, and why it is still enough: in both observations the transcript is
`<session_id>.jsonl`. If the id is stable across fires — which IS measured — then a path derived from the
id is stable too. That is a structural inference from a naming convention observed twice, not a
measurement, and it is labelled as such here because mistaking the two is the specific error that has cost
this item the most.

If the convention ever changes, "keep the earliest" starts naming a stale transcript. The cheap insurance:
when collapsing rows, if their `transcript_path` values differ, prefer the LATEST and record that they
disagreed. Nothing observed says they will, and the report should not be silent if they do.

`clear` remains unobserved. It is the one source that could plausibly mint a new id, and if it does the
effect is benign (it simply presents as a separate session).

**Legacy rows collapse trivially.** `v:1` was written at `SessionEnd`, one row per session, so dedup over
`v:1` is an identity mapping and every historical total survives untouched. Their single `timestamp`
becomes both `first_seen` and `last_seen`.

**The session live during the upgrade itself records nothing** — it booted under the v17 manifest so no
`SessionStart` capture fired, and by the time it exits the `SessionEnd` registration is gone. That is
benign: it matches exactly what v17 already did for every session, which was nothing.

### Which row wins, and which row orders

Two different questions, and answering both with "the earliest" is wrong:

- **Content comes from the EARLIEST row** — it names how the session ORIGINATED (`source=startup` rather
  than the `compact` that followed), and the transcript path is the same either way (measured above).
- **The collapsed record keeps BOTH timestamps** — `first_seen` and `last_seen`. Carrying one and
  silently using it for both purposes is how the two questions got conflated in the first place, and any
  output that prints a time must say which of the two it is printing.
- **Recency ordering comes from the LATEST row.** `-Last N` must rank a session by its most recent
  activity, not its birth. Otherwise a long session started at 08:00 that is still alive at 18:00 sorts
  as older than twenty short sessions that began and ended at midday, and `-Last 20` drops the single
  most active session on the machine. That inverts exactly the question the parameter exists to answer.

**And `Expand-CaptureRow` runs LAST — after dedup and after the slice.** It is the expensive step: it
`Select-String`s and `jq`s a whole transcript (`discipline-reaching-report.ps1:88-91`), and it is invoked
per-row inside the parse loop today (`:131`). Left in that position, a session with fifteen `compact` rows
would read the same multi-hundred-megabyte transcript fifteen times to produce one answer. Order the
pipeline: parse → collapse by `session_id` → take the last N → expand. That bounds transcript reads to N.

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

**And DELETE the whole `SessionEnd` block** (`:66-72`), in both drivers — not just its inner hook entry.
This hook is its only occupant, so moving it leaves an empty event registration behind: a listener that
resolves nothing, does nothing, and still reads to a future maintainer as though teardown capture exists.
Given that a phantom `SessionEnd` registration is precisely what cost this item three review rounds, the
empty shell is worse than clutter.

## A shipped defect this spec must fix, because it touches the same lines

**`.no-agy` does not suppress this hook when Claude is launched from a subdirectory.**
`agy-discipline-reaching.sh:51` tests `$cwd_path/.no-agy`, but the repo-root walk that decides WHERE the
row gets written does not happen until `:58-66`. So a user with `.no-agy` at their repo root who starts
Claude in `repo/src` is not suppressed — and the hook then writes into `repo/.clavity/`, the very tree
whose owner opted out.

**MEASURED 2026-08-05, with a control.** Payload `cwd=repo/src` and `repo/.no-agy` present: a row was
written. Same payload with `cwd=repo`: nothing written. The control behaving correctly is what makes the
first result a finding rather than a broken probe.

**Fix:** move the workspace check to AFTER the root walk and test `$root/.no-agy` (keeping the existing
`$cwd_path` and `$HOME/.claude` tests — a `.no-agy` in a subdirectory should still suppress that
subdirectory). Add a test whose `cwd` is a subdirectory of a repo carrying a root `.no-agy`; the existing
case at `scripts/tests/agy-discipline-reaching.Tests.ps1` only exercises `cwd` = repo root, which is why
this survived.

**And a second, related one: the hook writes into NON-REPOSITORY directories.** The root walk at `:58-66`
falls back to `root=$cwd_path` when it finds no `.git`, and `:73-74` then creates `$root/.clavity/`
regardless. **MEASURED:** a payload whose `cwd` is an ordinary folder with no git ancestor produced
`.clavity/discipline-reaching.jsonl` in that folder. Open Claude in `Downloads` and it leaves a directory
behind.

**Fix:** if the walk finds no `.git`, exit 0 without writing. A session outside any repository has no
project to attribute reaching to, so the row would be unattributable anyway — this discards nothing worth
having. Note the ordering interaction: this check and the `.no-agy` check both depend on `$root`, so both
belong after the walk.

Writing `.clavity/` into a git repo the user is actually working in is NOT part of this defect — that is
how every other piece of clavity's per-repo state already behaves, and a repo is a project the row can be
attributed to. The line being drawn is between "a repository" and "any directory at all".

**The `.no-agy` hole exists in eight sibling hooks** — every plugin hook tests `$cwd/.no-agy`. For the reminder
hooks the cost is an unwanted message rather than a write, so it is a different severity and a different
change; it is logged in `.clavity/local-anomalies.md` and is NOT in this spec's scope. Fixing it here for
the hook this spec already rewrites is not scope creep; leaving a consent bypass in the one hook that
WRITES would be.

## What this does NOT change

The hook body keeps its **structure**: no subprocesses (bash regex instead of jq, `printf %()T` instead of
`date`, in-shell `.git` walk instead of `git rev-parse`), plus the three fixes worth keeping — byte-exact
Windows paths, CR stripping, and pipe-safe stdin. Boot is not teardown and there is no cancellation
pressure, but a hook that runs at every session start should still be cheap.

**Its FIELDS do change, and "the body stays as rewritten" must not be read as forbidding that.**
`agy-discipline-reaching.sh:43` extracts `"reason"`; schema `v:3` needs `"source"`. A `"model"` extraction
joins the same regex block, `model` joins the `printf` template, and the literal `"v":2` at `:79` becomes
`"v":3`. The invariant being preserved is the process count and the escaping strategy — not the field list.

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

**🔴 The report can now scan a session that is still running — and this is the one genuinely new failure
the move introduces.** Under `SessionEnd` a row existed only after its session had finished, so every
transcript the report scanned was complete. Under `SessionStart` the row lands at turn zero, which means
running the report while another session is live scans a transcript that is still being written. That
session yields `fired: 0, reached: 0` and is filed under `scanned cleanly` — indistinguishable from a
finished session where the discipline genuinely never reached. It is a plausible number meaning something
other than what it says, which is the exact defect class this item exists to remove, arriving through the
door the fix opened.

**The first rule written here for this was not implementable, and replacing it is the point.** Round 2
said "never count the reporting session itself, and treat any transcript modified during the scan as
in-flight". Both halves fail:

- The report is a PowerShell script. Claude Code does not hand it the calling session's `session_id`, so
  "the reporting session" is not a thing it can identify without process-tree introspection.
- "Modified during the scan" tests a window of milliseconds. A live session waiting on a prompt or an API
  response is not writing during that window, so the check would miss almost every live session — while
  reading as though it had covered them.

**The rule that works, and needs neither:** a session whose transcript was modified within a recency
threshold (15 minutes is ample) is **`provisional`** — counted in its own bucket, never in `scanned
cleanly`. It needs only the file's mtime, and it subsumes the reporting session automatically, because the
transcript of the session running the report was appended to moments ago.

And the framing correction underneath: scanning a live transcript is not WRONG, it is **incomplete**. Every
dispatch it counts really happened; more may follow. `provisional` says exactly that, where "exclude" would
have thrown away a true partial count.

**Exactly how that lands in the output, because "counted separately but not discarded" is two instructions
and an implementer must not have to pick one.** A provisional session:

- is **NOT** in `scanned cleanly`, and its counts are **NOT** in the `DISPATCH RELAY` sums — those totals
  mean completed sessions, and mixing a partial count in would make them mean something softer without
  saying so;
- **IS** printed, with its counts, in its own `PROVISIONAL (still running - counts may grow)` section;
- is counted in `Sessions recorded`, which is a count of rows on file and has always been exactly that.

So nothing is thrown away and nothing is blended. This is the same shape as the existing `NOT SCANNED`
section, and for the same reason: a number whose meaning differs gets its own heading rather than a
footnote.

**A session started and abandoned in seconds now records too.** A mis-launch that the user immediately
kills writes a `startup` row, and its transcript exists, so it scans cleanly at zero. `SessionEnd` did not
reliably see these — a killed session has no teardown. This inflates the recorded-session count with true
zeroes. It does not corrupt any total the report prints, because the report refuses to compute a rate over
them, and that refusal is now doing load-bearing work rather than merely being principled.

**A missing row still cannot be distinguished from a session that never happened.** This move fixes the
KNOWN instance of the silent zero; it does not make the class detectable. That gap is deliberate and left
open: the honest detector is the owner-run outside-witness protocol in the prior spec, not another
self-report from the same machinery that would be failing.

## What this assumes about the HOST, and how each assumption would announce itself

Claude Code is external and can change without notice. Three assumptions, ranked by how loudly each fails:

| assumption | if it changes | how we find out |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` resolves at `SessionStart` | no rows at all | **SILENT** — the failure this item exists to fix, now at a different event |
| `session_id`/`transcript_path`/`source` stay top-level string keys | regex misses; empty fields | LOUD — every row lands as `transcript_not_found`, a visible bucket |
| `startup\|resume\|clear\|compact` is the exhaustive source list | a new source fires nothing | quiet, but FAIL-SAFE — a missed `clear`-like transition costs context, not a session |

Only the first is silent, and it is the one already known to bite. That asymmetry is worth stating plainly:
the schema's null discipline makes shape-drift visible, but nothing inside this design can make
non-registration visible. The detector for that remains the owner-run outside-witness protocol.

## Before this item may be called complete — one measurement, not an inference

Every claim that `${CLAUDE_PLUGIN_ROOT}` resolves at `SessionStart` currently rests on OTHER hooks working
there (`agy-anomaly-reminder.sh`, `agy-anomaly-model-notice.sh`, `agy-liveness-check.sh`). That is strong
inductive evidence and it is not a measurement of THIS hook.

**Required:** after the manifest change ships into the installed plugin, start a session and confirm a real
row lands. Round-1 rationale in the prior spec was wrong for three rounds precisely because a plausible
inference went unmeasured; the same shape of reasoning appears above, so it gets the same treatment.

## Testing

- Retarget `scripts/tests/agy-discipline-reaching.Tests.ps1` (**12 `It` blocks**) at the `SessionStart`
  payload shape; keep every existing regression (Windows path byte-exactness, CR stripping, pipe-safe
  stdin, fail-open, `.no-agy`, append, cross-driver parity, no non-zero exit). The change is concentrated
  in one place: the `Payload` helper at `:67` hardcodes
  `hook_event_name = 'SessionEnd'; reason = $Reason` and must emit `SessionStart` / `source`, with the
  `v:3` assertion following. Note that helper's default `($Cwd -replace '\\','/')` — it manufactures
  forward-slash fixtures, which is the shape that hid two shipped defects, so the dedicated real-Windows-
  path case must keep bypassing it.
- Add: the manifest registers `SessionEnd` **nowhere** and `SessionStart` for this hook — the defect being
  fixed is a registration defect, so registration needs an assertion.
- Add: the report deduplicates by `session_id` and still totals correctly across `v:1`/`v:2`/`v:3`.
- Add: a `v:3` row is COUNTED, not routed to `unsupported`. Assert the total, not merely the absence of a
  skip line — the current code path fails by silently incrementing a counter, which a loose assertion passes.
- Add: `-Last N` returns N distinct SESSIONS when the file holds a session with many rows. Construct the
  fixture so slicing-before-dedup gives a different answer than dedup-before-slicing; a fixture where both
  orders agree tests nothing.
- Add: collapsing a `startup` row at T1 with a `compact` row at T2 yields ONE record whose `source` is
  `startup` and whose recency key is T2. Assert both halves — a test that only checks the count passes
  even when content and ordering have been taken from the same row.
- Add: a session whose transcript mtime is inside the recency threshold reports as `provisional` and is
  excluded from `scanned cleanly`. Drive it by setting the fixture's mtime, not by racing a live writer.
- Add: a payload whose `cwd` has no `.git` ancestor writes NOTHING and creates no directory.
- Add: `.no-agy` at a repo root suppresses a payload whose `cwd` is a SUBDIRECTORY of that repo. This is
  the case that lets the shipped bypass through, so assert that NO file is created — not merely that the
  exit code is 0, which the bypass also satisfies.
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
