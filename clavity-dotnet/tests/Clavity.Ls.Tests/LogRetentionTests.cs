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

namespace Clavity.Ls.Tests;

public class LogRetentionTests
{
    [Fact]
    public void Prune_deletes_logs_older_than_max_age_and_keeps_recent_ones()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-logret-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var now = new DateTime(2026, 6, 28, 12, 0, 0, DateTimeKind.Utc);
            var old = Path.Combine(dir, "clavity-old.log");
            var fresh = Path.Combine(dir, "clavity-fresh.log");
            var unrelated = Path.Combine(dir, "cli.log");
            File.WriteAllText(old, "");
            File.WriteAllText(fresh, "");
            File.WriteAllText(unrelated, "");
            File.SetLastWriteTimeUtc(old, now.AddDays(-8));
            File.SetLastWriteTimeUtc(fresh, now.AddDays(-1));
            File.SetLastWriteTimeUtc(unrelated, now.AddDays(-30));

            LogRetention.Prune(dir, TimeSpan.FromDays(7), now);

            Assert.False(File.Exists(old), "old clavity log should be pruned");
            Assert.True(File.Exists(fresh), "recent clavity log should be kept");
            Assert.True(File.Exists(unrelated), "non-clavity logs must not be touched");
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void Prune_on_missing_directory_does_not_throw() =>
        LogRetention.Prune(
            Path.Combine(Path.GetTempPath(), "clavity-no-such-" + Guid.NewGuid().ToString("N")),
            TimeSpan.FromDays(7), DateTime.UtcNow);

    [Fact]
    public void Prune_skips_a_file_it_cannot_delete_and_still_prunes_what_it_can()
    {
        // A directory without write permission makes File.Delete throw UnauthorizedAccessException; the swallowed branch must
        // neither throw nor stop the sweep. (POSIX only: Windows ACLs are not set up from here; root ignores the mode.)
        if (OperatingSystem.IsWindows() || Environment.UserName == "root")
            return;
        var dir = Path.Combine(Path.GetTempPath(), "clavity-logret-ro-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var now = new DateTime(2026, 6, 28, 12, 0, 0, DateTimeKind.Utc);
        var old = Path.Combine(dir, "clavity-old.log");
        File.WriteAllText(old, "");
        File.SetLastWriteTimeUtc(old, now.AddDays(-8));
        var original = File.GetUnixFileMode(dir);
        File.SetUnixFileMode(dir, UnixFileMode.UserRead | UnixFileMode.UserExecute);
        try
        {
            LogRetention.Prune(dir, TimeSpan.FromDays(7), now);   // must not throw
            Assert.True(File.Exists(old), "a file that cannot be deleted stays");
        }
        finally
        {
            File.SetUnixFileMode(dir, original);
            Directory.Delete(dir, true);
        }
    }
}
