# clavity-ls audit log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every non-success clavity-ls reply names the event-log file and the call's id; the file is written by default.

**Architecture:** `LsEventLog` gains a default-file resolver, a 10 MB size cap with one `.old.log` rollover, a per-call id carried by an instance `AsyncLocal` and stamped on every line, and a `FilePath` accessor. One fault-envelope helper in `McpTools` adds `recentEvents`, `logPath`, `callId` to every fault reply. `ArgumentPrecheck` gets a log-aware variant.

**Tech Stack:** C# / .NET, xUnit, ModelContextProtocol SDK. All paths below are under `clavity-dotnet/`.

**Spec:** `docs/superpowers/specs/2026-11-07-ls-audit-log-design.md` (read its "Refinements" section: it overrides the design where it conflicts).

## Global Constraints
- Gate: `just test` from `clavity-dotnet/` (= `dotnet test tests/Clavity.Ls.Tests` then `dotnet test tests/Clavity.Integration.Tests`). No extra flags.
- Existing reply members, order and bytes may only GAIN the new members at the end; pinning tests are the oracle. If a pinned test fails, STOP and report; do not edit it to match (the two sanctioned edits are named in Tasks 2 and 3).
- stdout is the MCP channel; nothing new writes to it.
- A log line holds only the `LsEvent` schema plus `call`: never a prompt, reply, endpoint file or CSRF token.
- Recording must never fail the call it describes (existing swallow-all-sink-failures rule).
- Success replies are unchanged byte for byte. Tests build `new LsEventLog()` (memory only) and must never write under the real `~/.clavity`.
- Dispatch rules for implementers: Step 0 open each target file and confirm it matches the cited symbols, else report `STATE_MISMATCH: <what>`; if making code compile would change the shape/type/encoding of a pasted value, STOP and report `[original] -> [yours] because <reason>`.

## Review Focus
1. Two overlapping calls to the same tool get distinct ids and each line carries its own call's id (Task 2).
2. File sink dropped after a failure: the reply must not advertise a stale path; it says memory-only (Task 3).
3. A reply message containing `<`, `&` or non-ASCII text serializes byte-identically for the pre-existing members (Task 3).
4. Two servers with no session id and a shared explicit `CLAVITY_LS_LOG` file: ids stay unique (`p<pid>-<n:D6>`) (Task 2).
5. `CLAVITY_LS_LOG=off` / `OFF` / ` off ` disables the file; an unwritable default dir, or a default dir that does not exist yet, leaves the server working and writing (Task 1).
6. A server that reaches the size cap keeps recording its newest failures in the active file; a failed rollover drops to memory-only without failing the call (Task 1b).

---

### Task 1: Default sink resolution, retention, wiring

**Files:**
- Modify: `src/Clavity.Ls/LsEventLog.cs` (add near `ResolveFilePath`, line ~49)
- Modify: `src/Clavity.Cli/Program.cs:27-31` (the `new LsEventLog(Console.Error, LsEventLog.ResolveFilePath(...))` call)
- Test: `tests/Clavity.Ls.Tests/LsEventLogTests.cs`

**Interfaces:**
- Produces: `public const string OffValue = "off";` and
  `public static string? ResolveSink(string? envValue, string userProfileDir, string? sessionId, int pid)` on `LsEventLog`.
  Unset/blank -> file in `Path.Combine(userProfileDir, ".clavity", "logs")` named as `ResolveFilePath` names directory files (`clavity-ls-<session>.log` / `clavity-ls-pid<pid>.log`). `envValue.Trim()` equal to `OffValue` ignoring case -> null. Anything else -> `ResolveFilePath(envValue, sessionId, pid)`. `ResolveFilePath` itself is NOT changed.
- Existing, reuse: `LogRetention.Prune(string logsDir, TimeSpan maxAge, DateTime nowUtc)` + `LogRetention.DefaultMaxAge` (glob `clavity-*.log` already matches `clavity-ls-*.log`).

- [ ] **Step 1: Write failing tests** in `LsEventLogTests.cs` (the `_dir` temp dir fixture exists):
  - `An_unset_or_blank_value_resolves_to_the_default_file_under_dot_clavity_logs`: `ResolveSink(null|""|"   ", _dir, "s1", 42)` equals `Path.Combine(_dir, ".clavity", "logs", "clavity-ls-s1.log")`; with sessionId null -> `clavity-ls-pid42.log`.
  - `Off_in_any_case_with_padding_means_no_file`: `"off"`, `"OFF"`, `" Off "` -> null.
  - `An_explicit_value_behaves_exactly_as_ResolveFilePath`: for `_dir`, a file path, and a trailing-separator path, `ResolveSink(v, "ignored", "s1", 1)` equals `ResolveFilePath(v, "s1", 1)`.
  - `The_default_resolves_to_a_file_inside_the_dir_even_when_the_dir_does_not_exist_yet`: assert `Directory.Exists(Path.Combine(_dir, ".clavity", "logs"))` is false first, then the same expectation as the first test (guards `LsEventLog.cs:75`, which treats a missing path without a trailing separator as a file).
