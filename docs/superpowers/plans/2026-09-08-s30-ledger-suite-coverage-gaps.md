# §30 — Close two coverage gaps in the discipline-skills linter suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the linter suite catch two defects it is currently blind to — a ledger-owning discipline added to the linter but not to the test rosters, and a rogue early exit that would stop the linter after its first failure.

**Architecture:** Both gaps are the same shape as defects this repo has already closed elsewhere: a hand-maintained list with nothing reconciling it, and a loop whose continuation nothing asserts. 30a derives the roster from the linter's own `$ledgerFor` map instead of restating it; 30b adds one row that perturbs TWO skills and requires BOTH diagnostics. 30c is recorded as `DISCARDED-BELOW-FLOOR` with its reasoning, not silently dropped.

**Tech Stack:** PowerShell 7 (`pwsh`), Pester 5.

---

## Verified inputs (all read against HEAD before this plan was written)

🔴 **ROADMAP §30's line citations have ALL DRIFTED.** Verified and re-derived:

| §30 says | actually at |
|---|---|
| `Fail` at `check-agy-discipline-skills.ps1:76` | **`:10`** — `function Fail($msg) { Write-Error $msg -ErrorAction Continue; $script:fail = $true }` |
| rosters at `Tests.ps1:87,144` | **`:124`, `:152`, `:168`** |
| needles at `Tests.ps1:103,177` | the needle rows are the `-ForEach` block at **`:293`** |

**And 30a is BROADER than the section states.** It says the suite hardcodes "a two-element array".
There are **THREE** rosters, each repeating the same two entries verbatim:

```powershell
# Tests.ps1:124, :152, :168 - all three identical
    @{ skill = 'agy-capstone';   ledger = 'docs/agy-capstone-ledger.md' },
    @{ skill = 'agy-test-audit'; ledger = 'docs/agy-test-audit-ledger.md' }
```

The source of truth they mirror is `scripts/check-agy-discipline-skills.ps1:79-82`:

```powershell
$ledgerFor = @{
    'agy-capstone'   = 'docs/agy-capstone-ledger.md'
    'agy-test-audit' = 'docs/agy-test-audit-ledger.md'
}
```

🔴 **The linter's own comment at `:83-85` ASKS for the reconciliation that does not exist:** *"FAIL CLOSED
ON A TYPO. This map is keyed by discipline name and consulted with ContainsKey, so a misspelled key does
not error - it silently checks nothing... Reconcile it against the roster that is actually iterated."*

**The suite's fixture idiom, which both tasks must follow** (from the row at `:124`):

- `New-ScratchRoot` makes a scratch tree; `& $script:SkillPath $scratch $skill` returns the skill file.
- Perturb by **DELETION, never substitution** — the row's own comment records that a decoy marker made a
  guard keyed on the decoy pass 7/0. The fixture must differ from the real repo **by ABSENCE**.
- Assert the strip took effect BEFORE running the linter (`$body | Should -Not -Be $real`).
- `$LASTEXITCODE | Should -Be 1`, then match the needle with `[regex]::Escape(...)`.

## File Structure

- `scripts/tests/check-agy-discipline-skills.Tests.ps1` — replace three hardcoded rosters with one
  derived from the linter source (30a); add one two-skill row (30b).
- `clavity-dotnet/ROADMAP.md` — correct §30's drifted citations, record 30c's disposition.

---

### Task 1: 30a — derive the roster from `$ledgerFor` instead of restating it

**Files:**
- Modify: `scripts/tests/check-agy-discipline-skills.Tests.ps1` — `BeforeAll`, and the three `-ForEach`
  rosters at `:124`, `:152`, `:168`

- [ ] **Step 1: Write the row that pins the DERIVATION — not a self-comparison**

🔴 **THE OBVIOUS TEST HERE IS VACUOUS, AND I WROTE IT BEFORE CATCHING IT.** A row comparing "the roster
the tests use" against "the linter's keys" proves nothing once Step 3 derives the first FROM the second:
it compares a thing to itself and passes by construction. Once the roster is derived, coverage is
guaranteed by construction and needs no assertion — **what actually needs pinning is that the derivation
still finds something**, because a silently-empty parse is the failure that leaves the suite green.

Add this to `scripts/tests/check-agy-discipline-skills.Tests.ps1`:

