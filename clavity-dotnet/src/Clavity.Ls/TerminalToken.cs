using System.Linq;

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
    // TWO SETS, TWO DIFFERENT QUESTIONS. Conflating them was a reachable false-GREEN; letting them
    // DIVERGE is a reachable false-flag. The names say which question each answers - they are not
    // synonyms for "ornamentation", because a reader who thinks they are will merge them.
    //
    // Q1: DOES THIS LINE EXIST? A line made only of these is furniture ("***"), not content: skip it and
    // keep looking upward. '[' is deliberately ABSENT - see the measurement below.
    private static readonly char[] SkipIfLineIsOnlyThese = { '*', '`', '_', '#', ' ' };

    // Q2: HOW DO I MATCH A LINE THAT DOES EXIST? Stripped from its FRONT before comparing.
    //
    // 🔴 DERIVED, NEVER RETYPED. This is a STRICT SUPERSET of the skip set BY CONSTRUCTION, so the two
    // cannot silently diverge. MEASURED (AGY-CAPSTONE round 2): with the sets written as two independent
    // literals, adding '-' to the skip set alone left the suite 211/211 GREEN while a valid
    // "-VERDICT: ALIGNED" was falsely REJECTED - a false-flag, the exact class this whole change exists
    // to remove, reachable by a one-character edit that no test could see.
    private static readonly char[] StripFromFrontBeforeMatching =
        SkipIfLineIsOnlyThese.Concat(new[] { '[' }).ToArray();

    // WHY '[' IS IN THE SECOND SET AND NOT THE FIRST. Three disciplines tell their peer to write
    // "[VERDICT: ...]", so a peer bracketing a COMPLETE verdict was being flagged as truncated; the
    // tokens in DisciplineContract are stored WITHOUT the bracket so this stripping cannot contradict
    // them. But MEASURED (AGY-CAPSTONE round 1): with '[' also in the SKIP set, a reply ending
    // "VERDICT: ALIGNED\n[" - a model truncated part-way through its next line - had that "[" stripped
    // to empty, SKIPPED as blank, and the verdict ABOVE it matched. The gate returned COMPLETE for a
    // demonstrably truncated reply. Control: the same shape ending in "Z" correctly failed.
    //
    // 🔴 INVARIANT, enforced by DisciplineContractTests: NO STORED TOKEN MAY BEGIN WITH ONE OF THESE
    // CHARACTERS. Only the LINE is stripped, so a token like "[NEW_VERDICT]" would be unsatisfiable -
    // the line loses its '[' and can never match an expectation that still carries one.

    /// <summary>Is this character stripped from the front of a line before matching? EXPOSED so the
    /// invariant test cannot rot: a guard that hardcodes its own copy of the set silently stops covering
    /// the set the moment a character is added here, while still reading as an enforced invariant.</summary>
    public static bool IsDecoration(char c) => Array.IndexOf(StripFromFrontBeforeMatching, c) >= 0;

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
            var raw = lines[i].Trim();

            // SKIP decides whether this line EXISTS; STRIP decides how to match one that does. A line
            // that is ENTIRELY furniture is not content, so look further up; a line that merely STARTS
            // with decoration is a real line, and if what remains does not lead with the token, the reply
            // did not end where it claims to.
            if (raw.TrimStart(SkipIfLineIsOnlyThese).Length == 0) continue;

            return raw.TrimStart(StripFromFrontBeforeMatching).StartsWith(expected, StringComparison.Ordinal);
        }
        return false;
    }
}