- [ ] **Step 2:** Run `dotnet test tests/Clavity.Ls.Tests --filter LsEventLogTests`. Expected: build FAIL (`ResolveSink` undefined).
- [ ] **Step 3:** Implement `ResolveSink` + `OffValue` in `LsEventLog.cs`, delegating to `ResolveFilePath`: an unset value becomes `Path.Combine(userProfileDir, ".clavity", "logs") + Path.DirectorySeparatorChar` and is passed through it, so naming and `SafeFileName` stay in one place.
- [ ] **Step 4:** Run the same command. Expected: all `LsEventLogTests` PASS (old `ResolveFilePath` tests untouched).
- [ ] **Step 5:** Wire `Program.cs`: declare `var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);` before the log is built (no such local exists today), replace `LsEventLog.ResolveFilePath(` with `LsEventLog.ResolveSink(` passing `userProfile` as the new second argument. Before constructing the log, call `LogRetention.Prune(Path.Combine(userProfile, ".clavity", "logs"), LogRetention.DefaultMaxAge, DateTime.UtcNow)` inside `try { } catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }` (an unreadable dir must not stop the server). Note: on Linux a prune can delete a still-open file of an idle server older than 7 days; acceptable.
- [ ] **Step 6:** `dotnet build` (expected: Build succeeded, 0 errors). Commit: `feat(clavity-ls): write the event log file by default under ~/.clavity/logs`.

### Task 1b: Size cap with one rollover

**Files:**
- Modify: `src/Clavity.Ls/LsEventLog.cs` (constructor line 60; `Append` lines 127-149)
- Test: `tests/Clavity.Ls.Tests/LsEventLogTests.cs`

**Interfaces:**
- Produces: `public const long MaxFileBytes = 10 * 1024 * 1024;`, a new LAST constructor parameter `long maxFileBytes = MaxFileBytes` (existing call sites unchanged), and `public static string OldPathFor(string filePath)` = `Path.ChangeExtension(filePath, ".old.log")` (`clavity-ls-s1.log` -> `clavity-ls-s1.old.log`; a file with no extension `x` -> `x.old.log`).
- Behaviour in `Append`, after the file is open and BEFORE writing the line: if `_file.BaseStream.Length >= _maxFileBytes`, dispose `_file`, `File.Move(_filePath, OldPathFor(_filePath), overwrite: true)`, open a fresh file the same way as today (same `FileShare`, `AutoFlush`), then write. Any exception from this goes to the existing `catch (IsSinkFailure)` that drops the sink; no new catch, no retry. A file that is already over the cap when first opened (restart of the same session) rolls over on that first write.
- `.old.log` is pruned by the existing `clavity-*.log` glob; nothing to add in `Program.cs`.
- Known limit (document in Task 4, do not code around): the cap is per process. Two servers writing one file can lose lines across a rollover (one renames the file the other still holds open). That happens with a shared EXPLICIT `CLAVITY_LS_LOG` file, or with the default file when two servers run under the same session id (the default name is per session, `LsEventLog.cs:76`, and per pid only without a session id).

- [ ] **Step 1: Write failing tests** (log file `Path.Combine(_dir, "clavity-ls-t.log")`; cap `200` bytes via the new parameter; a line is well under 200):
  - `Reaching_the_cap_moves_the_file_to_old_log_and_continues_in_a_fresh_file`: record until `OldPathFor(path)` exists; assert the active file is non-empty and shorter than the old one, the old file holds the earliest line, and the active file holds the newest line.
  - `A_second_rollover_replaces_the_old_file`: keep recording through two rollovers; exactly two files exist in the dir (`*.log`), and the earliest line is in neither.
  - `A_failed_rollover_drops_the_sink_and_never_fails_the_call`: create a DIRECTORY at `OldPathFor(path)` so the move fails; recording through the cap does not throw, and after the failure further `Record` calls leave the active file's length unchanged; `Snapshot()` still holds the newest line.
  - `OldPathFor_names`: `clavity-ls-s1.log` -> `clavity-ls-s1.old.log`; `x` -> `x.old.log`.
