// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



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

    // ROADMAP s55: a glog line whose thread-id field is missing must NOT have the timestamp fraction
    // read as the pid. The control for this row is the same line WITH the field (RealPair -> pid 30728).
    [Fact]
    public void ParseLatest_rejects_a_line_with_no_thread_id_field_instead_of_reading_the_timestamp_fraction_as_pid()
    {
        var log =
            "I0731 11:43:49.288076 server.go:560] Language server listening on random port at 56311 for HTTPS (gRPC)\n" +
            "I0731 11:43:49.288080 server.go:568] Language server listening on random port at 56312 for HTTP\n";

        Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
    }

    // ROADMAP s55: the glog header must sit IMMEDIATELY before the pid, so a crafted fragment elsewhere on
    // the line cannot supply a pid/port pair. The prefix tolerance (PrefixedPair) must be unaffected.
    [Fact]
    public void ParseLatest_does_not_take_a_pid_from_text_that_is_not_a_glog_header()
    {
        var log =
            "999 x] Language server listening on random port at 56311 for HTTPS (gRPC)\n" +
            "999 x] Language server listening on random port at 56312 for HTTP\n";

        Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
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
        var log = "I0627 05:26:29.288076 99999999999999999999 some.go:123] " +
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
            "I0627 05:26:29.000000 100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 200 server.go:517] Language server listening on random port at 2000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 100 server.go:525] Language server listening on random port at 1001 for HTTP\n" +
            "I0627 05:26:29.000000 200 server.go:525] Language server listening on random port at 2001 for HTTP\n";

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
            "I0627 05:26:29.000000 38 server.go:560] Language server listening on random port at 56311 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 38 server.go:568] Language server listening on random port at 99999999999999999999 for HTTP\n";

        var ex = Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
        // Assert the FIELD, not just the generic wording: the pid path throws the same "not a usable number"
        // phrase, so a generic assert stays green if the implementation blames the wrong field.
        Assert.Contains("HTTP port", ex.Message);
    }

    [Fact]
    public void ParseLatest_skips_an_unparsable_foreign_line_and_reaches_its_own()
    {
        // The id check runs on lines belonging to OTHER sessions. An unusable number on a line we are merely
        // SKIPPING must not abort a scan that would otherwise succeed — the valid line follows it.
        var log =
            "I0627 05:26:29.000000 100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 99999999999999999999 server.go:525] Language server listening on random port at 5000 for HTTP\n" +
            "I0627 05:26:29.000000 100 server.go:525] Language server listening on random port at 1001 for HTTP\n";

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(1001, ep.HttpPort);
        Assert.Equal(100, ep.Pid);
    }

    [Fact]
    public void ParseLatest_falls_back_to_the_following_http_line_when_no_id_matches()
    {
        // Matching the id is a PREFERENCE, not a requirement. It is glog's thread field — every real pair
        // observed carries the same value on both lines, but that is an observation about the peer's logging,
        // not a contract. If the ids ever drift, discovery must still work rather than hard-fail; treating an
        // observed log detail as guaranteed is precisely what caused the outage this whole change fixes.
        var log =
            "I0627 05:26:29.000000 100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 101 server.go:525] Language server listening on random port at 1001 for HTTP\n";

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(1000, ep.GrpcPort);
        Assert.Equal(1001, ep.HttpPort);
    }

    [Fact]
    public void ParseLatest_rejects_a_non_adjacent_fallback_pair()
    {
        // The fallback fires only when no same-id HTTP line follows, i.e. nothing corroborates that the two lines
        // belong to one session. Adjacency is then the only remaining evidence: without this guard a two-session
        // log pairs session 100's gRPC port with session 200's HTTP port, and that chimera passes the listening
        // check (200 is alive), so the client silently talks to the WRONG workspace instead of erroring.
        var log =
            "I0627 05:26:29.000000 100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 200 server.go:525] Language server listening on random port at 2000 for HTTP\n";

        var ex = Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
        Assert.Contains("not its adjacent partner", ex.Message);
    }

    [Fact]
    public void ParseLatest_does_not_require_adjacency_on_the_same_id_path()
    {
        // The guard above is scoped to the FALLBACK on purpose. A matching id already proves the pairing, and the
        // ports come from two successive bind(0) calls — an unrelated process binding in between legitimately
        // yields a gap. Hard-failing a healthy session on that OS-level race would recreate the outage class this
        // file exists to prevent, so a same-id pair must resolve even when the ports are not adjacent.
        var log =
            "I0627 05:26:29.000000 100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 100 server.go:525] Language server listening on random port at 1007 for HTTP\n";

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(1000, ep.GrpcPort);
        Assert.Equal(1007, ep.HttpPort);
    }

    [Fact]
    public void ParseLatest_fallback_takes_the_FIRST_following_http_line_not_a_later_one()
    {
        // With no same-id line, the fallback candidate is the FIRST following HTTP line - the one bound right after
        // the gRPC port. A later HTTP line in the same log belongs to some other session, so remembering the last
        // candidate instead of the first would pair with it and then fail the adjacency guard on a healthy session.
        var log =
            "I0627 05:26:29.000000 100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 101 server.go:525] Language server listening on random port at 1001 for HTTP\n" +
            "I0627 05:26:29.000000 102 server.go:525] Language server listening on random port at 2000 for HTTP\n";

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(1000, ep.GrpcPort);
        Assert.Equal(1001, ep.HttpPort);
    }

    [Fact]
    public void ParseLatest_never_pairs_with_an_http_line_that_PRECEDES_the_chosen_grpc_line()
    {
        // The HTTP partner is searched only AFTER the newest gRPC line. glog's id field is a thread id and can repeat
        // across a restart, so an older session's same-id HTTP line above the newest gRPC line must not be taken:
        // it names the dead session's port, not this one's.
        var log =
            "I0627 05:26:29.000000 100 server.go:525] Language server listening on random port at 900 for HTTP\n" +
            "I0627 05:26:29.000000 100 server.go:517] Language server listening on random port at 1000 for HTTPS (gRPC)\n" +
            "I0627 05:26:29.000000 100 server.go:525] Language server listening on random port at 1001 for HTTP\n";

        var ep = LsDiscovery.ParseLatest(log);

        Assert.Equal(1000, ep.GrpcPort);
        Assert.Equal(1001, ep.HttpPort);
    }

    [Fact]
    public void ParseLatest_does_not_fall_back_to_an_older_complete_session_when_the_newest_is_incomplete()
    {
        // The boot race: the just-launched session has logged its gRPC line but not yet its HTTP line. Discovery must
        // report that as truncated and let the caller wait - resolving to the OLDER complete pair above it would
        // silently hand back a different workspace's Language Server (see the remarks on DiscoverActive).
        var log =
            "I0627 05:00:00.000000 111 server.go:517] Language server listening on random port at 50000 for HTTPS (gRPC)\n" +
            "I0627 05:00:00.000001 111 server.go:525] Language server listening on random port at 50001 for HTTP\n" +
            "I0627 06:00:00.000000 222 server.go:517] Language server listening on random port at 60000 for HTTPS (gRPC)\n";

        var ex = Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(log));
        Assert.Contains("gRPC port 60000", ex.Message);
        Assert.Contains("looks truncated", ex.Message);
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
        var ex = Assert.Throws<LsDiscoveryException>(
            () => LsDiscovery.DiscoverActive(RealPair, new FakeListeningPorts()));
        // This is the ONE conclusive discovery miss (the peer exited); AgyView's boot race keys on the flag.
        Assert.True(ex.PortNotListening);
    }

    [Fact]
    public void ParseLatest_failures_do_not_carry_the_port_not_listening_flag()
    {
        // Distractor for the row above: an unparsable log says nothing about the peer, so the flag stays false.
        var ex = Assert.Throws<LsDiscoveryException>(() => LsDiscovery.ParseLatest(""));
        Assert.False(ex.PortNotListening);
    }

    [Fact]
    public void ReadCliLogText_reads_a_log_that_a_live_agy_holds_open_for_writing()
    {
        // Capstone Branch C R5: the load-bearing assumption behind ReadCliLogText (a live agy keeps cli.log open for
        // writing, so the reader must share ReadWrite) had no pin. Windows enforces FileShare; on other OSes the
        // control below cannot fail, so the row proves nothing there and is skipped rather than passing vacuously.
        if (!OperatingSystem.IsWindows()) return;

        var path = Path.Combine(Path.GetTempPath(), "clavity-cli-log-" + Guid.NewGuid().ToString("N") + ".log");
        File.WriteAllText(path, RealPair);
        try
        {
            // The "agy": holds the file open for WRITING, letting others read.
            using var agy = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.Read);

            // Failing control in the same process: the naive read (FileShare.Read) is refused while agy writes.
            Assert.Throws<IOException>(() => File.ReadAllText(path));

            // The real reader shares ReadWrite and succeeds.
            Assert.Equal(RealPair, LsDiscovery.ReadCliLogText(path));
        }
        finally { File.Delete(path); }
    }
}
