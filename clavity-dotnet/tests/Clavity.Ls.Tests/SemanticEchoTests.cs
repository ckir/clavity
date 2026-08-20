using System;
using System.IO;
using System.Linq;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class SemanticEchoTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "se-" + Guid.NewGuid().ToString("N"));

    public SemanticEchoTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

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

    [Theory]
    [InlineData("}")]
    [InlineData("```")]
    [InlineData("---")]
    [InlineData("*/")]
    [InlineData("  }  ")]
    public void An_expectation_with_no_SUBSTANCE_cannot_discriminate_and_is_declared_UNUSABLE(string weak)
    {
        // CAPSTONE R1 FINDING (Mechanism Gamer + Boundary Smuggler), and I had just hit it myself while
        // computing the echo for that very consult: the last non-blank line of ANY C# file is "}", so a
        // peer that emits a closing brace satisfies the echo without reading anything. The same holds for
        // a fence, a rule, a block-comment terminator.
        //
        // Degrading silently to "satisfied" would be UNTESTABLE - the bool is true either way - and would
        // leave the operator believing a check ran. So the weakness is reported instead.
        Assert.False(SemanticEcho.IsUsableExpectation(weak));
        Assert.True(SemanticEcho.IsSatisfied("anything\n\n[VERDICT: ALIGNED]\n", weak));  // never a RED
    }

    [Fact]
    public void A_substantive_expectation_IS_usable()
    {
        // The passing control: without it, a predicate that calls EVERYTHING unusable satisfies the rows
        // above and silently disables the echo everywhere.
        Assert.True(SemanticEcho.IsUsableExpectation("the final line of the file"));
        Assert.True(SemanticEcho.IsUsableExpectation("## Done means"));
        Assert.False(SemanticEcho.IsUsableExpectation(null));   // nothing asked for = nothing to warn about
    }

    [Fact]
    public void ExpectedFrom_reads_the_artifact_and_returns_its_last_SUBSTANTIVE_line()
    {
        // THE POINT OF THE REDESIGN. The rule is now applied by exactly ONE party - the driver - reading
        // the file itself. Previously the CALLING AGENT computed the line and passed it in, so an honest
        // review could red merely because the two of them resolved "the last substantive line" to
        // different lines, or because an LLM miscounted characters. One reader cannot disagree with
        // itself.
        var path = Path.Combine(_dir, "artifact.md");
        File.WriteAllText(path, "# Title\n\nthe last real sentence in the file\n\n```\n}\n");
        Assert.Equal("the last real sentence in the file", SemanticEcho.ExpectedFrom(path));
    }

    [Fact]
    public void ExpectedFrom_returns_NULL_when_no_line_can_prove_anything()
    {
        // A file whose tail is all punctuation - the case that started this: every .cs file ends in "}".
        var path = Path.Combine(_dir, "punctuation.md");
        File.WriteAllText(path, "```\n}\n---\n");
        Assert.Null(SemanticEcho.ExpectedFrom(path));
    }

    [Fact]
    public void ExpectedFrom_returns_NULL_rather_than_throwing_for_a_missing_or_absent_path()
    {
        // Reading a caller-named file must never fail an ask. Absent, unreadable, or not named at all
        // are the same answer: there is no expectation, so nothing is claimed.
        Assert.Null(SemanticEcho.ExpectedFrom(Path.Combine(_dir, "does-not-exist.md")));
        Assert.Null(SemanticEcho.ExpectedFrom(null));
        Assert.Null(SemanticEcho.ExpectedFrom("   "));
    }

    [Fact]
    public void ExpectedFrom_reads_a_file_an_EDITOR_is_holding_OPEN_FOR_WRITE()
    {
        // CAPSTONE R9 FINDING (Boundary Smuggler), measured. The default File.ReadLines opens with a
        // share mode that CONFLICTS with an editor holding the file open for write - it throws, the catch
        // swallows it, and the consult silently degrades to [13b] ECHO WEAK. So the check would fail at
        // random depending on whether someone had the artifact open. Measured both ways: default share
        // throws, explicit FileShare.ReadWrite reads it fine.
        var path = Path.Combine(_dir, "held-open.md");
        File.WriteAllText(path, "notes\nthe last real sentence in the file\n");
        using var editor = new FileStream(path, FileMode.Open, FileAccess.Write, FileShare.Read);
        Assert.Equal("the last real sentence in the file", SemanticEcho.ExpectedFrom(path));
    }

    [Fact]
    public void ExpectedFrom_refuses_a_DIRECTORY_and_anything_that_is_not_a_regular_file()
    {
        // Same finding. The language server now opens a path the CALLER supplies, which it never did
        // before. File.Exists is false for a directory and - measured on this platform - for CON, NUL and
        // a pipe path too, so one guard closes the whole "block the ask forever on a device" vector.
        Assert.Null(SemanticEcho.ExpectedFrom(_dir));
        Assert.Null(SemanticEcho.ExpectedFrom("CON"));
    }

    [Fact]
    public void ExpectedFrom_refuses_an_artifact_larger_than_the_cap()
    {
        // An unbounded read on the ask path: "the artifact" could be a multi-gigabyte log. Streaming
        // bounds the MEMORY but not the time, so the size is capped too.
        var path = Path.Combine(_dir, "huge.md");
        File.WriteAllText(path, new string('a', SemanticEcho.MaxArtifactBytes + 1));
        Assert.Null(SemanticEcho.ExpectedFrom(path));
    }

    [Fact]
    public void A_blank_or_whitespace_expectation_is_treated_as_NO_expectation()
    {
        // A primary artifact ending in blank lines yields an empty "last line". Demanding an empty echo
        // would fail every reply. Degrade to no-expectation rather than to always-fail.
        Assert.True(SemanticEcho.IsSatisfied("anything\n\n[VERDICT: ALIGNED]\n", "   "));
    }
}
