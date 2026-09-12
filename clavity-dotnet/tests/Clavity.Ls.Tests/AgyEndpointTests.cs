// tests/Clavity.Ls.Tests/AgyEndpointTests.cs
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class AgyEndpointTests
{
    private static string WriteTemp(string content)
    {
        var path = Path.Combine(Path.GetTempPath(), $"agy-endpoint-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, content);
        return path;
    }

    [Fact]
    public void TryRead_parses_csrf_and_port_from_addr()
    {
        var path = WriteTemp("""{"csrf":"tok-123","addr":"localhost:55056","published":"2026-09-12T20:47:52Z"}""");
        try
        {
            var ep = AgyEndpoint.TryRead(path);
            Assert.NotNull(ep);
            Assert.Equal("tok-123", ep!.Csrf);
            Assert.Equal(55056, ep.Port);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void TryRead_returns_null_when_file_absent()
    {
        Assert.Null(AgyEndpoint.TryRead(Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.json")));
    }

    [Fact]
    public void TryRead_returns_null_on_malformed_json()
    {
        var path = WriteTemp("not json {");
        try { Assert.Null(AgyEndpoint.TryRead(path)); } finally { File.Delete(path); }
    }

    [Fact]
    public void TryRead_returns_null_when_csrf_or_addr_missing_or_portless()
    {
        var noCsrf = WriteTemp("""{"addr":"localhost:1"}""");
        var noPort = WriteTemp("""{"csrf":"t","addr":"localhost"}""");
        var blank = WriteTemp("""{"csrf":"","addr":"localhost:1"}""");
        try
        {
            Assert.Null(AgyEndpoint.TryRead(noCsrf));
            Assert.Null(AgyEndpoint.TryRead(noPort));
            Assert.Null(AgyEndpoint.TryRead(blank));
        }
        finally { File.Delete(noCsrf); File.Delete(noPort); File.Delete(blank); }
    }

    [Fact]
    public void TryRead_takes_the_port_after_the_LAST_colon()
    {
        // Pins the "port = digits after the last ':'" rule so a regression to first-colon parsing (IndexOf)
        // fails here: with IndexOf, the port span would be ":1]:8080", which does not parse -> null.
        var path = WriteTemp("""{"csrf":"t","addr":"[::1]:8080"}""");
        try
        {
            var ep = AgyEndpoint.TryRead(path);
            Assert.NotNull(ep);
            Assert.Equal(8080, ep!.Port);
        }
        finally { File.Delete(path); }
    }
}