- [ ] **Step 2:** `dotnet test tests/Clavity.Ls.Tests --filter LsEventLogTests`. Expected: build FAIL (`OldPathFor`/parameter undefined).
- [ ] **Step 3:** Implement per Interfaces.
- [ ] **Step 4:** Same command. Expected: PASS, all pre-existing `LsEventLogTests` unchanged.
- [ ] **Step 5:** Commit: `feat(clavity-ls): cap the event log at 10 MB with one .old.log rollover`.

### Task 2: Call id on every line, `FilePath`

**Files:**
- Modify: `src/Clavity.Ls/LsEventLog.cs` (`LsEvent` record line 13-21; `Record` line ~86)
- Modify: `src/Clavity.Mcp/McpTools.cs:234-241` (`RunAsync` start)
- Test: `tests/Clavity.Ls.Tests/LsEventLogTests.cs`, `tests/Clavity.Integration.Tests/McpToolsEventTests.cs`

**Interfaces:**
- Consumes: Task 1 (none required in code).
- Produces on `LsEvent`: a LAST positional member `[property: JsonPropertyName("call")] string? Call = null` (omitted when null by the existing option).
- Produces on `LsEventLog`:
  - `public string BeginCall()` : allocates `$"p{Environment.ProcessId}-{n:D6}"` (n from an `Interlocked`-incremented instance counter starting at 1, so the first id is `p<pid>-000001`), stores it in a private readonly INSTANCE field `AsyncLocal<string?>` (not static: two logs in one flow must not share an id), returns it.
  - `public void EndCall()` : sets that AsyncLocal to null.
  - `public string? CurrentCallId` : the AsyncLocal value.
  - `public string? FilePath` : the effective sink path read under `_gate`; null when no file, after a sink failure, or after `Dispose`.
  - `Record(...)` signature unchanged; it stamps `Call` from `CurrentCallId`.
- `RunAsync` calls `events.BeginCall()` as its first statement (before `Record(tool,"start")`) and wraps the whole existing body, catches included, in `try { ... } finally { events.EndCall(); }`, so the catches (Task 3) still read the id. Measured: an async method's AsyncLocal write never reaches its caller, so the `finally` marks the call's end rather than fixing a leak.

