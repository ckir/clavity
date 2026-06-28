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

    /// <summary>Read a cascade's full trajectory (transcript). The conversation id is accepted as the cascade id.</summary>
    public async Task<CascadeTrajectory> GetCascadeTrajectoryAsync(string cascadeId, CancellationToken cancellationToken = default)
    {
        var response = await _client.GetCascadeTrajectoryAsync(
            new GetCascadeTrajectoryRequest { CascadeId = cascadeId },
            cancellationToken: cancellationToken);
        return response.Trajectory;
    }

    /// <summary>
    /// Send a user message into the cascade. The response is EMPTY by contract — the reply is NOT returned
    /// here; read it back via <see cref="GetCascadeTrajectoryAsync"/> after
    /// <see cref="WaitForConversationFullyIdleAsync"/>. ⚠ LIVE this consumes quota and injects a visible
    /// message; only the fake LS exercises it before T10.
    /// </summary>
    public async Task SendUserCascadeMessageAsync(string cascadeId, string text, CancellationToken cancellationToken = default)
    {
        var request = new SendUserCascadeMessageRequest { CascadeId = cascadeId };
        request.Items.Add(new TextOrScopeItem { Text = text });
        await _client.SendUserCascadeMessageAsync(request, cancellationToken: cancellationToken);
    }

    /// <summary>Block until the conversation is fully idle (or the wait times out). Returns true if it timed out.</summary>
    public async Task<bool> WaitForConversationFullyIdleAsync(
        string conversationId,
        int inactivityTimeoutSeconds,
        int stabilizationDurationSeconds,
        CancellationToken cancellationToken = default)
    {
        var response = await _client.WaitForConversationFullyIdleAsync(
            new WaitForConversationFullyIdleRequest
            {
                ConversationId = conversationId,
                InactivityTimeoutSeconds = inactivityTimeoutSeconds,
                StabilizationDurationSeconds = stabilizationDurationSeconds,
            },
            cancellationToken: cancellationToken);
        return response.TimedOut;
    }

    public void Dispose() => _channel.Dispose();
}
