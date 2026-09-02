# Phase 1 — OUTPUT: the peer reply contract (§21) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the peer REPLY CONTRACT (§21) into the four AGY-* discipline skills, in the owner-fixed
order, mechanically enforced by the existing discipline linter.

⚠ **NOT every step is independently shippable, and an earlier draft of this line claimed otherwise.**
Tasks 1, 2, 3 and 5 are. **Task 4 is NOT: it hardcodes `claim-type` in its schemas, which Task 2
introduces.** Shipping Task 4 first would have the checker reject 100% of replies still using the old
word - the same 100%-rejection failure mode the panel already caught once in this plan. **Execution
order: 1, 5, 2, 3, 4**, and the 2-before-4 edge is a hard dependency, not a preference.

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
        # THE ANCHOR IS `**Put`, NOT `Put`. MEASURED in the solo panel: '(?m)^Put nothing...' does NOT
        # match '**Put nothing...**' while the linter's '(?m)^\*\*Put...' does. THE TEST AND THE LINTER
        # MUST AGREE ABOUT THE SAME STRING or one of them is guarding nothing.
        $mutated = $txt -replace '(?m)^\*\*Put nothing after the terminal token\.\*\*.*$', ''
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

Insert as a new paragraph immediately after the paragraph beginning `**A flagged reply is INCOMPLETE, not empty.**` in each of the four skills, **then mirror to the classic half IN THE SAME COMMIT.**

🔴 **BOTH HALVES OR NEITHER - the pair gate is fail-closed.** `check-seed-artifacts-synced.sh`
compares the two plugin trees and reds the moment they diverge, and it runs on push. Editing the four
dotnet skills and committing before mirroring leaves the repository in a state that cannot be pushed,
and the failure surfaces as a sync error rather than as "you forgot the other half". Do all eight files,
then commit once.

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
        # WHITESPACE-TOLERANT. The clause is markdown and markdown WRAPS: the phrase currently sits
        # across a line break in the inserted text, so a literal-space match finds nothing. A matcher
        # that breaks when prose re-wraps is not a guard, it is a time bomb.
        $mutated = $txt -replace 'WRONG\s+5\s+TIMES\s+IN\s+14\s+CLAIMS', 'sometimes wrong'
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

Insert immediately after **Task 1's clause** (the paragraph beginning
`**Put nothing after the terminal token.**`), NOT after the `A flagged reply is INCOMPLETE` anchor.

⚠ Both clauses share a neighbourhood, so anchoring both on the SAME paragraph wedges this one BETWEEN
that anchor and Task 1's text - mechanically fine, and confusingly interleaved to read. Since the
execution order puts Task 1 first, its clause is already in the file and is the better anchor. Task 1 gave an anchor and this step did
not; an implementer with no anchor invents a location, which this plan's own "anchor on QUOTED TEXT"
rule forbids.

```markdown
**`confidence` IS A POINTER, NEVER AUTHORITY.**
MEASURED across four audits: it was **WRONG 5 TIMES IN 14 CLAIMS**. It is still worth carrying, because it names WHICH MUTANT TO RUN - which is why every false
claim was cheap to kill. **A `measured` claim is ALWAYS re-run by the driver before folding; the label
buys the finding no credit whatsoever.** Phrase every trigger as a FALSIFIABLE PREDICTION - "removing X
leaves the suite green" - because that phrasing is what made all five refutations mechanical.
```

- [ ] **Step 4: Add the invariant**

