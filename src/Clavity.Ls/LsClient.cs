using Clavity.Ls.Proto;
using Grpc.Net.Client;

namespace Clavity.Ls;

/// <summary>
/// High-level client for agy's Language Server: wraps an h2c <see cref="GrpcChannel"/> and the generated
/// <see cref="LanguageServerService.LanguageServerServiceClient"/>. Construct from a channel (tests) or via
/// <see cref="Connect"/>, which discovers the live LS from cli.log text and dials it over h2c.
/// </summary>
public sealed class LsClient : IDisposable
{
    private readonly GrpcChannel _channel;
    private readonly LanguageServerService.LanguageServerServiceClient _client;

    public LsClient(GrpcChannel channel)
    {
        _channel = channel;
        _client = new LanguageServerService.LanguageServerServiceClient(channel);
    }

    /// <summary>Discover the active LS from cli.log text (liveness-checked) and open an h2c channel to it.</summary>
    public static LsClient Connect(string cliLogText, IListeningPorts listening)
    {
        var endpoint = LsDiscovery.DiscoverActive(cliLogText, listening);
        return new LsClient(LsChannel.ForHttpPort(endpoint.HttpPort));
    }

    /// <summary>Read a conversation's metadata (workspaces, repo/branch, ids).</summary>
    public async Task<Metadata> GetConversationMetadataAsync(string conversationId, CancellationToken cancellationToken = default)
    {
        var response = await _client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = conversationId },
            cancellationToken: cancellationToken);
        return response.Metadata;
    }

    public void Dispose() => _channel.Dispose();
}
