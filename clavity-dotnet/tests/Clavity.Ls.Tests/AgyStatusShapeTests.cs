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
}
