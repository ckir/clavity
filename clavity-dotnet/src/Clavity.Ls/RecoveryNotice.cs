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

    /// <summary>What a TRUNCATED REPLY notice adds: the token the discipline requires and the line the driver actually saw, so a
    /// closing line in the wrong vocabulary is told apart from a reply that was cut. When the Answer is itself cut at the cap its
    /// last line is NOT the reply's last line, so none is quoted. The adversarial-panel-review hint appears only for the mismatch
    /// seen in the flux sessions: the panel token was required and the reply ended on a [VERDICT: ...] line.</summary>
    public static string TerminalDetail(string expected, AskReply r)
    {
        string? line = r.AnswerTruncated ? null : TerminalToken.LastLine(r.Answer);
        var seen = r.AnswerTruncated
            ? $"the reply is longer than {BoundedView.AskMaxStepChars} characters, so its last line is in the file named below"
            : line is null ? "there was no reply text"
            : $"the last non-blank line was '{ReplyCapture.Clip(line, 100)}'";
        var hint = expected == "PANEL VERDICT" && line is not null
                   && TerminalToken.StripDecoration(line).StartsWith("VERDICT:", StringComparison.Ordinal)
            ? "; adversarial-panel-review closes each round on a line starting PANEL VERDICT, and the [VERDICT: ...] vocabulary belongs to "
              + "agy-first, agy-capstone and agy-test-audit: if the brief demanded it, fix the brief"
            : "";
        return $" (expected a last line starting with '{expected}'; {seen}{hint})";
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
