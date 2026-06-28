using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// T4 (integration, CI): AgyView end-to-end against an in-proc fake LS — resolve convId via
// GetAllCascadeTrajectories (not disk), discover LS (synthetic cli.log naming the fake port),
// GetCascadeTrajectory -> BoundedView. Includes boot-race retry + pending tests.
public class AgyViewIntegrationTests
{
    private sealed class FakeLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly string _cascadeId;
        private int _remainingEmptyPolls;

        public FakeLs(string cascadeId, int emptyMapPolls = 0)
        {
            _cascadeId = cascadeId;
            _remainingEmptyPolls = emptyMapPolls;
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
            => Task.FromResult(new GetCascadeTrajectoryResponse
            {
                NumTotalSteps = 2,
                Trajectory = new CascadeTrajectory
                {
                    CascadeId = _cascadeId,
                    Steps =
                    {
                        new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "first" } },
                        new CascadeStep { Kind = 15 },
                    },
                },
            });
    }

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

    // Writes a throwaway cli.log naming the fake's port; returns the cli.log path. No conversations dir/.db needed.
    private static string WriteCliLog(int port)
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-agyview-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return cliLog;
    }

    [Fact]
    public async Task AgyView_looks_at_active_conversation_and_returns_bounded_view()
    {
        var fake = new FakeLs(cascadeId: "cascade-1");
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
        var bounded = await view.LookAsync();

        Assert.Equal("cascade-1", bounded.CascadeId);
        Assert.Equal(2, bounded.TotalSteps);
        Assert.Equal(2, bounded.Steps.Count);
        Assert.Equal(14, bounded.Steps[0].Kind);
        Assert.Equal("first", bounded.Steps[0].Text);
    }

    [Fact]
    public async Task LookAsync_retries_until_a_conversation_appears_then_succeeds()
    {
        // Map is empty for the first 2 polls (conversation not created yet), then non-empty.
        var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: 2);
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = cliLog,
            BootRaceTimeout = TimeSpan.FromSeconds(5),
            BootRacePollInterval = TimeSpan.FromMilliseconds(50),
        });

        var bounded = await view.LookAsync();
        Assert.Equal("cascade-1", bounded.CascadeId);
    }

    [Fact]
    public async Task LookAsync_throws_AgyConversationPendingException_when_no_conversation_within_bound()
    {
        var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: int.MaxValue); // never appears
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = cliLog,
            BootRaceTimeout = TimeSpan.FromMilliseconds(300),
            BootRacePollInterval = TimeSpan.FromMilliseconds(50),
        });

        await Assert.ThrowsAsync<AgyConversationPendingException>(() => view.LookAsync());
    }
}
