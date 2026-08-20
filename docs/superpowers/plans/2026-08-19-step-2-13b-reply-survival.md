# Step 2 (13b) — make a peer's ANSWER survive truncation · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Every agy reply is captured to disk, structurally validated against the terminal token its calling
discipline mandates, and size-compared against that peer's recent replies as a warning — so a truncated or
never-written review is DETECTED rather than silently accepted.

**Architecture:** Three pure, separately-testable units in `Clavity.Ls` (`ReplyArchive`, `TerminalToken`,
`ReplySizeHistory`), wired at the single seam where `AgyView.AskAsync` already projects its reply. The
expected terminal token is supplied per-call by the calling discipline, because the four disciplines do not
share one grammar. Skill-side, four shipped SKILL.md files gain two measured-missing rules.

**Tech Stack:** C# / .NET 10, xUnit, PowerShell 5.1+ for the pair gate, markdown for the discipline skills.

---

## Why 13b is TWO problems, and why that shapes every task below

Settled by AGY-NEGOTIATE and owner-ruled 2026-08-19:

| problem | signal | strength |
|---|---|---|
| the reply died on the wire, or the model stopped mid-thought | terminal token, **per-discipline** | deterministic PROOF |
| the reply arrived intact but the work was never done — the **lone verdict line** | byte-count vs that peer's recent replies | **HEURISTIC WARNING only** |

**SEMANTIC ECHO covers BOTH, and it is the strongest of the three.** Added after the AGY-AFTER panel
proposed it as a disposition neither the ROADMAP nor the sequencing spec names (verified: no mention of
echo/checkpoint in either). The brief requires the peer to quote, verbatim and immediately before its
verdict, **the last non-blank line of the primary artifact it was told to read**. The driver computes that
line independently from the same file and compares.

> 🔴 **WHAT SHIPPED IS NOT THIS.** Recorded rather than quietly edited: the language server never reads
> the artifact. The CALLING AGENT applies the rule and passes the line in as `expectEcho`; `SemanticEcho`
> only compares two strings. The independence this paragraph claims does not exist - the same party that
> should be checked supplies the expectation - which is a real weakening of the signal and the reason the
> `[13b] NO ECHO` and `[13b] ECHO WEAK` notices had to exist at all. Found by capstone R5's Second Reader,
> in the code comment that had copied this sentence.

**Why it beats both other signals.** A peer that stopped mid-thought never reached the end of the artifact
and cannot produce the line. A peer that emitted a lone verdict line without doing the work never read the
artifact and cannot produce it either. So one check catches transport truncation AND the lone-verdict-line
laziness, **without size statistics that cry wolf on a terse but honest review.**

⚠ **It is NOT free and this plan does not pretend otherwise.** It only works when the consult names a
primary artifact - a review of a pasted question has nothing to echo - so `expectEcho` is optional in
exactly the way `expectTerminal` is. And it is defeatable by a peer that reads only the file's tail. It
raises the floor; it does not prove the work was done.

⚠ **Interaction with the byte-count, stated rather than left implicit.** If the echo check earns its
keep, the heuristic becomes largely redundant - its whole purpose was catching the case the echo catches
deterministically. The byte-count is retained here because it is named in the agreed "Done means", NOT
because it is still load-bearing. **Revisiting that is an owner decision after this ships, not a silent
drop now.**

**The byte-count must never be a gate.** A genuine "no findings" reply is short and correct. It warns; a
human decides. Conversely the token check IS deterministic and may fail the consult.

**The peer's first recommendation was to drop byte-count entirely.** It was rejected because the ROADMAP
entry's own worst case — a lone verdict line, token PRESENT, body ABSENT, exit code 0 — passes a token-only
oracle. Byte-count is the only driver-side signal that sees it.

---

## Verified state of the code this plan edits (checked 2026-08-19, not assumed)

- `clavity-dotnet/src/Clavity.Ls/AskReply.cs:5` — `public sealed record AskReply(string CascadeId, string?
  Answer, IReadOnlyList<ActivityItem> Activity, bool AnswerTruncated, bool ActivityTruncated)`.
- `clavity-dotnet/src/Clavity.Ls/BoundedView.cs:103` — `public static AskReply ProjectAskReply(string
  cascadeId, IReadOnlyList<CascadeStep> delta)`. Sets `AnswerTruncated` when IT caps the answer.
  **Driver-side capping is therefore ALREADY detected; this plan does not rebuild it.**
- `clavity-dotnet/src/Clavity.Ls/AgyView.cs:172` — `public async Task<AskReply> AskAsync(string message,
  TimeSpan? timeout = null, IProgress<AgyWaitProgress>? progress = null, CancellationToken
  cancellationToken = default)`; it calls `BoundedView.ProjectAskReply` at `:209`.
- `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:36` — `public static string ResolveDir(string? envOverride,
  string userProfileDir)`; `CLAVITY_GOLDEN_HEADER` if set, else `%USERPROFILE%\.clavity`. **Reuse this; do
  not invent a second convention.**
- `clavity-dotnet/src/Clavity.Ls/AgyView.cs:19` — `AgyViewOptions.GoldenHeaderDir` is the established
  pattern for an optional directory that tests leave null.
- **Nothing persists a reply to disk.** No `File.` or `Directory.` call exists in `AgyView.cs`.
- All four discipline skills exist in BOTH plugin trees and are **byte-identical today** (verified by diff):
  `clavity-dotnet/plugin/skills/{agy-capstone,agy-test-audit,adversarial-panel-review,agy-first}/SKILL.md`
  and the same four under `clavity-classic/plugin/skills/`.
- Terminal-token grammar, counted per file: `agy-capstone` 17 `[VERDICT` occurrences, `agy-test-audit` 12,
  `agy-first` 10, **`adversarial-panel-review` ZERO** — its terminal signal is `GREEN`
  (`adversarial-panel-review/SKILL.md:208`, "For this skill that means `GREEN`").
- Tests for this assembly live in `clavity-dotnet/tests/Clavity.Ls.Tests/*.cs`; the closest sibling is
  `AskReplyProjectionTests.cs` (`:84` `Over_cap_answer_sets_AnswerTruncated_only`).

---

## File structure

| file | responsibility |
|---|---|
| `src/Clavity.Ls/TerminalToken.cs` (new) | Pure. Does a reply end with the token its discipline mandates? |
| `src/Clavity.Ls/ReplySizeHistory.cs` (new) | Pure. Is this reply anomalously small against recent ones? |
| `src/Clavity.Ls/ReplyArchive.cs` (new) | The only unit that touches disk: persist a reply, append a size row, read recent sizes. |
| `src/Clavity.Ls/AskReply.cs` (modify) | Two additive flags carrying the two verdicts. |
| `src/Clavity.Ls/AgyView.cs` (modify) | Wire the three units at the existing projection seam. |
| `src/Clavity.Mcp/McpTools.cs` (modify) | Optional `expectTerminal` parameter on `agy_ask`. |
| the 4 × 2 `SKILL.md` files (modify) | The two measured-missing rules, mirrored. |

**Three pure units + one IO unit is deliberate.** The spec demands a test proving a TRUNCATED reply is
detected. Purity is what lets that test be deterministic instead of filesystem-dependent.

