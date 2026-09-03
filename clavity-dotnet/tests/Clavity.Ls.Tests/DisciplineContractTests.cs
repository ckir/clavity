using System.Linq;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class DisciplineContractTests
{
    [Theory]
    [InlineData("agy-capstone", "VERDICT:")]
    [InlineData("agy-test-audit", "VERDICT:")]
    [InlineData("agy-first", "VERDICT:")]
    [InlineData("adversarial-panel-review", "PANEL VERDICT")]
    public void Every_discipline_maps_to_its_own_terminal_token(string discipline, string expected)
    {
        // The token literals live HERE and nowhere else. The three [VERDICT: skills carry 17, 12 and 10
        // occurrences of that string (re-measured 2026-09-03) - but the token is stored WITHOUT the
        // bracket, because TerminalToken strips a leading '[' as decoration and a stored "[VERDICT:"
        // would describe an enforcement the matcher does not perform. The panel skill has ZERO [VERDICT
        // occurrences and closes each ROUND on a single-line PANEL VERDICT.
        Assert.Equal(expected, DisciplineContract.TerminalTokenFor(discipline));
    }

    [Fact]
    public void No_stored_token_begins_with_a_character_the_matcher_strips()
    {
        // TerminalToken strips leading decoration from the LINE only, so a token that BEGINS with one
        // of those characters could never be matched - the line would lose the character while the
        // expectation kept it. A future "[NEW_VERDICT]" would be unsatisfiable. Found as an UNSTATED
        // invariant by AGY-AFTER round 4; this test is what stops it being rediscovered as a live
        // defect by whoever adds the fifth discipline.
        foreach (var d in DisciplineContract.KnownDisciplines)
        {
            var tok = DisciplineContract.TerminalTokenFor(d)!;
            // ASK THE MATCHER, do not restate its set. A hardcoded copy silently stops covering any
            // character added to Decoration later, while still reading as an enforced invariant.
            Assert.False(TerminalToken.IsDecoration(tok[0]),
                $"discipline '{d}' stores token '{tok}', which begins with a stripped character");
        }
    }

    [Fact]
    public void An_unknown_discipline_yields_NO_token_rather_than_a_wrong_one()
    {
        // Guessing a token for an unknown caller would invent a contract. Returning null makes the
        // omission visible at the surface instead (see the [13b] UNCHECKED block in Task 5b).
        Assert.Null(DisciplineContract.TerminalTokenFor("not-a-discipline"));
        Assert.Null(DisciplineContract.TerminalTokenFor(null));
        Assert.Null(DisciplineContract.TerminalTokenFor("  "));
    }

    [Fact]
    public void Lookup_is_case_insensitive()
    {
        // A caller writing AGY-Capstone is naming the right discipline. Failing on case would produce
        // an UNCHECKED consult for a caller that did everything else right.
        Assert.Equal("VERDICT:", DisciplineContract.TerminalTokenFor("AGY-Capstone"));
    }

    [Fact]
    public void KnownDisciplines_lists_exactly_the_four_and_is_the_linter_s_source_of_truth()
    {
        // The skill linter asserts every enrolled skill mandates naming itself. If this list and the
        // linter's list drift, one of them silently stops covering a discipline.
        Assert.Equal(
            new[] { "adversarial-panel-review", "agy-capstone", "agy-first", "agy-test-audit" },
            DisciplineContract.KnownDisciplines.OrderBy(d => d, System.StringComparer.Ordinal).ToArray());
    }
}