```powershell
    It 'derives the ledger roster from the linter source, and the parse still finds the map' {
        # ROADMAP section 30a. The three rosters below are DERIVED from $ledgerFor rather than restating
        # it, so coverage of every ledger-owning discipline is structural - there is nothing left to
        # reconcile, and a row asserting "the roster covers the keys" would compare the parse to itself.
        #
        # What CAN still break is the parse: rename the variable, reformat the hashtable, or move it, and
        # the regex finds nothing. That yields an EMPTY roster, `-ForEach` discovers ZERO rows, and this
        # suite reports green having tested nothing. This row is the guard against that, and it names the
        # disciplines explicitly so an empty or truncated parse cannot satisfy it.
        $script:LedgerRoster.Count | Should -BeGreaterThan 1 -Because 'a zero-or-one roster silently disables the ledger rows it feeds'
        $script:LedgerRoster.skill | Should -Contain 'agy-capstone'
        $script:LedgerRoster.skill | Should -Contain 'agy-test-audit'
        # Every entry must carry a ledger path, or a half-parsed pair would feed a row with $null.
        foreach ($e in $script:LedgerRoster) {
            $e.ledger | Should -Match '^docs/.+-ledger\.md$' -Because "the parsed ledger for $($e.skill) must look like a ledger path, not a fragment"
        }
    }
```

- [ ] **Step 2: Run it and watch it FAIL**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: FAIL — `$script:LedgerRoster` does not exist yet, so `.Count` is `$null` and the first
assertion fails. The derivation arrives in Step 3.

- [ ] **Step 3: Derive the roster — in `BeforeDiscovery`, NOT `BeforeAll`**

🔴 **MEASURED 2026-09-08, and this is the whole reason this step is shaped the way it is.** Four variants
were run against Pester 5:

| form | rows discovered |
|---|---|
| `BeforeDiscovery { $roster = ... }` + `-ForEach $roster` (top level) | **2 — works** |
| `BeforeDiscovery { $roster = ... }` + `-ForEach $roster` (inside `Describe`) | **2 — works** |
| `BeforeAll { $script:roster = ... }` + `-ForEach $script:roster` | **0 — SILENTLY discovers nothing** |

`-ForEach` is evaluated during Pester's DISCOVERY phase; `BeforeAll` runs later, at RUN time, so the
variable is still `$null` when `-ForEach` reads it. **The suite does not error — it produces zero rows
and stays green**, which would silently delete all six ledger rows. That is the same silent-zero this
whole section is about, so it must not be introduced while fixing it.

**The roster is needed in BOTH phases**, so derive it twice, deliberately: `BeforeDiscovery` for the
`-ForEach` rosters (Task 1), and `BeforeAll` for the two-skill row's body (Task 2), which runs at run
time. Add a `BeforeDiscovery` block at the TOP of the file, before the outermost `Describe`:

```powershell
# PARSE THE LINTER'S MAP RATHER THAN RESTATING IT. ROADMAP section 30a. Reading the source is deliberate:
# dot-sourcing the linter would EXECUTE it, and it exits non-zero by design.
#
# THIS MUST BE BeforeDiscovery, NOT BeforeAll. MEASURED: `-ForEach` is evaluated at DISCOVERY, while
# BeforeAll runs at RUN time - a roster built there is $null when -ForEach reads it, and Pester then
# discovers ZERO rows WITHOUT erroring. The suite stays green having tested nothing.
BeforeDiscovery {
    $lintPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/check-agy-discipline-skills.ps1'
    $lintSrc  = [IO.File]::ReadAllText($lintPath)
    $mapBlock = [regex]::Match($lintSrc, '(?s)\$ledgerFor\s*=\s*@\{(.*?)\}')
    if (-not $mapBlock.Success) { throw 'section 30a: the $ledgerFor literal was not found - the roster would be empty and every ledger row would silently vanish' }
    $ledgerRoster = @(foreach ($m in [regex]::Matches($mapBlock.Groups[1].Value, "'([^']+)'\s*=\s*'([^']+)'")) {
        @{ skill = $m.Groups[1].Value; ledger = $m.Groups[2].Value }
    })
    if ($ledgerRoster.Count -lt 2) { throw "section 30a: parsed only $($ledgerRoster.Count) ledger discipline(s); a zero-or-one roster silently disables the rows it feeds" }
}
```

