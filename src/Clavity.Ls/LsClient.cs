using Clavity.Ls.Proto;
using Grpc.Core;
using Grpc.Net.Client;

namespace Clavity.Ls;

/// <summary>
/// High-level client for agy's Language Server: wraps an h2c <see cref="GrpcChannel"/> and the generated
/// <see cref="LanguageServerService.LanguageServerServiceClient"/>. Construct from a channel (tests) or via
/// <see cref="Connect"/>, which discovers the live LS from cli.log text and dials it over h2c.
/// </summary>
public sealed class LsClient : IDisposable
{
    /// <summary>Defensive client-side deadline for the SHORT unary calls (metadata / trajectory / send / list). A peer
    /// that connects then HANGS must not block a one-shot round-trip forever — without it the <c>AskAsync</c>
    /// <c>finally</c> that clears the in-flight marker would never run, and every later status check would falsely
    /// report "working". NOT applied to the idle-wait RPCs, which are intentionally long and bounded by their OWN
    /// caller deadline (<see cref="ProbeIdleAsync"/>'s 300ms; <c>AgyView.AskAsync</c>'s idle-wait CTS).</summary>
    public const int DefaultCallDeadlineSeconds = 30;

    private readonly GrpcChannel _channel;
    private readonly LanguageServerService.LanguageServerServiceClient _client;
    private readonly TimeSpan _callDeadline;

    public LsClient(GrpcChannel channel, TimeSpan? callDeadline = null)
    {
        _channel = channel;
        _client = new LanguageServerService.LanguageServerServiceClient(channel);
        _callDeadline = callDeadline ?? TimeSpan.FromSeconds(DefaultCallDeadlineSeconds);
    }

    /// <summary>A fresh absolute deadline (UTC) for one unary call, computed at call time. <paramref name="over"/>
    /// lets a CALLER tighten the bound for one call (e.g. the boot race clamps to its remaining budget) without
    /// changing the client-wide default.</summary>
    private DateTime NextCallDeadline(TimeSpan? over = null) => DateTime.UtcNow + (over ?? _callDeadline);

    /// <summary>Discover the active LS from cli.log text (liveness-checked) and open an h2c channel to it.</summary>
    public static LsClient Connect(string cliLogText, IListeningPorts listening, TimeSpan? callDeadline = null)
    {
        var endpoint = LsDiscovery.DiscoverActive(cliLogText, listening);
        return new LsClient(LsChannel.ForHttpPort(endpoint.HttpPort), callDeadline);
    }

    /// <summary>Read a conversation's metadata (workspaces, repo/branch, ids).</summary>
    public async Task<Clavity.Ls.Proto.Metadata> GetConversationMetadataAsync(string conversationId, CancellationToken cancellationToken = default)
    {
        var response = await _client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = conversationId },
            deadline: NextCallDeadline(),
            cancellationToken: cancellationToken);
        return response.Metadata;
    }

    /// <summary>Read a cascade's full trajectory (transcript). The conversation id is accepted as the cascade id.</summary>
    public async Task<CascadeTrajectory> GetCascadeTrajectoryAsync(string cascadeId, CancellationToken cancellationToken = default)
    {
        var response = await _client.GetCascadeTrajectoryAsync(
            new GetCascadeTrajectoryRequest { CascadeId = cascadeId },
            deadline: NextCallDeadline(),
            cancellationToken: cancellationToken);
        return response.Trajectory;
    }

    /// <summary>The deepest legacy fallback model id — used ONLY when the conversation has no prior model AND agy
    /// is too old to serve GetAvailableModels. Named here so the literal 1037 lives in exactly one place.</summary>
    public const int LegacyFallbackModelId = (int)Model.Gemini31ProHigh;

    /// <summary>
    /// Send a user message into the cascade with an explicitly-resolved <paramref name="requestedModel"/>. The
    /// live LS rejects a no-model send and rejects aliases, so the caller resolves a CONCRETE id (the
    /// conversation's own model, agy's default, or the legacy fallback). The response is EMPTY by contract — read
    /// the reply via <see cref="GetCascadeTrajectoryAsync"/> after <see cref="WaitForConversationFullyIdleAsync"/>.
    /// ⚠ LIVE this consumes quota and injects a visible message.
    /// </summary>
    public async Task SendUserCascadeMessageAsync(
        string cascadeId, string text, int requestedModel, CancellationToken cancellationToken = default)
    {
        var request = new SendUserCascadeMessageRequest
        {
            CascadeId = cascadeId,
            CascadeConfig = new CascadeConfig
            {
                PlannerConfig = new CascadePlannerConfig
                {
                    RequestedModel = new ModelOrAlias { Model = requestedModel },
                },
            },
        };
        request.Items.Add(new TextOrScopeItem { Text = text });
        await _client.SendUserCascadeMessageAsync(request, deadline: NextCallDeadline(), cancellationToken: cancellationToken);
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

    /// <summary>Probe idle/working: wait for full idle with a REALISTIC inactivity window, but bound the CALL with
    /// a short client <paramref name="deadline"/>. Returns "idle" if the wait resolves inside the deadline,
    /// "working" if the deadline cancels it first, "unknown" on any RPC error. (Spec: realistic inactivity, the
    /// deadline is the probe budget — never shrink inactivity, which would falsely read inter-step gaps as idle.)</summary>
    public async Task<string> ProbeIdleAsync(string conversationId, int inactivitySeconds, TimeSpan deadline,
        CancellationToken cancellationToken = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(deadline);
        try
        {
            await _client.WaitForConversationFullyIdleAsync(
                new WaitForConversationFullyIdleRequest
                {
                    ConversationId = conversationId,
                    InactivityTimeoutSeconds = inactivitySeconds,
                    StabilizationDurationSeconds = 0,
                },
                cancellationToken: cts.Token);
            return "idle";
        }
        catch (Exception ex) when (cts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
            && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
        {
            return "working";
        }
        catch (RpcException)
        {
            return "unknown";
        }
    }

    /// <summary>
    /// List the top-level conversations this LS instance knows (map key = conversation id). The multi-session
    /// convId resolver: each agy instance's LS reports only its own conversations. (GetBrowserOpenConversation
    /// is desktop-UI-only and errors on a CLI agy — E2-verified — so it is NOT used.)
    /// </summary>
    public async Task<IReadOnlyList<CascadeConversation>> GetAllCascadeTrajectoriesAsync(
        bool excludeSubtrajectories = true, CancellationToken cancellationToken = default,
        TimeSpan? deadlineOverride = null)
    {
        var response = await _client.GetAllCascadeTrajectoriesAsync(
            new GetAllCascadeTrajectoriesRequest { ExcludeSubtrajectories = excludeSubtrajectories },
            deadline: NextCallDeadline(deadlineOverride),
            cancellationToken: cancellationToken);

        return response.TrajectorySummaries
            .Select(kvp => new CascadeConversation(
                kvp.Key,
                kvp.Value.LastModifiedTime?.ToDateTimeOffset()))
            .ToList();
    }

    public void Dispose() => _channel.Dispose();
}
