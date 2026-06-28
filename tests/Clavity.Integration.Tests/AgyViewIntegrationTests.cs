using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// T6 Beat 2 (integration, CI): AgyView end-to-end against an in-proc fake LS — locate active conversation
// (temp conversations dir) -> discover LS (synthetic cli.log naming the fake port) -> GetCascadeTrajectory
// -> BoundedView. The fake returns a fixed trajectory regardless of the requested cascade id.
public class AgyViewIntegrationTests
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
    public async Task AgyView_looks_at_active_conversation_and_returns_bounded_view()
    {
        var traj = new GetCascadeTrajectoryResponse
        {
            NumTotalSteps = 2,
            Trajectory = new CascadeTrajectory
            {
                CascadeId = "cascade-1",
                Steps =
                {
                    new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "first" } },
                    new CascadeStep { Kind = 15 },
                },
            },
        };

        await using var app = await StartFakeAsync(traj);
        var port = PortOf(app);

        var dir = Path.Combine(Path.GetTempPath(), "clavity-agyview-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "aaaaaaaa-0000-0000-0000-000000000000.db"), "");
            var cliLog = Path.Combine(dir, "cli.log");
            File.WriteAllText(cliLog,
                $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
                $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");

            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, ConversationsDir = dir });
            var bounded = await view.LookAsync();

            Assert.Equal("cascade-1", bounded.CascadeId);
            Assert.Equal(2, bounded.TotalSteps);
            Assert.Equal(2, bounded.Steps.Count);
            Assert.Equal(14, bounded.Steps[0].Kind);
            Assert.Equal("first", bounded.Steps[0].Text);
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }
}