---

## Preconditions

- [ ] On `main`, tree clean, step 1 merged (`5a7d67b` or later).
- [ ] `docs/superpowers/*` is gitignored — committing this plan needs `git add -f`. `.clavity/` must NEVER
      be force-added.
- [ ] No `--no-verify`, no `git add -A`. Explicit paths only.
- [ ] **This edits implementation source AND a byte-identical skill pair, so it owes ONE re-capstone**
      (Task 6). The sequencing spec budgets for exactly that.

---

## Task 1: `TerminalToken` — the deterministic oracle

**Files:**
- Create: `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs`

- [x] **Step 1: Write the failing tests**

```csharp
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
        Assert.True(TerminalToken.IsSatisfied(reply, "[VERDICT:"));
    }

    [Fact]
    public void Token_present_but_NOT_at_the_end_is_NOT_satisfied()
    {
        // THE CASE THE SPEC NAMES: "a stored reply whose token is missing OR NOT AT THE END is a
        // truncated reply". A reply that quotes the token mid-body and then dies still lost its tail.
        var reply = "I will end with [VERDICT: ALIGNED] once done.\n\nNow the findings:\n- one\n";
        Assert.False(TerminalToken.IsSatisfied(reply, "[VERDICT:"));
    }

    [Fact]
    public void A_LONG_reply_missing_the_token_is_DETECTED()
    {
        // THE FAILING CONTROL THE SPEC DEMANDS. 20 KB of perfectly good review text with no terminal
        // token: this is a model that truncated ITSELF while the transport delivered every byte.
        // It proves detection is STRUCTURAL, not size-based - a byte-count check would pass this.
        var reply = new string('x', 20 * 1024) + "\nlast line with no token\n";
        Assert.False(TerminalToken.IsSatisfied(reply, "[VERDICT:"));
    }

    [Fact]
    public void Null_or_blank_answer_with_an_expectation_is_NOT_satisfied()
    {
        Assert.False(TerminalToken.IsSatisfied(null, "[VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("   \n\n", "[VERDICT:"));
    }

    [Fact]
    public void A_line_that_NEGATES_the_token_is_NOT_satisfied()
    {
        // AGY-AFTER panel finding, verified: a CONTAINS test accepts "Tests are not GREEN" as proof of
        // GREEN - a reply asserting the opposite of completion would pass. This is why the check is
        // STARTS-WITH. Without this row the fix has no oracle.
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nTests are not GREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("done\n\nno [VERDICT: ...] was produced\n", "[VERDICT:"));
    }

    [Fact]
    public void Markdown_emphasis_around_the_token_still_counts_as_compliance()
    {
        // A peer writing **GREEN** is complying. Failing it would train operators to ignore the check.
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\n**GREEN**\n", "GREEN"));
    }

    [Fact]
    public void The_panel_discipline_token_GREEN_works_the_same_way()
    {
        // adversarial-panel-review does NOT use [VERDICT: - it ends on GREEN (SKILL.md:208).
        // A single hardcoded [VERDICT: regex would flag every panel reply as truncated.
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nGREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nopen findings remain\n", "GREEN"));
    }
}
```

