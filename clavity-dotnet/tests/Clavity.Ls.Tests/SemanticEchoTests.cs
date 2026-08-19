using System.Linq;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class SemanticEchoTests
{
    [Fact]
    public void No_expectation_is_always_satisfied()
    {
        // A consult with no primary artifact has nothing to echo. It must not be reported as incomplete.
        Assert.True(SemanticEcho.IsSatisfied("anything", null));
    }

    [Fact]
    public void Echo_within_the_last_three_non_blank_lines_is_satisfied()
    {
        var reply = "findings\n\nECHO: the final line of the file\n\n[VERDICT: ALIGNED]\n";
        Assert.True(SemanticEcho.IsSatisfied(reply, "the final line of the file"));
    }

    [Fact]
    public void Echo_present_but_FAR_from_the_end_is_NOT_satisfied()
    {
        // THE POINT OF THE CHECK. A peer that quotes the line early and then truncates has still lost its
        // tail. Requiring it NEAR THE VERDICT is what makes this evidence of reaching the end.
        var filler = string.Join("\n", Enumerable.Repeat("more analysis", 10));
        var reply = "the final line of the file\n" + filler + "\n[VERDICT: ALIGNED]\n";
        Assert.False(SemanticEcho.IsSatisfied(reply, "the final line of the file"));
    }

    [Fact]
    public void A_reply_that_never_echoes_is_NOT_satisfied()
    {
        // The lone-verdict-line shape: a peer that never read the artifact cannot produce its last line.
        Assert.False(SemanticEcho.IsSatisfied("Review complete.\n\n[VERDICT: ALIGNED]\n", "the final line of the file"));
    }

    [Fact]
    public void Markdown_quoting_around_the_echo_still_counts()
    {
        // A peer wrapping the echo in backticks or a blockquote is complying. Failing it teaches operators
        // to ignore the check, which is how a guard dies.
        Assert.True(SemanticEcho.IsSatisfied("> `the final line of the file`\n\n[VERDICT: ALIGNED]\n",
                                             "the final line of the file"));
    }

    [Fact]
    public void A_DECORATION_ONLY_line_does_not_consume_a_tail_slot()
    {
        // MUTATION-AUDIT ROW, not in the plan. The plan's markdown row above does NOT pin the answer-side
        // Normalise: Contains is a substring test, so "> `x`" contains "x" whether or not the decoration
        // was stripped. Deleting Normalise from the tail projection left all six plan rows GREEN - a
        // guard nothing tested. What Normalise actually buys is that a decoration-only line counts as
        // BLANK and so does not eat one of the three tail slots. Here the echo is inside the window only
        // if the lone ">" is dropped.
        var reply = "ECHO: the final line of the file\n>\nsome note\n[VERDICT: ALIGNED]\n";
        Assert.True(SemanticEcho.IsSatisfied(reply, "the final line of the file"));
    }

    [Fact]
    public void An_expected_echo_carrying_its_OWN_markdown_matches_an_undecorated_quote()
    {
        // The other half the plan left unpinned: the NEEDLE is normalised too. When the artifact's last
        // line is itself decorated ("**the final line**") and the peer quotes it plainly, a raw needle
        // would never match. Without this row, dropping Normalise from the expectation side is invisible.
        var reply = "findings\n\nthe final line\n\n[VERDICT: ALIGNED]\n";
        Assert.True(SemanticEcho.IsSatisfied(reply, "**the final line**"));
    }

    [Fact]
    public void A_blank_or_whitespace_expectation_is_treated_as_NO_expectation()
    {
        // A primary artifact ending in blank lines yields an empty "last line". Demanding an empty echo
        // would fail every reply. Degrade to no-expectation rather than to always-fail.
        Assert.True(SemanticEcho.IsSatisfied("anything\n\n[VERDICT: ALIGNED]\n", "   "));
    }
}
