// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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
    [InlineData("0")]
    [InlineData("null")]
    public void ReadPluginState_a_non_boolean_enabled_is_not_Disabled(string enabled) =>
        Assert.Equal(PluginState.Enabled, ProfileJson.ReadPluginState(
            "[{\"id\":\"a@b\",\"scope\":\"user\",\"enabled\":" + enabled + "}]", "a@b"));

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
