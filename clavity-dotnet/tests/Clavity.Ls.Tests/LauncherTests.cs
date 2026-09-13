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
        string endpointFile = @"C:\Users\u\.clavity\agy-endpoint.11111111-2222-3333-4444-555555555555.json",
        bool skipPermissions = false,
        params string[] claudeArgs)
        => new()
        {
            Folder = folder,
            SessionId = sessionId,
            ProjectId = projectId,
            AgyLogFilePath = logFile,
            AgyEndpointFilePath = endpointFile,
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
            "$env:ANTIGRAVITY_PROJECT_ID='proj-123'; " +
            @"$env:CLAVITY_AGY_ENDPOINT='C:\Users\u\.clavity\agy-endpoint.11111111-2222-3333-4444-555555555555.json'; " +
            @"agy --log-file 'C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log'",
            script);
    }

    [Fact]
    public void ProjectId_is_omitted_when_absent()
    {
        var plan = Launcher.Build(Opts(projectId: null));

        var script = DecodeScript(plan);
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", script);
        // The endpoint export is UNCONDITIONAL (not gated on ProjectId), so it now leads the script.
        Assert.StartsWith("$env:CLAVITY_AGY_ENDPOINT='", script);
        Assert.Contains("; agy --log-file ", script);
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
    public void AgyTab_script_injects_the_fetch_and_follow_prompt_when_an_install_doc_is_given()
    {
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj",
            SessionId = "sid",
            AgyLogFilePath = "C:\\logs\\agy.log",
            AgyEndpointFilePath = "C:\\ep\\agy-endpoint.sid.json",
            SkipPermissions = true,
            AgyInstallDocPath = "C:\\install\\agy-pairing-INSTALL.md",
        });

        var script = DecodeScript(plan);

        Assert.Contains("--dangerously-skip-permissions", script);
        Assert.Contains("-i 'Fetch and follow the instructions at C:\\install\\agy-pairing-INSTALL.md'", script);
        Assert.True(script.IndexOf("--dangerously-skip-permissions", StringComparison.Ordinal)
                    < script.IndexOf(" -i '", StringComparison.Ordinal));
        // agy publishes to the PER-SESSION endpoint the tab exports; the INSTALL.md reads $env:CLAVITY_AGY_ENDPOINT.
        Assert.Contains("$env:CLAVITY_AGY_ENDPOINT='C:\\ep\\agy-endpoint.sid.json'; ", script);
    }

    [Fact]
    public void AgyTab_script_omits_the_prompt_when_no_install_doc_is_given()
    {
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj", SessionId = "sid", AgyLogFilePath = "C:\\logs\\agy.log",
            AgyEndpointFilePath = "C:\\ep\\agy-endpoint.sid.json", SkipPermissions = true,
        });
        var script = DecodeScript(plan);
        Assert.DoesNotContain(" -i '", script);
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
        Assert.Equal(@"C:\Users\u\.clavity\agy-endpoint.11111111-2222-3333-4444-555555555555.json",
            plan.ClaudeLaunch.Environment["CLAVITY_AGY_ENDPOINT"]);
        Assert.DoesNotContain("CLAVITY_LAUNCHED", plan.ClaudeLaunch.Environment.Keys);
    }

    [Fact]
    public void The_SAME_per_session_endpoint_is_threaded_to_BOTH_agy_and_Claude_so_two_sessions_never_collide()
    {
        // ROOT-CAUSE REGRESSION GUARD (2026-09-13). The agy-pairing bridge had agy publish, and clavity-ls
        // read, a single GLOBAL ~/.clavity/agy-endpoint.json with NO session discriminator on either side.
        // MEASURED: two agy instances (PIDs 22140/22720) both published there, the second overwrote the
        // first, and BOTH Claude peers connected to the last-published agy - a consult from this repo was
        // answered by a different project's agy. The fix threads ONE per-session path into BOTH the agy tab
        // (where agy publishes it, via $env:CLAVITY_AGY_ENDPOINT in INSTALL.md) AND Claude's env (where
        // clavity-ls reads it). Both must carry the SAME session-scoped path, or the rendezvous breaks: if
        // agy publishes to file A and clavity-ls reads file B they never meet; if either reverts to the
        // fixed global path, two sessions collide again. This asserts they are equal AND session-scoped.
        var endpoint = @"C:\Users\u\.clavity\agy-endpoint.SID-A.json";
        var plan = Launcher.Build(Opts(sessionId: "SID-A", endpointFile: endpoint));

        // clavity-ls (Claude's --mcp child inherits this) reads exactly this file.
        Assert.Equal(endpoint, plan.ClaudeLaunch.Environment["CLAVITY_AGY_ENDPOINT"]);
        // agy publishes to exactly this file (the tab exports it for INSTALL.md to consume).
        Assert.Contains("$env:CLAVITY_AGY_ENDPOINT='" + endpoint + "'; ", DecodeScript(plan));
        // and it is NOT the fixed global path that caused the collision.
        Assert.NotEqual(@"C:\Users\u\.clavity\agy-endpoint.json",
            plan.ClaudeLaunch.Environment["CLAVITY_AGY_ENDPOINT"]);
    }
}
