# §29a - the panel's terminal token - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax
> for tracking.

**Goal:** Make a findings-bearing `adversarial-panel-review` round satisfy the 13b completeness check,
instead of being flagged every time with a message telling the driver to discard its findings.

**Architecture:** Two driver-side changes. (1) The discipline's expected terminal token moves from `GREEN`
to `PANEL VERDICT`, the line the panel skill already mandates. (2) The matcher **normalises the EXPECTED
token exactly as it normalises the line**, so decoration - now including `[` - is stripped from both sides
before comparison. `StartsWith` stays; `DisciplineContract`'s three `[VERDICT:` values are UNCHANGED.
No `SKILL.md` edit, so no byte-identical pair, no plugin reinstall.

⚠ **AMENDED 2026-09-03 by owner ruling during AGY-AFTER round 1.** The plan was a one-value change; the
panel found a reachable false-flag (below) and the owner ruled the fix lands here rather than being
deferred. **It is still driver-only, which is what made §29a a legitimate BOUNDED prerequisite.**

**Tech Stack:** C# (`Clavity.Ls`), xUnit (`Clavity.Ls.Tests`).

---

## Why this shape, and what the owner ruled

**Owner ruling 2026-09-03** on an AGY-FIRST consult (`.clavity/seams/agyfirst-s29a-terminal-contract.md`):
**Option 4 - swap the token to `PANEL VERDICT`.**

The panel skill mandates that line already: `adversarial-panel-review/SKILL.md:47` -
*"one, with a single-line PANEL VERDICT summarizing the round's outcome."* And `SKILL.md:120-122` says
**the driver owns the terminal-token table** and the caller *"supplies NAMES only"*. So the driver's table
is simply wrong about a convention the skill already states; nothing in the skill needs to change.

**Rejected, and why, so they are not re-litigated:**

- **A multi-token set** (accept `PANEL VERDICT`, `GREEN` and `[VERDICT:`). The peer killed it with a
  counter-example I verified: `"GREEN is not the appropriate status because..."` satisfies
  `StartsWith("GREEN")`, so keeping `GREEN` re-admits the negation hazard the `StartsWith` comment exists
  to prevent.
- **Unifying the grammar to `[VERDICT:`** (the only genuinely non-negatable prefix). Correct but class 2:
  it edits a byte-identical `SKILL.md` pair and needs a plugin reinstall before it takes effect.

⚠ **MEASURED, and NOT claimed as a benefit of this change:** `PANEL VERDICT` is *also* negatable -
`"PANEL VERDICT is not the..."` satisfies `StartsWith("PANEL VERDICT")`. This change is **neutral** on
truncation safety, not positive. Today's `GREEN` carries the identical hazard, so nothing regresses - but
do not record this as hardening. The only fix for that class is the rejected `[VERDICT:` option.

---

## VERIFIED STATE - every anchor read at `fbfa1e3` before this plan was written

| claim | verified how |
|---|---|
| the token lives at `DisciplineContract.cs:25` | read: `["adversarial-panel-review"] = "GREEN",` |
| a test PINS the defect at `TerminalTokenTests.cs:73` | read: `Assert.False(... "panel ran\n\nopen findings remain\n", "GREEN")` |
| the stale `SKILL.md:208` citation appears in **FOUR** places | `DisciplineContract.cs:16`, `TerminalToken.cs:14-15`, `DisciplineContractTests.cs:18`, `TerminalTokenTests.cs:70` |
| `SKILL.md:208` no longer says what all four claim | read: it is now about seat rotation |
| the skill has **ZERO** `[VERDICT` occurrences | `grep -n "VERDICT"` -> `:3`, `:47`, `:288`, `:370`, none of them `[VERDICT` |
| `PANEL VERDICT` occurs exactly TWICE | `:3` (frontmatter) and `:47` (the mandate) |
| the integration test needs NO change | `AgyAskIntegrationTests.cs:1761` asserts only that the discipline is NAMED in an `[13b] UNCHECKED` notice - token-agnostic |
| test command | `clavity-dotnet/CLAUDE.md:21` - `dotnet test tests/Clavity.Ls.Tests` |

