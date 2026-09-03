# §29a - the panel's terminal token - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax
> for tracking.

**Goal:** Make a findings-bearing `adversarial-panel-review` round satisfy the 13b completeness check,
instead of being flagged every time with a message telling the driver to discard its findings.

**Architecture:** **TWO independent driver-side changes, in that order.** Task 2 swaps the panel
discipline's token to `PANEL VERDICT` — the original §29a, small, and **measured green on its own**.
Task 3 then fixes the bracket false-flag: **`DisciplineContract` stores the token that is actually
ENFORCED** (`VERDICT:`, no bracket, for the other three) and **`TerminalToken` treats a leading `[` as
decoration**, stripping it alongside `**`, `` ` ``, `_`, `#` and space. `StartsWith` stays, so the token
must still LEAD the line. No `SKILL.md` edit, so no byte-identical pair, no plugin reinstall.

⚠ **TASK 3 IS ATOMIC WITHIN ITSELF; TASK 2 IS NOT PART OF THAT.** An earlier draft merged both on an
over-broad claim that "the contract and matcher cannot be separated". **AGY-AFTER round 4 corrected it,
and the correction is MEASURED:** Task 2 applied alone gives `Clavity.Ls.Tests` 208/208 and
`Clavity.Integration.Tests` 84/84.

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
| `clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs` | the token table - the ONE place these literals live | MODIFY (**1 value in T2, 3 in T3** + doc comment) |
| `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs` | the matcher; **LOGIC CHANGES** - `[` joins the decoration set | MODIFY (**Task 3**) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs` | pins the table | MODIFY (**1 `InlineData` in T2, 5 sites in T3**, + the invariant guard) |
| `clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs` | pins the matcher | MODIFY (Task 1's rewrite, then **6 sites + 1 new `[Fact]`** in T3) |
| `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` | end-to-end 13b behaviour | MODIFY (**2 sites** - `:1456`, `:1474`; **the fake reply text is NOT touched**) |

**Blast radius: driver-only** - no plugin payload, no byte-identical pair, no `0c-local` reinstall, which
is why §29a is a BOUNDED Phase 0d prerequisite. ⚠ **But it is NOT small: 5 files across TWO test
projects.** An estimate of "3 values and one test file" was made during round 3 and was wrong by roughly
threefold. 🔴 **NO LINE-COUNT IS QUOTED HERE ON PURPOSE.** A "18 insertions / 17 deletions" figure was
carried until round 5, measured against a design that has since gained two `[Fact]`s and a public helper —
**a diffstat is volatile state in static prose and rots on the next fold.** Size the task from the FILE
LIST, which is stable, and read the real diffstat from git when you need one.

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

## Task 2: The panel token — the ORIGINAL §29a, and it ships alone

🔴 **THIS TASK IS INDEPENDENT AND LEAVES THE TREE GREEN.** An earlier draft merged it with Task 3 on the
claim that "the contract and matcher cannot be separated". **That claim was over-broad and AGY-AFTER
round 4 corrected it:** what cannot be split is the BRACKET fix's own contract/matcher halves (Task 3),
not the panel token. **MEASURED with this task applied alone: `Clavity.Ls.Tests` 208/208 and
`Clavity.Integration.Tests` 84/84.**

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs` (1 value + doc comment)
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs` (1 `InlineData`)
- (Task 1 already rewrote the test that pins this.)

- [ ] **Step 1: The token**

```bash
cd "$(git rev-parse --show-toplevel)" && sd '\["adversarial-panel-review"\] = "GREEN",' '["adversarial-panel-review"] = "PANEL VERDICT",' clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs
cd "$(git rev-parse --show-toplevel)" && sd '\[InlineData\("adversarial-panel-review", "GREEN"\)\]' '[InlineData("adversarial-panel-review", "PANEL VERDICT")]' clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs
```

- [ ] **Step 2: The doc comment**

`DisciplineContract.cs`, change:
```csharp
/// adversarial-panel-review ends on GREEN (its SKILL.md:208), the other three on [VERDICT:.</summary>
```
to:
```csharp
/// adversarial-panel-review closes each ROUND on a single-line PANEL VERDICT (its SKILL.md, section
/// "Step 1 - Solo panel"); the other three end on [VERDICT:. Cited by SECTION, not line: this comment
/// said ":208" until 2026-09-03 and that line had long since become something else.
///
/// GREEN is not gone from the panel skill - it remains that skill's RUN-level disposition ("Outputs",
/// and its Completeness gate: "For this skill that means GREEN"). This table checks a single REPLY,
/// which is one ROUND. Do not "reconcile" the two by reverting this.</summary>
```

- [ ] **Step 3: Run both suites**

```bash
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Ls.Tests
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Integration.Tests
```
Expected: **`Total: 208`, 0 failed** and **`Total: 84`, 0 failed** — both MEASURED.

🔴 **`Total: 208` IS NOT THE ORACLE — it is also the untouched baseline.** The oracle is the named test
from Task 1, which FAILS before this step:

```bash
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~The_panel_token_comes_from_the_contract"
```
Expected: **1 passed.** ⚠ **`dotnet test --filter` EXITS 0 ON NO MATCH — read the COUNT.**

- [ ] **Step 4: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs
git commit -m "fix(s29a): the panel's terminal token is PANEL VERDICT, not GREEN"
```

