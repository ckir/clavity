// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Text.Json;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class AgyStatusShapeTests
{
    [Fact]
    public void Healthy_AgyStatus_serializes_diagnostic_and_hint_as_null()
    {
        var json = JsonSerializer.Serialize(new AgyStatus("c", 3, "idle", 15));
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("Diagnostic").ValueKind);
        Assert.Equal(JsonValueKind.Null, doc.RootElement.GetProperty("Hint").ValueKind);
    }

    [Fact]
    public void A_healthy_AgyStatus_serializes_byte_for_byte_as_it_did_before_the_event_log()
    {
        // RecentEvents is OMITTED when null (a routine pre-fire poll must not grow); Diagnostic and Hint stay as they were.
        Assert.Equal(
            "{\"CascadeId\":\"c\",\"TotalSteps\":3,\"State\":\"idle\",\"LastStepKind\":15,\"Diagnostic\":null,\"Hint\":null}",
            JsonSerializer.Serialize(new AgyStatus("c", 3, "idle", 15)));
    }

    [Fact]
    public void A_fault_AgyStatus_carries_the_ring_as_RecentEvents()
    {
        var json = JsonSerializer.Serialize(new AgyStatus("", 0, "channel_down", 0,
            new ChannelDiagnostic("Unavailable", "x"), "h", new[] { "e1", "e2" }));
        using var doc = JsonDocument.Parse(json);
        Assert.Equal(new[] { "e1", "e2" }, doc.RootElement.GetProperty("RecentEvents").EnumerateArray().Select(e => e.GetString()).ToArray());
    }

    [Fact]
    public void Channel_down_AgyStatus_carries_the_diagnostic_and_hint()
    {
        var st = new AgyStatus("", 0, "channel_down", 0,
            new ChannelDiagnostic("Unavailable", "connection refused"), "restart the session");
        Assert.Equal("channel_down", st.State);
        Assert.Equal("Unavailable", st.Diagnostic!.StatusCode);
        Assert.Equal("restart the session", st.Hint);
    }

    [Fact]
    public void IsChannelDown_matches_dead_channel_exceptions_but_not_a_caller_cancel()
    {
        Assert.True(ChannelDown.IsChannelDown(new Grpc.Core.RpcException(
            new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "down"))));
        Assert.True(ChannelDown.IsChannelDown(new ObjectDisposedException("GrpcChannel")));
        Assert.True(ChannelDown.IsChannelDown(new LsDiscoveryException("agy not up")));
        // F6: a caller-cancel is NOT channel_down.
        Assert.False(ChannelDown.IsChannelDown(new Grpc.Core.RpcException(
            new Grpc.Core.Status(Grpc.Core.StatusCode.Cancelled, "cancelled"))));
        // criterion 4: an unrelated bug is NOT masked.
        Assert.False(ChannelDown.IsChannelDown(new InvalidOperationException("real bug")));
    }

    [Fact]
    public void Diagnose_unwraps_the_gRPC_status_and_never_returns_Unknown_when_a_cause_exists()
    {
        var d = ChannelDown.Diagnose(new Grpc.Core.RpcException(
            new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "connection refused")));
        Assert.Equal("Unavailable", d.StatusCode);
        Assert.Contains("connection refused", d.Detail);
    }

    [Fact]
    public void IsChannelDown_matches_a_wrapped_channel_death_but_not_a_bare_model_error()
    {
        var wrappedDead = new AgyModelUnavailableException("no default",
            new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "down")));
        var wrappedCancel = new AgyModelUnavailableException("no default",
            new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Cancelled, "cancelled")));

        Assert.True(ChannelDown.IsChannelDown(wrappedDead));
        Assert.False(ChannelDown.IsChannelDown(wrappedCancel));                    // F6(c)
        Assert.False(ChannelDown.IsChannelDown(new AgyModelUnavailableException("deprecated"))); // bare model error
    }

    [Fact]
    public void Diagnose_unwraps_a_wrapped_channel_death_to_the_real_inner_status()
    {
        var wrappedDead = new AgyModelUnavailableException("no default",
            new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "down")));
        Assert.Equal("Unavailable", ChannelDown.Diagnose(wrappedDead).StatusCode); // F4: not "Unknown"
    }
}
