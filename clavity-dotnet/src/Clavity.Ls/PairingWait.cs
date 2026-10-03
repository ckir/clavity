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
    /// it - or returns null once <paramref name="exitedPath"/> exists without a pairing: the agy script writes it, with
    /// agy's exit code, when agy ends or cannot start (capstone R1, owner-ruled A+B+C). A pairing wins over that file,
    /// so an agy that paired and then died is ChannelDown's case, not this one. There is deliberately no time limit
    /// while agy is alive: a new folder makes agy wait for a human to answer its trust prompt. Ctrl+C ends the process
    /// (the agy tab is a separate process and keeps running).</summary>
    public static AgyEndpoint? WaitForEndpoint(
        string endpointPath, string exitedPath, IListeningPorts listening, TextWriter output, Func<long> nowMs,
        Action<TimeSpan> sleep)
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
            if (TryReadExitCode(exitedPath) is { } code)
            {
                output.WriteLine($"clavity: agy exited before pairing (exit {code}) - Claude was NOT started. agy's tab, or " +
                                 "the terminal that ran `clavity-ls agy`, shows why.");
                return null;
            }
            if (!hinted && nowMs() - started >= (long)HintAfter.TotalMilliseconds)
            {
                output.WriteLine("clavity: still waiting - look at agy's tab: it may be asking you to trust this folder. If " +
                                 "the tab has closed or shows an error, agy is not running - press Ctrl+C.");
                hinted = true;
            }
            sleep(PollInterval);
        }
    }

    /// <summary>The exit code the agy script recorded, "unknown" when it recorded none, or null while there is no file.</summary>
    private static string? TryReadExitCode(string exitedPath)
    {
        try
        {
            if (!File.Exists(exitedPath))
                return null;
            var text = File.ReadAllText(exitedPath).Trim();
            return text.Length == 0 ? "unknown" : text;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return File.Exists(exitedPath) ? "unknown" : null;
        }
    }
}
