using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class TerminalTokenTests
{
    [Fact]
    public void Null_expectation_always_satisfied()
    {
        // A caller that names no token is opting out. It must never be reported as truncated,
        // or every non-discipline ask (agy_look, a bare question) reds forever.
        Assert.True(TerminalToken.IsSatisfied("anything at all", null));
        Assert.True(TerminalToken.IsSatisfied(null, null));
    }

    [Fact]
    public void Token_on_the_last_non_blank_line_is_satisfied()
    {
        var reply = "## Findings\n\nsomething\n\n[VERDICT: ALIGNED]\n\n   \n";
        Assert.True(TerminalToken.IsSatisfied(reply, "VERDICT:"));
    }

    [Fact]
    public void Token_present_but_NOT_at_the_end_is_NOT_satisfied()
    {
        // THE CASE THE SPEC NAMES: "a stored reply whose token is missing OR NOT AT THE END is a
        // truncated reply". A reply that quotes the token mid-body and then dies still lost its tail.
        var reply = "I will end with [VERDICT: ALIGNED] once done.\n\nNow the findings:\n- one\n";
        Assert.False(TerminalToken.IsSatisfied(reply, "VERDICT:"));
    }

    [Fact]
    public void A_LONG_reply_missing_the_token_is_DETECTED()
    {
        // THE FAILING CONTROL THE SPEC DEMANDS. 20 KB of perfectly good review text with no terminal
        // token: this is a model that truncated ITSELF while the transport delivered every byte.
        // It proves detection is STRUCTURAL, not size-based - a byte-count check would pass this.
        var reply = new string('x', 20 * 1024) + "\nlast line with no token\n";
        Assert.False(TerminalToken.IsSatisfied(reply, "VERDICT:"));
    }

    [Fact]
    public void Null_or_blank_answer_with_an_expectation_is_NOT_satisfied()
    {
        Assert.False(TerminalToken.IsSatisfied(null, "VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("   \n\n", "VERDICT:"));
    }

    [Fact]
    public void A_line_that_NEGATES_the_token_is_NOT_satisfied()
    {
        // AGY-AFTER panel finding, verified: a CONTAINS test accepts "Tests are not GREEN" as proof of
        // GREEN - a reply asserting the opposite of completion would pass. This is why the check is
        // STARTS-WITH. Without this row the fix has no oracle.
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nTests are not GREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("done\n\nno [VERDICT: ...] was produced\n", "VERDICT:"));
    }

    [Fact]
    public void Markdown_emphasis_around_the_token_still_counts_as_compliance()
    {
        // A peer writing **GREEN** is complying. Failing it would train operators to ignore the check.
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\n**GREEN**\n", "GREEN"));
    }

    [Fact]
    public void The_panel_token_comes_from_the_contract_and_accepts_a_findings_bearing_round()
    {
        // adversarial-panel-review does NOT use [VERDICT: - it closes each ROUND on a single-line
        // PANEL VERDICT (its SKILL.md, "Step 1 - Solo panel"). The token was GREEN until 2026-09-03,
        // which flagged EVERY findings-bearing round: the skill's Outputs section declares four
        // legitimate dispositions and only one is GREEN, so a round that found something was told it
        // was incomplete and its findings should be discarded. Measured five times - by this change's
        // own AGY-AFTER panel, every round of which was flagged while carrying real blocking defects.
        //
        // NOTE the two objects, or a later reader will "reconcile" them and revert this: GREEN is
        // still the RUN-level disposition (that skill's Outputs, and its Completeness gate - "For this
        // skill that means GREEN"). PANEL VERDICT is the PER-ROUND closing line, and a peer's reply IS
        // one round. This table checks a reply, so it takes the round-level token.
        //
        // READ FROM THE TABLE. A literal here would pass before the table changed and prove nothing -
        // measured: the literal form returned Failed 0, Passed 1 against the unchanged contract.
        var tok = DisciplineContract.TerminalTokenFor("adversarial-panel-review");
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nPANEL VERDICT: 2 open findings remain\n", tok));

        // Decoration at the ENDS is compliance, not failure - a distinct branch (TrimStart).
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\n**PANEL VERDICT: GREEN**\n", tok));

        // Still rejects a reply that never reached a verdict line at all.
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nopen findings remain\n", tok));
    }

    [Fact]
    public void A_bracket_wrapped_verdict_is_compliance_not_truncation()
    {
        // Three disciplines tell their peer to write "[VERDICT: ...]", so peers bracket by habit and a
        // COMPLETE reply must not be flagged for it. The bracket is stripped as decoration; the tokens
        // in DisciplineContract are stored without it so the contract states what is enforced.
        Assert.True(TerminalToken.IsSatisfied("x\n\n[VERDICT: ALIGNED]\n", "VERDICT:"));

        // Nesting works in EITHER order, because the characters are stripped as a set, not in sequence.
        Assert.True(TerminalToken.IsSatisfied("x\n\n[**VERDICT: ALIGNED**]\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n**[VERDICT: ALIGNED]**\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n[PANEL VERDICT: GREEN]\n", "PANEL VERDICT"));

        // THE BRACKET IS NOW OPTIONAL AND THE CONTRACT SAYS SO. Pinned here so it reads as a decision
        // rather than an oversight: it cannot be optional decoration AND enforced structure at once.
        Assert.True(TerminalToken.IsSatisfied("x\n\n* VERDICT: ALIGNED\n", "VERDICT:"));

        // REGRESSION GUARDS - the token must still LEAD the line, which is what StartsWith enforces.
        Assert.False(TerminalToken.IsSatisfied("x\n\nno [VERDICT: ...] was produced\n", "VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nTests are not GREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nlast line with no token\n", "VERDICT:"));
    }

    [Fact]
    public void A_line_that_is_ONLY_decoration_does_not_mask_a_truncated_reply()
    {
        // AGY-CAPSTONE round 1, BLOCKING, and introduced by adding '[' to the strip set: a line
        // containing only '[' stripped to empty, was SKIPPED as blank, and the verdict ABOVE it matched.
        // A model truncated part-way through its next line was therefore reported COMPLETE - a
        // false-GREEN in the completeness gate itself.
        //
        // The fix separates the two questions: SkipIfLineIsOnlyThese decides whether a line EXISTS,
        // StripFromFrontBeforeMatching decides how to match one that does - and the second is DERIVED
        // from the first, so a later edit cannot make them diverge (AGY-CAPSTONE round 2 measured that
        // divergence: adding '-' to the skip set alone kept the suite green while falsely rejecting a
        // valid "-VERDICT: ALIGNED").
        Assert.False(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n[", "VERDICT:"));

        // CONTROL, and it is what isolated the defect to '[': the identical shape ending in a character
        // that was never in either set already failed. Without this row a fix could be credited to the
        // wrong cause.
        Assert.False(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\nZ", "VERDICT:"));

        // AND THE BEHAVIOUR THAT MUST NOT REGRESS THE OTHER WAY. Markdown furniture after a verdict was
        // skipped before this change and must still be: "only skip genuinely blank lines" would have
        // fixed the false-GREEN by falsely flagging every reply that signs off with a rule.
        Assert.True(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n***\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n\n   \n", "VERDICT:"));
    }

    [Fact]
    public void EVERY_character_in_the_skip_set_is_treated_as_furniture()
    {
        // AGY-TEST-AUDIT 2026-09-04, Mechanism Gamer. The skip set carries FIVE characters and only '*'
        // and ' ' had a fixture. MEASURED: shrinking it to { '*', ' ' } left the suite 211/211 GREEN, so
        // three of the five were unpinned - a maintainer "simplifying" the array would falsely FLAG every
        // reply that signs off with a code fence, an underscore rule, or a trailing heading marker.
        Assert.True(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n```\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n___\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n###\n", "VERDICT:"));

        // Mixed, because the characters are stripped as a SET and not in sequence.
        Assert.True(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n *_`# \n", "VERDICT:"));

        // THE DISTRACTOR, and it is what stops this test passing on a matcher that skips any line
        // CONTAINING furniture: one of these characters plus real text is CONTENT, so it must NOT be
        // skipped - otherwise the verdict above it would certify a reply truncated in its next line.
        Assert.False(TerminalToken.IsSatisfied("findings\n\nVERDICT: ALIGNED\n# Next section\n", "VERDICT:"));
    }

    [Fact]
    public void A_reply_that_is_ONE_LINE_is_matched()
    {
        // AGY-TEST-AUDIT 2026-09-04, Boundary Smuggler. Every other fixture in this file carries a
        // newline, so index 0 was never the line that decided the answer. MEASURED: both the literal
        // `if (lines.Length == 1) return false;` after the Split AND the far more plausible off-by-one
        // `for (var i = lines.Length - 1; i > 0; i--)` left the suite 211/211 GREEN. A loop rewrite could
        // therefore drop the whole reply, whenever the reply is a single line, with nothing going red.
        Assert.True(TerminalToken.IsSatisfied("[VERDICT: ALIGNED]", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("PANEL VERDICT: GREEN", "PANEL VERDICT"));

        // THE FAILING CONTROL at the identical shape. Without it the rows above would also pass on a
        // matcher that returns true for ANY single-line input.
        Assert.False(TerminalToken.IsSatisfied("no verdict here", "VERDICT:"));
    }

    [Fact]
    public void IsDecoration_ANSWERS_the_question_the_invariant_guard_asks_it()
    {
        // AGY-TEST-AUDIT 2026-09-04, driver. DisciplineContractTests asserts !IsDecoration(tok[0]) for
        // every stored token - but nothing asserted IsDecoration returns TRUE for anything, so that guard
        // was vacuous under a broken oracle. MEASURED: `IsDecoration(char c) => false` left the suite
        // 211/211 GREEN while the guard still read as enforced. The doc comment on that method claims it
        // is exposed "so the invariant test cannot rot"; without this row the ORACLE rots instead, and
        // the fifth discipline to be added could store an unsatisfiable token unchallenged.
        Assert.True(TerminalToken.IsDecoration('['));   // the character the whole bracket fold turns on
        Assert.True(TerminalToken.IsDecoration('*'));
        Assert.True(TerminalToken.IsDecoration('`'));
        Assert.True(TerminalToken.IsDecoration('_'));
        Assert.True(TerminalToken.IsDecoration('#'));
        Assert.True(TerminalToken.IsDecoration(' '));

        // THE DISTRACTORS - it must REJECT a near-miss, or `=> true` satisfies every row above. 'V' and
        // 'P' are the first characters of the four stored tokens, which is precisely what the invariant
        // guard hands it; '-' is the character the capstone's divergence mutant used.
        Assert.False(TerminalToken.IsDecoration('V'));
        Assert.False(TerminalToken.IsDecoration('P'));
        Assert.False(TerminalToken.IsDecoration('-'));
    }

    [Fact]
    public void A_CRLF_reply_is_matched_INCLUDING_its_furniture_lines()
    {
        // AGY-TEST-AUDIT 2026-09-04, driver. The reply is split on '\n', so CRLF input leaves a trailing
        // '\r' on every line, and only the TRAILING half of `.Trim()` removes it. MEASURED:
        // `lines[i].Trim()` -> `lines[i].TrimStart()` left the suite 211/211 GREEN, because every fixture
        // used bare '\n'. Under that mutant a CRLF sign-off rule reads as "***\r", which is no longer
        // PURE furniture: it is not skipped, does not start with the token, and a complete reply is
        // falsely FLAGGED as truncated. That is the exact class this whole change exists to remove.
        Assert.True(TerminalToken.IsSatisfied("findings\r\n\r\nVERDICT: ALIGNED\r\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("findings\r\n\r\nVERDICT: ALIGNED\r\n***\r\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("findings\r\n\r\n[VERDICT: ALIGNED]\r\n", "VERDICT:"));

        // THE FAILING CONTROL: CRLF must not become a way to PASS a reply that never reached a verdict.
        Assert.False(TerminalToken.IsSatisfied("findings\r\n\r\nlast line with no token\r\n", "VERDICT:"));
    }
}
