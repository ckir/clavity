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
    public void The_tail_window_is_pinned_at_BOTH_edges_not_just_the_far_one()
    {
        // AGY-TEST-AUDIT 2026-08-30. TailLines is the whole tolerance of this check, and only its TIGHT
        // edge was pinned: the positive row puts the echo 2 non-blank lines from the end and the
        // negative row puts it 11, so every value from 3 to 10 satisfied the suite equally.
        // MEASURED, and it is why this row is shaped like this: TailLines -> 2 REDDENS a row already,
        // so the tight edge IS covered - but TailLines -> 10 left all 21 green. The gap was the LOOSE
        // edge alone. Pinning both means the constant cannot drift either way without a named failure.
        // THE BLANK LINES ARE DELIBERATE: the window counts NON-BLANK lines, so a fixture built from
        // consecutive lines would still pass if someone changed it to count raw lines instead.
        var justInside = "ECHO: the final line of the file\n\nanalysis\n\n[VERDICT: ALIGNED]\n";
        Assert.True(SemanticEcho.IsSatisfied(justInside, "the final line of the file"));

        var justOutside = "ECHO: the final line of the file\n\nanalysis\n\nmore\n\n[VERDICT: ALIGNED]\n";
        Assert.False(SemanticEcho.IsSatisfied(justOutside, "the final line of the file"));
    }

    [Fact]
    public void A_null_or_blank_answer_with_a_usable_expectation_is_NOT_satisfied()
    {
        // AGY-TEST-AUDIT 2026-08-30. IsSatisfied guards a null answer before splitting it, and nothing
        // exercised that guard: the existing null rows pass a null EXPECTATION, which returns true one
        // line above and never reaches the split. MEASURED: removing the guard left all 21 rows green,
        // while a null answer carrying a usable expectation would throw inside Split - and a truncated
        // reply is precisely when this is called.
        // THE SIBLING CLASS ALREADY HAS THIS ROW. TerminalTokenTests carries
        // Null_or_blank_answer_with_an_expectation_is_NOT_satisfied for the identical guard shape.
        Assert.False(SemanticEcho.IsSatisfied(null, "the final line of the file"));
        Assert.False(SemanticEcho.IsSatisfied("", "the final line of the file"));
        Assert.False(SemanticEcho.IsSatisfied("   \n\t\n", "the final line of the file"));
    }

    [Fact]
    public void Markdown_UNDERSCORE_emphasis_around_the_echo_still_counts()
    {
        // AGY-TEST-AUDIT 2026-08-30. Normalise strips > ` * _ and whitespace so formatting never fails an
        // honest echo. The suite covered the blockquote, the backtick and the asterisk; the underscore was
        // the one character in that set with no row.
        // THE UNDERSCORES GO ON THE EXPECTATION SIDE, AND THE FIRST VERSION OF THIS ROW PUT THEM ON THE
        // REPLY SIDE AND WAS VACUOUS. A mutant dropping '_' from the Trim set left it GREEN, because
        // IsSatisfied matches with Contains, not equality: "_the final line_".Contains("the final line")
        // holds whether or not the underscore was stripped. Stripping is only OBSERVABLE when the
        // decoration is on the expectation, where Normalise builds the NEEDLE - an undecorated reply then
        // cannot contain a needle that still carries its underscores. Same shape as the existing row
        // An_expected_echo_carrying_its_OWN_markdown_matches_an_undecorated_quote, for the other characters.
        var undecoratedReply = "the final line of the file\n\n[VERDICT: ALIGNED]\n";
        Assert.True(SemanticEcho.IsSatisfied(undecoratedReply, "_the final line of the file_"));
        Assert.True(SemanticEcho.IsSatisfied(undecoratedReply, "__the final line of the file__"));
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
    public void ExpectedFrom_refuses_an_artifact_larger_than_the_cap()
    {
        // An unbounded read on the ask path: "the artifact" could be a multi-gigabyte log. Streaming
        // bounds the MEMORY but not the time, so the size is capped too.
        //
        // THIS IS A MULTI-GUARD REGRESSION TARGET, and that is measured, not assumed. TWO guards can
        // satisfy it - the handle check (CanSeek + Length) and the read budget - so removing EITHER one
        // alone leaves this row green, and removing BOTH reds it. That is defense-in-depth rather than a
        // vacuous test, but it means this row cannot tell you WHICH guard is missing. The two exist for
        // different reasons: the handle check refuses a non-file atomically (a path can change between a
        // File.Exists check and the open, and a pipe HANGS rather than throwing), while the budget bounds
        // a file that keeps GROWING under FileShare.ReadWrite, where a length taken at open time is only
        // a snapshot. Neither is separately testable in-process; see docs/coverage-debt.md.
        var path = Path.Combine(_dir, "huge.md");
        File.WriteAllText(path, new string('a', SemanticEcho.MaxArtifactBytes + 1));
        Assert.Null(SemanticEcho.ExpectedFrom(path));
    }

    [Fact]
    public void A_single_ENORMOUS_line_is_bounded_and_never_becomes_the_echo_target()
    {
        // CAPSTONE R11 FINDING. The previous guard budgeted BETWEEN lines, which cannot protect against a
        // read that never returns: StreamReader.ReadLine has no upper bound, so a writer appending
        // without a newline makes it buffer until it hangs or throws OutOfMemory. The reader now splits
        // lines itself with a capped line buffer.
        //
        // The line here is well under the 4 MB file cap, so the handle check passes and this row
        // exercises the LINE cap specifically - the guard the file-size check cannot reach.
        var path = Path.Combine(_dir, "one-huge-line.md");
        File.WriteAllText(path, new string('a', SemanticEcho.MaxLineChars * 4));   // no newline at all

        // Returns null rather than a 4096-character fragment: an echo target the peer could never
        // reproduce verbatim would red every honest reply, which is worse than having no target.
        Assert.Null(SemanticEcho.ExpectedFrom(path));
    }

    [Fact]
    public void A_normal_line_after_an_enormous_one_is_still_found()
    {
        // The passing control. Without it, a reader that simply gave up on any file containing a long
        // line would satisfy the row above while silently disabling the echo for real artifacts.
        var path = Path.Combine(_dir, "huge-then-normal.md");
        File.WriteAllText(path, new string('a', SemanticEcho.MaxLineChars * 2) + "\nthe last real sentence\n");
        Assert.Equal("the last real sentence", SemanticEcho.ExpectedFrom(path));
    }

    [Fact]
    public void A_blank_or_whitespace_expectation_is_treated_as_NO_expectation()
    {
        // A primary artifact ending in blank lines yields an empty "last line". Demanding an empty echo
        // would fail every reply. Degrade to no-expectation rather than to always-fail.
        Assert.True(SemanticEcho.IsSatisfied("anything\n\n[VERDICT: ALIGNED]\n", "   "));
    }
}
