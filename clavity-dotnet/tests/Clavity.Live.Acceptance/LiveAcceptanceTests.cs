// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

namespace Clavity.Live.Acceptance;

// Tier B — live acceptance (plan §4). These tests touch a REAL logged-in agy and are the authority
// on real h2c wire behavior. They are gated: excluded from CI via the "LiveAgy" trait
// (`dotnet test --filter "Category!=LiveAgy"`) and skipped unless CLAVITY_LIVE_AGY=1.
public class LiveAcceptanceTests
{
    [Fact(Skip = "Live acceptance runbook — set CLAVITY_LIVE_AGY=1 and run with --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public void Live_contract_reverification_round_trip_against_a_real_agy_is_not_written_yet()
    {
        // NOT IMPLEMENTED. Will verify, on a live logged-in agy session: discover the LS port from its log ->
        // GetConversationMetadata -> a benign SendUserCascadeMessage round-trip -> WaitForConversationFullyIdle ->
        // read the reply. Until it exists the test is skipped rather than asserting anything vacuous.
    }
}
