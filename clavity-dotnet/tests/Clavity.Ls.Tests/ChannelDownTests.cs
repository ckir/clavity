using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ChannelDownTests
{
    // One diagnostic per Fault. The throw is the point: adding a Fault without updating this map fails the
    // suite loudly instead of silently skipping the new arm.
    private static ChannelDiagnostic RepresentativeDiagnosticFor(ChannelDown.Fault f) => f switch
    {
        ChannelDown.Fault.TransportDown => new ChannelDiagnostic("Unavailable", "connection refused"),
        ChannelDown.Fault.ResourceExhausted => new ChannelDiagnostic("ResourceExhausted", "message too big"),
        ChannelDown.Fault.AuthFailed => new ChannelDiagnostic("Unauthenticated", "token rejected"),
        ChannelDown.Fault.InvalidRequest => new ChannelDiagnostic("NotFound", "no such cascade"),
        _ => throw new InvalidOperationException(
            $"Fault.{f} has no representative diagnostic. Add one HERE, and an arm to StatusFor AND to Hint."),
    };

    [Fact]
    public void Every_fault_maps_to_its_own_status_so_a_new_arm_cannot_silently_report_channel_down()
    {
        // StatusFor's fallback is `_ => Status` ("channel_down"). A fault added to Classify and to Hint but
        // NOT to StatusFor therefore emits "channel_down" while the hint says the channel is fine -- the
        // precise contradiction StatusFor exists to prevent. That defect DID occur once during this change's
        // own review, guarded only by a code comment. A comment cannot fail a build; this test can.
        var faults = Enum.GetValues<ChannelDown.Fault>();

        var statusOf = faults.ToDictionary(f => f, f =>
        {
            var d = RepresentativeDiagnosticFor(f);
            // Guard the guard: the sample must actually classify as the fault it stands for, or this test
            // would be checking the wrong arm and still pass.
            Assert.Equal(f, ChannelDown.Classify(d));
            return ChannelDown.StatusFor(d);
        });

        var collisions = statusOf
            .GroupBy(kv => kv.Value)
            .Where(g => g.Count() > 1)
            .Select(g => $"{g.Key} <- {string.Join(" + ", g.Select(kv => kv.Key))}")
            .ToList();

        // Name WHICH faults collide, never just how many.
        Assert.True(collisions.Count == 0, "faults sharing one status: " + string.Join(" | ", collisions));
    }

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
    public void An_auth_refusal_is_not_reported_as_a_peer_shutdown()
    {
        // A gRPC auth status PROVES the channel reached the peer and the peer answered with a structured
        // error -- a dead transport cannot produce one. This bridge authenticates via a keyring, so this is
        // reachable, and "restart the session" is advice that can never clear it.
        foreach (var code in new[] { "Unauthenticated", "PermissionDenied" })
        {
            var d = new ChannelDiagnostic(code, "keyring token rejected");

            Assert.Equal("auth_failed", ChannelDown.StatusFor(d));
            Assert.DoesNotContain("shut down or restarted", ChannelDown.Hint(d));
        }
    }

    [Fact]
    public void A_rejected_request_is_not_reported_as_a_peer_shutdown()
    {
        // Same proof, different remedy: the peer answered and refused the REQUEST, so the operator must fix
        // the request (usually a stale cascade id), not restart a healthy process.
        foreach (var code in new[] { "NotFound", "InvalidArgument", "FailedPrecondition" })
        {
            var d = new ChannelDiagnostic(code, "no such cascade");

            Assert.Equal("invalid_request", ChannelDown.StatusFor(d));
            Assert.DoesNotContain("shut down or restarted", ChannelDown.Hint(d));
        }
    }

    [Fact]
    public void The_status_field_and_the_hint_never_contradict_each_other()
    {
        var big = new ChannelDiagnostic("ResourceExhausted", "Received message exceeds the maximum configured size");
        Assert.Equal("resource_exhausted", ChannelDown.StatusFor(big));
        Assert.DoesNotContain("shut down or restarted", ChannelDown.Hint(big));

        var dead = new ChannelDiagnostic("Unavailable", "connection refused");
        Assert.Equal("channel_down", ChannelDown.StatusFor(dead));
        Assert.Contains("shut down or restarted", ChannelDown.Hint(dead));
    }
}
