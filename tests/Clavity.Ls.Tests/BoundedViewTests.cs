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
}
