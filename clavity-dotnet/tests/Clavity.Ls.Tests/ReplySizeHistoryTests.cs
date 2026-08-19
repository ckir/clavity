using System.Collections.Generic;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class ReplySizeHistoryTests
{
    [Fact]
    public void Too_few_samples_never_warns()
    {
        // With no baseline there is nothing to be anomalous AGAINST. Warning here would fire on every
        // first-ever consult, which trains the operator to ignore the warning - the failure this avoids.
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new[] { 15000, 16000 }, 300));
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new int[0], 300));
    }

    [Fact]
    public void A_tiny_reply_after_large_ones_WARNS()
    {
        // The lone-verdict-line shape: 300 bytes where the last three were ~15 KB.
        Assert.True(ReplySizeHistory.IsAnomalouslySmall(new[] { 15000, 16500, 14000 }, 300));
    }

    [Fact]
    public void A_normal_reply_does_NOT_warn()
    {
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new[] { 15000, 16500, 14000 }, 12000));
    }

    [Fact]
    public void A_uniformly_small_history_does_NOT_warn_on_another_small_reply()
    {
        // A peer that always answers briefly is not truncating. The baseline is that peer's OWN norm,
        // not an absolute floor - an absolute floor would cry wolf on every terse discipline.
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new[] { 400, 350, 380 }, 300));
    }

    [Fact]
    public void ONE_huge_outlier_does_not_drag_the_baseline_because_the_stat_is_a_MEDIAN()
    {
        // MUTATION-AUDIT ROW, not in the plan. The class comment claims the baseline is "a MEDIAN, which
        // a single outlier cannot drag" - and swapping the median for a mean left all five planned rows
        // GREEN, so the claim was decoration. A peer whose norm is ~400 bytes and who once emitted a
        // 100 KB reply must not have every subsequent short-but-honest reply flagged.
        // median of {380, 400, 100000} = 400, so 350 is not below 25% of it; the mean is 33593, and
        // under a mean this would warn.
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new[] { 400, 380, 100000 }, 350));
    }

    [Fact]
    public void Only_the_most_recent_N_are_used()
    {
        // Ten old 15 KB replies must not keep flagging a peer whose recent norm has legitimately dropped.
        var history = new List<int> { 15000, 15000, 15000, 15000, 15000, 400, 350, 380, 390, 370 };
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(history, 300));
    }
}
