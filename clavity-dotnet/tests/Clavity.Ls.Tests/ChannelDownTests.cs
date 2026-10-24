// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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
    public void Only_the_auth_hint_tells_the_user_to_look_for_a_pending_prompt_in_the_agy_tab()
    {
        // MEASURED 2026-10-02 (Linux VM): a NEW agy on a new folder stopped on a folder-trust prompt and published its
        // endpoint only after the user approved it; until then every call is an auth refusal.
        foreach (var f in Enum.GetValues<ChannelDown.Fault>())
        {
            var hint = ChannelDown.Hint(RepresentativeDiagnosticFor(f));
            if (f == ChannelDown.Fault.AuthFailed)
                Assert.Contains("approve a prompt in its tab", hint);
            else
                Assert.DoesNotContain("approve a prompt in its tab", hint);
        }
    }

    [Fact]
    public void Only_the_two_faults_a_stale_client_can_cause_name_the_running_client_build()
    {
        // A stale INSTALLED client was blamed on a healthy peer (2026-08-09). The build stamp is added only where a fix
        // that is already in the source tree could be the real cause: a transport death and a size/quota refusal. A busy
        // peer, a stale endpoint, a refused credential and a rejected request are not cured by a newer client, and a
        // version string in them is noise the operator learns to ignore.
        var note = $"Running client: clavity-ls {ClientStamp.Value}";
        foreach (var f in Enum.GetValues<ChannelDown.Fault>())
        {
            var hint = ChannelDown.Hint(RepresentativeDiagnosticFor(f));
            if (f is ChannelDown.Fault.TransportDown or ChannelDown.Fault.ResourceExhausted)
                Assert.Contains(note, hint);
            else
                Assert.DoesNotContain("Running client", hint);
        }
        Assert.DoesNotContain("Running client", ChannelDown.Hint(new ChannelDiagnostic(ChannelDown.LsUnanswered, "busy")));
        Assert.DoesNotContain("Running client", ChannelDown.Hint(new ChannelDiagnostic(ChannelDown.LsEndpointStale, "stale")));
    }

    [Fact]
    public void The_stale_client_note_says_how_to_tell_and_what_to_do_and_stays_after_the_original_remedy()
    {
        var hint = ChannelDown.Hint(RepresentativeDiagnosticFor(ChannelDown.Fault.ResourceExhausted));
        // The existing remedy text must survive and come FIRST; the note is an addition, not a replacement.
        Assert.True(hint.IndexOf("raise MaxReceiveMessageSize", StringComparison.Ordinal) is var a and >= 0
            && hint.IndexOf("Running client", StringComparison.Ordinal) is var b and >= 0 && a < b, hint);
        Assert.Contains("this INSTALLED binary is stale", hint);
        Assert.Contains("update the clavity plugin", hint);
    }

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
    public void A_peer_that_was_reached_but_did_not_answer_is_diagnosed_as_busy_and_told_to_retry()
    {
        // Backlog ls-discovery-misreports-a-busy-peer-as-exited: the endpoint resolved and every poll hit
        // DeadlineExceeded, so the peer is alive. The hint must lead with retry and must NOT claim a shutdown.
        var d = ChannelDown.Diagnose(new LsDiscoveryException("peer busy") { PeerReachedButUnanswered = true });
        var hint = ChannelDown.Hint(d);

        Assert.Equal(ChannelDown.LsUnanswered, d.StatusCode);
        Assert.Contains("RETRY", hint);
        Assert.DoesNotContain("shut down or restarted", hint);
        Assert.Equal(ChannelDown.Status, ChannelDown.StatusFor(d)); // status stays channel_down (compatibility)
    }

    [Fact]
    public void A_discovery_failure_without_the_unanswered_flag_is_still_a_shutdown_or_not_started()
    {
        // Distractor for the row above: the SAME exception type without the flag keeps the old diagnosis.
        var d = ChannelDown.Diagnose(new LsDiscoveryException("not reachable"));
        var hint = ChannelDown.Hint(d);

        Assert.Equal("LsDiscovery", d.StatusCode);
        Assert.Contains("shut down or restarted", hint);
        Assert.DoesNotContain("RETRY", hint);
    }

    [Fact]
    public void A_stale_endpoint_file_is_diagnosed_and_the_hint_says_relaunch_agy_not_restart_the_session()
    {
        // Measured live 2026-10-12: the endpoint file named a dead port AND the cli.log session was dead; restarting
        // the Claude session cannot clear either. Only a relaunched agy republishes its endpoint.
        var d = ChannelDown.Diagnose(new LsDiscoveryException("not reachable. file X is stale") { StaleEndpointNote = "file X is stale" });
        var hint = ChannelDown.Hint(d);

        Assert.Equal(ChannelDown.LsEndpointStale, d.StatusCode);
        Assert.Contains("file X is stale", hint);
        Assert.Contains("Relaunch agy", hint);
        Assert.DoesNotContain("Restart the Claude Code session", hint);
        Assert.Equal(ChannelDown.Status, ChannelDown.StatusFor(d)); // status stays channel_down (compatibility)
    }

    [Fact]
    public void A_busy_peer_with_a_stale_note_is_still_told_to_retry()
    {
        // Distractor: PeerReachedButUnanswered proves the peer is alive, so it outranks the stale-file note.
        var d = ChannelDown.Diagnose(new LsDiscoveryException("busy")
            { PeerReachedButUnanswered = true, StaleEndpointNote = "file X is stale" });

        Assert.Equal(ChannelDown.LsUnanswered, d.StatusCode);
        Assert.Contains("RETRY", ChannelDown.Hint(d));
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

            // POSITIVELY pin the remedy, not only the absence of the wrong one. AGY-TEST-AUDIT 2026-09-13:
            // the AuthFailed and ResourceExhausted hints assert their own guidance, but InvalidRequest
            // asserted only what it must NOT say - so a reword of this arm to something generic (but still
            // not "shut down") would pass the negative alone, silently dropping the actionable guidance.
            // "rejected the REQUEST" is unique to this arm (AuthFailed says "REFUSED the credential",
            // ResourceExhausted names size/quota), so it also proves the InvalidRequest arm actually fired.
            Assert.Contains("rejected the REQUEST", ChannelDown.Hint(d));
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

public class ChannelDownAuthHintTests
{
    [Fact]
    public void AuthFailed_hint_names_the_endpoint_refresh_remedy_and_not_the_keyring()
    {
        var d = new ChannelDiagnostic(nameof(Grpc.Core.StatusCode.Unauthenticated), "missing CSRF token");
        Assert.Equal("auth_failed", ChannelDown.StatusFor(d));
        var hint = ChannelDown.Hint(d);
        Assert.Contains("agy-endpoint.json", hint);
        Assert.Contains("relaunch", hint, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("keyring", hint, StringComparison.OrdinalIgnoreCase);
    }
}
