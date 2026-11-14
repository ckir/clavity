// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



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

            // NON-EMPTY FIRST, or this guard CRASHES instead of reporting. AGY-CAPSTONE round 1: tok[0]
            // on an empty token throws IndexOutOfRangeException, so the suite would die with a stack
            // trace rather than naming the offending discipline. And an empty token is the worse bug it
            // would have been hiding - IsSatisfied treats a blank expectation as "caller opted out" and
            // returns true unconditionally, so that discipline's gate silently stops existing.
            Assert.False(string.IsNullOrWhiteSpace(tok),
                $"discipline '{d}' stores an empty token, which disables its completeness check entirely");

            // ASK THE MATCHER, do not restate its set. A hardcoded copy silently stops covering any
            // character added to Decoration later, while still reading as an enforced invariant.
            Assert.False(TerminalToken.IsDecoration(tok[0]),
                $"discipline '{d}' stores token '{tok}', which begins with a stripped character");

            // The mirror invariant, same family: Trim() removes trailing whitespace from the LINE before
            // matching, so a token that ENDS in whitespace can never be matched by a line that is exactly
            // that token. Cheap to guard, and the guard is the only thing that will say so out loud.
            Assert.Equal(tok.TrimEnd(), tok);
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
