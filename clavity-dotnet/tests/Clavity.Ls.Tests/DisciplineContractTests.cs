using System.Linq;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class DisciplineContractTests
{
    [Theory]
    [InlineData("agy-capstone", "[VERDICT:")]
    [InlineData("agy-test-audit", "[VERDICT:")]
    [InlineData("agy-first", "[VERDICT:")]
    [InlineData("adversarial-panel-review", "PANEL VERDICT")]
    public void Every_discipline_maps_to_its_own_terminal_token(string discipline, string expected)
    {
        // The token literals live HERE and nowhere else. Measured 2026-08-19: the first three use
        // [VERDICT: (17, 12 and 10 occurrences); adversarial-panel-review uses GREEN and has ZERO
        // [VERDICT occurrences - SKILL.md:208, "For this skill that means GREEN".
        Assert.Equal(expected, DisciplineContract.TerminalTokenFor(discipline));
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
        Assert.Equal("[VERDICT:", DisciplineContract.TerminalTokenFor("AGY-Capstone"));
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
