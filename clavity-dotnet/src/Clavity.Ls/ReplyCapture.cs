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
using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>ROADMAP section 74, C-capture: the server writes the FULL text of every assistant step of an ask's delta to
/// a file, so a reply the [13b] checks flag - or an Answer cut at 16 000 characters - can be read whole without a
/// re-ask. Every failure is RETURNED, never thrown: a capture must never fail the ask (spec panel R1, CA1).</summary>
public static class ReplyCapture
{
    /// <summary>Largest capture, in characters. Over it the head and the tail are kept - the verdict sits at the end.</summary>
    public const int MaxChars = 1024 * 1024;
    public const int HeadChars = 768 * 1024;
    public const int TailChars = 128 * 1024;

    /// <summary>Files kept per directory - a COUNT, not an age: a long session would defeat an age rule (D-prune).</summary>
    public const int Keep = 50;

    public static (string? Path, string? Error) Write(string dir, string cascadeId, int firstStepIndex, IReadOnlyList<CascadeStep> delta)
    {
        try
        {
            if (!IsSafeName(cascadeId)) return (null, $"cascade id '{Clip(cascadeId)}' is not safe in a file name");
            var text = Render(firstStepIndex, delta);
            Directory.CreateDirectory(dir);
            var path = System.IO.Path.Combine(dir, $"{cascadeId}-{firstStepIndex}.md");
            File.WriteAllText(path, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            return (path, null);
        }
        catch (Exception ex)
        {
            return (null, OneLine(ex));
        }
        finally
        {
            Prune(dir, Keep);   // after every write ATTEMPT (D-prune)
        }
    }

    /// <summary>Each assistant step with text, preceded by <c>----- agy step &lt;index&gt; -----</c>, where index is the
    /// step's position in the trajectory (<paramref name="firstStepIndex"/> + its position in the delta).</summary>
    public static string Render(int firstStepIndex, IReadOnlyList<CascadeStep> delta)
    {
        var sb = new StringBuilder();
        for (var i = 0; i < delta.Count; i++)
        {
            if (delta[i].Kind != StepKind.AssistantKind) continue;
            var t = delta[i].AssistantOutput?.Text;
            if (string.IsNullOrEmpty(t)) continue;
            sb.Append("----- agy step ").Append(firstStepIndex + i).Append(" -----\n").Append(t);
            if (!t.EndsWith('\n')) sb.Append('\n');
        }
        var all = sb.ToString();
        if (all.Length <= MaxChars) return all;
        var head = TextCut.Prefix(all, HeadChars);
        var tailStart = TextCut.SuffixStart(all, all.Length - TailChars);
        var omitted = tailStart - head.Length;
        return string.Concat(head, $"\n----- cut: {omitted} characters omitted -----\n", all.AsSpan(tailStart));
    }

    /// <summary>Delete all but the newest <paramref name="keep"/> <c>*.md</c> files. Best-effort: never throws.</summary>
    public static void Prune(string dir, int keep)
    {
        try
        {
            if (!Directory.Exists(dir)) return;
            var surplus = new DirectoryInfo(dir).GetFiles("*.md")
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .ThenByDescending(f => f.Name, StringComparer.Ordinal)
                .Skip(keep);
            foreach (var f in surplus)
            {
                try { f.Delete(); } catch { /* best-effort */ }
            }
        }
        catch { /* best-effort: pruning never fails the ask */ }
    }

    /// <summary>A cascade id becomes part of a file name, so only ASCII letters, digits and '-' are accepted.</summary>
    public static bool IsSafeName(string s) => s.Length is > 0 and <= 100 && s.All(c => char.IsAsciiLetterOrDigit(c) || c == '-');

    public static string OneLine(Exception ex) => Clip($"{ex.GetType().Name}: {ex.Message}".ReplaceLineEndings(" "));

    public static string Clip(string s, int max = 200) => TextCut.Prefix(s, max);
}
