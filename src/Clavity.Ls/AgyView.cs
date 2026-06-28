using Clavity.Ls.Proto;

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
}
