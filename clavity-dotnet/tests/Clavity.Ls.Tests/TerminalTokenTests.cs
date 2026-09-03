using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class TerminalTokenTests
{
    [Fact]
    public void Null_expectation_always_satisfied()
    {
        // A caller that names no token is opting out. It must never be reported as truncated,
        // or every non-discipline ask (agy_look, a bare question) reds forever.
        Assert.True(TerminalToken.IsSatisfied("anything at all", null));
        Assert.True(TerminalToken.IsSatisfied(null, null));
    }

    [Fact]
    public void Token_on_the_last_non_blank_line_is_satisfied()
    {
        var reply = "## Findings\n\nsomething\n\n[VERDICT: ALIGNED]\n\n   \n";
        Assert.True(TerminalToken.IsSatisfied(reply, "[VERDICT:"));
    }

    [Fact]
    public void Token_present_but_NOT_at_the_end_is_NOT_satisfied()
    {
        // THE CASE THE SPEC NAMES: "a stored reply whose token is missing OR NOT AT THE END is a
        // truncated reply". A reply that quotes the token mid-body and then dies still lost its tail.
        var reply = "I will end with [VERDICT: ALIGNED] once done.\n\nNow the findings:\n- one\n";
        Assert.False(TerminalToken.IsSatisfied(reply, "[VERDICT:"));
    }

    [Fact]
    public void A_LONG_reply_missing_the_token_is_DETECTED()
    {
        // THE FAILING CONTROL THE SPEC DEMANDS. 20 KB of perfectly good review text with no terminal
        // token: this is a model that truncated ITSELF while the transport delivered every byte.
        // It proves detection is STRUCTURAL, not size-based - a byte-count check would pass this.
        var reply = new string('x', 20 * 1024) + "\nlast line with no token\n";
        Assert.False(TerminalToken.IsSatisfied(reply, "[VERDICT:"));
    }

    [Fact]
    public void Null_or_blank_answer_with_an_expectation_is_NOT_satisfied()
    {
        Assert.False(TerminalToken.IsSatisfied(null, "[VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("   \n\n", "[VERDICT:"));
    }

    [Fact]
    public void A_line_that_NEGATES_the_token_is_NOT_satisfied()
    {
        // AGY-AFTER panel finding, verified: a CONTAINS test accepts "Tests are not GREEN" as proof of
        // GREEN - a reply asserting the opposite of completion would pass. This is why the check is
        // STARTS-WITH. Without this row the fix has no oracle.
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nTests are not GREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("done\n\nno [VERDICT: ...] was produced\n", "[VERDICT:"));
    }

    [Fact]
    public void Markdown_emphasis_around_the_token_still_counts_as_compliance()
    {
        // A peer writing **GREEN** is complying. Failing it would train operators to ignore the check.
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\n**GREEN**\n", "GREEN"));
    }

    [Fact]
    public void The_panel_token_comes_from_the_contract_and_accepts_a_findings_bearing_round()
    {
        // adversarial-panel-review does NOT use [VERDICT: - it closes each ROUND on a single-line
        // PANEL VERDICT (its SKILL.md, "Step 1 - Solo panel"). The token was GREEN until 2026-09-03,
        // which flagged EVERY findings-bearing round: the skill's Outputs section declares four
        // legitimate dispositions and only one is GREEN, so a round that found something was told it
        // was incomplete and its findings should be discarded. Measured five times - by this change's
        // own AGY-AFTER panel, every round of which was flagged while carrying real blocking defects.
        //
        // NOTE the two objects, or a later reader will "reconcile" them and revert this: GREEN is
        // still the RUN-level disposition (that skill's Outputs, and its Completeness gate - "For this
        // skill that means GREEN"). PANEL VERDICT is the PER-ROUND closing line, and a peer's reply IS
        // one round. This table checks a reply, so it takes the round-level token.
        //
        // READ FROM THE TABLE. A literal here would pass before the table changed and prove nothing -
        // measured: the literal form returned Failed 0, Passed 1 against the unchanged contract.
        var tok = DisciplineContract.TerminalTokenFor("adversarial-panel-review");
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nPANEL VERDICT: 2 open findings remain\n", tok));

        // Decoration at the ENDS is compliance, not failure - a distinct branch (TrimStart).
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\n**PANEL VERDICT: GREEN**\n", tok));

        // Still rejects a reply that never reached a verdict line at all.
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nopen findings remain\n", tok));
    }
}
