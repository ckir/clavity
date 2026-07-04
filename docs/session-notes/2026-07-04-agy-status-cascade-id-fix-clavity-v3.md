# Session note — 2026-07-04 — `agy_status` cascade-id fix + `clavity-v3` release

Handoff for a future session. What happened, why, and the current state. (Second note dated today; the
first is `2026-07-04-ls-ask-answer-fix-and-clavity-v2.md`.)

## What was fixed

**Symptom (consumer-reported):** `agy_status` and `agy_ask` reported **different id values for the same live
session**, so a consumer correlating a pre-fire `agy_status` with the `agy_ask` it then sent always saw a
mismatch — easily mistaken for a lost/misrouted reply.

**Root cause — a mislabeled field, NOT a threading/routing split.** The `AgyStatus` record's id field is named
`CascadeId` (`src/Clavity.Ls/AskReply.cs`), and the `agy_status` tool description documents it as a *cascade id*
— but `AgyView.StatusAsync` populated it with the **conversation id**:

```
var traj = await client.GetCascadeTrajectoryAsync(conversationId, ...);   // traj.CascadeId is right here
return new AgyStatus(conversationId, traj.Steps.Count, state, lastKind);  // ← wrong: conversation id in a CascadeId field
```

Meanwhile `AskAsync` fills its `CascadeId` from `full.CascadeId` (the real cascade id off the same kind of
trajectory). So the two tools reported two different real identifiers under the same field name.

## The fix (Option A — chosen by the user over agy's Option C)

`StatusAsync` now returns `new AgyStatus(traj.CascadeId, ...)` on both returns (`src/Clavity.Ls/AgyView.cs`).
The field's value now matches its name, matches the documented "cascade id" contract, and **`status.CascadeId`
string-equals `ask.CascadeId`** for the same session → the two tools are correlatable.

- **AGY-FIRST consult ran** (neutral framing + pasted code). agy recommended **Option C** — add a second
  `ConversationId` field to preserve the old value — arguing a consumer might rely on `status.CascadeId` as a
  session-routing key. **Verified false for this system** and the user chose **Option A** (minimal): the MCP
  tools (`agy_status`/`agy_ask`/`agy_look`) take **no id argument** (they auto-resolve the active conversation),
  so nothing round-trips the id, and **no test pins `AgyStatus.CascadeId == conversationId`**. So A can't
  silently break routing, and it aligns code with the already-documented contract. C was YAGNI (add a
  `ConversationId` field only if/when multi-session conversation-targeting is actually built).
- **Correction to agy (not rubber-stamped):** its "C is a noisy safe break" claim was off — C changes
  `CascadeId`'s *value* exactly like A does; it only preserves the old value under a new name, which buys
  nothing here since nothing consumes it.

**Testability note:** `StatusAsync` hits the network (`ConnectAndResolveAsync` + gRPC), so it has no pure unit
test — the projection unit tests cover `BoundedView`/`AskReply`, not `StatusAsync`. This fix is a value
correction verified by `dotnet build` (8/0/0) + `Clavity.Ls.Tests` (77/77) + inspection. A regression pin would
need the integration/live harness (`AgyViewIntegrationTests` / `AgyStatusProbeLiveTests`), not a unit test.

## Driving-SKILL update (version-agnostic)

`plugins/clavity-dotnet/skills/clavity-ls-driving/SKILL.md`:
- `agy_status` bullet now documents it returns `{ CascadeId, TotalSteps, State, LastStepKind }` and that its
  `CascadeId` matches `agy_ask`'s for the same session (so status↔ask correlate).
- `possible_modal` bullet sharpened: a long/large turn can outrun the idle-wait while still progressing — re-check
  `agy_status` and compare `TotalSteps` before calling it a hang; a reply produced *after* the timeout is **not**
  auto-redelivered (retrieve with a minimal follow-up `agy_ask`, correlate by content or `CascadeId`); keep single
  asks small/pure-text. (Written **version-agnostic** — no `v0.x` stamps in the skill body, per house style.)

## Release — `clavity-v3` (published via the serial umbrella tag)

- Merged `fix-agy-status-cascade-id` → `main` (`--no-ff`, merge `759131e`, fix `2038621`).
- Bumped dotnet **0.1.10 → 0.1.11** in `installer/clavity-dotnet.iss` (`#define AppVersion` — the version the
  release reads) + `plugins/clavity-dotnet/plugin.json` + its `.claude-plugin/plugin.json`. Commit `bd53158`.
- SKILL: commit `6c4cef9` (initial) then `858746b` (made version-agnostic — dropped the version stamps).
- Pushed `main` (`ae978bf..858746b`); tagged **`clavity-v3`** (serial, after `clavity-v2`) → `umbrella-release.yml`
  run **`28708988067`** = **SUCCESS**. GitHub Release **`clavity-v3`** is **LIVE** (not draft), confirmed with 4
  assets: `clavity-dotnet-setup-0.1.11.exe` (+`.sha256`, contains the fix) and `clavity-classic-setup-0.1.0.exe`
  (+`.sha256`, rebundled unchanged).
- **Release mechanism reminder (unchanged):** the ONLY release path is pushing a serial `clavity-v<N>` tag; it
  builds dotnet from `main` and rebundles classic from the `clavity-classic` branch tip. Bump the dotnet version
  in `installer/clavity-dotnet.iss` before tagging.

## Also this session

- `plugins/agy-autotrain/knowledge/agy-observations.md` — the agy-learn inbox was checkpointed on `main`
  (`b3b1ac5`) for durability (raw captures that had accumulated uncommitted; drained later by `agy-curate`, not a
  release artifact).

## Current repo state / loose ends

- `main` HEAD = `858746b` (tagged `clavity-v3`), pushed.
- Merged branch `fix-agy-status-cascade-id` can be deleted (local only; never pushed).
- Pre-existing dirty (NOT part of this release, left untouched): `publish/` (untracked build output — a `.gitignore`
  rule should match it but `status` still shows it; worth tidying the ignore) and
  `docs/superpowers/plans/2026-07-01-golden-header-parity.md` (untracked WIP plan).