---

## File Structure

| file | responsibility | status |
|---|---|---|
| `clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs` | the token table - the ONE place these literals live | MODIFY (value + doc comment) |
| `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs` | the matcher; **LOGIC CHANGES** - decoration set + normalise the expected token | MODIFY (Task 3) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs` | pins the table | MODIFY (InlineData + comment) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs` | pins the matcher against the panel shape | MODIFY (the assertion that encodes the defect) |

**Blast radius: driver-only.** No plugin payload, no byte-identical pair, no `0c-local` reinstall. That
is why §29a is a BOUNDED Phase 0d prerequisite.

---

## Task 1: Flip the test that pins the defect (TDD - test first)

**Files:**
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs:67-74`

- [ ] **Step 1: Replace the test with one that encodes the CORRECT contract**

The current test asserts a findings-bearing reply must FAIL. That is the defect, written down as an
assertion. Replace the whole `[Fact]` block with:

🔴 **THE TOKEN MUST BE READ FROM THE CONTRACT, NEVER RETYPED AS A LITERAL.** This is the whole reason
the test can go red. **PANEL R1 MEASURED both ways:** a version using `const string tok = "PANEL VERDICT"`
returned `Failed: 0, Passed: 1` against the UNCHANGED contract - a vacuous RED arm that would have halted
the plan on its own `STATE_MISMATCH` guard. The contract-reading version below returned **FAIL** against
the unchanged contract and is therefore a genuine oracle.

```csharp
    [Fact]
    public void The_panel_token_comes_from_the_contract_and_accepts_a_findings_bearing_round()
    {
        // adversarial-panel-review does NOT use [VERDICT: - it closes each ROUND on a single-line
        // PANEL VERDICT (its SKILL.md, "Step 1 - Solo panel"). The token was GREEN until 2026-09-03,
        // which flagged EVERY findings-bearing round: the skill's Outputs section declares FOUR
        // legitimate dispositions and only one of them is GREEN, so a round that found something was
        // told it was incomplete and its findings should be discarded. Measured TWICE - most recently
        // by this plan's own AGY-AFTER panel, whose reply carried three claimed blocking defects and
        // was flagged "do not fold findings from it".
        //
        // NOTE the two objects, or a later reader will "reconcile" them and revert this: GREEN is
        // still the RUN-level disposition (SKILL.md "Outputs", and its Completeness gate - "For this
        // skill that means GREEN"). PANEL VERDICT is the PER-ROUND closing line, and a peer's reply IS
        // a round. This table checks the reply, so it takes the round-level token.
        //
        // READ FROM THE TABLE. A literal here would pass before the table changed and prove nothing.
        var tok = DisciplineContract.TerminalTokenFor("adversarial-panel-review");
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nPANEL VERDICT: 2 open findings remain\n", tok));

        // Decoration at the ENDS is compliance, not failure - a distinct branch (TrimStart).
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\n**PANEL VERDICT: GREEN**\n", tok));

        // Still rejects a reply that never reached a verdict line at all.
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nopen findings remain\n", tok));

    }
```

⚠ **The bracket case belongs to Task 3, not here.** Do not add a `[PANEL VERDICT: ...]` row in this task:
it would assert the CURRENT (wrong) behaviour and then have to be inverted two tasks later.

⚠ **THREE SUFFIX VARIANTS WERE DELIBERATELY REMOVED.** `PANEL VERDICT: GREEN`, `: cap-reached` and
`: 2 open findings` all hit the identical `StartsWith` branch - the suffix is never examined - so they
cannot fail independently and only *look* like disposition coverage. The assertions kept are the three
genuinely distinct branches (plain prefix, decoration-stripped prefix, negative) plus the characterization
row. The old name, `..._accepts_every_disposition_its_skill_declares`, also over-claimed: the skill
declares FOUR dispositions and the test never exercised `agy-required-but-unreachable`.

- [ ] **Step 2: Run it and watch it FAIL**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~The_panel_token_comes_from_the_contract"
```
Expected: **1 failed** - `TerminalTokenFor` still returns `GREEN`, so the first assertion fails.
**If this test PASSES at this step, STOP** - the token is being read as a literal instead of from the
table, and Task 2 would prove nothing. Report `STATE_MISMATCH: the panel token test passes before the
contract changed`.

