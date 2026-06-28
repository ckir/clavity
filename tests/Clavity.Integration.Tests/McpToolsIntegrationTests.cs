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

// T6 Beat 2c (integration, CI): the agy_look MCP tool over the in-proc fake LS — proves the tool delegates
// to AgyView and serializes a bounded view. (Full MCP-transport coverage is unnecessary: the tool is a thin
// wrapper; AgyView's own integration test covers discover->connect->read->bound.)
public class McpToolsIntegrationTests
{
    private sealed class FakeLs(GetCascadeTrajectoryResponse trajectory)
        : LanguageServerService.LanguageServerServiceBase
    {
        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(trajectory);
    }

    private static async Task<WebApplication> StartFakeAsync(GetCascadeTrajectoryResponse traj)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(traj);
        builder.Services.AddSingleton<FakeLs>();
        var app = builder.Build();
        app.MapGrpcService<FakeLs>();
        await app.StartAsync();
        return app;
    }

    private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

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
        var port = PortOf(app);

        var dir = Path.Combine(Path.GetTempPath(), "clavity-mcptool-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "aaaaaaaa-0000-0000-0000-000000000000.db"), "");
            var cliLog = Path.Combine(dir, "cli.log");
            File.WriteAllText(cliLog,
                $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
                $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");

            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, ConversationsDir = dir });
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
}
