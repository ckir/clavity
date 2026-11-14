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

public class StartArgsTests
{
    private const string Sid = "11111111-2222-3333-4444-555555555555";
    private static readonly string Cwd = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "cwd"));
    private static readonly string Repo = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "repo"));

    [Fact]
    public void A_bare_folder_is_the_folder_and_nothing_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo }, Cwd);
        Assert.Equal(Repo, a.Folder);
        Assert.Null(a.AttachSessionId);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Without_a_folder_the_current_directory_is_used_and_dash_args_reach_Claude()
    {
        var a = StartArgs.Parse(new[] { "--model", "opus" }, Cwd);
        Assert.Equal(Cwd, a.Folder);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_directly_after_the_folder_is_consumed_and_the_rest_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", Sid, "--model", "opus" }, Cwd);
        Assert.Equal(Repo, a.Folder);
        Assert.True(a.Attach);
        Assert.Equal(Sid, a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_without_a_folder_uses_the_current_directory()
    {
        var a = StartArgs.Parse(new[] { "--attach", Sid }, Cwd);
        Assert.Equal(Cwd, a.Folder);
        Assert.True(a.Attach);
        Assert.Equal(Sid, a.AttachSessionId);
    }

    [Fact]
    public void Attach_after_a_Claude_argument_is_NOT_ours_and_reaches_Claude_untouched()
    {
        var a = StartArgs.Parse(new[] { Repo, "--model", "opus", "--attach", Sid }, Cwd);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus", "--attach", Sid }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_with_nothing_after_it_has_no_id()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Attach_followed_by_a_dash_argument_has_no_id_and_the_argument_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "--model", "opus" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Without_attach_Attach_is_false()
        => Assert.False(StartArgs.Parse(new[] { Repo }, Cwd).Attach);

    [Fact]
    public void Attach_followed_by_a_positional_prompt_has_no_id_and_the_prompt_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "fix the tests" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "fix the tests" }, a.ClaudeArgs);
    }

    [Fact]
    public void A_path_after_attach_is_not_an_id_and_never_becomes_a_file_name()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "../../etc" }, Cwd);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "../../etc" }, a.ClaudeArgs);
    }

    [Theory]
    [InlineData("11111111222233334444555555555555")]      // GUID "N" form
    [InlineData("11111111-2222-3333-4444-55555555555")]   // one digit short
    [InlineData("deadbeef")]                              // 8 hex: shaped like a truncated id
    public void Attach_with_a_malformed_id_is_refused_quoting_it(string bad)
    {
        var ex = Assert.Throws<ArgumentException>(() => StartArgs.Parse(new[] { Repo, "--attach", bad }, Cwd));
        Assert.Contains($"'{bad}'", ex.Message);
    }

    [Fact]
    public void Profile_directly_after_the_folder_is_consumed()
    {
        var a = StartArgs.Parse(new[] { Repo, "--profile", "work", "--model", "opus" }, Cwd);
        Assert.Equal("work", a.Profile);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
        Assert.False(a.Attach);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void Profile_and_attach_may_come_in_either_order(bool profileFirst)
    {
        var args = profileFirst
            ? new[] { Repo, "--profile", "work", "--attach", Sid }
            : new[] { Repo, "--attach", Sid, "--profile", "work" };
        var a = StartArgs.Parse(args, Cwd);
        Assert.Equal("work", a.Profile);
        Assert.True(a.Attach);
        Assert.Equal(Sid, a.AttachSessionId);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Attach_without_an_id_followed_by_profile_keeps_both()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "--profile", "work" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Equal("work", a.Profile);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Profile_without_the_flag_is_null()
        => Assert.Null(StartArgs.Parse(new[] { Repo }, Cwd).Profile);

    [Fact]
    public void Profile_after_a_Claude_argument_belongs_to_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "-c", "--profile", "x" }, Cwd);
        Assert.Null(a.Profile);
        Assert.Equal(new[] { "-c", "--profile", "x" }, a.ClaudeArgs);
    }

    [Theory]
    [InlineData(new object[] { new[] { "--profile" } })]
    [InlineData(new object[] { new[] { "--profile", "" } })]
    [InlineData(new object[] { new[] { "--profile", "  " } })]
    [InlineData(new object[] { new[] { "--profile", "-x" } })]
    [InlineData(new object[] { new[] { "--profile", "a", "--profile", "b" } })]
    public void Bad_profile_values_are_usage_errors(string[] tail)
        => Assert.Throws<ArgumentException>(() => StartArgs.Parse(new[] { Repo }.Concat(tail).ToArray(), Cwd));

    [Fact]
    public void A_relative_folder_is_resolved_against_the_given_current_directory_not_the_process_one()
    {
        var cwd = Path.Combine(Path.GetTempPath(), "clavity-args-cwd");
        var parsed = StartArgs.Parse(new[] { Path.Combine("sub", "repo") }, cwd);
        Assert.Equal(Path.GetFullPath(Path.Combine(cwd, "sub", "repo")), parsed.Folder);
    }
}