⚠ **`dotnet test --filter` EXITS 0 ON NO MATCH.** Read the COUNT, never the exit code alone.

---

## Task 2: Change the token, and every comment that asserts the old one

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs:16,25`
- Modify: `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs:14-15`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs:13,17-18`

- [ ] **Step 1: The token itself**

`DisciplineContract.cs:25`, change:
```csharp
            ["adversarial-panel-review"] = "GREEN",
```
to:
```csharp
            ["adversarial-panel-review"] = "PANEL VERDICT",
```

- [ ] **Step 2: The doc comment on the same file**

`DisciplineContract.cs:16`, change:
```csharp
/// adversarial-panel-review ends on GREEN (its SKILL.md:208), the other three on [VERDICT:.</summary>
```
to:
```csharp
/// adversarial-panel-review closes each round on a single-line PANEL VERDICT (its SKILL.md, section
/// "Step 1 - Solo panel"); the other three end on [VERDICT:. Cited by SECTION, not line: this comment
/// said ":208" until 2026-09-03 and that line had long since become something else.</summary>
```

- [ ] **Step 3: The same stale citation in the matcher's doc comment**

`TerminalToken.cs:14-15`, change:
```csharp
/// agy-test-audit and agy-first end on "[VERDICT:", while adversarial-panel-review ends on "GREEN"
/// (adversarial-panel-review/SKILL.md:208). A single hardcoded pattern would flag every panel reply.</summary>
```
to:
```csharp
/// agy-test-audit and agy-first end on "[VERDICT:", while adversarial-panel-review closes on a
/// single-line "PANEL VERDICT" (its SKILL.md, section "Step 1 - Solo panel"). A single hardcoded
/// pattern would flag every panel reply.</summary>
```

- [ ] **Step 4: The test's InlineData and its comment**

`DisciplineContractTests.cs:13`, change `[InlineData("adversarial-panel-review", "GREEN")]` to
`[InlineData("adversarial-panel-review", "PANEL VERDICT")]`.

Then `:17-18`, change:
```csharp
        // [VERDICT: (17, 12 and 10 occurrences); adversarial-panel-review uses GREEN and has ZERO
        // [VERDICT occurrences - SKILL.md:208, "For this skill that means GREEN".
```
to:
```csharp
        // [VERDICT: (17, 12 and 10 occurrences - re-measured 2026-09-03, still exact);
        // adversarial-panel-review has ZERO [VERDICT occurrences and closes each ROUND on a
        // single-line PANEL VERDICT, which its SKILL.md mandates in "Step 1 - Solo panel".
        // GREEN is NOT gone from that skill and this table does not contradict it: GREEN remains
        // the RUN-level disposition ("Outputs", and the Completeness gate - "For this skill that
        // means GREEN"), while this table checks a PEER'S REPLY, which is one ROUND.
        // Re-measure the counts before trusting them.
```

- [ ] **Step 5: Run the two suites and watch them PASS**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
```
Expected: **0 failed**, and **`Total: 208`** - MEASURED at `42cfa84` before this plan was executed, so
the number is an oracle rather than "the same as before". Task 1 REPLACES a test rather than adding one,
so the total must not move. **A different total means a test was added or lost - stop and find out which.**

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs clavity-dotnet/src/Clavity.Ls/TerminalToken.cs clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs
git commit -m "fix(s29a): the panel's terminal token is PANEL VERDICT, not GREEN"
```

---

## Task 3: Fix the bracket false-flag - normalise BOTH sides