```powershell
    # UNCONDITIONAL, deliberately. Gating this on the skill already containing the word `confidence`
    # would (a) make the guard removable by deleting the very word it guards, and (b) treat a common
    # English noun as banned - a skill writing "answer with high confidence" would be ordered to paste
    # an unrelated statistical caveat. Every discipline skill carries the false rate, full stop.
    # WHITESPACE-TOLERANT, for the reason above: the clause wraps in the markdown, so a literal-space
    # match would red on a skill that CORRECTLY carries it - a guard failing closed against valid input.
    if ($text -notmatch 'WRONG\s+5\s+TIMES\s+IN\s+14\s+CLAIMS') {
        Write-Error "$skill : ships confidence without its measured false rate - add the POINTER clause"
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

🔴 **THE DISCIPLINE DECLARES THE SCHEMA - NOT THE REPLY.** The first draft had each ROW carry a
`schema` key, which puts the declaration in the hands of the party being checked: the peer declares
whatever keys it emitted and always passes. That is the "parser loose enough to swallow anything" the
spec explicitly ruled out - *"a parser that silently ignores schema drift cannot enforce a contract"* -
and it would have shipped a checker with the same value as the one it replaces. The declaration lives in
a registry the checker owns; the reply names only WHICH discipline it is.

Create `scripts/tests/check-peer-reply-citations.Tests.ps1`:

```powershell
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Checker  = Join-Path $script:RepoRoot 'scripts/check-peer-reply-citations.py'
    if (-not (Test-Path -LiteralPath $script:Checker -PathType Leaf)) {
        throw "checker not found at $script:Checker - this suite cannot run"
    }
    # NO EXISTING SUITE IN scripts/tests INVOKES PYTHON - measured 2026-09-02, this is the first.
    # A missing or Store-stub `python` must SKIP VISIBLY, never fail as though the checker were broken.
    $script:Py = (Get-Command python -ErrorAction SilentlyContinue)?.Source
    $script:Made = [System.Collections.Generic.List[string]]::new()
    function New-Reply { param([string]$Json)
        $p = Join-Path ([IO.Path]::GetTempPath()) ("reply-" + [guid]::NewGuid() + ".json")
        [IO.File]::WriteAllText($p, $Json); $script:Made.Add($p); $p
    }
}

# EVERY fixture is tracked and removed. Without this the suite abandons a JSON file per row per run,
# forever, on every developer box and every CI runner.
AfterAll { foreach ($f in $script:Made) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }

Describe 'check-peer-reply-citations' {
    BeforeEach {
        if (-not $script:Py) {
            Set-ItResult -Skipped -Because 'python is not on PATH, so the checker cannot be exercised here'
        }
    }

    It 'accepts a reply whose keys match the DISCIPLINE-declared schema' {
        $r = New-Reply '[{"file":"justfile","quoted_line":"test-scripts-fast:","missing_test":"x"}]'
        & $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }

    It 'REJECTS a key the discipline did not declare - the peer cannot widen its own contract' {
        $r = New-Reply '[{"file":"justfile","quoted_line":"test-scripts-fast:","smuggled":"x"}]'
        $out = & $script:Py $script:Checker $r HEAD 'agy-test-audit' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'smuggled'
    }

    It 'REJECTS an unknown discipline rather than defaulting to permissive' {
        $r = New-Reply '[{"file":"justfile","quoted_line":"x"}]'
        $out = & $script:Py $script:Checker $r HEAD 'not-a-discipline' 2>&1
        $LASTEXITCODE | Should -Be 1
        ($out -join "`n") | Should -Match 'not-a-discipline'
    }

    It 'reports EVERY bad row, not just the first' {
        # A checker that aborts on row 1 hides all citation drift after it - the same silent-drop shape
        # as the TEN_KEYS bug this replaces, just relocated.
        # UNDECLARED KEYS, deliberately. An earlier fixture used only VALID keys, so it exercised the
        # citation-resolution path and never entered the schema validator at all - the row would have
        # passed with check_row_schema still aborting on its first error, which is the exact behaviour
        # it claims to disprove. A test must enter the code it names.
        $r = New-Reply '[{"file":"justfile","quoted_line":"x","smuggled_one":"a"},{"file":"justfile","quoted_line":"y","smuggled_two":"b"}]'
        $out = ((& $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1) -join "`n")
        $LASTEXITCODE | Should -Be 1
        $out | Should -Match 'smuggled_one'
        $out | Should -Match 'smuggled_two' -Because 'aborting on the first bad row hides every later one'
    }

    It 'resolves a citation whose only difference is a MANGLED EM-DASH' {
        # THE NORMALISATION ROW. An earlier draft demanded this row be proven non-vacuous while never
        # actually writing it - the plan referred to a row that did not exist. It must cite a real line
        # that CONTAINS an em-dash and present it mangled; a plain-ASCII fixture would pass against a
        # checker that normalises nothing, which is the vacuity this whole phase is about.
        # Pick the citation from a file that genuinely carries one, and prove the row RED by deleting
        # norm()'s dash replacement before marking Step 4 done.
        $r = New-Reply '[{"file":"clavity-dotnet/ROADMAP.md","quoted_line":"<a real line containing an em-dash, with the dash mangled>"}]'
        & $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0 -Because 'normalisation must absorb a mangled dash rather than call it drift'
    }

    It 'PRESERVES leading indentation - an indented citation must still resolve' {
        # norm() deliberately does NOT flatten leading whitespace: doing so would make every indented
        # citation unresolvable, trading one false-drift class for a larger one.
        $r = New-Reply '[{"file":"justfile","quoted_line":"    pwsh -NoProfile -c \"Invoke-Pester"}]'
        & $script:Py $script:Checker $r HEAD 'agy-capstone' 2>&1 | Out-Null
        $LASTEXITCODE | Should -Be 0
    }
}
```

- [ ] **Step 2: Run it and confirm it FAILS**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-peer-reply-citations.Tests.ps1 -Output Detailed"`
Expected: FAIL — the checker rejects every row on the hardcoded `TEN_KEYS` and knows nothing of `discipline`.

