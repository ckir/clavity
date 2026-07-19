using Clavity.Ls.Install;

namespace Clavity.Ls.Tests.Install;

public sealed class CliRouterTests
{
    private sealed class FakeRunner
    {
        public List<(string Exe, string Args)> Calls { get; } = new();
        public int ExitCode { get; set; }
        // Read-back models `plugin list` echoing what was installed (as <plugin>@<marketplace>, the real
        // format per spike Q3). DropInstall simulates an exit-0 install that did NOT persist.
        public bool DropInstall { get; set; }
        private readonly List<string> _installed = new();
        public ProcessOutcome Run(string exe, IReadOnlyList<string> args)
        {
            Calls.Add((exe, string.Join(" ", args)));
            if (exe == "claude" && args.Count >= 3 && args[0] == "plugin" && args[1] == "install" && args[2].Contains('@'))
            {
                if (!DropInstall) _installed.Add(args[2]);   // record the full <plugin>@<marketplace> spec
            }
            if (exe == "claude" && args.Count >= 2 && args[0] == "plugin" && args[1] == "list")
                return new ProcessOutcome(ExitCode, string.Join("\n", _installed));
            return new ProcessOutcome(ExitCode, "");
        }
    }

    /// <summary>Fakes register-plugin.ps1's process outcome (Option B, D2): records every request CliRouter
    /// routed to the streamer and returns a canned exit code, so Install/Uninstall tests never spawn powershell.</summary>
    private sealed class FakeStreamer
    {
        public List<RegistrarRequest> Requests { get; } = new();
        public int ExitCode { get; set; } = 0;
        public ProcessOutcome Stream(RegistrarRequest req)
        {
            Requests.Add(req);
            return new ProcessOutcome(ExitCode, $"AGENT {req.Agent} {(ExitCode == 0 ? "OK" : "FAIL x")}");
        }
    }

    [Fact]
    public void Install_streams_register_script_per_present_agent_with_correct_request()
    {
        var streamer = new FakeStreamer();
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        var runner = new FakeRunner();
        var rc = CliRouter.Run(new[] { "install" }, new StringWriter(), detection, runner.Run,
            @"C:\app", @"C:\app\plugins\clavity-dotnet", claudeRunning: () => false, streamer: streamer.Stream);
        Assert.Equal(0, rc);
        var req = Assert.Single(streamer.Requests);
        Assert.Equal("install", req.Verb);
        Assert.Equal("clavity-dotnet", req.PluginName);
        Assert.Equal("clavity-dotnet", req.MarketplaceName);
        Assert.Equal(@"C:\app", req.AppDir);
        Assert.Equal("claude", req.Agent);
    }

    [Fact]
    public void Install_returns_nonzero_when_the_registrar_fails_for_the_only_agent()
    {
        var streamer = new FakeStreamer { ExitCode = 3 };
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        var runner = new FakeRunner();
        var rc = CliRouter.Run(new[] { "install" }, new StringWriter(), detection, runner.Run,
            @"C:\app", @"C:\app\plugins\clavity-dotnet", claudeRunning: () => false, streamer: streamer.Stream);
        Assert.NotEqual(0, rc);
    }

