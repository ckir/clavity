namespace Clavity.Ls;

/// <summary>ROADMAP section 74, C-order: ONE recovery order, stated in every flagged notice as one compact sentence
/// carrying the concrete paths. Self-sufficient on purpose: a flagged notice fires only on a failed check, and it can
/// arrive after compaction has dropped both the once-per-session guidance block and the skill text (spec panel R5, CA1).
/// The skills carry the explanation; this carries the steps.</summary>
public static class RecoveryNotice
{
    /// <summary>Most characters the sentence may add to a notice, with this machine's real path lengths.</summary>
    public const int MaxChars = 400;

    public static string Sentence(AskReply r)
    {
        var noFile = r.ReplyFile is null && r.PeerFile is null;
        var steps = new List<string>();
        if (r.ReplyFile is { } replyFile) steps.Add($"read the last 200 lines of {replyFile}");
        if (r.PeerFile is { } peerFile) steps.Add($"read {peerFile} if it exists");
        if (noFile) steps.Add("agy_look, for a SHORT reply only (1000 characters per step)");
        steps.Add("re-ask at most once");
        steps.Add("halt and ask your human");

        var why = ReplyCapture.Clip(r.CaptureError ?? "off", 80);
        var lead = noFile ? $"No reply file is available (capture: {why}). "
                 : r.ReplyFile is null ? $"The capture failed ({why}). "
                 : "";
        return lead + "Recover in this order: " + string.Join("; ", steps.Select((s, i) => $"({i + 1}) {s}")) + ".";
    }

    public static string AnswerCut(AskReply r)
    {
        var file = r.CheckedSource == "peer-file" ? r.PeerFile : r.ReplyFile;
        return file is not null
            ? $"[13b] ANSWER CUT: Answer holds only the first {BoundedView.AskMaxStepChars} characters; the whole reply is in {file} - read its last 200 lines for the verdict."
            : $"[13b] ANSWER CUT: Answer holds only the first {BoundedView.AskMaxStepChars} characters, and the whole reply is not on disk ({ReplyCapture.Clip(r.CaptureError ?? "capture is off", 80)}); re-ask for a shorter reply if you need the rest.";
    }

    public static string Rescued(AskReply r) =>
        "[13b] RESCUED FROM PEER FILE: the chat reply failed the completeness checks"
        + (r.TurnEndedOnToolStep ? " (the turn ended on a tool step)" : "")
        + $", but the reply file the peer wrote, {r.PeerFile}, passed them - Answer is that file's text"
        + (r.AnswerTruncated ? $", cut to its first {BoundedView.AskMaxStepChars} characters: read the file's last 200 lines for the verdict." : ".");
}