- [ ] **Step 3: Replace the hardcoded schema with a DISCIPLINE-OWNED registry**

In `scripts/check-peer-reply-citations.py`, replace the `TEN_KEYS` block:

```python
import unicodedata

# THE CHECKER OWNS THE DECLARATION, and the DRIVER names the discipline on the COMMAND LINE.
# THE DRIVER NAMES THE DISCIPLINE, THE PEER DOES NOT. Requiring a "discipline" key inside each reply row
# would reject every reply from a peer that was never told to emit it - strict-looking and useless. The
# driver already knows which discipline it just ran.
#   usage: python check-peer-reply-citations.py <reply.json> <sha> <discipline>
SCHEMAS = {
    "agy-capstone":   ["seat", "id", "file", "line", "quoted_line",
                       "claim-type", "confidence", "trigger", "severity", "detail"],
    "agy-test-audit": ["seat", "id", "file", "line", "quoted_line",
                       "claim-type", "confidence", "missing_test", "severity", "detail"],
    "agy-first":      ["seat", "file", "line", "quoted_line", "claim-type", "confidence", "detail"],
    "adversarial-panel-review": ["seat", "file", "line", "quoted_line",
                                 "claim-type", "confidence", "detail"],
}
REQUIRED = ["file", "quoted_line"]

def norm(s):
    """Normalise for COMPARISON ONLY, and apply it to BOTH sides or it is worse than nothing.
    Mangled non-ASCII already read as citation drift once. Leading indentation is PRESERVED: flattening
    it would make every indented citation - a YAML key, a nested block, a PowerShell row - unresolvable,
    trading one false-drift class for a larger one. Only trailing whitespace is dropped."""
    s = unicodedata.normalize("NFKC", s)
    for dash in ("—", "–", "−"):
        s = s.replace(dash, "-")
    return s.rstrip()

def check_row_schema(row, idx, declared, problems):
    """Validate ONE row strictly against the discipline's declared keys. COLLECTS rather than aborts: a
    checker that exits on the first bad row hides every later citation, which is the same silent-drop
    failure as the hardcoded key list it replaces."""
    for key in REQUIRED:
        if key not in row:
            problems.append("row %d: missing required key %r" % (idx, key))
    for key in row:
        if key not in declared:
            problems.append("row %d: key %r is not declared for this discipline" % (idx, key))

# WIRING. Defining the helpers without calling them would leave the script crashing on the old constant
# this block replaces - the definitions below are not optional scaffolding.
reply_path, sha, discipline = sys.argv[1], sys.argv[2], sys.argv[3]
if discipline not in SCHEMAS:
    raise SystemExit("unknown discipline %r - add it to SCHEMAS deliberately" % discipline)
declared = SCHEMAS[discipline]
rows = json.load(io.open(reply_path, encoding="utf-8"))

problems = []
for idx, row in enumerate(rows, 1):
    check_row_schema(row, idx, declared, problems)
    claimed = norm(row["quoted_line"])
    blob = subprocess.run(["git", "show", "%s:%s" % (sha, row["file"])],
                          capture_output=True, text=True, encoding="utf-8")
    if blob.returncode != 0:
        problems.append("row %d: cannot read %s at %s" % (idx, row["file"], sha))
        continue
    # LOCATE BY CONTENT, NOT BY LINE NUMBER. The contract treats line numbers as untrusted - a peer
    # reading a diff computes them from hunk headers and gets them wrong - so the quoted text is the
    # citation and the driver finds it.
    if not any(norm(line) == claimed for line in blob.stdout.split("
")):
        problems.append("row %d: quoted_line not found in %s at %s: %r"
                        % (idx, row["file"], sha, row["quoted_line"]))
for msg in problems:
    print(msg)
raise SystemExit(1 if problems else 0)
```