**Owner-ruled during AGY-AFTER round 1: fold a correct fix in, do not defer it.**

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs` (add rows)

**The defect.** A peer writing `[PANEL VERDICT: GREEN]` is falsely flagged as truncated: `[` is not in the
strip set, so `StartsWith("PANEL VERDICT")` fails on a complete reply. Three of the four disciplines use a
token that BEGINS with `[`, so bracketing is the habit this convention trains.

🔴 **TWO WRONG FIXES, BOTH RULED OUT BY MEASUREMENT. Do not re-litigate them:**

1. **Add `[` to the strip set and stop there.** It strips the `[` the other three tokens BEGIN with, so
   `[VERDICT: ALIGNED]` becomes `VERDICT: ALIGNED]` and fails `StartsWith("[VERDICT:")`.
   `TerminalTokenTests.cs:20-21` pins that case and goes red.
2. **Subtract the expected token's first character from the strip set** (`Decoration.Where(c => c != expected[0])`).
   MEASURED: full suite passed and the bracket case was fixed - **but the live peer produced a
   counter-example that breaks it**, `[**VERDICT: ALIGNED**]` with expected `[VERDICT:`. Protecting `[`
   makes `TrimStart` halt on the first `[`, so decoration NESTED INSIDE the bracket is never stripped.
   **MEASURED as `TEMP_G`: it fails.**

**THE FIX: normalise the EXPECTED token exactly as the line is normalised.** Decoration is stripped from
both sides, so no character needs protecting and nesting works in either order. `DisciplineContract`'s
three `[VERDICT:` values are **UNCHANGED** - a fourth candidate (retokenising them to `VERDICT:`) was
rejected because it reaches into three working disciplines and into
`AgyAskIntegrationTests.cs:1456,1474`, a second test project this plan otherwise does not touch.

- [ ] **Step 1: Add the rows that must go RED**

Append inside `TerminalTokenTests.cs`:

```csharp
    [Fact]
    public void A_bracket_wrapped_verdict_is_compliance_not_truncation()
    {
        // Three of four disciplines use a token starting with '[', so peers bracket by habit. A complete
        // reply must not be flagged for it. MEASURED 2026-09-03: both rows below fail before this fix.
        Assert.True(TerminalToken.IsSatisfied("x\n\n[PANEL VERDICT: GREEN]\n", "PANEL VERDICT"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n[**VERDICT: ALIGNED**]\n", "[VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n**[VERDICT: ALIGNED]**\n", "[VERDICT:"));

        // REGRESSION GUARDS - these must not move. The negations stay rejected because the token does
        // not LEAD the line, which is what StartsWith actually enforces.
        Assert.True(TerminalToken.IsSatisfied("x\n\n[VERDICT: ALIGNED]\n", "[VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nno [VERDICT: ...] was produced\n", "[VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nTests are not GREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nlast line with no token\n", "[VERDICT:"));
    }
```

- [ ] **Step 2: Run it and watch it FAIL**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~A_bracket_wrapped_verdict"
```
Expected: **1 failed.** MEASURED at `00b27ca`: with the old matcher the two bracket rows fail and every
regression guard passes. **If it passes here, STOP** - the rows are not exercising the matcher.

- [ ] **Step 3: Implement**

In `TerminalToken.cs`, add the field to the class and replace the loop body:

```csharp
public static class TerminalToken
{
    // '[' IS INCLUDED, AND THAT IS ONLY SAFE BECAUSE THE EXPECTED TOKEN IS STRIPPED THE SAME WAY.
    // Stripping it from the LINE alone would break every discipline whose token begins with '['.
    private static readonly char[] Decoration = { '*', '`', '_', '#', ' ', '[' };
```

```csharp
        // NORMALISE BOTH SIDES. Decoration is noise wherever it appears, so it is removed from the
        // expected token as well as from the line - that is what lets '[' be stripped without breaking
        // the three disciplines whose token starts with it, and it handles nesting in either order
        // ("[**VERDICT:" and "**[VERDICT:") because the characters are stripped as a set, not in order.
        var want = expected.Trim().TrimStart(Decoration);
        if (want.Length == 0) want = expected;   // a token that is ALL decoration would match everything

        var lines = answer.Split('\n');
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            var line = lines[i].Trim().TrimStart(Decoration);
            if (line.Length == 0) continue;
            return line.StartsWith(want, StringComparison.Ordinal);
        }
        return false;
```

- [ ] **Step 4: Run the whole suite**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
```
Expected: **0 failed**, `Total: 209` - the 208 baseline plus this one new `[Fact]`.
**MEASURED during the panel: the fix passes the full suite with every added row green.**

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/TerminalToken.cs clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs
git commit -m "fix(s29a): a bracket-wrapped terminal token is compliance, not truncation"
```

---

## Task 4: Close §29a in the ROADMAP with its SHA

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (the §29 header and its §29a paragraph)

- [ ] **Step 1: Mark §29a shipped, leave §29b open**

The header currently reads `SPLIT: §29a is a Phase 0d PREREQUISITE, §29b is tracked debt`. Change only
the §29a half to `§29a SHIPPED <sha>`, and **leave §29b exactly as it is** - its cause is still
undetermined and it does not gate anything.

- [ ] **Step 2: Verify the claims gate**

🔴 **RUN THIS FROM THE REPOSITORY ROOT.** The script lives at `<repo-root>/scripts/`, NOT under
`clavity-dotnet/`, and **Task 2 Step 5 leaves the shell in `clavity-dotnet/`** because it begins with
`cd clavity-dotnet`. The `cd` below is therefore load-bearing, not decoration:

```bash
cd "$(git rev-parse --show-toplevel)" && pwsh -NoProfile -Command "& './scripts/check-roadmap-claims.ps1'"; rc=$?; echo "roadmap=$rc"; (exit $rc)
```
Expected: `check-roadmap-claims: OK - every line-count claim and closure sha in ...ROADMAP.md holds` and
`roadmap=0`. **This checker validates closure SHAs**, so a fabricated one fails here.

⚠ **MEASURED 2026-09-03: run from `clavity-dotnet/` it fails with `The term './scripts/check-roadmap-claims.ps1'
is not recognized...` and `rc=1`.** It fails CLOSED, which is correct - but the message names a missing
COMMAND, not a failing claim, and an executor who reads it as "the claims gate rejected my ROADMAP edit"
will go and edit the ROADMAP to satisfy a checker that never ran.

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): close section 29a - the panel terminal token"
```

---

## WHAT THIS DOES NOT FIX - state it, or the plan ships a False Safety Promise

- **It does not make the check truncation-safe.** `PANEL VERDICT` is negatable as a prefix exactly as
  `GREEN` was - both measured. This is neutral, not hardening.
- **It does not fix §29b**, the flag whose cause is undetermined. Explicitly out of scope; it is tracked
  debt and must not gate this.
- **It does not stop a DRIVER from demanding the wrong token in its brief.** Nothing mechanical prevents
  a brief saying "end on `[VERDICT: ALIGNED]`", which would fail the check under the new token. That is a
  behavioural obligation on whoever writes the brief, and `SKILL.md:120-122` already states it - *"You
  supply NAMES only: the driver owns the terminal-token table."* **It is called out here because the
  driver broke it repeatedly on 2026-09-03.**

- ⚠ **IT DOES NOT MAKE A NEGATED VERDICT FAIL, AND THAT IS DELIBERATE.** `[PANEL VERDICT is not reached]`
  is ACCEPTED, as is the unbracketed form. **This is not a defect - it is what the check is for.** 13b
  asks "did the reply REACH THE END", never "was the outcome good"; `TerminalToken.cs` says so in its own
  summary. A peer whose last line is a negative verdict has finished cleanly. What `StartsWith` actually
  enforces is that the token LEADS the line - which is why *"Tests are not GREEN"* is still rejected. The
  live peer supplied this reading and it corrected mine; I had recorded it as a cost of the Task 3 fix.

- **It does not test the WIRING.** `McpTools.cs:44` resolves the discipline to a token and `AgyView.cs:249`
  applies it; **no test covers that path end-to-end.** Task 1 now covers table -> matcher (it reads
  `DisciplineContract.TerminalTokenFor`), which is the half this change can break. The MCP-level wiring
  remains unguarded, and that is a pre-existing coverage gap for AGY-TEST-AUDIT, not for this plan.

---

## Self-review

**1. Coverage.** The original ruling has one substantive half (the token) and one hygiene half (four stale
citations of `SKILL.md:208`); AGY-AFTER round 1 added a third, owner-ruled (the bracket false-flag).
Task 1 pins the behaviour, Task 2 changes the token and all four comments, **Task 3 fixes the matcher**,
Task 4 closes the item. Nothing in either ruling is unimplemented.

**2. Placeholders.** None. Every step carries literal before/after text and an exact command. The one
value that must not be copied is the closure SHA in Task 3, which says so.

**3. Consistency.** `PANEL VERDICT` is spelled identically in the token, the InlineData, the test
constant and all three comments. `TerminalToken.IsSatisfied`'s signature is unchanged - the rejected
multi-token option would have changed it, and this one does not.

**4. Exhaustiveness audit.** Ran, and it moved two things:
- **The four-site citation sweep is IN the plan** because a `git grep` found `SKILL.md:208` in four files
  when the anomaly had named one. Law 3.
- **`AgyAskIntegrationTests.cs:1761` was checked and deliberately EXCLUDED** - it asserts the discipline
  is NAMED in an `[13b] UNCHECKED` notice and never mentions the token, so it is unaffected. Recorded so
  a later reader does not assume it was missed.
- Remaining gap, resolved elsewhere: §29b. Tracked in the ROADMAP, not here.

## Stand-downs

Required output of `adversarial-panel-review`: every finding stood down below the severity floor, or
accepted unverified, on one line with its citation. **Nothing was swept — round 1 produced no
below-floor discards.** The two dispositions that are not `FOLDED`:

- `REJECTED: DisciplineContractTests.cs:19` — the peer's claim that a misspelled dictionary KEY
  (`adverserial-panel-review`) or a typo'd VALUE (`PANEL VREDICT`) would leave both unit tests passing.
  `Assert.Equal(expected, DisciplineContract.TerminalTokenFor(discipline))` fails in BOTH cases: a bad
  key returns `null`, a bad value returns the typo. Its **general** point — that no test covers the
  `McpTools` wiring — is true and is now recorded under "WHAT THIS DOES NOT FIX".
- `FOLDED: Task 3 - normalise the expected token as well as the line` — the bracket gap. It was first
  disposed `DEFERRED-TO-ANOMALIES` as a MATERIAL deferral; **the owner ruled it be fixed inside §29a
  instead**, so the deferral is withdrawn and the anomaly entry is superseded by Task 3.
- `REJECTED: TerminalToken.cs summary + the live peer's Q2` — my own claim that accepting
  `[PANEL VERDICT is not reached]` is a cost of the Task 3 fix. It is a category error: this check tests
  for truncation, not for a good outcome. Recorded because I nearly shipped it as a known weakness.

## Review status

⚠ **AGY-AFTER ROUND 1 COMPLETE — 6 findings folded, 1 rejected by measurement, 1 deferred pending an
owner ruling.** Reviewed by the solo panel plus a live agy escalation round.

**Reviewing version, recorded because this plan edits the discipline that reviews it (sequence spec,
"Risks"):** `adversarial-panel-review/SKILL.md` at repo HEAD **`42cfa84`**, 380 lines.

🔴 **THE ESCALATION ROUND WAS ITSELF FLAGGED `[13b] TRUNCATED REPLY`** — *"Treat this consult as
INCOMPLETE - do not fold findings from it"* — because it closed on `PANEL VERDICT: ...` while the table
still expects `GREEN`. The reply was complete and its echo passed. **This plan's own review is the second
measured instance of the defect it fixes, and the discarded findings included the vacuous-TDD defect that
would have halted execution.**

▶ **NOT YET EXECUTABLE-APPROVED:** the deferred bracket finding is MATERIAL and awaits an owner ruling;
round 2 has not been run.
