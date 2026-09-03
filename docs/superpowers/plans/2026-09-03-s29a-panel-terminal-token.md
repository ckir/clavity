# §29a - the panel's terminal token - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax
> for tracking.

**Goal:** Make a findings-bearing `adversarial-panel-review` round satisfy the 13b completeness check,
instead of being flagged every time with a message telling the driver to discard its findings.

**Architecture:** Change ONE dictionary value in the driver - the discipline's expected terminal token
moves from `GREEN` to `PANEL VERDICT`, the line the panel skill already mandates. No matching logic
changes; `StartsWith` stays. No `SKILL.md` edit, so no byte-identical pair, no plugin reinstall.

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
| `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs` | the matcher; **logic unchanged**, doc comment only | MODIFY (comment) |
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

```csharp
    [Fact]
    public void The_panel_discipline_accepts_every_disposition_its_skill_declares()
    {
        // adversarial-panel-review does NOT use [VERDICT: - it closes each round on a single-line
        // PANEL VERDICT (its SKILL.md, "Step 1 - Solo panel"). The token was GREEN until 2026-09-03,
        // which flagged EVERY findings-bearing round: the skill's Outputs section declares FOUR
        // legitimate dispositions and only one of them is GREEN, so a round that found something was
        // told it was incomplete and its findings should be discarded. Measured: the first reply so
        // flagged carried a confirmed BLOCKING defect.
        const string tok = "PANEL VERDICT";
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nPANEL VERDICT: GREEN\n", tok));
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nPANEL VERDICT: 2 open findings remain\n", tok));
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\nPANEL VERDICT: cap-reached\n", tok));
        Assert.True(TerminalToken.IsSatisfied("panel ran\n\n**PANEL VERDICT: GREEN**\n", tok));

        // Still rejects a reply that never reached a verdict line at all.
        Assert.False(TerminalToken.IsSatisfied("panel ran\n\nopen findings remain\n", tok));
    }
```

- [ ] **Step 2: Run it and watch it FAIL**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~The_panel_discipline_accepts_every_disposition"
```
Expected: **1 failed.** The three `PANEL VERDICT: ...` assertions pass on their own (the token is passed
literally here, not read from the table), so **if this test PASSES at this step, STOP** - it is not
exercising the contract and Task 2 would prove nothing. Report `STATE_MISMATCH: the panel token test
passes before the contract changed`.

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
        // [VERDICT: (17, 12 and 10 occurrences); adversarial-panel-review has ZERO [VERDICT
        // occurrences and closes each round on a single-line PANEL VERDICT, which its SKILL.md
        // mandates in "Step 1 - Solo panel". Re-measure the counts before trusting them.
```

- [ ] **Step 5: Run the two suites and watch them PASS**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
```
Expected: **0 failed**, and the count must be the same as before this plan started plus nothing - Task 1
replaced a test rather than adding one.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs clavity-dotnet/src/Clavity.Ls/TerminalToken.cs clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs
git commit -m "fix(s29a): the panel's terminal token is PANEL VERDICT, not GREEN"
```

---

## Task 3: Close §29a in the ROADMAP with its SHA

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (the §29 header and its §29a paragraph)

- [ ] **Step 1: Mark §29a shipped, leave §29b open**

The header currently reads `SPLIT: §29a is a Phase 0d PREREQUISITE, §29b is tracked debt`. Change only
the §29a half to `§29a SHIPPED <sha>`, and **leave §29b exactly as it is** - its cause is still
undetermined and it does not gate anything.

- [ ] **Step 2: Verify the claims gate**

```bash
pwsh -NoProfile -Command "& './scripts/check-roadmap-claims.ps1'"; rc=$?; echo "roadmap=$rc"; (exit $rc)
```
Expected: `check-roadmap-claims: OK ...` and `roadmap=0`. **This checker validates closure SHAs**, so a
fabricated one fails here.

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

---

## Self-review

**1. Coverage.** The ruling has one substantive half (the token) and one hygiene half (four stale
citations of `SKILL.md:208`). Task 1 pins the behaviour, Task 2 changes the token and all four comments,
Task 3 closes the item. Nothing in the ruling is unimplemented.

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

## Review status

🔴 **NOT YET REVIEWED.** AGY-AFTER is owed on this plan before execution.
