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
    public void The_panel_discipline_token_GREEN_works_the_same_way()
    {
        // adversarial-panel-review does NOT use [VERDICT: - it ends on GREEN (SKILL.md:208).
        // A single hardcoded [VERDICT: regex would flag every panel reply as truncated.
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nGREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nopen findings remain\n", "GREEN"));
    }
}
