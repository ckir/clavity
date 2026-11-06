// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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
    public void A_healthy_call_records_start_then_end_success_and_adds_nothing_to_its_reply()
    {
        var log = new LsEventLog();
        var json = McpTools.RunAsync("agy_look", log, () => Task.FromResult(new { ok = 1 })).GetAwaiter().GetResult();

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
    public void The_end_event_carries_the_elapsed_time_of_the_call()
    {
        var log = new LsEventLog();
        McpTools.RunAsync("agy_ask", log, async () => { await Task.Delay(120); return 1; }).GetAwaiter().GetResult();
        var end = Parse(log.Snapshot()[^1]);
        Assert.InRange(end.GetProperty("dur_ms").GetInt64(), 100, 5000);
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
    public void The_ring_in_a_fault_reply_holds_earlier_calls_too_oldest_first()
    {
        var log = new LsEventLog();
        McpTools.RunAsync("agy_status", log, () => Task.FromResult(1)).GetAwaiter().GetResult();
        var json = McpTools.RunAsync<object>("agy_ask", log, () => throw new InvalidOperationException("boom")).GetAwaiter().GetResult();

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
    public void A_throwing_event_sink_cannot_change_a_reply()
    {
        // Recording must never be able to fail the call it describes.
        var log = new LsEventLog(new BrokenWriter());
        var json = McpTools.RunAsync("agy_look", log, () => Task.FromResult(new { ok = 1 })).GetAwaiter().GetResult();
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
}
