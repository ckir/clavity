using System;
using System.Collections.Generic;
using System.Linq;

namespace Clavity.Ls;

/// <summary>Maps a discipline to the terminal token its replies must end with. THE ONLY PLACE these
/// literals live.
///
/// It exists because the alternative - every caller passing "[VERDICT:" by hand - makes the completeness
/// check voluntary: mistype it or omit it and the guard silently does nothing. An AGY-AFTER panel called
/// that compliance theater, and it was right. The caller now names only WHICH discipline it is; the driver
/// supplies the contract.
///
/// The four do not share a grammar, which is exactly why this table exists rather than one regex:
/// adversarial-panel-review ends on GREEN (its SKILL.md:208), the other three on [VERDICT:.</summary>
public static class DisciplineContract
{
    private static readonly Dictionary<string, string> Tokens =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["agy-capstone"] = "[VERDICT:",
            ["agy-test-audit"] = "[VERDICT:",
            ["agy-first"] = "[VERDICT:",
            ["adversarial-panel-review"] = "GREEN",
        };

    /// <summary>The disciplines this driver knows. The skill linter enrols exactly these.</summary>
    public static IReadOnlyCollection<string> KnownDisciplines => Tokens.Keys.ToArray();

    /// <summary>The token, or null for an unknown/absent discipline - never a guess.</summary>
    public static string? TerminalTokenFor(string? discipline) =>
        !string.IsNullOrWhiteSpace(discipline) && Tokens.TryGetValue(discipline, out var t) ? t : null;
}
