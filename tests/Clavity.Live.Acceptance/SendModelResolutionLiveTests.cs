using Clavity.Ls;

namespace Clavity.Live.Acceptance;

// LIVE WRITE: dynamically resolves the model from the live conversation and sends it. Set CLAVITY_LIVE_AGY=1 +
// CLAVITY_LIVE_CLILOG, run --filter "Category=LiveAgy". Proves a real agy accepts the dynamically-resolved id
// (the silent-break this item prevents). Consumes quota; posts a visible message.
public class SendModelResolutionLiveTests
{
    private static bool LiveAgyEnabled => Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    [Fact(Skip = "Live WRITE: set CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Dynamically_resolved_model_is_accepted_by_a_real_send()
    {
        Assert.True(LiveAgyEnabled);
        var cliLog = Environment.GetEnvironmentVariable("CLAVITY_LIVE_CLILOG")!;
        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });

        // No exception ⇒ the resolved id was accepted (no "neither PlanModel nor RequestedModel specified" / no
        // "unknown model key"). The reply content is incidental here.
        var reply = await view.AskAsync("clavity live model-resolution acceptance: reply 'ok'.");
        Assert.NotNull(reply);
    }
}
