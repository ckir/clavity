# Session note — 2026-07-04 — `Clavity.Ls` ask-Answer fix + `clavity-v2` release

Handoff for a future session. What happened, why, and the current state.

## What was fixed

**Symptom:** `agy_ask` sometimes returned `Answer: null` even though agy clearly produced a reply — the
prose was only visible (and clipped) in `Activity`, forcing a wasted re-ask.

**Root cause (NOT a bus race — a deterministic projection rule):** `BoundedView.ProjectAskReply`
(`src/Clavity.Ls/BoundedView.cs`) sets `Answer` from the trailing **contiguous** assistant (Kind-15) run and
breaks on the first non-assistant step from the tail. When agy *tool-terminates* a turn (writes its verdict,
then does a trailing tool step like a memory write, then yields), the delta ends on a Kind≠15 step, so
`Answer` is null **by design** ("failure not hidden" — see the pinning test
`AskReplyProjectionTests.Delta_ending_on_a_tool_step_...`). The real pain was the *fallback*: `Activity`
summarizes each step to `ActivitySummaryChars = 200`, while `Answer` gets `AskMaxStepChars = 16000` — so a
~4000-char verdict was truncated to 200 in the fallback.

**The `agy_status` vs `agy_ask` "different cascade id" is a red herring:** status returns the *conversation
id*, ask/look return `full.CascadeId` — two ids for the same session, not a threading split.

## The fix (Option B — chosen by the user over agy's Option A)

Keep `Answer = null` on a trailing tool step (preserve the deliberate "failure not hidden" signal), but when
`Answer` is null ONLY because a tool step trailed the prose, give that last assistant run the **Answer budget**
in `Activity` instead of the 200 cap — so the prose survives intact and no re-ask is needed. The rescue is
skipped when the run IS the `Answer` (no double budget).

- Code: `src/Clavity.Ls/BoundedView.cs` `ProjectAskReply` (finds the last contiguous assistant run skipping
  trailing tool steps; `runIsTrailing` gates `Answer`; `rescueRun` gates the per-step budget).
- Tests: `tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs` — 2 new pinning tests; **77/77 green**.
- Doc: `plugins/clavity-dotnet/skills/clavity-ls-driving/SKILL.md` — new "`Answer == null`" bullet under
  "Results you must handle" (null Answer = tool-terminated turn → read Activity's last assistant step, now full).

**Consumer driving lesson (applies whenever driving agy via clavity-ls):** a null `Answer` is NOT "no reply"
and NOT an error — it means the turn ended on a tool step. Read the last Kind-15 step in `Activity` (full,
post-fix); only re-ask if `Activity` has no assistant step or `ActivityTruncated` dropped the tail you need.

**Scope:** dotnet-only. `clavity-classic` is unaffected — it has no `Clavity.Ls` / `AskReply` / `Answer`
projection (it's the psmux/bus lineage; grep of `plugins/clavity-classic` for these symbols is empty).

## Release — `clavity-v2` (PUBLISHED, live)

- Merged `fix-ask-answer-lossy-activity-fallback` → `main` (`--no-ff`, merge `af96b12`, fix `22e63c5`).
- Bumped dotnet **0.1.9 → 0.1.10** in `installer/clavity-dotnet.iss` (`#define AppVersion` — the version the
  release reads, per `build-dotnet.yml`) + `plugins/clavity-dotnet/plugin.json` + its `.claude-plugin/plugin.json`.
  Commit `1c64949`.
- Pushed `main`; tagged **`clavity-v2`** (serial umbrella tag, next after `clavity-v1`) → `umbrella-release.yml`
  run `28697004499` = **success**. GitHub Release **`clavity-v2`** live (not draft): assets
  `clavity-dotnet-setup-0.1.10.exe` (+`.sha256`, contains the fix) and `clavity-classic-setup-0.1.0.exe`
  (+`.sha256`, rebundled unchanged).
- **Release mechanism reminder:** the ONLY release path is pushing a serial `clavity-v<N>` tag; it builds
  dotnet from `main` and rebundles classic from the `clavity-classic` branch tip. Bump the dotnet version in
  `installer/clavity-dotnet.iss` before tagging.

## Current repo state / loose ends

- `main` HEAD = `1c64949` (tagged `clavity-v2`), pushed. Working tree has **pre-existing dirty files left
  untouched** (NOT mine, NOT in the release): `plugins/agy-autotrain/knowledge/agy-observations.md` (modified,
  +4 agy observations), `docs/superpowers/plans/2026-07-01-golden-header-parity.md` (untracked),
  `publish/` (untracked build output — a 75 MB `clavity-ls.exe` + pdbs; `git check-ignore` matched a rule yet
  status still shows it — worth tidying the ignore).
- Merged branch `fix-ask-answer-lossy-activity-fallback` can be deleted (local only; never pushed).
