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
/// (spec §2/§6). <see cref="Pid"/> is the glog-logged agy process id, kept for diagnostics and a
/// future PID-scoped listening check.
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
    //   group 1: severity+date (IWEF + MMDD)   group "pid": the process id   "port": the port number
    // The HTTPS line ends "for HTTPS (gRPC)"; the HTTP line ends "for HTTP" — anchoring on $ keeps the
    // HTTP pattern from also matching the HTTPS line.
    private static readonly Regex GrpcLine = new(
        @"^[IWEF]\d{4}\s+[\d:.]+\s+(?<pid>\d+)\s+\S+\]\s+Language server listening on random port at (?<port>\d+) for HTTPS \(gRPC\)\s*$",
        RegexOptions.Compiled);

    private static readonly Regex HttpLine = new(
        @"^[IWEF]\d{4}\s+[\d:.]+\s+(?<pid>\d+)\s+\S+\]\s+Language server listening on random port at (?<port>\d+) for HTTP\s*$",
        RegexOptions.Compiled);

    /// <summary>
    /// Parse the MOST RECENT LS endpoint from cli.log text. A cli.log accumulates across agy restarts,
    /// so the active session is the LAST gRPC line and the first HTTP line that follows it.
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
                grpcPort = int.Parse(m.Groups["port"].Value);
                pid = int.Parse(m.Groups["pid"].Value);
                break;
            }
        }

        if (grpcIdx < 0)
            throw new LsDiscoveryException(
                "No 'listening on random port ... for HTTPS (gRPC)' line found in cli.log.");

        for (int i = grpcIdx + 1; i < lines.Length; i++)
        {
            var m = HttpLine.Match(lines[i].TrimEnd('\r'));
            if (m.Success)
                return new LsEndpoint(grpcPort, int.Parse(m.Groups["port"].Value), pid);
        }

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
}
