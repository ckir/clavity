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

    /// <summary>The last non-blank line that is not mere furniture, trimmed - the line <see cref="IsSatisfied"/> judges. Null when
    /// there is none. It exists so the [13b] TRUNCATED REPLY notice can say WHICH line it saw (a mismatched closing line looks
    /// exactly like a cut reply otherwise, which cost the flux sessions many recoveries from the reply file).</summary>
    public static string? LastLine(string? answer)
    {
        if (string.IsNullOrWhiteSpace(answer)) return null;
        var lines = answer.Split('\n');
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var raw = lines[i].Trim();
            if (raw.TrimStart(SkipIfLineIsOnlyThese).Length == 0) continue;
            return raw;
        }
        return null;
    }

    /// <summary>The line with the same decoration removed from its front that <see cref="IsSatisfied"/> removes before matching.</summary>
    public static string StripDecoration(string line) => line.TrimStart(StripFromFrontBeforeMatching);

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

            // CASE-SENSITIVE (Ordinal), DELIBERATELY - and this comment exists because it was tried the
            // other way and measured worse. AGY-CAPSTONE round 2 folded this to OrdinalIgnoreCase to
            // tolerate a case-drifted "[Verdict: ALIGNED]"; round 3's fold-auditor caught the regression:
            // "PANEL VERDICT" carries NO trailing punctuation, so case-folding let StartsWith accept
            // ordinary prose that merely opens with those words ("panel verdict is still pending") - a
            // false-PASS in the completeness gate. A case drift is only a SAFE-direction false-FLAG (a
            // complete reply flagged as truncated is recovered by one re-ask); an accepted truncation is
            // not recoverable. The peer is told to emit the exact token, so enforce it exactly rather than
            // trade a recoverable flag for a truncation that slips through. Pinned by
            // TerminalTokenTests.The_token_match_stays_case_SENSITIVE_...
            return raw.TrimStart(StripFromFrontBeforeMatching).StartsWith(expected, StringComparison.Ordinal);
        }
        return false;
    }
}
