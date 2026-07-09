using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class AgyEnvironmentTests
{
    private const string Home = @"C:\Users\u\.gemini\antigravity-cli";

    [Fact]
    public void ResolveCliLogPath_uses_per_session_log_when_env_set()
    {
        var perSession = @"C:\Users\u\.gemini\antigravity-cli\logs\clavity-abc.log";
        Assert.Equal(perSession, AgyEnvironment.ResolveCliLogPath(perSession, Home));
    }

    [Fact]
    public void ResolveCliLogPath_falls_back_to_global_cli_log_when_env_unset_or_empty()
    {
        var expected = Path.Combine(Home, "cli.log");
        Assert.Equal(expected, AgyEnvironment.ResolveCliLogPath(null, Home));
        Assert.Equal(expected, AgyEnvironment.ResolveCliLogPath("", Home));
    }
}
