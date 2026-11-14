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



using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

// ROADMAP section 66. Fixture = the real two-line event agy wrote on 2026-10-01 (verbatim; only the pid column varies).
public class QuotaStopTests
{
    private const string Event =
        "E1001 21:09:09.415251  308834 errorreport.go:224] agent executor error: generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n" +
        "E1001 21:09:09.531891  308834 errorreport.go:224] generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n";
    private const string Noise = "I1001 21:09:08.000000  308834 ls.go:10] language server listening on 50465\n";

    private static string Tmp(string content)
    {
        var p = Path.Combine(Path.GetTempPath(), "quota-" + Guid.NewGuid().ToString("N") + ".log");
        File.WriteAllText(p, content);
        return p;
    }

    [Fact]
    public void An_event_appended_after_the_mark_is_found_with_its_reset()
    {
        var p = Tmp(Noise);
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, Event);
        var found = QuotaStopLog.FindSince(p, mark);
        Assert.NotNull(found);
        Assert.Equal("Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.", found);
    }

    [Fact]
    public void An_event_before_the_mark_does_not_fire()
    {
        var p = Tmp(Event + Noise);
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, Noise);
        Assert.Null(QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_truncated_or_rotated_log_is_rescanned_from_the_start()
    {
        var p = Tmp(new string('x', 500) + "\n");
        var mark = QuotaStopLog.Mark(p);            // 501
        File.WriteAllText(p, Event);             // shorter than the mark
        Assert.NotNull(QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_missing_log_is_no_stop()
    {
        var p = Path.Combine(Path.GetTempPath(), "quota-missing-" + Guid.NewGuid().ToString("N") + ".log");
        Assert.Equal(0, QuotaStopLog.Mark(p));
        Assert.Null(QuotaStopLog.FindSince(p, 0));
        Assert.Null(QuotaStopLog.FindSince(null, 0));
    }

    [Fact]
    public void A_half_written_last_line_does_not_fire_with_a_truncated_reset()
    {
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 21:09:09.5 1 x.go:1] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade. Resets in 2");   // no newline yet
        Assert.Null(QuotaStopLog.FindSince(p, mark));
        File.AppendAllText(p, "4m5s.\n");                                                                 // the line completes
        Assert.Equal("Individual quota reached. Please upgrade. Resets in 24m5s.", QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void When_several_events_were_appended_the_LAST_one_wins()
    {
        // The reset countdown shrinks with time, so the newest event is the most accurate. Test-audit Branch 4 R1, MG-1: the
        // original fixture repeats ONE identical sentence, so a first-match scan was indistinguishable from a last-match scan.
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 21:00:00.1 1 x.go:1] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade. Resets in 24m5s.\n");
        File.AppendAllText(p, "E1001 21:20:00.1 1 x.go:1] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade. Resets in 4m5s.\n");
        Assert.Equal("Individual quota reached. Please upgrade. Resets in 4m5s.", QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void Control_characters_in_the_sentence_are_neutralised()
    {
        // Test-audit Branch 4 R1, BS-1: the sentence is lifted from a log file into the driver's context; an escape
        // sequence or a tab inside it must not survive.
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 x] RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please\u001b[31m upgrade\tnow. Resets in 24m5s.\n");
        Assert.Equal("Individual quota reached. Please?[31m upgrade?now. Resets in 24m5s.", QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_429_that_is_not_a_quota_message_does_not_fire()
    {
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 21:09:09.5 1 x.go:1] RESOURCE_EXHAUSTED (code 429): too many requests\n");
        Assert.Null(QuotaStopLog.FindSince(p, mark));
    }
}
