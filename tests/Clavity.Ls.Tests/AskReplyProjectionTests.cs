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
