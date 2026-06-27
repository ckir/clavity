namespace Clavity.Live.Acceptance;

// Tier B — live acceptance (plan §4). These tests touch a REAL logged-in agy and are the authority
// on real h2c wire behavior. They are gated: excluded from CI via the "LiveAgy" trait
// (`dotnet test --filter "Category!=LiveAgy"`) and skipped unless CLAVITY_LIVE_AGY=1.
public class LiveAcceptanceTests
{
    private static bool LiveAgyEnabled =>
        Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    [Fact(Skip = "Live acceptance runbook — set CLAVITY_LIVE_AGY=1 and run with --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public void Placeholder_ContractReVerification()
    {
        // Filled in at plan task T10: discover LS port on a live session -> GetConversationMetadata
        // -> benign SendUserCascadeMessage round-trip -> WaitForConversationFullyIdle -> read reply.
        Assert.True(LiveAgyEnabled);
    }
}
