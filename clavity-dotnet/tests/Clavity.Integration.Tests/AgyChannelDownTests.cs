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
