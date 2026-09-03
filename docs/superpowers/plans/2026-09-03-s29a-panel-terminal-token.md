# §29a - the panel's terminal token - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax
> for tracking.

**Goal:** Make a findings-bearing `adversarial-panel-review` round satisfy the 13b completeness check,
instead of being flagged every time with a message telling the driver to discard its findings.

**Architecture:** One atomic driver-side change, in Task 2. **`DisciplineContract` stores the token that
is actually ENFORCED** - `PANEL VERDICT` for the panel discipline, and `VERDICT:` (no bracket) for the
other three - and **`TerminalToken` treats a leading `[` as decoration**, stripping it alongside `**`,
`` ` ``, `_`, `#` and space. `StartsWith` stays, so the token must still LEAD the line. No `SKILL.md`
edit, so no byte-identical pair, no plugin reinstall.

⚠ **AMENDED TWICE BY OWNER RULING DURING AGY-AFTER.** Round 1: the plan was a one-value change; the panel
found a reachable false-flag and the owner ruled the fix lands here. Round 3: an interim design stripped
`[` from the expected token at RUNTIME, which left `DisciplineContract` reading `[VERDICT:` while the
runtime enforced only `VERDICT:` - **MEASURED: a bracketless `* VERDICT: ALIGNED` satisfied it.** The
owner ruled the contract must store what is enforced. **Still driver-only, which is what keeps §29a a
legitimate BOUNDED prerequisite.**

**Tech Stack:** C# (`Clavity.Ls`), xUnit (`Clavity.Ls.Tests` **and `Clavity.Integration.Tests`**).

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
| ~~the integration test needs NO change~~ | 🔴 **SUPERSEDED at round 3.** True ONLY of `:1761`, which asserts the discipline is NAMED in an `[13b] UNCHECKED` notice and is token-agnostic. **`:1456` and `:1474` pass `expectTerminal: "[VERDICT:"` as a literal and DO need changing** - MEASURED: skipping them leaves `AskAsync_does_NOT_flag_when_the_reply_ends_with_the_expected_token` failing (`Failed: 1, Passed: 83`). |
| test command | `clavity-dotnet/CLAUDE.md:21` - `dotnet test tests/Clavity.Ls.Tests` |

---

## File Structure

