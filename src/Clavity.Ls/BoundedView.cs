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
    /// <summary>Per-step cap for an <c>ActivityItem.Summary</c> (a terse "what agy did", never a tool's full output).</summary>
    public const int ActivitySummaryChars = 200;

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

    /// <summary>
    /// Project a reply delta into an <see cref="AskReply"/>. Answer = the trailing CONTIGUOUS run of assistant
    /// (Kind-15) steps, joined chronologically, capped at <see cref="AskMaxStepChars"/> (Answer claims the budget
    /// FIRST). Activity = EVERY delta step summarized — head-truncated (oldest dropped) to the remaining budget so
    /// the tail (where failures surface) survives.
    /// </summary>
    public static AskReply ProjectAskReply(string cascadeId, IReadOnlyList<CascadeStep> delta)
    {
        // 1. Trailing contiguous assistant run → Answer.
        var trailing = new List<string>();
        for (var i = delta.Count - 1; i >= 0; i--)
        {
            if (delta[i].Kind != StepKind.AssistantKind) break;
            var t = delta[i].AssistantOutput?.Text;
            if (string.IsNullOrEmpty(t)) break;
            trailing.Add(t);
        }
        trailing.Reverse();
        string? answer = trailing.Count == 0 ? null : string.Join("\n", trailing);
        var answerTruncated = false;
        if (answer is not null && answer.Length > AskMaxStepChars)
        {
            answer = answer[..AskMaxStepChars];
            answerTruncated = true;
        }

        // 2. Complete activity record (every step), each summarized.
        static string? Summary(CascadeStep s)
        {
            var t = s.UserInput is { } u && u.Text.Length > 0 ? u.Text
                  : s.AssistantOutput is { } a && a.Text.Length > 0 ? a.Text
                  : null;
            return t is null ? null : t.Length > ActivitySummaryChars ? t[..ActivitySummaryChars] : t;
        }
        var all = delta.Select(s => new ActivityItem(s.Kind, StepKind.Label(s.Kind), Summary(s))).ToList();

        // 3. Activity gets the remaining budget; drop from the HEAD until it fits (preserve the tail).
        var remaining = AskBudgetChars - (answer?.Length ?? 0);
        var activityTruncated = false;
        var costs = all.Select(a => a.Summary?.Length ?? 0).ToList();
        var total = costs.Sum();
        var start = 0;
        while (total > remaining && start < all.Count)
        {
            total -= costs[start];
            start++;
            activityTruncated = true;
        }
        var activity = all.Skip(start).ToList();

        return new AskReply(cascadeId, answer, activity, answerTruncated, activityTruncated);
    }
}
