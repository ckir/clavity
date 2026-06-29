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
    /// <summary>Generous total budget for an <c>agy_ask</c> reply (the reply is a small delta you want whole).</summary>
    public const int AskBudgetChars = 32_000;
    /// <summary>Per-step cap for an <c>agy_ask</c> reply — large enough for a full prose answer, still bounds a runaway step.</summary>
    public const int AskMaxStepChars = 16_000;

    public static BoundedTrajectory Summarize(
        CascadeTrajectory trajectory,
        int budgetChars = DefaultBudgetChars,
        int maxStepChars = MaxStepTextChars,
        bool newestFirst = false)
    {
        var ordered = newestFirst
            ? Enumerable.Reverse(trajectory.Steps).ToList()
            : trajectory.Steps.ToList();

        var steps = new List<BoundedStep>();
        var used = 0;
        var truncated = false;

        foreach (var step in ordered)
        {
            // Surface the step's prose: user-message text (field 19) OR assistant-reply text (field 20).
            string? text =
                step.UserInput is { } ui && ui.Text.Length > 0 ? ui.Text
                : step.AssistantOutput is { } ao && ao.Text.Length > 0 ? ao.Text
                : null;
            if (text is not null && text.Length > maxStepChars)
                text = string.Concat(text.AsSpan(0, maxStepChars), "…");

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

        // Restore chronological order when we filled from the newest end (agy_ask).
        if (newestFirst)
            steps.Reverse();

        return new BoundedTrajectory(trajectory.CascadeId, trajectory.Steps.Count, steps, truncated);
    }
}