⚠ **`claim-type` appears in every schema above. It is defined by Task 2** — do Task 2 before Task 4, or
the checker declares a key the contract does not yet name.

- [ ] **Step 4: Run the suite to verify it passes, then PROVE the normalisation row can fail**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-peer-reply-citations.Tests.ps1 -Output Detailed"`
Expected: 6 passed, 0 failed.

🔴 **THEN PROVE THE NORMALISATION ROW CAN FAIL.** The row now exists (`resolves a citation whose only
difference is a MANGLED EM-DASH`), but a row that exists is not a row that bites. Fill its placeholder
with a REAL line from a file that genuinely contains an em-dash, presented mangled; then delete `norm()`'s
dash replacement and confirm **that specific row** goes red - **then RESTORE it and re-run before you
commit.** The plan previously said to break `norm()` and never said to put it back; a literal
implementer commits the crippled checker. Every mutation in this plan is temporary: break, observe red,
restore, observe green, and only then commit. A normalisation row asserted against plain
ASCII passes against a checker that normalises nothing — the exact class this repository keeps paying
for, and it may not ship unproven.

- [ ] **Step 5: Register the new suite — it will otherwise EXIST, PASS and NEVER RUN**

🔴 **DECIDE THE HALF BEFORE EDITING, and the default is SLOW.** The fast half measured **493-550s
against a 600s cap** and already took `gitignore-policy.Tests.ps1` (+6,6s) earlier the same day. This
plan adds a SECOND suite. Two additions to a half at 92% of a hard cap, neither of them re-measured, is
how a gate starts timing out - and the failure mode is a red CI run that looks like a broken test.
**Measure the suite solo first (Step 4 above gives you the figure), then:** if the fast half has not
been re-measured since 2026-09-02, put this suite in `test-scripts-slow` and say so in the row. The slow
half is backgrounded and past the cap already, so it absorbs the cost; the fast half has no headroom to
spend. Moving it later is one line; a cap breach costs a CI cycle to diagnose.

In `justfile`, append to the chosen recipe's array literal:
`, 'scripts/tests/check-peer-reply-citations.Tests.ps1'`

In `scripts/tests/_partition.md`, add a row to the `## Measured runtimes` fenced block:
`check-peer-reply-citations.Tests.ps1          <measured>s    6 tests   <- <FAST|SLOW>, added 2026-09-02`