**`throw`, not `Should`,** because this runs at discovery where there is no test context to fail — a
`Should` here would not be reported as a failing row.

Then add the run-time copy inside the outermost `BeforeAll`, after `$script:Lint` is set:

```powershell
        # The RUN-TIME copy, for the two-skill row in Task 2. Same parse, different phase - see the
        # BeforeDiscovery block at the top of this file for why one cannot serve both.
        $mapBlockRun = [regex]::Match([IO.File]::ReadAllText($script:Lint), '(?s)\$ledgerFor\s*=\s*@\{(.*?)\}')
        $mapBlockRun.Success | Should -BeTrue -Because 'the $ledgerFor literal must be findable, or the two-skill row silently perturbs nothing'
        $script:LedgerRoster = @(foreach ($m in [regex]::Matches($mapBlockRun.Groups[1].Value, "'([^']+)'\s*=\s*'([^']+)'")) {
            @{ skill = $m.Groups[1].Value; ledger = $m.Groups[2].Value }
        })
        $script:LedgerKeys = @($script:LedgerRoster.skill)
        $script:LedgerRoster.Count | Should -BeGreaterThan 1 -Because 'the two-skill row needs at least two ledger-owning disciplines'
```

- [ ] **Step 4: Run it and watch it PASS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: the new row passes; the three hardcoded rows still pass unchanged.

- [ ] **Step 5: Replace all three hardcoded rosters**

In each of the three rows — `REJECTS <skill> when its ledger path is stripped`, `... when its ledger FILE
is absent`, `... when its ledger is a DIRECTORY rather than a file` — replace:

```powershell
        ) -ForEach @(
            @{ skill = 'agy-capstone';   ledger = 'docs/agy-capstone-ledger.md' },
            @{ skill = 'agy-test-audit'; ledger = 'docs/agy-test-audit-ledger.md' }
        ) {
```

with:

```powershell
        ) -ForEach $ledgerRoster {
```

⚠ **VERIFY THE ROW COUNT AFTER THIS CHANGE — three rows x two disciplines = SIX ledger rows, exactly as
before.** A miscount here is the silent-zero failure: `-ForEach` over an empty roster discovers nothing
and reports green. `$ledgerRoster` is the BeforeDiscovery variable from Step 3, with no `$script:`
prefix — that prefix is what made the measured variant discover zero rows.

- [ ] **Step 6: Prove the derivation is live, not decorative**

Temporarily add a third key to `$ledgerFor` in `scripts/check-agy-discipline-skills.ps1`:

```powershell
    'agy-first' = 'docs/agy-first-ledger.md'
```

Re-run the suite. Expected: the ledger rows now run for THREE disciplines and FAIL for `agy-first`
(no such ledger exists), proving the roster follows the map. Then
`git checkout -- scripts/check-agy-discipline-skills.ps1` and confirm the suite is green again.

- [ ] **Step 7: Commit**

```bash
git add scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "test(s30a): derive the ledger roster from the linter's map instead of restating it"
```

---

### Task 2: 30b — one row that proves the linter does not stop at the first failure

**Files:**
- Modify: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

**The gap:** every existing row perturbs exactly ONE skill. `Fail` at
`scripts/check-agy-discipline-skills.ps1:10` sets `$script:fail = $true` and returns, so the loop at
`:92` continues to the next skill. If someone replaced that with a `break`, the linter would report only
the FIRST failing skill — and every current row would still pass, because none has a second failure to
lose.

- [ ] **Step 1: Write the failing test**