---

## Task 3: The bracket false-flag — contract and matcher together

🔴 **THIS TASK IS ATOMIC AND THAT IS MEASURED, not assumed.** Its two halves cannot be separated:

- **Contract first:** the contract says `VERDICT:` while the matcher still keeps `[`, so
  `[VERDICT: ALIGNED]` fails `StartsWith("VERDICT:")`.
- **Matcher first:** the matcher strips `[` while the contract still says `[VERDICT:`, so the stripped
  `VERDICT: ALIGNED]` fails `StartsWith("[VERDICT:")`.

**Files:** `TerminalToken.cs` · `DisciplineContract.cs` (3 values + comment) ·
`DisciplineContractTests.cs` (5 sites) · `TerminalTokenTests.cs` (6 sites + 2 new `[Fact]`s) ·
`AgyAskIntegrationTests.cs` (2 sites).

**Owner ruling, AGY-AFTER round 3: the CONTRACT stores what is actually ENFORCED.** An earlier draft
stripped `[` from the expected token at RUNTIME, which fixed the false-flag but left `DisciplineContract`
reading `[VERDICT:` while the runtime enforced only `VERDICT:` — **MEASURED: a bullet-prefixed
`* VERDICT: ALIGNED` satisfied it.** A file must not assert a guard it does not have.

- [ ] **Step 1: The contract values and every test literal — as COMMANDS, not a search**

⚠ **13 replacements across 4 files. Do NOT hunt them by hand** — that is how the wrong occurrence gets
replaced. Run these and read the counts back:

```bash
cd "$(git rev-parse --show-toplevel)"
for f in clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs \
         clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs \
         clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs \
         clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs; do
  before=$(grep -c '"\[VERDICT:"' "$f"); sd '"\[VERDICT:"' '"VERDICT:"' "$f"
  after=$(grep -c '"\[VERDICT:"' "$f")
  echo "$f  before=$before after=$after"
  [ "$before" -gt 0 ] && [ "$after" -eq 0 ] || echo "  !! STATE_MISMATCH in $f"
done
```

🔴 **THE ORACLE IS `before > 0` AND `after == 0` PER FILE — NOT a specific `before` value.** Every file
must have had at least one occurrence and must have none left. **Do NOT re-introduce hardcoded expected
counts here.** AGY-AFTER round 5 found exactly that: the previous draft asserted `3` and `5` for the
first two files, **labelled the numbers MEASURED when they were not** (they came from a different grep
pattern, without the surrounding quotes), and tied a mandatory abort to them — **so the plan halted
itself at this step.** The real counts are `4` and `4`; a comment and an `Assert` carry the literal too,
and any future comment mentioning it would shift them again. **A count that drifts with prose is not an
oracle. `after == 0` is.**

⚠ **The real proof is Step 5: both suites green.** This loop only stops the executor replacing the wrong
occurrence by hand.