- [x] **Step 2: Run and verify they fail**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~TerminalTokenTests`
Expected: FAIL — `error CS0103: The name 'TerminalToken' does not exist`.

- [x] **Step 3: Implement**

```csharp
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
```

- [x] **Step 4: Run and verify they pass**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~TerminalTokenTests`
Expected: `Passed!  - Failed:     0, Passed:     8`. **8, not 6** - the AGY-AFTER panel's fold added
the NEGATES row and the markdown-emphasis row after this line was first drafted. Read the COUNT:
`dotnet test --filter` exits 0 on NO MATCH. (Task 1b's 6 below is correct - it really has 6 rows.)

- [x] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/TerminalToken.cs clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs
git commit -m "feat(ls): TerminalToken - the deterministic half of 13b

A reply whose discipline-mandated terminal token is missing, or present but not
on the last non-blank line, lost its tail. The expectation is per-call because
the four disciplines do not share a grammar - adversarial-panel-review ends on
GREEN, the other three on [VERDICT:.

The 20 KB-without-a-token control is the one the sequencing spec demands: it
proves detection is STRUCTURAL, not size-based."
```

---

## Task 1b: `SemanticEcho` — proof the peer reached the END of the artifact

**Files:**
- Create: `clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/SemanticEchoTests.cs`

- [x] **Step 1: Write the failing tests**

```csharp
using System.Linq;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class SemanticEchoTests
{
    [Fact]
    public void No_expectation_is_always_satisfied()
    {
        // A consult with no primary artifact has nothing to echo. It must not be reported as incomplete.
        Assert.True(SemanticEcho.IsSatisfied("anything", null));
    }

    [Fact]
    public void Echo_within_the_last_three_non_blank_lines_is_satisfied()
    {
        var reply = "findings\n\nECHO: the final line of the file\n\n[VERDICT: ALIGNED]\n";
        Assert.True(SemanticEcho.IsSatisfied(reply, "the final line of the file"));
    }

    [Fact]
    public void Echo_present_but_FAR_from_the_end_is_NOT_satisfied()
    {
        // THE POINT OF THE CHECK. A peer that quotes the line early and then truncates has still lost its
        // tail. Requiring it NEAR THE VERDICT is what makes this evidence of reaching the end.
        var filler = string.Join("\n", Enumerable.Repeat("more analysis", 10));
        var reply = "the final line of the file\n" + filler + "\n[VERDICT: ALIGNED]\n";
        Assert.False(SemanticEcho.IsSatisfied(reply, "the final line of the file"));
    }

    [Fact]
    public void A_reply_that_never_echoes_is_NOT_satisfied()
    {
        // The lone-verdict-line shape: a peer that never read the artifact cannot produce its last line.
        Assert.False(SemanticEcho.IsSatisfied("Review complete.\n\n[VERDICT: ALIGNED]\n", "the final line of the file"));
    }

    [Fact]
    public void Markdown_quoting_around_the_echo_still_counts()
    {
        // A peer wrapping the echo in backticks or a blockquote is complying. Failing it teaches operators
        // to ignore the check, which is how a guard dies.
        Assert.True(SemanticEcho.IsSatisfied("> `the final line of the file`\n\n[VERDICT: ALIGNED]\n",
                                             "the final line of the file"));
    }

    [Fact]
    public void A_blank_or_whitespace_expectation_is_treated_as_NO_expectation()
    {
        // A primary artifact ending in blank lines yields an empty "last line". Demanding an empty echo
        // would fail every reply. Degrade to no-expectation rather than to always-fail.
        Assert.True(SemanticEcho.IsSatisfied("anything\n\n[VERDICT: ALIGNED]\n", "   "));
    }
}
```

- [x] **Step 2: Run and verify they fail**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~SemanticEchoTests`
Expected: FAIL — `error CS0103: The name 'SemanticEcho' does not exist`.

- [x] **Step 3: Implement**

```csharp
using System;
using System.Linq;

namespace Clavity.Ls;

/// <summary>Did the peer reach the END of the artifact it was told to read? The brief requires it to quote,
/// verbatim and near its verdict, the last non-blank line of that artifact; the driver computes the same
/// line from the same file and compares.
///
/// This is the strongest of 13b's three signals because it catches BOTH failure modes with one check. A
/// peer that stopped mid-thought never reached the end and cannot produce the line. A peer that emitted a
/// lone verdict line without doing the work never read the artifact and cannot produce it either - the
/// case a terminal-token oracle passes and only size statistics otherwise hint at.
///
/// LIMITS, stated because a guard whose limits are unstated gets trusted past them: it needs a primary
/// artifact, so a consult on a pasted question has nothing to echo; and a peer that reads only the file's
/// tail defeats it. It raises the floor. It does not prove the work was done.</summary>
public static class SemanticEcho
{
    /// <summary>How close to the end the echo must appear. Three tolerates a verdict line, a blank, and
    /// the echo itself without letting an early quote count.</summary>
    public const int TailLines = 3;

    public static bool IsSatisfied(string? answer, string? expectedEcho)
    {
        // No artifact, or an artifact whose last line is blank: nothing to demand. Degrading to
        // "satisfied" is deliberate - degrading to "failed" would red every such consult forever.
        if (string.IsNullOrWhiteSpace(expectedEcho)) return true;
        if (string.IsNullOrWhiteSpace(answer)) return false;

        var needle = Normalise(expectedEcho);
        if (needle.Length == 0) return true;

        var tail = answer.Split('\n')
                         .Select(Normalise)
                         .Where(l => l.Length > 0)
                         .Reverse()
                         .Take(TailLines);

        return tail.Any(line => line.Contains(needle, StringComparison.Ordinal));
    }

    /// <summary>Strip the decoration a complying peer legitimately adds - backticks, blockquote markers,
    /// emphasis - so formatting never fails an honest echo.</summary>
    private static string Normalise(string line) =>
        line.Trim().Trim('>', '`', '*', '_', ' ', '\t').Trim();
}
```

- [x] **Step 4: Run and verify they pass**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~SemanticEchoTests`
Expected: `Passed!  - Failed:     0, Passed:     8`. **8, not the 6 drafted here** - a mutation audit found the six left `Normalise` unguarded on BOTH sides, so two rows were added.

- [x] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/SemanticEcho.cs clavity-dotnet/tests/Clavity.Ls.Tests/SemanticEchoTests.cs
git commit -m "feat(ls): SemanticEcho - proof the peer reached the artifact's end

Proposed by the AGY-AFTER panel as a disposition neither the roadmap nor the
spec names (verified). It catches BOTH of 13b's problems with one check: a peer
that stopped mid-thought never reached the end, and a peer that emitted a lone
verdict line never read the artifact - so neither can quote its last line.

The echo must appear within the last 3 non-blank lines. An early quote followed
by truncation is exactly what this rejects."
```

---

## Task 1c: `DisciplineContract` — the driver owns the tokens, not the caller

**Files:**
- Create: `clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs`

🔴 **OWNER RULING 2026-08-19: the harness injects the expectations; the caller does not supply token
literals.** The AGY-AFTER panel's objection was blunt and correct: *"a security check that defaults to open
when the guarded entity forgets to turn it on is compliance theater."* An earlier draft of this plan had
every caller passing `expectTerminal: "[VERDICT:"` by hand - so a caller who mistyped it, or omitted it,
silently opted out of the entire check.

⚠ **There is no "harness" component in this architecture, so this task BUILDS the missing piece rather
than pointing at one.** The agent reads a SKILL.md and calls `agy_ask` directly; nothing sits between them.
The closest thing to injection available is: the driver owns the token table, the caller names only its
discipline, and a linter enforces that every skill mandates naming it.

⚠ **AUTO-DETECTION WAS CONSIDERED AND REJECTED BY MEASUREMENT.** Sniffing the payload for a shared marker
would let the driver infer the discipline with no caller cooperation at all. Measured: `agy-capstone`,
`agy-test-audit` and `agy-first` each carry a `REVIEW-ONLY` banner and a `.clavity/seams` path;
**`adversarial-panel-review` carries NEITHER** (0 occurrences of each). A heuristic would silently skip
AGY-AFTER - the same outlier that breaks a single `[VERDICT:` regex. **A guard that covers three of four
disciplines and says nothing about the fourth is worse than one that admits its scope.**

- [x] **Step 1: Write the failing tests**

```csharp
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class DisciplineContractTests
{
    [Theory]
    [InlineData("agy-capstone", "[VERDICT:")]
    [InlineData("agy-test-audit", "[VERDICT:")]
    [InlineData("agy-first", "[VERDICT:")]
    [InlineData("adversarial-panel-review", "GREEN")]
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
```

- [x] **Step 2: Run and verify they fail**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~DisciplineContractTests`
Expected: FAIL — `error CS0103: The name 'DisciplineContract' does not exist`.

- [x] **Step 3: Implement**

```csharp
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
```

Add `using System.Linq;` to the test file for `OrderBy`.

- [x] **Step 4: Run and verify they pass**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~DisciplineContractTests`
Expected: `Passed!  - Failed: 0, Passed: 7`.

- [x] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs
git commit -m "feat(ls): DisciplineContract - the driver owns the terminal tokens

Owner-ruled after the AGY-AFTER panel: the harness injects the expectations, the
caller does not pass token literals. A check the guarded party can silently skip
by mistyping a string is not a check.

Auto-detection was rejected by measurement, not taste: three disciplines carry a
REVIEW-ONLY banner and a seams path, adversarial-panel-review carries neither, so
a payload heuristic would silently skip a quarter of the surface."
```

---

## Task 2: `ReplySizeHistory` — the heuristic warning

**Files:**
- Create: `clavity-dotnet/src/Clavity.Ls/ReplySizeHistory.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/ReplySizeHistoryTests.cs`

- [x] **Step 1: Write the failing tests**

```csharp
using System.Collections.Generic;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class ReplySizeHistoryTests
{
    [Fact]
    public void Too_few_samples_never_warns()
    {
        // With no baseline there is nothing to be anomalous AGAINST. Warning here would fire on every
        // first-ever consult, which trains the operator to ignore the warning - the failure this avoids.
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new[] { 15000, 16000 }, 300));
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new int[0], 300));
    }

    [Fact]
    public void A_tiny_reply_after_large_ones_WARNS()
    {
        // The lone-verdict-line shape: 300 bytes where the last three were ~15 KB.
        Assert.True(ReplySizeHistory.IsAnomalouslySmall(new[] { 15000, 16500, 14000 }, 300));
    }

    [Fact]
    public void A_normal_reply_does_NOT_warn()
    {
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new[] { 15000, 16500, 14000 }, 12000));
    }

    [Fact]
    public void A_uniformly_small_history_does_NOT_warn_on_another_small_reply()
    {
        // A peer that always answers briefly is not truncating. The baseline is that peer's OWN norm,
        // not an absolute floor - an absolute floor would cry wolf on every terse discipline.
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(new[] { 400, 350, 380 }, 300));
    }

    [Fact]
    public void Only_the_most_recent_N_are_used()
    {
        // Ten old 15 KB replies must not keep flagging a peer whose recent norm has legitimately dropped.
        var history = new List<int> { 15000, 15000, 15000, 15000, 15000, 400, 350, 380, 390, 370 };
        Assert.False(ReplySizeHistory.IsAnomalouslySmall(history, 300));
    }
}
```

- [x] **Step 2: Run and verify they fail**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~ReplySizeHistoryTests`
Expected: FAIL — `error CS0103: The name 'ReplySizeHistory' does not exist`.

- [x] **Step 3: Implement**

```csharp
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
```

- [x] **Step 4: Run and verify they pass**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~ReplySizeHistoryTests`
Expected: `Passed!  - Failed:     0, Passed:     6`. **6, not 5** - a median-vs-mean mutant survived the planned five, so a sixth row pins the median.

- [x] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/ReplySizeHistory.cs clavity-dotnet/tests/Clavity.Ls.Tests/ReplySizeHistoryTests.cs
git commit -m "feat(ls): ReplySizeHistory - the heuristic half of 13b

Relative to THIS peer's own recent median, never an absolute floor: a genuine
'no findings' reply is short and correct, so an absolute threshold would cry
wolf and be tuned out. Median over the last 5, minimum 3 samples, flag below
25%. It is a WARNING and must never gate a consult."
```

---

## Task 3: `ReplyArchive` — capture, the only unit that touches disk

**Files:**
- Create: `clavity-dotnet/src/Clavity.Ls/ReplyArchive.cs`
- Test: `clavity-dotnet/tests/Clavity.Ls.Tests/ReplyArchiveTests.cs`

- [x] **Step 1: Write the failing tests**

```csharp
using System;
using System.IO;
using System.Linq;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class ReplyArchiveTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "ra-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    [Fact]
    public void Write_persists_the_answer_and_returns_its_path()
    {
        var path = ReplyArchive.Write(_dir, "conv-1", "the full review text", new DateTime(2026, 8, 19, 10, 30, 0, DateTimeKind.Utc));
        Assert.True(File.Exists(path));
        Assert.Contains("the full review text", File.ReadAllText(path));
    }

    [Fact]
    public void Write_appends_one_size_row_per_reply_and_ReadRecentSizes_returns_them_in_order()
    {
        ReplyArchive.Write(_dir, "c", new string('a', 100), new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc));
        ReplyArchive.Write(_dir, "c", new string('b', 200), new DateTime(2026, 8, 19, 10, 1, 0, DateTimeKind.Utc));
        Assert.Equal(new[] { 100, 200 }, ReplyArchive.ReadRecentSizes(_dir).ToArray());
    }

    [Fact]
    public void ReadRecentSizes_on_a_missing_directory_returns_EMPTY_not_a_throw()
    {
        // A fresh install has no archive. This must be a legitimate empty state, never a crash on the
        // first consult - and never a phantom baseline either.
        Assert.Empty(ReplyArchive.ReadRecentSizes(Path.Combine(_dir, "does-not-exist")));
    }

    [Fact]
    public void A_corrupt_size_row_is_SKIPPED_not_fatal()
    {
        // The archive is observational. A hand-edited or torn row must never take down an ask.
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, ReplyArchive.SizeIndexFileName), "100\nnot-a-number\n250\n");
        Assert.Equal(new[] { 100, 250 }, ReplyArchive.ReadRecentSizes(_dir).ToArray());
    }

    [Fact]
    public void Write_NEVER_throws_when_the_directory_cannot_be_created()
    {
        // Capture is observational: a broken archive must not convert a working ask into a failure.
        // A regular FILE where the directory must go makes creation fail deterministically (ENOTDIR).
        var blocker = Path.Combine(Path.GetTempPath(), "ra-block-" + Guid.NewGuid().ToString("N"));
        File.WriteAllText(blocker, "x");
        try
        {
            var path = ReplyArchive.Write(Path.Combine(blocker, "nested"), "c", "text", DateTime.UtcNow);
            Assert.Null(path);
        }
        finally { File.Delete(blocker); }
    }
}
```

- [x] **Step 2: Run and verify they fail**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~ReplyArchiveTests`
Expected: FAIL — `error CS0103: The name 'ReplyArchive' does not exist`.

