using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ModalGuardTests
{
    [Fact]
    public void SurfacingModalGuard_reports_the_operation_and_a_nonempty_hint()
    {
        var report = new SurfacingModalGuard().OnLsTimeout("WaitForConversationFullyIdle", TimeSpan.FromSeconds(120));
        Assert.Equal("WaitForConversationFullyIdle", report.Operation);
        Assert.Equal(TimeSpan.FromSeconds(120), report.Elapsed);
        Assert.False(string.IsNullOrWhiteSpace(report.Hint));
        Assert.Contains("modal", report.Hint, StringComparison.OrdinalIgnoreCase);
    }
}