    [Fact]
    public void Install_with_only_one_agent_present_does_not_fail_or_call_the_absent_agent()
    {
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false); // only claude
        var runner = new FakeRunner();
        var streamer = new FakeStreamer();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet",
            claudeRunning: () => false, streamer: streamer.Stream);

        Assert.Equal(0, rc);
        // Re-expressed (Option B): registration now streams through register-plugin.ps1, not runner.Calls —
        // the absent agent must not be streamed to either.
        Assert.DoesNotContain(streamer.Requests, r => r.Agent == "agy");
    }

    [Fact]
    public void Install_refuses_when_claude_is_running()
    {
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        var runner = new FakeRunner();
        var streamer = new FakeStreamer();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, runner.Run, @"C:\app",
            @"C:\app\plugins\clavity-dotnet", logsDir: null, clavityDataDir: null, claudeRunning: () => true,
            streamer: streamer.Stream);

        Assert.NotEqual(0, rc);
        Assert.Empty(runner.Calls);                       // refuse BEFORE any registration write
        Assert.Empty(streamer.Requests);                   // ...and before any register-plugin.ps1 invocation
        Assert.Contains("close Claude Code", sw.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Install_with_zero_agents_returns_nonzero_and_reports_and_runs_nothing()
    {
        var detection = new AgentDetection(onPath: _ => false, dirExists: _ => false); // none
        var runner = new FakeRunner();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.NotEqual(0, rc);
        Assert.Empty(runner.Calls);
        Assert.Contains("No compatible agent", sw.ToString());
    }

    [Fact]
    public void IsInstalled_does_not_false_match_a_substring_plugin_name()
    {
        var detection = new AgentDetection(onPath: _ => true, dirExists: _ => false); // both present
        var sw = new StringWriter();
        // Each agent's `plugin list` reports a DIFFERENT plugin whose name CONTAINS the query as a substring.
        ProcessRunner run = (exe, args) => new ProcessOutcome(0, "uncommonmemory\nclavity-dotnet");

        var rc = CliRouter.Run(new[] { "is-installed", "commonmemory" }, sw, detection, run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.NotEqual(0, rc); // 'commonmemory' is NOT installed; 'uncommonmemory' must not false-match
        Assert.Contains("not installed", sw.ToString());
    }

    [Fact]
    public void IsInstalled_matches_an_exact_plugin_token()
    {
        var detection = new AgentDetection(onPath: n => n == "agy", dirExists: _ => false); // only agy
        var sw = new StringWriter();
        ProcessRunner run = (exe, args) => new ProcessOutcome(0, "{ \"imports\": [ { \"name\": \"commonmemory\" } ] }");

        var rc = CliRouter.Run(new[] { "is-installed", "commonmemory" }, sw, detection, run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.Equal(0, rc);
        Assert.Contains("is installed", sw.ToString());
    }

    [Fact]
    public void Uninstall_returns_nonzero_when_an_agent_removal_fails()
    {
        var detection = new AgentDetection(onPath: _ => true, dirExists: _ => false); // both present
        var runner = new FakeRunner { ExitCode = 1 };
        var streamer = new FakeStreamer { ExitCode = 1 }; // every registrar uninstall "fails" (not 0, not 4)
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "uninstall" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet",
            claudeRunning: () => false, streamer: streamer.Stream);

        Assert.NotEqual(0, rc); // the Inno InitializeUninstall gate depends on a non-zero exit on failure
    }

    [Fact]
    public void Uninstall_refuses_when_claude_is_running()
    {
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        var runner = new FakeRunner();
        var streamer = new FakeStreamer();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "uninstall" }, sw, detection, runner.Run, @"C:\app",
            @"C:\app\plugins\clavity-dotnet", logsDir: null, clavityDataDir: null, claudeRunning: () => true,
            streamer: streamer.Stream);

        Assert.NotEqual(0, rc);
        Assert.Empty(runner.Calls);
        Assert.Empty(streamer.Requests);
        Assert.Contains("Claude Code is running", sw.ToString());
    }

    [Fact]
    public void Uninstall_with_zero_agents_succeeds_because_nothing_to_remove()
    {
        var detection = new AgentDetection(onPath: _ => false, dirExists: _ => false); // none present
        var runner = new FakeRunner();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "uninstall" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.Equal(0, rc); // the Inno uninstall gate must NOT abort when there are no agents
        Assert.Empty(runner.Calls); // no native uninstall attempted
        Assert.Contains("nothing to uninstall", sw.ToString());
    }

    [Fact]
    public void Uninstall_with_zero_agents_still_purges_data_when_requested()
    {
        // Capstone fix: zero agents present must NOT skip --purge-data (else a 'delete data' uninstall on a
        // machine whose agents were already removed would silently leave .clavity behind).
        var dataDir = Path.Combine(Path.GetTempPath(), "clavity-data-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dataDir); File.WriteAllText(Path.Combine(dataDir, "golden-header.md"), "wisdom");
        try
        {
            var detection = new AgentDetection(onPath: _ => false, dirExists: _ => false); // none present
            var sw = new StringWriter();
            var rc = CliRouter.Run(new[] { "uninstall", "--purge-data" }, sw, detection, new FakeRunner().Run,
                @"C:\app", @"C:\app\plugins\clavity-dotnet", logsDir: null, clavityDataDir: dataDir);

            Assert.Equal(0, rc);
            Assert.False(Directory.Exists(dataDir)); // purge ran despite zero agents
        }
        finally
        {
            if (Directory.Exists(dataDir)) Directory.Delete(dataDir, true);
        }
    }

    [Fact]
    public void Uninstall_with_purge_data_deletes_both_logs_and_clavity_data()
    {
        var logsDir = Path.Combine(Path.GetTempPath(), "clavity-logs-" + Guid.NewGuid().ToString("N"));
        var dataDir = Path.Combine(Path.GetTempPath(), "clavity-data-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(logsDir); File.WriteAllText(Path.Combine(logsDir, "clavity-x.log"), "log");
        Directory.CreateDirectory(dataDir); File.WriteAllText(Path.Combine(dataDir, "golden-header.md"), "wisdom");
        try
        {
            var detection = new AgentDetection(onPath: n => n == "agy", dirExists: _ => false);
            var streamer = new FakeStreamer(); // ExitCode 0 = registrar uninstall succeeds
            var sw = new StringWriter();
            var rc = CliRouter.Run(new[] { "uninstall", "--purge-data" }, sw, detection, new FakeRunner().Run,
                @"C:\app", @"C:\app\plugins\clavity-dotnet", logsDir, dataDir, streamer: streamer.Stream);

            Assert.Equal(0, rc);
            Assert.False(Directory.Exists(logsDir));   // logs purged
            Assert.False(Directory.Exists(dataDir));   // .clavity (golden-header) purged
        }
        finally
        {
            foreach (var d in new[] { logsDir, dataDir }) if (Directory.Exists(d)) Directory.Delete(d, true);
        }
    }

    [Fact]
    public void Uninstall_without_purge_data_preserves_clavity_data()
    {
        var dataDir = Path.Combine(Path.GetTempPath(), "clavity-data-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dataDir); File.WriteAllText(Path.Combine(dataDir, "golden-header.md"), "wisdom");
        try
        {
            var detection = new AgentDetection(onPath: n => n == "agy", dirExists: _ => false);
            var streamer = new FakeStreamer(); // ExitCode 0 = registrar uninstall succeeds
            var sw = new StringWriter();
            var rc = CliRouter.Run(new[] { "uninstall" }, sw, detection, new FakeRunner().Run,
                @"C:\app", @"C:\app\plugins\clavity-dotnet", logsDir: null, clavityDataDir: dataDir, streamer: streamer.Stream);

            Assert.Equal(0, rc);
            Assert.True(Directory.Exists(dataDir));    // plain uninstall PRESERVES .clavity
        }
        finally
        {
            if (Directory.Exists(dataDir)) Directory.Delete(dataDir, true);
        }
    }

    [Fact]
    public void Uninstall_with_purge_data_deletes_the_logs_dir()
    {
        var logsDir = Path.Combine(Path.GetTempPath(), "clavity-purge-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(logsDir);
        File.WriteAllText(Path.Combine(logsDir, "clavity-x.log"), "log");
        try
        {
            var detection = new AgentDetection(onPath: n => n == "agy", dirExists: _ => false); // only agy
            var runner = new FakeRunner(); // ExitCode 0 = uninstall succeeds
            var streamer = new FakeStreamer(); // ExitCode 0 = registrar uninstall succeeds
            var sw = new StringWriter();

            var rc = CliRouter.Run(new[] { "uninstall", "--purge-data" }, sw, detection, runner.Run,
                @"C:\app", @"C:\app\plugins\clavity-dotnet", logsDir, streamer: streamer.Stream);

            Assert.Equal(0, rc);
            Assert.False(Directory.Exists(logsDir)); // logs purged
        }
        finally
        {
            if (Directory.Exists(logsDir)) Directory.Delete(logsDir, true);
        }
    }

    [Fact]
    [Trait("Category", "Integration")]   // real Windows PowerShell 5.1 + writable temp PATH; Windows-only
    public void PowerShellRegistrar_runs_the_loose_script_via_File_and_maps_exit_code()
    {
        var script = PowerShellRegistrar.ScriptPath();
        Assert.True(File.Exists(script), $"register-plugin.ps1 not copied next to the test binary: {script}");

        var dir = Directory.CreateTempSubdirectory().FullName;
        // claude.cmd: echo the token on `plugin list` so read-back passes; always exit 0.
        File.WriteAllText(Path.Combine(dir, "claude.cmd"),
            "@echo off\r\nif \"%1 %2\"==\"plugin list\" echo clavity-dotnet@clavity-dotnet\r\nexit /b 0\r\n");
        File.WriteAllText(Path.Combine(dir, "agy.cmd"), "@echo off\r\nexit /b 0\r\n");
        var oldPath = Environment.GetEnvironmentVariable("PATH");
        try
        {
            // Prepend the fake-CLI dir to the REAL PATH so the fake agy.cmd wins over any real agy; KEEP the
            // real USERPROFILE — register-plugin.ps1's Start-Job time-box needs a valid profile/APPDATA
            // persistence path (a bare temp USERPROFILE breaks Start-Job: "The Persistence Path does not exist").
            // Agent=agy + fake-first guarantees no real agent is ever touched.
            Environment.SetEnvironmentVariable("PATH", dir + ";" + oldPath);
            // Use the AGY leg (not claude): register-plugin.ps1's inner Test-ClaudeRunning guard
            // (Get-Process -Name claude) fires whenever a real Claude Code process is live — e.g. when this
            // suite runs interactively from inside Claude Code — and returns exit 3 for the claude leg. The
            // agy leg has no such guard, so this deterministically proves the -File mechanism end-to-end
            // (script parsed via -File, agent detected, vectors run through the fake, mapped exit + AGENT line).
            var outcome = PowerShellRegistrar.Stream(
                new RegistrarRequest("install", "clavity-dotnet", "clavity-dotnet", dir, "agy"));
            Assert.Equal(0, outcome.ExitCode);                 // single detected agent OK
            Assert.Contains("AGENT agy OK", outcome.Output);
        }
        finally
        {
            Environment.SetEnvironmentVariable("PATH", oldPath);
            Directory.Delete(dir, true);
        }
    }
}