| file | responsibility | status |
|---|---|---|
| `clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs` | the token table - the ONE place these literals live | MODIFY (**4 values** + doc comment) |
| `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs` | the matcher; **LOGIC CHANGES** - `[` joins the decoration set | MODIFY (Task 2) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs` | pins the table | MODIFY (**5 sites** + comment) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs` | pins the matcher | MODIFY (**6 sites**, + Task 1's rewrite, + one new `[Fact]`) |
| `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` | end-to-end 13b behaviour | MODIFY (**2 sites** - `:1456`, `:1474`) |

**Blast radius: driver-only** - no plugin payload, no byte-identical pair, no `0c-local` reinstall, which
is why §29a is a BOUNDED Phase 0d prerequisite. ⚠ **But it is NOT small: MEASURED at 5 files, 18
insertions / 17 deletions, across TWO test projects.** An estimate of "3 values and one test file" was
made during round 3 and was wrong by roughly threefold; it is recorded here so the next reader sizes the
task from the measurement rather than from that estimate.

🔴 **EVERY COMMAND IN THIS PLAN IS SELF-LOCATING, AND THAT IS NOT DECORATION.** The executor's shell
**keeps its working directory between steps.** An earlier draft opened Task 1 with a bare
`cd clavity-dotnet`, which left every later step one level down; **MEASURED from there: `cd clavity-dotnet`
gives "No such file or directory", and `git add clavity-dotnet/src/...` gives `fatal: pathspec ... did not
match any files`.** The run would have died at Task 2. Found by AGY-AFTER round 2 — round 1 had fixed the
same bug in ONE task and missed the other four, which is the incomplete-fold failure exactly.
**Do not "simplify" `cd "$(git rev-parse --show-toplevel)"` back out of these commands.**

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
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~The_panel_token_comes_from_the_contract"
```
Expected: **1 failed** - `TerminalTokenFor` still returns `GREEN`, so the first assertion fails.
**If this test PASSES at this step, STOP** - the token is being read as a literal instead of from the
table, and Task 2 would prove nothing. Report `STATE_MISMATCH: the panel token test passes before the
contract changed`.

⚠ **`dotnet test --filter` EXITS 0 ON NO MATCH.** Read the COUNT, never the exit code alone.

---

## Task 2: The token contract and the matcher — ONE ATOMIC COMMIT

🔴 **TASKS 2 AND 3 WERE SEPARATE UNTIL AGY-AFTER ROUND 3. THEY CANNOT BE.** Splitting them leaves the
tree RED in either order, which is why this is one task:

- **Contract first, matcher second:** the contract says `VERDICT:` while the matcher still keeps `[`, so
  `[VERDICT: ALIGNED]` fails `StartsWith("VERDICT:")`.
- **Matcher first, contract second:** the matcher strips `[` while the contract still says `[VERDICT:`,
  so the stripped `VERDICT: ALIGNED]` fails `StartsWith("[VERDICT:")`.

**Both halves land together or neither does.**

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs` (4 values + doc comment)
- Modify: `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs` (decoration set + doc comment)
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs` (5 sites + comment)
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs` (6 sites)
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` (2 sites)

⚠ **MEASURED TOTAL: 5 files, 18 insertions / 17 deletions, across TWO test projects.** An earlier
estimate of "3 values and one test file" was wrong by roughly threefold. **Still driver-only** — no
plugin payload, no byte-identical pair, no `0c-local` reinstall — which is what keeps §29a a legitimate
Phase 0d prerequisite.

**Owner ruling 2026-09-03, AGY-AFTER round 3: the CONTRACT stores what is actually enforced.** An earlier
draft stripped `[` from the expected token at RUNTIME, which fixed the false-flag but left
`DisciplineContract` reading `[VERDICT:` while the runtime enforced only `VERDICT:` — **MEASURED: a
bullet-prefixed, bracketless `* VERDICT: ALIGNED` satisfied it.** That is a file asserting a guard it does
not have. Storing the normalised token instead makes the real contract visible to anyone who opens it.

- [ ] **Step 1: The contract values**

`DisciplineContract.cs`, change all four:
```csharp
            ["agy-capstone"] = "[VERDICT:",
            ["agy-test-audit"] = "[VERDICT:",
            ["agy-first"] = "[VERDICT:",
            ["adversarial-panel-review"] = "GREEN",
```
to:
```csharp
            ["agy-capstone"] = "VERDICT:",
            ["agy-test-audit"] = "VERDICT:",
            ["agy-first"] = "VERDICT:",
            ["adversarial-panel-review"] = "PANEL VERDICT",
```

⚠ **THE BRACKET IS DELIBERATELY ABSENT AND THAT IS THE POINT.** The skills still tell peers to write
`[VERDICT: ...]`; the bracket is DECORATION, stripped before comparison like `**` and `` ` ``. Storing
`[VERDICT:` here would claim an enforcement that does not exist.

- [ ] **Step 2: The doc comment in the same file**

`DisciplineContract.cs`, change:
```csharp
/// adversarial-panel-review ends on GREEN (its SKILL.md:208), the other three on [VERDICT:.</summary>
```
to:
```csharp
/// adversarial-panel-review closes each ROUND on a single-line PANEL VERDICT (its SKILL.md, section
/// "Step 1 - Solo panel"); the other three end on VERDICT:. Cited by SECTION, not line: this comment
/// said ":208" until 2026-09-03 and that line had long since become something else.
///
/// THE TOKENS ARE STORED WITHOUT THEIR BRACKET ON PURPOSE. Peers are told to write "[VERDICT: ...]",
/// and TerminalToken strips a leading '[' as decoration before comparing. A token stored as "[VERDICT:"
/// would therefore describe an enforcement the matcher does not perform. GREEN is not gone from the
/// panel skill either - it remains that skill's RUN-level disposition; this table checks a single
/// REPLY, which is one ROUND.</summary>
```

- [ ] **Step 3: The matcher**

`TerminalToken.cs`, add the field to the class:
```csharp
public static class TerminalToken
{
    // '[' IS DECORATION. Three disciplines tell their peer to write "[VERDICT: ...]", and a peer that
    // brackets a complete verdict was being flagged as truncated. The tokens in DisciplineContract are
    // stored WITHOUT the bracket so that stripping it here cannot contradict them.
    private static readonly char[] Decoration = { '*', '`', '_', '#', ' ', '[' };
```

and replace the strip in the loop:
```csharp
            var line = lines[i].Trim().TrimStart('*', '`', '_', '#', ' ');
```
with:
```csharp
            var line = lines[i].Trim().TrimStart(Decoration);
```

**Nothing else in the method changes.** `StartsWith` stays, and so does the negation guard it provides:
the token must LEAD the line, so *"Tests are not GREEN"* and *"no [VERDICT: ...] was produced"* are still
rejected.

- [ ] **Step 4: The doc comment on the matcher**

`TerminalToken.cs:13-15`, change:
```csharp
/// The expectation is supplied PER CALL because the four disciplines do not share a grammar: agy-capstone,
/// agy-test-audit and agy-first end on "[VERDICT:", while adversarial-panel-review ends on "GREEN"
/// (adversarial-panel-review/SKILL.md:208). A single hardcoded pattern would flag every panel reply.</summary>
```
to:
```csharp
/// The expectation is supplied PER CALL because the four disciplines do not share a grammar: agy-capstone,
/// agy-test-audit and agy-first end on "VERDICT:", while adversarial-panel-review closes each round on a
/// single-line "PANEL VERDICT" (its SKILL.md, section "Step 1 - Solo panel"). A single hardcoded pattern
/// would flag every panel reply.</summary>
```

- [ ] **Step 5: Every test literal that carries the old token**

**These are not optional — the suite goes RED without them.** Replace `"[VERDICT:"` with `"VERDICT:"` at
**6 sites in `TerminalTokenTests.cs`** and **5 sites in `DisciplineContractTests.cs`**, and
`expectTerminal: "[VERDICT:"` with `expectTerminal: "VERDICT:"` at **2 sites in
`AgyAskIntegrationTests.cs`**.

⚠ **MEASURED: skipping the integration file leaves
`AskAsync_does_NOT_flag_when_the_reply_ends_with_the_expected_token` FAILING** (Integration suite:
`Failed: 1, Passed: 83`). The plan's VERIFIED STATE row about the integration tests refers ONLY to
`:1761` and does NOT cover these two.

Then update `DisciplineContractTests.cs`'s comment block:
```csharp
        // The token literals live HERE and nowhere else. Measured 2026-08-19: the first three use
        // [VERDICT: (17, 12 and 10 occurrences); adversarial-panel-review uses GREEN and has ZERO
        // [VERDICT occurrences - SKILL.md:208, "For this skill that means GREEN".
```
to:
```csharp
        // The token literals live HERE and nowhere else. The three [VERDICT: skills carry 17, 12 and 10
        // occurrences of that string (re-measured 2026-09-03, still exact) - but the token is stored
        // WITHOUT the bracket, because TerminalToken strips a leading '[' as decoration. The panel skill
        // has ZERO [VERDICT occurrences and closes each ROUND on a single-line PANEL VERDICT.
        // Re-measure the counts before trusting them.
```

- [ ] **Step 6: Add the rows that prove the bracket is now decoration**

Append inside `TerminalTokenTests.cs`:

```csharp
    [Fact]
    public void A_bracket_wrapped_verdict_is_compliance_not_truncation()
    {
        // Three disciplines tell their peer to write "[VERDICT: ...]", so peers bracket by habit and a
        // complete reply must not be flagged for it. MEASURED 2026-09-03: the bracket rows fail before
        // this change and pass after it.
        Assert.True(TerminalToken.IsSatisfied("x\n\n[VERDICT: ALIGNED]\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n[**VERDICT: ALIGNED**]\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n**[VERDICT: ALIGNED]**\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n[PANEL VERDICT: GREEN]\n", "PANEL VERDICT"));

        // THE BRACKET IS NOW OPTIONAL, AND THE CONTRACT SAYS SO. This row exists to make that visible
        // rather than to be discovered later by someone reading DisciplineContract.
        Assert.True(TerminalToken.IsSatisfied("x\n\n* VERDICT: ALIGNED\n", "VERDICT:"));

        // REGRESSION GUARDS - the token must still LEAD the line.
        Assert.False(TerminalToken.IsSatisfied("x\n\nno [VERDICT: ...] was produced\n", "VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nTests are not GREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nlast line with no token\n", "VERDICT:"));
    }
```

⚠ **LITERALS ARE CORRECT IN *THIS* TEST, unlike Task 1 — do not "fix" them.** Task 1 pins the CONTRACT and
must read the table. This test pins the MATCHER across token SHAPES, including other disciplines' tokens;
coupling it to the table would let a table change silently alter which shapes are covered.

- [ ] **Step 7: Run BOTH suites**

```bash
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Ls.Tests
```
Expected: **0 failed, `Total: 209`** — the 208 baseline plus the one new `[Fact]` from Step 6.

```bash
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Integration.Tests
```
Expected: **0 failed, `Total: 84`.** MEASURED — this suite is not CI-run, so it is easy to forget, and it
is exactly where the missed literal shows up.

🔴 **`Total: 208` IS NOT AN ORACLE FOR THIS TASK AND NEVER WAS.** It is also the untouched baseline, so a
run that does nothing at all prints it. **The oracle is the pair:** `Total: 209` on the Ls suite (only
Step 6 moves it) AND the named test below passing, which fails before this task:

```bash
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~The_panel_token_comes_from_the_contract"
```
Expected: **1 passed.** ⚠ **`dotnet test --filter` EXITS 0 ON NO MATCH — read the COUNT.**

- [ ] **Step 8: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs clavity-dotnet/src/Clavity.Ls/TerminalToken.cs clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "fix(s29a): store the enforced token, and treat a leading bracket as decoration"
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
cd "$(git rev-parse --show-toplevel)" && git add clavity-dotnet/ROADMAP.md
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

- 🔴 **IT MAKES THE BRACKET OPTIONAL, ON PURPOSE, AND THE CONTRACT NOW SAYS SO.** After Task 2 a
  bracketless `VERDICT: ALIGNED`, and even a bullet-prefixed `* VERDICT: ALIGNED`, satisfy the three
  `VERDICT:` disciplines. **MEASURED.** This is the price of accepting `[VERDICT: ALIGNED]`, which the
  skills actually instruct peers to write: the bracket cannot be optional decoration AND enforced
  structure at once. What makes it acceptable is that `DisciplineContract` now stores `VERDICT:`, so the
  file states the enforcement it performs. **An earlier draft achieved the identical runtime behaviour
  while the contract still read `[VERDICT:` — that version was rejected by owner ruling as a file
  asserting a guard it did not have.** A test row pins the bracketless shape so it cannot be mistaken for
  an oversight.

- **It does not stop a peer emitting a MALFORMED bracketed line** such as `[[VERDICT: x` or
  `[VERDICT ALIGNED]` (no colon). The first is accepted (both `[` strip); the second is rejected (no
  colon). Neither is a truncation, which is all this gate judges.

---

## Self-review

**1. Coverage.** Three owner rulings are implemented: the token swap (original), the bracket fix
(round 1), and storing the ENFORCED token in the contract (round 3). Task 1 pins the behaviour and is the
RED arm, **Task 2 lands the contract and matcher together in one atomic commit**, Task 3 closes the item.
Nothing in any ruling is unimplemented.

**5. Dry-run.** The whole of Task 2 was applied and measured before this plan was called reviewed:
**`Clavity.Ls.Tests` 209/209 and `Clavity.Integration.Tests` 84/84**, then reverted. The stated expected
outputs are measurements, not predictions.

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

**Round 2:**

- `REJECTED: McpTools.cs:74-84` — the claim that making the bracket optional will break "a downstream
  parser that extracts the verdict payload". **No such parser exists.** The only `[VERDICT:` occurrences
  in `src/` are the three contract values and one comment; the matcher's result is consumed as a boolean.
  The underlying behaviour change is real and is now pinned by an explicit assertion instead.
- `REJECTED: measured` — the claim that Task 3's test "reintroduces the exact vacuous-TDD defect" by using
  string literals. It does not: with the old matcher that test **FAILS** (`Failed: 1, Passed: 0`).
  Literals are correct there because it pins the MATCHER across token shapes, including other disciplines'
  tokens; only Task 1 pins the CONTRACT and must read the table. The seat was right that the two tests
  look inconsistent, so the reason is now written into the plan beside the test.

**Round 3:**

- `FOLDED: Task 2 stores the enforced token` — the runtime normalisation made `DisciplineContract` claim
  an enforcement it did not perform (**measured: `* VERDICT: ALIGNED` satisfied `[VERDICT:`**). Owner-ruled.
- `FOLDED: Task 2 Step 7 names a real oracle` — `Total: 208` was **indistinguishable from doing nothing**,
  since 208 is the untouched baseline. The oracle is now `Total: 209` plus a named test that fails before
  the task.
- `FOLDED: Tasks 2 and 3 merged` — found while verifying the ruling, not by a seat: the contract and
  matcher changes leave the tree RED in **either** separated order, so they must be one commit.
- `REJECTED: no .gitmodules exists; git submodule status is empty` — the claim that
  `git rev-parse --show-toplevel` could return a submodule root here and break the `cd`.
- `DISCARDED-BELOW-FLOOR: every command block in this plan is fenced ` ```bash ` ` — the claim that the
  `$(...)` idiom fails under `cmd.exe`. True of `cmd.exe`, but an executor running these bash blocks in
  `cmd.exe` fails on the fences long before the subshell, so the idiom is not the reachable defect.

## Review status

⚠ **AGY-AFTER ROUNDS 1-3 COMPLETE — 11 folded, 6 rejected/discarded by measurement, 0 open.** Round 1:
solo panel (8 seats) + live escalation. Round 2: State Corruptor, Activation Auditor, Literal Implementer.
Round 3: Blindspot Auditor, Cascade Analyst, Boundary Smuggler. **Every round produced a blocking finding,
and rounds 2 and 3 each hit the PREVIOUS round's repair.**

⚠ **ROUND 3's REPLY ECHOED A STALE LINE** (`round 2 has not been run.`) while citing line numbers that
only exist AFTER round 2's fold — so it read the current file but produced the echo from its own context.
**The echo check caught exactly what it exists to catch.** Its findings were verified against the current
file individually rather than trusted or discarded wholesale.

🔴 **ROUND 2'S BLOCKING FIND WAS AN INCOMPLETE FOLD OF ROUND 1's FIX.** Round 1 corrected a
working-directory bug in ONE task and left the identical bug in four others; the executor's shell keeps
its cwd, so the run would have died at Task 2 with `fatal: pathspec ... did not match any files`.
**MEASURED.** Every command is now self-locating. This is the third law in its purest form: the dominant
fold defect is an incomplete fold.

**Both rounds' fixes were verified by RED/GREEN with the source reverted and the tests kept**, so no new
test is assumed non-vacuous — each was watched failing first. Final: full suite **209/209**.

**Reviewing version, recorded because this plan edits the discipline that reviews it (sequence spec,
"Risks"):** `adversarial-panel-review/SKILL.md` at repo HEAD **`42cfa84`**, 380 lines.

🔴 **THE ESCALATION ROUND WAS ITSELF FLAGGED `[13b] TRUNCATED REPLY`** — *"Treat this consult as
INCOMPLETE - do not fold findings from it"* — because it closed on `PANEL VERDICT: ...` while the table
still expects `GREEN`. The reply was complete and its echo passed. **This plan's own review is the second
measured instance of the defect it fixes, and the discarded findings included the vacuous-TDD defect that
would have halted execution.**

▶ **READY TO EXECUTE**, subject to the owner's call on whether to run a third round. Every finding from
both rounds carries a closed AGY-SCOPE token; nothing sits open.
