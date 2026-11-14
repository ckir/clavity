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



using System.Text.Json;
using Clavity.Ls;
using Clavity.Mcp;
using Xunit;

namespace Clavity.Integration.Tests;

// The event log as the MCP tools drive it (AGY-FIRST clavity-ls-logging, rounds 1-2): every call is bracketed by a start
// and an end event, and a FAULT reply - not a healthy one - carries the ring so the failing reply itself says what the
// server did.
public class McpToolsEventTests
{
    private static JsonElement Parse(string line) => JsonDocument.Parse(line).RootElement.Clone();

    private static (JsonElement Envelope, LsEventLog Log) RunFault(Exception toThrow)
    {
        var log = new LsEventLog();
        var json = McpTools.RunAsync<object>("agy_ask", log, () => throw toThrow).GetAwaiter().GetResult();
        return (Parse(json), log);
    }

    [Fact]
    public async Task A_healthy_call_records_start_then_end_success_and_adds_nothing_to_its_reply()
    {
        var log = new LsEventLog();
        var json = await McpTools.RunAsync("agy_look", log, () => Task.FromResult(new { ok = 1 }));

        Assert.Equal("{\"ok\":1}", json);   // the reply is byte-for-byte what it was before the event log existed
        var events = log.Snapshot().Select(Parse).ToArray();
        Assert.Equal(2, events.Length);
        Assert.Equal("start", events[0].GetProperty("phase").GetString());
        Assert.Equal("agy_look", events[0].GetProperty("tool").GetString());
        Assert.Equal("end", events[1].GetProperty("phase").GetString());
        Assert.Equal("success", events[1].GetProperty("outcome").GetString());
        Assert.True(events[1].GetProperty("dur_ms").GetInt64() >= 0);
    }

    [Fact]
    public async Task The_end_event_carries_the_elapsed_time_of_the_call()
    {
        var log = new LsEventLog();
        await McpTools.RunAsync("agy_ask", log, async () => { await Task.Delay(120); return 1; });
        var end = Parse(log.Snapshot()[^1]);
        Assert.InRange(end.GetProperty("dur_ms").GetInt64(), 100, 5000);
    }

    [Fact]
    public void A_generation_cap_hang_reply_carries_its_own_limit_hint_and_event_outcome()
    {
        // AGY-TEST-AUDIT PP-1/PP-2: the wire value, the dedicated hint and the event-log outcome token for the new limit.
        var report = new SurfacingModalGuard().OnLsTimeout("WaitFor", TimeSpan.FromSeconds(700), IdleLimit.GenerationCap);
        var (root, log) = RunFault(new AgyModalHangException(report));

        Assert.Equal("possible_modal", root.GetProperty("status").GetString());
        Assert.Equal("generation_cap", root.GetProperty("limit").GetString());
        Assert.Contains("CLAVITY_AGY_GENERATION_CAP_SECONDS", root.GetProperty("hint").GetString());
        Assert.Equal("possible_modal_generation_cap", Parse(log.Snapshot()[^1]).GetProperty("outcome").GetString());
    }

    [Fact]
    public void A_modal_hang_reply_for_a_discipline_ask_names_the_peer_file_and_says_to_treat_it_as_untrusted()
    {
        // ROADMAP section 108: the peer may finish AFTER the stall report; the reply file is where it will appear.
        var report = new ModalGuardReport("WaitFor", TimeSpan.FromSeconds(120), "agy may be stuck", IdleLimit.Stall);
        var (root, _) = RunFault(new AgyModalHangException(report) { PeerFile = "/ws/.clavity/scratch/agy-replies/c-0.md" });

        Assert.Equal("possible_modal", root.GetProperty("status").GetString());
        Assert.Equal("/ws/.clavity/scratch/agy-replies/c-0.md", root.GetProperty("peerFile").GetString());
        var note = root.GetProperty("peerFileNote").GetString()!;
        Assert.Contains("UNTRUSTED", note);
        Assert.Contains("idle", note);   // do not re-send until agy_status shows idle
        Assert.True(root.TryGetProperty("recentEvents", out _));   // the fault ring still rides along
    }

