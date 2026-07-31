using System.Text.RegularExpressions;

namespace Clavity.Ls;

/// <summary>
/// The two local ports agy's Language Server listens on, plus the agy PID that logged them.
/// </summary>
/// <remarks>
/// agy emits an adjacent pair on startup (glog format) into ~/.gemini/antigravity-cli/cli.log:
/// <code>
/// ...] Language server listening on random port at &lt;N&gt; for HTTPS (gRPC)
/// ...] Language server listening on random port at &lt;N+1&gt; for HTTP
/// </code>
/// The "HTTP" port speaks gRPC over h2c (cleartext HTTP/2) and is the one the .NET client dials
/// (spec §2/§6).
/// <para>
/// <see cref="Pid"/> is the 3rd glog field, and it is NOT reliably an OS process id — do NOT build an
/// OS-level, pid-scoped listening check on it. MEASURED (2026-07-31): on lines emitted after glog is
/// initialized it does equal the real pid (7/7 sessions matched the pid printed in the accompanying
/// "Starting language server process with pid N" message), but the port lines this class parses are
/// emitted BEFORE glog init ("ERROR: logging before google.Init: ") and carry a small non-pid value
/// instead — observed 38 while the owning agy process was pid 15788, and 51 while it was 27972. It is
/// therefore kept for DIAGNOSTICS and for correlating the two lines of one pair only. Liveness is
/// established by <see cref="DiscoverActive"/>'s port-level listening check, not by this value.
/// </para>
/// </remarks>
public sealed record LsEndpoint(int GrpcPort, int HttpPort, int Pid);

/// <summary>Thrown when a usable LS endpoint cannot be derived from a cli.log.</summary>
public sealed class LsDiscoveryException : Exception
{
    public LsDiscoveryException(string message) : base(message) { }
}

/// <summary>
/// Probe for whether a local TCP port is currently in the LISTENING set. Guards against a stale
/// cli.log line whose agy session has since exited (the line stays in the log forever, but the
/// port stops listening). The production adapter is <see cref="SystemListeningPorts"/>.
/// </summary>
public interface IListeningPorts
{
    bool IsListening(int port);
}

/// <summary>
/// Derives the active <see cref="LsEndpoint"/> from agy's cli.log. EMPIRICALLY-DERIVED contract:
/// the line text is agy 1.0.11's; re-verify on agy updates (spec §8).
/// </summary>
public static class LsDiscovery
{
    // glog line shape: I0627 05:26:29.288076 30728 server.go:517] <message>
    //   group "pid": the process id (the glog tail "<pid> <file:line>]")   "port": the port number
    // The HTTPS line ends "for HTTPS (gRPC)"; the HTTP line ends "for HTTP" — anchoring on $ keeps the
    // HTTP pattern from also matching the HTTPS line.
    //
    // DELIBERATELY NOT ANCHORED AT ^ : agy's log HEAD is not a contract. agy 1.1.9 (observed 2026-07-31)
    // began prefixing these very lines with pre-init logger noise —
    //   "ERROR: logging before google.Init: I0731 11:43:49.469806      38 server.go:560] Language server ..."
    // — which silently broke a pattern anchored on the glog severity token and took the whole channel
    // down while agy itself was healthy and listening. Anchor on the distinctive MESSAGE BODY instead;
    // the glog tail is still required because that is where the pid comes from. Leftmost-match lands on
    // the real pid: "\S+\]" cannot span whitespace, so a timestamp fragment can never satisfy it.
    private static readonly Regex GrpcLine = new(
        @"(?<pid>\d+)\s+\S+\]\s+Language server listening on random port at (?<port>\d+) for HTTPS \(gRPC\)\s*$",
        RegexOptions.Compiled);

    private static readonly Regex HttpLine = new(
        @"(?<pid>\d+)\s+\S+\]\s+Language server listening on random port at (?<port>\d+) for HTTP\s*$",
        RegexOptions.Compiled);

    /// <summary>
    /// Turn a captured digit run into an int, surfacing an unusable one as the typed
    /// <see cref="LsDiscoveryException"/> callers expect. Reachable because the patterns are prefix-tolerant:
    /// a digit run long enough to overflow <see cref="int"/> can be matched, and a bare <c>int.Parse</c> would
    /// escape the contract as an <see cref="OverflowException"/>.
    /// Deliberately NOT solved by capping the pattern's digit count: a capped group SLIDES along a longer run
    /// and silently yields a WRONG value (measured — <c>\d{1,7}</c> on a 20-digit run captures 9999999),
    /// which is worse than failing loudly. Only the <c>port</c> group is pinned by its literal "at " prefix;
    /// the <c>pid</c> group is not pinned at all.
    /// </summary>
    private static int ParseCaptured(Group captured, string what) =>
        int.TryParse(captured.Value, out var value)
            ? value
            : throw new LsDiscoveryException(
                $"cli.log {what} '{captured.Value}' is not a usable number; the log line is malformed.");

