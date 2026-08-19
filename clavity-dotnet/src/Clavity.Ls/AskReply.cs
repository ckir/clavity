namespace Clavity.Ls;

/// <summary>The typed reply from agy_ask. Answer = the trailing assistant prose (null if the delta ended on a
/// non-assistant step — read Activity). Activity = the COMPLETE step record (nothing dropped), head-truncated.</summary>
public sealed record AskReply(
    string CascadeId,
    string? Answer,
    IReadOnlyList<ActivityItem> Activity,
    bool AnswerTruncated,
    bool ActivityTruncated,
    // 13b. All three default to false so every existing construction site and test is unaffected.
    // TerminalTokenMissing is a DETERMINISTIC verdict: the discipline named a token and the reply does
    // not end with it. SizeAnomaly is a HEURISTIC WARNING and must never be treated as proof.
    bool TerminalTokenMissing = false,
    // The peer did not quote the artifact's last line near its verdict: it never reached the end, or
    // never read the artifact at all. Deterministic like TerminalTokenMissing, and strictly stronger -
    // it is the only flag that catches a reply whose token is present but whose body was never written.
    bool EchoMissing = false,
    bool SizeAnomaly = false);

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

/// <summary>agy_status result. State = idle | working | unknown, or one of the FAULT states
/// channel_down | resource_exhausted | auth_failed | invalid_request (see <see cref="ChannelDown.StatusFor"/>, which is
/// the single source of truth — add a state there and here together). Diagnostic + Hint are populated on every FAULT
/// state alike (they all come from the same catch, which carries the diagnostic) and are null on every healthy state;
/// additive, so existing consumers are unaffected — F7. Consumers must treat "State names a fault" rather than
/// "State == channel_down" as the test for a populated Diagnostic.</summary>
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
