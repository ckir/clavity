# Phase 1 — OUTPUT: the peer reply contract (§21) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the peer REPLY CONTRACT (§21) into the four AGY-* discipline skills, in the owner-fixed order, each step independently shippable and mechanically enforced by the existing discipline linter.

**Architecture:** Every change is contract TEXT in four `SKILL.md` files that exist as **byte-identical pairs** across `clavity-dotnet/plugin/skills/` and `clavity-classic/plugin/skills/` — so each edit touches **8 files**. Text alone is unenforced, so each step also adds an invariant to `scripts/check-agy-discipline-skills.ps1` and a **passing row plus a REJECTION row** to `scripts/tests/check-agy-discipline-skills.Tests.ps1`. That suite already stages a scratch root containing all four skills and perturbs exactly one, so its rejection rows are non-vacuity proofs by construction.

**Tech Stack:** Markdown contract text · PowerShell 7 (linter + Pester 6.1.0) · Python 3 (the citation checker) · `check-seed-artifacts-synced.sh` for pair parity.

---

## VERIFIED STATE — every anchor below was read at HEAD `b9aceb1` on 2026-09-02

Do not re-derive these; do re-check them if HEAD has moved.

| anchor | verified content |
|---|---|
| `scripts/check-peer-reply-citations.py:11-12` | `TEN_KEYS = ["seat","id","file","line","quoted_line","disposition","confidence","trigger","severity","detail"]` — hardcoded, includes `trigger` |
| `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md:156` | `A finding that survives disposition as a real \`defect\` is then CLASSED.` — the dangle: `defect` is **not** one of the five shipped disposition tokens |
| `clavity-dotnet/plugin/skills/agy-capstone/SKILL.md:358-360` | the five AGY-SCOPE tokens: `FOLDED`, `REJECTED`, `DISCARDED-BELOW-FLOOR`, `DEFERRED-TO-ANOMALIES`, `UNVERIFIED-ACCEPTED` |
| shared "What the driver reports back" block | `agy-capstone:49` · `agy-test-audit:45` · `agy-first:47` · `adversarial-panel-review:133` |
| pair parity | all four skills byte-identical across both plugins (`cmp` clean) |

**Line numbers drift. Anchor every edit on the QUOTED TEXT above, not on the number.** The spec that
produced this plan was itself burned once by citing an installed copy's numbering.

## File Structure

| file | responsibility | tasks |
|---|---|---|
| `{dotnet,classic}/plugin/skills/agy-capstone/SKILL.md` | capstone contract text | 1,2,3,4 |
| `{dotnet,classic}/plugin/skills/agy-test-audit/SKILL.md` | test-audit contract text | 1,3,4 |
| `{dotnet,classic}/plugin/skills/agy-first/SKILL.md` | consult contract text | 1,3 |
| `{dotnet,classic}/plugin/skills/adversarial-panel-review/SKILL.md` | panel contract text | 1,3 |
| `scripts/check-agy-discipline-skills.ps1` | the mechanical oracle for all of the above | 1,2,3,4 |
| `scripts/tests/check-agy-discipline-skills.Tests.ps1` | passing + REJECTION rows | 1,2,3,4 |
| `scripts/check-peer-reply-citations.py` | the citation reader | 4 |
| `scripts/tests/check-peer-reply-citations.Tests.ps1` | **CREATE** — the checker has no suite today | 4 |

---

### Task 1: §21 step 1 — the anti-wrap-up clause

Cheapest change, fixes a MEASURED loss (capstone rounds whose entire report was displaced by
"Standing by for your feedback"), and **independent of tasks 2-4**.

**Files:**
- Modify: all 8 `SKILL.md` files, in the paragraph beginning `**A flagged reply is INCOMPLETE, not empty.**`
- Modify: `scripts/check-agy-discipline-skills.ps1`
- Test: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

- [ ] **Step 1: Write the failing test**

Add to `scripts/tests/check-agy-discipline-skills.Tests.ps1`, inside `Describe 'check-agy-discipline-skills'`:

```powershell
    It 'REJECTS a skill whose closer omits the anti-wrap-up clause' {
        # NON-VACUITY BY CONSTRUCTION: the scratch root holds all four skills, so this fails on the
        # PERTURBED skill, never on a missing sibling. Perturb exactly one and require exit 1.
        $root = New-ScratchRoot
        $p = & $script:SkillPath $root 'agy-capstone'
        $txt = [IO.File]::ReadAllText($p)
        $mutated = $txt -replace '(?m)^Put nothing after the terminal token.*$', ''
        ($mutated -ne $txt) | Should -BeTrue -Because 'the mutant must actually apply, or this row proves nothing'
        [IO.File]::WriteAllText($p, $mutated)

        $out = & $script:Lint -Root $root 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'anti-wrap-up'
    }
```

- [ ] **Step 2: Run it and confirm it FAILS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: FAIL — the mutant precondition reds first (`the mutant must actually apply`), because no skill contains the clause yet.

- [ ] **Step 3: Add the clause to all EIGHT files**

Insert as a new paragraph immediately after the paragraph beginning `**A flagged reply is INCOMPLETE, not empty.**` in each of the four skills, then mirror to the classic half:

```markdown
**Put nothing after the terminal token.** The token must be the LAST thing in the reply - no summary, no
"standing by for your feedback", no offer of next steps. MEASURED: several rounds had their ENTIRE report
displaced by a closing pleasantry, because what the driver collects is the peer's FINAL message. A
terminal token alone does NOT fix this - every one of those rounds already demanded one.
```

- [ ] **Step 4: Add the invariant to the linter**

In `scripts/check-agy-discipline-skills.ps1`, alongside the existing per-skill invariants:

```powershell
    if ($text -notmatch '(?m)^\*\*Put nothing after the terminal token\.\*\*') {
        Write-Error "$skill : missing the anti-wrap-up clause (put nothing after the terminal token)"
        $failed = $true
    }
```

- [ ] **Step 5: Run the suite and the pair gate**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: all rows PASS, including the new rejection row.
Run: `bash scripts/check-seed-artifacts-synced.sh`
Expected: exit 0 — proves the classic half was mirrored.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/skills clavity-classic/plugin/skills scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "feat(skills): 21.1 - put nothing after the terminal token"
```

---

### Task 2: §21 step 2 — the peer-side table as `claim-type`, not "disposition"

`agy-capstone/SKILL.md:156` says a finding "survives **disposition** as a real `defect`" — but `defect`
is not one of the five shipped AGY-SCOPE disposition tokens. **Two different axes wear one word.** The
peer-side axis is what KIND of claim it is; the driver-side axis is what the driver DID with it.

**Files:**
- Modify: `{dotnet,classic}/plugin/skills/agy-capstone/SKILL.md` (the `:156` paragraph)
- Modify: `scripts/check-agy-discipline-skills.ps1`
- Test: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
    It 'REJECTS a capstone skill that uses "disposition" for the PEER-side axis' {
        $root = New-ScratchRoot
        $p = & $script:SkillPath $root 'agy-capstone'
        $txt = [IO.File]::ReadAllText($p)
        $mutated = $txt -replace 'survives its `claim-type` as a real', 'survives disposition as a real'
        ($mutated -ne $txt) | Should -BeTrue -Because 'the mutant must actually apply, or this row proves nothing'
        [IO.File]::WriteAllText($p, $mutated)

        $out = & $script:Lint -Root $root 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'claim-type'
    }
```

- [ ] **Step 2: Run it and confirm it FAILS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: FAIL at the mutant precondition — the target string does not exist yet.

- [ ] **Step 3: Fix the dangle in both halves**

Replace the sentence at `agy-capstone/SKILL.md:156`:

```markdown
A finding that survives its `claim-type` as a real `defect` is then CLASSED. **BLOCKING findings block GREEN;
```

and add, immediately above the existing severity table:

```markdown
**TWO AXES, ONE WORD - keep them apart.** `claim-type` is the PEER's axis: what KIND of claim this is -
`defect`, `by-design`, `out-of-scope`, `true-unsupported`, `already-known`. **`disposition` is the
DRIVER's axis** and is a closed five-token set defined below: `FOLDED`, `REJECTED`,
`DISCARDED-BELOW-FLOOR`, `DEFERRED-TO-ANOMALIES`, `UNVERIFIED-ACCEPTED`. `defect` is NOT a disposition,
which is exactly why calling the peer-side axis "disposition" dangled. `already-known` and
`out-of-scope` earned their place: both were used accurately across three audits.
```

- [ ] **Step 4: Add the invariant**

```powershell
    if ($skill -eq 'agy-capstone' -and $text -match '(?m)survives disposition as a real') {
        Write-Error "$skill : the PEER-side axis must be named claim-type, not disposition"
        $failed = $true
    }
```

