# clavity-ls audit log: log path and call id in error replies

Status: APPROVED by owner (2026-11-07), with the agy-first settlements at the end. Product: clavity-dotnet (`Clavity.Ls`, `Clavity.Mcp`).

## Intent and why
An agent whose clavity-ls call fails should learn from the failing reply itself where the failure is recorded
and which log entries are its own, without a new tool. Today the event log (#105) is opt-in
(`CLAVITY_LS_LOG`) and its lines carry no call identity, so an error reply can neither name a file nor point at a call.

## Goals
- Event log file is ON by default, so the reported path is always real.
- Every non-success reply carries `logPath`, `callId`, `recentEvents`.
- Every log line of a call carries that call's id (`call`), so `grep <callId> <logPath>` isolates it.

## Non-goals
- No new MCP tool. No change to successful replies.
- No log of prompts, replies, endpoint files or CSRF tokens (the existing schema rule stands).
- SDK-level failures raised before our code runs ("An error occurred invoking ...") cannot be reached; documented limit.

## Anti-goals
- A default file that grows without bound, or whose failure can break a call (existing swallow-all-sink-failures rule stays).
- A reply that names a path that is not being written (sink dropped after a failure must not still be advertised).

## Approaches considered
- A. Add the fields to each envelope in place (7 sites, easy to forget on the next one).
- B. One shared fault-envelope helper used by `RunAsync` and `ArgumentPrecheck`, plus a test that every
  non-success status carries all three fields. **Chosen by owner**: keeps the guarantee after future changes.
- Log default (owner chose): file ON by default, over "report no file log" and "write only after first failure".

## Design
1. **Default path.** `LsEventLog.ResolveFilePath` gains a default: `<userprofile>/.clavity/logs/clavity-ls-<session|pid<pid>>.log`
   (base dir follows `GoldenHeader.ResolveDir`'s pattern). `CLAVITY_LS_LOG` still overrides (dir or file);
   `CLAVITY_LS_LOG=off` disables the file (builder's call on the exact token; document it).
2. **Retention.** At server start prune `clavity-ls-*.log` older than 7 days in the default dir via `LogRetention.Prune`.
3. **Call id.** `p<pid>-<n>`, per-process counter, assigned in `RunAsync`; `LsEvent` gains optional `call`
   (omitted when null, per the existing wire rule). Start and end events carry it.
4. **Fault helper.** One function builds every non-success reply (`possible_modal` both shapes, `waiting_for_human`,
   `channel_down`, `model_unavailable`, `error`) and adds `logPath`, `callId`, `recentEvents`; existing members and
   their order are unchanged. `ArgumentPrecheck` refusals (plain text, `IsError`) get a trailing sentence naming
   `logPath`; they get no `callId` unless the builder can allocate one without touching `RunAsync` ordering.
5. **Honest path.** `logPath` is null/omitted if the file sink is disabled or was dropped after a failure; the reply
   then says the log is memory-only.
6. **Docs.** README (EN + EL) `CLAVITY_LS_LOG` entry, CHANGELOG line, `agy-assumptions.md` untouched (not agy-facing).

## Constraints
- Pinned byte-for-byte shapes of existing replies may only gain the new members; the pinning tests are the oracle.
- stdout is the MCP channel; nothing new may write to it.

## Left to the builder
`off` token spelling; whether precheck refusals get a call id; log line flush/lock behaviour under the default dir
(per-line flush already exists); test layout (extend `LsEventLogTests.cs`, `McpToolsEventTests.cs`).

## Refinements found while planning (against the code as it is now)
- `LsEventLog.ResolveFilePath` is pinned by `LsEventLogTests` ("unset/blank means no file"), so the default does NOT go there:
  a new `ResolveSink` wraps it. Same behaviour as item 1.
- `waiting_for_human` is pinned to carry NO ring (`A_waiting_for_human_reply_is_recorded_without_dumping_the_ring`). It gets
  `logPath` + `callId` but not `recentEvents`; the pinning test wins over "all three" in goal 2.
- `agy_status` fault replies are built in `AgyView.StatusAsync`, outside `RunAsync`: `AgyStatus` gains `LogPath`/`CallId`.
  The call id travels by `AsyncLocal` so no signature changes. Absent `LogPath` on a status reply means memory-only.
- Precheck refusals DO get a call id (resolves "left to the builder"): they record a `refused` event.
- `CHANGELOG.md` is release-generated from conventional commits; it is not hand-edited (supersedes item 6's CHANGELOG line).
- Default dir is fixed `~/.clavity/logs` (not redirected by the golden-header override).

## Settled by the agy-first consult and negotiation (owner approved 2026-11-07)
Peer reply: `.clavity/scratch/ls-audit-log/reply.md`, negotiation: `.clavity/scratch/ls-audit-log-negotiate/reply.md`.
- **Fixed-width ids.** `p<pid>-<n:D6>` (e.g. `p42-000001`). Measured: `grep -c p42-1` over lines for p42-1/p42-10/p42-11
  printed 3; with equal-width ids no id is a substring of another, so `grep <callId> <logPath>` isolates one call.
- **Default dir has a trailing separator.** `ResolveFilePath` (`LsEventLog.cs:75`) treats a missing path without a trailing
  separator as a FILE; `ResolveSink` therefore passes the default dir with `Path.DirectorySeparatorChar` appended.
  The sink already creates the parent dir (`LsEventLog.cs:134`).
- **Size cap with one rollover (resolves anti-goal "grows without bound").** At 10 MB the active file is renamed to
  `<name>.old.log` (replacing any earlier one) and a fresh active file is opened. If the rollover fails, the sink is
  dropped as after any write failure (memory-only from then on). No timer, no further generations: at most 20 MB per
  server. `.old.log` matches the prune glob `clavity-*.log` (`LogRetention.cs:25`). Known limit, documented, not coded
  around: a call straddling a rollover has its start line in `.old.log`.
- **Call id lives on the log instance.** The `AsyncLocal` is an instance field of `LsEventLog` (not static), so two logs in
  one flow do not share an id. Assigned in `RunAsync` and in `ArgumentPrecheck.For` on refusal (a refused call never reaches
  `RunAsync`, so no call gets two ids), each cleared in a `finally`. Measured: an `async` method's AsyncLocal write does not
  reach its caller even on synchronous completion, so the `finally` marks the end of the call rather than fixing a leak.
  A single outer request filter was considered and rejected: tests drive `RunAsync` directly, so it would need a fallback anyway.
- **`agy_status` faults carry `LogNote`** when memory-only, matching `FaultJson`'s `logNote`.
- Pre-existing and left alone: `AgyStatus` members are PascalCase while `RunAsync` envelopes are camelCase; argument refusals are
  `IsError` while tool faults are not.