- [x] **Step 3: Implement**

```csharp
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace Clavity.Ls;

/// <summary>Persists every reply, so a review that dies on the wire is still on disk. The ROADMAP entry's
/// second measured loss was exactly this: "a reply died on the wire with the review stranded in the peer's
/// console". Today nothing in AgyView writes a reply anywhere.
///
/// EVERY operation is best-effort and swallows its own failures. The archive is OBSERVATIONAL: a broken or
/// unwritable archive must never convert a working ask into a failed one. That is the same rule the
/// progress sink follows in AgyView, and for the same reason.</summary>
public static class ReplyArchive
{
    public const string SizeIndexFileName = "reply-sizes.txt";

    /// <summary>Write one reply. Returns the path written, or null if anything at all went wrong.</summary>
    public static string? Write(string dir, string cascadeId, string? answer, DateTime utcNow)
    {
        try
        {
            Directory.CreateDirectory(dir);
            var safeCascade = Sanitise(cascadeId);
            var name = $"{utcNow:yyyyMMdd-HHmmss}-{safeCascade}.md";
            var path = Path.Combine(dir, name);
            File.WriteAllText(path, answer ?? string.Empty, new UTF8Encoding(false));

            // One row per reply: the byte length of the answer as UTF-8, which is what the peer sent.
            var bytes = answer is null ? 0 : Encoding.UTF8.GetByteCount(answer);
            var index = Path.Combine(dir, SizeIndexFileName);
            File.AppendAllText(index, bytes.ToString(CultureInfo.InvariantCulture) + "\n", new UTF8Encoding(false));

            // PRUNE ON WRITE so the read stays bounded. Only the most recent rows can ever matter -
            // ReplySizeHistory looks at the last Window - and an unpruned index turns every ask into an
            // O(N) read that grows forever. Rewrite only when the file has actually outgrown the cap.
            var rows = File.ReadAllLines(index);
            if (rows.Length > MaxIndexRows)
                File.WriteAllLines(index, rows[^MaxIndexRows..], new UTF8Encoding(false));
            return path;
        }
        catch
        {
            // Deliberately unconditional - see the class remark. There is no logger in this layer.
            return null;
        }
    }

    /// <summary>How many rows the index keeps. Bounded on WRITE so the read is O(1) in repo age.</summary>
    public const int MaxIndexRows = 100;

    /// <summary>Sizes of previously-archived replies, oldest first. Empty when the archive does not exist.
    ///
    /// BOUNDED BY CONSTRUCTION. An AGY-AFTER panel found the first draft read the ENTIRE index on every
    /// ask and parsed every row only for the caller to keep the last five - an O(N) read and parse on a
    /// hot path, growing forever with repo age. The index is now pruned on write, so this read is bounded
    /// by MaxIndexRows rather than by history.</summary>
    public static IReadOnlyList<int> ReadRecentSizes(string dir)
    {
        var sizes = new List<int>();
        try
        {
            var index = Path.Combine(dir, SizeIndexFileName);
            if (!File.Exists(index)) return sizes;
            foreach (var line in File.ReadAllLines(index))
            {
                // A torn or hand-edited row is skipped, never fatal.
                if (int.TryParse(line.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n))
                    sizes.Add(n);
            }
        }
        catch
        {
            // Same rule: an unreadable archive yields no baseline rather than an exception.
        }
        return sizes;
    }

    private static string Sanitise(string value)
    {
        var sb = new StringBuilder(value.Length);
        foreach (var c in value)
            sb.Append(char.IsLetterOrDigit(c) || c == '-' || c == '_' ? c : '-');
        return sb.Length == 0 ? "unknown" : sb.ToString();
    }
}
```

