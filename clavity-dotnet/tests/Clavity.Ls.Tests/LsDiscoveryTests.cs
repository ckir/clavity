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

        // Assert on the MESSAGE, not just the type: ParseLatest throws LsDiscoveryException for several
        // distinct reasons, so a bare Assert.Throws stays green when the method fails for an UNRELATED reason
        // (e.g. reverting the body-anchoring fix makes it throw "no HTTPS line found" instead, and the test
        // would never notice). Binding the message keeps this test about the $ anchor specifically.
        var ex = Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
        Assert.Contains("looks truncated", ex.Message);
    }

    [Fact]
    public void ParseLatest_reports_an_unusable_number_as_the_typed_exception()
    {
        // The patterns are prefix-tolerant, so a digit run long enough to overflow int is matchable. That must
        // surface as LsDiscoveryException (the contract callers catch), never as a raw OverflowException.
        // NOTE: capping the pattern's digit count does NOT fix this — a capped group slides along the run and
        // silently captures a wrong value, so the parse stays uncapped and the conversion is guarded instead.
        var log = "I0627 05:26:29.288076 30728 some.go:123] echo 99999999999999999999 fake] " +
                  "Language server listening on random port at 888 for HTTPS (gRPC)\n";

        var ex = Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
        Assert.Contains("not a usable number", ex.Message);
    }

    [Fact]
    public void ParseLatest_pairs_the_http_line_of_the_SAME_session_when_two_sessions_interleave()
    {
        // The global cli.log is shared, so two agy instances starting concurrently interleave their pairs.
        // The chosen gRPC line is the LAST one (pid 200); the first HTTP line after it belongs to pid 100.
        // Taking that one yields a chimera endpoint that still passes the listening check (pid 100 is alive),
        // so the client would talk to the WRONG workspace. Kills two mutants at once: dropping the pid
        // cross-check, and collapsing the forward scan to the single adjacent line.
        var log =
            "100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "200 server.go:517] Language server listening on random port at 2000 for HTTPS (gRPC)\n" +
            "100 server.go:525] Language server listening on random port at 1001 for HTTP\n" +
            "200 server.go:525] Language server listening on random port at 2001 for HTTP\n";

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(200, ep.Pid);
        Assert.Equal(2000, ep.GrpcPort);
        Assert.Equal(2001, ep.HttpPort);
    }

    [Fact]
    public void ParseLatest_reports_an_unusable_HTTP_port_as_the_typed_exception()
    {
        // Covers the HTTP-line parse path specifically. The existing overflow test only exercises the gRPC
        // line, so reverting JUST the HTTP-side guard to a raw int.Parse would otherwise keep every test green.
        var log =
            "38 server.go:560] Language server listening on random port at 56311 for HTTPS (gRPC)\n" +
            "38 server.go:568] Language server listening on random port at 99999999999999999999 for HTTP\n";

        var ex = Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
        Assert.Contains("not a usable number", ex.Message);
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
