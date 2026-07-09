using System.Text;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class LauncherTests
{
    /// <summary>Decode the agy-tab pwsh script from the base64 <c>-EncodedCommand</c> argument (UTF-16LE).</summary>
    private static string DecodeScript(LaunchPlan plan) =>
        Encoding.Unicode.GetString(Convert.FromBase64String(plan.AgyTab.Arguments[6]));

    [Fact]
    public void AgyTab_arguments_contain_no_semicolon_so_wt_does_not_split_the_command()
    {
        // Regression (v0.1.4 launch bug): Windows Terminal treats ';' in its command line as a tab/pane
        // separator. A raw ';' in any wt argument shatters the launch into broken sub-tabs and agy never
        // starts. The script must be passed base64-encoded (-EncodedCommand), which has no ';'.
        var plan = Launcher.Build(Opts());
        Assert.All(plan.AgyTab.Arguments, arg => Assert.DoesNotContain(";", arg));
    }

    private static LaunchOptions Opts(
        string folder = @"C:\work\repo",
        string sessionId = "11111111-2222-3333-4444-555555555555",
        string? projectId = "proj-123",
        string logFile = @"C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log",
        bool skipPermissions = false,
        params string[] claudeArgs)
        => new()
        {
            Folder = folder,
            SessionId = sessionId,
            ProjectId = projectId,
            AgyLogFilePath = logFile,
            SkipPermissions = skipPermissions,
            ClaudeArgs = claudeArgs,
        };

    [Fact]
    public void AgyTab_is_wt_new_tab_running_pwsh_with_baked_env_and_per_session_log()
    {
        var plan = Launcher.Build(Opts());

        Assert.Equal("wt", plan.AgyTab.FileName);
        Assert.Equal(
            new[] { "new-tab", "--startingDirectory", @"C:\work\repo", "pwsh", "-NoExit", "-EncodedCommand" },
            plan.AgyTab.Arguments.Take(6));
        Assert.Equal(@"C:\work\repo", plan.AgyTab.WorkingDirectory);

        var script = DecodeScript(plan);
        Assert.Equal(
            "$env:ANTIGRAVITY_CSRF_TOKEN='clavity'; $env:ANTIGRAVITY_PROJECT_ID='proj-123'; " +
            @"agy --log-file 'C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log'",
            script);
    }

    [Fact]
    public void ProjectId_is_omitted_when_absent()
    {
        var plan = Launcher.Build(Opts(projectId: null));

        var script = DecodeScript(plan);
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", script);
        Assert.StartsWith("$env:ANTIGRAVITY_CSRF_TOKEN='clavity'; agy --log-file ", script);
    }

    [Fact]
    public void SkipPermissions_appends_flag_only_when_opted_in()
    {
        Assert.DoesNotContain("--dangerously-skip-permissions", DecodeScript(Launcher.Build(Opts())));
        Assert.EndsWith(" --dangerously-skip-permissions", DecodeScript(Launcher.Build(Opts(skipPermissions: true))));
    }

    [Fact]
    public void Env_values_are_single_quoted_with_embedded_quotes_doubled()
    {
        var plan = Launcher.Build(Opts(logFile: @"C:\o'brien\clavity.log"));
        Assert.Contains(@"agy --log-file 'C:\o''brien\clavity.log'", DecodeScript(plan));
    }

    [Fact]
    public void ClaudeLaunch_threads_session_identity_and_drops_legacy_marker()
    {
        var plan = Launcher.Build(Opts(claudeArgs: new[] { "--model", "opus" }));

        Assert.Equal("claude", plan.ClaudeLaunch.FileName);
        Assert.Equal(new[] { "--model", "opus" }, plan.ClaudeLaunch.Arguments);
        Assert.Equal(@"C:\work\repo", plan.ClaudeLaunch.WorkingDirectory);
        Assert.Equal("11111111-2222-3333-4444-555555555555",
            plan.ClaudeLaunch.Environment["CLAVITY_SESSION_ID"]);
        Assert.Equal(@"C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log",
            plan.ClaudeLaunch.Environment["CLAVITY_AGY_LOG"]);
        Assert.DoesNotContain("CLAVITY_LAUNCHED", plan.ClaudeLaunch.Environment.Keys);
    }
}
