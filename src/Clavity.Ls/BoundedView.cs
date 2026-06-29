using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>One trimmed step in a <see cref="BoundedTrajectory"/>: just the step kind and (truncated) text.</summary>
public sealed record BoundedStep(int Kind, string? Text);

/// <summary>
/// A size-budgeted, id-free summary of a cascade trajectory — safe to hand to an LLM as a "look".
/// Carries only the cascade id (the addressable handle), per-step kind, and truncated step text; it never
/// surfaces the trajectory's verbose internals (step metadata ids/timestamps, generator/executor metadata,
/// permission arrays) because those proto fields are not modeled/read.
/// </summary>
public sealed record BoundedTrajectory(string CascadeId, int TotalSteps, IReadOnlyList<BoundedStep> Steps, bool Truncated);

/// <summary>
/// Trims a verbose <see cref="CascadeTrajectory"/> into a <see cref="BoundedTrajectory"/> within a character
/// budget (spec §5): each step's text is capped, and steps are included only until the total budget is hit.
/// </summary>
public static class BoundedView
{
    public const int DefaultBudgetChars = 8000;
    public const int MaxStepTextChars = 1000;

    public static BoundedTrajectory Summarize(CascadeTrajectory trajectory, int budgetChars = DefaultBudgetChars)
    {
        var steps = new List<BoundedStep>();
        var used = 0;
        var truncated = false;

        foreach (var step in trajectory.Steps)
        {
            // Surface the step's prose: user-message text (field 19) OR assistant-reply text (field 20).
            // Before this, only user_input was read, so agy's replies (kind 15) came back null.
            string? text =
                step.UserInput is { } ui && ui.Text.Length > 0 ? ui.Text
                : step.AssistantOutput is { } ao && ao.Text.Length > 0 ? ao.Text
                : null;
            if (text is not null && text.Length > MaxStepTextChars)
                text = string.Concat(text.AsSpan(0, MaxStepTextChars), "…");

            var cost = text?.Length ?? 0;
            if (used + cost > budgetChars)
            {
                truncated = true;
                break;
            }

            used += cost;
            steps.Add(new BoundedStep(step.Kind, text));
        }

        if (steps.Count < trajectory.Steps.Count)
            truncated = true;

        return new BoundedTrajectory(trajectory.CascadeId, trajectory.Steps.Count, steps, truncated);
    }
}
