using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// Tier A integration (deterministic, CI). Stands up an in-proc FAKE Language Server on Kestrel h2c
// (127.0.0.1:0) and drives it through the REAL LsChannel + generated client — proving the h2c channel
// (AppContext Http2UnencryptedSupport switch + http scheme) completes a gRPC round-trip. T4.
public class LsChannelIntegrationTests
{
    private sealed class FakeLanguageServer(GetConversationMetadataResponse response)
        : LanguageServerService.LanguageServerServiceBase
    {
        public override Task<GetConversationMetadataResponse> GetConversationMetadata(
            GetConversationMetadataRequest request, ServerCallContext context)
            => Task.FromResult(response);
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

    [Fact]
    public async Task H2c_channel_completes_a_GetConversationMetadata_round_trip()
    {
        var expected = new GetConversationMetadataResponse
        {
            // Fully-qualified: `using Grpc.Core;` (for ServerCallContext) also defines a `Metadata` type.
            Metadata = new Clavity.Ls.Proto.Metadata
            {
                RootConversationId = "test-conv-id",
                Workspaces =
                {
                    new Workspace
                    {
                        BranchName = "main",
                        WorkspaceFolderAbsoluteUri = "file:///C:/dev/Rust/clavity",
                        Repository = new Repository
                        {
                            ComputedName = "ckir/clavity",
                            GitOriginUrl = "git@github.com:ckir/clavity.git",
                        },
                    },
                },
            },
        };

        await using var app = await StartFakeLsAsync(expected);
        using var channel = LsChannel.ForHttpPort(PortOf(app));
        var client = new LanguageServerService.LanguageServerServiceClient(channel);

        var resp = await client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = "test-conv-id" });

        Assert.NotNull(resp.Metadata);
        var ws = Assert.Single(resp.Metadata.Workspaces);
        Assert.Equal("main", ws.BranchName);
        Assert.Equal("ckir/clavity", ws.Repository.ComputedName);
        Assert.Equal("test-conv-id", resp.Metadata.RootConversationId);
    }

    [Fact]
    public async Task A_response_larger_than_the_4MB_grpc_default_completes()
    {
        const int bigStringLength = 5 * 1024 * 1024;
        var bigString = new string('x', bigStringLength);

        var expected = new GetConversationMetadataResponse
        {
            Metadata = new Clavity.Ls.Proto.Metadata
            {
                RootConversationId = bigString,
            },
        };

        await using var app = await StartFakeLsAsync(expected);
        using var channel = LsChannel.ForHttpPort(PortOf(app));
        var client = new LanguageServerService.LanguageServerServiceClient(channel);

        var resp = await client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = "test-conv-id" });

        Assert.NotNull(resp.Metadata);
        Assert.Equal(bigStringLength, resp.Metadata.RootConversationId.Length);
        Assert.Equal(bigString, resp.Metadata.RootConversationId);
    }
}
