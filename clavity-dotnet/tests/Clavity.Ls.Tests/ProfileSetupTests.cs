// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.ComponentModel;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>`start --profile` setup (spec Design 3a-3f): the ORDER of agent-profile and claude commands, the lock, and
/// every failure path. The Fake scripts results by command line.</summary>
public sealed class ProfileSetupTests
{
    private static readonly string Dir = Path.Combine(Path.GetTempPath(), "clavity-profile-dir");

    private const string Create = "agent-profile claude create work";
    private const string Doctor = "agent-profile claude doctor work --json";
    private const string List = "claude plugin list --json";
    private const string MktList = "claude plugin marketplace list --json";
    private const string MktAddClavity = "claude plugin marketplace add ckir/clavity";
    private const string MktAddSuper = "claude plugin marketplace add obra/superpowers-marketplace";
    private const string InstallClavity = "claude plugin install clavity@clavity -y --scope user";
    private const string InstallSuper = "claude plugin install superpowers@superpowers-marketplace -y --scope user";

    private static CommandResult Ok(string stdout = "") => new(0, stdout, "", false);

    private static string DoctorJson(string dir) =>
        "{\"schema\":\"agent-profile/doctor/1\",\"checks\":[{\"id\":\"launch_environment\",\"data\":" +
        "{\"name\":\"CLAUDE_CONFIG_DIR\",\"value\":" + System.Text.Json.JsonSerializer.Serialize(dir) + "}}]}";

    private static string Plugins(params (string Id, string Enabled)[] ps) =>
        "[" + string.Join(",", ps.Select(p =>
            $"{{\"id\":\"{p.Id}\",\"scope\":\"user\",\"enabled\":{p.Enabled}}}")) + "]";

    /// <summary>A scripted value that hands out <paramref name="results"/> in order, repeating the last.</summary>
    private static Func<CommandResult> Seq(params CommandResult[] results)
    {
        var i = 0;
        return () => results[Math.Min(i++, results.Length - 1)];
    }

    private static Fake NewFake(Dictionary<string, object>? extra = null, bool isWindows = false)
    {
        var script = new Dictionary<string, object> { [Doctor] = Ok(DoctorJson(Dir)) };
        if (extra is not null)
            foreach (var (k, v) in extra)
                script[k] = v;
        return new Fake { IsWindows = isWindows, Script = script };
    }

    private static string[] Cmds(Fake fx) =>
        fx.Calls.Where(c => !c.StartsWith("onpath:", StringComparison.Ordinal) && c != "claude?").ToArray();

    private static string[] L(params string[] calls) => calls;

    private static Dictionary<string, object> BothEnabled() => new()
    {
        [List] = Ok(Plugins(("clavity@clavity", "true"), ("superpowers@superpowers-marketplace", "true"))),
    };

