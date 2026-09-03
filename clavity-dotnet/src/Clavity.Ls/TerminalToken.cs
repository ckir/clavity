namespace Clavity.Ls;

/// <summary>Is a reply STRUCTURALLY complete - does it end with the terminal token its calling discipline
/// mandates? This is the deterministic half of 13b: a reply whose token is missing, or present but not at
/// the end, lost its tail on the wire or stopped mid-thought.
///
/// It deliberately does NOT judge whether the WORK was done, and NOTHING here does any more: a lone
/// verdict line with no body satisfies this check. A size heuristic used to flag that case; it was deleted
/// with the reply archive that fed it, because the archive produced ten of the review's nineteen defects
/// to deliver a warning nobody was obliged to act on. That trade is stated plainly rather than left for a
/// reader to infer from an absence.
///
/// The expectation is supplied PER CALL because the four disciplines do not share a grammar: agy-capstone,
/// agy-test-audit and agy-first end on "VERDICT:", while adversarial-panel-review closes each round on a
/// single-line "PANEL VERDICT" (its SKILL.md, section "Step 1 - Solo panel"). A single hardcoded pattern
/// would flag every panel reply.</summary>
public static class TerminalToken
{
    // '[' IS DECORATION. Three disciplines tell their peer to write "[VERDICT: ...]", so a peer that
    // brackets a COMPLETE verdict was being flagged as truncated. The tokens in DisciplineContract are
    // stored WITHOUT the bracket precisely so that stripping it here cannot contradict them.
    //
    // 🔴 INVARIANT, enforced by DisciplineContractTests: NO STORED TOKEN MAY BEGIN WITH ONE OF THESE
    // CHARACTERS. Only the LINE is stripped, so a token like "[NEW_VERDICT]" would be unsatisfiable -
    // the line loses its '[' and can never match an expectation that still carries one.
    private static readonly char[] Decoration = { '*', '`', '_', '#', ' ', '[' };

    /// <summary>Is this character stripped from the front of a line before matching? EXPOSED so the
    /// invariant test cannot rot: a guard that hardcodes its own copy of the set silently stops covering
    /// the set the moment a character is added here, while still reading as an enforced invariant.</summary>
    public static bool IsDecoration(char c) => Array.IndexOf(Decoration, c) >= 0;

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
            var line = lines[i].Trim().TrimStart(Decoration);
            if (line.Length == 0) continue;
            return line.StartsWith(expected, StringComparison.Ordinal);
        }
        return false;
    }
}
