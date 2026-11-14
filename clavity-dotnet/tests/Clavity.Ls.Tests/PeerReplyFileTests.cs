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
using Clavity.Ls;
using Clavity.Ls.Proto;
using Xunit;

namespace Clavity.Ls.Tests;

public class PeerReplyFileTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "prf-" + Guid.NewGuid().ToString("N"));
    public PeerReplyFileTests() => Directory.CreateDirectory(_root);
    public void Dispose() { if (Directory.Exists(_root)) Directory.Delete(_root, recursive: true); }

    private static Clavity.Ls.Proto.Metadata Md(params string[] uris)
    {
        var md = new Clavity.Ls.Proto.Metadata();
        foreach (var u in uris) md.Workspaces.Add(new Workspace { WorkspaceFolderAbsoluteUri = u });
        return md;
    }

    private void Shield(string content)
    {
        Directory.CreateDirectory(Path.Combine(_root, ".clavity"));
        File.WriteAllText(Path.Combine(_root, ".clavity", ".gitignore"), content);
    }

    [Fact]
    public void One_local_workspace_is_the_root() =>
        Assert.Equal((_root, (string?)null), PeerReplyFile.ResolveRoot(Md(new Uri(_root).AbsoluteUri), null));

    [Fact]
    public void Unknown_none_several_and_non_file_workspaces_request_nothing()
    {
        Assert.Contains("unknown", PeerReplyFile.ResolveRoot(null, "Unimplemented").Status);
        Assert.Contains("no workspace", PeerReplyFile.ResolveRoot(Md(), null).Status);
        Assert.Contains("2 workspaces", PeerReplyFile.ResolveRoot(Md(new Uri(_root).AbsoluteUri, new Uri(_root).AbsoluteUri), null).Status);
        Assert.Contains("not a local folder", PeerReplyFile.ResolveRoot(Md("https://example.com/x"), null).Status);
        Assert.Null(PeerReplyFile.ResolveRoot(null, "x").Root);
    }

    [Fact]
    public void Prepare_requires_a_bare_star_line_in_the_shield()
    {
        Assert.Contains(".gitignore", PeerReplyFile.Prepare(_root, "abc", 7).Status);   // no shield at all
        Shield("*.log\n");
        Assert.Null(PeerReplyFile.Prepare(_root, "abc", 7).Path);                        // a shield without '*'
        Shield("# shield\n*\n");
        var (path, nonce, status) = PeerReplyFile.Prepare(_root, "abc", 7);
        Assert.Null(status);
        Assert.Equal(Path.Combine(_root, ".clavity", "scratch", "agy-replies", "abc-7.md"), path);
        Assert.Matches("^[0-9a-f]{32}$", nonce);
        Assert.True(Directory.Exists(Path.GetDirectoryName(path)));
    }

    [Fact]
    public void The_request_block_ends_on_the_nonce_line_and_names_the_path()
    {
        var block = PeerReplyFile.RequestBlock(@"C:\w\.clavity\scratch\agy-replies\abc-7.md", "0123456789abcdef0123456789abcdef");
        var lines = block.Split('\n');
        Assert.Equal("agy-reply-nonce: 0123456789abcdef0123456789abcdef", lines[^1]);
        Assert.Contains(@"C:\w\.clavity\scratch\agy-replies\abc-7.md", lines);
        Assert.StartsWith("\n\n", block);
    }

    [Fact]
    public void TryRead_returns_the_body_after_a_matching_nonce_line()
    {
        var f = Path.Combine(_root, "r.md");
        File.WriteAllText(f, "agy-reply-nonce: n1\r\n\r\nreport\r\n[VERDICT: ALIGNED]");
        Assert.Equal(("report\n[VERDICT: ALIGNED]", (string?)null), PeerReplyFile.TryRead(f, "n1"));
    }

    [Fact]
    public void TryRead_refuses_absent_wrong_nonce_and_oversized_files()
    {
        var f = Path.Combine(_root, "r.md");
        Assert.Contains("did not write", PeerReplyFile.TryRead(f, "n1").Status);
        File.WriteAllText(f, "agy-reply-nonce: OTHER\n\nreport");
        Assert.Contains("nonce", PeerReplyFile.TryRead(f, "n1").Status);
        File.WriteAllText(f, "agy-reply-nonce: n1\n\n" + new string('x', PeerReplyFile.MaxBytes));
        var big = PeerReplyFile.TryRead(f, "n1");
        Assert.Null(big.Body);
        Assert.Contains("cap", big.Status);
    }

    [Fact]
    public void TryRead_accepts_a_file_of_exactly_MaxBytes_and_refuses_one_byte_more()
    {
        // The cap is inclusive: the oversized row above overshoots by the 21-byte nonce prefix and never probes the edge.
        var f = Path.Combine(_root, "edge.md");
        const string prefix = "agy-reply-nonce: n1\n\n";
        File.WriteAllText(f, prefix + new string('x', PeerReplyFile.MaxBytes - prefix.Length));
        Assert.Equal(PeerReplyFile.MaxBytes, new FileInfo(f).Length);
        var atCap = PeerReplyFile.TryRead(f, "n1");
        Assert.Null(atCap.Status);
        Assert.Equal(PeerReplyFile.MaxBytes - prefix.Length, atCap.Body!.Length);
        File.WriteAllText(f, prefix + new string('x', PeerReplyFile.MaxBytes - prefix.Length + 1));
        Assert.Equal(PeerReplyFile.MaxBytes + 1, new FileInfo(f).Length);
        var over = PeerReplyFile.TryRead(f, "n1");
        Assert.Null(over.Body);
        Assert.Contains("cap", over.Status);
    }
}
