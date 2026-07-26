using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ModalGuardTests
{
    [Fact]
    public void Stall_report_names_both_a_modal_and_a_long_single_step()
    {
        var report = new SurfacingModalGuard().OnLsTimeout(
            "WaitForConversationFullyIdle", TimeSpan.FromSeconds(120), IdleLimit.Stall);

        Assert.Equal("WaitForConversationFullyIdle", report.Operation);
        Assert.Equal(TimeSpan.FromSeconds(120), report.Elapsed);
        Assert.Equal(IdleLimit.Stall, report.Limit);
        // F4: the stall hint must name BOTH failure causes, never modal-only.
        Assert.Contains("modal", report.Hint, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("long step", report.Hint, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("CLAVITY_AGY_IDLE_STALL_SECONDS", report.Hint);
    }

    [Fact]
    public void Absolute_max_report_says_progressing_exceeded_budget_and_does_not_claim_a_modal()
    {
        var report = new SurfacingModalGuard().OnLsTimeout(
            "WaitForConversationFullyIdle", TimeSpan.FromSeconds(600), IdleLimit.AbsoluteMax);

        Assert.Equal(IdleLimit.AbsoluteMax, report.Limit);
        Assert.DoesNotContain("modal", report.Hint, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("CLAVITY_AGY_IDLE_MAX_SECONDS", report.Hint);
    }
}
