using Clavity.Ls.Install;

namespace Clavity.Ls.Tests.Install;

public sealed class CliRouterTests
{
    private sealed class FakeRunner
    {
        public List<(string Exe, string Args)> Calls { get; } = new();
        public int ExitCode { get; set; }
        public ProcessOutcome Run(string exe, IReadOnlyList<string> args)
        {
            Calls.Add((exe, string.Join(" ", args)));
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
}