⚠ **SIX, not three - and the count is mechanically enforced.** The suite grew from 3 rows to 6 during
review and this figure went stale with it. `test-suite-registration.Tests.ps1` re-runs Pester discovery
per suite and compares the COUNT, so a stale number reds the gate. **Count the `It` blocks you actually
wrote, do not copy this figure.**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1"`
Expected: 9 passed. ⚠ **`git add` the new suite FIRST** — that gate reads TRACKED files, so an unstaged suite reads as a PHANTOM.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-peer-reply-citations.py scripts/tests/check-peer-reply-citations.Tests.ps1 justfile scripts/tests/_partition.md clavity-dotnet/plugin/skills clavity-classic/plugin/skills
git commit -m "feat(skills): 21.4 - JSON inline with a reader that validates a DECLARED schema"
```

---

### Task 5: the isolation round the ROADMAP explicitly asks for

🔴 **RUN THIS IMMEDIATELY AFTER TASK 1. NOT AT THE END.** The task numbering is not the execution order
here, and following it literally destroys the experiment. Task 5 proves isolation by sending a brief that
differs from a recent successful round **by one paragraph only**. If Tasks 2, 3 and 4 merge first, HEAD
also carries the `claim-type` axis, the `confidence` pointer clause and the JSON schema rules - so the
brief differs from the baseline in FOUR ways and isolates nothing. **Execution order is 1, 5, 2, 3, 4.**

> *"Also wanted: one deliberate round that OMITS the anti-wrap-up clause, because the clause is strongly
> SUPPORTED as the mechanism but not ISOLATED — the failing rounds differed from the probes in more than
> that one sentence."*

- [ ] **Step 1: Snapshot, then run one consult whose brief omits the clause and is otherwise identical**

```bash
git status --short > /tmp/panel-before.txt   # the envelope check every consult owes
```
**Run BOTH conditions here, back to back. Task 5 generates its own baseline.**

1. Send a brief WITH the clause (the post-Task-1 norm). Record whether the body arrived inline.
2. Send the same brief with the anti-wrap-up paragraph deleted, and nothing else changed. Record the same.

🔴 **THIS REPLACED A TEMPORAL PARADOX I INTRODUCED WHILE FIXING SOMETHING ELSE.** The previous
wording demanded a baseline from "a recent successful round run AFTER Task 1 shipped" - while the
execution order says to run Task 5 IMMEDIATELY after Task 1, when no such round exists yet. Generating
both arms inside the task removes the dependency on history entirely, and is a better experiment anyway:
the two arms are minutes apart on one peer version rather than compared across an unknown gap.

🔴 **THE BASELINE ERA IS THE WHOLE EXPERIMENT, and "a recent successful round" is ambiguous
without it.** Every round before Task 1 also lacked the clause, so deleting it from a pre-Task-1 baseline
changes nothing and the run measures noise. The comparison that isolates is: rounds WITH the clause
(post-Task-1, the new normal) against this one deliberate round WITHOUT it. Changing anything else destroys the isolation this task exists to establish.

- [ ] **Step 2: Record the OUTCOME and the FIELD, not an impression**

The mechanism is displacement, not truncation, so record `AnswerTruncated` explicitly — it was `false`
on all four earlier probes, and reading it is what distinguished the two. Note whether the body arrived
inline or only a receipt did.

- [ ] **Step 3: Write the result into `docs/agy-capstone-ledger.md`, including a negative one**

If the body arrives intact WITHOUT the clause, the clause is **not** isolated as the mechanism and the
ledger must say exactly that. A supported-but-unisolated claim written up as measured is the failure
this whole phase exists to remove — n=1 either way is a datum, not a proof, and the row must say which.

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

## WHAT THESE GUARDS DO NOT PROVE — state it, or the plan ships a False Safety Promise

**Tasks 1-3 prove that contract TEXT SHIPS. They do not prove the peer OBEYS it.** Task 4 is different in
kind, and the first draft of this section wrongly swept it in: a checker that reads the peer's ACTUAL
reply and rejects an undeclared key is a post-execution OBEDIENCE check - the only one in this phase.
That gap is inherent — the discipline is best-effort prompt-discipline, not a sandbox — but it must be
written down, because §21 exists precisely to remove a False Safety Promise from our own instructions and
would be a poor place to introduce a fresh one. The only evidence of obedience is a measured round, which
is what Task 5 is for and why it is not optional.

## Panel round 1 - dispositions (AGY-AFTER, 2026-09-02)

Solo floor (10 seats) + agy escalation (`code-reviewer` subagent, 10 seats). **16 findings, 15 FOLDED,
1 REJECTED by measurement.** Verdict of the escalation round: `REQUEST CHANGES`.

- `FOLDED: the mutant regex could not match the clause it perturbs` - '^Put' vs '**Put'; test and linter
  disagreed about one string, so Task 1 could never have passed.
- `FOLDED: the confidence invariant was conditional on the word it guards` - removable by deletion, and
  it also treated a common English noun as banned. Now unconditional.
- `FOLDED: the reply declared its own schema` - the peer declaring what it may emit always passes. Moved
  to a checker-owned registry.
- `FOLDED: the checker required a "discipline" key no task ever tells the peer to emit` - it would have
  rejected 100% of real replies while looking strict. The driver now names the discipline on the CLI.
- `FOLDED: check_row_schema was defined and never called` - replacing the old constant would have left
  the script crashing on a deleted name.
- `FOLDED: norm() flattened leading indentation` - every indented citation would become unresolvable,
  trading one false-drift class for a larger one. Only trailing whitespace is dropped now.
- `FOLDED: the checker aborted on the first bad row` - hiding all later drift, the same silent-drop shape
  as the bug it replaces.
- `FOLDED: Step 4 demanded proof of a normalisation row that was never written` - the row now exists.
- `FOLDED: Task 5's isolation is destroyed by any task merging before it` - execution order is 1, 5, 2, 3, 4.
- `FOLDED: Task 3 Step 3 had no insertion anchor` while Task 1 did.
- `FOLDED: the "guards prove text, not obedience" claim was too broad` - Task 4 IS an obedience check.
- `FOLDED: the Pester suite leaked a temp file per row per run` - AfterAll now removes them.
- `FOLDED: a second suite was going into a cap-adjacent half unmeasured` - defaults to slow.
- `FOLDED: no suite had ever invoked python` - the new one skips visibly when it is absent.
- `FOLDED: the plan named no execution order for its own tasks` - now stated explicitly.
- 🔴 `REJECTED: "Set-ItResult was removed entirely in Pester 5+, so the skip will crash CI"` - **FALSE,
  killed by measurement.** `Get-Command Set-ItResult` resolves from Pester 6.1.0, and
  `scripts/tests/check-plugin-drift.Tests.ps1:370` ships a row using it that passed 18/18 the same day.

