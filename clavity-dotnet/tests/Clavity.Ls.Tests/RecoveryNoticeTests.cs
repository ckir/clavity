// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



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

    private static AskReply WithAnswer(string? answer, bool cut = false) =>
        new("c", answer, Array.Empty<ActivityItem>(), cut, false, TerminalTokenMissing: true);

    [Fact]
    public void Terminal_detail_names_the_expected_token_and_the_line_the_driver_saw()
    {
        var d = RecoveryNotice.TerminalDetail("VERDICT:", WithAnswer("report\n\nPANEL VERDICT: CLEAN\n"));
        Assert.Contains("'VERDICT:'", d);
        Assert.Contains("'PANEL VERDICT: CLEAN'", d);
        Assert.DoesNotContain("adversarial-panel-review closes", d);   // the panel hint is for the panel mismatch only
    }

    [Fact]
    public void Panel_asked_for_PANEL_VERDICT_but_ended_on_a_bracket_VERDICT_line_gets_the_specific_hint()
    {
        var d = RecoveryNotice.TerminalDetail("PANEL VERDICT", WithAnswer("report\n[VERDICT: GREEN]\n"));
        Assert.Contains("'PANEL VERDICT'", d);
        Assert.Contains("'[VERDICT: GREEN]'", d);
        Assert.Contains("adversarial-panel-review closes each round on a line starting PANEL VERDICT", d);
        Assert.Contains("fix the brief", d);
    }

    [Fact]
    public void The_panel_hint_is_not_shown_for_a_panel_reply_that_simply_stopped_mid_sentence()
    {
        var d = RecoveryNotice.TerminalDetail("PANEL VERDICT", WithAnswer("report that stops in the middle of a sen"));
        Assert.Contains("'report that stops in the middle of a sen'", d);
        Assert.DoesNotContain("adversarial-panel-review closes", d);
    }

    [Fact]
    public void A_cut_Answer_does_not_quote_its_last_line_because_that_is_not_the_replys_last_line()
    {
        var d = RecoveryNotice.TerminalDetail("PANEL VERDICT", WithAnswer("the first sixteen thousand characters", cut: true));
        Assert.DoesNotContain("the first sixteen", d);
        Assert.Contains($"{BoundedView.AskMaxStepChars} characters", d);
    }

    [Fact]
    public void The_quoted_line_is_clipped_at_exactly_one_hundred_characters()
    {
        // Test audit MG-1: 'shorter than 600' passed for any clip from 50 to 500.
        var hundred = new string('a', 100);
        Assert.Contains($"'{hundred}')", RecoveryNotice.TerminalDetail("VERDICT:", WithAnswer(hundred)));          // exactly the limit: whole line
        var d = RecoveryNotice.TerminalDetail("VERDICT:", WithAnswer(hundred + "b"));                              // one over: clipped to the limit
        Assert.Contains($"'{hundred}')", d);
        Assert.DoesNotContain(hundred + "b", d);
    }

    [Fact]
    public void A_cut_Answer_that_happens_to_end_on_a_bracket_VERDICT_line_gets_no_panel_hint()
    {
        // The prefix cut at the cap is not the reply's end, so its last line proves nothing about the closing line.
        var d = RecoveryNotice.TerminalDetail("PANEL VERDICT", WithAnswer("quoted earlier in the reply\n[VERDICT: GREEN]\n", cut: true));
        Assert.DoesNotContain("adversarial-panel-review closes", d);
        Assert.DoesNotContain("[VERDICT: GREEN]", d);
    }

    [Fact]
    public void An_empty_reply_says_so()
    {
        Assert.Contains("no reply text", RecoveryNotice.TerminalDetail("VERDICT:", WithAnswer(null)));
        Assert.Contains("no reply text", RecoveryNotice.TerminalDetail("VERDICT:", WithAnswer("  \n")));
    }

    [Fact]
    public void A_very_long_last_line_is_clipped()
    {
        var d = RecoveryNotice.TerminalDetail("VERDICT:", WithAnswer(new string('x', 5000)));
        Assert.True(d.Length < 600, $"{d.Length} chars");
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
