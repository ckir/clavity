# clavity-ls agy channel resilience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `clavity-ls`'s `agy_ask`/`agy_status`/`agy_look` survive two failure modes it currently mishandles — a long-but-healthy agy turn (abandoned at a flat 120s), and a dead agy channel (opaque bare error) — by replacing the flat idle-wait cap with a progress-extensible deadline and by turning every channel death into a structured `channel_down` diagnosis.

**Architecture:** Two cohesive concerns over the SAME files (`AgyView.cs`, `McpTools.cs`). Part A rewrites the single `CancelAfter` idle-wait in `AgyView.AskAsync` into a windowed loop that resets on step-count progress and stops at an absolute-max backstop, with two new `CLAVITY_AGY_IDLE_*` env knobs and a `limit` field on `possible_modal`. Part B adds a targeted `channel_down` catch (RpcException≠Cancelled | ObjectDisposedException | LsDiscoveryException, plus a wrapped-on-new-conversation variant) in `McpTools.RunAsync` and a never-throwing local catch in `AgyView.StatusAsync`, both producing a `ChannelDiagnostic` that unwraps the real gRPC cause.

**Tech Stack:** C# / .NET, gRPC (`Grpc.Core`), xUnit, in-proc Kestrel fake LS. Source specs (design source of truth, assume-correct): `docs/superpowers/specs/2026-07-25-agy-ask-idle-wait-timeout-design.md` and `docs/superpowers/specs/2026-07-25-agy-tool-channel-diagnosability-design.md`.

---

