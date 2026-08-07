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
    public void A_resource_exhausted_that_is_not_about_message_size_does_not_assert_the_size_cause()
    {
        // ResourceExhausted is ALSO gRPC's standard code for quota depletion and rate limiting. The hint
        // must not send an operator to raise MaxReceiveMessageSize during a quota event -- that is the same
        // "confidently name the wrong remedy" defect this whole change exists to remove, just relocated.
        var d = new ChannelDiagnostic("ResourceExhausted", "429 from upstream");
        var hint = ChannelDown.Hint(d);

        // CONTROL, and it is load-bearing. Hint() interpolates Detail into its prefix, so asserting on a
        // word that also appears in Detail would assert on THIS TEST'S OWN INPUT and pass no matter what the
        // code says. An earlier draft of this test did exactly that and went green against the unfixed hint.
        // Pinning the input clean is what makes the assertion below capable of failing.
        Assert.DoesNotContain("quota", d.Detail, StringComparison.OrdinalIgnoreCase);

        Assert.DoesNotContain("shut down or restarted", hint);
        Assert.Contains("quota", hint, StringComparison.OrdinalIgnoreCase);
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
