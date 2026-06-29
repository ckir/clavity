using System.Linq;
using Clavity.Ls;
using Clavity.Ls.Proto;

namespace Clavity.Ls.Tests;

public class BoundedViewTests
{
    private static CascadeTrajectory Traj(string id, params (int kind, string text)[] steps)
    {
        var t = new CascadeTrajectory { CascadeId = id };
        foreach (var (kind, text) in steps)
            t.Steps.Add(new CascadeStep { Kind = kind, UserInput = new CascadeUserInput { Text = text } });
        return t;
    }

    [Fact]
    public void Assistant_step_reply_text_is_surfaced_not_just_user_input()
    {
        // Regression: agy's reply (kind 15) carries prose in assistant_output (field 20), NOT user_input (19).
        // BoundedView previously read only user_input, so replies came back null.
        var t = new CascadeTrajectory { CascadeId = "c0" };
        t.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "hi" } });
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "Hello! How can I help?" } });

        var v = BoundedView.Summarize(t);

        Assert.Equal("hi", v.Steps[0].Text);
        Assert.Equal(15, v.Steps[1].Kind);
        Assert.Equal("Hello! How can I help?", v.Steps[1].Text);
    }

    [Fact]
    public void Small_trajectory_is_preserved_untruncated()
    {
        var v = BoundedView.Summarize(Traj("c1", (14, "hello"), (15, "world")));

        Assert.Equal("c1", v.CascadeId);
        Assert.Equal(2, v.TotalSteps);
        Assert.Equal(2, v.Steps.Count);
        Assert.False(v.Truncated);
        Assert.Equal(14, v.Steps[0].Kind);
        Assert.Equal("hello", v.Steps[0].Text);
    }

    [Fact]
    public void Fat_trajectory_trims_within_budget_and_flags_truncated()
    {
        var big = new string('x', 2000);
        var steps = Enumerable.Range(0, 50).Select(_ => (15, big)).ToArray();

        var v = BoundedView.Summarize(Traj("c2", steps), budgetChars: 8000);

        var total = v.Steps.Sum(s => s.Text?.Length ?? 0);
        Assert.True(total <= 8000, $"emitted {total} chars > budget 8000");
        Assert.True(v.Truncated);
        Assert.True(v.Steps.Count < 50);
        Assert.Equal(50, v.TotalSteps);
    }

    [Fact]
    public void Per_step_text_is_truncated_to_cap()
    {
        var v = BoundedView.Summarize(Traj("c3", (14, new string('y', 5000))));

        Assert.NotNull(v.Steps[0].Text);
        Assert.True(v.Steps[0].Text!.Length <= BoundedView.MaxStepTextChars + 1);
    }

    [Fact]
    public void Ask_caps_allow_a_full_long_reply_uncapped_below_the_ask_per_step_limit()
    {
        // A 5000-char reply exceeds the LOOK 1000 cap but is under the ASK 16000 cap → must come back whole.
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = new string('z', 5000) } });

        var v = BoundedView.Summarize(t, BoundedView.AskBudgetChars, BoundedView.AskMaxStepChars, newestFirst: true);

        Assert.Equal(5000, v.Steps[0].Text!.Length);
        Assert.False(v.Truncated);
    }

    [Fact]
    public void Ask_newestFirst_keeps_the_final_reply_when_budget_is_tight()
    {
        // Older noisy step would overflow the budget in forward order, dropping the real answer.
        // newestFirst must KEEP the final reply and drop the older step instead.
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = new string('x', 8000) } });
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "THE ANSWER" } });

        var v = BoundedView.Summarize(t, budgetChars: 8000, maxStepChars: 16000, newestFirst: true);

        Assert.Contains(v.Steps, s => s.Text == "THE ANSWER");
        Assert.True(v.Truncated);
    }

    [Fact]
    public void Ask_newestFirst_returns_kept_steps_in_chronological_order()
    {
        var t = new CascadeTrajectory { CascadeId = "c" };
        t.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "first" } });
        t.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "second" } });

        var v = BoundedView.Summarize(t, BoundedView.AskBudgetChars, BoundedView.AskMaxStepChars, newestFirst: true);

        Assert.Equal(2, v.Steps.Count);
        Assert.Equal("first", v.Steps[0].Text);
        Assert.Equal("second", v.Steps[1].Text);
        Assert.False(v.Truncated);
    }
}
