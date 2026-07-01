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
// GetCascadeTrajectory -> BoundedView. Includes boot-race retry + pending + >1-conversation tiebreak tests.
public class AgyViewIntegrationTests : IDisposable
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

    // Serves TWO top-level conversations with distinct last_modified_time, and echoes the REQUESTED cascade id
    // back in the trajectory — so a test can assert WHICH conversation AgyView resolved (the most-recent one).
    private sealed class TwoConversationFakeLs : LanguageServerService.LanguageServerServiceBase
    {
        public const string OlderId = "older-conversation";
        public const string NewerId = "newer-conversation";

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries[OlderId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
                    new DateTimeOffset(2026, 6, 27, 0, 0, 0, TimeSpan.Zero)),
            };
            resp.TrajectorySummaries[NewerId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
                    new DateTimeOffset(2026, 6, 28, 0, 0, 0, TimeSpan.Zero)),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(new GetCascadeTrajectoryResponse
            {
                NumTotalSteps = 1,
                Trajectory = new CascadeTrajectory
                {
                    CascadeId = request.CascadeId, // echo the id AgyView asked for
                    Steps = { new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "x" } } },
                },
            });
    }

    // A peer whose LS connects but whose GetAllCascadeTrajectories never answers — the connected-but-hung case.
    private sealed class HangingMapFakeLs : LanguageServerService.LanguageServerServiceBase
    {
        public override async Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            await Task.Delay(TimeSpan.FromSeconds(30), context.CancellationToken); // far past any boot budget
            return new GetAllCascadeTrajectoriesResponse();
        }
    }

    private static async Task<WebApplication> StartFakeAsync<T>(T fake)
        where T : LanguageServerService.LanguageServerServiceBase
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

    private readonly List<string> _tempDirs = new();

    // Writes a throwaway cli.log naming the fake's port; returns the cli.log path. No conversations dir/.db needed.
    // The temp dir is tracked and removed in Dispose so test runs don't accumulate directories.
    private string WriteCliLog(int port)
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-agyview-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        _tempDirs.Add(dir);
        var cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return cliLog;
    }

    public void Dispose()
    {
        foreach (var dir in _tempDirs)
        {
            try { Directory.Delete(dir, true); }
            catch (IOException) { /* best-effort cleanup */ }
        }
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
            // Realistic budget: the boot call is now deadline-bounded (finding B), so a small budget would
            // deadline-kill the cold-channel call (a fresh channel is built per poll) before it returns the empty
            // map. 5s gives ample margin over cold establishment, so the "reachable-but-empty → pending" path is
            // what's actually exercised (the default-budget test proves establishment is well under that).
            BootRaceTimeout = TimeSpan.FromSeconds(5),
            BootRacePollInterval = TimeSpan.FromMilliseconds(50),
        });

        await Assert.ThrowsAsync<AgyConversationPendingException>(() => view.LookAsync());
    }

    [Fact]
    public async Task LookAsync_honors_the_boot_race_budget_when_GetAllCascadeTrajectories_hangs()
    {
        // Round-3 finding B: a connected-but-hung peer must not block on the client's 30s default deadline —
        // the boot race bounds the call to its OWN (shorter) remaining budget and fails within it.
        await using var app = await StartFakeAsync(new HangingMapFakeLs());
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions
        {
            CliLogPath = cliLog,
            // Budget large enough to establish the channel + reach the hanging handler, so the bound (not an
            // establishment failure) is what ends the call.
            BootRaceTimeout = TimeSpan.FromSeconds(5),
            BootRacePollInterval = TimeSpan.FromMilliseconds(50),
        });

        var sw = System.Diagnostics.Stopwatch.StartNew();
        await Assert.ThrowsAsync<LsDiscoveryException>(() => view.LookAsync());
        sw.Stop();
        // Pre-fix this blocks ~30s (the call's own deadline); the fix bounds it to ~the boot budget. The <12s
        // threshold sits well below 30s so it fails only if the deadline bound is missing.
        Assert.True(sw.Elapsed < TimeSpan.FromSeconds(12), $"boot race must fail within ~its budget, took {sw.Elapsed}");
    }

    [Fact]
    public async Task LookAsync_resolves_the_most_recently_modified_conversation_when_more_than_one()
    {
        // Two top-level conversations; AgyView must pick the one with the later last_modified_time (maps are
        // UNORDERED on the wire, so this guards against relying on iteration order — spec §6).
        await using var app = await StartFakeAsync(new TwoConversationFakeLs());
        var cliLog = WriteCliLog(PortOf(app));

        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
        var bounded = await view.LookAsync();

        Assert.Equal(TwoConversationFakeLs.NewerId, bounded.CascadeId);
    }
}
