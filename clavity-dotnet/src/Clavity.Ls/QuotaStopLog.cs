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



using System.Text;
using System.Text.RegularExpressions;

namespace Clavity.Ls;

/// <summary>ROADMAP section 66. agy reports a quota stop ONLY in its own log and in its terminal; on the wire the turn
/// ends with no assistant text, which agy_ask could not tell from a dropped reply. The log is the file clavity-ls already
/// opens for port discovery (AgyViewOptions.CliLogPath), so: remember its length when an ask starts, and after the wait
/// scan what was APPENDED for the quota event. Position, not time: glog stamps carry no year or zone.</summary>
public static partial class QuotaStopLog   // not `QuotaStop`: that is the AskReply FIELD it fills, and `QuotaStop = QuotaStop.FindSince(...)` reads badly
{
    /// <summary>Only this much of the appended region is scanned, from its END: the event is written as the turn ends,
    /// so it is near the tail, and a chatty log must not make every ask read megabytes.</summary>
    public const long ScanWindow = 1024 * 1024;

    // The two lines agy writes per event both end with this; the capture is the human sentence after the code.
    // The trailing lookahead requires a COMPLETE line: agy may still be writing it when the scan runs, and a half-written
    // "Resets in 2" must not be reported as a 2-unit reset. A missed event degrades to today's [13b] notice, never to a wrong one.
    [GeneratedRegex(@"RESOURCE_EXHAUSTED \(code 429\): (Individual quota reached\.[^\r\n]*?Resets in [^\s.]+\.?)(?=\r?\n)", RegexOptions.CultureInvariant)]
    private static partial Regex EventRegex();

    // The sentence is lifted from a LOG FILE into the driver's context (test-audit Branch 4 R1, BS-1): control characters
    // (an escape sequence, a tab, a NUL) are mapped to '?' exactly as ArgumentPrecheck does for client-supplied names.
    private static string Printable(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s) sb.Append(char.IsControl(c) ? '?' : c);
        return sb.ToString();
    }

    /// <summary>The log's current length, or 0 when it cannot be read. Never throws.</summary>
    public static long Mark(string? path)
    {
        try { return path is not null && File.Exists(path) ? new FileInfo(path).Length : 0; }
        catch { return 0; }
    }

    /// <summary>The quota message appended after <paramref name="mark"/>, or null. A file shorter than the mark (rotated,
    /// truncated) is scanned from the start. Opened shared: agy holds the file open for writing. Never throws.</summary>
    public static string? FindSince(string? path, long mark)
    {
        try
        {
            if (path is null || !File.Exists(path)) return null;
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var start = mark <= fs.Length ? mark : 0;
            if (fs.Length - start > ScanWindow) start = fs.Length - ScanWindow;
            fs.Position = start;
            using var reader = new StreamReader(fs, Encoding.UTF8, detectEncodingFromByteOrderMarks: false);
            var appended = reader.ReadToEnd();
            string? last = null;
            foreach (Match m in EventRegex().Matches(appended)) last = m.Groups[1].Value;
            return last is null ? null : Printable(last);
        }
        catch { return null; }
    }
}