    [Fact]
    public void A_modal_hang_reply_for_an_ordinary_ask_has_no_peer_file_properties_at_all()
    {
        // The shape of the report for an ordinary ask is byte-for-byte what it was before section 108: the properties
        // are ABSENT, not null.
        var report = new ModalGuardReport("WaitFor", TimeSpan.FromSeconds(120), "agy may be stuck", IdleLimit.Stall);
        var (root, _) = RunFault(new AgyModalHangException(report));

        Assert.False(root.TryGetProperty("peerFile", out _));
        Assert.False(root.TryGetProperty("peerFileNote", out _));
    }

    [Fact]
    public void A_modal_hang_reply_carries_the_last_step_status_and_text_length_in_its_diagnostic()
    {
        var report = new ModalGuardReport("WaitFor", TimeSpan.FromSeconds(120), "agy may be stuck", IdleLimit.Stall);
        var diag = new TimeoutDiagnostic(5, 3, 15, "assistant", "partial", LastStepStatus: 2, LastStepTextLength: 17500);
        var (root, _) = RunFault(new AgyModalHangException(report, diag));

        var d = root.GetProperty("diagnostic");
        Assert.Equal(2, d.GetProperty("LastStepStatus").GetInt32());
        Assert.Equal(17500, d.GetProperty("LastStepTextLength").GetInt32());
    }

    [Fact]
    public void A_modal_hang_reply_carries_the_ring_and_records_the_limit_in_its_outcome()
    {
        var report = new ModalGuardReport("WaitFor", TimeSpan.FromSeconds(120), "agy may be stuck", IdleLimit.Stall);
        var (root, log) = RunFault(new AgyModalHangException(report));

        Assert.Equal("possible_modal", root.GetProperty("status").GetString());
        var ring = root.GetProperty("recentEvents").EnumerateArray().Select(e => Parse(e.GetString()!)).ToArray();
        Assert.Equal("start", ring[0].GetProperty("phase").GetString());
        Assert.Equal("possible_modal_stall", ring[^1].GetProperty("outcome").GetString());
        Assert.Equal(log.Snapshot().Count, ring.Length);   // the ring INCLUDING this call's own end event
    }

    [Fact]
    public void An_absolute_max_hang_is_recorded_distinctly_from_a_stall()
    {
        var report = new ModalGuardReport("WaitFor", TimeSpan.FromSeconds(1800), "budget spent", IdleLimit.AbsoluteMax);
        var (_, log) = RunFault(new AgyModalHangException(report));
        Assert.Equal("possible_modal_absolute_max", Parse(log.Snapshot()[^1]).GetProperty("outcome").GetString());
    }

