namespace Clavity.Ls;

/// <summary>The typed reply from agy_ask. Answer = the trailing assistant prose (null if the delta ended on a
/// non-assistant step — read Activity). Activity = the COMPLETE step record (nothing dropped), head-truncated.</summary>
public sealed record AskReply(
    string CascadeId,
    string? Answer,
    IReadOnlyList<ActivityItem> Activity,
    bool AnswerTruncated,
    bool ActivityTruncated);

/// <summary>One summarized step of the reply delta. Summary = bounded prose for assistant/user steps, else null.</summary>
public sealed record ActivityItem(int Kind, string Label, string? Summary);

/// <summary>On agy_ask timeout: where agy was. NewAgySteps discounts the injected user step; LastStepClass splits
/// a slow tool (don't abandon) from a true hang.</summary>
public sealed record TimeoutDiagnostic(
    int TotalSteps, int NewAgySteps, int LastStepKind, string LastStepClass, string? LastStepSummary);

/// <summary>agy_status result. State = idle | working | unknown.</summary>
public sealed record AgyStatus(string CascadeId, int TotalSteps, string State, int LastStepKind);

/// <summary>Maps agy step kinds to a label + a coarse class. 14=user, 15=assistant, everything else = tool
/// (the spec's "tool" + "unknown" both fail-safe to slow). Built from the captured trajectory golden.</summary>
public static class StepKind
{
    public const int UserKind = 14;
    public const int AssistantKind = 15;

    public static string Class(int kind) => kind switch
    {
        UserKind => "user",
        AssistantKind => "assistant",
        _ => "tool",
    };

    public static string Label(int kind) => kind switch
    {
        UserKind => "user",
        AssistantKind => "assistant",
        _ => $"step {kind}",
    };
}
