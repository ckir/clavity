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
            => throw new RpcException(new Status(_status, "channel dead")); // catalog RPC dies -> wraps it

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
            => Task.FromResult(new SendUserCascadeMessageResponse());

        public override Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
            => Task.FromResult(new WaitForConversationFullyIdleResponse { TimedOut = false });
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

    // Boot-race fake: the LS is reachable-but-EMPTY on the first discovery poll (which latches reachedLsButEmpty in
    // the buggy code), then the channel DIES on every subsequent poll. Drives the capstone-R2 latch regression.
    private sealed class FakeReachedEmptyThenDeadLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _discoveryCalls;

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            // Poll 1: reachable, but no conversation yet (empty map) -> ConnectAndResolve marks reachedLsButEmpty.
            // Poll 2+: the channel is dead. (BootRaceTimeout is generous so discovery succeeds and >=1 death poll
            // follows the empty one before the deadline — the last poll before the deadline is a death.)
            if (System.Threading.Interlocked.Increment(ref _discoveryCalls) == 1)
                return Task.FromResult(new GetAllCascadeTrajectoriesResponse());
            throw new RpcException(new Status(StatusCode.Unavailable, "agy died mid-boot-race"));
        }
    }

    [Fact]
    public async Task Boot_race_reached_empty_then_dead_reports_channel_down_not_waiting_for_human()
    {
        // Capstone R2 regression: reachedLsButEmpty must reflect only the MOST RECENT poll. If the LS is reached
        // empty once and then dies, the boot-race deadline must throw LsDiscoveryException (-> channel_down /
        // "restart the session"), NOT a latched AgyConversationPendingException (-> waiting_for_human), which would
        // trap the operator waiting on a dead server. On the pre-fix (latched) code agy_status returns the
        // waiting_for_human envelope (no "State" property), so GetProperty("State") throws and this test fails.
        var fake = new FakeReachedEmptyThenDeadLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            // Fixed: reachedLsButEmpty reflects only the LAST poll (a death) -> LsDiscoveryException at the deadline
            // -> channel_down AgyStatus (Diagnostic.StatusCode "LsDiscovery"). Buggy (latched): the stale empty-poll
            // flag throws AgyConversationPendingException -> the waiting_for_human envelope (lowercase "status", no
            // "State"), so GetProperty("State") throws and the test fails RED.
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.False(doc.RootElement.TryGetProperty("status", out _)); // NOT the waiting_for_human error envelope
            Assert.Equal("LsDiscovery", doc.RootElement.GetProperty("Diagnostic").GetProperty("StatusCode").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Boot_race_never_reachable_reports_channel_down()
    {
        // Gap-4: discovery (GetAllCascadeTrajectories) NEVER succeeds -- every poll throws the dead status, so
        // ConnectAndResolveAsync never obtains a client and hits the boot-race deadline with sawChannelDeath=true,
        // throwing LsDiscoveryException -> channel_down (NOT waiting_for_human, since reachedLsButEmpty never gets
        // set when every poll dies pre-flight). A SHORT BootRaceTimeout keeps this test fast.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable, throwOnDiscovery: true);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var result = await McpTools.AgyAsk(view, "hi");
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    // Boot-race fake: a TRANSIENT death on the first discovery poll (the LS has bound the port but its gRPC
    // service is not ready yet -> Unavailable), then reachable-but-EMPTY forever (the LS is up, waiting for the
    // human to start a conversation). Drives the capstone-R3 "flapping" regression.
    private sealed class FakeTransientThenEmptyLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _discoveryCalls;

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            if (System.Threading.Interlocked.Increment(ref _discoveryCalls) == 1)
                throw new RpcException(new Status(StatusCode.Unavailable, "gRPC service still binding"));
            return Task.FromResult(new GetAllCascadeTrajectoriesResponse()); // reachable but empty -> waiting_for_human
        }
    }

    [Fact]
    public async Task Boot_race_transient_death_then_reached_empty_reports_waiting_for_human_not_channel_down()
    {
        // Capstone R3 regression: sawChannelDeath must reflect only the MOST RECENT conclusive poll, so a healthy
        // LS whose gRPC service throws a transient Unavailable while still binding (poll 1) and then comes up empty
        // (poll 2+, waiting for the human) must yield waiting_for_human -- NOT a latched channel_down. On the pre-fix
        // code sawChannelDeath latches from poll 1 and never clears, so the deadline throws LsDiscoveryException ->
        // channel_down (an AgyStatus with "State", no lowercase "status"), and GetProperty("status") throws RED.
        var fake = new FakeTransientThenEmptyLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            // waiting_for_human is the RunAsync error envelope (lowercase "status"); channel_down would be the
            // AgyStatus shape ("State"). Asserting the envelope pins that the transient death did NOT latch.
            Assert.Equal("waiting_for_human", doc.RootElement.GetProperty("status").GetString());
            Assert.False(doc.RootElement.TryGetProperty("State", out _));
        }
        finally { Directory.Delete(dir, true); }
    }
}