⚠ **DO NOT touch the fake reply text in `AgyAskIntegrationTests.cs`.** It emits
`"findings here\n\n[VERDICT: ALIGNED]"` and **must keep its bracket** — with `expectTerminal` now
bracketless, that test becomes the end-to-end proof that a bracketed reply survives the wiring. A round-4
seat argued this change "neuters" the test; **measured, the opposite is true, but only because the
fixture keeps its bracket.**

- [ ] **Step 2: The matcher**

```csharp
public static class TerminalToken
{
    // '[' IS DECORATION. Three disciplines tell their peer to write "[VERDICT: ...]", and a peer that
    // brackets a complete verdict was being flagged as truncated.
    //
    // 🔴 INVARIANT, and it is enforced by a test below: NO EXPECTED TOKEN MAY BEGIN WITH ONE OF THESE
    // CHARACTERS. Only the LINE is stripped, so a token like "[NEW_VERDICT]" would be unsatisfiable -
    // the line loses its '[' and can never match an expectation that still has one. This is the price
    // of storing the enforced token in DisciplineContract rather than normalising it at runtime.
    private static readonly char[] Decoration = { '*', '`', '_', '#', ' ', '[' };

    /// <summary>Is this character stripped from the front of a line before matching? EXPOSED SO THE
    /// INVARIANT TEST CANNOT ROT: a guard that hardcodes its own copy of the set stops covering the set
    /// the moment a character is added here, while still claiming to enforce it.</summary>
    public static bool IsDecoration(char c) => Array.IndexOf(Decoration, c) >= 0;
```

and in the loop replace `TrimStart('*', '`', '_', '#', ' ')` with `TrimStart(Decoration)`.
**Nothing else changes.** `StartsWith` stays, so the token must still LEAD the line.

- [ ] **Step 3: Make the invariant MECHANICAL, not a comment**

A rule with no implementation is worse than no rule. Add to `DisciplineContractTests.cs`:

```csharp
    [Fact]
    public void No_stored_token_begins_with_a_character_the_matcher_strips()
    {
        // TerminalToken strips leading decoration from the LINE only. A token that BEGINS with one of
        // those characters could therefore never be matched - the line would lose the character and the
        // expectation would keep it. Found as an unstated invariant by AGY-AFTER round 4; this test is
        // what stops it being rediscovered as a live defect by whoever adds the fifth discipline.
        foreach (var d in DisciplineContract.KnownDisciplines)
        {
            var tok = DisciplineContract.TerminalTokenFor(d)!;
            // ASK THE MATCHER, do not restate its set. A hardcoded copy would silently stop covering
            // any character added to Decoration later, while still reading as an enforced invariant.
            Assert.False(TerminalToken.IsDecoration(tok[0]),
                $"discipline '{d}' stores token '{tok}', which begins with a stripped character");
        }
    }
