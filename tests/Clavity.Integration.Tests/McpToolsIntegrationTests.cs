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

namespace Clavity.Integration.Tests;

// T4 (integration, CI): the agy_look MCP tool over the in-proc fake LS — proves the tool delegates
// to AgyView and serializes a bounded view. (Full MCP-transport coverage is unnecessary: the tool is a thin
// wrapper; AgyView's own integration test covers discover->connect->read->bound.)
public class McpToolsIntegrationTests
{
    private sealed class FakeLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly GetCascadeTrajectoryResponse _trajectory;
        private readonly string _cascadeId;
        private int _remainingEmptyPolls;

        public FakeLs(GetCascadeTrajectoryResponse trajectory)
        {
            _trajectory = trajectory;
            _cascadeId = "cascade-1";
        }

        public FakeLs(string cascadeId, int emptyMapPolls = 0)
        {
            _cascadeId = cascadeId;
            _remainingEmptyPolls = emptyMapPolls;
            _trajectory = new GetCascadeTrajectoryResponse();
        }

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            if (_remainingEmptyPolls > 0)
            {
                _remainingEmptyPolls--; // simulate "conversation not created yet" for N polls.
            }
            else
            {
                resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
                {
                    LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
                };
            }
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(_trajectory);
    }

    private static async Task<WebApplication> StartFakeAsync(GetCascadeTrajectoryResponse traj)
        => await StartFakeAsync(new FakeLs(traj));

    private static async Task<WebApplication> StartFakeAsync(FakeLs fake)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(fake);
        var app = builder.Build();
        app.MapGrpcService<FakeLs>();
        await app.StartAsync();
        return app;
    }

    private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

    private static string WriteCliLog(int port)
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-mcptool-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return cliLog;
    }

    [Fact]
    public async Task Agy_look_tool_returns_bounded_view_json()
    {
        var traj = new GetCascadeTrajectoryResponse
        {
            NumTotalSteps = 1,
            Trajectory = new CascadeTrajectory
            {
                CascadeId = "cascade-1",
                Steps = { new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "hi" } } },
            },
        };

        await using var app = await StartFakeAsync(traj);
        var cliLog = WriteCliLog(PortOf(app));

        var dir = Path.GetDirectoryName(cliLog)!;
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var json = await McpTools.AgyLook(view);

            using var doc = JsonDocument.Parse(json);
            Assert.Equal("cascade-1", doc.RootElement.GetProperty("CascadeId").GetString());
            Assert.Equal(1, doc.RootElement.GetProperty("TotalSteps").GetInt32());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task Agy_look_tool_returns_waiting_json_when_no_conversation()
    {
        var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: int.MaxValue);
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var dir = Path.GetDirectoryName(cliLog)!;
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromMilliseconds(300),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });

            var json = await McpTools.AgyLook(view);

            using var doc = JsonDocument.Parse(json);
            Assert.Equal("waiting_for_human", doc.RootElement.GetProperty("status").GetString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
}
