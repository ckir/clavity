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

    /// <summary>Resolved golden-header path to read+prepend per ask; null disables injection (tests / no add-on).</summary>
    public string? GoldenHeaderPath { get; init; }
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

    // CascadeId-keyed in-flight tracker: an ask in flight for conversation A must NOT make a status check on idle
    // conversation B report "working" (multi-session contamination). Keyed by conversation id, not view-global.
    private readonly System.Collections.Concurrent.ConcurrentDictionary<string, byte> _inFlight = new();

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
    private const int ProbeDeadlineMs = 300;

    /// <summary>Report agy busy/idle for the pre-fire check. Local fast-path: if THIS view has an ask in flight for
    /// the resolved conversation, return "working" without touching the network (sidesteps overlap + multi-session
    /// contamination, keyed by CascadeId). Else probe; an RPC error ⇒ "unknown" (fail-safe, never a false idle).</summary>
    public async Task<AgyStatus> StatusAsync(CancellationToken cancellationToken = default)
    {
        var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
        using (client)
        {
            var traj = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            var lastKind = traj.Steps.Count > 0 ? traj.Steps[^1].Kind : 0;

            if (_inFlight.ContainsKey(conversationId))
                return new AgyStatus(conversationId, traj.Steps.Count, "working", lastKind);

            var state = await client.ProbeIdleAsync(
                conversationId, IdleInactivityTimeoutSeconds, TimeSpan.FromMilliseconds(ProbeDeadlineMs), cancellationToken);
            return new AgyStatus(conversationId, traj.Steps.Count, state, lastKind);
        }
    }

    /// <summary>
    /// Send <paramref name="message"/> to the active conversation, wait for it to go idle, then return the NEW
    /// trajectory steps (agy's reply) as a size-bounded view. A client-side <paramref name="timeout"/> guards the
    /// idle-wait (ties to T9 ModalGuard) — on expiry a <see cref="TimeoutException"/> is thrown. ⚠ This is a WRITE:
    /// live it consumes quota and posts a visible message; live use is gated to T10.
    /// </summary>
    public async Task<AskReply> AskAsync(
        string message,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
        using (client)
        {
            // Step count BEFORE sending — everything appended after this index is the reply to our message.
            var before = (await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken)).Steps.Count;

            var header = _options.GoldenHeaderPath is null ? null : GoldenHeader.TryRead(_options.GoldenHeaderPath);
            var outgoing = GoldenHeader.Apply(header, message);

            _inFlight[conversationId] = 1;
            try
            {
                await client.SendUserCascadeMessageAsync(conversationId, outgoing, cancellationToken);

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
                    var diag = await BuildTimeoutDiagnosticAsync(client, conversationId, before, cancellationToken);
                    throw new AgyModalHangException(
                        _modalGuard.OnLsTimeout("WaitForConversationFullyIdle", timeout ?? DefaultIdleWaitTimeout), diag);
                }

                var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
                var delta = full.Steps.Skip(before).ToList();
                return BoundedView.ProjectAskReply(full.CascadeId, delta);
            }
            finally
            {
                _inFlight.TryRemove(conversationId, out _);
            }
        }
    }

    /// <summary>On idle-wait timeout, capture WHERE agy stopped: agy-produced step count (discounting our injected
    /// user step), and the last step's kind/class/summary — so the consumer can tell a slow tool from a true hang.</summary>
    private static async Task<TimeoutDiagnostic> BuildTimeoutDiagnosticAsync(
        LsClient client, string conversationId, int before, CancellationToken ct)
    {
        var full = await client.GetCascadeTrajectoryAsync(conversationId, ct);
        var total = full.Steps.Count;
        var newAgy = Math.Max(0, total - (before + 1)); // +1 discounts our injected Kind-14 user step.
        var last = total > 0 ? full.Steps[^1] : null;
        var lastKind = last?.Kind ?? 0;
        string? summary = last is null ? null
            : (last.UserInput is { } u && u.Text.Length > 0 ? u.Text
               : last.AssistantOutput is { } a && a.Text.Length > 0 ? a.Text : null);
        if (summary is { Length: > 500 } s) summary = s[..500];
        return new TimeoutDiagnostic(total, newAgy, lastKind, StepKind.Class(lastKind), summary);
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
