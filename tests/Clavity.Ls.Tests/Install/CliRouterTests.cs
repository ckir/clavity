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
}
