using Clavity.Ls.Proto;
using Grpc.Core;

namespace Clavity.Ls;

/// <summary>Where the live agy session's state lives on disk (overridable for tests).</summary>
public sealed class AgyViewOptions
{
    public required string CliLogPath { get; init; }
    public required string ConversationsDir { get; init; }
}

/// <summary>
/// The read/"look" surface the MCP <c>agy_look</c> tool sits on: locate the active agy conversation
/// (newest conversations/*.db), fetch its cascade trajectory over the live LS (h2c), and return a
/// size-budgeted <see cref="BoundedTrajectory"/>.
/// </summary>
public sealed class AgyView
{
    private readonly AgyViewOptions _options;
    private readonly IListeningPorts _listening;

    public AgyView(AgyViewOptions options, IListeningPorts? listening = null)
    {
        _options = options;
        _listening = listening ?? new SystemListeningPorts();
    }

    /// <summary>Look at the active conversation's trajectory, bounded to <paramref name="budgetChars"/>.</summary>
    public async Task<BoundedTrajectory> LookAsync(
        int budgetChars = BoundedView.DefaultBudgetChars, CancellationToken cancellationToken = default)
    {
        var conversationId = ConversationLocator.NewestActive(_options.ConversationsDir)
            ?? throw new InvalidOperationException(
                $"No active agy conversation (.db) found in {_options.ConversationsDir}.");

        using var client = LsClient.Connect(LsDiscovery.ReadCliLogText(_options.CliLogPath), _listening);
        var trajectory = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
        return BoundedView.Summarize(trajectory, budgetChars);
    }

    /// <summary>Default client-side ceiling on the idle-wait, so a stuck conversation can't block forever.</summary>
    public static readonly TimeSpan DefaultIdleWaitTimeout = TimeSpan.FromSeconds(120);
    private const int IdleInactivityTimeoutSeconds = 30;
    private const int IdleStabilizationSeconds = 2;

    /// <summary>
    /// Send <paramref name="message"/> to the active conversation, wait for it to go idle, then return the NEW
    /// trajectory steps (agy's reply to this message) as a size-bounded view. A client-side <paramref name="timeout"/>
    /// guards the idle-wait (agy refinement (i); ties to T9 ModalGuard) — on expiry a <see cref="TimeoutException"/>
    /// is thrown. ⚠ This is a WRITE: live it consumes quota and posts a visible message; live use is gated to T10.
    /// </summary>
    public async Task<BoundedTrajectory> AskAsync(
        string message,
        int budgetChars = BoundedView.DefaultBudgetChars,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var conversationId = ConversationLocator.NewestActive(_options.ConversationsDir)
            ?? throw new InvalidOperationException(
                $"No active agy conversation (.db) found in {_options.ConversationsDir}.");

        using var client = LsClient.Connect(LsDiscovery.ReadCliLogText(_options.CliLogPath), _listening);

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
            throw new TimeoutException(
                $"agy conversation did not go idle within {(timeout ?? DefaultIdleWaitTimeout)}.");
        }

        var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
        var reply = new CascadeTrajectory { CascadeId = full.CascadeId };
        reply.Steps.AddRange(full.Steps.Skip(before));
        return BoundedView.Summarize(reply, budgetChars);
    }
}
