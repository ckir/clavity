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

public class ProfileJsonTests
{
    private static string Doctor(string schema = "agent-profile/doctor/1", string checkId = "launch_environment",
        string name = "CLAUDE_CONFIG_DIR", string value = "\"/p/work/claude\"") =>
        "{\"schema\":\"" + schema + "\",\"checks\":[{\"id\":\"" + checkId +
        "\",\"data\":{\"kind\":\"env\",\"name\":\"" + name + "\",\"value\":" + value + "}}]}";

    [Fact]
    public void ReadConfigDir_returns_the_launch_environment_value() =>
        Assert.Equal("/p/work/claude", ProfileJson.ReadConfigDir(Doctor()));

    [Theory]
    [InlineData("agent-profile/doctor/2", "launch_environment", "CLAUDE_CONFIG_DIR")]
    [InlineData("agent-profile/doctor/1", "other_check", "CLAUDE_CONFIG_DIR")]
    [InlineData("agent-profile/doctor/1", "launch_environment", "OTHER_VAR")]
    public void ReadConfigDir_is_null_for_wrong_schema_check_or_name(string schema, string id, string name) =>
        Assert.Null(ProfileJson.ReadConfigDir(Doctor(schema, id, name)));

    [Theory]
    [InlineData("\"\"")]
    [InlineData("null")]
    [InlineData("42")]
    [InlineData("true")]
    [InlineData("[\"/x\"]")]
    public void ReadConfigDir_is_null_for_an_empty_or_non_string_value(string value) =>
        Assert.Null(ProfileJson.ReadConfigDir(Doctor(value: value)));

    [Theory]
    [InlineData("not json")]
    [InlineData("")]
    [InlineData("null")]
    [InlineData("[]")]
    [InlineData("42")]
    [InlineData("{}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\"}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\",\"checks\":{}}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\",\"checks\":[1,null,\"x\",[]]}")]
    [InlineData("{\"schema\":7,\"checks\":[]}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\",\"checks\":[{\"id\":\"launch_environment\",\"data\":null}]}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\",\"checks\":[{\"id\":\"launch_environment\",\"data\":5}]}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\",\"checks\":[{\"id\":\"launch_environment\"}]}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\",\"checks\":[{\"id\":9,\"data\":{\"name\":\"CLAUDE_CONFIG_DIR\",\"value\":\"/x\"}}]}")]
    [InlineData("{\"schema\":\"agent-profile/doctor/1\",\"checks\":[{\"id\":\"launch_environment\",\"data\":{\"name\":3,\"value\":\"/x\"}}]}")]
    public void ReadConfigDir_never_throws_and_is_null_on_malformed_input(string json) =>
        Assert.Null(ProfileJson.ReadConfigDir(json));

    [Fact]
    public void ReadConfigDir_null_input_is_null() => Assert.Null(ProfileJson.ReadConfigDir(null!));