- [ ] **Step 5: Run the suite and the pair gate**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"` → all PASS
Run: `bash scripts/check-seed-artifacts-synced.sh` → exit 0

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/skills clavity-classic/plugin/skills scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "feat(skills): 21.2 - the peer-side axis is claim-type, not disposition"
```

---

### Task 3: §21 step 3 — `confidence` as a POINTER, never authority

**MEASURED across four audits: `confidence` was WRONG 5 TIMES IN 14 CLAIMS.** Its value is real and
specific — it names which mutant to run. Its danger is that it reads as evidence.

**Files:**
- Modify: all 8 `SKILL.md` files (the reply-format section of each)
- Modify: `scripts/check-agy-discipline-skills.ps1`
- Test: `scripts/tests/check-agy-discipline-skills.Tests.ps1`

- [ ] **Step 1: Write the failing test**

```powershell
    It 'REJECTS a skill that ships confidence without its measured false rate' {
        $root = New-ScratchRoot
        $p = & $script:SkillPath $root 'agy-test-audit'
        $txt = [IO.File]::ReadAllText($p)
        $mutated = $txt -replace 'WRONG 5 TIMES IN 14 CLAIMS', 'sometimes wrong'
        ($mutated -ne $txt) | Should -BeTrue -Because 'the mutant must actually apply, or this row proves nothing'
        [IO.File]::WriteAllText($p, $mutated)

        $out = & $script:Lint -Root $root 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'false rate'
    }
```

- [ ] **Step 2: Run it and confirm it FAILS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"`
Expected: FAIL at the mutant precondition.

- [ ] **Step 3: Add the clause to all EIGHT files**

```markdown
**`confidence` IS A POINTER, NEVER AUTHORITY.** MEASURED across four audits: it was **WRONG 5 TIMES IN 14
CLAIMS**. It is still worth carrying, because it names WHICH MUTANT TO RUN - which is why every false
claim was cheap to kill. **A `measured` claim is ALWAYS re-run by the driver before folding; the label
buys the finding no credit whatsoever.** Phrase every trigger as a FALSIFIABLE PREDICTION - "removing X
leaves the suite green" - because that phrasing is what made all five refutations mechanical.
```

- [ ] **Step 4: Add the invariant**

```powershell
    if ($text -match '(?m)\bconfidence\b' -and $text -notmatch 'WRONG 5 TIMES IN 14 CLAIMS') {
        Write-Error "$skill : ships confidence without its measured false rate"
        $failed = $true
    }
```

- [ ] **Step 5: Run the suite and the pair gate**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output Detailed"` → all PASS
Run: `bash scripts/check-seed-artifacts-synced.sh` → exit 0

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/skills clavity-classic/plugin/skills scripts/check-agy-discipline-skills.ps1 scripts/tests/check-agy-discipline-skills.Tests.ps1
git commit -m "feat(skills): 21.3 - confidence is a pointer, with its measured false rate"
```

---

### Task 4: §21 step 4 — JSON INLINE, with a reader that validates a DECLARED schema

**Two hard conditions from the ROADMAP, plus one from the spec:**
1. it ships WITH a reader (else it is the "field no rule reads" this same skill forbids);
2. the reader MUST normalise non-ASCII (an em-dash arriving mangled already read as drift once);
3. **the reader validates against a schema each discipline DECLARES** — not a universal ten-key list.
   *Why not just loosen it:* "a parser that silently ignores schema drift cannot enforce a contract."
   A checker that accepts `missing_test` because it accepts everything has the same value as one that
   rejected it: neither is reading the citations.

**MEASURED, and this is the requirement's origin:** `check-peer-reply-citations.py:11-12` hardcodes
`TEN_KEYS` including `trigger`. The AGY-TEST-AUDIT brief used `missing_test` for that slot, every row
failed on SCHEMA, and **the citation check silently never ran** — while the brief asserted citations were
"checked mechanically". That is a False Safety Promise in our own instructions.

**Files:**
- Modify: `scripts/check-peer-reply-citations.py`
- Create: `scripts/tests/check-peer-reply-citations.Tests.ps1`
- Modify: `{dotnet,classic}/plugin/skills/agy-capstone/SKILL.md` and `.../agy-test-audit/SKILL.md`
- Modify: `justfile` (register the new suite) and `scripts/tests/_partition.md` (its runtimes row)

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/check-peer-reply-citations.Tests.ps1`:

```powershell
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Checker  = Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py'
    if (-not (Test-Path -LiteralPath $script:Checker -PathType Leaf)) {
        throw "checker not found at $script:Checker - this suite cannot run"
    }
    function New-Reply { param([string]$Json)
        $p = Join-Path ([IO.Path]::GetTempPath()) ("reply-" + [guid]::NewGuid() + ".json")
        [IO.File]::WriteAllText($p, $Json); $p
    }
}

Describe 'check-peer-reply-citations' {
    It 'accepts a DECLARED schema that is not the ten-key default' {
        # THE DEFECT THIS SUITE EXISTS FOR: a discipline declaring `missing_test` instead of `trigger`
        # had every row fail on SCHEMA, so the citation check silently never ran while the brief said
        # it had. A declared schema must be honoured; an undeclared key must still be rejected.
        $r = New-Reply '[{"schema":["seat","file","quoted_line","missing_test"],"seat":"1","file":"justfile","quoted_line":"test-scripts-fast:","missing_test":"x"}]'
        & python $script:Checker $r HEAD 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'REJECTS a row carrying a key the reply did not declare' {
        $r = New-Reply '[{"schema":["seat","file","quoted_line"],"seat":"1","file":"justfile","quoted_line":"test-scripts-fast:","smuggled":"x"}]'
        $out = & python $script:Checker $r HEAD 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'smuggled'
    }

    It 'normalises a mangled em-dash rather than reporting drift' {
        # An em-dash arriving mangled already read as drift once. Normalisation is a hard condition.
        $r = New-Reply '[{"schema":["seat","file","quoted_line"],"seat":"1","file":"justfile","quoted_line":"test-scripts-fast:"}]'
        & python $script:Checker $r HEAD 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
```

- [ ] **Step 2: Run it and confirm it FAILS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-peer-reply-citations.Tests.ps1 -Output Detailed"`
Expected: FAIL — the checker rejects every row on the hardcoded `TEN_KEYS`.

- [ ] **Step 3: Replace the hardcoded schema with a declared one**

In `scripts/check-peer-reply-citations.py`, replace the `TEN_KEYS` block:

```python
# A DECLARED schema, validated STRICTLY against that declaration. NOT a universal key list, and NOT a
# parser loose enough to swallow anything: "a parser that silently ignores schema drift cannot enforce a
# contract." Each row names its own `schema`; every other key must appear in it, and the three keys the
# checker itself reads are always required.
REQUIRED = ["file", "quoted_line"]

def row_schema(row, idx):
    declared = row.get("schema")
    if not isinstance(declared, list) or not declared:
        raise SystemExit("row %d: no `schema` declared - the contract requires each row to name its keys" % idx)
    for key in REQUIRED:
        if key not in declared:
            raise SystemExit("row %d: declared schema omits required key %r" % (idx, key))
    for key in row:
        if key != "schema" and key not in declared:
            raise SystemExit("row %d: key %r is not in the declared schema" % (idx, key))
    return declared
```

and normalise before comparing:

```python
import unicodedata

def norm(s):
    # Mangled non-ASCII already read as drift once. Compare on a normalised form so an em-dash that
    # survived a codepage round-trip does not masquerade as a citation that moved.
    return unicodedata.normalize("NFKC", s).replace("—", "-").replace("–", "-").strip()
```

- [ ] **Step 4: Run the suite to verify it passes**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-peer-reply-citations.Tests.ps1 -Output Detailed"`
Expected: 3 passed, 0 failed.

- [ ] **Step 5: Register the new suite — it will otherwise EXIST, PASS and NEVER RUN**

In `justfile`, append to the `test-scripts-fast` array literal:
`, 'scripts/tests/check-peer-reply-citations.Tests.ps1'`

