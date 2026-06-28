using Clavity.Ls.Proto;
using Grpc.Core;

namespace Clavity.Ls;

/// <summary>Where the live agy session's state lives + boot-race bounds (overridable for tests).</summary>
public sealed class AgyViewOptions
{
    /// <summary>The cli.log to discover the LS port from — per-session (CLAVITY_AGY_LOG) or the global default.</summary>
    public required string CliLogPath { get; init; }

    /// <summary>Total time to keep retrying connection + conversation resolution during the agy boot race.</summary>
    public TimeSpan BootRaceTimeout { get; init; } = TimeSpan.FromSeconds(10);

    /// <summary>Delay between boot-race polls.</summary>
    public TimeSpan BootRacePollInterval { get; init; } = TimeSpan.FromMilliseconds(500);
}

/// <summary>
/// The read/"look"/"ask" surface the MCP tools sit on. Resolves the active conversation id from the agy
/// Language Server (GetAllCascadeTrajectories) — NOT from disk — and bounds the agy boot race with a single
/// retry/poll at connection establishment; once connected, each call is a single round-trip.
/// </summary>
public sealed class AgyView
{
    private readonly AgyViewOptions _options;
    private readonly IListeningPorts _listening;
    private readonly IModalGuard _modalGuard;

    public AgyView(AgyViewOptions options, IListeningPorts? listening = null, IModalGuard? modalGuard = null)
    {
        _options = options;
        _listening = listening ?? new SystemListeningPorts();
        _modalGuard = modalGuard ?? new SurfacingModalGuard();
    }

    /// <summary>Look at the active conversation's trajectory, bounded to <paramref name="budgetChars"/>.</summary>
    public async Task<BoundedTrajectory> LookAsync(
        int budgetChars = BoundedView.DefaultBudgetChars, CancellationToken cancellationToken = default)
    {
        var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
        using (client)
        {
            var trajectory = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            return BoundedView.Summarize(trajectory, budgetChars);
        }
    }

    /// <summary>Default client-side ceiling on the idle-wait, so a stuck conversation can't block forever.</summary>
    public static readonly TimeSpan DefaultIdleWaitTimeout = TimeSpan.FromSeconds(120);
    private const int IdleInactivityTimeoutSeconds = 30;
    private const int IdleStabilizationSeconds = 2;

    /// <summary>
    /// Send <paramref name="message"/> to the active conversation, wait for it to go idle, then return the NEW
    /// trajectory steps (agy's reply) as a size-bounded view. A client-side <paramref name="timeout"/> guards the
    /// idle-wait (ties to T9 ModalGuard) — on expiry a <see cref="TimeoutException"/> is thrown. ⚠ This is a WRITE:
    /// live it consumes quota and posts a visible message; live use is gated to T10.
    /// </summary>
    public async Task<BoundedTrajectory> AskAsync(
        string message,
        int budgetChars = BoundedView.DefaultBudgetChars,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
        using (client)
        {
            // Step count BEFORE sending — everything appended after this index is the reply to our message.
            var before = (await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken)).Steps.Count;

            await client.SendUserCascadeMessageAsync(conversationId, message, cancellationToken);

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(timeout ?? DefaultIdleWaitTimeout);
            try
            {
                await client.WaitForConversationFullyIdleAsync(
                    conversationId, IdleInactivityTimeoutSeconds, IdleStabilizationSeconds, timeoutCts.Token);
            }
            catch (Exception ex) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
                && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
            {
                throw new AgyModalHangException(
                    _modalGuard.OnLsTimeout("WaitForConversationFullyIdle", timeout ?? DefaultIdleWaitTimeout));
            }

            var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            var reply = new CascadeTrajectory { CascadeId = full.CascadeId };
            reply.Steps.AddRange(full.Steps.Skip(before));
            return BoundedView.Summarize(reply, budgetChars);
        }
    }

    /// <summary>
    /// Establish a connection and resolve the conversation id, bounded by the boot race. Polls until the cli.log
    /// has the port line, the LS is reachable, AND GetAllCascadeTrajectories returns a non-empty map. On timeout:
    /// <see cref="AgyConversationPendingException"/> if the LS was reachable but reported no conversation (E3 —
    /// wait for the human); otherwise <see cref="LsDiscoveryException"/> (agy not up). Returns a LIVE client the
    /// caller must dispose.
    /// </summary>
    private async Task<(LsClient Client, string ConversationId)> ConnectAndResolveAsync(CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + _options.BootRaceTimeout;
        var reachedLsButEmpty = false;

        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            LsClient? client = null;
            try
            {
                client = LsClient.Connect(LsDiscovery.ReadCliLogText(_options.CliLogPath), _listening);
                var conversations = await client.GetAllCascadeTrajectoriesAsync(
                    excludeSubtrajectories: true, cancellationToken);
                if (conversations.Count > 0)
                {
                    var owned = client;
                    client = null; // hand ownership to the caller — the finally must NOT dispose it.
                    return (owned, SelectMostRecent(conversations));
                }

                reachedLsButEmpty = true; // LS up, but no conversation yet (E3).
            }
            catch (LsDiscoveryException) { }  // log/port not ready, or port not listening yet.
            catch (IOException) { }           // cli.log not present yet.
            catch (RpcException) { }          // LS not answering yet.
            finally
            {
                // Dispose on every non-handoff exit: retry, empty map, OR an unhandled throw (e.g. cancellation
                // surfaced as OperationCanceledException, which is NOT in the catch list) — so the client never leaks.
                client?.Dispose();
            }

            if (DateTime.UtcNow >= deadline)
            {
                if (reachedLsButEmpty)
                    throw new AgyConversationPendingException(
                        "agy is running but has no conversation yet. WAIT for the human to start or continue the " +
                        "agy session, then try again — do NOT auto-retry in a loop.");
                throw new LsDiscoveryException(
                    $"agy Language Server not reachable within {_options.BootRaceTimeout} via {_options.CliLogPath}; " +
                    "the agy session is still starting or has exited.");
            }

            await Task.Delay(_options.BootRacePollInterval, cancellationToken);
        }
    }

    /// <summary>The instance's most-recently-active conversation. Protobuf maps are UNORDERED on the wire, so the
    /// pick MUST be by <c>last_modified_time</c> (spec §6), with conversation id as a stable tiebreaker.</summary>
    private static string SelectMostRecent(IReadOnlyList<CascadeConversation> conversations) =>
        conversations.Count == 1
            ? conversations[0].ConversationId
            : conversations
                .OrderByDescending(c => c.LastModifiedUtc ?? DateTimeOffset.MinValue)
                .ThenBy(c => c.ConversationId, StringComparer.Ordinal)
                .First().ConversationId;
}
