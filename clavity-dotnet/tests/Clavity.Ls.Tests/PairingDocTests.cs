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

public sealed class PairingDocTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-pairingdoc-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    // The source of truth is clavity-dotnet/pairing/agy-pairing-INSTALL.md, linked into the test output by the
    // csproj. The embedded copy must be byte-identical to it - a stale or empty resource would hand agy the
    // wrong instructions, and nothing downstream would notice.
    private static byte[] SourceDoc() => File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, PairingDoc.FileName));

    [Fact]
    public void Embedded_doc_is_byte_identical_to_the_source_doc()
    {
        var source = SourceDoc();
        Assert.NotEmpty(source);
        Assert.Equal(source, PairingDoc.ReadEmbedded());
    }

    [Fact]
    public void Materialize_creates_the_directory_and_writes_the_doc()
    {
        Assert.False(Directory.Exists(_dir));

        var path = PairingDoc.Materialize(_dir);

        Assert.Equal(Path.Combine(_dir, PairingDoc.FileName), path);
        Assert.Equal(SourceDoc(), File.ReadAllBytes(path));
    }

    [Fact]
    public void Materialize_replaces_a_stale_doc_left_by_an_older_version()
    {
        Directory.CreateDirectory(_dir);
        var path = Path.Combine(_dir, PairingDoc.FileName);
        File.WriteAllText(path, "stale instructions from an older clavity-ls");

        Assert.Equal(path, PairingDoc.Materialize(_dir));
        Assert.Equal(SourceDoc(), File.ReadAllBytes(path));
    }

    // Two releases' docs can have the same length, so the skip must compare BYTES: a stale doc of exactly the
    // current length must still be replaced.
    [Fact]
    public void Materialize_replaces_a_stale_doc_of_the_same_length()
    {
        Directory.CreateDirectory(_dir);
        var path = Path.Combine(_dir, PairingDoc.FileName);
        var stale = new byte[SourceDoc().Length];
        Array.Fill(stale, (byte)'x');
        File.WriteAllBytes(path, stale);

        PairingDoc.Materialize(_dir);

        Assert.Equal(SourceDoc(), File.ReadAllBytes(path));
    }

    // When the final move fails, the temp file must not be left behind in ~/.clavity, and the failure must reach
    // the caller as one of the exceptions `start` turns into a refusal. A directory squatting on the doc's name
    // makes the move fail deterministically on every platform.
    [Fact]
    public void Materialize_leaves_no_temp_file_when_the_move_fails()
    {
        Directory.CreateDirectory(Path.Combine(_dir, PairingDoc.FileName));

        var ex = Record.Exception(() => PairingDoc.Materialize(_dir));

        Assert.True(ex is IOException or UnauthorizedAccessException, $"unexpected {ex?.GetType().Name ?? "no exception"}");
        Assert.Empty(Directory.GetFiles(_dir));
    }

    [Fact]
    public void Materialize_is_idempotent_and_leaves_no_temp_files()
    {
        var first = PairingDoc.Materialize(_dir);
        var second = PairingDoc.Materialize(_dir);

        Assert.Equal(first, second);
        Assert.Equal(SourceDoc(), File.ReadAllBytes(second));
        Assert.Equal(new[] { PairingDoc.FileName }, Directory.GetFiles(_dir).Select(Path.GetFileName));
    }

    // Replacing a file that another process has open fails on Windows (measured: File.Move onto an open file is
    // "Access to the path is denied" under every share mode), and start then refuses to launch. Skipping the
    // write when the bytes already match keeps that risk to the one start after an upgrade, so pin the skip by
    // its effect: an unchanged doc is not rewritten.
    [Fact]
    public void Materialize_does_not_rewrite_a_doc_that_already_matches()
    {
        var path = PairingDoc.Materialize(_dir);
        var marker = new DateTime(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        File.SetLastWriteTimeUtc(path, marker);

        PairingDoc.Materialize(_dir);

        Assert.Equal(marker, File.GetLastWriteTimeUtc(path));
    }
}
