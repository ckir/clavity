using Clavity.Ls;
using Xunit.Abstractions;

namespace Clavity.Live.Acceptance;

// Tier B — live acceptance (repo-plan T10). Drives the PRODUCTION write path end-to-end against a REAL agy
// over h2c: AgyView.AskAsync = SendUserCascadeMessage -> WaitForConversationFullyIdle -> GetCascadeTrajectory.
// This is the one place the live SendUserCascadeMessage write is exercised (the fake LS covers it in CI).
// ⚠ WRITE: consumes agy quota and posts a VISIBLE message into the conversation. Gated: excluded from CI by the
// "LiveAgy" trait (`dotnet test --filter "Category!=LiveAgy"`) and Skip unless run deliberately with
// CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG = the per-session agy `--log-file`. The conversation id is resolved
// from the LS (GetAllCascadeTrajectories) inside AgyView — the agy session must already have a conversation.
public class AgyAskLiveTests
{
    private readonly ITestOutputHelper _out;
    public AgyAskLiveTests(ITestOutputHelper output) => _out = output;

    private static bool LiveAgyEnabled => Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    private static string CliLogPath =>
        Environment.GetEnvironmentVariable("CLAVITY_LIVE_CLILOG")
        ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".gemini", "antigravity-cli", "cli.log");

    // Happy path: send a uniquely-tagged message, wait for idle, read the reply delta. The reply is returned as a
    // size-bounded, id-free view; assistant text is not modeled (deferred per spec §5), so the proof is structural:
    // our message must land as a user-input step (SendUserCascadeMessage reached agy), and agy must append at least
    // one more step beyond it (the round-trip completed — not merely our own echo).
    [Fact(Skip = "Live WRITE: set CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CLILOG, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Real_agy_completes_ask_round_trip_via_AgyView()
    {
        Assert.True(LiveAgyEnabled);

        var message = $"clavity T10 live acceptance {Guid.NewGuid():N}. Reply with the single word PONG.";
        var view = new AgyView(new AgyViewOptions { CliLogPath = CliLogPath });

        var reply = await view.AskAsync(message, timeout: TimeSpan.FromSeconds(120));

        _out.WriteLine($"cascade id: {reply.CascadeId}");
        _out.WriteLine($"new steps (delta after send): {reply.TotalSteps}");
        foreach (var s in reply.Steps)
            _out.WriteLine($"  kind={s.Kind} text={(s.Text is null ? "<null>" : s.Text)}");

        Assert.False(string.IsNullOrEmpty(reply.CascadeId));
        Assert.Contains(reply.Steps, s => s.Text == message);   // our message landed as a user step.
        Assert.True(reply.TotalSteps >= 2,                       // agy appended a reply beyond our message.
            $"expected >= 2 new steps (our message + agy reply); got {reply.TotalSteps}");
    }
}
