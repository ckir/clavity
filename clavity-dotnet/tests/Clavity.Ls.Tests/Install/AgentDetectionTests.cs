using Clavity.Ls.Install;

namespace Clavity.Ls.Tests.Install;

public sealed class AgentDetectionTests
{
    [Fact]
    public void Detects_claude_when_cli_on_path()
    {
        var d = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        Assert.True(d.IsPresent(Agent.Claude));
        Assert.False(d.IsPresent(Agent.Agy));
    }

    [Fact]
    public void Detects_agy_when_config_dir_exists()
    {
        var d = new AgentDetection(onPath: _ => false, dirExists: p => p.Contains(".gemini"));
        Assert.True(d.IsPresent(Agent.Agy));
    }

    [Fact]
    public void DetectsNone_when_neither_signal()
    {
        var d = new AgentDetection(onPath: _ => false, dirExists: _ => false);
        Assert.Empty(d.Present());
    }
}