- [x] **Step 4: Run and verify they pass**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter FullyQualifiedName~ReplyArchiveTests`
Expected: `Passed!  - Failed:     0, Passed:     7`. **7, not 5** - deleting the prune block AND deleting `Sanitise` both left the planned five green, so each got a row.

- [x] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/ReplyArchive.cs clavity-dotnet/tests/Clavity.Ls.Tests/ReplyArchiveTests.cs
git commit -m "feat(ls): ReplyArchive - persist every reply, best-effort

The entry's second measured loss was a reply dying on the wire with the review
stranded in the peer's console. Nothing in AgyView wrote a reply anywhere.

Every operation swallows its own failures: the archive is observational and must
never convert a working ask into a failed one - the same rule the progress sink
already follows."
```

---

## Task 4: Wire the three units into `AgyView` and expose the expectation on `agy_ask`

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AskReply.cs:5`
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs:172` (signature) and `:209` (the projection seam)
- Modify: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs` — `AgyAsk`
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`

- [x] **Step 1: Add the two additive flags to `AskReply`**

Replace the record at `AskReply.cs:5-10` with:

```csharp
public sealed record AskReply(
    string CascadeId,
    string? Answer,
    IReadOnlyList<ActivityItem> Activity,
    bool AnswerTruncated,
    bool ActivityTruncated,
    // 13b. Both default to false so every existing construction site and test is unaffected.
    // TerminalTokenMissing is a DETERMINISTIC verdict: the discipline named a token and the reply does
    // not end with it. SizeAnomaly is a HEURISTIC WARNING and must never be treated as proof.
    bool TerminalTokenMissing = false,
    // The peer did not quote the artifact's last line near its verdict: it never reached the end, or
    // never read the artifact at all. Deterministic like TerminalTokenMissing, and strictly stronger -
    // it is the only flag that catches a reply whose token is present but whose body was never written.
    bool EchoMissing = false,
    bool SizeAnomaly = false);
```

- [x] **Step 2: Run the existing suites to prove the additive change breaks nothing**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`
Expected: `Passed!` with the same count as before the change (164 at the time of writing), because both
new members have defaults.

- [x] **Step 3: Extend `AgyView.AskAsync` and wire the seam**

Change the signature at `AgyView.cs:172` to add one optional parameter, keeping every existing caller valid:

```csharp
    public async Task<AskReply> AskAsync(
        string message,
        TimeSpan? timeout = null,
        IProgress<AgyWaitProgress>? progress = null,
        string? expectTerminal = null,
        string? expectEcho = null,
        CancellationToken cancellationToken = default)
```

Replace the `return BoundedView.ProjectAskReply(full.CascadeId, delta);` at `AgyView.cs:209` with:

```csharp
                var projected = BoundedView.ProjectAskReply(full.CascadeId, delta);
                return Evaluate13b(projected, expectTerminal, expectEcho);
```

Add this private method to `AgyView`, directly beneath `AskAsync`:

```csharp
    /// <summary>13b: capture the reply, then judge it two ways - structurally (did it end with the token
    /// its discipline mandates?) and heuristically (is it anomalously small for THIS peer?).
    ///
    /// Both are computed even when the archive is unavailable: the token check needs no history, and a
    /// missing archive simply yields no baseline, so the size warning stays false rather than firing on
    /// an empty one.</summary>
    private AskReply Evaluate13b(AskReply reply, string? expectTerminal, string? expectEcho)
    {
        var tokenMissing = !TerminalToken.IsSatisfied(reply.Answer, expectTerminal);
        var echoMissing = !SemanticEcho.IsSatisfied(reply.Answer, expectEcho);

        var sizeAnomaly = false;
        if (_options.GoldenHeaderDir is { } dir)
        {
            var archive = Path.Combine(dir, "replies");
            var recent = ReplyArchive.ReadRecentSizes(archive);
            var bytes = reply.Answer is null ? 0 : Encoding.UTF8.GetByteCount(reply.Answer);
            sizeAnomaly = ReplySizeHistory.IsAnomalouslySmall(recent, bytes);
            // Archive AFTER measuring, so this reply is never part of its own baseline.
            ReplyArchive.Write(archive, reply.CascadeId, reply.Answer, DateTime.UtcNow);
        }

        return reply with { TerminalTokenMissing = tokenMissing, SizeAnomaly = sizeAnomaly };
    }
```

Add `using System.Text;` and `using System.IO;` to the top of `AgyView.cs` if not already present.

- [x] **Step 4: Expose the expectation on the MCP tool**

In `clavity-dotnet/src/Clavity.Mcp/McpTools.cs`, change the `AgyAsk` signature to add one optional
parameter and pass it through:

```csharp
    public static async Task<CallToolResult> AgyAsk(
        AgyView view, string message, IProgress<ProgressNotificationValue> progress,
        string? discipline = null, string? expectEcho = null,
        CancellationToken cancellationToken = default)
```

and change the `view.AskAsync(...)` call inside it to:

```csharp
        // THE INJECTION POINT. The caller names its discipline; the driver supplies the token. A caller
        // cannot mistype "[VERDICT:" into a silent opt-out, because it never types it.
        var expectTerminal = DisciplineContract.TerminalTokenFor(discipline);
        var json = await RunAsync(() => view.AskAsync(message, progress: relay, expectTerminal: expectTerminal, expectEcho: expectEcho, cancellationToken: cancellationToken));
```

**An OPTIONAL parameter is additive to the generated MCP input schema — this is measured, not assumed.**
The `seam` experiment on 2026-08-19 built the exact proposed signature, registered it through the real
`AddMcpServer().WithTools<T>()` path, and found the optional parameter present in `properties` and ABSENT
from `required`, byte-identical on SDK 1.4.0 (pinned) and 2.2.0. Task 5 re-pins that for this parameter.

- [x] **Step 5: Run the full suites**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests`
Expected: both `Passed!` with zero failures.

- [x] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AskReply.cs clavity-dotnet/src/Clavity.Ls/AgyView.cs clavity-dotnet/src/Clavity.Mcp/McpTools.cs
git commit -m "feat(ls): wire 13b at the projection seam

AskReply gains two additive flags (both default false, so every existing call
site and test is untouched). AgyView archives the reply and computes both
verdicts at the single point where it already projects one.

