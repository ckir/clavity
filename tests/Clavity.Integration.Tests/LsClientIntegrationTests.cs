using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// T5 integration (Tier A, CI): the FULL discover -> connect -> read -> parse path against an in-proc fake LS
// (Kestrel h2c, 127.0.0.1:0). A synthetic cli.log names the fake's actual port so LsClient.Connect discovers it.
public class LsClientIntegrationTests
{
    private sealed class FakeLanguageServer(GetConversationMetadataResponse response)
        : LanguageServerService.LanguageServerServiceBase
    {
        public override Task<GetConversationMetadataResponse> GetConversationMetadata(
            GetConversationMetadataRequest request, ServerCallContext context)
            => Task.FromResult(response);

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries["conv-older"] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
                    new DateTimeOffset(2026, 6, 27, 0, 0, 0, TimeSpan.Zero)),
            };
            resp.TrajectorySummaries["conv-newer"] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
                    new DateTimeOffset(2026, 6, 28, 0, 0, 0, TimeSpan.Zero)),
            };
            return Task.FromResult(resp);
        }
    }

    private static async Task<WebApplication> StartFakeLsAsync(GetConversationMetadataResponse response)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(response);
        builder.Services.AddSingleton<FakeLanguageServer>();
        var app = builder.Build();
        app.MapGrpcService<FakeLanguageServer>();
        await app.StartAsync();
        return app;
    }

    private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

    // Synthetic cli.log naming the fake's port as the HTTP (h2c) port, so LsClient.Connect discovers it.
    private static string CliLogFor(int httpPort) =>
        $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {httpPort - 1} for HTTPS (gRPC)\n" +
        $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {httpPort} for HTTP\n";

    [Fact]
    public async Task GetAllCascadeTrajectories_returns_conversations_with_timestamps()
    {
        await using var app = await StartFakeLsAsync(new GetConversationMetadataResponse());
        var port = PortOf(app);
        using var ls = LsClient.Connect(CliLogFor(port), new SystemListeningPorts());

        var conversations = await ls.GetAllCascadeTrajectoriesAsync(excludeSubtrajectories: true);

        Assert.Equal(2, conversations.Count);
        Assert.Contains(conversations, c => c.ConversationId == "conv-older");
        Assert.Contains(conversations, c => c.ConversationId == "conv-newer");
    }

    [Fact]
    public async Task Discover_connect_read_returns_parsed_metadata()
    {
        var expected = new GetConversationMetadataResponse
        {
            Metadata = new Clavity.Ls.Proto.Metadata
            {
                RootConversationId = "conv-xyz",
                Workspaces =
                {
                    new Workspace
                    {
                        BranchName = "main",
                        Repository = new Repository { ComputedName = "ckir/clavity" },
                    },
                },
            },
        };

        await using var app = await StartFakeLsAsync(expected);
        var port = PortOf(app);

        using var ls = LsClient.Connect(CliLogFor(port), new SystemListeningPorts());
        var metadata = await ls.GetConversationMetadataAsync("conv-xyz");

        Assert.Equal("conv-xyz", metadata.RootConversationId);
        var ws = Assert.Single(metadata.Workspaces);
        Assert.Equal("main", ws.BranchName);
        Assert.Equal("ckir/clavity", ws.Repository.ComputedName);
    }
}
