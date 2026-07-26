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
}
