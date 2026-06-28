using System.Linq;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class LauncherTests
{
    private static LaunchOptions Opts(
        string folder = @"C:\work\repo",
        string? projectId = "proj-123",
        string logFile = @"C:\Users\u\.gemini\antigravity-cli\cli.log",
        bool skipPermissions = false,
        params string[] claudeArgs)
        => new()
        {
            Folder = folder,
            ProjectId = projectId,
            AgyLogFilePath = logFile,
            SkipPermissions = skipPermissions,
            ClaudeArgs = claudeArgs,
        };

    [Fact]
    public void AgyTab_is_wt_new_tab_running_pwsh_with_baked_env_and_agy()
    {
        var plan = Launcher.Build(Opts());

        Assert.Equal("wt", plan.AgyTab.FileName);
        Assert.Equal(
            new[] { "new-tab", "--startingDirectory", @"C:\work\repo", "pwsh", "-NoExit", "-Command" },
            plan.AgyTab.Arguments.Take(6));
        Assert.Equal(@"C:\work\repo", plan.AgyTab.WorkingDirectory);

        var script = plan.AgyTab.Arguments[6];
        Assert.Equal(
            "$env:ANTIGRAVITY_CSRF_TOKEN='clavity'; $env:ANTIGRAVITY_PROJECT_ID='proj-123'; " +
            @"agy --log-file 'C:\Users\u\.gemini\antigravity-cli\cli.log'",
            script);
    }

    [Fact]
    public void ProjectId_is_omitted_when_absent()
    {
        var plan = Launcher.Build(Opts(projectId: null));

        var script = plan.AgyTab.Arguments[6];
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", script);
        Assert.StartsWith("$env:ANTIGRAVITY_CSRF_TOKEN='clavity'; agy --log-file ", script);
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", plan.AgyTab.Environment.Keys);
    }

    [Fact]
    public void SkipPermissions_appends_flag_only_when_opted_in()
    {
        Assert.DoesNotContain("--dangerously-skip-permissions", Launcher.Build(Opts()).AgyTab.Arguments[6]);
        Assert.EndsWith(" --dangerously-skip-permissions", Launcher.Build(Opts(skipPermissions: true)).AgyTab.Arguments[6]);
    }

    [Fact]
    public void Env_values_are_single_quoted_with_embedded_quotes_doubled()
    {
        var plan = Launcher.Build(Opts(logFile: @"C:\o'brien\cli.log"));
        Assert.Contains(@"agy --log-file 'C:\o''brien\cli.log'", plan.AgyTab.Arguments[6]);
    }

    [Fact]
    public void ClaudeLaunch_runs_claude_in_folder_marked_clavity_launched()
    {
        var plan = Launcher.Build(Opts(claudeArgs: new[] { "--model", "opus" }));

        Assert.Equal("claude", plan.ClaudeLaunch.FileName);
        Assert.Equal(new[] { "--model", "opus" }, plan.ClaudeLaunch.Arguments);
        Assert.Equal(@"C:\work\repo", plan.ClaudeLaunch.WorkingDirectory);
        Assert.Equal("1", plan.ClaudeLaunch.Environment["CLAVITY_LAUNCHED"]);
    }
}
