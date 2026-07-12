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

    /// <summary>Resolved golden-header directory to read+prepend per ask; null disables injection (tests / no add-on).</summary>
    public string? GoldenHeaderDir { get; init; }

    /// <summary>The CF1 escalation-index block, prebuilt ONCE at server startup from the install's manuals dir
    /// (Option C). Appended to every injected header; null disables it (tests / classic / manuals absent).</summary>
    public string? EscalationIndex { get; init; }

    /// <summary>Where operator-facing diagnostics go. Default = stderr (stdout is the MCP protocol channel, so
    /// it must NOT carry log lines). Tests inject a StringWriter to assert the surfaced model line.</summary>
    public TextWriter Diagnostics { get; init; } = Console.Error;
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

    // Once-per-process guidance delivery (spec §5.C-C): the [driver_guidance] block is appended to the FIRST
    // agy_ask of this server session only. AgyView is a process-lifetime singleton, so this flag IS session-scoped.
    private int _guidanceDelivered; // 0 = not yet delivered

    /// <summary>Return the labelled driver-guidance block on the FIRST call per process; null thereafter,
    /// or when injection is disabled (GoldenHeaderDir null).</summary>
    public string? TryTakeGuidanceBlock()
    {
        if (_options.GoldenHeaderDir is null) return null;
        if (Interlocked.Exchange(ref _guidanceDelivered, 1) != 0) return null;
        var cheat = DriverCheatsheet.Read(_options.GoldenHeaderDir, m => _options.Diagnostics.WriteLine($"clavity: {m}"));
        return DriverCheatsheet.Block(cheat);
    }

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
            // Report the REAL cascade id (traj.CascadeId), NOT the conversation id — the field is named
            // CascadeId and AskAsync fills its CascadeId from the same trajectory, so status.CascadeId now
            // string-equals ask.CascadeId and a consumer can correlate a pre-fire status with its ask.

            if (_inFlight.ContainsKey(conversationId))
                return new AgyStatus(traj.CascadeId, traj.Steps.Count, "working", lastKind);

            var state = await client.ProbeIdleAsync(
                conversationId, IdleInactivityTimeoutSeconds, TimeSpan.FromMilliseconds(ProbeDeadlineMs), cancellationToken);
            return new AgyStatus(traj.CascadeId, traj.Steps.Count, state, lastKind);
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
            // Full pre-send trajectory: its Count delimits the reply, AND it carries the conversation's model.
            var beforeTrajectory = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            var before = beforeTrajectory.Steps.Count;

            var model = await ResolveSendModelAsync(client, beforeTrajectory, cancellationToken);

            var header = _options.GoldenHeaderDir is null
                ? null
                : GoldenHeader.TryReadCombined(_options.GoldenHeaderDir, m => _options.Diagnostics.WriteLine($"clavity: {m}"));
            if (_options.EscalationIndex is { Length: > 0 } idx)                 // CF1 Option C (no-op when null)
                header = string.IsNullOrEmpty(header) ? idx : header.TrimEnd() + "\n\n" + idx;
            var outgoing = GoldenHeader.Apply(header, message);

            _inFlight[conversationId] = 1;
            try
            {
                try
                {
                    await client.SendUserCascadeMessageAsync(conversationId, outgoing, model, cancellationToken);
                }
                catch (RpcException)
                {
                    InvalidateCatalog();   // a stale cache may have approved a now-deprecated id; refresh next ask.
                    throw;
                }

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
                // Bound THIS call to the boot race's REMAINING budget — otherwise a connected-but-hung peer would
                // block on the client's default 30s deadline and blow past the (shorter) boot-race budget. The
                // resulting DeadlineExceeded flows through the RpcException catch below; the returned client keeps
                // its normal per-call deadline for everything after connect.
                var remaining = deadline - DateTime.UtcNow;
                if (remaining < TimeSpan.Zero) remaining = TimeSpan.Zero;
                var conversations = await client.GetAllCascadeTrajectoriesAsync(
                    excludeSubtrajectories: true, cancellationToken, deadlineOverride: remaining);
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

    // Catalog cache: AgyView is a process-lifetime singleton (Program.cs:29) while LsClient is per-ask, so the
    // per-LS-session model catalog is memoized HERE. Fetched once; self-heals via InvalidateCatalog() on a model
    // rejection (Spec: "refresh on a miss / send rejection"). Failures are NOT cached (only a successful catalog).
    private FetchAvailableModelsResponse? _catalogCache;
    private readonly SemaphoreSlim _catalogGate = new(1, 1);

    private async Task<FetchAvailableModelsResponse> GetCatalogAsync(LsClient client, CancellationToken ct)
    {
        if (_catalogCache is { } cached) return cached;
        await _catalogGate.WaitAsync(ct);
        try { return _catalogCache ??= await client.GetAvailableModelsAsync(ct); }
        finally { _catalogGate.Release(); }
    }

    private void InvalidateCatalog() => _catalogCache = null;

    /// <summary>
    /// Resolve the concrete send-model (spec resolution ladder): (1) the conversation's own last-executed model
    /// from the trajectory — validated against the cached catalog; (2) agy's default for a brand-new conversation;
    /// (3) the retained legacy const when agy is too old to serve GetAvailableModels (LOUD warning). The PRIMARY
    /// trajectory model is never overridden by a catalog hiccup (renumber-proof); the catalog (cached) is consulted
    /// only for validation + the new-conversation default. Surfaces the chosen id + source on stderr.
    /// </summary>
    private async Task<int> ResolveSendModelAsync(LsClient client, CascadeTrajectory trajectory, CancellationToken ct)
    {
        if (SendModelResolver.ResolveFromTrajectory(trajectory) is int t)
        {
            // Deprecation guard against the cached catalog. UNIMPLEMENTED (older agy) -> skip silently; a TRANSIENT
            // failure -> skip but WARN (don't fail a known-good same-agy id on an optional-RPC hiccup — finding #2).
            try
            {
                var catalog = await GetCatalogAsync(client, ct);
                if (!SendModelResolver.IsInCatalog(t, catalog))
                    throw new AgyModelUnavailableException(DeprecatedModelHint);
            }
            catch (RpcException ex) when (ex.StatusCode == StatusCode.Unimplemented) { /* older agy: no catalog. */ }
            catch (RpcException)
            {
                _options.Diagnostics.WriteLine(
                    "clavity: WARNING — could not reach agy's model catalog to validate; proceeding with the " +
                    $"conversation's model {t}.");
            }
            Surface(t, ModelSource.Trajectory);
            return t;
        }

        // No prior model — a brand-new conversation needs agy's default, so the catalog is REQUIRED here.
        FetchAvailableModelsResponse catalog2;
        try
        {
            catalog2 = await GetCatalogAsync(client, ct);
        }
        catch (RpcException ex) when (ex.StatusCode == StatusCode.Unimplemented)
        {
            _options.Diagnostics.WriteLine(
                $"clavity: WARNING — agy is outdated (no GetAvailableModels); driving with legacy model " +
                $"{LsClient.LegacyFallbackModelId}, which may NOT be your conversation's model. Update agy.");
            Surface(LsClient.LegacyFallbackModelId, ModelSource.Legacy);
            return LsClient.LegacyFallbackModelId;
        }
        catch (RpcException ex)   // transient on a capable agy -> clear, non-crashing error (Spec: never crash).
        {
            throw new AgyModelUnavailableException(
                $"Could not reach agy's model catalog to pick a default for this new conversation ({ex.StatusCode}). " +
                "Retry once agy is responsive.");
        }

        if (SendModelResolver.ResolveDefault(catalog2) is int d)
        {
            Surface(d, ModelSource.Default);
            return d;
        }
        throw new AgyModelUnavailableException(
            "agy returned no default model and the conversation has no prior model. In agy, select a model and " +
            "send a message, then retry.");
    }

    private const string DeprecatedModelHint =
        "The conversation's model is no longer available. In agy, pick a new model AND send a message so the " +
        "conversation records it, then retry.";

    private void Surface(int model, ModelSource source) => _options.Diagnostics.WriteLine(
        $"clavity: driving with model {model} (source: {source.ToString().ToLowerInvariant()})");
}
