# clavity-ls MCP tool channel diagnosability — Design

**Status:** design (brainstormed; AGY-FIRST divergent pass folded — agy `[VERDICT: MINIMAL_DIAGNOSE_ONLY]`,
converged with the consuming agent; owner delegated the pick). Product: `clavity-dotnet` (`clavity-ls`).
Sibling of the `agy_ask` idle-wait timeout spec (same file, `McpTools.cs`); a SEPARATE, cohesive concern.

## Problem (log + code confirmed)

When agy's language server shuts down or restarts, the gRPC port `clavity-ls` talks to dies with it and
`clavity-ls`'s MCP tools throw an UNCAUGHT `RpcException` — the MCP framework then renders a bare
`An error occurred invoking 'agy_ask'` with NO cause. `RunAsync<T>` (`McpTools.cs:34-55`) catches ONLY
`AgyModalHangException` and `AgyConversationPendingException`; everything else propagates. Worse,
`agy_status` — the health-check — ALSO throws on a dead channel (`StatusAsync` calls
`GetCascadeTrajectoryAsync`, which throws, BEFORE the fail-safe `ProbeIdleAsync` runs), so the one tool
that should report "channel down" is itself useless exactly when needed.

**Evidence (this session):** `~/.gemini/antigravity-cli/logs/clavity-231b5128….log:1001-1011` (18:20:48) —
`CLI program exited, shutting down` -> `Language server shutting down` -> agy SIGKILL-abandons ALL its MCP
instances (`i.CS.Close() did not return within 100ms after SIGKILL`). The Close()-hang is agy-side Go
(`mcp_manager.go:1429`) and the shutdown is intermittent ("happens occasionally"). Both are OUT OF SCOPE —
this spec makes `clavity-ls` DIAGNOSE the dropped channel, not fix agy.

## Goal

On a dead/failed channel, every clavity-ls tool returns a STRUCTURED, actionable diagnostic (cause + hint)
instead of an opaque error; `agy_status` becomes a reliable NEVER-throwing health check reporting
`channel_down`, so a caller can pre-flight it and get a clean signal.

## Success criteria (checkable)

1. A dead-channel `agy_ask` / `agy_look` returns a structured `{status:"channel_down", diagnostic, hint}`
   — never a bare MCP error. This holds whether the channel was already dead (pre-flight) OR dies mid-call.
2. `agy_status` NEVER throws on a dead channel — it returns its normal `AgyStatus` shape with
   `state:"channel_down"`.
3. The diagnostic names the real cause (the `RpcException` `StatusCode` + detail) and the hint is
   actionable (what died + how to recover + where to look).
4. A genuinely unexpected exception (e.g. `NullReferenceException`) is NOT masked as a channel error — it
   still propagates (or surfaces distinctly), so real bugs are not hidden.

## Approach chosen — minimal targeted diagnose-only (agy's #2 + refinements)

