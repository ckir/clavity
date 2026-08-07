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
    /// <summary>Max step COUNT emitted by either bounded projection — <c>ActivityItem</c>s in an <c>agy_ask</c> reply
    /// (<see cref="ProjectAskReply"/>) and <c>BoundedStep</c>s in an <c>agy_look</c> view (<see cref="Summarize"/>).
    /// The char budget alone does NOT bound a peer that emits a huge COUNT of zero-text steps (each costs 0 chars) —
    /// cap the count so the JSON stays small. Applied to <c>agy_ask</c> from the start; <c>agy_look</c> was left
    /// uncapped until 2026-08-07 and emitted 750 steps under a 900-char budget.</summary>
    public const int MaxActivitySteps = 500;

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

            // A step with no prose costs 0 chars, so `used + cost > budgetChars` can NEVER fire for it and
            // the char budget alone cannot bound a tool-heavy cascade. ProjectAskReply already caps the
            // count for exactly this reason (see MaxActivitySteps); Summarize -- the agy_look path -- did
            // not, and returned one entry per step no matter how tight the budget was. Measured: 750 steps
            // emitted under a 900-char budget.
            if (steps.Count >= MaxActivitySteps)
            {
                truncated = true;
                break;
            }

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
    /// FIRST). A delta that ends on a NON-assistant (tool) step still yields a null Answer BY DESIGN ("failure not
    /// hidden" — don't present pre-tool prose as a complete answer when the turn ended on a tool step). Activity =
    /// EVERY delta step summarized — head-truncated (oldest dropped) to the remaining budget so the tail survives.
    /// FALLBACK RESCUE: when Answer is null ONLY because a tool step trailed the prose, the last assistant run is
    /// NOT truncated to <see cref="ActivitySummaryChars"/> in Activity — it gets the Answer budget instead, so a
    /// tool-terminated turn's prose survives intact and the consumer needs no re-ask.
    /// </summary>
    public static AskReply ProjectAskReply(string cascadeId, IReadOnlyList<CascadeStep> delta)
    {
        // 1. Find the LAST contiguous assistant run, skipping any trailing non-assistant (tool) steps.
        //    end = index of the last assistant step; runStart = first index of its contiguous run.
        int end = delta.Count - 1;
        while (end >= 0 && delta[end].Kind != StepKind.AssistantKind) end--;
        int runStart = end + 1; // no assistant step ⇒ runStart(0) > end(-1) ⇒ empty run
        var trailing = new List<string>();
        for (var i = end; i >= 0; i--)
        {
            if (delta[i].Kind != StepKind.AssistantKind) break;
            runStart = i;
            var t = delta[i].AssistantOutput?.Text;
            if (string.IsNullOrEmpty(t)) continue; // skip an empty-text assistant step; don't end the run on it
            trailing.Add(t);
        }
        trailing.Reverse();

        // Answer = the run ONLY when it is TRAILING (the delta ends on assistant prose). A trailing tool step
        // yields a null Answer BY DESIGN — see the class summary and AskReplyProjectionTests ("failure not hidden").
        bool runIsTrailing = end == delta.Count - 1 && trailing.Count > 0;
        string? answer = runIsTrailing ? string.Join("\n", trailing) : null;
        var answerTruncated = false;
        if (answer is not null && answer.Length > AskMaxStepChars)
        {
            answer = answer[..AskMaxStepChars];
            answerTruncated = true;
        }

        // Rescue: null Answer caused ONLY by a trailing tool step ⇒ don't truncate that last assistant run to 200
        // in Activity; give its steps the Answer budget so the prose is not lost. (When the run IS the Answer, its
        // Activity copy stays terse — the prose already lives in Answer, so a full second copy would double the cost.)
        bool rescueRun = !runIsTrailing && trailing.Count > 0;

        // 2. Complete activity record (every step), each summarized.
        string? Summary(int idx, CascadeStep s)
        {
            var t = s.UserInput is { } u && u.Text.Length > 0 ? u.Text
                  : s.AssistantOutput is { } a && a.Text.Length > 0 ? a.Text
                  : null;
            if (t is null) return null;
            int cap = rescueRun && idx >= runStart && idx <= end && s.Kind == StepKind.AssistantKind
                ? AskMaxStepChars : ActivitySummaryChars;
            return t.Length > cap ? t[..cap] : t;
        }
        var all = delta.Select((s, idx) => new ActivityItem(s.Kind, StepKind.Label(s.Kind), Summary(idx, s))).ToList();

        // 3. Activity gets the remaining budget; drop from the HEAD until it fits (preserve the tail).
        var remaining = AskBudgetChars - (answer?.Length ?? 0);
        var activityTruncated = false;
        var costs = all.Select(a => a.Summary?.Length ?? 0).ToList();
        var total = costs.Sum();
        var start = 0;
        while ((total > remaining || all.Count - start > MaxActivitySteps) && start < all.Count)
        {
            total -= costs[start];
            start++;
            activityTruncated = true;
        }
        var activity = all.Skip(start).ToList();

        return new AskReply(cascadeId, answer, activity, answerTruncated, activityTruncated);
    }
}
