namespace Clavity.Integration.Tests;

/// <summary>Captures every progress report so a test can assert on the SEQUENCE, not just that something happened.
/// Deliberately synchronous and order-preserving, matching the production relay in <c>McpTools</c>: a
/// <see cref="System.Progress{T}"/>-based collector would queue callbacks to the thread pool with no
/// SynchronizationContext present, and a test that asserts monotonicity cannot be built on a collector that may
/// reorder what it collects.</summary>
internal sealed class CollectingProgress<T> : IProgress<T>
{
    private readonly List<T> _reports = new();

    /// <summary>Snapshot of what has been reported, in order.</summary>
    public IReadOnlyList<T> Reports
    {
        get { lock (_reports) return _reports.ToArray(); }
    }

    public void Report(T value)
    {
        lock (_reports) _reports.Add(value);
    }
}
