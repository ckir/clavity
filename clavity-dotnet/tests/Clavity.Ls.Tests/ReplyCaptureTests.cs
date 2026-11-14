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
using System.IO;
using System.Linq;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Xunit;

namespace Clavity.Ls.Tests;

public class ReplyCaptureTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "rc-" + Guid.NewGuid().ToString("N"));
    public void Dispose() { if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true); }

    private static CascadeStep User(string t) => new() { Kind = 14, UserInput = new CascadeUserInput { Text = t } };
    private static CascadeStep Asst(string t) => new() { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = t } };
    private static CascadeStep Tool() => new() { Kind = 5 };

    [Fact]
    public void Writes_every_assistant_step_with_its_trajectory_index()
    {
        var (path, error) = ReplyCapture.Write(_dir, "abc-123", 40, new[] { User("q"), Asst("report"), Tool(), Asst("Noted.") });
        Assert.Null(error);
        Assert.Equal(Path.Combine(_dir, "abc-123-40.md"), path);
        Assert.Equal("----- agy step 41 -----\nreport\n----- agy step 43 -----\nNoted.\n", File.ReadAllText(path!));
    }

    [Fact]
    public void Over_the_cap_keeps_head_and_tail_and_says_how_much_was_cut()
    {
        var big = new string('h', ReplyCapture.MaxChars) + "THE-VERDICT";
        var text = ReplyCapture.Render(0, new[] { Asst(big) });
        Assert.StartsWith("----- agy step 0 -----\nhhh", text);
        Assert.EndsWith("THE-VERDICT\n", text);
        var all = "----- agy step 0 -----\n".Length + big.Length + 1;
        Assert.Contains($"\n----- cut: {all - ReplyCapture.HeadChars - ReplyCapture.TailChars} characters omitted -----\n", text);
        Assert.True(text.Length < ReplyCapture.MaxChars);
    }

    [Fact]
    public void A_failed_write_is_returned_never_thrown()
    {
        Directory.CreateDirectory(_dir);
        var blocker = Path.Combine(_dir, "a-file");
        File.WriteAllText(blocker, "x");
        var (path, error) = ReplyCapture.Write(blocker, "abc", 1, new[] { Asst("r") });   // a FILE where the dir should be
        Assert.Null(path);
        Assert.False(string.IsNullOrWhiteSpace(error));
        Assert.DoesNotContain('\n', error!);
    }

    [Fact]
    public void An_unsafe_cascade_id_is_refused()
    {
        var (path, error) = ReplyCapture.Write(_dir, "..\\evil", 1, new[] { Asst("r") });
        Assert.Null(path);
        Assert.Contains("not safe", error);
    }

    [Fact]
    public void Prune_keeps_the_newest_N_md_files_only()
    {
        Directory.CreateDirectory(_dir);
        var t0 = DateTime.UtcNow.AddHours(-1);
        for (var i = 0; i < 5; i++)
        {
            var f = Path.Combine(_dir, $"f{i}.md");
            File.WriteAllText(f, "x");
            File.SetLastWriteTimeUtc(f, t0.AddMinutes(i));
        }
        File.WriteAllText(Path.Combine(_dir, "keep.txt"), "not a capture");
        ReplyCapture.Prune(_dir, 2);
        Assert.Equal(new[] { "f3.md", "f4.md", "keep.txt" },
                     Directory.GetFiles(_dir).Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal).ToArray());
    }

    private static bool HasLoneSurrogate(string s)
    {
        for (var i = 0; i < s.Length; i++)
        {
            if (char.IsHighSurrogate(s[i]) && !(i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))) return true;
            if (char.IsLowSurrogate(s[i]) && !(i > 0 && char.IsHighSurrogate(s[i - 1]))) return true;
        }
        return false;
    }

    [Fact]
    public void An_emoji_straddling_the_head_cut_or_the_tail_cut_is_never_split()
    {
        // Capstone R1 BS1. Put a surrogate pair exactly across BOTH cut points: its high half is the last char the
        // head would keep, and its low half is the first char the tail would keep.
        const string emoji = "\U0001F600";
        var header = "----- agy step 0 -----\n".Length;
        var pre = new string('h', ReplyCapture.HeadChars - 1 - header);
        var mid = new string('m', 200_000);
        var text = pre + emoji + mid + emoji + new string('t', ReplyCapture.TailChars - 2);

        var rendered = ReplyCapture.Render(0, new[] { Asst(text) });

        Assert.Contains("characters omitted", rendered);
        Assert.False(HasLoneSurrogate(rendered), "the cut left half of an emoji");
        Assert.True(HasLoneSurrogate(text.Substring(0, ReplyCapture.HeadChars - header)),
                    "control: a raw cut of this very text DOES split the pair, so the row can fail");
    }

    [Fact]
    public void Clip_never_splits_a_surrogate_pair()
    {
        // Capstone R2 FA4: Clip shortens error text that ends up in the result JSON.
        var s = new string('a', 199) + "\U0001F600" + "zzz";
        var c = ReplyCapture.Clip(s, 200);
        Assert.Equal(199, c.Length);
        Assert.Equal(new string('a', 199), c);
        Assert.Equal("short", ReplyCapture.Clip("short", 200));
    }
}
