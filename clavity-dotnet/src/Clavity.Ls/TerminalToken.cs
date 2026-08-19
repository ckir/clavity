namespace Clavity.Ls;

/// <summary>Is a reply STRUCTURALLY complete - does it end with the terminal token its calling discipline
/// mandates? This is the deterministic half of 13b: a reply whose token is missing, or present but not at
/// the end, lost its tail on the wire or stopped mid-thought.
///
/// It deliberately does NOT judge whether the WORK was done. A lone verdict line with no body satisfies
/// this check and is caught (heuristically) by <see cref="ReplySizeHistory"/> instead. Conflating the two
/// is what made the first design brittle.
///
/// The expectation is supplied PER CALL because the four disciplines do not share a grammar: agy-capstone,
/// agy-test-audit and agy-first end on "[VERDICT:", while adversarial-panel-review ends on "GREEN"
/// (adversarial-panel-review/SKILL.md:208). A single hardcoded pattern would flag every panel reply.</summary>
public static class TerminalToken
{
    /// <param name="answer">The reply text, or null when the delta ended on a non-assistant step.</param>
    /// <param name="expected">The literal the last non-blank line must contain; null = caller opts out.</param>
    public static bool IsSatisfied(string? answer, string? expected)
    {
        // No expectation = not a discipline call. Never report those as truncated.
        if (string.IsNullOrWhiteSpace(expected)) return true;
        if (string.IsNullOrWhiteSpace(answer)) return false;

        // The LAST NON-BLANK line, not merely "contains": the spec's oracle is "missing OR NOT AT THE END".
        //
        // STARTS-WITH, NOT CONTAINS. A substring test accepts a line that NEGATES the token:
        //     "Tests are not GREEN".Contains("GREEN") == true
        // so a reply asserting the review FAILED would satisfy a check for GREEN. Measured against this
        // plan's own first draft during its AGY-AFTER panel. Leading markdown emphasis is stripped first,
        // because a peer that writes **GREEN** or `GREEN` is complying, not failing.
        var lines = answer.Split('\n');
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var line = lines[i].Trim().TrimStart('*', '`', '_', '#', ' ');
            if (line.Length == 0) continue;
            return line.StartsWith(expected, StringComparison.Ordinal);
        }
        return false;
    }
}
