using System;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class RecoveryNoticeTests
{
    // This box's real lengths: an 80-character capture path and a 110-character peer path (Task 1 measured the root).
    private static readonly string Capture = @"C:\Users\user\.clavity\agy-replies\" + new string('c', 36) + "-179.md";
    private static readonly string Peer = @"C:\Users\user\Development\Rust\clavity\.clavity\scratch\agy-replies\" + new string('p', 36) + "-179.md";
    private static AskReply R(string? replyFile = null, string? peerFile = null, string? captureError = null,
                              string? checkedSource = null, bool cut = false, bool tool = false) =>
        new("c", "a", Array.Empty<ActivityItem>(), cut, false, ReplyFile: replyFile, CaptureError: captureError,
            CheckedSource: checkedSource, TurnEndedOnToolStep: tool, PeerFile: peerFile);

    [Fact]
    public void Both_files_give_the_four_step_order_with_the_capture_END_first()
    {
        var s = RecoveryNotice.Sentence(R(Capture, Peer));
        Assert.Equal($"Recover in this order: (1) read the last 200 lines of {Capture}; (2) read {Peer} if it exists; (3) re-ask at most once; (4) halt and ask your human.", s);
        Assert.True(s.Length <= RecoveryNotice.MaxChars, $"{s.Length} chars");
    }

    [Fact]
    public void A_failed_capture_drops_step_one_and_says_so()
    {
        var s = RecoveryNotice.Sentence(R(peerFile: Peer, captureError: new string('e', 300)));
        Assert.StartsWith("The capture failed (", s);
        Assert.DoesNotContain("last 200 lines", s);
        Assert.Contains($"(1) read {Peer} if it exists", s);
        Assert.True(s.Length <= RecoveryNotice.MaxChars, $"{s.Length} chars");
    }

    [Fact]
    public void No_file_at_all_names_the_two_steps_left_never_a_dead_end()
    {
        var s = RecoveryNotice.Sentence(R(captureError: new string('e', 300)));
        Assert.StartsWith("No reply file is available (capture: ", s);
        Assert.Contains("(1) agy_look, for a SHORT reply only (1000 characters per step); (2) re-ask at most once; (3) halt and ask your human.", s);
        Assert.True(s.Length <= RecoveryNotice.MaxChars, $"{s.Length} chars");
    }

    [Fact]
    public void Answer_cut_points_at_the_file_the_Answer_came_from()
    {
        Assert.Contains(Capture, RecoveryNotice.AnswerCut(R(Capture, Peer, checkedSource: "chat", cut: true)));
        Assert.Contains(Peer, RecoveryNotice.AnswerCut(R(Capture, Peer, checkedSource: "peer-file", cut: true)));
        Assert.DoesNotContain(Capture, RecoveryNotice.AnswerCut(R(Capture, Peer, checkedSource: "peer-file", cut: true)));
        Assert.Contains("not on disk", RecoveryNotice.AnswerCut(R(captureError: "IOException: x", cut: true)));
    }

    [Fact]
    public void Rescued_says_which_file_passed_and_reports_a_tool_ended_turn()
    {
        var s = RecoveryNotice.Rescued(R(Capture, Peer, checkedSource: "peer-file", tool: true));
        Assert.StartsWith("[13b] RESCUED FROM PEER FILE:", s);
        Assert.Contains(Peer, s);
        Assert.Contains("the turn ended on a tool step", s);
        Assert.Contains("last 200 lines", RecoveryNotice.Rescued(R(Capture, Peer, checkedSource: "peer-file", cut: true)));
    }
}
