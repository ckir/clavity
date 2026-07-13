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

    [Fact]
    public void Install_runs_native_command_for_each_present_agent()
    {
        var detection = new AgentDetection(onPath: _ => true, dirExists: _ => false); // both present
        var runner = new FakeRunner();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.Equal(0, rc);
        Assert.Contains(runner.Calls, c => c.Exe == "claude" && c.Args.Contains("marketplace add C:\\app"));
        Assert.Contains(runner.Calls, c => c.Exe == "claude" && c.Args.Contains("install clavity-dotnet@clavity"));
        Assert.Contains(runner.Calls, c => c.Exe == "agy" && c.Args.Contains(@"plugin install C:\app\plugins\clavity-dotnet"));
    }

    [Fact]
    public void Install_deregisters_the_legacy_unified_clavity_marketplace_before_registering_the_new_name()
    {
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        var runner = new FakeRunner();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.Equal(0, rc);
        var legacyRemove = runner.Calls.FindIndex(c => c.Exe == "claude" && c.Args == "plugin marketplace remove clavity");
        var newAdd = runner.Calls.FindIndex(c => c.Exe == "claude" && c.Args.StartsWith("plugin marketplace add"));
        Assert.True(legacyRemove >= 0, "legacy 'marketplace remove clavity' not issued");
        Assert.True(legacyRemove < newAdd, "legacy removal must precede the new-name add");
    }

    [Fact]
    public void Install_with_plugin_option_installs_the_named_add_on_from_its_sibling_dir()
    {
        var detection = new AgentDetection(onPath: _ => true, dirExists: _ => false); // both present
        var runner = new FakeRunner();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install", "--plugin", "agy-autotrain" }, sw, detection, runner.Run,
            @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.Equal(0, rc);
        Assert.Contains(runner.Calls, c => c.Exe == "claude" && c.Args.Contains("install agy-autotrain@clavity"));
        Assert.Contains(runner.Calls, c => c.Exe == "agy" && c.Args.Contains(@"plugin install C:\app\plugins\agy-autotrain"));
    }

    [Fact]
    public void Install_with_only_one_agent_present_does_not_fail_or_call_the_absent_agent()
    {
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false); // only claude
        var runner = new FakeRunner();
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.Equal(0, rc);
        Assert.DoesNotContain(runner.Calls, c => c.Exe == "agy");
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
    public void Install_read_back_fails_when_the_entry_did_not_persist_after_an_exit_zero_install()
    {
        var detection = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        var runner = new FakeRunner { DropInstall = true };
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.NotEqual(0, rc);
        Assert.Contains("read-back", sw.ToString());
        Assert.Contains(runner.Calls, c => c.Exe == "claude" && c.Args == "plugin list");
    }

    [Fact]
    public void Install_with_mixed_per_agent_results_returns_zero_and_reports_both()
    {
        // C1 per-agent OR-semantics: install succeeds (exit 0) as long as AT LEAST ONE detected agent's
        // registration succeeds; the FAILED agent is reported but does not fail the whole install (was
        // exit 1 under the prior AND-semantics — this pins the new behavior).
        var detection = new AgentDetection(onPath: _ => true, dirExists: _ => false); // both present
        ProcessRunner run = (exe, args) =>
        {
            // Claude's post-install read-back (`plugin list`) must echo the just-installed entry so this
            // test's claude leg still counts as ok — the OR-semantics pin is about the AGY leg failing.
            if (exe == "claude" && args.Count >= 2 && args[0] == "plugin" && args[1] == "list")
                return new ProcessOutcome(0, "clavity-dotnet@clavity-dotnet");
            return exe == "claude" ? new ProcessOutcome(0, "") : new ProcessOutcome(1, "boom");
        };
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "install" }, sw, detection, run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.Equal(0, rc);
        var text = sw.ToString();
        Assert.Contains("] ok:", text);
        Assert.Contains("] FAILED:", text);
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
        var runner = new FakeRunner { ExitCode = 1 }; // every native plugin-uninstall "fails"
        var sw = new StringWriter();

        var rc = CliRouter.Run(new[] { "uninstall" }, sw, detection, runner.Run, @"C:\app", @"C:\app\plugins\clavity-dotnet");

        Assert.NotEqual(0, rc); // the Inno InitializeUninstall gate depends on a non-zero exit on failure
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
            var sw = new StringWriter();
            var rc = CliRouter.Run(new[] { "uninstall", "--purge-data" }, sw, detection, new FakeRunner().Run,
                @"C:\app", @"C:\app\plugins\clavity-dotnet", logsDir, dataDir);

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
            var sw = new StringWriter();
            var rc = CliRouter.Run(new[] { "uninstall" }, sw, detection, new FakeRunner().Run,
                @"C:\app", @"C:\app\plugins\clavity-dotnet", logsDir: null, clavityDataDir: dataDir);

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
            var sw = new StringWriter();

            var rc = CliRouter.Run(new[] { "uninstall", "--purge-data" }, sw, detection, runner.Run,
                @"C:\app", @"C:\app\plugins\clavity-dotnet", logsDir);

            Assert.Equal(0, rc);
            Assert.False(Directory.Exists(logsDir)); // logs purged
        }
        finally
        {
            if (Directory.Exists(logsDir)) Directory.Delete(logsDir, true);
        }
    }
}
