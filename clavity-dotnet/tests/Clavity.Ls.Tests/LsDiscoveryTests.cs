using Clavity.Ls;

namespace Clavity.Ls.Tests;

// T3 unit tests. Oracle = the real agy 1.0.11 cli.log line shape (captured from
// ~/.gemini/antigravity-cli/cli.log). Pure string parsing — no live agy, deterministic, CI-safe.
public class LsDiscoveryTests
{
    // A verbatim two-line capture from agy 1.0.11's cli.log (glog format).
    private const string RealPair =
        "I0627 05:26:29.288076 30728 server.go:517] Language server listening on random port at 61954 for HTTPS (gRPC)\n" +
        "I0627 05:26:29.292085 30728 server.go:525] Language server listening on random port at 61955 for HTTP\n";

    // A verbatim two-line capture from agy 1.1.9 (2026-07-31), which began prefixing these lines with
    // pre-init logger noise. Same glog tail, arbitrary head — the reason discovery anchors on the body.
    private const string PrefixedPair =
        "ERROR: logging before google.Init: I0731 11:43:49.469806      38 server.go:560] Language server listening on random port at 56311 for HTTPS (gRPC)\n" +
        "ERROR: logging before google.Init: I0731 11:43:49.474132      38 server.go:568] Language server listening on random port at 56312 for HTTP\n";

    [Fact]
    public void ParseLatest_reads_grpc_http_and_pid_from_real_pair()
    {
        var ep = LsDiscovery.ParseLatest(RealPair);

        Assert.Equal(61954, ep.GrpcPort);
        Assert.Equal(61955, ep.HttpPort);
        Assert.Equal(30728, ep.Pid);
    }

    [Fact]
    public void ParseLatest_http_port_is_the_higher_of_the_adjacent_pair()
    {
        var ep = LsDiscovery.ParseLatest(RealPair);

        // The .NET h2c client dials the HTTP (higher) port, NOT the HTTPS/gRPC one.
        Assert.True(ep.HttpPort > ep.GrpcPort);
        Assert.Equal(ep.GrpcPort + 1, ep.HttpPort);
    }

    [Fact]
    public void ParseLatest_picks_the_most_recent_session_when_log_has_restarts()
    {
        var log =
            "I0627 05:00:00.000000 111 server.go:517] Language server listening on random port at 50000 for HTTPS (gRPC)\n" +
            "I0627 05:00:00.000001 111 server.go:525] Language server listening on random port at 50001 for HTTP\n" +
            "I0627 06:00:00.000000 222 server.go:517] Language server listening on random port at 60000 for HTTPS (gRPC)\n" +
            "I0627 06:00:00.000001 222 server.go:525] Language server listening on random port at 60001 for HTTP\n";

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(60000, ep.GrpcPort);
        Assert.Equal(60001, ep.HttpPort);
        Assert.Equal(222, ep.Pid);
    }

    [Fact]
    public void ParseLatest_tolerates_crlf_line_endings()
    {
        var log = RealPair.Replace("\n", "\r\n");

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(61954, ep.GrpcPort);
        Assert.Equal(61955, ep.HttpPort);
    }

    [Fact]
    public void ParseLatest_throws_typed_error_when_no_grpc_line()
    {
        var log = "I0627 05:26:29.000000 30728 server.go:99] some unrelated log line\n";

        Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
    }

    [Fact]
    public void ParseLatest_throws_when_grpc_present_but_http_line_missing()
    {
        var log =
            "I0627 05:26:29.288076 30728 server.go:517] Language server listening on random port at 61954 for HTTPS (gRPC)\n";

        Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
    }

    [Fact]
    public void ParseLatest_reads_prefixed_glog_pair()
    {
        // agy 1.1.9 prepends "ERROR: logging before google.Init: " to the port lines. The head is not a
        // contract; the message body is. Leftmost-match still yields the glog pid, not a timestamp fragment.
        var ep = LsDiscovery.ParseLatest(PrefixedPair);

        Assert.Equal(56311, ep.GrpcPort);
        Assert.Equal(56312, ep.HttpPort);
        Assert.Equal(38, ep.Pid);
    }

    [Fact]
    public void ParseLatest_picks_newest_across_a_log_format_change()
    {
        // A log that spans a peer upgrade holds both shapes. Back-compat (the old pair still parses) and
        // recency (the newer pair wins) in one case.
        var ep = LsDiscovery.ParseLatest(RealPair + PrefixedPair);

        Assert.Equal(56311, ep.GrpcPort);
        Assert.Equal(56312, ep.HttpPort);
        Assert.Equal(38, ep.Pid);
    }

    [Fact]
    public void ParseLatest_never_takes_the_http_port_from_an_https_line()
    {
        // Pins the trailing $ on the HTTP pattern. "for HTTP" is a prefix of "for HTTPS", so an unanchored
        // pattern matches an HTTPS line too. Here the second line is an HTTPS line the gRPC pattern rejects
        // (trailing text after the "(gRPC)"), so ParseLatest scans PAST the chosen gRPC line and reaches it —
        // unanchored, that yields HttpPort == GrpcPort and the client dials the TLS port. It must throw.
        var log =
            PrefixedPair.Split('\n')[0] + "\n" +
            "ERROR: logging before google.Init: I0731 11:43:50.000000      38 server.go:560] " +
            "Language server listening on random port at 56311 for HTTPS (gRPC) [retry]\n";

        Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
    }

    [Fact]
    public void ParseLatest_throws_on_empty_input()
    {
        Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(""));
    }

    private sealed class FakeListeningPorts(params int[] open) : IListeningPorts
    {
        private readonly HashSet<int> _open = [.. open];

        public bool IsListening(int port) => _open.Contains(port);
    }

    [Fact]
    public void DiscoverActive_returns_endpoint_when_http_port_is_listening()
    {
        var ep = LsDiscovery.DiscoverActive(RealPair, new FakeListeningPorts(61955));

        Assert.Equal(61955, ep.HttpPort);
        Assert.Equal(61954, ep.GrpcPort);
    }

    [Fact]
    public void DiscoverActive_throws_when_port_not_listening_stale_log()
    {
        // The latest line is present, but the session has exited → port absent from the listening set.
        Assert.Throws<LsDiscoveryException>(
            () => LsDiscovery.DiscoverActive(RealPair, new FakeListeningPorts()));
    }
}
