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
        Assert.Equal("clavity", req.PluginName);
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
        if (!OperatingSystem.IsWindows())
        {
            // This test requires Windows PowerShell 5.1 which is not available on Linux/macOS.
            // The CI pipeline runs this test on Windows agents.
            return;
        }
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
