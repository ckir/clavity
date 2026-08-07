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

/// <summary>On a dead/failed clavity-ls -> agy channel: the underlying gRPC failure. StatusCode = the gRPC
/// StatusCode name (e.g. "Unavailable"), or the concrete exception type name ("ObjectDisposed"/"LsDiscovery")
/// when no RpcException is available; Detail = the failure detail/message. Never "Unknown" while a real cause
/// exists (F4).</summary>
public sealed record ChannelDiagnostic(string StatusCode, string Detail);

/// <summary>agy_status result. State = idle | working | unknown | channel_down | payload_too_large. Diagnostic + Hint
/// ONLY on channel_down (null on every healthy state; additive, so existing consumers are unaffected — F7).</summary>
public sealed record AgyStatus(
    string CascadeId, int TotalSteps, string State, int LastStepKind,
    ChannelDiagnostic? Diagnostic = null, string? Hint = null);

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