> **Line numbers are as-of-HEAD `f2fd96a` and DRIFT within this plan.** Every `file:line` below was verified against HEAD, but each task that INSERTS lines shifts the citations in later tasks that touch the same file (e.g. Task A1 adds ~6 lines to `AgyViewOptions` at the top of `AgyView.cs`, so Task A2/B3/B4's `AgyView.cs` line numbers move down). Line numbers are NAVIGATION only — every edit is located by the **quoted anchor text** (the Edit tool matches text, not line numbers), and each task's Step 0 re-confirms the anchor exists before editing. If an anchor is not found verbatim, STOP with `STATE_MISMATCH` rather than guessing a line.

## Two things the owner must know before executing

1. **CI-gate scope (flagged, NOT resolved in this plan).** The repo's automated gate is `just test` = `dotnet test tests/Clavity.Ls.Tests` (`ci-dotnet.yml:26`). The fake-LS integration tests (existing `AgyAskIntegrationTests`, `McpToolsIntegrationTests`, and the new suites this plan adds) live in `tests/Clavity.Integration.Tests`, which **CI does not run**. This plan follows the established placement (fake-LS tests → `Clavity.Integration.Tests`, pure-unit tests → `Clavity.Ls.Tests`) and pushes every deterministic guard it can into `Clavity.Ls.Tests` so CI actually protects it. Widening the CI gate to include `Clavity.Integration.Tests` is a separate one-line change (`ci-dotnet.yml` + the `justfile` `test` recipe) with its own review — **out of scope here; call it out to the owner.**
2. **One F5 path is not integration-simulable.** The §0b F5 guard ("`agy_status` survives an `ObjectDisposedException` from `ProbeIdleAsync`") cannot be exercised through the in-proc fake, because a server-thrown exception always arrives at the client as an `RpcException` (which `ProbeIdleAsync` intentionally swallows to `"unknown"`), never as a client-side `ObjectDisposedException`. Task B4 therefore guards F5 by (a) a unit test that `ChannelDown.IsChannelDown(ObjectDisposedException) == true`, and (b) the structural fact that `StatusAsync`'s catch wraps the **entire** body including `ProbeIdleAsync` (verified by the spec-compliance review), plus (c) an integration test of the common dead-channel path (`GetCascadeTrajectory` throws, reached before `ProbeIdleAsync`). This is documented in the task.

## File Structure

Production (all in `clavity-dotnet/src/`):
- `Clavity.Ls/AgyView.cs` — the windowed idle-wait loop in `AskAsync` (Part A); the never-throwing local catch in `StatusAsync` and the threaded RpcException at the new-conversation model path (Part B). Owns both behaviors.
- `Clavity.Ls/AgyViewOptions.cs` *(same file as `AgyView.cs`)* — two new option properties (`IdleStallWindow`, `IdleAbsoluteMax`).
- `Clavity.Ls/AgyEnvironment.cs` — two new env-var name constants + a `ResolveSeconds` parse helper.
- `Clavity.Cli/Program.cs` — resolve the two env vars into `AgyViewOptions`.
- `Clavity.Ls/ModalGuard.cs` — `IModalGuard.OnLsTimeout` gains a `limit`; `ModalGuardReport` gains `Limit`; the stall-vs-absolute_max hint split; a new `IdleLimit` constant pair.
- `Clavity.Ls/AskReply.cs` — a new `ChannelDiagnostic` record; `AgyStatus` gains two optional fields (`Diagnostic`, `Hint`).
- `Clavity.Ls/ChannelDown.cs` *(new file)* — the shared `channel_down` decision (`IsChannelDown`), the F4 unwrap-the-cause extractor (`Diagnose`), the hint, and the wire-status constant. Shared by `McpTools.RunAsync` and `AgyView.StatusAsync`.
- `Clavity.Ls/AgyModelUnavailableException.cs` — add an inner-exception constructor overload (F3).
- `Clavity.Mcp/McpTools.cs` — `limit` on the `possible_modal` payload (Part A); the central `channel_down` catch (Part B).

Tests:
- `tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs` *(new)* — `ResolveSeconds` parsing (CI-gated).
- `tests/Clavity.Ls.Tests/ModalGuardTests.cs` — rewrite for the limit split (CI-gated).
- `tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs` *(new)* — `AgyStatus`/`ChannelDiagnostic` serialization + `ChannelDown` decision unit tests (CI-gated).
- `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` — enhance `FakeAskLs` with a wait-plan; rewrite the two old timeout tests; add the progress/stall/absolute-max/fast-idle/long-single-step tests.
- `tests/Clavity.Integration.Tests/AgyChannelDownTests.cs` *(new)* — dead-channel `agy_ask`/`agy_look`/`agy_status`, criterion-4 propagation, F3 new-conversation, F6 caller-cancel end-to-end.

---

## Part A — progress-extensible idle-wait timeout

### Task A1: Env knobs + options + wiring

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyEnvironment.cs`
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs:7-28` (the `AgyViewOptions` class)
- Modify: `clavity-dotnet/src/Clavity.Cli/Program.cs:18-26` (the options initializer)
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs` (create)

**Step 0 — State verification.** Open the three files and confirm: `AgyEnvironment` (AgyEnvironment.cs) exposes `LogPathVar`/`SessionIdVar`/`ResolveCliLogPath` and nothing named `IdleStall*`; `AgyViewOptions` (AgyView.cs:7) has `CliLogPath`/`BootRaceTimeout`/`GoldenHeaderDir`/`EscalationIndex`/`Diagnostics` and no `IdleStallWindow`; `AgyView.DefaultIdleWaitTimeout` is `public static readonly TimeSpan = 120s` at AgyView.cs:106; Program.cs:18-26 builds `AgyViewOptions` with `CliLogPath`/`GoldenHeaderDir`/`EscalationIndex`. If any differ, STOP and report `STATE_MISMATCH: <what>`.

- [ ] **Step 1: Write the failing test** — `clavity-dotnet/tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs`

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class AgyEnvironmentTests
{
    [Fact]
    public void ResolveSeconds_parses_a_positive_integer_to_a_TimeSpan()
        => Assert.Equal(TimeSpan.FromSeconds(90),
            AgyEnvironment.ResolveSeconds("90", TimeSpan.FromSeconds(120)));

    [Fact]
    public void ResolveSeconds_falls_back_when_unset_or_blank()
    {
        Assert.Equal(TimeSpan.FromSeconds(120), AgyEnvironment.ResolveSeconds(null, TimeSpan.FromSeconds(120)));
        Assert.Equal(TimeSpan.FromSeconds(120), AgyEnvironment.ResolveSeconds("", TimeSpan.FromSeconds(120)));
    }

    [Fact]
    public void ResolveSeconds_falls_back_on_a_non_numeric_or_negative_value()
    {
        Assert.Equal(TimeSpan.FromSeconds(600), AgyEnvironment.ResolveSeconds("abc", TimeSpan.FromSeconds(600)));
        Assert.Equal(TimeSpan.FromSeconds(600), AgyEnvironment.ResolveSeconds("-5", TimeSpan.FromSeconds(600)));
    }

    [Fact]
    public void ResolveSeconds_treats_zero_as_the_fallback_unless_allowZero()
    {
        Assert.Equal(TimeSpan.FromSeconds(600), AgyEnvironment.ResolveSeconds("0", TimeSpan.FromSeconds(600)));
        Assert.Equal(TimeSpan.Zero, AgyEnvironment.ResolveSeconds("0", TimeSpan.FromSeconds(600), allowZero: true));
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter AgyEnvironmentTests`
Expected: FAIL to compile — `AgyEnvironment` has no `ResolveSeconds`.

- [ ] **Step 3: Add the constants + parse helper** — append inside `AgyEnvironment` (AgyEnvironment.cs), after `ResolveCliLogPath`:

```csharp
    /// <summary>Env var: max seconds with NO agy step progress before agy_ask reports possible_modal(stall).</summary>
    public const string IdleStallSecondsVar = "CLAVITY_AGY_IDLE_STALL_SECONDS";

    /// <summary>Env var: absolute max total idle-wait (seconds) regardless of progress; 0 = unbounded.</summary>
    public const string IdleMaxSecondsVar = "CLAVITY_AGY_IDLE_MAX_SECONDS";

    /// <summary>Parse a positive-seconds env value to a TimeSpan. Unset/blank/non-numeric/negative -> <paramref
    /// name="fallback"/>. Zero -> fallback UNLESS <paramref name="allowZero"/> (the absolute-max "unbounded"
    /// sentinel), in which case "0" -> <see cref="TimeSpan.Zero"/>.</summary>
    public static TimeSpan ResolveSeconds(string? raw, TimeSpan fallback, bool allowZero = false)
    {
        if (int.TryParse(raw, out var s) && (s > 0 || (allowZero && s == 0)))
            return TimeSpan.FromSeconds(s);
        return fallback;
    }
```

- [ ] **Step 4: Add the two option properties** — in `AgyViewOptions` (AgyView.cs), after the `Diagnostics` property (line 27), before the closing brace:

```csharp

    /// <summary>Stall window: max time with NO agy step progress before agy_ask reports possible_modal(limit=stall).
    /// Env: CLAVITY_AGY_IDLE_STALL_SECONDS. Default = <see cref="AgyView.DefaultIdleWaitTimeout"/> (120s) — it was
    /// always really a no-further-progress window, not a whole-turn budget.</summary>
    public TimeSpan IdleStallWindow { get; init; } = AgyView.DefaultIdleWaitTimeout;

    /// <summary>Absolute max total idle-wait regardless of progress. Env: CLAVITY_AGY_IDLE_MAX_SECONDS. Default
    /// 600s; <see cref="TimeSpan.Zero"/> = unbounded (rely purely on progress + the server idle signal).</summary>
    public TimeSpan IdleAbsoluteMax { get; init; } = TimeSpan.FromSeconds(600);
```

- [ ] **Step 5: Wire the env vars in Program.cs** — in the `AgyViewOptions` initializer (Program.cs:18-26), after the `EscalationIndex = ...` line (line 25), add:

```csharp
        IdleStallWindow = AgyEnvironment.ResolveSeconds(
            Environment.GetEnvironmentVariable(AgyEnvironment.IdleStallSecondsVar),
            AgyView.DefaultIdleWaitTimeout),
        IdleAbsoluteMax = AgyEnvironment.ResolveSeconds(
            Environment.GetEnvironmentVariable(AgyEnvironment.IdleMaxSecondsVar),
            TimeSpan.FromSeconds(600), allowZero: true),
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests --filter AgyEnvironmentTests`
Expected: `Passed!  - Failed:     0` (4 tests).

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AgyEnvironment.cs clavity-dotnet/src/Clavity.Ls/AgyView.cs \
        clavity-dotnet/src/Clavity.Cli/Program.cs clavity-dotnet/tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs
git commit -m "feat(clavity-ls): add CLAVITY_AGY_IDLE_STALL/MAX_SECONDS knobs + AgyViewOptions"
```

---

### Task A2: Progress-extensible idle-wait (ModalGuard limit split + windowed loop + payload)

This is ONE atomic task on purpose. The `OnLsTimeout` signature change and its only call site (`AgyView`) must land together — splitting them would leave an intermediate red build for the between-task reviewers. Follow strict TDD: all tests first (red), then all implementation (green), then one commit.

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/ModalGuard.cs` (limit split)
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs` (the windowed loop in `AskAsync` + two helpers)
- Modify: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs` (add `limit` to the `possible_modal` payload)
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/ModalGuardTests.cs` (rewrite — CI-gated)
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` (enhance `FakeAskLs`; rewrite the two old timeout tests; add five new)

**Step 0 — State verification.** Confirm: (a) `ModalGuard.cs` has `ModalGuardReport(string Operation, TimeSpan Elapsed, string Hint)` (record, 3 params), `IModalGuard.OnLsTimeout(string operation, TimeSpan elapsed)`, and `SurfacingModalGuard.OnLsTimeout` returning a report whose hint contains "modal"; `ModalGuardTests.cs` has one test asserting `Contains("modal", ...)`. (b) The `AskAsync` idle-wait block (the `using var timeoutCts = ...` through `return BoundedView.ProjectAskReply(full.CascadeId, delta);`) is present and calls `_modalGuard.OnLsTimeout("WaitForConversationFullyIdle", timeout ?? DefaultIdleWaitTimeout)` with TWO args; `AskAsync` takes `(string message, TimeSpan? timeout = null, CancellationToken cancellationToken = default)`; `BuildTimeoutDiagnosticAsync` exists and seeds `newAgy = total - (before + 1)`. (c) `LsClient.WaitForConversationFullyIdleAsync` returns `bool TimedOut`. (d) `McpTools.RunAsync`'s `AgyModalHangException` catch serializes `possible_modal`. (e) `FakeAskLs.WaitForConversationFullyIdle` does one `Task.Delay(_idleDelay)` then appends the reply. If any differ, STOP: `STATE_MISMATCH: <what>`. Named oracle: the timeout spec's Algorithm block + Error-handling section + Testing items 1–6.

**Shape-divergence STOP.** The `possible_modal` payload adds exactly ONE field `limit` (string, `"stall"|"absolute_max"`); `elapsedSeconds` becomes TOTAL elapsed (not per-window) but stays a number. Do NOT change the `status` string, remove any existing field, or alter `elapsedSeconds`'s type. If compiling forces any wire field's name/shape to change, STOP and report `[original] -> [yours] because <reason>`.

**Accepted assumption (document, no code change).** The loop treats a server-returned `TimedOut == true` the same as a client-window elapse (→ probe progress), and relies on `WaitForConversationFullyIdleAsync` genuinely BLOCKING until inactivity/idle rather than returning `TimedOut == true` instantly. If a future agy returned `TimedOut == true` immediately AND agy kept advancing steps, the loop would iterate quickly — but it is still hard-bounded by the absolute-max backstop and terminates. The fake models `TimedOut == false` (idle) and client-window elapse only; the instant-`TimedOut==true` case is out of scope and backstopped.

- [ ] **Step 1: Write the failing ModalGuard test** — replace the body of `clavity-dotnet/tests/Clavity.Ls.Tests/ModalGuardTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ModalGuardTests
{
    [Fact]
    public void Stall_report_names_both_a_modal_and_a_long_single_step()
    {
        var report = new SurfacingModalGuard().OnLsTimeout(
            "WaitForConversationFullyIdle", TimeSpan.FromSeconds(120), IdleLimit.Stall);

        Assert.Equal("WaitForConversationFullyIdle", report.Operation);
        Assert.Equal(TimeSpan.FromSeconds(120), report.Elapsed);
        Assert.Equal(IdleLimit.Stall, report.Limit);
        // F4: the stall hint must name BOTH failure causes, never modal-only.
        Assert.Contains("modal", report.Hint, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("long step", report.Hint, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("CLAVITY_AGY_IDLE_STALL_SECONDS", report.Hint);
    }

    [Fact]
    public void Absolute_max_report_says_progressing_exceeded_budget_and_does_not_claim_a_modal()
    {
        var report = new SurfacingModalGuard().OnLsTimeout(
            "WaitForConversationFullyIdle", TimeSpan.FromSeconds(600), IdleLimit.AbsoluteMax);

        Assert.Equal(IdleLimit.AbsoluteMax, report.Limit);
        Assert.DoesNotContain("modal", report.Hint, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("CLAVITY_AGY_IDLE_MAX_SECONDS", report.Hint);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter ModalGuardTests`
Expected: FAIL to compile — no `IdleLimit`, and `OnLsTimeout` takes 2 args.

- [ ] **Step 3: Implement the limit split** — replace the entire body of `clavity-dotnet/src/Clavity.Ls/ModalGuard.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>Why an idle-wait gave up: <see cref="Stall"/> (no step progress within the stall window) vs
/// <see cref="AbsoluteMax"/> (agy kept progressing but exceeded the absolute budget). The wire value carried in
/// the possible_modal `limit` field.</summary>
public static class IdleLimit
{
    public const string Stall = "stall";
    public const string AbsoluteMax = "absolute_max";
}

/// <summary>What a bounded LS wait timing out tells Claude. The shipped guard does NO inspection — clavity does
/// not bake a desktop/browser automation probe into the binary (spec scope §6); it SURFACES the signal and Claude
/// inspects the agy tab at runtime (e.g. via flaui-mcp). <see cref="Limit"/> distinguishes a stall from the
/// absolute-max backstop.</summary>
public sealed record ModalGuardReport(string Operation, TimeSpan Elapsed, string Hint, string Limit);

/// <summary>Invoked when a bounded LS wait times out (a possible terminal-modal hang, or the absolute-max
/// backstop). A seam: the real inspection is deferred to Claude's runtime, so the shipped impl only produces a
/// hint keyed to <paramref name="limit"/> (<see cref="IdleLimit"/>).</summary>
public interface IModalGuard
{
    ModalGuardReport OnLsTimeout(string operation, TimeSpan elapsed, string limit);
}

/// <summary>Default guard: produces a hint telling Claude what happened + which knob to turn; performs NO
/// inspection itself.</summary>
public sealed class SurfacingModalGuard : IModalGuard
{
    public ModalGuardReport OnLsTimeout(string operation, TimeSpan elapsed, string limit)
    {
        var hint = limit == IdleLimit.AbsoluteMax
            ? $"agy was still making progress on '{operation}' but exceeded the absolute wait budget ({elapsed} total). " +
              "It is NOT necessarily stuck on a modal — raise CLAVITY_AGY_IDLE_MAX_SECONDS (or set it to 0 to disable " +
              "the cap) for long reviews, or investigate a runaway if agy never stops producing steps."
            : $"no agy step progress on '{operation}' within the stall window ({elapsed} total). agy may be stuck on a " +
              "terminal modal (auth-refresh / quota / consent), OR running a single long step (a big compile / test / " +
              "subagent that emits no intermediate step) — the step-count signal cannot distinguish them. Inspect the " +
              "agy tab (e.g. with flaui-mcp); if your workload has long single steps, raise CLAVITY_AGY_IDLE_STALL_SECONDS. " +
              "Do NOT silently retry.";
        return new ModalGuardReport(operation, elapsed, hint, limit);
    }
}
```

(Do NOT run to green or commit yet — implementing `ModalGuard` breaks the `AgyView` `OnLsTimeout` call site until Step 6 restores it. That is expected inside this one atomic task; the single green + commit come at the end.)

- [ ] **Step 4: Enhance `FakeAskLs` with an invocation-driven wait plan** — in `AgyAskIntegrationTests.cs`, inside `FakeAskLs`:

  (a) Add a nested record + two fields near the top of `FakeAskLs` (after `_catalog`, line 26):

```csharp
        // A per-WaitFor-invocation script: window N (0-based, clamped to the last entry) appends AppendSteps
        // trajectory steps, then either goes idle (returns TimedOut=false with the reply) or blocks until the
        // client's per-window CancelAfter cancels it. Null => the legacy single-idleDelay behavior (back-compat).
        public sealed record WaitStep(int AppendSteps, bool GoesIdle);
        private readonly IReadOnlyList<WaitStep>? _waitPlan;
        private int _waitCalls;
        public int WaitCalls => _waitCalls;
        private int _trajectoryCalls;
        public int TrajectoryCalls => _trajectoryCalls;
        // When true, GetCascadeTrajectory throws RpcException(Unavailable) on the PROBE call (after >=1 wait window)
        // while the pre-send before-trajectory (the first call) still succeeds. Drives the F2 probe-failure test.
        private readonly bool _throwOnProbeTrajectory;
```

  (b) Extend the constructor to accept `waitPlan` — replace the constructor (lines 28-37) with:

```csharp
        public FakeAskLs(
            string cascadeId, string replyText, TimeSpan idleDelay, IEnumerable<CascadeStep> initial,
            FetchAvailableModelsResponse? catalog = null, IReadOnlyList<WaitStep>? waitPlan = null,
            bool throwOnProbeTrajectory = false)
        {
            _cascadeId = cascadeId;
            _replyText = replyText;
            _idleDelay = idleDelay;
            _steps = new List<CascadeStep>(initial);
            _catalog = catalog;
            _waitPlan = waitPlan;
            _throwOnProbeTrajectory = throwOnProbeTrajectory;
        }
```

  (c) Replace `GetCascadeTrajectory` (the existing override) with a call-counting version that can fail the PROBE. Match the existing method by its `GetCascadeTrajectoryResponse GetCascadeTrajectory(...)` signature:

```csharp
        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
        {
            // The 1st call is AskAsync's pre-send before-trajectory; later calls are per-window progress probes.
            var n = Interlocked.Increment(ref _trajectoryCalls);
            if (_throwOnProbeTrajectory && n > 1)
                throw new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "probe dead"));
            lock (_gate)
            {
                var traj = new CascadeTrajectory { CascadeId = _cascadeId };
                traj.Steps.AddRange(_steps);
                return Task.FromResult(new GetCascadeTrajectoryResponse
                {
                    Trajectory = traj,
                    NumTotalSteps = (uint)_steps.Count,
                });
            }
        }
```

  (d) Replace `WaitForConversationFullyIdle` (the existing override) with:

```csharp
        public override async Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
        {
            if (_waitPlan is null)
            {
                // Legacy behavior (back-compat for the existing tests): wait the scripted delay, then reply.
                await Task.Delay(_idleDelay, context.CancellationToken);
                lock (_gate)
                    _steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = _replyText } });
                return new WaitForConversationFullyIdleResponse { TimedOut = false };
            }

            var idx = Interlocked.Increment(ref _waitCalls) - 1;
            var step = _waitPlan[Math.Min(idx, _waitPlan.Count - 1)];
            lock (_gate)
            {
                for (var i = 0; i < step.AppendSteps; i++)
                    _steps.Add(new CascadeStep { Kind = 5, AssistantOutput = new CascadeAssistantOutput { Text = "progress" } });
                if (step.GoesIdle)
                {
                    _steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = _replyText } });
                    return new WaitForConversationFullyIdleResponse { TimedOut = false };
                }
            }
            // Never idle this window: block until the client's per-window CancelAfter cancels the call.
            await Task.Delay(Timeout.Infinite, context.CancellationToken);
            return new WaitForConversationFullyIdleResponse { TimedOut = false }; // unreachable
        }
```

- [ ] **Step 5: Write the failing integration tests** — in `AgyAskIntegrationTests.cs`, DELETE the two old timeout tests (`AskAsync_throws_TimeoutException_when_conversation_never_goes_idle` and `AskAsync_timeout_diagnostic_reports_no_agy_progress_when_it_never_moved` — locate them by name, not line number), and add these five tests (their diagnostic coverage is absorbed into the stall test):

```csharp
    [Fact]
    public async Task AskAsync_returns_reply_when_agy_progresses_across_several_stall_windows()
    {
        // The regression this whole change exists to fix: agy still advancing across windows must NOT be abandoned.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false), // window 1: +1 step, window elapses
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false), // window 2: +1 step, elapses
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),  // window 3: idle -> reply
        };
        var fake = new FakeAskLs("conv-1", "final answer", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(150),
                IdleAbsoluteMax = TimeSpan.Zero, // unbounded: prove progress alone carries the wait
            });
            var reply = await view.AskAsync("do a long thing");
            Assert.Equal("final answer", reply.Answer);
            Assert.Equal(3, fake.WaitCalls); // 2 progress windows + 1 idle
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_stalls_after_exactly_one_window_when_agy_makes_no_progress()
    {
        // F5 regression guard: a dead agy (no steps after our send) stalls at 1x the window, NOT 2x. If lastProgress
        // were seeded with `before` (not before+1), the caller's own injected user step would read as progress and
        // push the stall to a second window.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false) };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(150),
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("hello"));
            Assert.Equal(IdleLimit.Stall, ex.Report.Limit);
            Assert.Equal(1, fake.WaitCalls); // exactly ONE window
            // Absorbed diagnostic coverage from the old timeout test: agy produced nothing.
            Assert.NotNull(ex.Diagnostic);
            Assert.Equal(0, ex.Diagnostic!.NewAgySteps);
            Assert.Equal("user", ex.Diagnostic.LastStepClass);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_reports_absolute_max_when_agy_progresses_forever_past_the_budget()
    {
        // agy advances every window and never idles -> the absolute-max backstop stops it with limit=absolute_max.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false) }; // reused every window
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(100),
                IdleAbsoluteMax = TimeSpan.FromMilliseconds(250), // exhausts after ~2-3 windows
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("runaway"));
            Assert.Equal(IdleLimit.AbsoluteMax, ex.Report.Limit);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_reports_absolute_max_not_stall_when_a_budget_clamped_window_finds_no_progress()
    {
        // agy panel round 3 guard: window 1 progresses (resets the stall window), then the absolute-max budget
        // clamps window 2 to the short remainder, which elapses with NO progress. The label MUST be absolute_max
        // (the budget was the binding cap), NOT stall (which would tell the operator to raise the wrong knob).
        // This FAILS on the pre-fix code, which threw Stall unconditionally in the no-progress branch.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false), // window 1: progresses
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false), // window 2 (budget-clamped): no progress
        };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(150),
                IdleAbsoluteMax = TimeSpan.FromMilliseconds(250), // window 1 (150ms) < 250ms; window 2 clamps to the ~100ms remainder
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("progress then quit"));
            Assert.Equal(IdleLimit.AbsoluteMax, ex.Report.Limit);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_fast_idle_returns_immediately_in_one_window()
    {
        // Happy path unchanged: the server reports idle on the first window -> reply, no stall machinery.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "quick", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog }); // defaults; unused (idles immediately)
            var reply = await view.AskAsync("hi");
            Assert.Equal("quick", reply.Answer);
            Assert.Equal(1, fake.WaitCalls);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_long_single_step_stalls_with_a_hint_naming_both_modal_and_long_step()
    {
        // F4 owned-tradeoff guard: a single long step holds the step count static -> stall, same as a true modal.
        // The hint names BOTH causes; the sent message is left intact (non-destructive).
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false) };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(150),
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("compile the world"));
            Assert.Equal(IdleLimit.Stall, ex.Report.Limit);
            Assert.Contains("modal", ex.Report.Hint, StringComparison.OrdinalIgnoreCase);
            Assert.Contains("long step", ex.Report.Hint, StringComparison.OrdinalIgnoreCase);
            Assert.Equal("compile the world", fake.LastSentText);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_probe_failure_fails_toward_stall_without_a_second_trajectory_call()
    {
        // F2 (agy panel round 4): when the per-window progress probe (GetCascadeTrajectory) throws, the loop must
        // fail-toward possible_modal(stall) with a NULL diagnostic and make NO second trajectory call. The pre-fix
        // code called BuildModalHangAsync -> BuildTimeoutDiagnosticAsync -> a 2nd GetCascadeTrajectory which, on the
        // just-failed channel, would fail again and ESCAPE the loop as an uncaught RpcException -> channel_down,
        // silently violating F2. On the buggy code this test throws RpcException (not AgyModalHangException) and
        // TrajectoryCalls == 3, so it fails.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false) }; // window elapses -> probe fires
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(),
            waitPlan: plan, throwOnProbeTrajectory: true);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(120),
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("probe dies"));
            Assert.Equal(IdleLimit.Stall, ex.Report.Limit);
            Assert.Null(ex.Diagnostic);             // fail-toward stall with a null diagnostic (no 2nd network hit)
            Assert.Equal(2, fake.TrajectoryCalls);  // pre-send before-trajectory + the failing probe ONLY
        }
        finally { Directory.Delete(dir, true); }
    }
```

- [ ] **Step 6: Run the tests to verify they fail** (red for the right reason)

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter ModalGuardTests; dotnet test tests/Clavity.Integration.Tests --filter AgyAskIntegrationTests`
Expected: both FAIL to build — `ModalGuard` is not yet reimplemented and the loop is not yet implemented (`ex.Report.Limit` / `IdleLimit` / the `WaitStep` overload don't exist on the production path yet), and after Step 3 the `AgyView` `OnLsTimeout` call site is a 2-arg call that no longer compiles. This is the expected red state before the implementation steps.

- [ ] **Step 7: Implement the windowed loop** — in `AgyView.cs`, replace the `AskAsync` idle-wait block (from `using var timeoutCts = ...` through `return BoundedView.ProjectAskReply(full.CascadeId, delta);`) with:

```csharp
                await WaitForIdleWithProgressAsync(client, conversationId, before, timeout, cancellationToken);

                var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
                var delta = full.Steps.Skip(before).ToList();
                return BoundedView.ProjectAskReply(full.CascadeId, delta);
```

Then update the `AskAsync` XML doc comment so its `<paramref name="timeout"/>` sentence reads: `A client-side <paramref name="timeout"/>, when supplied, overrides the configured stall window for this call (the absolute-max backstop still comes from options).` And add these two private methods immediately after `AskAsync`, just before `BuildTimeoutDiagnosticAsync`:

```csharp
    /// <summary>Wait for agy to go idle, but do NOT abandon a wait while agy is still making progress. Loops bounded
    /// windows: each window waits for the server "fully idle" up to the stall window; if the server reports idle we
    /// return; if the window elapses (client CancelAfter) OR the server reports a wait-timeout, we probe the step
    /// count and either RESET the stall window (agy advanced) or throw possible_modal(stall). An absolute-max backstop
    /// bounds a step-producing runaway (TimeSpan.Zero => unbounded). A caller cancel propagates as cancellation,
    /// never possible_modal (F3). A per-window probe failure fails-toward possible_modal(stall), never spins (F2).</summary>
    private async Task WaitForIdleWithProgressAsync(
        LsClient client, string conversationId, int before, TimeSpan? stallOverride, CancellationToken cancellationToken)
    {
        var stallWindow = stallOverride ?? _options.IdleStallWindow;
        var absoluteMax = _options.IdleAbsoluteMax;   // TimeSpan.Zero => unbounded
        var start = DateTime.UtcNow;
        var lastProgress = before + 1;                // F5: +1 discounts our own injected Kind-14 user step.

        while (true)
        {
            var windowSecs = stallWindow;
            if (absoluteMax > TimeSpan.Zero)
            {
                var remaining = absoluteMax - (DateTime.UtcNow - start);
                if (remaining <= TimeSpan.Zero)
                    throw await BuildModalHangAsync(client, conversationId, before, start, IdleLimit.AbsoluteMax, cancellationToken);
                windowSecs = remaining < stallWindow ? remaining : stallWindow;
            }

            using var windowCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            windowCts.CancelAfter(windowSecs);
            bool serverTimedOut;
            try
            {
                serverTimedOut = await client.WaitForConversationFullyIdleAsync(
                    conversationId, IdleInactivityTimeoutSeconds, IdleStabilizationSeconds, windowCts.Token);
            }
            catch (Exception ex) when (windowCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
                && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
            {
                serverTimedOut = true; // window elapsed while agy was still active -> treat as a wait-timeout.
            }

            if (!serverTimedOut)
                return; // server reported fully idle: agy is done (happy path unchanged).

            int total;
            try
            {
                var probe = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
                total = probe.Steps.Count;
            }
            catch (RpcException)
            {
                // F2: fail-toward possible_modal(stall) WITHOUT a second network hit. BuildModalHangAsync would call
                // BuildTimeoutDiagnosticAsync -> another GetCascadeTrajectoryAsync; the channel just failed THIS
                // probe, so that retry would likely fail too and ESCAPE the loop as an uncaught RpcException ->
                // central catch -> channel_down, silently violating F2's "fail-toward possible_modal". Throw the
                // stall directly with a null diagnostic instead (agy panel round 4). The stall/absolute_max branches
                // below keep the real diagnostic: their channel is alive, so BuildTimeoutDiagnosticAsync succeeds.
                throw new AgyModalHangException(
                    _modalGuard.OnLsTimeout("WaitForConversationFullyIdle", DateTime.UtcNow - start, IdleLimit.Stall), null);
            }

            if (total > lastProgress)
                lastProgress = total; // agy advanced -> reset the stall window and keep waiting.
            else if (absoluteMax > TimeSpan.Zero && (DateTime.UtcNow - start) >= absoluteMax)
                // Honest label (agy panel round 3): if THIS window was clamped by the absolute-max budget and it
                // elapsed with no progress, the wait ended because the TOTAL budget ran out — NOT a stall. Reporting
                // Stall here would tell the operator to raise CLAVITY_AGY_IDLE_STALL_SECONDS (the wrong knob) when
                // CLAVITY_AGY_IDLE_MAX_SECONDS is the binding cap.
                throw await BuildModalHangAsync(client, conversationId, before, start, IdleLimit.AbsoluteMax, cancellationToken);
            else
                throw await BuildModalHangAsync(client, conversationId, before, start, IdleLimit.Stall, cancellationToken);
        }
    }

    private async Task<AgyModalHangException> BuildModalHangAsync(
        LsClient client, string conversationId, int before, DateTime start, string limit, CancellationToken ct)
    {
        var diag = await BuildTimeoutDiagnosticAsync(client, conversationId, before, ct);
        return new AgyModalHangException(
            _modalGuard.OnLsTimeout("WaitForConversationFullyIdle", DateTime.UtcNow - start, limit), diag);
    }
```

- [ ] **Step 8: Add `limit` to the `possible_modal` payload** — in `McpTools.cs`, in the `AgyModalHangException` catch (the `JsonSerializer.Serialize(new { status = "possible_modal", ... })` block), insert the `limit` line after `elapsedSeconds`:

```csharp
            return JsonSerializer.Serialize(new
            {
                status = "possible_modal",
                operation = ex.Report.Operation,
                elapsedSeconds = ex.Report.Elapsed.TotalSeconds,
                limit = ex.Report.Limit,
                hint = ex.Report.Hint,
                diagnostic = ex.Diagnostic,   // where agy stopped: slow tool vs hang (null if not computed).
            });
```

- [ ] **Step 9: Build + run BOTH suites to verify green**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests --filter ModalGuardTests && dotnet test tests/Clavity.Integration.Tests --filter AgyAskIntegrationTests`
Expected: `dotnet build` succeeds (the loop restored the `OnLsTimeout` call site); `ModalGuardTests` `Passed!  - Failed:     0` (2 tests); `AgyAskIntegrationTests` `Passed!  - Failed:     0` (the five new ones plus the untouched model-resolution/guidance tests).

- [ ] **Step 10: Commit** (one commit for the whole timeout fix)

```bash
git add clavity-dotnet/src/Clavity.Ls/ModalGuard.cs clavity-dotnet/src/Clavity.Ls/AgyView.cs \
        clavity-dotnet/src/Clavity.Mcp/McpTools.cs \
        clavity-dotnet/tests/Clavity.Ls.Tests/ModalGuardTests.cs \
        clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(clavity-ls): progress-extensible idle-wait (limit-aware ModalGuard + windowed loop + payload)"
```

---

## Part B — channel diagnosability

### Task B1: `ChannelDiagnostic` record + `AgyStatus` enrichment

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AskReply.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs` (create)

**Step 0 — State verification.** Confirm AskReply.cs has `TimeoutDiagnostic` (record) and `AgyStatus(string CascadeId, int TotalSteps, string State, int LastStepKind)` (4-param record). Confirm the two `new AgyStatus(...)` call sites at AgyView.cs:126,130 pass exactly 4 args. If different, STOP: `STATE_MISMATCH: <what>`. Named oracle: §0b spec F7 (the two new fields are OPTIONAL, null on healthy states, additive).

- [ ] **Step 1: Write the failing test** — `clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs`:

```csharp
using System.Text.Json;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class AgyStatusShapeTests
{
    [Fact]
    public void Healthy_AgyStatus_serializes_diagnostic_and_hint_as_null()
    {
        var json = JsonSerializer.Serialize(new AgyStatus("c", 3, "idle", 15));
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("Diagnostic").ValueKind);
        Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("Hint").ValueKind);
    }

    [Fact]
    public void Channel_down_AgyStatus_carries_the_diagnostic_and_hint()
    {
        var st = new AgyStatus("", 0, "channel_down", 0,
            new ChannelDiagnostic("Unavailable", "connection refused"), "restart the session");
        Assert.Equal("channel_down", st.State);
        Assert.Equal("Unavailable", st.Diagnostic!.StatusCode);
        Assert.Equal("restart the session", st.Hint);
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter AgyStatusShapeTests`
Expected: FAIL to compile — no `ChannelDiagnostic`; `AgyStatus` has no `Diagnostic`/`Hint`.

- [ ] **Step 3: Add the record + enrich `AgyStatus`** — in `AskReply.cs`, add `ChannelDiagnostic` after `TimeoutDiagnostic` (after line 18) and replace the `AgyStatus` record (lines 20-21):

```csharp

/// <summary>On a dead/failed clavity-ls -> agy channel: the underlying gRPC failure. StatusCode = the gRPC
/// StatusCode name (e.g. "Unavailable"), or the concrete exception type name ("ObjectDisposed"/"LsDiscovery")
/// when no RpcException is available; Detail = the failure detail/message. Never "Unknown" while a real cause
/// exists (F4).</summary>
public sealed record ChannelDiagnostic(string StatusCode, string Detail);

/// <summary>agy_status result. State = idle | working | unknown | channel_down. Diagnostic + Hint are populated
/// ONLY on channel_down (null on every healthy state; additive, so existing consumers are unaffected — F7).</summary>
public sealed record AgyStatus(
    string CascadeId, int TotalSteps, string State, int LastStepKind,
    ChannelDiagnostic? Diagnostic = null, string? Hint = null);
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests --filter AgyStatusShapeTests`
Expected: `Passed!  - Failed:     0` (2 tests). The two 4-arg `new AgyStatus(...)` call sites still compile (new params are optional).

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AskReply.cs clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs
git commit -m "feat(clavity-ls): ChannelDiagnostic record + optional AgyStatus diagnostic/hint"
```

---

### Task B2: `ChannelDown` helper + central `channel_down` catch in `RunAsync`

**Files:**
- Create: `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs`
- Modify: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs` (add a catch after the existing two)
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs` (add `ChannelDown` unit tests)
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs` (create)

**Step 0 — State verification.** Confirm `McpTools.RunAsync<T>` (McpTools.cs:34-55) catches `AgyModalHangException` then `AgyConversationPendingException` and nothing else; that `LsDiscoveryException` exists (LsDiscovery.cs:21); that `AgyView.LookAsync`/`AskAsync` call `GetCascadeTrajectoryAsync` early and un-wrapped (AgyView.cs:100,149). If different, STOP: `STATE_MISMATCH: <what>`. Named oracle: §0b spec "Central catch in RunAsync<T>" + success criteria 1 & 4.

**Shape-divergence STOP.** The new payload is exactly `{ status = "channel_down", diagnostic = <ChannelDiagnostic>, hint = <string> }`. Do not add/rename fields. If compiling forces a shape change, STOP and report.

- [ ] **Step 1: Write the failing unit tests** — append to `AgyStatusShapeTests.cs`:

```csharp
    [Fact]
    public void IsChannelDown_matches_dead_channel_exceptions_but_not_a_caller_cancel()
    {
        Assert.True(ChannelDown.IsChannelDown(new Grpc.Core.RpcException(
            new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "down"))));
        Assert.True(ChannelDown.IsChannelDown(new ObjectDisposedException("GrpcChannel")));
        Assert.True(ChannelDown.IsChannelDown(new LsDiscoveryException("agy not up")));
        // F6: a caller-cancel is NOT channel_down.
        Assert.False(ChannelDown.IsChannelDown(new Grpc.Core.RpcException(
            new Grpc.Core.Status(Grpc.Core.StatusCode.Cancelled, "cancelled"))));
        // criterion 4: an unrelated bug is NOT masked.
        Assert.False(ChannelDown.IsChannelDown(new InvalidOperationException("real bug")));
    }

    [Fact]
    public void Diagnose_unwraps_the_gRPC_status_and_never_returns_Unknown_when_a_cause_exists()
    {
        var d = ChannelDown.Diagnose(new Grpc.Core.RpcException(
            new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "connection refused")));
        Assert.Equal("Unavailable", d.StatusCode);
        Assert.Contains("connection refused", d.Detail);
    }
