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

    /// <summary>Stall window: max time with NO agy step progress before agy_ask reports possible_modal(limit=stall).
    /// Env: CLAVITY_AGY_IDLE_STALL_SECONDS. Default = <see cref="AgyView.DefaultIdleWaitTimeout"/> (120s) — it was
    /// always really a no-further-progress window, not a whole-turn budget.</summary>
    public TimeSpan IdleStallWindow { get; init; } = AgyView.DefaultIdleWaitTimeout;

    /// <summary>Absolute max total idle-wait regardless of progress. Env: CLAVITY_AGY_IDLE_MAX_SECONDS. Default
    /// 600s; <see cref="TimeSpan.Zero"/> = unbounded (rely purely on progress + the server idle signal).</summary>
    public TimeSpan IdleAbsoluteMax { get; init; } = TimeSpan.FromSeconds(600);
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

    /// <summary>Return the labelled driver-guidance block on the FIRST call per process; null thereafter, or when
    /// there is nothing to deliver (no golden-header dir AND no escalation index — F1: the two are independent).
    /// T4b: this block is the SOLE destination for the driver cheatsheet, the golden header (SEED+GROWTH), and the
    /// escalation index — none of which reach the peer any more (see AskAsync). If the cheatsheet degraded to the
    /// baseline floor anomalously (over-cap/unreadable/empty), the block leads with a warning so the degrade is
    /// OBSERVABLE, not silent.</summary>
    public string? TryTakeGuidanceBlock()
    {
        // F1 (independent toggles): the block has SOMETHING to deliver when a golden-header dir is configured
        // (cheatsheet + header) OR an escalation index is set. The two are INDEPENDENT — an index with no header
        // dir still rides to the driver (pre-T4b it rode to the peer; T4b moves it to the driver). Bail — WITHOUT
        // consuming the once-per-process gate — only when NEITHER source is present.
        var haveIndex = _options.EscalationIndex is { Length: > 0 };
        if (_options.GoldenHeaderDir is null && !haveIndex) return null;
        if (Interlocked.Exchange(ref _guidanceDelivered, 1) != 0) return null;

        void Warn(string m) => _options.Diagnostics.WriteLine($"clavity: {m}");

        // Order (F5 canonical, matched by clavity-classic): warning -> cheatsheet -> header -> escalation index.
        var sections = new List<string>();
        if (_options.GoldenHeaderDir is { } dir)
        {
            var (cheat, degraded) = DriverCheatsheet.ReadWithDegradeStatus(dir, Warn);
            if (degraded) sections.Add(DriverCheatsheet.DegradedWarningPrefix); // F2: any anomalous degrade is observable
            sections.Add(cheat);
            var header = GoldenHeader.TryReadCombined(dir, Warn);
            if (!string.IsNullOrEmpty(header)) sections.Add(header);
        }
        if (_options.EscalationIndex is { Length: > 0 } idx) sections.Add(idx); // CF1 Option C, independent of the header dir

        // F3: no artificial total cap — every section is inherently bounded (cheatsheet <= DriverCheatsheet.MaxBytes,
        // header <= GoldenHeader.MaxBytes COMBINED, escalation index < 1 KiB by construction), so the assembled block
        // is bounded at ~33 KiB. Pinned by the inherent-bound test so a future per-region cap bump can't silently
        // grow the block unbounded.
        return DriverCheatsheet.Block(string.Join("\n\n", sections));
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
        try
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
        catch (Exception ex) when (ChannelDown.IsChannelDown(ex))
        {
            // F5: the catch wraps the WHOLE body incl ProbeIdleAsync (whose internal fail-safe catches only
            // RpcException, so an ObjectDisposedException from it would otherwise escape to the central RunAsync
            // catch and return the {status:channel_down} error-envelope instead of this AgyStatus shape). A health
            // check reports health in its OWN shape and never throws (criterion 2), carrying the diagnostic+hint (F7).
            // A caller-cancel (RpcException Cancelled / OperationCanceledException) is NOT matched here -> it
            // propagates (F6); AgyConversationPendingException is NOT matched -> it flows to RunAsync's
            // waiting_for_human catch, unchanged.
            var diag = ChannelDown.Diagnose(ex);
            return new AgyStatus("", 0, ChannelDown.Status, 0, diag, ChannelDown.Hint(diag));
        }
    }

    /// <summary>
    /// Send <paramref name="message"/> to the active conversation, wait for it to go idle, then return the NEW
    /// trajectory steps (agy's reply) as a size-bounded view. A client-side <paramref name="timeout"/>, when
    /// supplied, overrides the configured stall window for this call (the absolute-max backstop still comes from
    /// options). ⚠ This is a WRITE: live it consumes quota and posts a visible message; live use is gated to T10.
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

            // T4b (audience split): the golden header (SEED+GROWTH) and escalation index are DRIVER guidance, not
            // peer-facing content — they no longer reach the wire. The peer receives ONLY the raw user ask; the
            // accumulated wisdom is instead delivered to the driver once per process via TryTakeGuidanceBlock().
            var outgoing = message;

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

                await WaitForIdleWithProgressAsync(client, conversationId, before, timeout, cancellationToken);

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

    /// <summary>Wait for agy to go idle, but do NOT abandon a wait while agy is still making progress. Loops bounded
    /// windows: each window waits for the server "fully idle" up to the stall window; if the server reports idle we
    /// return; if the window elapses (client CancelAfter) OR the server reports a wait-timeout, we probe the step
    /// count and either RESET the stall window (agy advanced) or throw possible_modal(stall/absolute_max). An
    /// absolute-max backstop bounds a step-producing runaway (TimeSpan.Zero => unbounded). A caller cancel propagates
    /// as cancellation, never possible_modal (F3). A per-window probe failure fails-toward possible_modal(stall) with
    /// a NULL diagnostic — never spins, never a second network hit (F2 + agy panel R4). The stall/absolute_max
    /// diagnostic is built from the trajectory we ALREADY fetched this window (no redundant re-fetch — agy panel R5 F10).</summary>
    private async Task WaitForIdleWithProgressAsync(
        LsClient client, string conversationId, int before, TimeSpan? stallOverride, CancellationToken cancellationToken)
    {
        var stallWindow = stallOverride ?? _options.IdleStallWindow;
        var absoluteMax = _options.IdleAbsoluteMax;   // TimeSpan.Zero => unbounded
        var start = DateTime.UtcNow;
        var lastProgress = before + 1;                // F5: +1 discounts our own injected Kind-14 user step.
        CascadeTrajectory? lastProbe = null;          // R5 F10: last successfully-fetched trajectory, reused for the diagnostic.

        while (true)
        {
            var windowSecs = stallWindow;
            if (absoluteMax > TimeSpan.Zero)
            {
                var remaining = absoluteMax - (DateTime.UtcNow - start);
                if (remaining <= TimeSpan.Zero)
                    throw BuildModalHang(lastProbe, before, start, IdleLimit.AbsoluteMax);
                windowSecs = remaining < stallWindow ? remaining : stallWindow;
            }

            using var windowCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            windowCts.CancelAfter(windowSecs);
            bool serverTimedOut;
            try
            {
                serverTimedOut = await client.WaitForConversationFullyIdleAsync(
                    conversationId, IdleInactivityTimeoutSeconds, IdleStabilizationSeconds, windowCts.Token);
            }
            catch (Exception ex) when (windowCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
                && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
            {
                serverTimedOut = true; // window elapsed while agy was still active -> treat as a wait-timeout.
            }

            if (!serverTimedOut)
                return; // server reported fully idle: agy is done (happy path unchanged).

            CascadeTrajectory probe;
            try
            {
                probe = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            }
            catch (RpcException) when (!cancellationToken.IsCancellationRequested)
            {
                // F2 (agy panel R4): fail-toward possible_modal(stall) with a NULL diagnostic and NO second network
                // hit. The channel just failed THIS probe; re-fetching for a diagnostic would likely fail again and
                // ESCAPE the loop as an uncaught RpcException -> central catch -> channel_down, silently violating F2.
                // The `!cancellationToken.IsCancellationRequested` guard mirrors the window-wait catch above: the probe
                // runs on the OUTER token, so a caller-cancel arriving as RpcException{Cancelled} here must PROPAGATE
                // as a cancellation, never be reclassified as possible_modal (F3) — otherwise the method's documented
                // "a caller cancel never becomes possible_modal" guarantee would break on this narrow timing window.
                throw BuildModalHang(null, before, start, IdleLimit.Stall);
            }
            lastProbe = probe;
            var total = probe.Steps.Count;

            if (total > lastProgress)
                lastProgress = total; // agy advanced -> reset the stall window and keep waiting.
            else if (absoluteMax > TimeSpan.Zero && (DateTime.UtcNow - start) >= absoluteMax)
                // Honest label (agy panel R3): a budget-clamped window that elapsed with no progress ended because the
                // TOTAL budget ran out — NOT a stall. Reporting Stall would send the operator to the wrong knob
                // (CLAVITY_AGY_IDLE_STALL_SECONDS) when CLAVITY_AGY_IDLE_MAX_SECONDS is the binding cap.
                throw BuildModalHang(probe, before, start, IdleLimit.AbsoluteMax);
            else
                throw BuildModalHang(probe, before, start, IdleLimit.Stall);
        }
    }

    /// <summary>Build the possible_modal exception from an ALREADY-FETCHED trajectory (null => null diagnostic). PURE
    /// + synchronous: it makes NO network call, so it cannot fail with a transient RpcException that would escape to
    /// the central channel_down catch (agy panel R4/R5 — F8/F10). Elapsed = the TOTAL wait since start.</summary>
    private AgyModalHangException BuildModalHang(CascadeTrajectory? trajectory, int before, DateTime start, string limit)
    {
        var diag = trajectory is null ? null : BuildTimeoutDiagnostic(trajectory, before);
        return new AgyModalHangException(
            _modalGuard.OnLsTimeout("WaitForConversationFullyIdle", DateTime.UtcNow - start, limit), diag);
    }

    /// <summary>Where agy stopped, from an already-fetched trajectory: agy-produced step count (discounting our
    /// injected user step) + the last step's kind/class/summary. PURE — the caller fetched the trajectory, so there
    /// is no redundant re-fetch (agy panel R5 F10).</summary>
    private static TimeoutDiagnostic BuildTimeoutDiagnostic(CascadeTrajectory full, int before)
    {
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
        catch (RpcException ex) when (ex.StatusCode == StatusCode.Cancelled)
        {
            throw;   // F6(d): a caller-cancel is a cancellation, never wrapped as a model error / channel_down.
        }
        catch (RpcException ex)   // transient OR a dead channel: thread the RpcException so the central catch can
        {                         // diagnose a channel death (F3); a genuine transient stays a model-availability error.
            throw new AgyModelUnavailableException(
                $"Could not reach agy's model catalog to pick a default for this new conversation ({ex.StatusCode}). " +
                "Retry once agy is responsive.", ex);
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