```

- [ ] **Step 4: The rows that prove the bracket is now decoration**

Append to `TerminalTokenTests.cs`:

```csharp
    [Fact]
    public void A_bracket_wrapped_verdict_is_compliance_not_truncation()
    {
        Assert.True(TerminalToken.IsSatisfied("x\n\n[VERDICT: ALIGNED]\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n[**VERDICT: ALIGNED**]\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n**[VERDICT: ALIGNED]**\n", "VERDICT:"));
        Assert.True(TerminalToken.IsSatisfied("x\n\n[PANEL VERDICT: GREEN]\n", "PANEL VERDICT"));

        // THE BRACKET IS NOW OPTIONAL AND THE CONTRACT SAYS SO. Pinned so it is not read as an oversight.
        Assert.True(TerminalToken.IsSatisfied("x\n\n* VERDICT: ALIGNED\n", "VERDICT:"));

        // REGRESSION GUARDS - the token must still LEAD the line.
        Assert.False(TerminalToken.IsSatisfied("x\n\nno [VERDICT: ...] was produced\n", "VERDICT:"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nTests are not GREEN\n", "GREEN"));
        Assert.False(TerminalToken.IsSatisfied("x\n\nlast line with no token\n", "VERDICT:"));
    }
```

⚠ **LITERALS ARE CORRECT HERE, unlike Task 1 — do not "fix" them.** Task 1 pins the CONTRACT and must
read the table; this pins the MATCHER across token SHAPES, including other disciplines' tokens.

- [ ] **Step 5: Run BOTH suites**

```bash
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Ls.Tests
cd "$(git rev-parse --show-toplevel)/clavity-dotnet" && dotnet test tests/Clavity.Integration.Tests
```
Expected: **`Total: 210`, 0 failed** (208 baseline + the two new `[Fact]`s from Steps 3 and 4) and
**`Total: 84`, 0 failed.** ⚠ **The integration suite is NOT CI-run**, which is exactly why a missed
literal there survives to the next session.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)" && git add clavity-dotnet/src/Clavity.Ls/TerminalToken.cs clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs clavity-dotnet/tests/Clavity.Ls.Tests/DisciplineContractTests.cs clavity-dotnet/tests/Clavity.Ls.Tests/TerminalTokenTests.cs clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "fix(s29a): store the enforced token, and treat a leading bracket as decoration"
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
- `FOLDED: the task checkpoints name a real oracle` — `Total: 208` was **indistinguishable from doing
  nothing**, since 208 is the untouched baseline. ⚠ **Task 2 legitimately still expects `Total: 208`**
  (it adds no test), so there the oracle is the NAMED TEST from Task 1, which fails before it. Task 3
  expects `Total: 210` — the two new `[Fact]`s are the only things that move the count.
- `FOLDED: Tasks 2 and 3 merged` — found while verifying the ruling, not by a seat: the contract and
  matcher changes leave the tree RED in **either** separated order, so they must be one commit.
- `REJECTED: no .gitmodules exists; git submodule status is empty` — the claim that
  `git rev-parse --show-toplevel` could return a submodule root here and break the `cd`.
- `DISCARDED-BELOW-FLOOR: every command block in this plan is fenced ` ```bash ` ` — the claim that the
  `$(...)` idiom fails under `cmd.exe`. True of `cmd.exe`, but an executor running these bash blocks in
  `cmd.exe` fails on the fences long before the subshell, so the idiom is not the reachable defect.

**Round 4:**

- `FOLDED: Tasks 2 and 3 SPLIT again` — the merge was over-broad and my justification for it was wrong.
  What cannot be split is Task 3's own contract/matcher halves; the panel token is independent.
  **MEASURED: Task 2 alone gives 208/208 and 84/84.** The seat proposed the horizontal split and was right.
- `FOLDED: DisciplineContractTests gains an invariant guard` — an **unstated invariant** was found: since
  only the LINE is stripped, no stored token may BEGIN with a stripped character, or it becomes
  unsatisfiable (a future `[NEW_VERDICT]` would be impossible to match). This is the real cost of storing
  the enforced token instead of normalising at runtime. It is now a mechanical test over
  `KnownDisciplines`, not a comment — a rule with no implementation is worse than no rule.
- `FOLDED: Task 3 Step 1 is now a COMMAND with counts` — 13 replacements across 4 files were specified as
  prose, which invites an executor to replace the wrong occurrence. Replaced with a loop that prints
  `before -> after` per file and a `STATE_MISMATCH` instruction if the numbers differ.
- `REJECTED: AgyAskIntegrationTests.cs:1468` — the claim that updating `expectTerminal` "neuters" the
  integration test and bypasses the bracket logic. **The fixture emits
  `"findings here\n\n[VERDICT: ALIGNED]"` and is NOT changed**, so with a bracketless expectation that
  test becomes the end-to-end PROOF that a bracketed reply survives the wiring. The seat assumed the
  fixture would change too. The plan now says explicitly that it must not.

**Round 5** — bespoke seats, because the standard palette was exhausted after four rounds:

- 🔴 `FOLDED: the counted command asserted FABRICATED numbers and halted the plan` — **the worst finding
  of the review, and it was mine.** Round 4's repair asserted `3` and `5` occurrences for the first two
  files **and labelled them MEASURED. They were not.** They came from a different grep pattern
  (`\[VERDICT:`, without the surrounding quotes) than the command actually runs
  (`"\[VERDICT:"`). **The real counts are `4` and `4`** — a comment and an `Assert` carry the literal too.
  Because the step tied a mandatory `STATE_MISMATCH` abort to those numbers, **the plan halted itself at
  Task 3 Step 1** — the same self-halting shape round 1 found, reintroduced by round 4's own fix.
  **The step now asserts `before > 0 && after == 0` per file and hardcodes no count**, because a count
  that drifts whenever someone writes a comment is not an oracle.
- `FOLDED: the invariant guard was decoupled from the thing it guards` — it hardcoded its own copy of the
  decoration set, so adding a character to `Decoration` would leave it silently not covering that
  character while still reading as an enforced invariant. `TerminalToken` now exposes
  `IsDecoration(char)` and the guard asks it. **PROVEN by a second mutant: with `'~'` added to
  `Decoration` and a token of `~VERDICT:`, the re-coupled guard FAILS — the hardcoded version could not
  have seen it.**
- `FOLDED: three stale folds contradicting each other` — `Total: 210` in Task 3 versus a "final: 209/209"
  in Review status (the latter measured the MERGED design); a closing line still asking about "a third
  round" after four had run; and a diffstat quoted as fact. **The diffstat is now removed rather than
  corrected** — volatile state in static prose rots on the next fold, so the stable FILE LIST is the size
  signal and git is the source for a real diffstat.
- `REJECTED: the echo prints `$f`, and the expected output listed basenames` — correct as stated, but it
  is subsumed: the fabricated counts were removed entirely, so there is no longer an expected output
  string to mismatch.

## Review status

⚠ **AGY-AFTER ROUNDS 1-5 COMPLETE — 17 folded, 8 rejected/discarded by measurement, 0 open.** R1: solo
panel (8 seats) + live escalation. R2: State Corruptor, Activation Auditor, Literal Implementer.
R3: Blindspot Auditor, Cascade Analyst, Boundary Smuggler. R4: Resource Vampire, plus Axiom Breaker and
Mechanism Gamer re-seated. **R5 exhausted the palette and used two BESPOKE seats** — Fold Consistency
Auditor and Executor Simulator — which the skill permits when the artifact needs a lens the palette does
not cover. **Every round produced a blocking finding, and rounds 2-5 each found theirs inside the
PREVIOUS round's repair.**

🔴 **THAT PATTERN IS THE ARTIFACT'S MOST IMPORTANT PROPERTY, AND IT IS NOT A SIGN THE PANEL IS PADDING.**
Three consecutive rounds found a real defect *in the fix the round before had just made*: a vacuous RED
arm, an incomplete cwd fold, a contract that lied about its own enforcement, and an over-broad merge.
**A fix is unreviewed code** — that is the whole reason this discipline re-runs after folding rather than
stopping at the first clean-looking draft.

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
test is assumed non-vacuous — each was watched failing first.

**Suite counts, reconciled after round 5 found them contradicting each other:** baseline **208** ·
after **Task 2** still **208** (it adds no test — its oracle is the NAMED test from Task 1) · after
**Task 3** **210** (the two new `[Fact]`s are the only things that move it) · `Clavity.Integration.Tests`
**84** throughout. ⚠ **An earlier "final: 209/209" was the dry-run of the MERGED design and no longer
describes this plan.**

**Reviewing version, recorded because this plan edits the discipline that reviews it (sequence spec,
"Risks"):** `adversarial-panel-review/SKILL.md` at repo HEAD **`42cfa84`**, 380 lines.

🔴 **THE ESCALATION ROUND WAS ITSELF FLAGGED `[13b] TRUNCATED REPLY`** — *"Treat this consult as
INCOMPLETE - do not fold findings from it"* — because it closed on `PANEL VERDICT: ...` while the table
still expects `GREEN`. The reply was complete and its echo passed. **This plan's own review is the second
measured instance of the defect it fixes, and the discarded findings included the vacuous-TDD defect that
would have halted execution.**

▶ **NOT YET EXECUTED. FIVE AGY-AFTER ROUNDS HAVE RUN**, each producing a blocking finding, and rounds
2-5 each found theirs inside the PREVIOUS round's repair. Every finding from all five carries a closed
AGY-SCOPE token; nothing sits open. **The hard round cap is 6, and whether to spend it is the owner's
call — this line must be updated by whoever answers that, not left to rot as it did after round 2.**