Rejected: broad `catch (Exception)` (agy's #1 — masks real bugs, violates criterion 4); auto-recover via
`LsDiscovery` rebuild (agy's #3 — mutates the `Program.cs`-once singleton config, filesystem scan in the
RPC hot path, race risk if agy's port changed, and MCP-session state likely needs a restart anyway; noted
as a future direction, out of scope); the pre-flight-probe-hijacking-`AgyModalHangException` (agy's #4 —
a dead channel is not a modal hang, and it misses mid-ask death).

### Design

**New types (mirror the `possible_modal` pattern — `AgyModalHangException` + `TimeoutDiagnostic`):**
- `ChannelDiagnostic(string StatusCode, string Detail)` — a record (like `TimeoutDiagnostic`), carrying the
  gRPC `StatusCode` name (e.g. `"Unavailable"`) and `ex.Status.Detail`/`ex.Message`.

**Central catch in `RunAsync<T>` (`McpTools.cs`)** — add, after the existing two catches:
```
catch (Exception ex) when (ex is RpcException or ObjectDisposedException or LsDiscoveryException)
{
    // channel dead: agy's LS shut down/restarted (RpcException), the channel was disposed mid-flight
    // (ObjectDisposedException), or the LS is fully down and can't even be discovered
    // (LsDiscoveryException — thrown by ConnectAndResolveAsync at connect time).
    return JsonSerializer.Serialize(new {
        status = "channel_down",
        diagnostic = <ChannelDiagnostic from ex>,   // StatusCode + detail (Unknown for the non-Rpc cases)
        hint = "<the honest hint below>",
    });
}
```
This is TARGETED (three channel-dead exception types — F1 added `LsDiscoveryException` so that a fully-down
LS that `agy_ask`/`agy_look` can't even discover yields `channel_down`, not a bare error, matching what
`agy_status`'s local catch already does), so a `NullReferenceException` or other real bug still propagates
(criterion 4). Because the catch is in `RunAsync` — which wraps ALL three tools — it covers both a pre-dead
channel and a channel that dies MID-`AskAsync`/`LookAsync` (criterion 1).

**F2 (accepted limitation):** an `ObjectDisposedException` originating from a genuine disposal BUG in our
own code (not the channel) would be mislabeled `channel_down`. Accepted as rare: in these code paths an
`ObjectDisposedException` is almost always the disposed `GrpcChannel`. If this ever bites, narrow the filter
to inspect the disposed object's type — not done speculatively.

**F3 (WRAPPED channel-death on the new-conversation path — MUST fold):** `AskAsync` calls
`ResolveSendModelAsync` (`AgyView.cs:152` -> `:309`). On a BRAND-NEW conversation the model catalog is
REQUIRED, and `AgyView.cs:346` catches a generic `RpcException` (a dead channel surfaces as
`StatusCode.Unavailable`) and re-throws it WRAPPED as `AgyModelUnavailableException` (dropping the
`RpcException`). That wrapper is NOT in the central `when` filter, so a dead-channel `agy_ask` on a new
conversation would bare-error — violating criterion 1. (The EXISTING-conversation path is safe: there the
catalog `RpcException` is swallowed at `:321`/`:322` and the dead channel resurfaces at send time as a plain
`RpcException`, which the central catch handles.) Resolution: the channel-death cause must survive to the
central catch. Two acceptable mechanisms (implementer's call):
  (i) at `AgyView.cs:346`, pass the `RpcException` as the `AgyModelUnavailableException`'s `InnerException`,
      and extend the central `when` filter to also match
      `AgyModelUnavailableException { InnerException: RpcException or ObjectDisposedException or LsDiscoveryException }`
      -> `channel_down`; or
  (ii) at `:346`, when the `RpcException` is a channel-death status, RE-THROW the `RpcException` (don't wrap)
      so the existing central catch handles it, wrapping as `AgyModelUnavailableException` ONLY for a
      non-channel/transient status.
Either way, a BARE `AgyModelUnavailableException` with NO channel-death cause (the deprecated-model /
not-in-catalog cases at `:319`/`:348`/`:358`) is NOT `channel_down` and is OUT OF SCOPE (it behaves as
today — a genuine model-availability error, not a channel error). Do not blanket-catch
`AgyModelUnavailableException` as `channel_down` — that would mislabel a real deprecated-model error.

**`agy_status` local catch (`AgyView.StatusAsync`)** — wrap the RPC calls (`ConnectAndResolveAsync` +
`GetCascadeTrajectoryAsync`) in `try/catch` for `RpcException`, `ObjectDisposedException`, AND
`LsDiscoveryException` (the LS-unreachable case), returning
`new AgyStatus(cascadeId: "", totalSteps: 0, state: "channel_down", lastStepKind: 0)`. So `agy_status`
returns its normal shape with a `channel_down` state and never throws (criterion 2). (The central
`RunAsync` catch remains the backstop, but the local catch keeps `agy_status`'s result shape consistent —
a health check should report health in its own shape, not an error envelope.)

**The hint (criterion 3 — this is the "diagnosis mechanism"):**
> "clavity-ls -> agy channel is down ([<StatusCode>] <detail>). agy's language server appears to have shut
> down or restarted (it does this intermittently). Restart the Claude Code session (or the clavity-ls MCP
> server) to re-establish the channel. agy's own logs are at ~/.gemini/antigravity-cli/ (cli.log +
> logs/clavity-<sessionId>.log) if you need to confirm the shutdown."

Naming the log path turns "opaque failure" into "here's exactly how to confirm what happened."

### Components touched
- `McpTools.cs` — the new `catch` in `RunAsync`; serialize `channel_down`.
- `AgyView.cs` — the local `try/catch` in `StatusAsync`.
- A new `ChannelDiagnostic` record (next to `TimeoutDiagnostic` in `AskReply.cs`).
- (No new exception type is strictly required — the exceptions are caught where thrown-through; but if a
  cleaner seam is wanted, an `AgyChannelDownException` mirroring `AgyModalHangException` is an acceptable
  equivalent. Implementer's call; the wire result is identical.)

## Testing

Extend `AgyAskIntegrationTests` / `McpToolsIntegrationTests` with a fake LS that throws
`RpcException(new Status(StatusCode.Unavailable, "…"))` (the `FakeAskLs` already models a thrown
`RpcException` for `Unimplemented`; extend it to a dead-channel status):
1. **Dead-channel `agy_ask` -> `channel_down`** — assert the returned JSON has `status:"channel_down"`, a
   `diagnostic` with the `StatusCode`, and the hint; assert it did NOT throw / no bare error.
2. **`agy_status` -> `AgyStatus{state:"channel_down"}`, never throws** — on the same dead channel.
3. **Mid-ask death -> `channel_down`** — the fake goes idle-then-throws (or throws partway) so the
   `RpcException` surfaces after the send; assert the `RunAsync` central catch yields `channel_down`.
4. **Non-channel exception still propagates (criterion 4)** — a fake that throws e.g.
   `InvalidOperationException` must NOT be reported as `channel_down` (it propagates / surfaces distinctly),
   proving the targeted catch does not mask real bugs.
5. **Wrapped channel-death on a NEW conversation -> `channel_down` (F3 regression guard)** — drive
   `agy_ask` on a brand-new conversation (no prior model, so `ResolveSendModelAsync` takes the
   catalog-REQUIRED path) and have the fake throw a dead-channel `RpcException(StatusCode.Unavailable)`
   during `GetAvailableModels`. Assert the result is `channel_down` (NOT a bare error, NOT
   `AgyModelUnavailableException` leaking out). Complement: a `deprecated-model` `AgyModelUnavailableException`
   with NO channel cause must NOT be reported as `channel_down` (it stays a model error) — proving the fold
   distinguishes a wrapped channel death from a genuine model-availability error.

## Out of scope
- Auto-recover / reconnect via `LsDiscovery` rebuild (future direction; agy's #3 — revisit only if the
  restart friction proves too costly in practice).
- Fixing agy's `mcp_manager.go` Close()-hang or its shutdown trigger (agy-side Go, not ours).
- Renaming/altering the existing `possible_modal` / `waiting_for_human` statuses.

## Open questions
None blocking. Whether to also catch `IOException` (the code map flagged it as theoretically possible from
a dead channel, though gRPC normally wraps transport failures in `RpcException`) is left to the implementer:
add it to the `when` filter only if a test or live evidence shows a dead channel surfacing a bare
`IOException`; do not add it speculatively (keep the catch targeted).
