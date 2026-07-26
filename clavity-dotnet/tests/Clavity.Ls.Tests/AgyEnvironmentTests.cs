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

    [Fact]
    public void ResolveSeconds_parses_a_positive_integer_to_a_TimeSpan()
        => Assert.Equal(TimeSpan.FromSeconds(90),
            AgyEnvironment.ResolveSeconds("90", TimeSpan.FromSeconds(120)));

    [Fact]
    public void ResolveSeconds_falls_back_when_unset_or_blank()
    {
        Assert.Equal(TimeSpan.FromSeconds(120), AgyEnvironment.ResolveSeconds(null, TimeSpan.FromSeconds(120)));
        Assert.Equal(TimeSpan.FromSeconds(120), AgyEnvironment.ResolveSeconds("", TimeSpan.FromSeconds(120)));
    }

    [Fact]
    public void ResolveSeconds_falls_back_on_a_non_numeric_or_negative_value()
    {
        Assert.Equal(TimeSpan.FromSeconds(600), AgyEnvironment.ResolveSeconds("abc", TimeSpan.FromSeconds(600)));
        Assert.Equal(TimeSpan.FromSeconds(600), AgyEnvironment.ResolveSeconds("-5", TimeSpan.FromSeconds(600)));
    }

    [Fact]
    public void ResolveSeconds_treats_zero_as_the_fallback_unless_allowZero()
    {
        Assert.Equal(TimeSpan.FromSeconds(600), AgyEnvironment.ResolveSeconds("0", TimeSpan.FromSeconds(600)));
        Assert.Equal(TimeSpan.Zero, AgyEnvironment.ResolveSeconds("0", TimeSpan.FromSeconds(600), allowZero: true));
    }
}