```

Add `using Clavity.Ls;` is already present at the top of the file (from B1). Ensure `using Grpc.Core;` is NOT required — the tests fully-qualify `Grpc.Core.*` above.

- [ ] **Step 2: Run to verify failure**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter AgyStatusShapeTests`
Expected: FAIL to compile — no `ChannelDown`.

- [ ] **Step 3: Create `ChannelDown`** — `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs`:

```csharp
using Grpc.Core;

namespace Clavity.Ls;

/// <summary>The shared diagnosis for a dead clavity-ls -> agy channel: decides whether a caught exception is a
/// channel death (<see cref="IsChannelDown"/>), unwraps the underlying gRPC cause (<see cref="Diagnose"/> — never
/// emits "Unknown" while a real RpcException is available, F4), and produces the actionable hint. Shared by
/// McpTools' central RunAsync catch and AgyView.StatusAsync so both surfaces agree.</summary>
public static class ChannelDown
{
    public const string Status = "channel_down";

    /// <summary>True if the exception is a channel death we should diagnose. Excludes a caller-cancel
    /// (RpcException StatusCode.Cancelled — F6). The AgyModelUnavailableException-wrapper clause is added in the
    /// F3 fold.</summary>
    public static bool IsChannelDown(Exception ex) =>
        (ex is RpcException rpc && rpc.StatusCode != StatusCode.Cancelled)
        || ex is ObjectDisposedException or LsDiscoveryException;

    /// <summary>Extract the diagnostic per the F4 unwrap rule: the RpcException's status; else an inner
    /// RpcException's status; else the concrete exception type name — never a bare "Unknown".</summary>
    public static ChannelDiagnostic Diagnose(Exception ex) => ex switch
    {
        RpcException rpc => new ChannelDiagnostic(rpc.StatusCode.ToString(), DetailOf(rpc)),
        { InnerException: RpcException rpc } => new ChannelDiagnostic(rpc.StatusCode.ToString(), DetailOf(rpc)),
        ObjectDisposedException => new ChannelDiagnostic("ObjectDisposed", ex.Message),
        LsDiscoveryException => new ChannelDiagnostic("LsDiscovery", ex.Message),
        _ => new ChannelDiagnostic(ex.GetType().Name, ex.Message),
    };

    // Real gRPC uses an EMPTY (not null) Status.Detail on many failures, so `?? Message` would not fire; fall back
    // to the exception Message whenever Detail is null OR empty, to keep the diagnostic from reading "[Unavailable] ".
    private static string DetailOf(RpcException rpc) =>
        string.IsNullOrEmpty(rpc.Status.Detail) ? rpc.Message : rpc.Status.Detail;

    public static string Hint(ChannelDiagnostic d) =>
        $"clavity-ls -> agy channel is down ([{d.StatusCode}] {d.Detail}). agy's language server appears to have " +
        "shut down or restarted (it does this intermittently). Restart the Claude Code session (or the clavity-ls " +
        "MCP server) to re-establish the channel. agy's own logs are at ~/.gemini/antigravity-cli/ (cli.log + " +
        "logs/clavity-<sessionId>.log) if you need to confirm the shutdown.";
}
```

