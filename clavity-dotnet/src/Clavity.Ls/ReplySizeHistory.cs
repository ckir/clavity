using System;
using System.Collections.Generic;
using System.Linq;

namespace Clavity.Ls;

/// <summary>Is this reply anomalously small against THIS peer's own recent replies? The heuristic half of
/// 13b, and it is a WARNING, never a gate.
///
/// It exists because the deterministic token oracle is blind to the ROADMAP entry's worst measured case: a
/// lone verdict line whose prose claimed the review had been printed when nothing else was emitted. The
/// token is present there; only the size betrays it.
///
/// It is deliberately relative, not absolute. A genuine "no findings" reply is short AND correct, so an
/// absolute floor would fire constantly and be tuned out. The comparison is against a MEDIAN, which a
/// single outlier cannot drag, and against only the most recent samples, so a peer whose norm legitimately
/// changes stops being flagged.</summary>
public static class ReplySizeHistory
{
    /// <summary>Samples needed before any judgement. Below this there is no baseline to be anomalous against.</summary>
    public const int MinimumSamples = 3;

    /// <summary>How many recent replies form the baseline.</summary>
    public const int Window = 5;

    /// <summary>Fraction of the median below which a reply is flagged.</summary>
    public const double Fraction = 0.25;

    public static bool IsAnomalouslySmall(IReadOnlyCollection<int> recentSizes, int currentSize)
    {
        if (recentSizes is null || recentSizes.Count < MinimumSamples) return false;

        var window = recentSizes.Skip(Math.Max(0, recentSizes.Count - Window)).OrderBy(n => n).ToList();
        var median = window.Count % 2 == 1
            ? window[window.Count / 2]
            : (window[window.Count / 2 - 1] + window[window.Count / 2]) / 2.0;

        if (median <= 0) return false;
        return currentSize < median * Fraction;
    }
}
