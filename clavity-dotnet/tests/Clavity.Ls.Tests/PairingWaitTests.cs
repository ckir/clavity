using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class PairingWaitTests : IDisposable
{
    private readonly string _ep = Path.Combine(Path.GetTempPath(), $"agy-endpoint-wait-{Guid.NewGuid():N}.json");

    public void Dispose()
    {
        if (File.Exists(_ep))
            File.Delete(_ep);
    }

    private sealed class Ports(Func<int, bool> f) : IListeningPorts
    {
        public bool IsListening(int port) => f(port);
    }

    /// <summary>A fake clock; <paramref name="onSleep"/> runs at each poll with the time reached, to change the world.</summary>
    private static (Func<long> now, Action<TimeSpan> sleep) Clock(Action<long> onSleep)
    {
        long now = 0;
        return (() => now, t => { now += (long)t.TotalMilliseconds; onSleep(now); });
    }

    private void Publish(string json) => File.WriteAllText(_ep, json);

    [Fact]
    public void Waits_through_an_EMPTY_publish_and_returns_the_valid_one()
    {
        // MEASURED: agy first published {"csrf":"","addr":""} through an MCP shell tool, then the real values.
        Publish("""{"csrf":"","addr":"","published":"x"}""");
        var (now, sleep) = Clock(t => { if (t >= 3000) Publish("""{"csrf":"tok","addr":"localhost:4242","published":"x"}"""); });
        var output = new StringWriter();

        var ep = PairingWait.WaitForEndpoint(_ep, new Ports(_ => true), output, now, sleep);

        Assert.Equal(4242, ep.Port);
        Assert.Equal("tok", ep.Csrf);
        Assert.True(now() >= 3000);
        Assert.Contains("agy paired (port 4242)", output.ToString());
    }

    [Fact]
    public void A_published_port_that_is_not_listening_yet_keeps_it_waiting()
    {
        Publish("""{"csrf":"tok","addr":"localhost:4242","published":"x"}""");
        var listeningFrom = 2000L;
        var (now, sleep) = Clock(_ => { });
        var ep = PairingWait.WaitForEndpoint(_ep, new Ports(_ => now() >= listeningFrom), new StringWriter(), now, sleep);
        Assert.Equal(4242, ep.Port);
        Assert.True(now() >= listeningFrom, $"returned at {now()} ms, before the port listened");
    }

    [Fact]
    public void The_trust_prompt_hint_appears_once_after_10_s_and_not_before()
    {
        var (now, sleep) = Clock(t => { if (t >= 25_000) Publish("""{"csrf":"tok","addr":"localhost:1","published":"x"}"""); });
        var output = new StringWriter();
        PairingWait.WaitForEndpoint(_ep, new Ports(_ => true), output, now, sleep);

        var text = output.ToString();
        Assert.Equal(1, text.Split("trust this folder").Length - 1);
        // ...and it came AFTER 10 s: a run that pairs at 9.5 s never shows it.
        var quick = new StringWriter();
        if (File.Exists(_ep)) File.Delete(_ep);
        var (now2, sleep2) = Clock(t => { if (t >= 9_500) Publish("""{"csrf":"tok","addr":"localhost:1","published":"x"}"""); });
        PairingWait.WaitForEndpoint(_ep, new Ports(_ => true), quick, now2, sleep2);
        Assert.DoesNotContain("trust this folder", quick.ToString());
    }

    [Fact]
    public void An_endpoint_already_valid_returns_at_once_without_sleeping()
    {
        Publish("""{"csrf":"tok","addr":"localhost:7","published":"x"}""");
        var slept = false;
        var ep = PairingWait.WaitForEndpoint(_ep, new Ports(_ => true), new StringWriter(), () => 0, _ => slept = true);
        Assert.Equal(7, ep.Port);
        Assert.False(slept);
    }
}