    [Fact]
    public void Fresh_profile_installs_both_plugins_adding_both_marketplaces()
    {
        var fx = NewFake(new()
        {
            [List] = Seq(Ok("[]"), Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true"), ("superpowers@superpowers-marketplace", "true")))),
            [MktList] = Ok("[]"),
        });
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
        Assert.Equal(L(
            "cmd:" + Create, "profile-lock", "cmd:" + Doctor,
            "cmd:" + List, "cmd:" + MktList, "cmd:" + MktAddClavity, "cmd:" + InstallClavity, "cmd:" + List,
            "cmd:" + List, "cmd:" + MktList, "cmd:" + MktAddSuper, "cmd:" + InstallSuper, "cmd:" + List,
            "profile-release"), Cmds(fx));
    }

    [Fact]
    public void Marketplace_already_configured_is_not_added()
    {
        var fx = NewFake(new()
        {
            [List] = Seq(Ok("[]"), Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true"), ("superpowers@superpowers-marketplace", "true")))),
            [MktList] = Ok("[{\"name\":\"clavity\"},{\"name\":\"superpowers-marketplace\"}]"),
        });
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
        Assert.DoesNotContain(fx.Calls, c => c.Contains("marketplace add", StringComparison.Ordinal));
        Assert.Contains("cmd:" + InstallClavity, fx.Calls);
        Assert.Contains("cmd:" + InstallSuper, fx.Calls);
    }

    [Fact]
    public void Enabled_plugins_cause_no_install()
    {
        var fx = NewFake(BothEnabled());
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
        Assert.Equal(L("cmd:" + Create, "profile-lock", "cmd:" + Doctor, "cmd:" + List, "cmd:" + List, "profile-release"), Cmds(fx));
    }

    [Fact]
    public void Disabled_plugin_is_enabled_not_installed()
    {
        var fx = NewFake(new()
        {
            [List] = Seq(Ok(Plugins(("clavity@clavity", "false"))), Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true"), ("superpowers@superpowers-marketplace", "true")))),
        });
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
        Assert.Equal(L("cmd:" + Create, "profile-lock", "cmd:" + Doctor,
            "cmd:" + List, "cmd:claude plugin enable clavity@clavity", "cmd:" + List,
            "cmd:" + List, "profile-release"), Cmds(fx));
    }

    [Fact]
    public void Project_scoped_plugin_counts_as_absent()
    {
        var projectScoped = "[{\"id\":\"clavity@clavity\",\"scope\":\"project\",\"enabled\":true}]";
        var fx = NewFake(new()
        {
            [List] = Seq(Ok(projectScoped), Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true"), ("superpowers@superpowers-marketplace", "true")))),
            [MktList] = Ok("[{\"name\":\"clavity\"}]"),
        });
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
        Assert.Contains("cmd:" + InstallClavity, fx.Calls);
    }

    [Fact]
    public void Plugin_still_not_enabled_after_install_fails()
    {
        var fx = NewFake(new() { [List] = Ok("[]"), [MktList] = Ok("[{\"name\":\"clavity\"}]") });
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.Contains("clavity: ", fx.Err.ToString());
        Assert.Contains("clavity@clavity", fx.Err.ToString());
        Assert.Equal("profile-release", fx.Calls[^1]);
    }

    [Fact]
    public void Doctor_exit_5_with_a_document_continues()
    {
        var fx = NewFake(BothEnabled().Concat(new Dictionary<string, object>
            { [Doctor] = new CommandResult(5, DoctorJson(Dir), "warnings", false) }).ToDictionary(p => p.Key, p => p.Value));
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
    }

    [Fact]
    public void Doctor_exit_5_with_a_missing_directory_fails()
    {
        var fx = NewFake(BothEnabled().Concat(new Dictionary<string, object>
            { [Doctor] = new CommandResult(5, DoctorJson(Dir), "", false) }).ToDictionary(p => p.Key, p => p.Value));
        var missing = new Fake
        {
            Script = fx.Script, MissingDirs = new() { Dir },
        };
        Assert.Null(ProfileSetup.Run(missing, "work"));
        Assert.Contains("clavity: ", missing.Err.ToString());
        Assert.Contains(Dir, missing.Err.ToString());
        Assert.DoesNotContain(missing.Calls, c => c.StartsWith("cmd:claude ", StringComparison.Ordinal));
        Assert.Equal("profile-release", missing.Calls[^1]);
    }

    [Fact]
    public void Doctor_with_bad_json_fails()
    {
        var fx = NewFake(new() { [Doctor] = Ok("not json") });
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.Contains("clavity: ", fx.Err.ToString());
        Assert.Equal("profile-release", fx.Calls[^1]);
    }

    [Fact]
    public void Doctor_with_another_exit_code_fails()
    {
        var fx = NewFake(new() { [Doctor] = new CommandResult(4, DoctorJson(Dir), "bad name", false) });
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.Contains("bad name", fx.Err.ToString());
    }

    [Fact]
    public void Missing_agent_profile_fails_before_any_command()
    {
        var fx = new Fake { AgentProfileOnPath = false };
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.DoesNotContain(fx.Calls, c => c.StartsWith("cmd:", StringComparison.Ordinal));
        Assert.Contains("agent-profile", fx.Err.ToString());
        Assert.StartsWith("clavity: ", fx.Err.ToString());
    }

    [Fact]
    public void Missing_agent_profile_on_Windows_names_the_exe()
    {
        var fx = new Fake { IsWindows = true, AgentProfileOnPath = false };
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.Contains("agent-profile.exe", fx.Err.ToString());
    }

    [Fact]
    public void Missing_claude_fails_before_any_command()
    {
        var fx = new Fake { ClaudeThere = false };
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.DoesNotContain(fx.Calls, c => c.StartsWith("cmd:", StringComparison.Ordinal));
        Assert.Contains("claude", fx.Err.ToString());
        Assert.StartsWith("clavity: ", fx.Err.ToString());
    }

    [Fact]
    public void Windows_uses_agent_profile_exe()
    {
        var fx = NewFake(isWindows: true, extra: new()
        {
            ["agent-profile.exe claude doctor work --json"] = Ok(DoctorJson(Dir)),
            [List] = Ok(Plugins(("clavity@clavity", "true"), ("superpowers@superpowers-marketplace", "true"))),
        });
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
        Assert.Equal("cmd:agent-profile.exe claude create work", Cmds(fx)[0]);
    }

    [Fact]
    public void Create_failing_reports_its_stderr_and_takes_no_lock()
    {
        var fx = NewFake(new() { [Create] = new CommandResult(4, "", "invalid profile name", false) });
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.Contains("invalid profile name", fx.Err.ToString());
        Assert.StartsWith("clavity: ", fx.Err.ToString());
        Assert.DoesNotContain("profile-lock", fx.Calls);
        Assert.DoesNotContain("profile-release", fx.Calls);
    }

    [Fact]
    public void Timeout_fails_naming_the_command()
    {
        var fx = NewFake(new() { [List] = new CommandResult(-1, "", "", true) });
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.Contains("claude plugin list --json", fx.Err.ToString());
        Assert.Contains("timed out", fx.Err.ToString());
        Assert.Equal("profile-release", fx.Calls[^1]);
    }

    [Fact]
    public void Win32Exception_fails_cleanly()
    {
        var fx = NewFake(new() { [Create] = new Win32Exception(2, "The system cannot find the file specified.") });
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.StartsWith("clavity: ", fx.Err.ToString());
        Assert.Contains("The system cannot find the file specified.", fx.Err.ToString());
    }

    [Fact]
    public void Second_plugin_failing_fails_the_whole_run()
    {
        var fx = NewFake(new()
        {
            [List] = Seq(Ok(Plugins(("clavity@clavity", "true"))), Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true")))),
            [MktList] = Ok("[{\"name\":\"superpowers-marketplace\"}]"),
            [InstallSuper] = new CommandResult(1, "", "install exploded", false),
        });
        Assert.Null(ProfileSetup.Run(fx, "work"));
        Assert.Contains("install exploded", fx.Err.ToString());
        Assert.Equal("profile-release", fx.Calls[^1]);
        Assert.Single(fx.Calls, c => c == "profile-release");
    }

    [Fact]
    public void Lock_wait_expiring_fails_naming_the_profile()
    {
        var fx = NewFake(new() { }, false);
        var held = new Fake { ProfileLockHeld = true, Script = fx.Script };
        Assert.Null(ProfileSetup.Run(held, "work"));
        Assert.Contains("timed out waiting for profile 'work' setup", held.Err.ToString());
        Assert.Equal(L("cmd:" + Create, "profile-lock"), Cmds(held));
    }

    [Fact]
    public void Plugin_commands_run_with_CLAUDE_CONFIG_DIR_and_a_neutral_cwd()
    {
        var fx = NewFake(new()
        {
            [List] = Seq(Ok("[]"), Ok(Plugins(("clavity@clavity", "true"))),
                Ok(Plugins(("clavity@clavity", "true"), ("superpowers@superpowers-marketplace", "true")))),
            [MktList] = Ok("[]"),
        });
        Assert.Equal(Dir, ProfileSetup.Run(fx, "work"));
        var claude = fx.CapturedRan.Where(c => c.FileName == "claude").ToList();
        Assert.NotEmpty(claude);
        Assert.All(claude, c =>
        {
            Assert.Equal(Dir, c.Environment["CLAUDE_CONFIG_DIR"]);
            Assert.Equal(fx.UserProfile, c.WorkingDirectory);
        });
        var ap = fx.CapturedRan.Where(c => c.FileName == "agent-profile").ToList();
        Assert.Equal(2, ap.Count);
        Assert.All(ap, c => Assert.False(c.Environment.ContainsKey("CLAUDE_CONFIG_DIR")));
    }
}