- [ ] **Step 4: Add the central catch** — in `McpTools.cs`, in `RunAsync<T>`, add after the `AgyConversationPendingException` catch (after line 54):

```csharp
        catch (Exception ex) when (ChannelDown.IsChannelDown(ex))
        {
            var diag = ChannelDown.Diagnose(ex);
            return JsonSerializer.Serialize(new
            {
                status = ChannelDown.Status,
                diagnostic = diag,
                hint = ChannelDown.Hint(diag),
            });
        }
```

- [ ] **Step 5: Write the failing integration tests** — `clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs`:

```csharp
using System.Text.Json;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Clavity.Mcp;
using ModelContextProtocol.Protocol;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// Channel-diagnosability (§0b): a dead clavity-ls -> agy channel yields a structured channel_down diagnosis,
// never a bare error; agy_status never throws; a real bug is not masked; a caller-cancel is not channel_down.
public class AgyChannelDownTests
{
    // A fake whose channel is "dead": chosen RPCs throw a configurable gRPC status. GetAllCascadeTrajectories
    // succeeds (so ConnectAndResolve returns a client) unless throwOnDiscovery; GetCascadeTrajectory throws the
    // dead status (pre-flight death) unless sendThenThrowOnWait, in which case it succeeds and WaitFor throws.
    private sealed class FakeChannelDownLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly StatusCode _status;
        private readonly string _cascadeId;
        private readonly bool _throwOnDiscovery;
        private readonly bool _sendThenThrowOnWait;
        private readonly List<CascadeStep> _steps = new();

        public FakeChannelDownLs(string cascadeId, StatusCode status, bool throwOnDiscovery = false, bool sendThenThrowOnWait = false)
        { _cascadeId = cascadeId; _status = status; _throwOnDiscovery = throwOnDiscovery; _sendThenThrowOnWait = sendThenThrowOnWait; }

        private RpcException Dead() => new(new Status(_status, "channel dead"));

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            if (_throwOnDiscovery) throw Dead();
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
        {
            if (!_sendThenThrowOnWait) throw Dead(); // pre-flight death: the first ask/look/status RPC throws.
            var traj = new CascadeTrajectory { CascadeId = _cascadeId };
            lock (_steps) traj.Steps.AddRange(_steps);
            return Task.FromResult(new GetCascadeTrajectoryResponse { Trajectory = traj });
        }

        public override Task<GetAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
            => Task.FromResult(new GetAvailableModelsResponse
            {
                AvailableModels = new FetchAvailableModelsResponse
                {
                    DefaultAgentModelId = "k",
                    Models = { { "k", new ModelDetails { Model = 1042 } } },
                },
            });

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
        {
            lock (_steps)
                _steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = request.Items.Count > 0 ? request.Items[0].Text : "" } });
            return Task.FromResult(new SendUserCascadeMessageResponse());
        }

        public override Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
        {
            if (_sendThenThrowOnWait) throw Dead();
            return Task.FromResult(new WaitForConversationFullyIdleResponse { TimedOut = false });
        }
    }

    private static async Task<WebApplication> StartAsync<T>(T fake) where T : class
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(fake);
        var app = builder.Build();
        app.MapGrpcService<T>();
        await app.StartAsync();
        return app;
    }

    private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

    private static string SetUpAgyDir(int port, out string cliLog)
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-chdown-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return dir;
    }

    private static AgyView ViewFor(string cliLog) => new(new AgyViewOptions { CliLogPath = cliLog });

    [Fact]
    public async Task Dead_channel_agy_ask_returns_channel_down_not_a_bare_error()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var result = await McpTools.AgyAsk(ViewFor(cliLog), "hi");
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
            Assert.Equal("Unavailable", doc.RootElement.GetProperty("diagnostic").GetProperty("StatusCode").GetString());
            Assert.False(string.IsNullOrEmpty(doc.RootElement.GetProperty("hint").GetString()));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Dead_channel_agy_look_returns_channel_down()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var json = await McpTools.AgyLook(ViewFor(cliLog));
            using var doc = JsonDocument.Parse(json);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Mid_ask_channel_death_returns_channel_down()
    {
        // Trajectory + send succeed; the channel dies during WaitFor -> the central catch still yields channel_down.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable, sendThenThrowOnWait: true);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var result = await McpTools.AgyAsk(ViewFor(cliLog), "hi");
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_grpc_cancelled_status_is_not_reported_as_channel_down()
    {
        // F6 end-to-end (agy panel round 2, [VERDICT: REJECT] fold): a gRPC call cancelled by the outer token
        // surfaces as RpcException{StatusCode.Cancelled}. It must be EXCLUDED from channel_down and propagate as a
        // cancellation. NOTE the earlier draft pre-cancelled a local token, which threw OperationCanceledException
        // at ConnectAndResolveAsync's ThrowIfCancellationRequested BEFORE any gRPC call — trivially passing without
        // ever exercising the `rpc.StatusCode != StatusCode.Cancelled` guard. Force the guard by having the fake
        // surface a real RpcException{Cancelled} from the first RPC and asserting it propagates (NOT channel_down):
        // if the `!= StatusCode.Cancelled` exclusion were removed, IsChannelDown would return true and this would
        // instead return a channel_down AgyStatus (no throw), failing the assertion.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Cancelled); // GetCascadeTrajectory throws Cancelled
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var ex = await Assert.ThrowsAsync<RpcException>(() => McpTools.AgyStatus(ViewFor(cliLog)));
            Assert.Equal(StatusCode.Cancelled, ex.StatusCode); // propagated as a cancellation, not masked
        }
        finally { Directory.Delete(dir, true); }
    }
}
```