The reply is archived AFTER it is measured, so it is never part of its own
baseline. The expectation is optional on agy_ask because an optional MCP
parameter is additive to the input schema - measured against the real
registration path on SDK 1.4.0 and 2.2.0."
```

---

## Task 5: Pin the MCP schema and prove the wiring end-to-end

**Files:**
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/McpToolsIntegrationTests.cs`
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`

- [x] **Step 1: Extend the existing schema pin**

`McpToolsIntegrationTests.cs` already has `AgyAsk_input_schema_exposes_only_message_and_stays_backward_compatible`
(at `:219`). Add a sibling that pins the NEW parameter's optionality:

```csharp
    [Fact]
    public void AgyAsk_expectTerminal_is_OPTIONAL_in_the_generated_schema()
    {
        // 13b adds a parameter. If it landed in `required`, every existing agy_ask caller breaks - and it
        // would break silently at the protocol layer, not in any C# test. Pin optionality, not presence.
        var tool = McpServerTool.Create(typeof(McpTools).GetMethod(nameof(McpTools.AgyAsk))!);
        using var doc = JsonDocument.Parse(tool.ProtocolTool.InputSchema.GetRawText());
        var required = doc.RootElement.GetProperty("required").EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.Equal(new[] { "message" }, required);
        Assert.True(doc.RootElement.GetProperty("properties").TryGetProperty("expectTerminal", out _));
    }
```

- [x] **Step 2: Add the end-to-end control — a reply WITHOUT the token is flagged**

Add to `AgyAskIntegrationTests.cs`:

```csharp
    [Fact]
    public async Task AskAsync_flags_TerminalTokenMissing_when_the_discipline_named_a_token_and_the_reply_lacks_it()
    {
        // The end-to-end half of the spec's demand. The unit test proves the oracle; this proves the WIRING
        // - that AskAsync actually consults it and surfaces the verdict on the reply.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a full review with no terminal token", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("review it", expectTerminal: "[VERDICT:");
            Assert.True(reply.TerminalTokenMissing);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_does_NOT_flag_when_the_reply_ends_with_the_expected_token()
    {
        // The passing control. Without it the row above is satisfied by a check that flags EVERYTHING.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "findings here\n\n[VERDICT: ALIGNED]", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("review it", expectTerminal: "[VERDICT:");
            Assert.False(reply.TerminalTokenMissing);
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AskAsync_with_NO_expectation_never_flags()
    {
        // Every non-discipline ask goes through this path. If it flagged, agy_ask would report truncation
        // on ordinary questions forever.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "just an answer", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var reply = await view.AskAsync("hello");
            Assert.False(reply.TerminalTokenMissing);
        }
        finally { Directory.Delete(dir, true); }
    }
```

- [x] **Step 3: Run**

Run: `cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests`
Expected: `Passed!  - Failed: 0` with 4 more tests than before.

- [x] **Step 4: Prove the new checks are NON-VACUOUS with logic mutants**

Run each mutant, confirm the NAMED test goes red, then restore. A mutant that reds nothing means the test
is decorative.

| # | mutation | file | expected red |
|---|---|---|---|
| M1 | `if (string.IsNullOrWhiteSpace(expected)) return true;` → `return true;` (always satisfied) | `TerminalToken.cs` | `AskAsync_flags_TerminalTokenMissing...` + `A_LONG_reply_missing_the_token_is_DETECTED` |
| M2 | `return line.Contains(expected, ...)` → `return answer.Contains(expected, ...)` (anywhere, not at the end) | `TerminalToken.cs` | `Token_present_but_NOT_at_the_end_is_NOT_satisfied` |
| M3 | `recentSizes.Count < MinimumSamples` → `recentSizes.Count < 0` (no minimum) | `ReplySizeHistory.cs` | `Too_few_samples_never_warns` |
| M4 | `currentSize < median * Fraction` → `currentSize < median` | `ReplySizeHistory.cs` | `A_normal_reply_does_NOT_warn` |
| M5 | delete the `ReplyArchive.Write(...)` call in `Evaluate13b` | `AgyView.cs` | `Write_appends_one_size_row...` stays green (unit-level) — **this mutant SHOULD survive the integration suite; record it as a known gap rather than pretending otherwise** |

**M5 is listed BECAUSE it survives.** Nothing asserts that `AgyView` actually archives, only that
`ReplyArchive` can. Either add an integration row asserting a file appears under the resolved dir, or
record it as an accepted boundary in `docs/coverage-debt.md`. **Do not leave it undocumented.**

- [x] **Step 5: Commit**

```bash
git add clavity-dotnet/tests/Clavity.Integration.Tests/McpToolsIntegrationTests.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "test(13b): end-to-end wiring + schema optionality, with mutants

Four mutants caught by their specific intended test. M5 (deleting the archive
call) SURVIVES: nothing asserts AgyView archives, only that ReplyArchive can.
Recorded rather than hidden - see the plan's Task 5 Step 4."
```

---

## Task 5b: SURFACE the two verdicts — without this the whole plan is inert

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs` — `AgyAsk`
- Test: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`

🔴 **THIS TASK EXISTS BECAUSE THE PLAN WITHOUT IT SATISFIES THE SPEC AND CHANGES NOTHING.** Found by
this plan's own solo panel: `TerminalTokenMissing` and `SizeAnomaly` were computed, carried on `AskReply`,
and read by NOTHING. Capture existed, the byte-count existed, a test proved detection - and a truncated
review would still have been folded, because no caller ever saw the verdict. **A detector with no consumer
is not a detector.**

- [x] **Step 1: Append a warning block to the tool result when either flag is set**

In `McpTools.AgyAsk`, after `var guidance = view.TryTakeGuidanceBlock();`, add:

```csharp
        // 13b: the verdicts must REACH the caller. A flag nothing reads cannot stop a truncated review
        // being folded, which is the entire failure this step exists to end.
        var reply13b = view.LastReply;   // set by AskAsync; see Task 4
        if (reply13b is { TerminalTokenMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] TRUNCATED REPLY: the terminal token this discipline requires is missing or "
                     + "not at the end. Treat this consult as INCOMPLETE - do not fold findings from it. "
                     + "Recover with agy_look or re-ask; never read it as 'no findings'."
            });
        }
        else if (reply13b is { EchoMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] ECHO MISSING: the peer did not quote the artifact's last line near its "
                     + "verdict, so it did not reach the end of what it was asked to read - or did not "
                     + "read it. Treat this consult as INCOMPLETE and do not fold findings from it."
            });
        }
        else if (reply13b is { SizeAnomaly: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] SIZE WARNING: this reply is far smaller than this peer's recent replies. "
                     + "That is a HEURISTIC, not proof - a genuine 'no findings' is legitimately short. "
                     + "Confirm the reply is complete before folding or accepting a clean verdict."
            });
        }

        // OMISSION MUST BE LOUD. Without this block a caller that names no discipline gets a completely
        // normal-looking result with no checks run - which is the compliance-theater failure in a
        // different costume: not a check that can be turned off, but one that was never turned on and
        // said nothing about it. This does NOT block the consult; it makes the gap visible.
        if (DisciplineContract.TerminalTokenFor(discipline) is null)
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] UNCHECKED: no known discipline was named on this ask, so the completeness "
                     + "checks did NOT run. If this is a discipline consult, re-issue it with "
                     + "discipline set to one of: " + string.Join(", ", DisciplineContract.KnownDisciplines)
                     + ". If it is an ordinary question, this notice is expected."
            });
        }
