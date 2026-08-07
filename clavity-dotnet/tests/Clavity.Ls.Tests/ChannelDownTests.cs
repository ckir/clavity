using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ChannelDownTests
{
    [Fact]
    public void An_oversized_payload_is_not_reported_as_a_peer_shutdown()
    {
        var d = new ChannelDiagnostic("ResourceExhausted", "Received message exceeds the maximum configured size");
        var hint = ChannelDown.Hint(d);

        // The whole defect in one assertion: the operator must not be sent to inspect a healthy process.
        Assert.DoesNotContain("shut down or restarted", hint);
        Assert.Contains("too large", hint);
        Assert.Contains("fresh cascade", hint);
    }

    [Fact]
    public void A_genuine_transport_death_still_reports_a_peer_shutdown()
    {
        // The existing behaviour must survive: this is the case the old hint was written for.
        var d = new ChannelDiagnostic("Unavailable", "connection refused");
        var hint = ChannelDown.Hint(d);

        Assert.Contains("shut down or restarted", hint);
    }

    [Fact]
    public void Every_hint_names_the_status_code_and_detail_it_was_given()
    {
        // Distractor case: a fault we have not special-cased must still surface its real diagnostic
        // rather than falling through to an empty or generic string.
        var d = new ChannelDiagnostic("Internal", "backend exploded");
        var hint = ChannelDown.Hint(d);

        Assert.Contains("Internal", hint);
        Assert.Contains("backend exploded", hint);
    }

    [Fact]
    public void The_status_field_and_the_hint_never_contradict_each_other()
    {
        var big = new ChannelDiagnostic("ResourceExhausted", "Received message exceeds the maximum configured size");
        Assert.Equal("payload_too_large", ChannelDown.StatusFor(big));
        Assert.DoesNotContain("shut down or restarted", ChannelDown.Hint(big));

        var dead = new ChannelDiagnostic("Unavailable", "connection refused");
        Assert.Equal("channel_down", ChannelDown.StatusFor(dead));
        Assert.Contains("shut down or restarted", ChannelDown.Hint(dead));
    }
}