⚠ **A defect this round found in the REVIEW, not the artifact.** The first fold pass reported success on
a replacement that silently did not apply, because the script asserted nothing - so a commit message
claimed a fix that was not in the tree. Root cause, measured: backslash escapes were mangled in transit
(`` arrived as a backspace byte), so the anchor could never match. **Every fold in this plan is now
applied under a hard assertion, and one by line surgery rather than string replace.** The lesson is the
one the repository already knows and it was violated while folding a finding about exactly it: a mutation
that is not asserted did not happen.

## Panel round 2 - dispositions (AGY-AFTER, 2026-09-02)

Rotation added **State Corruptor** (dropped in round 1) and a bespoke **Execution Order Auditor**,
because round 1 REWROTE the execution order and nothing had reviewed the rewrite. **9 findings, 9 FOLDED,
0 refuted.** Six seats returned "no new findings" WITH an explicit statement of what they did not examine.
Escalation verdict: `REQUEST CHANGES`.

- `FOLDED: the inserted clause WRAPS across a newline while the linter and mutant match a contiguous
  string` - MEASURED: the phrase sits across lines 242-243 and both matchers searched for it with literal
  spaces, so the linter would have RED on a skill that correctly carries the clause. Both matchers are now
  whitespace-tolerant AND the phrase is kept unwrapped: a guard that breaks when prose re-wraps is a time
  bomb, so fixing only one side would have left it armed.
- `FOLDED: Step 4 told the implementer to break norm() and never to restore it` - MEASURED: the word
  "restore" appeared ZERO times in the plan. A literal implementer commits the crippled checker.
- `FOLDED: a temporal paradox I introduced while fixing something else` - the order says run Task 5
  immediately after Task 1, while Task 5 demanded a baseline from a round run AFTER Task 1 shipped. Task 5
  now generates BOTH arms itself, which removes the dependency on history and is a better experiment.
- `FOLDED: the Goal claimed every step is independently shippable; Task 4 is not` - it hardcodes
  `claim-type`, which Task 2 introduces. Shipping 4 before 2 rejects 100% of replies still using the old
  word - the same failure mode the panel caught once already in this plan.
- `FOLDED: the _partition.md row said 3 tests; the suite has 6` - the suite doubled during review and the
  figure went stale. That count is mechanically enforced by re-running discovery, so it reds the gate.
- `FOLDED: the "reports EVERY bad row" test never entered the code it names` - its fixture used only
  DECLARED keys, so it exercised citation resolution, not the schema validator. It would have passed with
  the abort-on-first-error behaviour it claims to disprove. Fixture now carries undeclared keys.
- `FOLDED: both plugin halves must be committed together` - the pair gate is fail-closed and runs on push.
- `FOLDED: Task 5's baseline era was ambiguous` - superseded by the both-arms design above.
- `FOLDED: Task 3 anchored on the same paragraph as Task 1` - interleaving the two clauses. Now anchored
  after Task 1's clause.

⚠ **Two of round 2's findings were defects round 1's FOLDS introduced** (the temporal paradox, and the
line-wrap that arrived with the clause text). That is the documented reason to re-run a round after
folding: a fix spawns its own edges.

## Stand-downs

- `DISCARDED-BELOW-FLOOR: untrusted 'file' value in a reply row reaching the filesystem` — the checker
  resolves citations through `git show <sha>:<path>`, which is repo-scoped by construction, so a
  traversal-shaped value cannot escape the object database. Reachable only as a confusing error, never as
  a read outside the repo.
- `DISCARDED-BELOW-FLOOR: the anti-wrap-up clause could be pasted anywhere in a 429-line skill and still
  satisfy its invariant` — position is unenforced, but the clause is peer-facing instruction text that is
  read whole rather than executed at a location, so a correct paste at the wrong offset changes nothing
  the peer does. Re-raise if the linter ever gains a position check for any other clause.

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