```

**The two are `if`/`else if`, not two independent blocks.** A truncated reply is usually also a small one,
and emitting both would make the deterministic verdict compete with the heuristic for the reader's
attention. The deterministic one wins.

- [x] **Step 2: Add `LastReply` to `AgyView`**

In `AgyView`, add beside the other state:

```csharp
    /// <summary>The most recent reply this view produced, so the MCP layer can surface its 13b verdicts.
    /// Not thread-safe by design: one AgyView drives one conversation, serially.</summary>
    public AskReply? LastReply { get; private set; }
```

and in `Evaluate13b`, replace `return reply with { ... };` with:

```csharp
        var evaluated = reply with
        {
            TerminalTokenMissing = tokenMissing,
            EchoMissing = echoMissing,
            SizeAnomaly = sizeAnomaly,
        };
        LastReply = evaluated;
        return evaluated;
```

- [x] **Step 3: Test that the warning actually reaches the caller**

```csharp
    [Fact]
    public async Task AgyAsk_appends_a_TRUNCATED_block_when_the_terminal_token_is_missing()
    {
        // Without this the detector is inert: the flag is set and no caller ever sees it.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "a review with no token", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var result = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(), discipline: "agy-capstone");
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains(texts, t => t.Contains("[13b] TRUNCATED REPLY"));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task AgyAsk_appends_NO_13b_block_when_the_reply_is_complete()
    {
        // The passing control. Without it, a check that appends the warning ALWAYS satisfies the row above.
        var plan = new[] { new FakeAskLs.WaitStep(AppendSteps: 0, GoesIdle: true) };
        var fake = new FakeAskLs("conv-1", "findings\n\n[VERDICT: ALIGNED]", TimeSpan.Zero,
                                 Array.Empty<CascadeStep>(), waitPlan: plan);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var result = await McpTools.AgyAsk(view, "review it",
                new CollectingProgress<ProgressNotificationValue>(), discipline: "agy-capstone");
            var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.DoesNotContain(texts, t => t.Contains("[13b]"));
        }
        finally { Directory.Delete(dir, true); }
    }
```

- [x] **Step 4: Commit**

```bash
git add clavity-dotnet/src/Clavity.Mcp/McpTools.cs clavity-dotnet/src/Clavity.Ls/AgyView.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(mcp): surface the 13b verdicts to the caller

Found by this plan's own solo panel: both flags were computed and read by
NOTHING. The plan satisfied the spec's Done-means while a truncated review would
still have been folded. A detector with no consumer is not a detector."
```

---

## Task 6: The two measured discipline gaps — all four skills, BOTH plugin trees

**Files (eight, and they are a byte-identical pair — every edit must be mirrored):**
- `clavity-dotnet/plugin/skills/{agy-capstone,agy-test-audit,adversarial-panel-review,agy-first}/SKILL.md`
- `clavity-classic/plugin/skills/{agy-capstone,agy-test-audit,adversarial-panel-review,agy-first}/SKILL.md`

**The two gaps, measured 2026-08-19 by direct grep (not by a counter — two counters misfired that day, and
the first version of the table below was wrong; see the correction under it):**

| discipline | MANDATES open questions | says a clean round is a coverage claim |
|---|---|---|
| AGY-FIRST (`agy-first`) | **NO** - no open-question language at all | **NO** |
| AGY-AFTER (`adversarial-panel-review`) | **NO** - `:68-73` rules how to FRAME one neutrally, assuming one exists; never requires it | **NO** |
| AGY-CAPSTONE (`agy-capstone`) | **NO** - `:255` is NEGOTIATION language, not a question mandate | **NO** |
| AGY-TEST-AUDIT (`agy-test-audit`) | **NO** | **NO** |

🔴 **CORRECTED 2026-08-19 after an owner challenge.** An earlier draft of this table credited three
disciplines with asking open questions. **That was wrong** - the grep behind it matched *disagreement* and
*negotiation* wording, not a requirement to ASK anything. **None of the four mandates an open question.**
Every open question in that day's consults was the driver's own practice, unshipped, and would vanish with
the operator. The gap is four-wide, not one-wide.

- [x] **Step 1: Add the coverage-claim rule to all four**

Insert this paragraph into each of the four skills, immediately before its stop-condition / verdict section:

```markdown
**A CLEAN ROUND IS A COVERAGE CLAIM, NOT A RESULT.** Before accepting one, ask what was NOT examined -
which files went unread, which behaviours were never exercised, which lens was not applied. A round that
finds nothing has told you about its own coverage, not about the artifact. Measured 2026-08-19: of two
clean rounds in one session, both later proved to have missed a real defect that hand-enumeration found.
```

- [x] **Step 2: Add the open-question requirement to ALL FOUR disciplines**

**Three to four questions per payload, not one.** The evidence is directional and one-sided: on 2026-08-19
every payload carrying FOUR open questions produced a genuine surprise (a design split neither party had
seen; a signal-choice pivot that changed what got built; a third disposition; an honest "I cannot explain
this"), while payloads carrying ONE produced clean rounds that later proved wrong. One question lets the
peer pick the easy one and stop.

**The four shapes below are not a style guide - each earned its place by producing a finding that day.**
Insert this block into the consult section of EACH of the four skills:

```markdown
**Every payload MUST carry THREE to FOUR OPEN QUESTIONS the peer answers in its own words** - never a
checkbox, never a yes/no, and never a question whose expected answer is stated in the payload. One
question is not enough: it lets the peer answer the easiest and stop. Draw them from these four shapes,
each of which produced a real finding on 2026-08-19:

1. **Disagree with my guess.** State where YOU think the weakness is, then ask the peer where IT thinks
   it is and to say plainly if you are wrong. (Produced an 8-row case matrix, and a correction that a
   proposed fix would have destroyed the property it was fixing.)
2. **A disposition I have not named.** "Is there an option neither this artifact nor I have named?" A fork
   stated as N options is often really N+1. (Produced a third disposition that dissolved a ruling.)
3. **Reject the frame.** "Is the signal / metric / approach I have chosen even the right one?" (Produced
   the largest single design change of that session - the chosen signal was wrong and the peer said so.)
4. **Permit ignorance explicitly.** "If you cannot explain this, say so plainly rather than constructing a
   story." (Produced an honest known-unknown instead of a confident fabrication - the peer had already
   fabricated once that day.)

**A payload whose questions all have knowable answers is not asking anything.** If you can predict every
answer, you are seeking agreement, not review.
```

- [x] **Step 2b: Make the briefs ASK for the echo — WITHOUT THIS THE CHECK FAILS EVERY CONSULT**

🔴 **This step is not optional garnish; omitting it breaks every review.** The driver computes the
expected echo and compares. If the brief never told the peer to produce one, NO reply can satisfy it and
every consult reds - a fail-CLOSED guard on the hot path of every discipline. **The demand and the check
must ship in the same commit.**

Insert into the payload-construction section of EACH of the four skills:

```markdown
**Every payload that names a PRIMARY ARTIFACT must demand a SEMANTIC ECHO.** Add, as the second-to-last
instruction:

> Immediately before your terminal verdict, quote verbatim the LAST NON-BLANK LINE of
> `<the primary artifact path>`. Quote it exactly; do not paraphrase or summarise it.

Then pass that same line to the ask as `expectEcho`, having read it yourself from the same file. The
driver compares them and reports `[13b] ECHO MISSING` when they disagree.

