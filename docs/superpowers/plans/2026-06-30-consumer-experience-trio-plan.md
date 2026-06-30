# Consumer-Experience Trio (clavity-dotnet) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the three MCP tools a Claude uses to drive agy honest and ergonomic: `agy_ask` blocks correctly but fails with a diagnostic, returns a tripartite typed reply, and `agy_status` reports busy/idle.

**Architecture:** Contained changes to existing units — new DTOs + a pure projection in `BoundedView`, `AskAsync` returns `AskReply` and builds a `TimeoutDiagnostic` on timeout, a `CascadeId`-keyed in-flight tracker on the singleton `AgyView`, a deadline-bounded idle probe on `LsClient`, and a new `StatusAsync`. No new subsystems.

**Tech Stack:** .NET 10, C#, xunit, Grpc.AspNetCore in-proc fake LS.

**Spec (oracle):** `docs/superpowers/specs/2026-06-30-consumer-experience-trio-design.md`.

**Build / test (the repo gate — don't invent stricter flags):**
- `dotnet build -c Release`
- CI scope: `dotnet test --filter "Category!=LiveAgy"`
- One class: `dotnet test --filter "FullyQualifiedName~AskReplyProjectionTests"`
- Live: `CLAVITY_LIVE_AGY=1 CLAVITY_LIVE_CLILOG=<path> dotnet test --filter "Category=LiveAgy"`

> **STATE-VERIFICATION (Step 0 each task):** open the cited file and confirm the pasted "current" shape before editing; on mismatch report `STATE_MISMATCH` and stop. Code is on **`main`**; implement on a feature branch off main.
>
> **Integration with epic item #3 (dynamic model):** the #3 plan (`…-dynamic-send-model-resolution-plan.md`, committed) also edits `AskAsync` (send-model param + pre-send trajectory). **This trio lands first**; #3 then rebases onto the new `AskAsync`/`AskReply` shape (mechanical — its send change is independent of the reply projection). Do NOT execute both concurrently on the same branch.

---

## File Structure

**Create:**
- `src/Clavity.Ls/AskReply.cs` — the DTOs (`AskReply`, `ActivityItem`, `TimeoutDiagnostic`, `AgyStatus`) + the pure `StepKind` classifier (`Label`/`Class`).
- `tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs` — pure unit tests for the projection.
- `tests/Clavity.Live.Acceptance/AgyStatusProbeLiveTests.cs` — the probe-semantics spike.

**Modify:**
- `src/Clavity.Ls/BoundedView.cs` — add `ProjectAskReply(IReadOnlyList<CascadeStep> delta)`.
- `src/Clavity.Ls/AgyView.cs` — `AskAsync` returns `AskReply` + `TimeoutDiagnostic`; new `StatusAsync`; `CascadeId`-keyed in-flight tracker.
- `src/Clavity.Ls/LsClient.cs` — `ProbeIdleAsync(int inactivitySeconds, TimeSpan deadline)`.
- `src/Clavity.Ls/AgyModalHangException.cs` — carry an optional `TimeoutDiagnostic`.
- `src/Clavity.Mcp/McpTools.cs` — `AgyAsk` flows `AskReply`; `AgyStatus` → `StatusAsync`; `RunAsync` includes the diagnostic.
- `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` — extend `FakeAskLs`, add tests.

---

## Task 1: DTOs + kind classifier + the pure projection (no live agy)

**Files:** Create `src/Clavity.Ls/AskReply.cs`, `tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs`; Modify `src/Clavity.Ls/BoundedView.cs`.

**Current state (verify):** `BoundedView.cs` has `BoundedStep(int Kind, string? Text)`, `BoundedTrajectory(...)`, `Summarize(...)`, consts `AskBudgetChars = 32_000`, `AskMaxStepChars = 16_000`. `CascadeStep` (proto) has `Kind`, `UserInput` (Kind 14), `AssistantOutput` (Kind 15) with `.Text`.

- [ ] **Step 1: Write the failing projection tests**

Create `tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs`:

```csharp
using Clavity.Ls;
using Clavity.Ls.Proto;

namespace Clavity.Ls.Tests;

public class AskReplyProjectionTests
{
    private static CascadeStep User(string t) => new() { Kind = 14, UserInput = new CascadeUserInput { Text = t } };
    private static CascadeStep Asst(string t) => new() { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = t } };
    private static CascadeStep Tool(int kind = 90) => new() { Kind = kind };

    private static AskReply Project(params CascadeStep[] delta) =>
        BoundedView.ProjectAskReply("c", delta);

    [Fact]
    public void Trailing_assistant_step_becomes_Answer()
    {
        var r = Project(User("hi"), Asst("the answer"));
        Assert.Equal("the answer", r.Answer);
        Assert.False(r.AnswerTruncated);
        Assert.Equal(2, r.Activity.Count); // complete record
    }

    [Fact]
    public void Delta_ending_on_a_tool_step_yields_null_Answer_but_keeps_prose_in_Activity()
    {
        var r = Project(Asst("I found the bug"), Tool());
        Assert.Null(r.Answer);                                   // failure not hidden
        Assert.Contains(r.Activity, a => a.Summary == "I found the bug"); // prose preserved
    }

    [Fact]
    public void Trailing_contiguous_assistant_run_joins()
    {
        var r = Project(Tool(), Asst("part 1"), Asst("part 2"));
        Assert.Equal("part 1\npart 2", r.Answer);
    }

    [Fact]
    public void Over_cap_answer_sets_AnswerTruncated_only()
    {
        var big = new string('x', BoundedView.AskMaxStepChars + 50);
        var r = Project(Asst(big));
        Assert.True(r.AnswerTruncated);
        Assert.False(r.ActivityTruncated);
        Assert.True(r.Answer!.Length <= BoundedView.AskMaxStepChars);
    }

    [Fact]
    public void Activity_truncates_from_the_head_preserving_the_tail()
    {
        // Many activity steps with summaries; force the activity budget to drop oldest, keep newest.
        var steps = Enumerable.Range(0, 400).Select(i => User($"step-{i}-{new string('y', 200)}")).ToArray();
        var r = Project(steps);
        Assert.True(r.ActivityTruncated);
        Assert.Equal(399, r.Activity.Count == 0 ? -1 : ExtractIndex(r.Activity[^1].Summary)); // newest kept
    }

    private static int ExtractIndex(string? s) => int.Parse(s!.Split('-')[1]);

    [Fact]
    public void Labels_known_kinds_and_classifies()
    {
        Assert.Equal("user", StepKind.Class(14));
        Assert.Equal("assistant", StepKind.Class(15));
        Assert.Equal("tool", StepKind.Class(90));        // non-LLM ⇒ tool (covers spec's tool+unknown)
        Assert.Equal("step 90", StepKind.Label(90));
        Assert.Equal("user", StepKind.Label(14));
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~AskReplyProjectionTests"`
Expected: BUILD FAIL — `AskReply`, `StepKind`, `BoundedView.ProjectAskReply` undefined.

- [ ] **Step 3: Create the DTOs + classifier**

Create `src/Clavity.Ls/AskReply.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>The typed reply from agy_ask. Answer = the trailing assistant prose (null if the delta ended on a
/// non-assistant step — read Activity). Activity = the COMPLETE step record (nothing dropped), head-truncated.</summary>
public sealed record AskReply(
    string CascadeId,
    string? Answer,
    IReadOnlyList<ActivityItem> Activity,
    bool AnswerTruncated,
    bool ActivityTruncated);

/// <summary>One summarized step of the reply delta. Summary = bounded prose for assistant/user steps, else null.</summary>
public sealed record ActivityItem(int Kind, string Label, string? Summary);

/// <summary>On agy_ask timeout: where agy was. NewAgySteps discounts the injected user step; LastStepClass splits
/// a slow tool (don't abandon) from a true hang.</summary>
public sealed record TimeoutDiagnostic(
    int TotalSteps, int NewAgySteps, int LastStepKind, string LastStepClass, string? LastStepSummary);

/// <summary>agy_status result. State = idle | working | unknown.</summary>
public sealed record AgyStatus(string CascadeId, int TotalSteps, string State, int LastStepKind);

/// <summary>Maps agy step kinds to a label + a coarse class. 14=user, 15=assistant, everything else = tool
/// (the spec's "tool" + "unknown" both fail-safe to slow). Built from the captured trajectory golden.</summary>
public static class StepKind
{
    public const int UserKind = 14;
    public const int AssistantKind = 15;

    public static string Class(int kind) => kind switch
    {
        UserKind => "user",
        AssistantKind => "assistant",
        _ => "tool",
    };

    public static string Label(int kind) => kind switch
    {
        UserKind => "user",
        AssistantKind => "assistant",
        _ => $"step {kind}",
    };
}
```

- [ ] **Step 4: Add the projection to `BoundedView`**

In `src/Clavity.Ls/BoundedView.cs`, add a `const int ActivitySummaryChars = 200;` near the other consts, and this method to the `BoundedView` class:

```csharp
    /// <summary>
    /// Project a reply delta into an <see cref="AskReply"/>. Answer = the trailing CONTIGUOUS run of assistant
    /// (Kind-15) steps, joined chronologically, capped at <see cref="AskMaxStepChars"/> (Answer claims the budget
    /// FIRST). Activity = EVERY delta step summarized — head-truncated (oldest dropped) to the remaining budget so
    /// the tail (where failures surface) survives.
    /// </summary>
    public static AskReply ProjectAskReply(string cascadeId, IReadOnlyList<CascadeStep> delta)
    {
        // 1. Trailing contiguous assistant run → Answer.
        var trailing = new List<string>();
        for (var i = delta.Count - 1; i >= 0; i--)
        {
            if (delta[i].Kind != StepKind.AssistantKind) break;
            var t = delta[i].AssistantOutput?.Text;
            if (string.IsNullOrEmpty(t)) break;
            trailing.Add(t);
        }
        trailing.Reverse();
        string? answer = trailing.Count == 0 ? null : string.Join("\n", trailing);
        var answerTruncated = false;
        if (answer is not null && answer.Length > AskMaxStepChars)
        {
            answer = answer[..AskMaxStepChars];
            answerTruncated = true;
        }

        // 2. Complete activity record (every step), each summarized.
        static string? Summary(CascadeStep s)
        {
            var t = s.UserInput is { } u && u.Text.Length > 0 ? u.Text
                  : s.AssistantOutput is { } a && a.Text.Length > 0 ? a.Text
                  : null;
            return t is null ? null : t.Length > ActivitySummaryChars ? t[..ActivitySummaryChars] : t;
        }
        var all = delta.Select(s => new ActivityItem(s.Kind, StepKind.Label(s.Kind), Summary(s))).ToList();

        // 3. Activity gets the remaining budget; drop from the HEAD until it fits (preserve the tail).
        var remaining = AskBudgetChars - (answer?.Length ?? 0);
        var activityTruncated = false;
        var costs = all.Select(a => a.Summary?.Length ?? 0).ToList();
        var total = costs.Sum();
        var start = 0;
        while (total > remaining && start < all.Count)
        {
            total -= costs[start];
            start++;
            activityTruncated = true;
        }
        var activity = all.Skip(start).ToList();

        return new AskReply(cascadeId, answer, activity, answerTruncated, activityTruncated);
    }
```

- [ ] **Step 5: Run the unit tests to green**

Run: `dotnet test tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~AskReplyProjectionTests"`
Expected: PASS (6 tests).

- [ ] **Step 6: Commit**

```bash
git add src/Clavity.Ls/AskReply.cs src/Clavity.Ls/BoundedView.cs tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs
git commit -m "feat(ls): AskReply DTOs + StepKind classifier + ProjectAskReply (trailing-answer, complete head-truncated activity)"
```

---

## Task 2: `AskAsync` returns `AskReply` + the `CascadeId`-keyed in-flight tracker

**Files:** Modify `src/Clavity.Ls/AgyView.cs`, `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`.

**Current state (verify):** `AskAsync` (AgyView.cs:63-98) returns `Task<BoundedTrajectory>`; pre-send `var before = (await client.GetCascadeTrajectoryAsync(...)).Steps.Count;` (:73); send (:77); post builds `reply` + `BoundedView.Summarize(reply, …, newestFirst:true)` (:93-96).

- [ ] **Step 1: Add the in-flight tracker fields**

In `AgyView` (private members), add:

```csharp
    // CascadeId-keyed: an in-flight ask for conv A must NOT make a status check on idle conv B report "working".
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte> _inFlight = new();
```

- [ ] **Step 2: Change `AskAsync` to return `AskReply` (write the change)**

Change the signature `public async Task<BoundedTrajectory> AskAsync(` → `public async Task<AskReply> AskAsync(`. Replace the body from the pre-send block (:72-77) through the return (:93-96) so it marks in-flight, captures the delta, and projects:

```csharp
            // Step count BEFORE sending — everything appended after this index is the reply to our message.
            var before = (await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken)).Steps.Count;

            var header = _options.GoldenHeaderPath is null ? null : GoldenHeader.TryRead(_options.GoldenHeaderPath);
            var outgoing = GoldenHeader.Apply(header, message);

            _inFlight[conversationId] = 1;
            try
            {
                await client.SendUserCascadeMessageAsync(conversationId, outgoing, cancellationToken);

                using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeoutCts.CancelAfter(timeout ?? DefaultIdleWaitTimeout);
                try
                {
                    await client.WaitForConversationFullyIdleAsync(
                        conversationId, IdleInactivityTimeoutSeconds, IdleStabilizationSeconds, timeoutCts.Token);
                }
                catch (Exception ex) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
                    && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
                {
                    var diag = await BuildTimeoutDiagnosticAsync(client, conversationId, before, cancellationToken);
                    throw new AgyModalHangException(
                        _modalGuard.OnLsTimeout("WaitForConversationFullyIdle", timeout ?? DefaultIdleWaitTimeout), diag);
                }

                var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
                var delta = full.Steps.Skip(before).ToList();
                return BoundedView.ProjectAskReply(full.CascadeId, delta);
            }
            finally
            {
                _inFlight.TryRemove(conversationId, out _);
            }
```

Add the diagnostic builder method to `AgyView`:

```csharp
    private static async Task<TimeoutDiagnostic> BuildTimeoutDiagnosticAsync(
        LsClient client, string conversationId, int before, CancellationToken ct)
    {
        var full = await client.GetCascadeTrajectoryAsync(conversationId, ct);
        var total = full.Steps.Count;
        var newAgy = Math.Max(0, total - (before + 1)); // +1 discounts our injected Kind-14 user step.
        var last = total > 0 ? full.Steps[^1] : null;
        var lastKind = last?.Kind ?? 0;
        string? summary = last is null ? null
            : (last.UserInput is { } u && u.Text.Length > 0 ? u.Text
               : last.AssistantOutput is { } a && a.Text.Length > 0 ? a.Text : null);
        if (summary is { Length: > 500 } s) summary = s[..500];
        return new TimeoutDiagnostic(total, newAgy, lastKind, StepKind.Class(lastKind), summary);
    }
```

- [ ] **Step 3: Update `AgyModalHangException` to carry the diagnostic**

In `src/Clavity.Ls/AgyModalHangException.cs`, add an optional diagnostic:

```csharp
public sealed class AgyModalHangException : TimeoutException
{
    public ModalGuardReport Report { get; }
    public TimeoutDiagnostic? Diagnostic { get; }
    public AgyModalHangException(ModalGuardReport report, TimeoutDiagnostic? diagnostic = null) : base(report.Hint)
        => (Report, Diagnostic) = (report, diagnostic);
}
```

- [ ] **Step 4: Verify `McpTools.AgyAsk` still compiles (generic `RunAsync<AskReply>`)**

`RunAsync<T>` is generic and serializes `await action()`. `AgyAsk` now flows `AskReply` — no signature change needed (`RunAsync(() => view.AskAsync(...))`). Confirm at build.

- [ ] **Step 5: Update the integration tests for the new shape (write the failing test)**

In `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`, the existing tests reference `bounded.Steps` — they break with `AskReply`. Update `FakeAskLs` to carry the reply as an ASSISTANT step (so `Answer` populates), and rewrite assertions. Change the `WaitForConversationFullyIdle` override's appended step from `Kind = 15, UserInput=…` to assistant output:

```csharp
                _steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = _replyText } });
```

Rewrite the first test to the new contract:

```csharp
    [Fact]
    public async Task AskAsync_returns_answer_from_the_trailing_assistant_step()
    {
        var initial = new[] { new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "original" } } };
        var fake = new FakeAskLs("conv-1", "agy reply here", TimeSpan.FromMilliseconds(50), initial);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("please do X");
            Assert.Equal("agy reply here", reply.Answer);
            Assert.Equal("conv-1", reply.CascadeId);
            Assert.NotEmpty(reply.Activity); // includes our user step + the assistant reply
        }
        finally { Directory.Delete(dir, true); }
    }
```

Update the golden-header test (`AskAsync_prepends_golden_header_to_the_sent_message`) — it only asserts `fake.LastSentText`, so it is unaffected by the return type; leave its body, it still compiles.

- [ ] **Step 6: Run the integration tests**

Run: `dotnet test tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~AgyAskIntegrationTests"`
Expected: PASS.

- [ ] **Step 7: Full build + CI scope**

Run: `dotnet build -c Release && dotnet test --filter "Category!=LiveAgy"`
Expected: BUILD SUCCEEDED; all non-live PASS.

- [ ] **Step 8: Commit**

```bash
git add src/Clavity.Ls/AgyView.cs src/Clavity.Ls/AgyModalHangException.cs tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(ls): agy_ask returns AskReply; CascadeId-keyed in-flight tracker; timeout builds diagnostic"
```

---

## Task 3: Surface the timeout diagnostic through the MCP modal path

**Files:** Modify `src/Clavity.Mcp/McpTools.cs`, `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`.

**Current state (verify):** `McpTools.RunAsync` (:33-42) catches `AgyModalHangException` → `{ status="possible_modal", operation, elapsedSeconds, hint }`.

- [ ] **Step 1: Include the diagnostic in the modal serialization**

In `src/Clavity.Mcp/McpTools.cs`, the `catch (AgyModalHangException ex)` block, add the diagnostic:

```csharp
        catch (AgyModalHangException ex)
        {
            return JsonSerializer.Serialize(new
            {
                status = "possible_modal",
                operation = ex.Report.Operation,
                elapsedSeconds = ex.Report.Elapsed.TotalSeconds,
                hint = ex.Report.Hint,
                diagnostic = ex.Diagnostic,
            });
        }
```

- [ ] **Step 2: Write the failing diagnostic test**

In `AgyAskIntegrationTests.cs`, the existing never-idle test asserts `AgyModalHangException`. Add one asserting the diagnostic. The fake's `WaitForConversationFullyIdle` appends the reply only AFTER its delay; with a short client timeout and a long fake delay, NO new agy step exists when the timeout fires (only our injected user step) ⇒ `NewAgySteps == 0`:

```csharp
    [Fact]
    public async Task AskAsync_timeout_diagnostic_reports_silent_when_agy_never_moved()
    {
        var fake = new FakeAskLs("conv-1", "never", TimeSpan.FromSeconds(10), Array.Empty<CascadeStep>());
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(
                () => view.AskAsync("hello", timeout: TimeSpan.FromMilliseconds(200)));
            Assert.NotNull(ex.Diagnostic);
            Assert.Equal(0, ex.Diagnostic!.NewAgySteps);          // only the injected user step exists
            Assert.Equal("user", ex.Diagnostic.LastStepClass);    // last step is our Kind-14 ⇒ likely hang
        }
        finally { Directory.Delete(dir, true); }
    }
```

(The pre-existing `AskAsync_throws_TimeoutException_when_conversation_never_goes_idle` still passes — it only asserts the exception + report.)

- [ ] **Step 3: Run**

Run: `dotnet test tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~AgyAskIntegrationTests"`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/Clavity.Mcp/McpTools.cs tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(mcp): surface the agy_ask timeout diagnostic in the possible_modal result"
```

---

## Task 4: `agy_status` busy/idle (probe + fast-path)

**Files:** Modify `src/Clavity.Ls/LsClient.cs`, `src/Clavity.Ls/AgyView.cs`, `src/Clavity.Mcp/McpTools.cs`, `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`.

**Current state (verify):** `LsClient.WaitForConversationFullyIdleAsync` (:74-89). `McpTools.AgyStatus` (:16-21) returns `{ CascadeId, TotalSteps, Truncated }` from `LookAsync`.

- [ ] **Step 1: Add the deadline-bounded probe to `LsClient`**

In `src/Clavity.Ls/LsClient.cs`, after `WaitForConversationFullyIdleAsync`, add:

```csharp
    /// <summary>Probe idle/working: wait for full idle with a REALISTIC inactivity window, but bound the CALL with
    /// a short client <paramref name="deadline"/>. Returns "idle" if the wait resolves inside the deadline,
    /// "working" if the deadline cancels it first, "unknown" on any RPC error. (Spec: realistic inactivity, the
    /// deadline is the probe budget — never shrink inactivity, which would falsely read inter-step gaps as idle.)</summary>
    public async Task<string> ProbeIdleAsync(string conversationId, int inactivitySeconds, TimeSpan deadline,
        CancellationToken cancellationToken = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(deadline);
        try
        {
            await _client.WaitForConversationFullyIdleAsync(
                new WaitForConversationFullyIdleRequest
                {
                    ConversationId = conversationId,
                    InactivityTimeoutSeconds = inactivitySeconds,
                    StabilizationDurationSeconds = 0,
                },
                cancellationToken: cts.Token);
            return "idle";
        }
        catch (Exception ex) when (cts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
            && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
        {
            return "working";
        }
        catch (RpcException)
        {
            return "unknown";
        }
    }
```

- [ ] **Step 2: Add `StatusAsync` to `AgyView`**

In `src/Clavity.Ls/AgyView.cs`, add (near `LookAsync`); add `private const int ProbeDeadlineMs = 300;`:

```csharp
    /// <summary>Report agy busy/idle for the pre-fire check. Local fast-path: if THIS view has an ask in flight for
    /// the resolved conversation, return "working" without touching the network (sidesteps overlap + multi-session
    /// contamination, keyed by CascadeId). Else probe; an RPC error ⇒ "unknown" (fail-safe, never a false idle).</summary>
    public async Task<AgyStatus> StatusAsync(CancellationToken cancellationToken = default)
    {
        var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
        using (client)
        {
            var traj = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            var lastKind = traj.Steps.Count > 0 ? traj.Steps[^1].Kind : 0;

            if (_inFlight.ContainsKey(conversationId))
                return new AgyStatus(conversationId, traj.Steps.Count, "working", lastKind);

            var state = await client.ProbeIdleAsync(
                conversationId, IdleInactivityTimeoutSeconds, TimeSpan.FromMilliseconds(ProbeDeadlineMs), cancellationToken);
            return new AgyStatus(conversationId, traj.Steps.Count, state, lastKind);
        }
    }
```

- [ ] **Step 3: Point `McpTools.AgyStatus` at `StatusAsync`**

Replace `McpTools.AgyStatus` (:15-21):

```csharp
    [McpServerTool(Name = "agy_status"), Description("Report whether the active agy conversation is idle, working, or unknown (pre-fire check), plus cascade id and step count.")]
    public static async Task<string> AgyStatus(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.StatusAsync(cancellationToken));
```

- [ ] **Step 4: Make `FakeAskLs` serve the probe + write tests**

`FakeAskLs.WaitForConversationFullyIdle` already waits `_idleDelay` then returns. For an "idle" probe it must return FAST; for "working" it must outlast the 300 ms deadline. The existing `_idleDelay` controls this. Add tests:

```csharp
    [Fact]
    public async Task StatusAsync_reports_idle_when_probe_returns_fast()
    {
        var fake = new FakeAskLs("conv-1", "x", TimeSpan.Zero, Array.Empty<CascadeStep>()); // idle resolves immediately
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var st = await view.StatusAsync();
            Assert.Equal("idle", st.State);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task StatusAsync_reports_working_when_probe_outlasts_the_deadline()
    {
        var fake = new FakeAskLs("conv-1", "x", TimeSpan.FromSeconds(5), Array.Empty<CascadeStep>()); // never idle in 300ms
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var st = await view.StatusAsync();
            Assert.Equal("working", st.State);
        }
        finally { Directory.Delete(dir, true); }
    }
```

- [ ] **Step 5: Run + full CI scope**

Run: `dotnet build -c Release && dotnet test --filter "Category!=LiveAgy"`
Expected: BUILD SUCCEEDED; all non-live PASS.

- [ ] **Step 6: Commit**

```bash
git add src/Clavity.Ls/LsClient.cs src/Clavity.Ls/AgyView.cs src/Clavity.Mcp/McpTools.cs tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(ls): agy_status reports idle/working/unknown via deadline-bounded probe + CascadeId fast-path"
```

---

## Task 5: Live probe-semantics spike (LIVE-AGY) — GO/NO-GO

**Files:** Create `tests/Clavity.Live.Acceptance/AgyStatusProbeLiveTests.cs`.

**Oracle:** spec Feature 3 — confirm `WaitForConversationFullyIdle` measures inactivity from *last activity* (an idle conversation returns inside 300 ms) vs *call time* (probe unviable → ship `unknown`-only).

- [ ] **Step 1: Write the live spike (Skip-gated)**

```csharp
using Clavity.Ls;

namespace Clavity.Live.Acceptance;

// LIVE: confirms the deadline-bounded idle probe. With agy IDLE, ProbeIdleAsync must return "idle" within ~300ms.
// If it returns "working" on a known-idle agy, the RPC uses call-time semantics ⇒ NO-GO (ship unknown-only).
public class AgyStatusProbeLiveTests
{
    private static bool Enabled => Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    [Fact(Skip = "Live: set CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Probe_reports_idle_for_an_idle_agy_within_the_deadline()
    {
        Assert.True(Enabled);
        var cliLog = Environment.GetEnvironmentVariable("CLAVITY_LIVE_CLILOG")!;
        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
        var st = await view.StatusAsync();   // agy assumed idle at test time
        Assert.Equal("idle", st.State);      // NO-GO signal if this is "working"
    }
}
```

- [ ] **Step 2: Confirm excluded from CI**

Run: `dotnet test --filter "Category!=LiveAgy"`
Expected: the live test does not run; all else PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/Clavity.Live.Acceptance/AgyStatusProbeLiveTests.cs
git commit -m "test(live): agy_status probe-semantics spike (idle agy ⇒ idle within deadline)"
```

---

## Task 6: Docs + durable index

**Files:** Modify `README.md` (verify heading at Step 0); update the execution index.

- [ ] **Step 1: README note**

Add under the clavity-dotnet section:

```markdown
> **Consumer surface (agy_ask / agy_status):** `agy_ask` returns `{ Answer?, Activity[], AnswerTruncated,
> ActivityTruncated }` — `Answer` is agy's reply (absent if the turn ended on a tool/error — check `Activity`);
> on a stall it returns a `possible_modal` status with a diagnostic (slow tool vs hang). `agy_status` reports
> `idle | working | unknown` for a pre-fire check.
```

- [ ] **Step 2: Commit + update the durable execution index**

```bash
git add README.md
git commit -m "docs: document the agy_ask/agy_status consumer surface"
```

Then record the trio's completion + commit SHAs in `project_clavity-dotnet_execution.md` + the `MEMORY.md` pointer.

---

## Self-Review

**Spec coverage:** F1 block+diagnostic → Tasks 2-3 (`TimeoutDiagnostic`, modal surface); F2 typed reply → Task 1 (`ProjectAskReply`) + Task 2 (wire-through); F3 busy/idle → Task 4 (probe + fast-path) + Task 5 (spike). Backward-compat (no skill parses old shape) → no skill task needed (measured). Out-of-scope items absent. ✓

**Placeholder scan:** none — every step has complete code + exact commands. The kind-classifier collapses spec "tool"+"unknown" to `"tool"` (both fail-safe-slow) — a documented faithful simplification, not a gap. ✓

**Type consistency:** `AskReply(CascadeId, Answer?, Activity, AnswerTruncated, ActivityTruncated)`, `ActivityItem(Kind, Label, Summary?)`, `TimeoutDiagnostic(TotalSteps, NewAgySteps, LastStepKind, LastStepClass, LastStepSummary?)`, `AgyStatus(CascadeId, TotalSteps, State, LastStepKind)`, `BoundedView.ProjectAskReply(string, IReadOnlyList<CascadeStep>)`, `LsClient.ProbeIdleAsync(string, int, TimeSpan, CancellationToken)`, `AgyView.StatusAsync(CancellationToken)`, `AgyModalHangException(ModalGuardReport, TimeoutDiagnostic?)` — consistent across tasks. ✓

**Exhaustiveness audit:** contracts fully shaped; edges (null Answer, off-by-one, head-truncation, fast-path key, unknown→tool, probe NO-GO→unknown) each have a task/test; the one live dependency (probe semantics) is isolated to Task 5 with a defined NO-GO fallback (`unknown`-only). No open placeholders.
