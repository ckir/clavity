using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class PairingWaitTests : IDisposable
{
    private readonly string _ep = Path.Combine(Path.GetTempPath(), $"agy-endpoint-wait-{Guid.NewGuid():N}.json");
    private readonly string _exited = Path.Combine(Path.GetTempPath(), $"agy-session-wait-{Guid.NewGuid():N}.exited");

    public void Dispose()
    {
        foreach (var f in new[] { _ep, _exited })
            if (File.Exists(f))
                File.Delete(f);
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

        var ep = PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), output, now, sleep);

        Assert.Equal(4242, ep!.Port);
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
        var ep = PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => now() >= listeningFrom), new StringWriter(), now, sleep);
        Assert.Equal(4242, ep!.Port);
        Assert.True(now() >= listeningFrom, $"returned at {now()} ms, before the port listened");
    }

    [Fact]
    public void The_trust_prompt_hint_appears_once_after_10_s_and_not_before()
    {
        var (now, sleep) = Clock(t => { if (t >= 25_000) Publish("""{"csrf":"tok","addr":"localhost:1","published":"x"}"""); });
        var output = new StringWriter();
        PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), output, now, sleep);

        var text = output.ToString();
        Assert.Equal(1, text.Split("trust this folder").Length - 1);
        // ...and it came AFTER 10 s: a run that pairs at 9.5 s never shows it.
        var quick = new StringWriter();
        if (File.Exists(_ep)) File.Delete(_ep);
        var (now2, sleep2) = Clock(t => { if (t >= 9_500) Publish("""{"csrf":"tok","addr":"localhost:1","published":"x"}"""); });
        PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), quick, now2, sleep2);
        Assert.DoesNotContain("trust this folder", quick.ToString());
    }

    [Fact]
    public void An_endpoint_already_valid_returns_at_once_without_sleeping()
    {
        Publish("""{"csrf":"tok","addr":"localhost:7","published":"x"}""");
        var slept = false;
        var ep = PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), new StringWriter(), () => 0, _ => slept = true);
        Assert.Equal(7, ep!.Port);
        Assert.False(slept);
    }

    [Fact]
    public void An_exited_file_without_a_pairing_ends_the_wait_with_agys_exit_code()
    {
        // Capstone R1: agy died (or never started) after the terminal claimed - the wait must not run forever.
        var (now, sleep) = Clock(t => { if (t >= 2000) File.WriteAllText(_exited, "127\n"); });
        var output = new StringWriter();

        Assert.Null(PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), output, now, sleep));
        Assert.Contains("agy exited before pairing (exit 127) - Claude was NOT started", output.ToString());
        Assert.InRange(now(), 2000, 3000);
    }

    [Fact]
    public void An_empty_exited_file_reports_an_unknown_exit()
    {
        File.WriteAllText(_exited, "");
        var output = new StringWriter();
        Assert.Null(PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), output, () => 0, _ => { }));
        Assert.Contains("(exit unknown)", output.ToString());
    }

    [Fact]
    public void A_pairing_wins_over_an_exited_file_and_a_published_but_dead_port_does_not()
    {
        File.WriteAllText(_exited, "1");
        Publish("""{"csrf":"tok","addr":"localhost:4242","published":"x"}""");
        // Listening: paired, even though agy has since recorded an end (ChannelDown's case, not this one).
        Assert.Equal(4242, PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), new StringWriter(), () => 0, _ => { })!.Port);
        // Published but not listening: agy published and then died - abort, do not wait for a port that never opens.
        Assert.Null(PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => false), new StringWriter(), () => 0, _ => { }));
    }

    [Fact]
    public void The_hint_tells_the_user_that_a_closed_tab_means_press_Ctrl_C()
    {
        var (now, sleep) = Clock(t => { if (t >= 11_000) Publish("""{"csrf":"tok","addr":"localhost:1","published":"x"}"""); });
        var output = new StringWriter();
        PairingWait.WaitForEndpoint(_ep, _exited, new Ports(_ => true), output, now, sleep);
        Assert.Contains("If the tab has closed or shows an error, agy is not running - press Ctrl+C.", output.ToString());
    }
}