**Why this and not a nonce.** A nonce you invent proves only that the peer read your BRIEF. The
artifact's last line proves it reached the END of the thing under review - which is exactly what a
truncated or unread review cannot do.

**When there is no primary artifact** - a design question, a pasted fork with no file - omit the demand
and pass no `expectEcho`. The check degrades to satisfied rather than to failed, deliberately: a guard
that reds on consults it was never meant to cover gets disabled, and then it covers nothing.
```

- [x] **Step 2c: Enrol ALL FOUR in the skill linter and assert each mandates naming itself**

🔴 **`adversarial-panel-review` is currently NOT ENROLLED in the linter at all.** Measured:
`scripts/check-agy-discipline-skills.ps1:13` reads `$skills = @('agy-first', 'agy-capstone',
'agy-test-audit')`, and its own comment at `:20` records that adversarial-panel-review "DOES carry the
taxonomy but is not enrolled in `$skills` at all". So AGY-AFTER is the outlier on THREE counts now - no
`[VERDICT:` token, no `REVIEW-ONLY` banner, and no linter coverage. **Fix the enrolment as part of this
step; a mandate no linter checks for one discipline is the honour system this task exists to replace.**

Change `:13` to:

```powershell
$skills = @('agy-first', 'agy-capstone', 'agy-test-audit', 'adversarial-panel-review')
```

Then add a check asserting each enrolled skill instructs the caller to name itself on the ask:

```powershell
# 13b: the completeness checks only run when the ask names its discipline. If a skill does not TELL the
# caller to name it, every consult from that discipline silently runs unchecked - and the driver's
# [13b] UNCHECKED notice is the only thing that would ever say so.
foreach ($skill in $skills) {
    $path = Join-Path $repoRoot "clavity-dotnet/plugin/skills/$skill/SKILL.md"
    $text = Get-Content -Raw -LiteralPath $path
    if ($text -notmatch [regex]::Escape("discipline: `"$skill`"")) {
        Fail "$skill does not instruct the caller to pass discipline: `"$skill`" - its consults will run UNCHECKED"
    }
}
```

**Run it and prove it can fail** — delete the mandate line from one skill, confirm the linter reds and
names that skill, then restore. A linter that has never been seen to fail is not known to work.

- [x] **Step 3: Mirror to `clavity-classic` and prove byte-identity**

```bash
for f in agy-capstone agy-test-audit adversarial-panel-review agy-first; do
  cp "clavity-dotnet/plugin/skills/$f/SKILL.md" "clavity-classic/plugin/skills/$f/SKILL.md"
done
for f in agy-capstone agy-test-audit adversarial-panel-review agy-first; do
  diff <(tr -d '\r' < "clavity-dotnet/plugin/skills/$f/SKILL.md") \
       <(tr -d '\r' < "clavity-classic/plugin/skills/$f/SKILL.md") >/dev/null \
    && echo "  IDENTICAL $f" || echo "  DIFFER $f"
done
```

Expected: four `IDENTICAL` lines.

- [x] **Step 4: Run the pair gates**

```bash
bash scripts/check-seed-artifacts-synced.sh
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1
```

Expected: `seed agent artifacts in sync (dotnet == classic)`, and the discipline-skill linter passing.
**Read each exit code without a pipe** — `$?` after `| tail` is the pipe's status, not the script's.

- [x] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/skills clavity-classic/plugin/skills
git commit -m "docs(disciplines): a clean round is a coverage claim; all four mandate 3-4 open questions

Two gaps measured by direct grep across the four AGY-* disciplines, and BOTH are
four-wide. The coverage-claim rule was in none of them. And none MANDATED an open
question - an earlier count credited three of them, but that grep had matched
negotiation wording, not a requirement to ask anything. Every open question in
that day's consults was unshipped driver practice.

Three to four questions, not one: payloads carrying four produced every genuine
surprise that day; payloads carrying one produced clean rounds that were wrong.

Folded into step 2 rather than tracked separately because it is the same
byte-identical pair and therefore the same re-capstone."
```

---

## Task 7: AGY-CAPSTONE over the whole range

- [ ] **Step 1** Run the `clavity:agy-capstone` skill over `<step-2-base>..HEAD`, resolving the base from
      this plan's first commit. This edits implementation source, so the discipline is mandatory, and the
      sequencing spec already budgets exactly one re-review for this step.
- [ ] **Step 2** Fold verified findings, commit each, and RE-EXTEND the range over the fold commits before
      the next round — a fix is unreviewed code.
- [ ] **Step 3** On owner-confirmed GREEN, write `.clavity/agy-marks/agy-capstone.head` with the REVIEWED
      sha (not ambient HEAD) and add the row to `docs/agy-capstone-ledger.md`.

---

## Self-review

**1. Spec coverage.** The sequencing spec's "Done means" requires (a) driver-side capture — Task 3 + Task 4;
(b) a byte-count against that peer's recent replies — Task 2 + Task 4; (c) **a test proving a TRUNCATED
reply is DETECTED, not merely that an intact one passes** — Task 1 Step 1's
`A_LONG_reply_missing_the_token_is_DETECTED` (20 KB, structurally incomplete) and Task 5 Step 2's
end-to-end flag row, both with passing controls beside them. The owner's added scope is Task 6.

**2. Placeholder scan.** No TBD, no "handle errors appropriately", no "similar to Task N". Every code step
carries complete code. The one deliberate omission is the `<step-2-base>` sha in Task 7, which cannot exist
before Task 1 is committed; the step says how to resolve it.

**3. Type consistency.** 🔴 **One defect was found here AFTER the plan was first committed and is recorded rather than quietly fixed:** Task 5b's two MCP-layer tests still called `McpTools.AgyAsk(..., expectTerminal: "[VERDICT:")` after the owner ruling changed that surface to take `discipline`. They would not have compiled. The two `view.AskAsync(..., expectTerminal:)` call sites are CORRECT and deliberately unchanged - `AskAsync` keeps the literal internally; only the MCP surface names a discipline. **A signature change is not done when the signature changes; it is done when every caller moves.**

 `TerminalToken.IsSatisfied(string?, string?)`, `ReplySizeHistory
.IsAnomalouslySmall(IReadOnlyCollection<int>, int)`, `ReplyArchive.Write(string, string, string?,
DateTime)` and `ReplyArchive.ReadRecentSizes(string)` are used with those exact signatures in Tasks 4 and 5.
`AskReply`'s new members are named `TerminalTokenMissing` and `SizeAnomaly` throughout.

**4. Known gaps, stated rather than hidden.**
- **M5 survives:** nothing asserts `AgyView` archives, only that `ReplyArchive` can. Task 5 Step 4 requires
  either an added integration row or a recorded accepted boundary — not silence.
- **The size warning is not surfaced to the operator anywhere yet.** `SizeAnomaly` is computed and carried
  on the reply; no discipline reads it. That is deliberate for this step and belongs to whichever step
  teaches the skills to consume it — but it means shipping this alone leaves the heuristic half INERT.
  **Flag to the owner rather than assume.**
- **The peer's scratchpad remedy is NOT in this plan.** The owner ruled it be measured first; it is neither
  adopted nor discarded here.
