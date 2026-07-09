using Clavity.Ls;
using Clavity.Ls.Proto;

namespace Clavity.Ls.Tests;

public class AskReplyProjectionTests
{
    private static CascadeStep User(string t) => new() { Kind = 14, UserInput = new CascadeUserInput { Text = t } };
    private static CascadeStep Asst(string t) => new() { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = t } };
    private static CascadeStep Tool(int kind = 90) => new() { Kind = kind };

    private static AskReply Project(params CascadeStep[] delta) =>
        BoundedView.ProjectAskReply("c", delta);

    [Fact]
    public void Trailing_assistant_step_becomes_Answer()
    {
        var r = Project(User("hi"), Asst("the answer"));
        Assert.Equal("the answer", r.Answer);
        Assert.False(r.AnswerTruncated);
        Assert.Equal(2, r.Activity.Count); // complete record
    }

    [Fact]
    public void Delta_ending_on_a_tool_step_yields_null_Answer_but_keeps_prose_in_Activity()
    {
        var r = Project(Asst("I found the bug"), Tool());
        Assert.Null(r.Answer);                                   // failure not hidden
        Assert.Contains(r.Activity, a => a.Summary == "I found the bug"); // prose preserved
    }

    [Fact]
    public void Trailing_tool_step_keeps_null_Answer_but_recovers_the_full_last_prose_in_Activity()
    {
        // The "failure not hidden" signal (null Answer) is preserved, but the last assistant run is NOT
        // truncated to the 200-char Activity cap — it gets the Answer budget so a tool-terminated turn's
        // verdict survives intact and the consumer needs no re-ask (the bug this fix targets).
        var longProse = new string('z', 4000); // >> ActivitySummaryChars: would be lost under the flat cap
        var r = Project(Asst(longProse), Tool());
        Assert.Null(r.Answer);                                            // signal preserved
        var lastAsst = r.Activity.Last(a => a.Kind == StepKind.AssistantKind);
        Assert.Equal(4000, lastAsst.Summary!.Length);                     // full prose recovered, not clipped to 200
        Assert.False(r.ActivityTruncated);
    }

    [Fact]
    public void Answered_turn_keeps_Activity_copy_terse_no_double_budget()
    {
        // When the run IS the Answer, its Activity copy must stay at the 200 cap — the prose already lives in
        // Answer, so a full second copy would double the char cost.
        var longProse = new string('q', 4000);
        var r = Project(Asst(longProse));
        Assert.Equal(longProse, r.Answer);
        var asst = r.Activity.Single(a => a.Kind == StepKind.AssistantKind);
        Assert.Equal(BoundedView.ActivitySummaryChars, asst.Summary!.Length); // terse, not rescued
    }

    [Fact]
    public void Trailing_contiguous_assistant_run_joins()
    {
        var r = Project(Tool(), Asst("part 1"), Asst("part 2"));
        Assert.Equal("part 1\npart 2", r.Answer);
    }

    [Fact]
    public void Empty_text_assistant_step_mid_run_is_skipped_not_a_run_terminator()
    {
        // An empty-text Kind-15 step (agy emits these) must NOT end the trailing run and drop the earlier prose.
        var r = Project(Tool(), Asst("part 1"), Asst(""), Asst("part 2"));
        Assert.Equal("part 1\npart 2", r.Answer);
    }

    [Fact]
    public void A_huge_count_of_zero_text_steps_is_capped_by_step_count_not_just_chars()
    {
        // Zero-text steps cost 0 chars, so the char budget never trims them — the COUNT cap must, preserving the tail.
        var steps = Enumerable.Range(0, BoundedView.MaxActivitySteps + 50).Select(_ => Tool()).ToArray();
        var r = Project(steps);
        Assert.True(r.ActivityTruncated);
        Assert.Equal(BoundedView.MaxActivitySteps, r.Activity.Count);
    }

    [Fact]
    public void Over_cap_answer_sets_AnswerTruncated_only()
    {
        var big = new string('x', BoundedView.AskMaxStepChars + 50);
        var r = Project(Asst(big));
        Assert.True(r.AnswerTruncated);
        Assert.False(r.ActivityTruncated);
        Assert.True(r.Answer!.Length <= BoundedView.AskMaxStepChars);
    }

    [Fact]
    public void Activity_truncates_from_the_head_preserving_the_tail()
    {
        // Many activity steps with summaries; force the activity budget to drop oldest, keep newest.
        var steps = Enumerable.Range(0, 400).Select(i => User($"step-{i}-{new string('y', 200)}")).ToArray();
        var r = Project(steps);
        Assert.True(r.ActivityTruncated);
        Assert.NotEmpty(r.Activity);
        Assert.Equal(399, ExtractIndex(r.Activity[^1].Summary)); // newest kept at the tail
    }

    private static int ExtractIndex(string? s) => int.Parse(s!.Split('-')[1]);

    [Fact]
    public void Labels_known_kinds_and_classifies()
    {
        Assert.Equal("user", StepKind.Class(14));
        Assert.Equal("assistant", StepKind.Class(15));
        Assert.Equal("tool", StepKind.Class(90));        // non-LLM ⇒ tool (covers spec's tool+unknown)
        Assert.Equal("step 90", StepKind.Label(90));
        Assert.Equal("user", StepKind.Label(14));
    }
}