```powershell
    It 'reports EVERY failing skill, not just the first (ROADMAP section 30b)' {
        # Each other row here perturbs ONE skill, so all of them are blind to an early exit: replace
        # Fail's `$script:fail = $true` with a `break` and the linter halts after the first failure while
        # every single-perturbation row stays green. This row breaks TWO skills and requires BOTH
        # diagnostics, which is the only shape that can see the difference.
        #
        # It uses the SAME two disciplines the ledger roster names, and deletes rather than substitutes,
        # for the reason recorded on the ledger rows: a fixture that INJECTS a decoy lets a guard keyed
        # on the decoy pass while proving nothing.
        $roster = @($script:LedgerRoster)
        $roster.Count | Should -BeGreaterThan 1 -Because 'this row needs at least two ledger-owning disciplines to perturb'

        $scratch = New-ScratchRoot
        try {
            foreach ($entry in $roster) {
                $target = & $script:SkillPath $scratch $entry.skill
                $real   = Get-Content -Raw $target
                $real.Contains($entry.ledger) | Should -BeTrue -Because "the fixture needs $($entry.ledger) present in $($entry.skill) before it can be removed"
                $body = $real.Replace($entry.ledger, '')
                $body | Should -Not -Be $real -Because "the strip must take effect for $($entry.skill)"
                Set-Content -Path $target -Value $body -NoNewline -Encoding utf8
            }

            $out = & $script:Lint -Root $scratch 2>&1
            $LASTEXITCODE | Should -Be 1
            $text = Get-LintText $out

            # THE ASSERTION IS THAT BOTH APPEAR. Asserting a COUNT would be weaker: a count is invariant
            # under reporting the same skill twice, which is exactly the confusion an early-exit bug
            # creates. Name each one.
            foreach ($entry in $roster) {
                $text | Should -Match ([regex]::Escape("never names '$($entry.ledger)'")) -Because "$($entry.skill) must be reported even when it is not the first failure"
            }
        }
        finally { Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run it and watch it PASS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: PASS — the linter today does continue past the first failure. This row pins that; it does not
fix a live defect.

- [ ] **Step 3: Prove it is not vacuous — this step IS the deliverable**

A row that passes on first write proves nothing until a mutant reddens it. In
`scripts/check-agy-discipline-skills.ps1:10`, replace:

```powershell
function Fail($msg) { Write-Error $msg -ErrorAction Continue; $script:fail = $true }
```

with a version that stops after the first failure:

```powershell
function Fail($msg) { Write-Error $msg -ErrorAction Continue; $script:fail = $true; $script:stopEarly = $true }
```

and add `if ($script:stopEarly) { break }` at the end of the `foreach ($skill in $skills)` body at `:92`.

Re-run the suite. Expected: **the new row goes RED and the single-perturbation rows stay GREEN** — which
is precisely the blindness this task exists to remove. Then
`git checkout -- scripts/check-agy-discipline-skills.ps1`, confirm `git diff` is empty for it, and re-run
to confirm green.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "test(s30b): pin that the linter reports every failing skill, not just the first"
```

---

### Task 3: Record 30c as discarded, and correct §30's drifted citations

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md:2506` and the §30 body

- [ ] **Step 1: Record the disposition and the corrections**

Rewrite the §30 header status to `▶ **30a + 30b SHIPPED <sha>; 30c DISCARDED-BELOW-FLOOR**` and add:

> **30c — `DISCARDED-BELOW-FLOOR`, ruled 2026-09-08 (owner, with the peer concurring).** The needles
> assert a message PREFIX, so truncating an explanatory suffix passes silently. The fix is worse than the
> gap: pinning suffixes is pinning prose verbatim, the anti-pattern this repo folded TWICE in the
> section-21 capstone because every rewording becomes a false RED. The section recorded that
> counter-argument against itself when it was promoted; nothing has changed it.
>
> 🔴 **CITATION CORRECTION.** All three of this section's line references had drifted by 2026-09-08:
> `Fail` is at `check-agy-discipline-skills.ps1:10`, not `:76`; the rosters are at
> `check-agy-discipline-skills.Tests.ps1:124, :152, :168`, not `:87,144`. **And 30a was understated —
> there were THREE identical hardcoded rosters, not one two-element array.**

- [ ] **Step 2: Verify the claims guard still passes**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-roadmap-claims.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(s30): 30c discarded below floor, and three drifted citations corrected"
```

---

## Closing the phase

- [ ] **Update the suite's test count**, because rows were added:

```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"
```

Take the discovered count and correct that suite's row in `scripts/tests/_partition.md`.
🔴 **A count is DERIVED — grepping the SUBJECT never finds a stale one. Grep the OLD NUMBER as a
literal.** This exact miss turned CI red on 2026-09-08.

- [ ] **Run the guard that reconciles counts and registration:**

```bash
pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"
```

Expected: 9/9.

- [ ] **Run every suite that touches the linter, derived by grep rather than memory:**

```bash
grep -rl 'check-agy-discipline-skills' scripts/tests/*.Tests.ps1
```