> **Note on the criterion-4 test:** a real (non-channel) bug is guarded deterministically by the `IsChannelDown(InvalidOperationException) == false` unit test in Step 1 (`AgyStatusShapeTests`). An end-to-end variant is deliberately omitted because a server-thrown exception always reaches the client as an `RpcException` — and a non-`Cancelled` `RpcException` (e.g. `Internal`) is BY SPEC a `channel_down` (the central `when` matches every non-`Cancelled` gRPC status). So an in-proc fake cannot produce a client-side non-`RpcException` reaching `RunAsync`; criterion 4 is about a genuine CLIENT-side exception (e.g. `NullReferenceException`) in our own code, which is not an `RpcException` and therefore is not matched — exactly what the unit test pins.

- [ ] **Step 6: Run to verify pass**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests --filter AgyStatusShapeTests && dotnet test tests/Clavity.Integration.Tests --filter AgyChannelDownTests`
Expected: `Passed!  - Failed:     0` for both filters.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/ChannelDown.cs clavity-dotnet/src/Clavity.Mcp/McpTools.cs \
        clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs \
        clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs
git commit -m "feat(clavity-ls): central channel_down catch in RunAsync + ChannelDown helper"
```

---

### Task B3: F3 — wrapped channel-death on the new-conversation model path

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyModelUnavailableException.cs` (add an inner-exception ctor)
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs:346-351` (thread the RpcException; let Cancelled propagate)
- Modify: `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs` (extend `IsChannelDown` with the wrapper clause)
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs` (add F3 discrimination unit tests)
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs` (add the new-conversation integration test)