    [Fact]
    public void ReadPluginState_Enabled_for_an_enabled_user_entry() =>
        Assert.Equal(PluginState.Enabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"agy-autotrain@clavity\",\"scope\":\"user\",\"enabled\":true}]", "agy-autotrain@clavity"));

    [Fact]
    public void ReadPluginState_Enabled_when_enabled_is_absent() =>
        Assert.Equal(PluginState.Enabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"user\"}]", "a@b"));

    [Fact]
    public void ReadPluginState_Disabled_when_enabled_is_false() =>
        Assert.Equal(PluginState.Disabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":false}]", "a@b"));

    [Fact]
    public void ReadPluginState_Absent_for_a_project_scope_entry() =>
        Assert.Equal(PluginState.Absent, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"project\",\"enabled\":true}]", "a@b"));

    [Fact]
    public void ReadPluginState_Absent_for_a_bare_name_against_an_id() =>
        Assert.Equal(PluginState.Absent, ProfileJson.ReadPluginState(
            "[{\"id\":\"clavity\",\"scope\":\"user\",\"enabled\":true}]", "clavity@clavity"));

    [Fact]
    public void ReadPluginState_user_entry_wins_over_a_project_entry_of_the_same_id() =>
        Assert.Equal(PluginState.Disabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"project\",\"enabled\":true},{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":false}]", "a@b"));

    [Theory]
    [InlineData("[]")]
    [InlineData("garbage")]
    [InlineData("")]
    [InlineData("null")]
    [InlineData("42")]
    [InlineData("{}")]
    [InlineData("{\"id\":\"a@b\",\"scope\":\"user\"}")]
    [InlineData("[1,null,\"x\",[],true]")]
    [InlineData("[{\"id\":5,\"scope\":\"user\"}]")]
    [InlineData("[{\"id\":\"a@b\",\"scope\":5}]")]
    [InlineData("[{\"id\":\"a@b\",\"scope\":null}]")]
    [InlineData("[{\"scope\":\"user\"}]")]
    public void ReadPluginState_never_throws_and_is_Absent_on_malformed_input(string json) =>
        Assert.Equal(PluginState.Absent, ProfileJson.ReadPluginState(json, "a@b"));

    [Theory]
    [InlineData("\"false\"")]
    [InlineData("\"true\"")]
    [InlineData("0")]
    [InlineData("1")]
    [InlineData("null")]
    [InlineData("{}")]
    public void ReadPluginState_a_non_boolean_enabled_is_Disabled_fail_closed(string enabled) =>
        Assert.Equal(PluginState.Disabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":" + enabled + "}]", "a@b"));

    [Fact]
    public void ReadPluginState_first_duplicate_user_entry_decides_true_then_false() =>
        Assert.Equal(PluginState.Enabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":true},{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":false}]", "a@b"));

    [Fact]
    public void ReadPluginState_first_duplicate_user_entry_decides_false_then_true() =>
        Assert.Equal(PluginState.Disabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":false},{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":true}]", "a@b"));

    [Theory]
    [InlineData("\"   \"")]
    [InlineData("\"\\t\\n\"")]
    public void ReadConfigDir_is_null_for_a_whitespace_only_value(string value) =>
        Assert.Null(ProfileJson.ReadConfigDir(Doctor(value: value)));

    [Theory]
    [InlineData("{\"name\":\"CLAUDE_CONFIG_DIR\",\"value\":\"/x\"}")]
    [InlineData("{\"kind\":\"other\",\"name\":\"CLAUDE_CONFIG_DIR\",\"value\":\"/x\"}")]
    public void ReadConfigDir_does_not_require_data_kind_env(string data) =>
        Assert.Equal("/x", ProfileJson.ReadConfigDir(
            "{\"schema\":\"agent-profile/doctor/1\",\"checks\":[{\"id\":\"launch_environment\",\"data\":" + data + "}]}"));

    [Fact]
    public void ReadPluginState_null_input_is_Absent() =>
        Assert.Equal(PluginState.Absent, ProfileJson.ReadPluginState(null!, "a@b"));

    private const string Markets = "[{\"name\":\"clavity\",\"source\":\"github\",\"repo\":\"ckir/clavity\"}]";

    [Fact]
    public void HasMarketplace_true_for_a_listed_name() => Assert.True(ProfileJson.HasMarketplace(Markets, "clavity"));

    [Fact]
    public void HasMarketplace_false_for_an_unlisted_name() => Assert.False(ProfileJson.HasMarketplace(Markets, "other"));

    [Theory]
    [InlineData("garbage")]
    [InlineData("")]
    [InlineData("null")]
    [InlineData("{}")]
    [InlineData("[]")]
    [InlineData("[1,null,\"clavity\",[]]")]
    [InlineData("[{\"name\":5}]")]
    [InlineData("[{\"name\":null}]")]
    public void HasMarketplace_never_throws_and_is_false_on_malformed_input(string json) =>
        Assert.False(ProfileJson.HasMarketplace(json, "clavity"));

    [Fact]
    public void HasMarketplace_null_input_is_false() => Assert.False(ProfileJson.HasMarketplace(null!, "clavity"));
}