    /// <summary>
    /// Parse the MOST RECENT LS endpoint from cli.log text. A log can hold several agy sessions, so the
    /// active one is found by scanning BACKWARD to the last gRPC line. Its HTTP partner is then the first
    /// following HTTP line carrying the SAME 3rd-glog-field value — a PREFERENCE, not a requirement: a
    /// shared log interleaves concurrently-starting sessions, so taking the first following line outright
    /// can pair one session's gRPC port with another's HTTP port. If no following line matches, the first
    /// following HTTP line is used as a fallback, because that field is not a contract the peer owes us
    /// (see the <see cref="LsEndpoint"/> remarks) and hard-failing on it would be the same mistake that
    /// broke discovery in the first place.
    /// </summary>
    /// <exception cref="LsDiscoveryException">No complete gRPC+HTTP pair is present.</exception>
    public static LsEndpoint ParseLatest(string cliLogText)
    {
        if (string.IsNullOrEmpty(cliLogText))
            throw new LsDiscoveryException("cli.log is empty; no Language Server port lines to parse.");

        var lines = cliLogText.Split('\n');

        int grpcIdx = -1, grpcPort = 0, pid = 0;
        for (int i = lines.Length - 1; i >= 0; i--)
        {
            var m = GrpcLine.Match(lines[i].TrimEnd('\r'));
            if (m.Success)
            {
                grpcIdx = i;
                grpcPort = ParseCaptured(m.Groups["port"], "gRPC port");
                pid = ParseCaptured(m.Groups["pid"], "pid");
                break;
            }
        }

        if (grpcIdx < 0)
            throw new LsDiscoveryException(
                "No 'listening on random port ... for HTTPS (gRPC)' line found in cli.log.");

        Match? firstAny = null;
        for (int i = grpcIdx + 1; i < lines.Length; i++)
        {
            var m = HttpLine.Match(lines[i].TrimEnd('\r'));
            if (!m.Success) continue;

            // PREFER this session's own HTTP line. The global cli.log is shared, so two agy instances starting
            // concurrently interleave their pairs; taking the first following HTTP line regardless of pid can
            // hand back one session's gRPC port with another's HTTP port. That chimera survives DiscoverActive's
            // listening check — the other session is genuinely alive — and the client then talks to the WRONG
            // workspace's Language Server.
            //
            // TryParse, not ParseCaptured: this runs on lines belonging to OTHER sessions, and an unusable
            // number on a line we are merely skipping must not abort a scan that would otherwise succeed.
            if (int.TryParse(m.Groups["pid"].Value, out var httpPid) && httpPid == pid)
                return new LsEndpoint(grpcPort, ParseCaptured(m.Groups["port"], "HTTP port"), pid);

            // Remember the first following HTTP line as a FALLBACK. Matching on the id is a preference, not a
            // requirement: the id is glog's thread field, and while every real pair observed emits the same
            // value on both lines (16/16 across all local logs), that is an empirical observation about the
            // peer's logging, not a contract it owes us. Hard-failing on it would repeat the exact mistake
            // that caused this outage — treating an observed log detail as guaranteed. If no same-id line
            // exists we still return a usable endpoint, exactly as before this check was added.
            firstAny ??= m;
        }

        if (firstAny is not null)
            return new LsEndpoint(grpcPort, ParseCaptured(firstAny.Groups["port"], "HTTP port"), pid);

        throw new LsDiscoveryException(
            $"Found gRPC port {grpcPort} (pid {pid}) but no following 'for HTTP' line; cli.log session looks truncated.");
    }

    /// <summary>
    /// Parse the latest endpoint AND confirm its HTTP (h2c) port is currently listening — i.e. the
    /// logged session is still alive, not a stale line from an exited agy.
    /// </summary>
    /// <exception cref="LsDiscoveryException">No pair found, or the port is not listening.</exception>
    public static LsEndpoint DiscoverActive(string cliLogText, IListeningPorts listening)
    {
        var ep = ParseLatest(cliLogText);
        if (!listening.IsListening(ep.HttpPort))
            throw new LsDiscoveryException(
                $"Latest cli.log endpoint http={ep.HttpPort} (grpc={ep.GrpcPort}, pid={ep.Pid}) is not listening; " +
                "the agy session likely exited — relaunch agy.");
        return ep;
    }

    /// <summary>
    /// Read agy's cli.log text from disk. A LIVE agy keeps cli.log open for writing, so the plain
    /// <see cref="File.ReadAllText(string)"/> (which opens with <see cref="FileShare.Read"/>) fails with
    /// a sharing violation against a running session. This opens with <see cref="FileShare.ReadWrite"/>,
    /// the only way to read the log of an active agy. EMPIRICALLY-DERIVED, verified live (agy 1.0.11) —
    /// see docs/agy-ls-assumptions.md.
    /// </summary>
    public static string ReadCliLogText(string cliLogPath)
    {
        using var stream = new FileStream(cliLogPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        using var reader = new StreamReader(stream);
        return reader.ReadToEnd();
    }
}
