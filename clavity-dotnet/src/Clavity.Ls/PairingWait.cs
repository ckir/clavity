namespace Clavity.Ls;

/// <summary>
/// Holds Claude back until this session's agy has PAIRED - published a usable endpoint - so the user sees agy (and any
/// prompt it is waiting on, such as folder trust) before switching to Claude for the main work (owner request
/// 2026-10-03; AGY-FIRST: wait without a time limit, hint after 10 s, Ctrl+C aborts). "Paired" is exactly what
/// <c>AgyView.ConnectPreferringEndpoint</c> will accept: <see cref="AgyEndpoint.TryRead"/> succeeds (it rejects the
/// empty values an MCP shell tool publishes) AND the port is listening.
/// </summary>
public static class PairingWait
{
    public static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(500);
    public static readonly TimeSpan HintAfter = TimeSpan.FromSeconds(10);

    /// <summary>Blocks until <paramref name="endpointPath"/> holds a usable endpoint whose port is listening, and returns
    /// it. There is deliberately no time limit: a new folder makes agy wait for a human to answer its trust prompt.
    /// Ctrl+C ends the process (the agy tab is a separate process and keeps running).</summary>
    public static AgyEndpoint WaitForEndpoint(
        string endpointPath, IListeningPorts listening, TextWriter output, Func<long> nowMs, Action<TimeSpan> sleep)
    {
        var started = nowMs();
        var hinted = false;
        output.WriteLine("clavity: waiting for agy to publish its endpoint - Claude starts once agy has paired. Ctrl+C aborts.");
        while (true)
        {
            if (AgyEndpoint.TryRead(endpointPath) is { } ep && listening.IsListening(ep.Port))
            {
                output.WriteLine($"clavity: agy paired (port {ep.Port}) - starting Claude.");
                return ep;
            }
            if (!hinted && nowMs() - started >= (long)HintAfter.TotalMilliseconds)
            {
                output.WriteLine("clavity: still waiting - look at agy's tab: it may be asking you to trust this folder.");
                hinted = true;
            }
            sleep(PollInterval);
        }
    }
}