- [ ] **Step 1: Write failing tests.**
  - LsEventLogTests: `A_record_outside_a_call_has_no_call_member` (existing exact-string test must still pass untouched); `BeginCall_stamps_every_following_record_in_that_flow_and_ids_are_distinct_and_pid_prefixed` (two sequential `BeginCall` in separate `Task.Run` flows -> `p<pid>-000001`, `p<pid>-000002`, lines carry them); `Two_logs_in_one_flow_do_not_share_a_call_id` (`a.BeginCall()` then `b.Record(...)`: b's line has no `call`); `EndCall_clears_the_id` (after `EndCall`, a `Record` line has no `call`); `FilePath_is_null_without_a_sink_the_path_with_one_and_null_again_after_the_sink_fails` (reuse the unwritable-path technique of `A_file_that_cannot_be_opened_never_fails_the_call...` at line 128, Record once, then assert null).
  - Update `An_event_has_no_member_that_could_carry_a_payload_or_a_secret` (line ~258): add `"Call"` to the expected sorted array (sanctioned edit; an id is not a payload).
  - McpToolsEventTests: `Two_overlapping_calls_to_the_same_tool_stamp_their_own_lines` (two `RunAsync("agy_ask", log, async () => { await Task.Delay(...); ... })` started together via `Task.WhenAll`; group `Snapshot()` by `call`: two groups, each exactly start then end); `Inside_RunAsync_the_action_sees_the_call_id_of_its_own_start_line` (the action captures `log.CurrentCallId`; it matches `^p\d+-\d{6}$` and equals the `call` of the `start` line). Do NOT add a "does not leak to the caller" test: an async method never leaks an AsyncLocal write to its caller, so such a test passes without `EndCall`; `EndCall` is covered by `EndCall_clears_the_id`.
- [ ] **Step 2:** `dotnet test tests/Clavity.Ls.Tests --filter LsEventLogTests` and `dotnet test tests/Clavity.Integration.Tests --filter McpToolsEventTests`. Expected: FAIL / build error.
- [ ] **Step 3:** Implement as in Interfaces.
- [ ] **Step 4:** Run both commands again. Expected: PASS, including the unchanged pre-existing tests in both classes.
- [ ] **Step 5:** Commit: `feat(clavity-ls): stamp every event-log line with its call id`.

### Task 3: Shared fault helper; `agy_status` fault fields

**Files:**
- Modify: `src/Clavity.Mcp/McpTools.cs` (`RunAsync` catches, lines 247-322)
- Modify: `src/Clavity.Ls/AskReply.cs:73-75` (`AgyStatus`), `src/Clavity.Ls/AgyView.cs:228-233` (fault return), `src/Clavity.Ls/LsEventLog.cs` (add `public const string MemoryOnlyNote`)
- Test: `tests/Clavity.Integration.Tests/McpToolsEventTests.cs`, `tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs`

**Interfaces:**
- Consumes: Task 2 (`BeginCall`, `CurrentCallId`, `FilePath`).
- Produces: `internal static string FaultJson(LsEventLog events, object body, bool includeRing = true)` in `McpTools`: `JsonSerializer.SerializeToNode(body)` as a `JsonObject`, then appends in this order `recentEvents` (the `events.Snapshot()` string array; skipped when `includeRing` is false), `logPath` (only when `events.FilePath` is non-null), `logNote` (only when it IS null: the exact string `"event log is memory-only (file disabled or dropped); no log file holds this call"`, which stays true when `includeRing` is false and `recentEvents` is absent), `callId` (only when `events.CurrentCallId` is non-null); returns `JsonSerializer.Serialize(node)` (same encoder as today, so escaping is unchanged).
- Produces on `AgyStatus`: three new LAST optional members, each `[property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]`, in this order: `string? LogPath = null, string? LogNote = null, string? CallId = null`. `LogNote` carries the same exact string as `FaultJson`'s `logNote`, set only when `LogPath` is null (share one constant, e.g. `LsEventLog.MemoryOnlyNote`).
- Rewrite each of the five catch blocks so its anonymous body has its current members minus `recentEvents`, passed to `FaultJson`: `possible_modal` both shapes (ring on), `channel_down`/`StatusFor` (on), `model_unavailable` (on), `error` (on), `waiting_for_human` (`includeRing: false`, pinned). Keep every other member and its order.
- `AgyView.StatusAsync` fault return passes `Events.FilePath`, the note when `FilePath` is null (else null), and `Events.CurrentCallId` as the three new members.

- [ ] **Step 1: Write failing tests.**
  - McpToolsEventTests: `Every_fault_status_carries_logPath_callId_and_the_ring_except_waiting_for_human` as a `[Theory]` over exceptions (`AgyModalHangException` plain, with `PeerFile`, `AgyModelUnavailableException`, `InvalidOperationException`, a channel-down exception as built in AgyChannelDownTests) using a log made with `new LsEventLog(filePath: <temp file>)`: assert `logPath` equals that path, `callId` matches `^p\d+-\d{6}$` and equals the `call` of the last ring line, `recentEvents` present. A separate `Fact` for `AgyConversationPendingException`: `logPath` and `callId` present, `recentEvents` absent.
  - `A_fault_reply_from_a_log_with_no_file_says_memory_only_and_has_no_logPath`: `new LsEventLog()` -> no `logPath`, `logNote` equals the string above, `recentEvents` present.
  - `A_dropped_file_sink_is_not_advertised`: unwritable path (technique as Task 2), fault -> no `logPath`, `logNote` present.
  - `Pre_existing_members_serialize_byte_identically_with_html_and_non_ascii_text`: `error` fault with message `"a<b>&c é 日本"`; assert the reply string STARTS WITH `{"status":"error","exception":"InvalidOperationException","message":"a<b>&c é 日本","recentEvents":` (in the C# test, a verbatim string so the backslashes are literal). Measured with the default encoder: `{"status":"error","message":"a<b>&c é 日本"}`, and the same escaping survives `SerializeToNode` + appended member + `Serialize`. If the real prefix differs, report the difference, do not adjust the code to match the test.
  - A successful call's reply is still exactly `{"ok":1}` (existing test; must stay green).
  - AgyStatusShapeTests: extend the fault test at line 33 pattern: a fault `AgyStatus` with `LogPath`/`CallId` serializes `LogPath`,`CallId` and no `LogNote`; one with only `LogNote`/`CallId` serializes those two and no `LogPath`; a healthy one omits all three (existing line 26 test stays green).
- [ ] **Step 2:** Run `dotnet test tests/Clavity.Integration.Tests --filter McpToolsEventTests` and `dotnet test tests/Clavity.Ls.Tests --filter AgyStatusShapeTests`. Expected: FAIL.
- [ ] **Step 3:** Implement per Interfaces.
- [ ] **Step 4:** Run the same, then the full `just test`. Expected: all PASS (`McpToolsRunAsyncTests`, `AgyChannelDownTests` line ~689 ring test, `AgyAskIntegrationTests` ~3182 healthy-status test unchanged).
- [ ] **Step 5:** Commit: `feat(clavity-ls): fault replies name the event-log file and the call id`.

### Task 4: Argument refusals, docs

**Files:**
- Modify: `src/Clavity.Mcp/ArgumentPrecheck.cs:21-32` (add beside `Filter`)
- Modify: `src/Clavity.Cli/Program.cs:76`
- Modify: `README.md:165` and `README.el.md:154` (`CLAVITY_LS_LOG` entries)
- Test: `tests/Clavity.Integration.Tests/ArgumentPrecheckTests.cs`

**Interfaces:**
- Consumes: Tasks 2-3 (`BeginCall`, `FilePath`, `Record`).
- Produces: `public static McpRequestHandler<CallToolRequestParams, CallToolResult> For(LsEventLog events)`: behaves exactly like `Filter`, except on a refusal it calls `events.BeginCall()` (and `events.EndCall()` in a `finally` once the refusal is built), `events.Record(name, "refused", outcome: "invalid_arguments")` (BEFORE reading `FilePath`, so a first write has been attempted), then appends to the refusal text: `" Logged as <callId> in <logPath>."` or, when `FilePath` is null, `" Logged as <callId> (memory-only; no log file)."`. `Filter` is unchanged (existing tests use it as a method group).

- [ ] **Step 1: Write failing tests** in `ArgumentPrecheckTests.cs` using the existing server fixture (extend its builder with an optional `LsEventLog` that selects `ArgumentPrecheck.For(log)` instead of `Filter`): `A_refusal_with_a_file_log_names_the_call_id_and_path_and_the_file_holds_a_refused_line` (call `agy_ask` with `["payload"]="hi"`; `IsError` true; text ends with `Logged as p<pid>-<6 digits> in <path>.`; the file contains one line with that `call` and `"phase":"refused"`); `A_refusal_with_a_memory_only_log_says_so`; `A_well_formed_call_is_untouched_by_the_log_aware_filter` (no `refused` line, no suffix).
- [ ] **Step 2:** `dotnet test tests/Clavity.Integration.Tests --filter ArgumentPrecheckTests`. Expected: FAIL.
- [ ] **Step 3:** Implement `For`; share the body with `Filter` (Filter = the same handler with a null log) to avoid two copies. Switch `Program.cs:76` to `ArgumentPrecheck.For(events)` (`events` is already in scope there).
- [ ] **Step 4:** Docs: rewrite the `CLAVITY_LS_LOG` entries (EN and EL, same facts): default-on at `~/.clavity/logs/clavity-ls-<session|pid<pid>>.log`; override as before; `off` disables; lines gain `call`; fault replies carry `logPath`, `callId`; absent `logPath` = memory-only (`logNote` says so); ids are `p<pid>-<6 digits>` so `grep <callId> <logPath>` isolates one call; the file is capped at 10 MB with one `<name>.old.log` rollover (a call that straddles a rollover has its start line in `.old.log`; two servers writing one file, an explicit one or the default under a shared session id, can lose lines across a rollover); a caller-cancelled call is rethrown to the SDK (`McpTools.cs:304-310`), so its reply carries neither field, though its `cancelled` line is logged; files older than 7 days are pruned at start; SDK-level "An error occurred invoking" errors are not covered. Do not touch `CHANGELOG.md` (release-generated).
- [ ] **Step 5:** `just test` from `clavity-dotnet/`. Expected: both projects PASS. Commit: `feat(clavity-ls): argument refusals name the log; document the default event log`.

## Self-review
- Spec coverage: default-on file (T1), retention (T1), size cap + rollover (T1b), call id on lines (T2), shared helper + every status (T3), honest path/dropped sink (T3), precheck (T4), docs (T4), SDK-error limit documented (T4). Non-goals untouched.
- Conflicts with pinned tests are resolved in the spec's Refinements (ResolveFilePath, waiting_for_human ring, members list, CHANGELOG).
- Names consistent: `BeginCall`, `EndCall`, `CurrentCallId`, `FilePath`, `FaultJson`, `ResolveSink`, `For`, `OffValue`, `MaxFileBytes`, `OldPathFor`, `MemoryOnlyNote`.
- Task 3's `FaultJson` uses `LsEventLog.MemoryOnlyNote` (introduced in Task 3, used by both `FaultJson` and `AgyView`).

## Stand-downs
Adversarial panel (solo + agy, 3 rounds, round 3 CLEAN, 2026-11-07). No finding was DISCARDED-BELOW-FLOOR or UNVERIFIED-ACCEPTED; every non-folded finding was REJECTED by measurement or by the spec (OldPathFor self-collision: measured `.old.old.log`; prune of a 7-day-old `.old.log`: spec item 2; rollover straddle and cancellation: already documented limits).
