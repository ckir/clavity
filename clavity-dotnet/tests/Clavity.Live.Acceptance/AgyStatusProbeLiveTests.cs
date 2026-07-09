using Clavity.Ls;

namespace Clavity.Live.Acceptance;

// LIVE: confirms the deadline-bounded idle probe. With agy IDLE, ProbeIdleAsync must return "idle" within ~300ms.
// If it returns "working" on a known-idle agy, the RPC uses call-time semantics ⇒ NO-GO (ship unknown-only).
public class AgyStatusProbeLiveTests
{
    private static bool Enabled => Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    [Fact(Skip = "Live: set CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Probe_reports_idle_for_an_idle_agy_within_the_deadline()
    {
        Assert.True(Enabled);
        var cliLog = Environment.GetEnvironmentVariable("CLAVITY_LIVE_CLILOG")!;
        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
        var st = await view.StatusAsync();   // agy assumed idle at test time
        Assert.Equal("idle", st.State);      // NO-GO signal if this is "working"
    }
}