In `scripts/tests/_partition.md`, add a row to the `## Measured runtimes` fenced block:
`check-peer-reply-citations.Tests.ps1          <measured>s    3 tests   <- FAST, added 2026-09-02`

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1"`
Expected: 9 passed. ⚠ **`git add` the new suite FIRST** — that gate reads TRACKED files, so an unstaged suite reads as a PHANTOM.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-peer-reply-citations.py scripts/tests/check-peer-reply-citations.Tests.ps1 justfile scripts/tests/_partition.md clavity-dotnet/plugin/skills clavity-classic/plugin/skills
git commit -m "feat(skills): 21.4 - JSON inline with a reader that validates a DECLARED schema"
```

---

### Task 5: the isolation round the ROADMAP explicitly asks for

> *"Also wanted: one deliberate round that OMITS the anti-wrap-up clause, because the clause is strongly
> SUPPORTED as the mechanism but not ISOLATED — the failing rounds differed from the probes in more than
> that one sentence."*

- [ ] **Step 1: Run one consult whose brief omits the clause, everything else held constant**
- [ ] **Step 2: Record whether the body was displaced, in `docs/agy-capstone-ledger.md`**
- [ ] **Step 3: If the clause is NOT isolated as the mechanism, say so in the ledger** — a supported-but-unisolated claim must not be written up as measured.

---

## §23 — NOT PLANNED HERE, AND THAT IS DELIBERATE

**§23 has an OPEN OWNER DESIGN FORK and cannot be planned to line level until it is ruled.** The ROADMAP
says so in terms: *"a ledger mirroring the capstone's, a completion gate that requires a row, or an
explicit accepted limitation that audited ranges are not tracked. That is a design fork and belongs to
the owner."* Writing line-level steps against an undecided fork is the exact failure the plan-vs-spec
discipline names, so this plan stops at the fork instead of inventing past it.

**Two things about §23 are already settled and must not be re-derived:**
- **Its original capture premise was FALSE.** The marker was never a coverage attestation — it is a nudge
  debounce, and `agy-test-audit/SKILL.md:313-314` specifies ambient `HEAD`.
- **The real defect is the ABSENT RECORD:** `docs/agy-capstone-ledger.md` exists and carries a range
  column; there is **no AGY-TEST-AUDIT ledger at all**, so audited ranges live only in per-topic memory.

**Before the fork goes to the owner, AGY-FIRST binds** — consult the peer, then present the owner BOTH
recommendations. That consult is the next action after Task 5.

---

## Discipline required for this change — not a quiet edit

All four skills ship in the installer payload, so by the capstone's own table any defect here is
**class 2 → BLOCKING**, across eight files in two byte-identical halves. The ROADMAP requires **panel,
then capstone** for this change. Do not skip to a quiet edit.

---

## SELF-AUDIT (run before handing over)

**Spec coverage.** §21 steps 1-4 → Tasks 1-4. The isolation round → Task 5. §23 → explicitly deferred to
an owner fork, with its two settled facts recorded so they are not re-derived. **No §21 requirement is
unmapped.**

**Placeholders.** One deliberate, and it is marked: `<measured>s` in Task 4 Step 5. It cannot be filled
before the suite exists — the timing discipline forbids inventing a figure, and `_partition.md` rows are
mechanically checked for a CURRENT test count but not for the time. Every other step carries real text.

**Type/name consistency.** `claim-type` (Task 2) is used identically in Tasks 2 and 4. `schema`,
`REQUIRED`, `row_schema`, `norm` (Task 4) are defined where first used. The five disposition tokens are
quoted identically in Task 2 and the verified-state table.

**Gaps — TWO CLOSED BY MEASUREMENT after the first audit pass, one genuinely open:**
1. ~~Where the clause lands in `adversarial-panel-review`.~~ **CLOSED, measured at HEAD `b9aceb1`:** all
   four skills carry the anchor paragraph `A flagged reply is INCOMPLETE, not empty.` -
   `agy-capstone:54` · `agy-test-audit:50` · `agy-first:52` · `adversarial-panel-review:138`. Anchoring
   on that quoted text works for all four; the differing line numbers do not matter.
2. ~~The linter's `-Root` parameter is assumed.~~ **CLOSED, measured:**
   `scripts/check-agy-discipline-skills.ps1:5-6` declares
   `param([string]$Root = (Split-Path -Parent $PSScriptRoot))`. The rejection rows' `-Root $root` is correct.
3. 🔴 **STILL OPEN, and it must not be forgotten: Task 4's third row is currently VACUOUS.** It asserts a
   plain ASCII quote, so it does not exercise the normalisation path at all - it would pass against a
   checker that never normalises anything. It cannot be written properly until the normalise path exists
   and its exact mangled form is known. **Resolved in Task 4 Step 4:** before marking that step done,
   replace the fixture with a genuinely mangled em-dash and prove the row RED against a checker with
   `norm()` removed. A row that cannot fail is the exact class this repository keeps paying for.
