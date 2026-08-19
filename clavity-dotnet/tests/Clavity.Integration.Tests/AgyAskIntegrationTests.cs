using System.Text.Json;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Clavity.Mcp;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;

namespace Clavity.Integration.Tests;

// T7 (integration, CI): AgyView.AskAsync end-to-end against an in-proc fake LS that scripts busy -> idle.
// SendUserCascadeMessage appends a user step; WaitForConversationFullyIdle waits a scripted delay, appends the
// assistant reply, then reports idle; GetCascadeTrajectory returns the running step list. AskAsync returns the
// NEW steps (reply) bounded. NOTE: BoundedView only surfaces UserInput.Text, so the fake carries the reply text
// there (real assistant-text decode is deferred per T6 scope) — this is a test-only simplification.
public class AgyAskIntegrationTests
{
    private sealed class FakeAskLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly object _gate = new();
        private readonly List<CascadeStep> _steps;
        private readonly string _cascadeId;
        private readonly string _replyText;
        private readonly TimeSpan _idleDelay;
        private readonly FetchAvailableModelsResponse? _catalog;

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
        // Gap-3: when true, GetAvailableModels ALWAYS throws a transient RpcException(Unavailable) — regardless of
        // whether a catalog was supplied — to drive the catalog-unreachable warn-and-proceed path for a conversation
        // that already has a resolvable trajectory model.
        private readonly bool _throwCatalogUnavailable;
        // Gap-1 (idle-wait caller-cancel): signalled the instant a "never idle this window" WaitForConversationFullyIdle
        // call is genuinely BLOCKED server-side, so a test can cancel the CALLER token only once it is certain the
        // client is truly parked inside that RPC — never racing a fixed delay against cold gRPC-channel setup time.
        private readonly TaskCompletionSource _waitBlockedTcs = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task WaitBlockedSignal => _waitBlockedTcs.Task;

        public FakeAskLs(
            string cascadeId, string replyText, TimeSpan idleDelay, IEnumerable<CascadeStep> initial,
            FetchAvailableModelsResponse? catalog = null, IReadOnlyList<WaitStep>? waitPlan = null,
            bool throwOnProbeTrajectory = false, bool throwCatalogUnavailable = false)
        {
            _cascadeId = cascadeId;
            _replyText = replyText;
            _idleDelay = idleDelay;
            _steps = new List<CascadeStep>(initial);
            _catalog = catalog;
            _waitPlan = waitPlan;
            _throwOnProbeTrajectory = throwOnProbeTrajectory;
            _throwCatalogUnavailable = throwCatalogUnavailable;
        }

