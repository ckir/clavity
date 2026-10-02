using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class SessionPathsTests
{
    private const string Sid = "11111111-2222-3333-4444-555555555555";

    [Fact]
    public void For_derives_every_file_from_the_profile_and_the_session_id()
    {
        var home = Path.Combine("x", "home");
        var p = SessionPaths.For(home, Sid);

        Assert.Equal(Sid, p.SessionId);
        // The log and endpoint names are the ones `start` already used before this branch - unchanged on Windows.
        Assert.Equal(Path.Combine(home, ".gemini", "antigravity-cli", "logs", $"clavity-{Sid}.log"), p.AgyLog);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-endpoint.{Sid}.json"), p.Endpoint);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-session.{Sid}.sh"), p.AgyScript);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-session.{Sid}.claim"), p.Claim);
    }

    [Theory]
    [InlineData(Sid, true)]
    [InlineData("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", true)]
    [InlineData("11111111222233334444555555555555", false)]   // GUID "N" form: not what start prints
    [InlineData("../../etc/passwd", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void IsValidSessionId_accepts_only_the_GUID_D_form(string? id, bool expected)
        => Assert.Equal(expected, SessionPaths.IsValidSessionId(id));
}
