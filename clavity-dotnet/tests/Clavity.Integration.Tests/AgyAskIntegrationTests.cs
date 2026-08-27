using System.IO;
using System.Text;
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
        /// <param name="ServerTimesOut">Return the server's OWN inactivity timeout immediately instead of
        /// blocking until the client's window cancels. This is a real LS behaviour - the server has its own
        /// IdleInactivityTimeoutSeconds - and it is the case that separates "the budget ran out" from "the
        /// server gave up early with budget to spare".</param>
        public sealed record WaitStep(int AppendSteps, bool GoesIdle, bool ServerTimesOut = false);
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
        // Delay applied to PROBE trajectory fetches (not the pre-send one). The limit label is decided AFTER
        // the probe returns, so this widens the window in which the budget can expire while the server - not
        // our own window timer - is what ended the wait. Without it that case cannot be constructed: the
        // clamped window always wins the race, which is exactly what an earlier probe run measured.
        private readonly TimeSpan _probeDelay;
        // Gap-1 (idle-wait caller-cancel): signalled the instant a "never idle this window" WaitForConversationFullyIdle
        // call is genuinely BLOCKED server-side, so a test can cancel the CALLER token only once it is certain the
        // client is truly parked inside that RPC — never racing a fixed delay against cold gRPC-channel setup time.
        private readonly TaskCompletionSource _waitBlockedTcs = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task WaitBlockedSignal => _waitBlockedTcs.Task;

        public FakeAskLs(
            string cascadeId, string replyText, TimeSpan idleDelay, IEnumerable<CascadeStep> initial,
            FetchAvailableModelsResponse? catalog = null, IReadOnlyList<WaitStep>? waitPlan = null,
            bool throwOnProbeTrajectory = false, bool throwCatalogUnavailable = false,
            TimeSpan probeDelay = default)
        {
            _cascadeId = cascadeId;
            _replyText = replyText;
            _idleDelay = idleDelay;
            _steps = new List<CascadeStep>(initial);
            _catalog = catalog;
            _waitPlan = waitPlan;
            _throwOnProbeTrajectory = throwOnProbeTrajectory;
            _throwCatalogUnavailable = throwCatalogUnavailable;
            _probeDelay = probeDelay;
        }

        public string? LastSentText { get; private set; }
        public int? LastSentModel { get; private set; }

        public override async Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
        {
            // The 1st call is AskAsync's pre-send before-trajectory; later calls are per-window progress probes.
            var n = Interlocked.Increment(ref _trajectoryCalls);
            if (_throwOnProbeTrajectory && n > 1)
                throw new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "probe dead"));
            if (_probeDelay > TimeSpan.Zero && n > 1)
                await Task.Delay(_probeDelay, context.CancellationToken);
            lock (_gate)
            {
                var traj = new CascadeTrajectory { CascadeId = _cascadeId };
                traj.Steps.AddRange(_steps);
                return new GetCascadeTrajectoryResponse
                {
                    Trajectory = traj,
                    NumTotalSteps = (uint)_steps.Count,
                };
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
            if (step.ServerTimesOut)
                return new WaitForConversationFullyIdleResponse { TimedOut = true };

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

    /// <summary>Write a throwaway artifact for the driver to derive an echo target from. The driver now
    /// reads the file itself, so a test that wants an echo must provide a FILE, not a string.</summary>
    private static string WriteArtifact(string dir, string content)
    {
        var path = Path.Combine(dir, "artifact-" + Guid.NewGuid().ToString("N") + ".md");
        File.WriteAllText(path, content);
        return path;
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
        // so a future per-region cap bump forces re-examination of the bound instead of silently growing the
        // delivered block. cheatsheet <= DriverCheatsheet.MaxBytes; header <= GoldenHeader.MaxBytes (combined);
        // escalation index < 1 KiB by construction; warning + separators < 256 B.
        //
        // RE-EXAMINED AND RAISED 34 KiB -> 50 KiB on 2026-08-27. This tripwire did exactly its job: raising
        // GoldenHeader.MaxBytes from 16 to 32 KiB turned it red, which is the forced re-examination, not an
        // obstacle to route around. New arithmetic: 16384 + 32768 + 1024 + 256 = 50,432 B (49.25 KiB).
        //
        // WHAT THE BOUND IS FOR, restated because the number alone does not carry it: this block is prepended
        // to EVERY ask, once per process, so the bound is the worst-case TOKEN charge on the user's agent in
        // every session — roughly 12k tokens at 50 KiB. It is not a memory-safety limit. Raise it only with a
        // measured reason, and record the reason here rather than only in a commit message.
        const int indexBound = 1024;
        const int warningAndSeparators = 256;
        var inherent = DriverCheatsheet.MaxBytes + GoldenHeader.MaxBytes + indexBound + warningAndSeparators;
        Assert.True(inherent <= 50 * 1024, $"driver-guidance inherent bound grew to {inherent} B; re-examine panel finding F3");
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
            Assert.Equal(1, reports[0].NewSteps);                 // +1, our own user step discounted
            Assert.Equal(3, reports[1].NewSteps);                 // +1 then +2, cumulative

            // TotalSteps pinned to its EXACT value, not merely to being larger than the previous one. The empty
            // initial trajectory plus our injected Kind-14 user step makes total 1, then +1 and +2 give 2 and 4.
            // A `>` comparison is satisfied by ANY increasing quantity: swapping `total` for `window` at
            // AgyView.cs:292 yields 1 and 2, still strictly increasing, so the old assertion stayed green while
            // the field reported the wrong number entirely (AGY-TEST-AUDIT gap 3).
            Assert.Equal(2, reports[0].TotalSteps);
            Assert.Equal(4, reports[1].TotalSteps);

            // Elapsed is asserted only for being POPULATED, which is the assertion that can actually fail. An
            // earlier `Elapsed >= Elapsed` comparison between two reports was removed and its removal was right -
            // Elapsed is DateTime.UtcNow - start sampled later each iteration, so that ordering held BY
            // CONSTRUCTION and no mutation could break it. This is a DIFFERENT claim: that the field carries a
            // real duration at all. Hardcoding TimeSpan.Zero at AgyView.cs:292 passed every assertion in this
            // suite before this line existed (AGY-TEST-AUDIT gap 2).
            Assert.True(reports[0].Elapsed > TimeSpan.Zero, "Elapsed must carry a real duration, not a placeholder");
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
            var sink = new ThrowingProgress();
            var reply = await view.AskAsync("do a long thing", progress: sink);
            Assert.Equal("final answer", reply.Answer);
            // Without this the test is VACUOUS: delete the report call and the sink never throws, nothing is
            // swallowed, and the assertion above still passes. Capstone R3 found exactly that.
            Assert.True(sink.Invocations > 0, "the sink must actually have been invoked for the swallow to mean anything");
        }
        finally { Directory.Delete(dir, true); }
    }

    /// <summary>Throws on every report AND counts them. The count is load-bearing: a test that only asserts the
    /// ask succeeded would pass on a build that stopped reporting entirely, because a sink that is never called
    /// never throws and nothing is swallowed. Asserting Invocations &gt; 0 is what makes it able to fail.</summary>
    private sealed class ThrowingProgress : IProgress<AgyWaitProgress>
    {
        public int Invocations;
        public void Report(AgyWaitProgress value)
        {
            Interlocked.Increment(ref Invocations);
            throw new InvalidOperationException("sink is broken");
        }
    }

    /// <summary>Throws a cancellation the sink generated for its OWN reasons - an internal transport timeout -
    /// while the caller's token stays live. TaskCanceledException DERIVES from OperationCanceledException, which is
    /// exactly why a type-based filter got this wrong.</summary>
    private sealed class SinkTimesOutProgress : IProgress<AgyWaitProgress>
    {
        public int Invocations;
        public void Report(AgyWaitProgress value)
        {
            Interlocked.Increment(ref Invocations);
            throw new TaskCanceledException("the sink's own transport timed out");
        }
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
            var sink = new SinkTimesOutProgress();
            var reply = await view.AskAsync("do a long thing", progress: sink);
            Assert.Equal("final answer", reply.Answer);
            Assert.True(sink.Invocations > 0, "the sink must actually have been invoked for the swallow to mean anything");
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_surfaces_a_CLEAN_cancellation_when_the_sink_throws_after_the_caller_cancelled()
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
            // A caller who cancels must get a CANCELLATION - never the sink's crash. The sink here cancels the
            // caller's token and then throws an AggregateException; that throw must be swallowed like any other, and
            // the cancellation must reach the caller through the loop's own linked windowCts. An earlier version of
            // this test asserted the AggregateException ESCAPED, which enforced exactly the F3 violation capstone R3
            // identified: a cancelled ask faulting with an unrelated exception instead of cancelling.
            var ex = await Record.ExceptionAsync(() => view.AskAsync(
                "do a long thing", progress: new CancelsCallerThenThrowsWrapped(cts), cancellationToken: cts.Token));

            // The shape a caller-cancel takes here is the file's ESTABLISHED one, asserted the same way the existing
            // "propagates a caller cancel" tests assert it: gRPC surfaces a cancelled call as RpcException{Cancelled}
            // wrapping an OperationCanceledException, so both forms are legitimate. Naming only one would make this
            // test brittle against which layer happens to observe the cancel first.
            Assert.NotNull(ex);
            Assert.IsNotType<AggregateException>(ex);   // the sink's throw must NOT be what reaches the caller
            Assert.True(ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled },
                $"a cancelled ask must surface a cancellation, not the sink's crash; got: {ex}");
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
                // Scaled up 5x from 100ms/250ms. The RATIO is what this test needs (a budget worth ~3 windows);
                // the MAGNITUDE is what keeps it honest on a loaded machine. `lastProbe` starts null at
                // AgyView.cs:234 and the budget check at :240-244 runs on the FIRST iteration, before any probe -
                // so if the process stalls for longer than the whole budget between AgyView.cs:232 and :242 (a GC
                // pause or thread-pool starvation on busy CI), the ask throws with a NULL diagnostic and the
                // Assert.NotNull below fails for a reason that has nothing to do with the behaviour under test.
                // At 250ms that needed only a quarter-second hiccup. This is a flake this test's OLD assertions
                // could not have: they checked only Limit, which is AbsoluteMax on that early path too.
                IdleStallWindow = TimeSpan.FromMilliseconds(500),
                IdleAbsoluteMax = TimeSpan.FromMilliseconds(1500), // exhausts after ~3 windows
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("runaway"));
            Assert.Equal(IdleLimit.AbsoluteMax, ex.Report.Limit);
            // The diagnostic is the WHOLE operator payload on a runaway: it is the only thing that says where agy
            // was when the budget killed it. The stall test above asserts all of this; this one asserted only the
            // Limit, so dropping the probe left the suite green while handing the operator a blind hang exception -
            // the one failure they most need to debug (AGY-TEST-AUDIT gap 4).
            //
            // ROUTE MATTERS: there are TWO absolute-max throws and this test reaches only ONE. agy progresses in
            // every window here, so the no-progress branch at AgyView.cs:323 is unreachable; this exits at the
            // loop-top budget check, AgyView.cs:244, which passes `lastProbe`. Measured, not assumed: mutating
            // :323 to BuildModalHang(null, ...) leaves this test GREEN, and mutating :244 turns it red. The peer
            // that found this gap cited :323 - the finding was real, the line was the wrong one of the two, and
            // the sibling route is pinned by the budget-clamped test below.
            Assert.NotNull(ex.Diagnostic);
            // The semantic INVERSE of the stall case, which pins NewAgySteps == 0 and LastStepClass "user": here
            // agy really was advancing, and the last thing it did was a Kind-5 tool step, never our own user step.
            // An exact NewAgySteps count would be timing-bound (how many 100ms windows fit a 250ms budget);
            // "agy advanced at all" is both stable and the claim that distinguishes this path from a stall.
            Assert.True(ex.Diagnostic!.NewAgySteps > 0, "a runaway advanced; 0 new steps would be the STALL case");
            Assert.Equal("tool", ex.Diagnostic.LastStepClass);
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
                // Scaled up from 150ms/250ms, keeping the ratio that MAKES this test what it is: window 1 must
                // fit inside the budget and window 2 must be clamped to the remainder. Widening only the budget -
                // the obvious-looking fix, and the one the capstone peer proposed - destroys the test: at a 2s
                // budget window 2 is no longer clamped, the no-progress branch reports Stall instead of
                // AbsoluteMax, and the assertion below fails. MEASURED, not reasoned: that exact edit turned this
                // test red while the other 61 stayed green. Scaling BOTH preserves the clamp and still buys the
                // jitter margin (see the sibling test above for why the margin matters).
                IdleStallWindow = TimeSpan.FromMilliseconds(1000),
                IdleAbsoluteMax = TimeSpan.FromMilliseconds(1500), // window 1 (1000ms) < 1500ms; window 2 clamps to the ~500ms remainder
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("progress then quit"));
            Assert.Equal(IdleLimit.AbsoluteMax, ex.Report.Limit);
            // The SECOND absolute-max route (AgyView.cs:323, the no-progress branch, which passes `probe`). Its
            // sibling above covers :244 only, and a fix applied to one route while the other kept shipping a
            // blind diagnostic is precisely the half-fix this suite keeps re-learning.
            //
            // The exact count holds because the plan is exactly two windows, so agy contributes exactly one step.
            // That is a claim about the PLAN, not an unconditional one: a stall longer than the whole budget
            // would exit at :244 before this route is reached, and then neither the count nor the route would be
            // what this test names. The widened budget above is what makes that a theoretical case rather than a
            // CI flake - the earlier version of this comment called it "deterministic" flatly, which was wrong.
            Assert.NotNull(ex.Diagnostic);
            Assert.Equal(1, ex.Diagnostic!.NewAgySteps);
            Assert.Equal("tool", ex.Diagnostic.LastStepClass);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_reports_STALL_when_a_clamped_window_is_cut_short_by_the_servers_own_timeout()
    {
        // The other half of the limit rule, and the case that makes the rule non-trivial. Window 2 IS budget-
        // clamped, but the server returns its own inactivity timeout immediately instead of the window running
        // to its end - so the budget did NOT run out and there is still time left. The honest label is Stall.
        //
        // This is what forces the label to depend on BOTH "the budget was the binding cap" AND "the window
        // actually elapsed". A fix that keyed on the clamp alone would report absolute_max here, sending the
        // operator to raise a budget that was never the thing that stopped the wait.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false),                        // window 1: progresses
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false, ServerTimesOut: true),  // window 2: server quits early
        };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(1000),
                IdleAbsoluteMax = TimeSpan.FromMilliseconds(1500), // window 2 clamps to the ~500ms remainder
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("server quits early"));
            Assert.Equal(IdleLimit.Stall, ex.Report.Limit);
            Assert.NotNull(ex.Diagnostic);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_reports_absolute_max_when_the_budget_is_GONE_even_though_the_server_ended_the_window()
    {
        // The case the clamp-and-elapsed rule gets wrong on its own. Window 2 IS budget-clamped, the SERVER
        // ends it early (so windowElapsed is false), and by the time the label is decided the budget has
        // nonetheless run out. Telling the operator "stall" here sends them to raise CLAVITY_AGY_IDLE_STALL_
        // SECONDS when the budget is the thing that is exhausted and only CLAVITY_AGY_IDLE_MAX_SECONDS can
        // help - the same mislabel, one case over.
        //
        // The 300ms probe delay is what makes this constructible at all. The label is decided AFTER the probe
        // returns, so a slow probe is what lets the budget expire while the server, not our window timer,
        // ended the wait. An earlier attempt without it measured limit=absolute_max for the wrong reason: the
        // clamped window won the race and windowElapsed was true, so the branch under test never ran.
        //
        // Arithmetic, budget 1000ms / stall window 500ms / probe delay 300ms:
        //   window 1  waits 500 (not clamped: remaining 1000 > 500), progresses, probe 300 -> elapsed ~800
        //   window 2  remaining 200 <= 500 -> CLAMPED; server returns its own timeout at once (elapsed ~800),
        //             probe 300 -> elapsed ~1100 >= 1000. Budget gone, windowElapsed false.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 1, GoesIdle: false),
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false, ServerTimesOut: true),
        };
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan,
                                 probeDelay: TimeSpan.FromMilliseconds(300));
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                IdleStallWindow = TimeSpan.FromMilliseconds(500),
                IdleAbsoluteMax = TimeSpan.FromMilliseconds(1000),
            });
            var ex = await Assert.ThrowsAsync<AgyModalHangException>(() => view.AskAsync("budget gone"));
            // Assert the PRECONDITION too, so this test cannot pass for the wrong reason: if the budget were
            // not actually exhausted at the decision, absolute_max would be the wrong answer and this would be
            // pinning a bug rather than a fix.
            Assert.True(ex.Report.Elapsed >= TimeSpan.FromMilliseconds(1000),
                $"precondition: the budget must really be gone, was {ex.Report.Elapsed.TotalMilliseconds:F0}ms");
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
    public async Task AgyAsk_relays_each_wait_report_to_the_MCP_sink_carrying_the_WINDOW_as_the_progress_value()
    {
        // The ADAPTER, which nothing pinned. McpTools.AgyAsk converts each AgyWaitProgress into the
        // ProgressNotificationValue an MCP client actually receives, and that conversion had no test at all: all
        // seven McpTools.AgyAsk call sites in this suite pass `new CollectingProgress<...>()` INLINE as a
        // throwaway and never read it back, so nothing could observe what was relayed (AGY-TEST-AUDIT gap 1).
        // Placed here rather than in McpToolsIntegrationTests.cs for the same reason the possible_modal test above
        // is: that file's FakeLs cannot be made to wait, and no wait means no progress to relay.
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
            var relayed = new CollectingProgress<ProgressNotificationValue>();
            var result = await McpTools.AgyAsk(view, "do a long thing", relayed);

            Assert.Contains("final answer", Assert.IsType<TextContentBlock>(result.Content[0]).Text);

            var reports = relayed.Reports;
            Assert.Equal(2, reports.Count);   // one per ELAPSED window; the idle one relays nothing

            // Progress carries WINDOW. This must be asserted on BOTH reports to mean anything: on the first the
            // window (1) and the new-step count (1) coincide, so one report cannot tell the two apart. The second
            // separates all three candidates - window 2, new steps 3, total steps 4 - so mapping Progress to
            // either step count at McpTools.cs:37 turns this line red. Monotonicity alone would not: all three of
            // those sequences increase, which is why the MCP "must increase" rule is not by itself evidence that
            // the right field was chosen.
            Assert.Equal(1f, reports[0].Progress);
            Assert.Equal(2f, reports[1].Progress);

            // The step counts ride in the human-readable Message, where they are informative without having to be
            // monotonic - that split is the reason Window exists as a separate field at all.
            Assert.Contains("1 new step(s)", reports[0].Message);
            Assert.Contains("3 new step(s)", reports[1].Message);
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

    [Fact]
    public async Task AskAsync_flags_TerminalTokenMissing_when_the_discipline_named_a_token_and_the_reply_lacks_it()
    {
        // The end-to-end half of the spec's demand. The unit test proves the oracle; this proves the WIRING
        // - that AskAsync actually consults it and surfaces the verdict on the reply.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a full review with no terminal token", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("review it", expectTerminal: "[VERDICT:");
            Assert.True(reply.TerminalTokenMissing);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_does_NOT_flag_when_the_reply_ends_with_the_expected_token()
    {
        // The passing control. Without it the row above is satisfied by a check that flags EVERYTHING.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "findings here\n\n[VERDICT: ALIGNED]", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("review it", expectTerminal: "[VERDICT:");
            Assert.False(reply.TerminalTokenMissing);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_flags_EchoMissing_when_the_reply_never_quotes_the_artifact_s_last_line()
    {
        // The plan's draft of Evaluate13b COMPUTED echoMissing and then returned a record carrying only
        // the other two flags - the echo would have shipped permanently false. Deleting the assignment
        // again is invisible to every other row, so without this pair the fix has no oracle.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "Review complete.\n\n[VERDICT: ALIGNED]", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("review it", expectEcho: "the last line of the artifact");
            Assert.True(reply.EchoMissing);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_does_NOT_flag_EchoMissing_when_the_reply_quotes_that_line()
    {
        // The passing control: without it the row above is satisfied by a check that flags everything.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "findings\n\nECHO: the last line of the artifact\n\n[VERDICT: ALIGNED]",
                                 TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("review it", expectEcho: "the last line of the artifact");
            Assert.False(reply.EchoMissing);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AgyAsk_appends_a_TRUNCATED_block_when_the_terminal_token_is_missing()
    {
        // Without this the detector is inert: the flag is set and no caller ever sees it.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a review with no token", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var result = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(), discipline: "agy-capstone");
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains(texts, t => t.Contains("[13b] TRUNCATED REPLY"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AgyAsk_appends_NO_13b_block_when_the_reply_is_complete()
    {
        // The passing control. Without it, a check that appends the warning ALWAYS satisfies the row above.
        //
        // A FULLY compliant consult now means BOTH signals were available and both were satisfied: a
        // terminal token AND an echo of the artifact's last substantive line. The consult that supplies no
        // echo target is legitimately told so (see the NO ECHO row), so this control supplies one.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "findings\n\nthe last line of the artifact\n\n[VERDICT: ALIGNED]",
                                 TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var result = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(),
                discipline: "agy-capstone",
                artifactPath: WriteArtifact(dir, "notes\nthe last line of the artifact\n"));
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.DoesNotContain(texts, t => t.Contains("[13b]"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Only_ONE_13b_block_is_emitted_when_several_verdicts_fire_at_once()
    {
        // MUTATION-AUDIT ROW. The blocks are if/else-if on purpose - a truncated reply is usually also
        // an un-echoed and a small one, and emitting all of them makes the verdicts compete for the
        // reader's attention until the operator skims past all of them. Turning the else-if into
        // independent ifs left every other row green, so the design decision had no oracle.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a review with no token", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            // BOTH deterministic verdicts fire: no terminal token AND no echo of the artifact's last line.
            var result = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(),
                discipline: "agy-capstone",
                artifactPath: WriteArtifact(dir, "notes\nthe last line of the artifact\n"));
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();

            var only = Assert.Single(texts, t => t.Contains("[13b]"));
            Assert.Contains("[13b] TRUNCATED REPLY", only);   // the STRONGEST verdict is the one shown
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_FAILED_ask_does_not_surface_the_PREVIOUS_ask_s_13b_verdict()
    {
        // CAPSTONE R1 FINDING (State Corruptor), verified and STRONGER than reported. The peer flagged
        // AgyView.LastReply as a concurrency race on a singleton - Program.cs:44 does register AgyView as
        // a singleton, so that is real. But the defect is reachable SINGLE-THREADED and needs no race at
        // all: RunAsync catches the exception and returns an error payload, while LastReply still holds
        // the PREVIOUS ask's verdicts - so a failed ask reports a truncation verdict about a reply that
        // does not exist. A deterministic control beats a timing-dependent one.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),    // ask 1 succeeds, and is FLAGGED
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: false),   // ask 2 stalls -> modal hang
        };
        var fake = new FakeAskLs("conv-1", "a review with no token", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
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

            var first = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(), discipline: "agy-capstone");
            var firstTexts = first.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains(firstTexts, t => t.Contains("[13b] TRUNCATED REPLY"));   // precondition

            var second = await McpTools.AgyAsk(view, "review it again",
                new CollectingProgress<ProgressNotificationValue>(), discipline: "agy-capstone");
            var secondTexts = second.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            // ASSERT NO VERDICT, not "no 13b block at all". A verdict is a claim ABOUT A REPLY, and the
            // second ask produced none, so none of the three may appear. NO ECHO is a fact about the ASK
            // and is legitimately present either way - blanket-asserting its absence would pin an
            // unrelated design into this row and break it the next time a notice is added.
            Assert.DoesNotContain(secondTexts, t => t.Contains("TRUNCATED REPLY"));
            Assert.DoesNotContain(secondTexts, t => t.Contains("ECHO MISSING"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AgyAsk_warns_ECHO_WEAK_when_the_echo_target_cannot_discriminate()
    {
        // CAPSTONE R1 fold, re-pointed by the R8 trim. The driver now READS the artifact, so the weak
        // case is a weak FILE rather than a weak string a caller typed: a source file whose tail is all
        // punctuation yields no line that could prove anything. Silently skipping would leave the
        // operator believing the check ran.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a review", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var weak = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(),
                discipline: "agy-capstone", artifactPath: WriteArtifact(dir, "}\n```\n---\n"));
            var weakTexts = weak.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains(weakTexts, t => t.Contains("[13b] ECHO WEAK"));
            // And it must NOT also be reported as a missing echo - the target is the problem, not the peer.
            Assert.DoesNotContain(weakTexts, t => t.Contains("[13b] ECHO MISSING"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AgyAsk_does_NOT_warn_ECHO_WEAK_for_a_substantive_target()
    {
        // The passing control: without it a predicate that calls every target weak satisfies the row above
        // and disables the echo check everywhere while looking diligent.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a review", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var ok = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(),
                discipline: "agy-capstone",
                artifactPath: WriteArtifact(dir, "notes\nthe last line of the artifact\n"));
            var okTexts = ok.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.DoesNotContain(okTexts, t => t.Contains("[13b] ECHO WEAK"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_discipline_consult_that_OMITS_the_echo_target_is_told_so()
    {
        // CAPSTONE R2 FINDING (Mechanism Gamer), verified: the ECHO WEAK guard only fired when expectEcho
        // was NON-NULL, so an agent that simply omitted the parameter bypassed the strongest signal in
        // total silence. That is the same fail-open shape the UNCHECKED notice was created to close for
        // `discipline` - a guard you can skip by not talking to it. Omission stays LEGAL (a design
        // question has no artifact to echo); it just stops being invisible.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "findings\n\n[VERDICT: ALIGNED]", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var result = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(), discipline: "agy-capstone");
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains(texts, t => t.Contains("[13b] NO ECHO"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AgyAsk_appends_UNCHECKED_when_no_discipline_is_named()
    {
        // The loud-omission block gets its OWN oracle rather than being observed incidentally by an
        // unrelated guidance row. A caller that names no discipline must be TOLD the checks did not run -
        // a check that was never turned on, and said nothing about it, is the same failure as one that
        // can be turned off.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "an ordinary answer", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var result = await McpTools.AgyAsk(view, "hello",
                new CollectingProgress<ProgressNotificationValue>());
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            var notice = Assert.Single(texts, t => t.Contains("[13b] UNCHECKED"));
            // It must NAME the disciplines, or the operator cannot act on it.
            Assert.Contains("adversarial-panel-review", notice);
            Assert.Contains("agy-capstone", notice);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task The_UNCHECKED_notice_is_shown_ONCE_per_session_not_on_every_ask()
    {
        // R8 TRIM. Every other UNCHECKED row builds a FRESH AgyView, so none of them can see a latch at
        // all - the change would have shipped untested, which is the exact vacuity this review kept
        // finding. agy_ask serves ordinary questions too, and a block on every one of those is how an
        // operator learns to skip [13b] entirely.
        var plan = new[]
        {
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),
            new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true),
        };
        var fake = new FakeAskLs("conv-1", "an ordinary answer", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });

            var first = await McpTools.AgyAsk(view, "hello",
                new CollectingProgress<ProgressNotificationValue>());
            Assert.Contains(first.Content.OfType<TextContentBlock>().Select(b => b.Text),
                            t => t.Contains("[13b] UNCHECKED"));

            var second = await McpTools.AgyAsk(view, "hello again",
                new CollectingProgress<ProgressNotificationValue>());
            Assert.DoesNotContain(second.Content.OfType<TextContentBlock>().Select(b => b.Text),
                                  t => t.Contains("[13b] UNCHECKED"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task An_UNKNOWN_discipline_is_reported_UNCHECKED_rather_than_silently_accepted()
    {
        // A mistyped discipline is the realistic failure - "agy_capstone", "capstone", a stale name. It
        // must not look identical to a clean consult, which is exactly what returning a guessed token
        // would produce.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a review with no token", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var result = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(), discipline: "agy_capstone");
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains(texts, t => t.Contains("[13b] UNCHECKED"));
            Assert.DoesNotContain(texts, t => t.Contains("[13b] TRUNCATED REPLY"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_with_NO_expectation_never_flags()
    {
        // Every non-discipline ask goes through this path. If it flagged, agy_ask would report truncation
        // on ordinary questions forever.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "just an answer", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("hello");
            Assert.False(reply.TerminalTokenMissing);
            Assert.False(reply.EchoMissing);
        }
        finally { Directory.Delete(dir, true); }
    }
}