        public string? LastSentText { get; private set; }
        public int? LastSentModel { get; private set; }

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

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
        {
            lock (_gate)
            {
                LastSentText = request.Items.Count > 0 ? request.Items[0].Text : null;
                LastSentModel = request.CascadeConfig?.PlannerConfig?.RequestedModel?.Model;
                _steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = LastSentText ?? "" } });
            }
            return Task.FromResult(new SendUserCascadeMessageResponse());
        }

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
            _waitBlockedTcs.TrySetResult();
            await Task.Delay(Timeout.Infinite, context.CancellationToken);
            return new WaitForConversationFullyIdleResponse { TimedOut = false }; // unreachable
        }

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

        public override Task<GetAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
        {
            if (_throwCatalogUnavailable)
                throw new RpcException(new Status(StatusCode.Unavailable, "catalog down"));
            if (_catalog is null)
                throw new RpcException(new Status(StatusCode.Unimplemented, "older agy"));
            return Task.FromResult(new GetAvailableModelsResponse { AvailableModels = _catalog });
        }
    }

    private static async Task<WebApplication> StartFakeAsync(FakeAskLs fake)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(fake);
        var app = builder.Build();
        app.MapGrpcService<FakeAskLs>();
        await app.StartAsync();
        return app;
    }

    // Gap-1 (boot-race caller-cancel): GetAllCascadeTrajectories blocks INDEFINITELY (not a fixed delay) so a
    // precise CancelAfter on the caller token deterministically lands mid-call. Mirrors the pattern already used by
    // AgyViewIntegrationTests.HangingMapFakeLs (which uses a fixed 30s delay for a different assertion — a
    // sub-boot-budget wall-clock bound). This variant needs a truly indefinite block, hence the separate class.
    private sealed class HangingDiscoveryFakeLs : LanguageServerService.LanguageServerServiceBase
    {
        // Signalled the instant this handler is genuinely blocked, so the test can cancel the caller token only
        // once it is certain AskAsync is truly parked in ConnectAndResolveAsync's discovery call — never racing a
        // fixed delay against cold gRPC-channel setup time.
        private readonly TaskCompletionSource _blockedTcs = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task BlockedSignal => _blockedTcs.Task;

        public override async Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            _blockedTcs.TrySetResult();
            await Task.Delay(Timeout.Infinite, context.CancellationToken);
            return new GetAllCascadeTrajectoriesResponse(); // unreachable
        }
    }

    // Generic sibling of StartFakeAsync(FakeAskLs) for hosting a DIFFERENT fake service type (e.g.
    // HangingDiscoveryFakeLs). C# prefers the non-generic overload above when the argument IS a FakeAskLs, so
    // existing call sites are unaffected.
    private static async Task<WebApplication> StartFakeAsync<T>(T fake) where T : LanguageServerService.LanguageServerServiceBase
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
        var dir = Path.Combine(Path.GetTempPath(), "clavity-agyask-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return dir;
    }

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

            Assert.Equal("please do X", fake.LastSentText);
            Assert.Equal("agy reply here", reply.Answer);  // the trailing assistant step
            Assert.Equal("conv-1", reply.CascadeId);
            Assert.NotEmpty(reply.Activity);               // complete record: our user step + the assistant reply
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AskAsync_sends_only_the_raw_ask_and_withholds_the_golden_header_from_the_peer()
    {
        // T4b (audience split): the golden header is DRIVER guidance now, delivered via TryTakeGuidanceBlock —
        // it must never reach the peer over the wire.
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>());

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var headerFile = Path.Combine(dir, GoldenHeader.SeedFileName);
        File.WriteAllText(headerFile, "DRIVING RULE: scope to judgment");
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, GoldenHeaderDir = dir });
            await view.AskAsync("please review");

            Assert.Equal("please review", fake.LastSentText);
            Assert.DoesNotContain("DRIVING RULE: scope to judgment", fake.LastSentText);
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task Ask_withholds_the_escalation_index_from_the_peer_even_when_index_set()
    {
        // T4b (audience split): the escalation index is DRIVER guidance now (delivered via
        // TryTakeGuidanceBlock), not peer-facing content.
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>());

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var headerFile = Path.Combine(dir, GoldenHeader.SeedFileName);
        File.WriteAllText(headerFile, "SEED-BODY");
        var manualsDir = Directory.CreateTempSubdirectory().FullName;
        var manualPath = Path.Combine(manualsDir, "agy-assumptions.md");
        File.WriteAllText(manualPath, "detail");
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                GoldenHeaderDir = dir,
                EscalationIndex = EscalationIndex.Build(manualsDir),   // built once, as Program.cs does
            });
            await view.AskAsync("please review");

            Assert.Equal("please review", fake.LastSentText);
            Assert.DoesNotContain("SEED-BODY", fake.LastSentText);
            Assert.DoesNotContain(manualPath, fake.LastSentText);
            Assert.DoesNotContain("escalation index", fake.LastSentText, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            Directory.Delete(dir, true);
            Directory.Delete(manualsDir, true);
        }
    }

    [Fact]
    public async Task TryTakeGuidanceBlock_returns_the_golden_header_and_escalation_index_withheld_from_the_peer()
    {
        // T4b: everything withheld from the wire above must instead surface once to the DRIVER on this channel.
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>());

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var headerFile = Path.Combine(dir, GoldenHeader.SeedFileName);
        File.WriteAllText(headerFile, "SEED-BODY");
        var manualsDir = Directory.CreateTempSubdirectory().FullName;
        var manualPath = Path.Combine(manualsDir, "agy-assumptions.md");
        File.WriteAllText(manualPath, "detail");
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                GoldenHeaderDir = dir,
                EscalationIndex = EscalationIndex.Build(manualsDir),   // built once, as Program.cs does
            });
            await view.AskAsync("please review");

            var block = view.TryTakeGuidanceBlock();
            Assert.NotNull(block);
            Assert.StartsWith("[driver_guidance]", block);
            Assert.Contains(DriverCheatsheet.BaselineFloor, block);   // no cheatsheet file in this dir -> floor
            Assert.Contains("SEED-BODY", block);
            Assert.Contains(manualPath, block);
            Assert.Contains("escalation index", block, StringComparison.OrdinalIgnoreCase);

            // T4a composition-order pin: Contains alone does not pin ORDER. The canonical section order
            // (panel F5) is cheatsheet -> golden header (SEED+GROWTH) -> escalation index, so the header
            // (GROWTH) must precede the index (ESCALATION). Rust has no index, so this three-way order is
            // C#-only and was unpinned until here.
            var floorPos = block!.IndexOf(DriverCheatsheet.BaselineFloor, StringComparison.Ordinal);
            var headerPos = block.IndexOf("SEED-BODY", StringComparison.Ordinal);
            var indexPos = block.IndexOf("escalation index", StringComparison.OrdinalIgnoreCase);
            Assert.True(floorPos < headerPos && headerPos < indexPos,
                $"canonical order must be cheatsheet -> header -> escalation index; got floor@{floorPos} header@{headerPos} index@{indexPos}: {block}");

            Assert.Null(view.TryTakeGuidanceBlock());   // once-per-process: second call returns null.
        }
        finally
        {
            Directory.Delete(dir, true);
            Directory.Delete(manualsDir, true);
        }
    }

    // F1 (panel finding): the golden-header dir and the escalation index are INDEPENDENT toggles. An index with
    // no header dir configured must still ride to the driver — it must NOT be dropped just because there is no
    // golden-header dir to read a cheatsheet/header from. TryTakeGuidanceBlock does no network I/O, so a bogus
    // CliLogPath is fine here — neither AskAsync nor LookAsync is invoked.
    [Fact]
    public void TryTakeGuidanceBlock_survives_a_null_golden_header_dir_when_escalation_index_is_set()
    {
        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = "unused-in-this-test",
            GoldenHeaderDir = null,
            EscalationIndex = "## agy knowledge — escalation index\n- x",
        });

        var block = view.TryTakeGuidanceBlock();

        Assert.NotNull(block);
        Assert.Contains("## agy knowledge — escalation index\n- x", block);
    }

    // F1: with NEITHER source present, there is nothing to deliver, so the block stays null (and — per the
    // existing once-per-process contract — this bail-out must not itself consume the delivery gate, though that
    // is covered by the once-per-process assertion above; here we just pin the null result).
    [Fact]
    public void TryTakeGuidanceBlock_returns_null_when_neither_header_dir_nor_escalation_index_is_set()
    {
        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = "unused-in-this-test",
            GoldenHeaderDir = null,
            EscalationIndex = null,
        });

        Assert.Null(view.TryTakeGuidanceBlock());
    }

    [Fact]
    public void Driver_guidance_block_has_a_documented_inherent_bound()
    {
        // F3: no explicit total cap; the composed block is bounded because every section is. Pin the arithmetic
        // so a future per-region cap bump forces re-examination of the ~33 KiB bound instead of silently growing
        // the delivered block. cheatsheet <= DriverCheatsheet.MaxBytes; header <= GoldenHeader.MaxBytes (combined);
        // escalation index < 1 KiB by construction; warning + separators < 256 B.
        const int indexBound = 1024;
        const int warningAndSeparators = 256;
        var inherent = DriverCheatsheet.MaxBytes + GoldenHeader.MaxBytes + indexBound + warningAndSeparators;
        Assert.True(inherent <= 34 * 1024, $"driver-guidance inherent bound grew to {inherent} B; re-examine panel finding F3");
    }

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
    public async Task AskAsync_reports_liveness_once_per_elapsed_window_with_a_monotonic_value()
    {
        // The wait can outlast an MCP client's tool-call timeout, and before this it ran SILENT — the client saw
        // nothing between send and reply. This pins the observable contract of the liveness reports:
        //   1. one report per ELAPSED window (a window that goes idle produces none — nothing to report),
        //   2. Window strictly increasing, because the MCP progress contract requires the relayed value to increase
        //      and neither step count can carry that (a window with no agy activity leaves both unchanged),
        //   3. NewSteps discounting our own injected user step, so "0 new steps" means agy really did nothing.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false), // window 1 elapses: +1 step
            new FakeAskLs.WaitStep(AppendSteps: 2, GoesIdle: false), // window 2 elapses: +2 more
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),  // goes idle: NO report for this one
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
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            var progress = new CollectingProgress<AgyWaitProgress>();
            var reply = await view.AskAsync("do a long thing", progress: progress);

            Assert.Equal("final answer", reply.Answer);

            var reports = progress.Reports;
            Assert.Equal(2, reports.Count);                       // two ELAPSED windows, not three waits

            Assert.Equal(1, reports[0].Window);                   // monotonic, 1-based
            Assert.Equal(2, reports[1].Window);
            Assert.True(reports[1].Window > reports[0].Window, "Window must strictly increase for the MCP relay");

            Assert.Equal(1, reports[0].NewSteps);                 // +1, our own user step discounted
            Assert.Equal(3, reports[1].NewSteps);                 // +1 then +2, cumulative
            Assert.True(reports[1].TotalSteps > reports[0].TotalSteps);
            Assert.True(reports[1].Elapsed >= reports[0].Elapsed);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_reports_the_final_window_of_a_wait_that_is_about_to_stall()
    {
        // A stalling wait must report the window it died on — that last report is what says WHERE it stopped. If the
        // report were emitted only on the keep-waiting branch, a stall would produce zero reports and the operator
        // would learn nothing from the one case they most need to diagnose.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false) };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
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
            var progress = new CollectingProgress<AgyWaitProgress>();
            await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("stall me", progress: progress));

            var reports = progress.Reports;
            Assert.Single(reports);
            Assert.Equal(1, reports[0].Window);
            Assert.Equal(0, reports[0].NewSteps);   // agy did nothing: the +1 discount is what makes this 0, not 1
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_survives_a_progress_sink_that_throws()
    {
        // Reporting is observational. A caller whose sink throws must not thereby convert a working ask into a
        // failure — the reply is the product, the report is a courtesy.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false),
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),
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
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            var reply = await view.AskAsync("do a long thing", progress: new ThrowingProgress());
            Assert.Equal("final answer", reply.Answer);
        }
        finally { Directory.Delete(dir, true); }
    }

    private sealed class ThrowingProgress : IProgress<AgyWaitProgress>
    {
        public void Report(AgyWaitProgress value) => throw new InvalidOperationException("sink is broken");
    }

    /// <summary>Throws a cancellation the sink generated for its OWN reasons - an internal transport timeout -
    /// while the caller's token stays live. TaskCanceledException DERIVES from OperationCanceledException, which is
    /// exactly why a type-based filter got this wrong.</summary>
    private sealed class SinkTimesOutProgress : IProgress<AgyWaitProgress>
    {
        public void Report(AgyWaitProgress value) => throw new TaskCanceledException("the sink's own transport timed out");
    }

    /// <summary>Cancels the caller's token and then throws a genuine cancel WRAPPED in an AggregateException, the
    /// shape a sink produces when it bridges async with .Result/.Wait(). A type-based filter swallowed this.</summary>
    private sealed class CancelsCallerThenThrowsWrapped(CancellationTokenSource cts) : IProgress<AgyWaitProgress>
    {
        public void Report(AgyWaitProgress value)
        {
            cts.Cancel();
            throw new AggregateException(new OperationCanceledException("wrapped by a .Result bridge"));
        }
    }

    [Fact]
    public async Task AskAsync_swallows_a_sinks_OWN_cancellation_when_the_caller_did_not_cancel()
    {
        // Capstone R2: a sink whose internal transport times out throws TaskCanceledException, which DERIVES from
        // OperationCanceledException. The earlier type-based filter let that escape and failed a perfectly live ask
        // on a cancellation that never happened. Keying on the caller's token is what makes this swallowable.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false),
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),
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
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            var reply = await view.AskAsync("do a long thing", progress: new SinkTimesOutProgress());
            Assert.Equal("final answer", reply.Answer);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_does_NOT_swallow_a_sink_throw_once_the_CALLER_has_cancelled()
    {
        // Capstone R2, the other direction: when the caller HAS cancelled, nothing the sink throws may hide it -
        // including a cancel WRAPPED in an AggregateException, which is what a sink bridging async with .Result
        // produces and which the earlier type-based filter swallowed outright.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false),
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),
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
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            using var cts = new CancellationTokenSource();
            // Assert the SPECIFIC exception that must escape, never merely "something threw". A bare catch swallows
            // the sink's AggregateException and the caller's now-cancelled token makes the NEXT window throw
            // OperationCanceledException instead - so ThrowsAnyAsync<Exception> passes under BOTH the correct filter
            // and the broken one, and proves nothing. A mutation run caught exactly that: the looser assertion
            // survived a bare-catch mutant. Naming AggregateException is what makes this test able to fail.
            await Assert.ThrowsAsync<AggregateException>(() => view.AskAsync(
                "do a long thing", progress: new CancelsCallerThenThrowsWrapped(cts), cancellationToken: cts.Token));
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
            // R5 F10 guard: the diagnostic is built from the probe we already fetched — pre-send before-trajectory
            // + the one probe ONLY, no redundant third fetch (pre-F10 code did before+probe+diagnostic = 3).
            Assert.Equal(2, fake.TrajectoryCalls);
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

    [Fact]
    public async Task AskAsync_propagates_a_caller_cancel_during_the_idle_wait_never_possible_modal()
    {
        // Gap-1 (idle-wait): the fake blocks forever in WaitForConversationFullyIdle, so AskAsync is parked in
        // WaitForIdleWithProgressAsync. Cancelling the CALLER token must propagate a cancellation, not become
        // possible_modal(stall). A LONG stall window ensures the stall machinery does not fire before we cancel.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false) };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromSeconds(30),
                IdleAbsoluteMax = TimeSpan.Zero,
            });
            using var cts = new CancellationTokenSource();
            var ask = view.AskAsync("cancel me", cancellationToken: cts.Token);
            // Cancel only once the fake proves AskAsync is genuinely parked in the idle-wait RPC — never race a
            // fixed delay against cold gRPC-channel setup time (which, on a loaded machine, can itself exceed a
            // few hundred ms and would otherwise land the cancel on an EARLIER call instead of the intended one).
            await fake.WaitBlockedSignal.WaitAsync(TimeSpan.FromSeconds(10));
            cts.Cancel();
            var ex = await Record.ExceptionAsync(() => ask);
            Assert.NotNull(ex);
            Assert.IsNotType<AgyModalHangException>(ex); // NOT reclassified as possible_modal
            Assert.True(ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled }, $"unexpected: {ex}");
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_propagates_a_caller_cancel_during_the_boot_race()
    {
        // Gap-1 (boot-race / capstone F1): the fake's GetAllCascadeTrajectories blocks forever, so AskAsync is
        // parked in ConnectAndResolveAsync. Cancelling the CALLER token must propagate as a cancellation, never be
        // swallowed into channel_down/LsDiscoveryException. A LONG BootRaceTimeout keeps the boot-race deadline
        // from firing before we cancel.
        var discoveryFake = new HangingDiscoveryFakeLs();
        await using var app = await StartFakeAsync(discoveryFake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(30),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            using var cts = new CancellationTokenSource();
            var ask = view.AskAsync("cancel me", cancellationToken: cts.Token);
            // Same determinism fix as the idle-wait test above: cancel only once we're certain AskAsync is truly
            // parked in the discovery call, not racing cold gRPC-channel setup time.
            await discoveryFake.BlockedSignal.WaitAsync(TimeSpan.FromSeconds(10));
            cts.Cancel();
            var ex = await Record.ExceptionAsync(() => ask);
            Assert.NotNull(ex);
            Assert.IsNotType<AgyModalHangException>(ex);
            Assert.IsNotType<LsDiscoveryException>(ex); // must THROW a cancellation, not the channel_down cause
            Assert.True(ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled }, $"unexpected: {ex}");
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AgyAsk_serializes_the_possible_modal_payload_when_agy_stalls()
    {
        // Gap-2: McpTools.AgyAsk must serialize {status:"possible_modal", limit:"stall", hint:..., ...} when the
        // idle-wait stalls. The stall-machinery tests above call AgyView.AskAsync directly, bypassing McpTools'
        // JSON serialization entirely — this pins the actual wire shape Claude parses (a rename of status/limit
        // would break Claude's possible_modal handling loop, but would NOT fail any AgyView-level test).
        // Placed here (not McpToolsIntegrationTests.cs) because that file's FakeLs.WaitForConversationFullyIdle
        // always returns immediately (TimedOut = false) and cannot be made to stall; FakeAskLs's waitPlan can.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false) };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
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
            var result = await McpTools.AgyAsk(view, "stall me", new CollectingProgress<ProgressNotificationValue>());
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("possible_modal", doc.RootElement.GetProperty("status").GetString());
            Assert.Equal("stall", doc.RootElement.GetProperty("limit").GetString());
            Assert.False(string.IsNullOrEmpty(doc.RootElement.GetProperty("hint").GetString()));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_proceeds_with_the_trajectory_model_when_the_catalog_is_transiently_unreachable()
    {
        // Gap-3: an EXISTING conversation already has a resolvable trajectory model (source: trajectory), so the
        // catalog is consulted only for deprecation VALIDATION, not required. When GetAvailableModels throws a
        // transient/dead RpcException (Unavailable, not Unimplemented/Cancelled), ResolveSendModelAsync must WARN to
        // Diagnostics and PROCEED with the trajectory model rather than failing the ask (F2 first-block broad catch,
        // AgyView.cs ~line 436-441). Reuses the trajectory-model fake pattern from
        // AskAsync_sends_the_conversations_own_model_from_the_trajectory, with a catalog that always throws.
        var initial = new[]
        {
            new CascadeStep
            {
                Kind = 15,
                Metadata = new CortexStepMetadata { GeneratorModel = 1016 },
                UserInput = new CascadeUserInput { Text = "prior assistant turn" },
            },
        };
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), initial, throwCatalogUnavailable: true);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var diagnostics = new StringWriter();
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Diagnostics = diagnostics });
            var reply = await view.AskAsync("please do X"); // must SUCCEED despite the catalog being unreachable.

            Assert.Equal(1016, fake.LastSentModel);
            Assert.Equal("ok", reply.Answer);
            var diagText = diagnostics.ToString();
            Assert.Contains("WARNING", diagText);
            Assert.Contains("catalog", diagText);
        }
        finally { Directory.Delete(dir, true); }
    }

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

    [Fact]
    public async Task AskAsync_sends_the_conversations_own_model_from_the_trajectory()
    {
        var initial = new[]
        {
            new CascadeStep
            {
                Kind = 15,
                Metadata = new CortexStepMetadata { GeneratorModel = 1016 },
                UserInput = new CascadeUserInput { Text = "prior assistant turn" },
            },
        };
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), initial);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var diagnostics = new StringWriter();
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Diagnostics = diagnostics });
            await view.AskAsync("please do X");

            Assert.Equal(1016, fake.LastSentModel);                       // the conversation's model, not 1037.
            Assert.Contains("driving with model 1016 (source: trajectory)", diagnostics.ToString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AskAsync_falls_back_to_legacy_model_for_a_new_conversation()
    {
        // No prior model in the trajectory -> the Task-3 fallback is the legacy const (Tasks 4-6 add the default).
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>());

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var diagnostics = new StringWriter();
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Diagnostics = diagnostics });
            await view.AskAsync("hi");

            Assert.Equal(LsClient.LegacyFallbackModelId, fake.LastSentModel);
            Assert.Contains("source: legacy", diagnostics.ToString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AskAsync_uses_agy_default_for_a_new_conversation_when_catalog_is_available()
    {
        // Default key maps to 1042 (NOT LegacyFallbackModelId/1037), so a pass proves the default path ran.
        var catalog = new FetchAvailableModelsResponse { DefaultAgentModelId = "gemini-3.1-flash" };
        catalog.Models["gemini-3.1-pro-high"] = new ModelDetails { Model = 1037 };
        catalog.Models["gemini-3.1-flash"] = new ModelDetails { Model = 1042 };
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>(), catalog);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        var diagnostics = new StringWriter();
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Diagnostics = diagnostics });
            await view.AskAsync("first message");

            Assert.Equal(1042, fake.LastSentModel);                  // agy's default, resolved from the catalog.
            Assert.Contains("source: default", diagnostics.ToString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AskAsync_throws_loud_deadlock_error_when_the_conversations_model_was_removed()
    {
        // Trajectory says the conversation ran 9999, but the live catalog no longer lists it (deprecated).
        var initial = new[]
        {
            new CascadeStep { Kind = 15, Metadata = new CortexStepMetadata { GeneratorModel = 9999 } },
        };
        var catalog = new FetchAvailableModelsResponse { DefaultAgentModelId = "k" };
        catalog.Models["k"] = new ModelDetails { Model = 1037 };       // 9999 is NOT present
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), initial, catalog);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var ex = await Assert.ThrowsAsync<AgyModelUnavailableException>(() => view.AskAsync("go"));
            Assert.Contains("pick a new model AND send a message", ex.Message);
            Assert.Null(fake.LastSentModel);                          // never sent.
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AskAsync_throws_when_new_conversation_and_catalog_has_no_default()
    {
        var emptyCatalog = new FetchAvailableModelsResponse();        // reachable, but no default / no models
        var fake = new FakeAskLs("conv-1", "ok", TimeSpan.FromMilliseconds(50), Array.Empty<CascadeStep>(), emptyCatalog);

        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var ex = await Assert.ThrowsAsync<AgyModelUnavailableException>(() => view.AskAsync("go"));
            Assert.Contains("no default model", ex.Message);
            Assert.Null(fake.LastSentModel);
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
}