**Step 0 — State verification.** Confirm `AgyModelUnavailableException(string message) : Exception(message)` has ONLY a message ctor (AgyModelUnavailableException.cs:9). Confirm AgyView.cs:346-351 is `catch (RpcException ex) { throw new AgyModelUnavailableException($"Could not reach agy's model catalog to pick a default...({ex.StatusCode})...", ...); }` with NO inner exception passed, and that the deprecated-model throws at :319/:348/:358 pass only a message. Confirm the existing tests `AskAsync_throws_loud_deadlock_error_when_the_conversations_model_was_removed` (AgyAskIntegrationTests.cs:468) and `AskAsync_throws_when_new_conversation_and_catalog_has_no_default` (:495) assert `AgyModelUnavailableException` with specific `.Message` substrings. If different, STOP: `STATE_MISMATCH: <what>`. Named oracle: §0b spec F3 (mechanism (i)) + F4 + F6(c)/(d).

**Design decision (pins the spec's "implementer's call"):** use **mechanism (i)** — pass the `RpcException` as the wrapper's `InnerException` and match the wrapper in the central filter. The code forces this choice's prerequisite: `AgyModelUnavailableException` currently has no inner-exception ctor, so one must be added. Mechanism (ii) [re-throw the bare RpcException] is NOT used, to keep the existing `AgyModelUnavailableException` message contract for genuine transient-catalog failures.

- [ ] **Step 1: Write the failing unit tests** — append to `AgyStatusShapeTests.cs`:

```csharp
    [Fact]
    public void IsChannelDown_matches_a_wrapped_channel_death_but_not_a_bare_model_error()
    {
        var wrappedDead = new AgyModelUnavailableException("no default",
            new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "down")));
        var wrappedCancel = new AgyModelUnavailableException("no default",
            new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Cancelled, "cancelled")));

        Assert.True(ChannelDown.IsChannelDown(wrappedDead));
        Assert.False(ChannelDown.IsChannelDown(wrappedCancel));                    // F6(c)
        Assert.False(ChannelDown.IsChannelDown(new AgyModelUnavailableException("deprecated"))); // bare model error
    }

    [Fact]
    public void Diagnose_unwraps_a_wrapped_channel_death_to_the_real_inner_status()
    {
        var wrappedDead = new AgyModelUnavailableException("no default",
            new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "down")));
        Assert.Equal("Unavailable", ChannelDown.Diagnose(wrappedDead).StatusCode); // F4: not "Unknown"
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter AgyStatusShapeTests`
Expected: FAIL to compile — `AgyModelUnavailableException` has no `(string, Exception)` ctor.

- [ ] **Step 3: Add the inner-exception ctor** — replace `clavity-dotnet/src/Clavity.Ls/AgyModelUnavailableException.cs` line 9 (the primary-constructor class) with a two-ctor class:

```csharp
public sealed class AgyModelUnavailableException : Exception
{
    public AgyModelUnavailableException(string message) : base(message) { }
    public AgyModelUnavailableException(string message, Exception? inner) : base(message, inner) { }
}
```

- [ ] **Step 4: Extend `IsChannelDown`** — in `ChannelDown.cs`, replace the `IsChannelDown` body with the wrapper-aware version:

```csharp
    public static bool IsChannelDown(Exception ex) =>
        (ex is RpcException rpc && rpc.StatusCode != StatusCode.Cancelled)
        || ex is ObjectDisposedException or LsDiscoveryException
        || (ex is AgyModelUnavailableException && ex.InnerException is
            (RpcException { StatusCode: not StatusCode.Cancelled }) or ObjectDisposedException or LsDiscoveryException);
```

- [ ] **Step 5: Thread the RpcException at the new-conversation path** — in `AgyView.cs`, inside `ResolveSendModelAsync`, locate this EXACT catch block (the one after the `Unimplemented` catch, in the new-conversation `catalog2` path) — the ANCHOR to match verbatim:

```csharp
        catch (RpcException ex)   // transient on a capable agy -> clear, non-crashing error (Spec: never crash).
        {
            throw new AgyModelUnavailableException(
                $"Could not reach agy's model catalog to pick a default for this new conversation ({ex.StatusCode}). " +
                "Retry once agy is responsive.");
        }
```

Replace it with a Cancelled-propagating split that passes the RpcException as the inner (if the anchor is not found verbatim, STOP with `STATE_MISMATCH`):

```csharp
        catch (RpcException ex) when (ex.StatusCode == StatusCode.Cancelled)
        {
            throw;   // F6(d): a caller-cancel is a cancellation, never wrapped as a model error / channel_down.
        }
        catch (RpcException ex)   // transient OR a dead channel: thread the RpcException so the central catch can
        {                         // diagnose a channel death (F3); a genuine transient stays a model-availability error.
            throw new AgyModelUnavailableException(
                $"Could not reach agy's model catalog to pick a default for this new conversation ({ex.StatusCode}). " +
                "Retry once agy is responsive.", ex);
        }
```

- [ ] **Step 6: Write the failing integration test** — in `AgyChannelDownTests.cs`, add a fake for the new-conversation path (empty trajectory, catalog RPC throws) and the test. Add the fake as a nested class:

```csharp
    // New conversation (empty trajectory -> catalog REQUIRED) whose GetAvailableModels throws a dead-channel status.
    private sealed class FakeNewConvCatalogDownLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly string _cascadeId;
        private readonly StatusCode _status;
        private readonly List<CascadeStep> _steps = new();
        public FakeNewConvCatalogDownLs(string cascadeId, StatusCode status) { _cascadeId = cascadeId; _status = status; }

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
        {
            var traj = new CascadeTrajectory { CascadeId = _cascadeId };
            lock (_steps) traj.Steps.AddRange(_steps); // empty on the first ask -> new-conversation model path
            return Task.FromResult(new GetCascadeTrajectoryResponse { Trajectory = traj });
        }

        public override Task<GetAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
            => throw new RpcException(new Status(_status, "channel dead")); // catalog RPC dies -> :346 wraps it

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
            => Task.FromResult(new SendUserCascadeMessageResponse());

        public override Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
            => Task.FromResult(new WaitForConversationFullyIdleResponse { TimedOut = false });
    }

    [Fact]
    public async Task Dead_channel_on_a_new_conversation_ask_reports_channel_down_with_the_real_inner_status()
    {
        // F3 regression guard: the dead-channel RpcException wrapped as AgyModelUnavailableException on the
        // new-conversation catalog path must STILL surface as channel_down with the REAL inner status (F4), not
        // a bare error and not "Unknown".
        var fake = new FakeNewConvCatalogDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var result = await McpTools.AgyAsk(ViewFor(cliLog), "hi");
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
            Assert.Equal("Unavailable", doc.RootElement.GetProperty("diagnostic").GetProperty("StatusCode").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }
```

- [ ] **Step 7: Run to verify pass + no regression on the existing model-error tests**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests --filter AgyStatusShapeTests && dotnet test tests/Clavity.Integration.Tests --filter "AgyChannelDownTests|AgyAskIntegrationTests"`
Expected: `Passed!  - Failed:     0`. In particular the existing `AskAsync_throws_loud_deadlock_error...` and `AskAsync_throws_when_new_conversation_and_catalog_has_no_default` still pass (those exceptions carry NO inner RpcException, so `IsChannelDown` is false and they propagate as before).

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AgyModelUnavailableException.cs clavity-dotnet/src/Clavity.Ls/AgyView.cs \
        clavity-dotnet/src/Clavity.Ls/ChannelDown.cs \
        clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs \
        clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs
git commit -m "feat(clavity-ls): diagnose a wrapped channel death on the new-conversation model path (F3)"
```

---

### Task B4: `agy_status` never-throwing local catch (F5/F7)

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs:114-132` (`StatusAsync`)
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs` (add the dead-channel `agy_status` test)

**Step 0 — State verification.** Confirm `StatusAsync` (AgyView.cs:114-132) calls `ConnectAndResolveAsync` -> `GetCascadeTrajectoryAsync` (line 119) -> optionally `ProbeIdleAsync` (line 128) with NO try/catch around them, and returns a 4-arg `AgyStatus`. Confirm `ProbeIdleAsync` (LsClient.cs:115-141) catches only `RpcException` (-> "unknown") and its own CTS cancel (-> "working"). If different, STOP: `STATE_MISMATCH: <what>`. Named oracle: §0b spec "agy_status local catch" (F5: wrap the ENTIRE body incl ProbeIdleAsync) + criterion 2 + F7.

**Testability note (read the "Two things" callout #2 at the top).** The pure "`ObjectDisposedException` FROM `ProbeIdleAsync`" path is NOT integration-simulable (a server exception reaches the client as `RpcException`, which `ProbeIdleAsync` swallows to `"unknown"`). It is guarded by (a) the `IsChannelDown(ObjectDisposedException) == true` unit test (Task B2, Step 1) and (b) this task placing the catch around the WHOLE body incl `ProbeIdleAsync` (verified by the spec-compliance reviewer against the F5 requirement). The integration test below covers the common dead-channel path where `GetCascadeTrajectory` throws (reached before `ProbeIdleAsync`).

- [ ] **Step 1: Write the failing integration test** — in `AgyChannelDownTests.cs`, add:

```csharp
    [Fact]
    public async Task Dead_channel_agy_status_returns_the_status_shape_with_channel_down_and_never_throws()
    {
        // Criterion 2 + F7: agy_status reports channel_down in its OWN AgyStatus shape (not the {status:...} error
        // envelope), never throws, and carries the diagnostic + hint.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable); // GetCascadeTrajectory throws
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var json = await McpTools.AgyStatus(ViewFor(cliLog));
            using var doc = JsonDocument.Parse(json);
            // AgyStatus shape has "State"/"Diagnostic"/"Hint"; the error envelope would have a lowercase "status".
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.False(doc.RootElement.TryGetProperty("status", out _));
            Assert.Equal("Unavailable", doc.RootElement.GetProperty("Diagnostic").GetProperty("StatusCode").GetString());
            Assert.False(string.IsNullOrEmpty(doc.RootElement.GetProperty("Hint").GetString()));
        }
        finally { Directory.Delete(dir, true); }
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests --filter AgyChannelDownTests`
Expected: FAIL — today `StatusAsync` lets the `RpcException` escape to the central `RunAsync` catch, producing the `{status:"channel_down"}` ENVELOPE (lowercase `status`), so the `Assert.False(TryGetProperty("status"))` fails.

- [ ] **Step 3: Wrap `StatusAsync` in a never-throwing local catch** — in `AgyView.cs`, replace the ENTIRE `StatusAsync` method — locate it by its signature anchor `public async Task<AgyStatus> StatusAsync(CancellationToken cancellationToken = default)` and replace from that line through its closing brace (if the signature is not found verbatim, STOP with `STATE_MISMATCH`) — with:

```csharp
    public async Task<AgyStatus> StatusAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
            using (client)
            {
                var traj = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
                var lastKind = traj.Steps.Count > 0 ? traj.Steps[^1].Kind : 0;
                // Report the REAL cascade id (traj.CascadeId), NOT the conversation id — the field is named
                // CascadeId and AskAsync fills its CascadeId from the same trajectory, so status.CascadeId now
                // string-equals ask.CascadeId and a consumer can correlate a pre-fire status with its ask.

                if (_inFlight.ContainsKey(conversationId))
                    return new AgyStatus(traj.CascadeId, traj.Steps.Count, "working", lastKind);

                var state = await client.ProbeIdleAsync(
                    conversationId, IdleInactivityTimeoutSeconds, TimeSpan.FromMilliseconds(ProbeDeadlineMs), cancellationToken);
                return new AgyStatus(traj.CascadeId, traj.Steps.Count, state, lastKind);
            }
        }
        catch (Exception ex) when (ChannelDown.IsChannelDown(ex))
        {
            // F5: the catch wraps the WHOLE body incl ProbeIdleAsync (whose internal fail-safe catches only
            // RpcException, so an ObjectDisposedException from it would otherwise escape to the central RunAsync
            // catch and return the {status:channel_down} error-envelope instead of this AgyStatus shape). A health
            // check reports health in its OWN shape and never throws (criterion 2), carrying the diagnostic+hint (F7).
            // A caller-cancel (RpcException Cancelled / OperationCanceledException) is NOT matched here -> it
            // propagates (F6); AgyConversationPendingException is NOT matched -> it flows to RunAsync's
            // waiting_for_human catch, unchanged.
            var diag = ChannelDown.Diagnose(ex);
            return new AgyStatus("", 0, ChannelDown.Status, 0, diag, ChannelDown.Hint(diag));
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Integration.Tests --filter AgyChannelDownTests`
Expected: `Passed!  - Failed:     0`. The F6 caller-cancel test from B2 still passes (a cancelled token surfaces `OperationCanceledException`, which `IsChannelDown` does not match, so it propagates).

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AgyView.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs
git commit -m "feat(clavity-ls): agy_status never-throws on a dead channel (channel_down + diagnostic)"
```

---

## Final verification

- [ ] **Full build + repo CI gate + integration suite**

Run:
```bash
cd clavity-dotnet && dotnet build && just test && dotnet test tests/Clavity.Integration.Tests
```
Expected: `dotnet build` succeeds; `just test` (= `dotnet test tests/Clavity.Ls.Tests`, the CI gate) `Passed!  - Failed:     0`; `dotnet test tests/Clavity.Integration.Tests` `Passed!  - Failed:     0`. (The Live.Acceptance project is NOT run — it needs a live agy and self-gates; `AgyAskLiveTests.cs:39`'s `timeout: 120s` now means "stall window 120s" and still compiles.)

- [ ] **Final code review** — dispatch a final reviewer over the whole range for both concerns, then proceed to `superpowers:finishing-a-development-branch`.

## AGY-CAPSTONE (after the branch is finished)

Per the standing discipline, once the implementation is committed, run a convergent agy capstone over the COMMITTED range (not the plan): send agy the diff, force `file:line` citations, VERIFY every finding by measurement before folding, re-run until a full round is GREEN. This is where the exception taxonomy (the F3/F4/F5/F6 discriminations and the real `RpcException`/`Grpc.Core` behavior) finally gets checked against the actual gRPC library rather than reasoned about on the page.

## Notes / out of scope

- Auto-recover / reconnect via `LsDiscovery` rebuild (§0b future direction).
- Submit-then-poll `agy_ask` handle model (timeout-spec future direction).
- Fixing agy's `mcp_manager.go` Close()-hang (agy-side Go).
- Renaming `possible_modal` / `waiting_for_human` status strings (compat).
- Widening the CI gate to run `tests/Clavity.Integration.Tests` (flagged above; owner's call).