    [Fact]
    public void A_channel_down_reply_carries_the_ring_and_records_channel_down()
    {
        var (root, _) = RunFault(new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "refused")));
        Assert.Equal("channel_down", root.GetProperty("status").GetString());
        var last = Parse(root.GetProperty("recentEvents").EnumerateArray().Last().GetString()!);
        Assert.Equal("end", last.GetProperty("phase").GetString());
        Assert.Equal("channel_down", last.GetProperty("outcome").GetString());
    }

    [Fact]
    public void A_model_unavailable_reply_carries_the_ring()
    {
        var (root, _) = RunFault(new AgyModelUnavailableException("deprecated"));
        Assert.Equal("model_unavailable", root.GetProperty("status").GetString());
        var last = Parse(root.GetProperty("recentEvents").EnumerateArray().Last().GetString()!);
        Assert.Equal("model_unavailable", last.GetProperty("outcome").GetString());
    }

    [Fact]
    public void An_unexpected_exception_reply_carries_the_ring()
    {
        var (root, _) = RunFault(new InvalidOperationException("boom"));
        Assert.Equal("error", root.GetProperty("status").GetString());
        var last = Parse(root.GetProperty("recentEvents").EnumerateArray().Last().GetString()!);
        Assert.Equal("error", last.GetProperty("outcome").GetString());
    }

    [Fact]
    public async Task The_ring_in_a_fault_reply_holds_earlier_calls_too_oldest_first()
    {
        var log = new LsEventLog();
        await McpTools.RunAsync("agy_status", log, () => Task.FromResult(1));
        var json = await McpTools.RunAsync<object>("agy_ask", log, () => throw new InvalidOperationException("boom"));

        var tools = Parse(json).GetProperty("recentEvents").EnumerateArray()
            .Select(e => Parse(e.GetString()!)).Select(e => e.GetProperty("tool").GetString() + "/" + e.GetProperty("phase").GetString()).ToArray();
        Assert.Equal(new[] { "agy_status/start", "agy_status/end", "agy_ask/start", "agy_ask/end" }, tools);
    }

    [Fact]
    public void A_caller_cancel_is_recorded_as_cancelled_and_still_propagates()
    {
        var log = new LsEventLog();
        Assert.ThrowsAny<OperationCanceledException>(() =>
            McpTools.RunAsync<object>("agy_ask", log, () => throw new OperationCanceledException()).GetAwaiter().GetResult());
        Assert.Equal("cancelled", Parse(log.Snapshot()[^1]).GetProperty("outcome").GetString());

        var grpc = new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Cancelled, "by caller"));
        Assert.Throws<Grpc.Core.RpcException>(() =>
            McpTools.RunAsync<object>("agy_ask", log, () => throw grpc).GetAwaiter().GetResult());
        Assert.Equal("cancelled", Parse(log.Snapshot()[^1]).GetProperty("outcome").GetString());
    }

    [Fact]
    public void A_waiting_for_human_reply_is_recorded_without_dumping_the_ring()
    {
        var (root, log) = RunFault(new AgyConversationPendingException("no conversation yet"));
        Assert.Equal("waiting_for_human", root.GetProperty("status").GetString());
        Assert.False(root.TryGetProperty("recentEvents", out _));   // not a fault: the operator just has to act in agy
        Assert.Equal("waiting_for_human", Parse(log.Snapshot()[^1]).GetProperty("outcome").GetString());
    }

    [Fact]
    public async Task Two_overlapping_calls_to_the_same_tool_stamp_their_own_lines()
    {
        var log = new LsEventLog();
        await Task.WhenAll(
            McpTools.RunAsync("agy_ask", log, async () => { await Task.Delay(150); return 1; }),
            McpTools.RunAsync("agy_ask", log, async () => { await Task.Delay(50); return 2; }));

        var lines = log.Snapshot().Select(Parse).ToArray();
        var groups = lines.GroupBy(l => l.GetProperty("call").GetString()).ToArray();
        Assert.Equal(2, groups.Length);
        foreach (var g in groups)
            Assert.Equal(new[] { "start", "end" }, g.Select(l => l.GetProperty("phase").GetString()).ToArray());
    }

    [Fact]
    public async Task Inside_RunAsync_the_action_sees_the_call_id_of_its_own_start_line()
    {
        var log = new LsEventLog();
        string? seen = null;
        await McpTools.RunAsync("agy_ask", log, () => { seen = log.CurrentCallId; return Task.FromResult(1); });

        Assert.Matches(@"^p\d+-\d{6}$", seen);
        Assert.Equal(seen, Parse(log.Snapshot()[0]).GetProperty("call").GetString());
    }

    [Fact]
    public async Task A_throwing_event_sink_cannot_change_a_reply()
    {
        // Recording must never be able to fail the call it describes.
        var log = new LsEventLog(new BrokenWriter());
        var json = await McpTools.RunAsync("agy_look", log, () => Task.FromResult(new { ok = 1 }));
        Assert.Equal("{\"ok\":1}", json);
    }

    private sealed class BrokenWriter : TextWriter
    {
        public override System.Text.Encoding Encoding => System.Text.Encoding.UTF8;
        public override void WriteLine(string? value) => throw new IOException("stderr closed");
    }

    private static AskReply Reply(bool token = false, bool echo = false, bool busy = false, string? quota = null)
        => new("c", "a", Array.Empty<ActivityItem>(), false, false,
            TerminalTokenMissing: token, EchoMissing: echo, PeerStillBusy: busy, QuotaStop: quota);

    [Fact]
    public void An_ask_outcome_is_the_strongest_incompleteness_in_the_notice_order()
    {
        Assert.Equal("success", McpTools.AskOutcome(Reply()));
        Assert.Equal("peer_still_busy", McpTools.AskOutcome(Reply(busy: true)));
        Assert.Equal("truncated", McpTools.AskOutcome(Reply(token: true)));
        Assert.Equal("truncated", McpTools.AskOutcome(Reply(echo: true)));
        Assert.Equal("truncated", McpTools.AskOutcome(Reply(token: true, busy: true)));
        Assert.Equal("quota_stop", McpTools.AskOutcome(Reply(token: true, busy: true, quota: "Resets in 24m")));
    }

    [Fact]
    public void A_status_outcome_is_success_only_when_no_fault_diagnostic_is_present()
    {
        Assert.Equal("success", McpTools.StatusOutcome(new AgyStatus("c", 3, "working", 15)));
        Assert.Equal("channel_down", McpTools.StatusOutcome(
            new AgyStatus("", 0, "channel_down", 0, new ChannelDiagnostic("Unavailable", "x"), "h")));
    }

    // ---- Task 3: fault replies name the log file and the call id ----

    private static ModalGuardReport StallReport() =>
        new("WaitFor", TimeSpan.FromSeconds(120), "agy may be stuck", IdleLimit.Stall);

    public static IEnumerable<object[]> FaultsWithRing() => new[]
    {
        new object[] { new AgyModalHangException(StallReport()) },
        new object[] { new AgyModalHangException(StallReport()) { PeerFile = "/ws/reply.md" } },
        new object[] { new AgyModelUnavailableException("deprecated") },
        new object[] { new InvalidOperationException("boom") },
        new object[] { new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "refused")) },
    };

    private static string TempLogPath() => Path.Combine(Path.GetTempPath(), "clavity-t3-" + Guid.NewGuid().ToString("N") + ".log");

    [Theory]
    [MemberData(nameof(FaultsWithRing))]
    public async Task Every_fault_status_carries_logPath_callId_and_the_ring_except_waiting_for_human(Exception toThrow)
    {
        var path = TempLogPath();
        try
        {
            using var log = new LsEventLog(filePath: path);
            var json = await McpTools.RunAsync<object>("agy_ask", log, () => throw toThrow);
            var root = Parse(json);

            Assert.Equal(path, root.GetProperty("logPath").GetString());
            var callId = root.GetProperty("callId").GetString()!;
            Assert.Matches(@"^p\d+-\d{6}$", callId);
            var ring = root.GetProperty("recentEvents").EnumerateArray().Select(e => Parse(e.GetString()!)).ToArray();
            Assert.Equal(callId, ring[^1].GetProperty("call").GetString());
            Assert.False(root.TryGetProperty("logNote", out _));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task A_waiting_for_human_reply_carries_logPath_and_callId_but_no_ring()
    {
        var path = TempLogPath();
        try
        {
            using var log = new LsEventLog(filePath: path);
            var json = await McpTools.RunAsync<object>("agy_ask", log, () => throw new AgyConversationPendingException("wait"));
            var root = Parse(json);

            Assert.Equal("waiting_for_human", root.GetProperty("status").GetString());
            Assert.Equal(path, root.GetProperty("logPath").GetString());
            Assert.Matches(@"^p\d+-\d{6}$", root.GetProperty("callId").GetString()!);
            Assert.False(root.TryGetProperty("recentEvents", out _));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void A_fault_reply_from_a_log_with_no_file_says_memory_only_and_has_no_logPath()
    {
        var (root, _) = RunFault(new InvalidOperationException("boom"));
        Assert.False(root.TryGetProperty("logPath", out _));
        Assert.Equal("event log is memory-only (file disabled or dropped); no log file holds this call",
            root.GetProperty("logNote").GetString());
        Assert.True(root.TryGetProperty("recentEvents", out _));
        Assert.True(root.TryGetProperty("callId", out _));
    }

    [Fact]
    public async Task A_dropped_file_sink_is_not_advertised()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-t3-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var blocker = Path.Combine(dir, "blocker");
            File.WriteAllText(blocker, "x");
            using var log = new LsEventLog(filePath: Path.Combine(blocker, "events.log"));   // cannot be opened: sink drops on first write
            var json = await McpTools.RunAsync<object>("agy_ask", log, () => throw new InvalidOperationException("boom"));
            var root = Parse(json);

            Assert.False(root.TryGetProperty("logPath", out _));
            Assert.True(root.TryGetProperty("logNote", out _));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Pre_existing_members_serialize_byte_identically_with_html_and_non_ascii_text()
    {
        var log = new LsEventLog();
        var json = await McpTools.RunAsync<object>("agy_ask", log, () => throw new InvalidOperationException("a<b>&c \u00e9 \u65e5\u672c"));
        Assert.StartsWith(
            @"{""status"":""error"",""exception"":""InvalidOperationException"",""message"":""a\u003Cb\u003E\u0026c \u00E9 \u65E5\u672C"",""recentEvents"":",
            json);
    }
}
