# Branch T - tracker format, its gate, and the test-infrastructure closures Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every tracked work item one machine-checkable status line, enforce it with a gate, teach agents the format, normalise the four trackers once, and close the test-infrastructure items (§34, the Pester temp leak, §56, §36, §77) so Branch T leaves nothing of its own open.

**Architecture:** A new sibling gate `scripts/check-tracker-status.ps1` (own fixture suite) owns the format; `scripts/check-roadmap-claims.ps1` gains a Check C for `path:N` pointers (§77). One canonical `docs/tracker-format.md` carries a marked excerpt that three skills in both plugins repeat; a parity script pins them. Test hygiene is one shared helper `scripts/tests/TestTemp.ps1` (null-safe removal for §34 + one shared temp root with a 24 h sweep) and a Pester gate forbidding direct `GetTempPath()` use outside a named exemption list.

**Tech Stack:** PowerShell 7 + Pester 6 (gates, suites), bash (hooks, seed-sync), one-off Python (normalisation script, kept in the session scratchpad), `just`, GitHub Actions.

**Branch:** `sweep/branch-t-format-and-gates` (HEAD at plan time `c1e92abd`). Spec: `docs/superpowers/specs/2026-10-08-final-sweep-sequence-design.md` (sections "The tracker format - decided 2026-10-08", "Owner batch ruling on the third inventory"). Consult record: seam `.clavity/seams/branch-t-plan-agy-first.md`, replies `.clavity/scratch/branch-t-plan/reply.md`, `reply-2.md`, `reply-3.md` (envelope intact after all three).

---

## Decisions this plan carries (owner-approved or agy+driver agreed; re-open only with a measurement)

| Fork | Decision | Source |
|---|---|---|
| 1 §36 | `clavity-dotnet/justfile` `test` runs BOTH projects; `ci-dotnet.yml` calls `just test`. **MEASURED CORRECTION (2026-10-08): NO workflow in `.github/workflows/` installs or runs `just` today** (the earlier claim "ci-dotnet is the only one without just" was wrong). The CI half is therefore a first-ever `just` in CI and is isolated as the LAST task (Task 9) so the owner can drop it without touching the rest. | owner chose (b); correction surfaced at handoff |
| 2 §77 | Check C: `path:N` / `path:N-M` pointers range-checked; opt-in anchor `` `file:N` ("quoted text") `` verified on line N (or within N..M). Content drift of un-anchored pointers stays unchecked and is stated in the script header. | agy+driver agreed |
| 3 temp | ONE shared root `%TEMP%/clavity-tests/`, a 24 h sweep of that root, a gate forbidding direct `GetTempPath()` / `$env:TEMP` / `$env:TMP` in suites, migrate ALL suites in this branch, with a NAMED exemption list (reason per entry) for the two `.testbak` sites. | owner asked for a common scope; agy+driver agreed after negotiation (reply-3); **awaits owner confirmation at handoff** |
| 4 §56 | A never-audited roster doc renders as `## <doc> - AUDIT-NEVER (claims inspected: 0)` (em dash, as the hook regex needs), so `docs-audit-reminder.sh:33` counts it unchanged; `Get-FindingsSummary` gains `NeverAudited`. | agy+driver agreed |
| 5 gate scope | ONE parser shape for every entry of every tracker incl. numbered items 0-13; strikethrough removed (`KILLED` carries it). | agy withdrew its carve-out |
| 6 evidence | ROADMAP-file entries closed by ruling need a `- **<id> ...` bullet under "Non-goals / accepted limitations" in `clavity-dotnet/ROADMAP.md`; standalone-file entries (backlog stub, fix-the-tool) carry their own `**Reopen if:**` line. | agy+driver agreed |
| tracker 4 | `agy-autotrain/ROADMAP.md` (`## AT-1`, `## AT-2`) is a fourth tracker, inside the gate. | measured; spec had not named it |

## Measured facts the tasks rely on (all re-measured 2026-10-08 on `c1e92abd`; Task 0 re-checks them)

- `scripts/check-roadmap-claims.ps1` is 267 lines: Check A `:90`, Check B `:173-234`, closure regex `:179` (`SHIPPED|RULED|OWNER ACCEPTED|CLOSED`), sha regex `:196`. Its suite has a row (`check-roadmap-claims.Tests.ps1:389`) that runs it against the REAL ROADMAP, so any new check inside that script turns that row red until the real ROADMAP satisfies it.
- `clavity-dotnet/ROADMAP.md`: 65 `### §N` headings (§14..§78), 14 numbered `### N.` items (0..13), `## Non-goals / accepted limitations` at line 3996 (7 `- **§` bullets from step 0). 144 backticked `path:N` pointers (§77).
- 19 backlog stubs (`docs/backlog/*.md`, status at line 3); 14 fix-the-tool entries plus `README.md`, `_template.md`, `DRY-RUN-2026-07-11.md` (`agy-autotrain/docs/fix-the-tool-backlog/`, frontmatter `status:`; values today: 6 open, 3 fixed-in-repo, 4 released, 1 wont-fix; only 1 of the 7 fixed/released entries carries `fixed-by:`); `review-relay/ROADMAP.md` (D1, D2, R1); `agy-autotrain/ROADMAP.md` (AT-1, AT-2).
- No script parses the fix-the-tool `status:` value (grep of `scripts/`, `agy-autotrain/scripts`); stale prose about the enum lives in `agy-autotrain/docs/fix-the-tool-backlog/_template.md:6`, `docs/backlog-triage-runbook.md:104,:276`, `docs/coverage-debt.md` boundary H (line 454).
- §34: 96 `$x = New-...; $y = New-...` allocation lines immediately before `try {` in 10 files: agy-liveness-check 18, agy-anomaly-capture-reminder 11, agy-anomaly-reminder 18, agy-discipline-reaching 13, agy-anomaly-dispatch-reminder 12, agy-anomaly-model-notice 10, agy-drive-session-reset 6, agy-after-reminder 4, agy-anomaly-contract-stamp 3, hook-spawn-budget 1 (the last is outside the ROADMAP's nine). All 10 dot-source `scripts/tests/BashHookHelpers.ps1`. **MEASURED in pwsh 7: `Remove-Item $null,$b -Recurse -Force -ErrorAction SilentlyContinue` THROWS `ParameterBindingValidationException`, and so does `Remove-Item @()`.** So the ROADMAP's own fix shape (init to `$null`, allocate inside `try`) would make the `finally` throw; removal must filter nulls and skip an empty set.
- Temp: 58 suites touch `GetTempPath()` / `$env:TEMP` directly, 27 clean up, 31 of the 58 dot-source `BashHookHelpers.ps1`. The driver's `%TEMP%` holds 30 765 directories (top: `asrt` 2159, `anom-cap-home` 707, `anom-cap-ws` 648, `clavity-store` 393, `dar` 389, `ns-clean` 246). `assertion-strength-reminder.Tests.ps1:73` and `docs-audit-reminder.Tests.ps1:11` create directories and never remove them (the only `Remove-Item` in the first is on env vars). `check-seed-artifacts-synced.Tests.ps1:104` and `:168` park a tracked file at a fixed temp name and restore it in `finally` (a sweep would destroy it; a kill mid-test leaves the tracked file missing).
- §56: `Render-FindingsView` (`docs-audit-lib.ps1:152`) and `Get-FindingsSummary` (`:180`) ignore roster docs absent from the store; the hook regex is `^## .+ — AUDIT-` (`.claude/hooks/docs-audit-reminder.sh:33`). The ROADMAP's claim that a `NEVER AUDITED` header matches it is false.
- Registration: a new suite must be in the `justfile` `test-scripts-fast` or `-slow` explicit list (`test-suite-registration.Tests.ps1`), have a row in `scripts/tests/_partition.md`; a new top-level script needs a row in `scripts/README.md` (`scripts-readme-inventory.Tests.ps1`). `check-seed-artifacts-synced.sh` discovery-walks plugin hooks/skills/knowledge and requires dotnet == classic byte-identity for the three skills edited here.

## Dry-run record (2026-10-08, scratch copies under the session scratchpad, nothing in the repo touched)

The plan's own code blocks were extracted by script and RUN: (1) the gate + its suite: first run `11 passed / 14 failed`, three real defects found and folded into the blocks above - a child pwsh's redirected stdout is decoded with the OEM code page so the section sign arrives as 0x15 and breaks Pester's NUnit export (tests now decode as UTF-8); `Read-Lines -Required` was described but not implemented (only the dotnet ROADMAP is mandatory); a struck-through `### ~~1. T~~` heading never matched the heading regex, so it was silently not an entry; `-List` printed no title - after the folds `Tests Passed: 25, Failed: 0`. (2) `TestTemp.ps1` + its suite: `Tests Passed: 10, Failed: 0`. (3) Check C applied to a copy of `check-roadmap-claims.ps1` and its suite: `Tests Passed: 34, Failed: 0`; against the real ROADMAP: 0 OUT-OF-RANGE, 71 not checkable. (4) The gate against the real, un-normalised repo: 103 NO-STATUS, 79 HEADING-STATUS, 8 BAD-TOKEN - the size of Task 4. (5) The discipline gate's regex against the real suites: 58 suites / 222 lines (independently reproduces the earlier 58). **Not dry-run** (stated, not hidden): the normalisation script (written at execution, oracle = the gate), the parity script, the §56 edits, the 58-suite migration, Task 9.
Known limits of the temp gate, recorded rather than hidden: it sees `GetTempPath()` / `$env:TEMP` / `$env:TMP` in PowerShell, not a `mktemp -d` inside a bash string (`agy-consult-guard.Tests.ps1:860`, `agy-shield-lib.Tests.ps1`'s shims) nor a `$env:TMPDIR` assigned from an already-routed path - those write inside child processes or under the routed root.

## File structure

| File | Responsibility |
|---|---|
| `docs/tracker-format.md` (create) | The canonical format: status line, tokens, evidence rules, per-tracker shapes, the marked excerpt. |
| `scripts/check-tracker-status.ps1` (create) | The gate: refuses malformed/evidence-less entries in the four trackers; `-List` prints open-partition items. |
| `scripts/tests/check-tracker-status.Tests.ps1` (create) | Fixture suite for the gate + the real-repo row (added last). |
| `scripts/check-tracker-format-excerpt.ps1` (create) | Parity: the excerpt block in `docs/tracker-format.md` == the block in each of 6 skill files. |
| `scripts/tests/check-tracker-format-excerpt.Tests.ps1` (create) | Its suite. |
| `scripts/check-roadmap-claims.ps1` (modify) | Check C (pointers, §77). |
| `scripts/tests/TestTemp.ps1` (create) | `Remove-TestPath`, `Get-TestTempRoot`, `New-TestTempPath`, `Invoke-TestTempSweep`. |
| `scripts/tests/TestTemp.Tests.ps1` (create) | Its suite. |
| `scripts/tests/test-temp-discipline.Tests.ps1` (create) | Gate: no direct temp use outside `TestTemp.ps1` + exemption table. |
| `scripts/tests/BashHookHelpers.ps1` (modify) | Dot-sources `TestTemp.ps1`; its `New-TempRepo` uses the shared root. |
| 10 hook suites + ~48 other suites (modify) | §34 shape; shared temp root. |
| `scripts/docs-audit-lib.ps1`, `scripts/docs-audit.ps1` (modify) | §56. |
| `clavity-dotnet/justfile`, `.github/workflows/ci-dotnet.yml` (modify) | §36. |
| `clavity-dotnet/ROADMAP.md`, `docs/backlog/*.md`, `agy-autotrain/docs/fix-the-tool-backlog/*.md`, `review-relay/ROADMAP.md`, `agy-autotrain/ROADMAP.md` (modify) | One-time normalisation. |
| `docs/superpowers/plans/2026-10-08-branch-t-normalisation-table.tsv` (create, already generated) | The per-entry decided token table (120 rows; 5 JUDGE rows go to the owner first). |

## Dispatch rules for implementer subagents (CLAUDE.md rule 4; paste into EVERY dispatch)

- **Step 0, state verification:** open each target file and confirm the context quoted in the task (line numbers, the quoted lines) matches reality BEFORE editing; on a mismatch STOP and report `STATE_MISMATCH: <what>`; do not adapt.
- **Shape-divergence stop:** if making code work would change the shape, type or encoding of any value in the pasted code (a status-line regex, an exit code, an output token, a file's LF line endings), STOP and report `[original] -> [yours] because <reason>`. "It compiles/passes" is not a justification.
- **Oracle:** the named test is the oracle; if a value looks wrong the oracle wins - surface the conflict, never edit the test to match the code. Tests in Tasks 1-8 are written FIRST in the task: "tests are already written - implement until they pass".
- **No elided enumerations:** every list in a task is complete; never extend or invent one.
- **Gates as they are:** use the exact commands below; do not add flags.
- **Tiers:** Tasks 5 and 6 per-file edits = Sonnet (error-cost: weakened tests pass silently). Task 4's script, Tasks 1-3, 7-9 = Sonnet. The driver (Opus) runs every measurement, the normalisation apply, and all timing figures; subagents never time anything.
- **Never** `git add -A` or `git add .`; stage explicit paths; never commit `.clavity/`. Commit trailer: exactly the `Co-Authored-By:` line the session's current attribution reminder gives (it changes between sessions; do not copy one from this plan).

---

### Task 0: Re-measure the premises (driver, no edits)

**Files:** none.

- [ ] **Step 1: Re-run the premise measurements**

Run (bash):
```bash
cd /c/Users/user/Development/Rust/clavity
git rev-parse --abbrev-ref HEAD; git status --short
grep -c '^### §' clavity-dotnet/ROADMAP.md           # expect 65
grep -cE '^### (~~)?[0-9]+\. ' clavity-dotnet/ROADMAP.md   # expect 14
ls docs/backlog/*.md | wc -l                          # expect 19
grep -n '^## Non-goals' clavity-dotnet/ROADMAP.md     # expect 3996
grep -rn 'just ' .github/workflows/*.yml | grep -v '#' | head   # expect: no run/uses of just
pwsh -NoProfile -c '$a=$null; $b=Join-Path $env:TEMP "nope-xyz"; try { Remove-Item $a,$b -Recurse -Force -ErrorAction SilentlyContinue; "no throw" } catch { "THREW " + $_.Exception.GetType().Name }'   # expect THREW ParameterBindingValidationException
```
Expected: branch `sweep/branch-t-format-and-gates`; only `AIBridgeWeb/ FIX.md TODO.md` untracked; the counts above. Any difference: STOP and re-plan the affected task.

- [ ] **Step 2: Stage the generated table and commit with this plan**

```bash
git add -f docs/superpowers/plans/2026-10-08-branch-t-tracker-format-and-gates.md docs/superpowers/plans/2026-10-08-branch-t-normalisation-table.tsv
git commit -m "docs(plan): Branch T - tracker format, gates, and test-infrastructure closures"
```

---

### Task 1: The canonical format file and the gate (tests first)

**Files:**
- Create: `docs/tracker-format.md`, `scripts/check-tracker-status.ps1`, `scripts/tests/check-tracker-status.Tests.ps1`
- Modify: `justfile` (fast list + new recipe), `scripts/README.md` (row), `scripts/tests/_partition.md` (row)

- [ ] **Step 1: Write `docs/tracker-format.md`**

```markdown
# Tracker entry format

Every tracked work item - a `clavity-dotnet/ROADMAP.md` section, a `docs/backlog/*.md` stub, an
`agy-autotrain/docs/fix-the-tool-backlog/*.md` entry, a `review-relay/ROADMAP.md` item, an
`agy-autotrain/ROADMAP.md` item - has ONE current status in ONE fixed place, enforced by
`scripts/check-tracker-status.ps1` (`just check-tracker-status`).

<!-- tracker-format:begin -->
**Writing a tracker entry** (full rules: `docs/tracker-format.md`): the heading is the TITLE ONLY; the next non-blank line is `**Status:** <TOKEN> <YYYY-MM-DD> - <one line>`. TOKEN is one of OPEN, SCHEDULED, IMPLEMENTED (open) or SHIPPED (cite a commit sha), CLOSED-BY-RULING (a ROADMAP entry needs a Non-goals bullet; a stub needs a `**Reopen if:**` line), KILLED (state why). Never put a status in the heading; an open sub-item gets its own entry. `just check-tracker-status` enforces this.
<!-- tracker-format:end -->

## The status line
`**Status:** <TOKEN> <YYYY-MM-DD> - <one line>` - the date is the date of that status; the one line is a
sentence, not history. History goes in the body; when a status changes, the line is REPLACED and the old
line is kept in the body (`> **Previous status:** ...`).

## Tokens (one closed set for every tracker)
| Partition | Token | Meaning | Evidence the gate requires |
|---|---|---|---|
| open | `OPEN` | real, not yet scheduled | none |
| open | `SCHEDULED` | has an owner branch or slot | none |
| open | `IMPLEMENTED` | built on an UNMERGED branch | none |
| closed | `SHIPPED` | merged to `main` | a backticked 7-40 hex commit sha on the status line that exists in the repository |
| closed | `CLOSED-BY-RULING` | an accepted limitation, with a reopen condition | ROADMAP file: a `- **<id> ...` bullet under "Non-goals / accepted limitations"; standalone file: a `**Reopen if:**` line in the entry |
| closed | `KILLED` | will not be done | a reason of at least 12 characters after the dash |

Release is NOT a status. When a release ships an item, add ONE line directly under the status line:
`**Released:** clavity-v<N>`. Only `SHIPPED` may carry it.
A docs-only closure cites the sha of the commit that made it true (the code commit, or for a ruling use
`CLOSED-BY-RULING`, which needs no sha).

## Per-tracker shapes
- `clavity-dotnet/ROADMAP.md`: `### §N - Title` or `### N. Title` (legacy numbered items 0-13); ids are `§N` / `item N`.
- `review-relay/ROADMAP.md`: `### D1 - Title`, `### R1 - Title`; `agy-autotrain/ROADMAP.md`: `## AT-1 - Title`.
- `docs/backlog/*.md`: line 1 `# Title`; the status line is the next non-blank line. Id = file name.
- fix-the-tool entries: frontmatter keys instead of a line - `status: <TOKEN>`; `SHIPPED` needs `fixed-by: <sha, ...>` and
  `fixed-on: <date>` (and `released-in: clavity-vN` once released); `KILLED` needs `reason: <text>`; `CLOSED-BY-RULING` needs
  a `**Reopen if:**` line in the body.
- The heading never carries a status marker (no check mark, arrow, `~~` strike-through, red circle, or status word after the title).

## What the gate can and cannot see
It checks that a cited sha EXISTS in the repository, not that it is the commit that did the work (a real but unrelated sha passes);
that a Non-goals bullet or `**Reopen if:**` line EXISTS, not that its reasoning is sound; and that a pointer is in range (and, if
anchored, that its quoted text is on the line), not that an un-anchored pointer still means what it did. Review and the capstone
carry those; the gate removes the failure where nothing was recorded at all.
- An open sub-item (a lettered paragraph, a "Fork 2") is NOT allowed inside a closed entry: it becomes its own entry titled
  "... (formerly <old id>)".
```

- [ ] **Step 2: Write the failing suite `scripts/tests/check-tracker-status.Tests.ps1`**

```powershell
# Fixture repos under $TestDrive for scripts/check-tracker-status.ps1. The real repository is exercised by
# exactly one row, added LAST (Task 4 step 9), once the trackers are normalised.
BeforeAll {
    $script:Script = Join-Path $PSScriptRoot '..' 'check-tracker-status.ps1'
    if (-not (Test-Path -LiteralPath $script:Script -PathType Leaf)) { throw "check-tracker-status.ps1 not found at $script:Script - this suite cannot run" }
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath

    function New-TrackerRepo {
        # $Files: hashtable of repo-relative path -> content. Always a real git repo with one commit, so a cited sha exists.
        # clavity-dotnet/ROADMAP.md is the one MANDATORY tracker, so every fixture gets an empty one unless it supplies its own
        # or passes -NoRoadmap (the row that proves a deleted tracker does not read green).
        param([hashtable]$Files = @{}, [switch]$NoRoadmap)
        if (-not $NoRoadmap -and -not $Files.ContainsKey('clavity-dotnet/ROADMAP.md')) {
            $Files = $Files.Clone(); $Files['clavity-dotnet/ROADMAP.md'] = "# R`n`n## Non-goals / accepted limitations`n"
        }
        $repo = Join-Path $TestDrive ('tr-' + [Guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $repo -Force
        & git -C $repo init -q
        & git -C $repo config user.email 't@t.t'; & git -C $repo config user.name 'T'; & git -C $repo config core.autocrlf false
        [IO.File]::WriteAllText((Join-Path $repo 'seed.txt'), "x`n")
        foreach ($rel in $Files.Keys) {
            $p = Join-Path $repo ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
            $null = New-Item -ItemType Directory -Path (Split-Path $p -Parent) -Force
            [IO.File]::WriteAllText($p, $Files[$rel])
        }
        & git -C $repo add -A; & git -C $repo commit -q -m fixture
        [pscustomobject]@{ Root = $repo; Sha = ((& git -C $repo rev-parse HEAD) | Select-Object -First 1).Trim() }
    }
    function Invoke-Gate {
        param([string]$Root, [switch]$List)
        $a = @('-NoProfile', '-File', $script:Script, '-RepoRoot', $Root); if ($List) { $a += '-List' }
        # MEASURED in the dry run: a child pwsh's redirected stdout is decoded with the console's OEM code page, in which
        # the section sign (0xA7) arrives as 0x15 - which then makes Pester's own NUnit export throw on a failure message.
        # Decode the child as UTF-8 for the duration of the call.
        $prev = [Console]::OutputEncoding
        try { [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); $out = & pwsh @a 2>&1 | Out-String; $code = $LASTEXITCODE }
        finally { [Console]::OutputEncoding = $prev }
        [pscustomobject]@{ Out = $out; Code = $code }
    }
    $script:RM = 'clavity-dotnet/ROADMAP.md'
    function Roadmap([string]$Entries, [string]$NonGoals = '') {
        "# R`n`n$Entries`n`n## Non-goals / accepted limitations`n`n$NonGoals`n"
    }
}

Describe 'check-tracker-status.ps1 - ROADMAP entries' {
    It 'exits 0 for a well-formed OPEN entry' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — Title`n`n**Status:** OPEN 2026-10-08 - not yet scheduled`n`nbody") }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'refuses an entry with no status line' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — Title`n`nbody only") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-STATUS.*§1'
    }
    It 'refuses a token outside the closed set' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** DONE 2026-10-08 - x`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'BAD-TOKEN.*DONE'
    }
    It 'refuses a malformed date' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** OPEN 2026-13-45 - x`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'BAD-DATE.*§1'
    }
    It 'refuses a heading that carries a status marker' -ForEach @(
        @{ H = '### §1 — T — ✅ SHIPPED' }, @{ H = '### §1 — T ▶ PROMOTED' }, @{ H = '### ~~1. T~~' }, @{ H = '### §1 — T · 🚫 KILLED' }) {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "$H`n`n**Status:** OPEN 2026-10-08 - x`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'HEADING-STATUS'
    }
    It 'accepts a status word INSIDE a title that has no marker glyph' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — The SHIPPED flag is wrong`n`n**Status:** OPEN 2026-10-08 - x`n") }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'requires a sha on SHIPPED, and the sha must exist' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-SHA.*§1'
        $g = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done in ``deadbee```n") }
        $r2 = Invoke-Gate $g.Root; $r2.Code | Should -Be 1; $r2.Out | Should -Match 'PHANTOM.*deadbee'
    }
    It 'accepts SHIPPED with an existing sha, and an optional Released line' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done")  }
        $sha = $f.Sha.Substring(0, 10)
        [IO.File]::WriteAllText((Join-Path $f.Root $script:RM), (Roadmap "### §1 — T`n`n**Status:** SHIPPED 2026-10-08 - done in ``$sha```n**Released:** clavity-v24`n"))
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'refuses a Released line on a non-SHIPPED entry' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** OPEN 2026-10-08 - x`n**Released:** clavity-v24`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'RELEASED-ON-UNSHIPPED'
    }
    It 'requires a Non-goals bullet for CLOSED-BY-RULING, and matches the id exactly (§1 is not §10)' {
        $body = "### §1 — T`n`n**Status:** CLOSED-BY-RULING 2026-10-08 - accepted`n"
        $f = New-TrackerRepo @{ $script:RM = (Roadmap $body) }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-NONGOALS.*§1'
        $g = New-TrackerRepo @{ $script:RM = (Roadmap $body "- **§10 - other** (closed by ruling)") }
        (Invoke-Gate $g.Root).Code | Should -Be 1   # the distractor
        $h = New-TrackerRepo @{ $script:RM = (Roadmap $body "- **§1 - T** (closed by ruling)") }
        (Invoke-Gate $h.Root).Code | Should -Be 0
    }
    It 'requires a reason of 12+ characters on KILLED' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** KILLED 2026-10-08 - no`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-REASON.*§1'
    }
    It 'checks numbered legacy items with the same shape' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### 7. Legacy item`n`nbody`n") }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-STATUS.*item 7'
    }
    It 'rejects a status line that is not the NEXT non-blank line (an earlier prose line hides it)' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`nSome prose first.`n**Status:** OPEN 2026-10-08 - x`n") }
        (Invoke-Gate $f.Root).Code | Should -Be 1
    }
    It 'does not read "###" lines inside a fenced code block as entries' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — T`n`n**Status:** OPEN 2026-10-08 - x`n`n``````text`n### §2 — not an entry`n```````n") }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
}

Describe 'check-tracker-status.ps1 - standalone files' {
    It 'accepts a backlog stub whose status line is the next non-blank line after the title' {
        $f = New-TrackerRepo @{ 'docs/backlog/a.md' = "# Title`n`n**Status:** OPEN 2026-10-08 - x`n" }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'requires **Reopen if:** for a stub CLOSED-BY-RULING' {
        $f = New-TrackerRepo @{ 'docs/backlog/a.md' = "# Title`n`n**Status:** CLOSED-BY-RULING 2026-10-08 - accepted`n" }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-REOPEN.*a\.md'
        $g = New-TrackerRepo @{ 'docs/backlog/a.md' = "# Title`n`n**Status:** CLOSED-BY-RULING 2026-10-08 - accepted`n`n**Reopen if:** it recurs`n" }
        (Invoke-Gate $g.Root).Code | Should -Be 0
    }
    It 'checks fix-the-tool frontmatter: token set, SHIPPED needs fixed-by with an existing sha' {
        $d = 'agy-autotrain/docs/fix-the-tool-backlog'
        $f = New-TrackerRepo @{ "$d/x.md" = "---`nslug: x`nstatus: fixed-in-repo`n---`nbody`n" }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'BAD-TOKEN.*fixed-in-repo'
        $g = New-TrackerRepo @{ "$d/x.md" = "---`nslug: x`nstatus: SHIPPED`n---`nbody`n" }
        $r2 = Invoke-Gate $g.Root; $r2.Code | Should -Be 1; $r2.Out | Should -Match 'NO-SHA.*x\.md'
    }
    It 'skips README.md and _template.md in the fix-the-tool directory' {
        $d = 'agy-autotrain/docs/fix-the-tool-backlog'
        $f = New-TrackerRepo @{ "$d/README.md" = "no frontmatter`n"; "$d/_template.md" = "---`nstatus: OPEN`n---`n" }
        (Invoke-Gate $f.Root).Code | Should -Be 0
    }
    It 'checks review-relay D/R items and agy-autotrain AT items' {
        $f = New-TrackerRepo @{ 'review-relay/ROADMAP.md' = "## Open decisions`n`n### D1 - T`n`nno status`n" }
        $r = Invoke-Gate $f.Root; $r.Code | Should -Be 1; $r.Out | Should -Match 'NO-STATUS.*D1'
        $g = New-TrackerRepo @{ 'agy-autotrain/ROADMAP.md' = "## AT-1 - T`n`nno status`n" }
        (Invoke-Gate $g.Root).Code | Should -Be 1
    }
}

Describe 'check-tracker-status.ps1 - list mode and run errors' {
    It '-List prints every open-partition entry with its tracker and exits 0, and prints no closed one' {
        $f = New-TrackerRepo @{ $script:RM = (Roadmap "### §1 — Open one`n`n**Status:** SCHEDULED 2026-10-08 - branch C`n`n### §2 — Done one`n`n**Status:** KILLED 2026-10-08 - will not be done`n") }
        $r = Invoke-Gate $f.Root -List
        $r.Code | Should -Be 0
        $r.Out | Should -Match 'SCHEDULED.*§1.*Open one'
        $r.Out | Should -Not -Match '§2'
    }
    It 'exits 2 when the repository root is not a git repository' {
        $d = Join-Path $TestDrive 'nogit'; $null = New-Item -ItemType Directory -Path $d -Force
        (Invoke-Gate $d).Code | Should -Be 2
    }
    It 'reports the missing MANDATORY tracker (the dotnet ROADMAP) as a failure, not a pass' {
        $f = New-TrackerRepo @{ 'docs/backlog/a.md' = "# T`n`n**Status:** OPEN 2026-10-08 - x`n" } -NoRoadmap
        $r = Invoke-Gate $f.Root
        $r.Out | Should -Match 'clavity-dotnet/ROADMAP\.md'
        $r.Code | Should -Be 1
    }
}
```
- [ ] **Step 3: Run it red**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-tracker-status.Tests.ps1 -Output Detailed -CI"`
Expected: the BeforeAll throws `check-tracker-status.ps1 not found` (suite red).

- [ ] **Step 4: Write `scripts/check-tracker-status.ps1`**

```powershell
#!/usr/bin/env pwsh
# Enforces docs/tracker-format.md over every tracked work item. EXIT: 0 clean · 1 at least one violation ·
# 2 the RUN could not start (not a git repository / git missing). -List prints the open-partition items
# (exit 0) - the end-of-sweep Done check runs it.
# Trackers: clavity-dotnet/ROADMAP.md, review-relay/ROADMAP.md, agy-autotrain/ROADMAP.md (heading entries),
# docs/backlog/*.md (stubs), agy-autotrain/docs/fix-the-tool-backlog/*.md (frontmatter).
[CmdletBinding()]
param([string]$RepoRoot, [switch]$List)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host 'check-tracker-status: git is not on PATH - nothing was checked' -ForegroundColor Yellow; exit 2 }
& git -C $RepoRoot rev-parse --git-dir *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "check-tracker-status: '$RepoRoot' is not a git repository - nothing was checked" -ForegroundColor Yellow; exit 2 }

$OpenTokens   = @('OPEN', 'SCHEDULED', 'IMPLEMENTED')
$ClosedTokens = @('SHIPPED', 'CLOSED-BY-RULING', 'KILLED')
$StatusRe  = [regex]'^\*\*Status:\*\* (?<tok>\S+) (?<date>\d{4}-\d{2}-\d{2}) - (?<text>\S.*)$'
$ShaRe     = [regex]'`(?<sha>[0-9a-fA-F]{7,40})`'
$ReleasedRe = [regex]'^\*\*Released:\*\* clavity-v\d+$'
# A status MARKER in a heading. Words alone are allowed (a title may say "the SHIPPED flag"); glyphs and strike-through are not.
$HeadingMarkRe = [regex]'(✅|▶|🚫|🔴|⚠|~~|\s[—·-]\s*(SHIPPED|FIXED|CLOSED|KILLED|PROMOTED|SCHEDULED|OPEN)\b)'
$isShallow = ((& git -C $RepoRoot rev-parse --is-shallow-repository 2>$null) -join '').Trim() -eq 'true'
$problems = [System.Collections.Generic.List[string]]::new()
$entries  = [System.Collections.Generic.List[object]]::new()

function Read-Lines([string]$Rel, [switch]$Required) {
    $p = Join-Path $RepoRoot ($Rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        # Only clavity-dotnet/ROADMAP.md is mandatory; the other trackers are checked when present (a deleted MANDATORY one must not read green).
        if ($Required) { $script:problems.Add("MISSING-TRACKER  $Rel is not a readable file - nothing in it was checked") }
        return $null
    }
    return ([IO.File]::ReadAllText($p) -split "`r?`n")
}
function Test-Sha([string]$Sha, [string]$Where) {
    if ($script:isShallow) { return }
    & git -C $RepoRoot cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) { $script:problems.Add("PHANTOM  $Where  ``$Sha`` does not exist in this repository") }
}
function Test-Entry {
    # $Tok/$Date/$Text parsed from the status line; $Block = the entry's lines (for Reopen-if); $NonGoals = ROADMAP bullets.
    param([string]$Tracker, [string]$Id, [string]$Where, $M, [string[]]$Block, [string[]]$NextLines, [string[]]$NonGoals, [string]$Kind, [string]$Title = '')
    $tok = $M.Groups['tok'].Value
    if (($OpenTokens + $ClosedTokens) -notcontains $tok) { $problems.Add("BAD-TOKEN  $Where  '$tok' is not one of: $(($OpenTokens + $ClosedTokens) -join ', ')"); return }
    $d = [datetime]::MinValue
    if (-not [datetime]::TryParseExact($M.Groups['date'].Value, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { $problems.Add("BAD-DATE  $Where  '$($M.Groups['date'].Value)' is not a calendar date"); return }
    $text = $M.Groups['text'].Value
    switch ($tok) {
        'SHIPPED' {
            $shas = @($ShaRe.Matches($text))
            if ($shas.Count -eq 0) { $problems.Add("NO-SHA  $Where  SHIPPED needs a backticked commit sha on the status line") }
            foreach ($s in $shas) { Test-Sha $s.Groups['sha'].Value $Where }
        }
        'KILLED' { if ($text.Trim().Length -lt 12) { $problems.Add("NO-REASON  $Where  KILLED needs a reason of at least 12 characters") } }
        'CLOSED-BY-RULING' {
            if ($Kind -eq 'roadmap') {
                $hit = @($NonGoals | Where-Object { $_ -match ('^- \*\*' + [regex]::Escape($Id) + '(?![0-9A-Za-z])') })
                if ($hit.Count -eq 0) { $problems.Add("NO-NONGOALS  $Where  CLOSED-BY-RULING needs a '- **$Id ...' bullet under 'Non-goals / accepted limitations' in clavity-dotnet/ROADMAP.md") }
            } elseif (-not (@($Block) -match '^\*\*Reopen if:\*\* \S')) { $problems.Add("NO-REOPEN  $Where  CLOSED-BY-RULING needs a '**Reopen if:** ...' line in the entry") }
        }
    }
    $rel = @($NextLines | Where-Object { $_ -match '^\*\*Released:\*\*' })
    foreach ($r in $rel) {
        if (-not $ReleasedRe.IsMatch($r)) { $problems.Add("BAD-RELEASED  $Where  '$r' is not '**Released:** clavity-vN'") }
        elseif ($tok -ne 'SHIPPED') { $problems.Add("RELEASED-ON-UNSHIPPED  $Where  only a SHIPPED entry may carry a Released line") }
    }
    $script:entries.Add([pscustomobject]@{ Tracker = $Tracker; Id = $Id; Token = $tok; Open = ($OpenTokens -contains $tok); Where = $Where; Title = $Title; Text = $text })
}

function Test-HeadingTracker {
    param([string]$Rel, [string]$Tracker, [regex]$HeadingRe, [scriptblock]$IdOf, [string[]]$NonGoals, [string]$Kind, [switch]$Required)
    $lines = Read-Lines $Rel -Required:$Required; if ($null -eq $lines) { return }
    $fence = $false; $idx = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*```') { $fence = -not $fence; continue }
        if (-not $fence -and $HeadingRe.IsMatch($lines[$i])) { $idx += $i }
        elseif (-not $fence -and $lines[$i] -match '^## Non-goals') { $idx += $i }   # a section boundary, not an entry
    }
    foreach ($k in 0..([Math]::Max($idx.Count - 1, 0))) {
        if ($idx.Count -eq 0) { break }
        $i = $idx[$k]; if (-not $HeadingRe.IsMatch($lines[$i])) { continue }
        $end = if ($k + 1 -lt $idx.Count) { $idx[$k + 1] } else { $lines.Count }
        $id = & $IdOf $lines[$i]; $where = "$Rel`:$($i + 1) $id"
        if ($HeadingMarkRe.IsMatch($lines[$i])) { $problems.Add("HEADING-STATUS  $where  the heading must be the title only (status markers belong on the status line)") }
        $j = $i + 1; while ($j -lt $end -and $lines[$j].Trim() -eq '') { $j++ }
        $m = if ($j -lt $end) { $StatusRe.Match($lines[$j]) } else { $null }
        if ($null -eq $m -or -not $m.Success) { $problems.Add("NO-STATUS  $where  the next non-blank line after the heading must be '**Status:** <TOKEN> <YYYY-MM-DD> - <text>'"); continue }
        $next = @($lines[($j + 1)..([Math]::Min($j + 2, $end - 1))] | Where-Object { $_ })
        Test-Entry -Tracker $Tracker -Id $id -Where $where -M $m -Block $lines[$i..($end - 1)] -NextLines $next -NonGoals $NonGoals -Kind $Kind -Title ($lines[$i] -replace '^#+\s*', '')
    }
}

# --- ROADMAP-style trackers --------------------------------------------------------------------------
$rmLines = Read-Lines 'clavity-dotnet/ROADMAP.md'   # the mandatory-tracker problem is raised once, by Test-HeadingTracker -Required below
$nonGoals = @()
if ($null -ne $rmLines) {
    $ng = [array]::FindIndex($rmLines, [Predicate[string]] { param($l) $l -like '## Non-goals*' })
    if ($ng -ge 0) { $nonGoals = @($rmLines[$ng..($rmLines.Count - 1)] | Where-Object { $_ -like '- **`*' -or $_ -like '- **§*' -or $_ -like '- **item *' -or $_ -like '- **AT-*' -or $_ -like '- **D*' -or $_ -like '- **R*' }) }
}
Test-HeadingTracker -Rel 'clavity-dotnet/ROADMAP.md' -Tracker 'dotnet-roadmap' -Kind 'roadmap' -NonGoals $nonGoals -Required `
    -HeadingRe ([regex]'^### (?:~~)?(?:§\d+ |\d+\. )') `
    -IdOf { param($l) if ($l -match '^### (?:~~)?(§\d+) ') { $Matches[1] } elseif ($l -match '^### (?:~~)?(\d+)\. ') { "item $($Matches[1])" } }
Test-HeadingTracker -Rel 'review-relay/ROADMAP.md' -Tracker 'review-relay' -Kind 'roadmap' -NonGoals $nonGoals `
    -HeadingRe ([regex]'^### [DR]\d+ ') -IdOf { param($l) if ($l -match '^### ([DR]\d+) ') { $Matches[1] } }
Test-HeadingTracker -Rel 'agy-autotrain/ROADMAP.md' -Tracker 'agy-autotrain-roadmap' -Kind 'roadmap' -NonGoals $nonGoals `
    -HeadingRe ([regex]'^## AT-\d+ ') -IdOf { param($l) if ($l -match '^## (AT-\d+) ') { $Matches[1] } }

# --- backlog stubs -----------------------------------------------------------------------------------
$stubDir = Join-Path $RepoRoot 'docs' 'backlog'
if (Test-Path -LiteralPath $stubDir -PathType Container) {
    foreach ($f in Get-ChildItem -LiteralPath $stubDir -Filter '*.md' -File | Sort-Object Name) {
        $lines = [IO.File]::ReadAllText($f.FullName) -split "`r?`n"; $where = "docs/backlog/$($f.Name)"
        $t = 0; while ($t -lt $lines.Count -and $lines[$t].Trim() -eq '') { $t++ }
        if ($t -ge $lines.Count -or $lines[$t] -notmatch '^# ') { $problems.Add("NO-TITLE  $where  line 1 must be '# <title>'"); continue }
        $j = $t + 1; while ($j -lt $lines.Count -and $lines[$j].Trim() -eq '') { $j++ }
        $m = if ($j -lt $lines.Count) { $StatusRe.Match($lines[$j]) } else { $null }
        if ($null -eq $m -or -not $m.Success) { $problems.Add("NO-STATUS  $where  the next non-blank line after the title must be '**Status:** <TOKEN> <YYYY-MM-DD> - <text>'"); continue }
        $next = @($lines[($j + 1)..([Math]::Min($j + 2, $lines.Count - 1))] | Where-Object { $_ })
        Test-Entry -Tracker 'backlog-stub' -Id $f.Name -Where $where -M $m -Block $lines -NextLines $next -NonGoals @() -Kind 'file' -Title ($lines[$t] -replace '^#+\s*', '')
    }
}

# --- fix-the-tool frontmatter --------------------------------------------------------------------------
$ftDir = Join-Path $RepoRoot 'agy-autotrain' 'docs' 'fix-the-tool-backlog'
if (Test-Path -LiteralPath $ftDir -PathType Container) {
    foreach ($f in Get-ChildItem -LiteralPath $ftDir -Filter '*.md' -File | Where-Object { $_.Name -notin @('README.md', '_template.md', 'DRY-RUN-2026-07-11.md') } | Sort-Object Name) {
        $lines = [IO.File]::ReadAllText($f.FullName) -split "`r?`n"; $where = "agy-autotrain/docs/fix-the-tool-backlog/$($f.Name)"
        if ($lines.Count -lt 3 -or $lines[0] -ne '---') { $problems.Add("NO-STATUS  $where  no frontmatter"); continue }
        $close = [array]::IndexOf($lines, '---', 1)
        if ($close -lt 0) { $problems.Add("NO-STATUS  $where  unterminated frontmatter"); continue }
        $fm = @{}; foreach ($l in $lines[1..($close - 1)]) { if ($l -match '^([A-Za-z-]+):\s*(.*?)\s*(#.*)?$') { $fm[$Matches[1]] = $Matches[2] } }
        if (-not $fm.ContainsKey('status')) { $problems.Add("NO-STATUS  $where  frontmatter has no status: key"); continue }
        $tok = $fm['status']
        if (($OpenTokens + $ClosedTokens) -notcontains $tok) { $problems.Add("BAD-TOKEN  $where  '$tok' is not one of: $(($OpenTokens + $ClosedTokens) -join ', ')"); continue }
        switch ($tok) {
            'SHIPPED' {
                $shas = @(([regex]'[0-9a-fA-F]{7,40}').Matches($(if ($fm.ContainsKey('fixed-by')) { $fm['fixed-by'] } else { '' })))
                if ($shas.Count -eq 0) { $problems.Add("NO-SHA  $where  SHIPPED needs fixed-by: <sha, ...>") }
                foreach ($s in $shas) { Test-Sha $s.Value $where }
                if (-not $fm.ContainsKey('fixed-on')) { $problems.Add("NO-DATE  $where  SHIPPED needs fixed-on: <YYYY-MM-DD>") }
            }
            'KILLED' { if (-not $fm.ContainsKey('reason') -or $fm['reason'].Length -lt 12) { $problems.Add("NO-REASON  $where  KILLED needs reason: of at least 12 characters") } }
            'CLOSED-BY-RULING' { if (-not (@($lines) -match '^\*\*Reopen if:\*\* \S')) { $problems.Add("NO-REOPEN  $where  CLOSED-BY-RULING needs a '**Reopen if:** ...' line") } }
        }
        if ($fm.ContainsKey('released-in') -and $tok -ne 'SHIPPED') { $problems.Add("RELEASED-ON-UNSHIPPED  $where  released-in: is only valid on SHIPPED") }
        $entries.Add([pscustomobject]@{ Tracker = 'fix-the-tool'; Id = $f.Name; Token = $tok; Open = ($OpenTokens -contains $tok); Where = $where; Text = '' })
    }
}

if ($isShallow) { $problems.Add('SHALLOW  this repository has no history, so cited shas could not be verified - deepen the checkout (git fetch --unshallow)') }

if ($List) {
    foreach ($e in @($entries | Where-Object Open | Sort-Object Tracker, Id)) { Write-Host ("{0,-11} {1,-22} {2,-10} {3}" -f $e.Token, $e.Tracker, $e.Id, $e.Title) }
    Write-Host "check-tracker-status: $(@($entries | Where-Object Open).Count) open item(s) of $($entries.Count)"
    exit 0
}
if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host $p -ForegroundColor Red }
    Write-Host "`ncheck-tracker-status: $($problems.Count) problem(s) - see docs/tracker-format.md" -ForegroundColor Red
    exit 1
}
Write-Host "check-tracker-status: OK - $($entries.Count) entries, $(@($entries | Where-Object Open).Count) open" -ForegroundColor Green
exit 0
```
Fixture note: in the `-List` row the ROADMAP is the only tracker present, so the other trackers' absence must not print MISSING-TRACKER for the optional ones - only `clavity-dotnet/ROADMAP.md` is mandatory. Implement by making `Read-Lines` take `-Required`: pass it only for `clavity-dotnet/ROADMAP.md`; for `review-relay/ROADMAP.md` and `agy-autotrain/ROADMAP.md` a missing file returns `$null` silently. (The real-repo row in Task 4 asserts all five trackers were seen: `Out` matches `entries`.)

- [ ] **Step 5: Run green**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-tracker-status.Tests.ps1 -Output Detailed -CI"`
Expected: `Tests Passed: 25, Failed: 0` (measured in the dry run on the code above).

- [ ] **Step 6: Mutants (the driver applies each, confirms the NAMED row goes red, then `git restore`s)**

| Mutant | Row that must go red |
|---|---|
| in `Test-Entry`, change `-notcontains $tok` to `-contains $tok` | 'refuses a token outside the closed set' |
| delete the `Test-Sha` call in the SHIPPED arm | 'requires a sha on SHIPPED, and the sha must exist' (PHANTOM half) |
| drop `(?![0-9A-Za-z])` from the Non-goals match | 'requires a Non-goals bullet ... (§1 is not §10)' |
| in `Test-HeadingTracker` remove the `$fence` toggle | 'does not read "###" lines inside a fenced code block' |
| change `$j = $i + 1; while ... ` to start the status search at `$end - 1` | 'rejects a status line that is not the NEXT non-blank line' |

- [ ] **Step 7: Register and document**

`justfile`: add `'scripts/tests/check-tracker-status.Tests.ps1'` to the end of the `test-scripts-fast` list; add the recipe near `check-doc-stubs`:
```just
# Tracker entry format gate (docs/tracker-format.md). Seconds-range, safe for pre-push.
check-tracker-status:
    pwsh -NoProfile -File scripts/check-tracker-status.ps1
```
`scripts/README.md`: add under the gates table the row `| \`check-tracker-status.ps1\` | Enforce docs/tracker-format.md over the ROADMAP, backlog stubs, fix-the-tool entries and the two other ROADMAPs (\`-List\` prints open items) | \`just check-tracker-status\` |`. `scripts/tests/_partition.md`: add a row `check-tracker-status.Tests.ps1   <measured by the driver>s   26 tests   <- FAST, NEW 2026-10-08` (the driver measures; subagents leave `UNMEASURED`).
Run: `pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/test-suite-registration.Tests.ps1','scripts/tests/scripts-readme-inventory.Tests.ps1') -Output Detailed -CI"` → `Failed: 0`.

- [ ] **Step 8: Commit** (the gate is NOT yet wired to pre-push/CI: it would be red until Task 4)

```bash
git add docs/tracker-format.md scripts/check-tracker-status.ps1 scripts/tests/check-tracker-status.Tests.ps1 justfile scripts/README.md scripts/tests/_partition.md
git commit -m "feat(gates): tracker entry format file and its status-line gate"
```

---

### Task 2: Check C - `path:N` pointers (§77)

**Files:** Modify `scripts/check-roadmap-claims.ps1` (insert before the `if ($isShallow)` summary block at `:236`), `scripts/tests/check-roadmap-claims.Tests.ps1` (new `Describe` before the real-repo `Describe` at `:387`), `clavity-dotnet/ROADMAP.md` (fix any out-of-range pointers the new check finds).

- [ ] **Step 1: Measure the real population (driver)**

DRY-RUN RESULT (2026-10-08, plan code applied to a scratch copy of the checker, run against the real ROADMAP): `OK ... (71 pointer(s) not checkable)` - **0 OUT-OF-RANGE**, 71 of the 144 not checkable (bare names and untracked paths), so about 73 were range-checked and all hold. Consequence: a pure range check finds NOTHING in today's ROADMAP, which is exactly agy's point (range-only certifies rot); §77's actual complaint (the §14 skill table's pointers do not hold the quoted text) is content drift and only surfaces once the five table pointers are converted to the ANCHORED form in Step 5. The driver re-runs the measurement at execution time and records the three numbers (checked / not checkable / out-of-range) in the commit message.

- [ ] **Step 2: Write the failing rows** (insert a new `Describe 'check-roadmap-claims.ps1 - the path:N pointer half (Check C)'` before line 387):

```powershell
Describe 'check-roadmap-claims.ps1 - the path:N pointer half (Check C)' {
    It 'passes a pointer inside the file' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } -Roadmap "See ``skills/a/SKILL.md:3``.`n"
        (Invoke-Claims $f.Root $f.Roadmap).Code | Should -Be 0
    }
    It 'fails a pointer past the end of the file and says OUT-OF-RANGE' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } -Roadmap "See ``skills/a/SKILL.md:4``.`n"
        $r = Invoke-Claims $f.Root $f.Roadmap; $r.Code | Should -Be 1; $r.Out | Should -Match 'OUT-OF-RANGE.*SKILL\.md:4'
    }
    It 'checks BOTH ends of a range' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n2`n3`n" } -Roadmap "See ``skills/a/SKILL.md:2-9``.`n"
        (Invoke-Claims $f.Root $f.Roadmap).Code | Should -Be 1
    }
    It 'verifies an ANCHORED pointer: the quoted text must be on line N' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "alpha`nbeta`ngamma`n" } -Roadmap "See ``skills/a/SKILL.md:2`` (`"beta`").`n"
        (Invoke-Claims $f.Root $f.Roadmap).Code | Should -Be 0
        $g = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "alpha`nbeta`ngamma`n" } -Roadmap "See ``skills/a/SKILL.md:3`` (`"beta`").`n"
        $r = Invoke-Claims $g.Root $g.Roadmap; $r.Code | Should -Be 1; $r.Out | Should -Match 'ANCHOR-MISS.*beta'
    }
    It 'verifies an anchored RANGE: the text may sit anywhere inside N..M' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "alpha`nbeta`ngamma`n" } -Roadmap "See ``skills/a/SKILL.md:1-2`` (`"beta`").`n"
        (Invoke-Claims $f.Root $f.Roadmap).Code | Should -Be 0
    }
    It 'does not check a pointer whose path is a bare name or not tracked, and counts it as unchecked' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n" } -Roadmap "See ``SKILL.md:99`` and ``elsewhere/x.cs:7``.`n"
        $r = Invoke-Claims $f.Root $f.Roadmap; $r.Code | Should -Be 0; $r.Out | Should -Match '2 pointer\(s\) not checkable'
    }
    It 'ignores a pointer inside a fenced code block' {
        $f = New-ClaimRepo -Files @{ 'skills/a/SKILL.md' = "1`n" } -Roadmap "``````text`n``skills/a/SKILL.md:50```n```````n"
        (Invoke-Claims $f.Root $f.Roadmap).Code | Should -Be 0
    }
}
```

- [ ] **Step 3: Run red** - `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-roadmap-claims.Tests.ps1 -Output Detailed -CI"` → the two failing-direction rows (OUT-OF-RANGE, range, ANCHOR-MISS) red.

- [ ] **Step 4: Implement Check C** (insert before `if ($isShallow) {` at the end of check B, i.e. after the `for` loop that ends at `:234`):

```powershell
# --- C. path:N / path:N-M pointers (ROADMAP section 77) ---------------------------------------------
# WHAT THIS CATCHES: a pointer past the end of its file (OUT-OF-RANGE), and - only for the OPT-IN anchored form
# `file:N` ("quoted text") - a pointer whose line no longer holds the text (ANCHOR-MISS). WHAT IT DOES NOT: an
# un-anchored pointer that is still in range but now points at the wrong line reads GREEN; a pure range check
# cannot see content drift (agy and the driver agreed, 2026-10-08). New pointers should be anchored.
# NOT CHECKABLE (counted, never failed): a bare name with no '/', or a path that is not a tracked file.
$ptrRe  = [regex]'`(?<path>[A-Za-z0-9_./-]+\.[A-Za-z0-9]+):(?<a>\d+)(?:-(?<b>\d+))?`(?:\s+\("(?<anchor>[^"]+)"\))?'
$fence  = $false; $unchecked = 0
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^\s*```') { $fence = -not $fence; continue }
    if ($fence) { continue }
    foreach ($m in $ptrRe.Matches($lines[$i])) {
        $rel = $m.Groups['path'].Value
        $a = 0; $b = 0
        if (-not [int]::TryParse($m.Groups['a'].Value, [ref]$a)) { $unchecked++; continue }
        $b = $a
        if ($m.Groups['b'].Success -and -not [int]::TryParse($m.Groups['b'].Value, [ref]$b)) { $unchecked++; continue }
        if ($rel -notmatch '/') { $unchecked++; continue }
        $hits = @($tracked | Where-Object { $_ -eq $rel -or $_.EndsWith("/$rel", [StringComparison]::OrdinalIgnoreCase) })
        if ($hits.Count -ne 1) { $unchecked++; continue }
        $hp = Join-Path $RepoRoot ($hits[0] -replace '/', [IO.Path]::DirectorySeparatorChar)
        try { $fl = [IO.File]::ReadAllLines($hp) } catch { $unchecked++; continue }
        if ($a -lt 1 -or $b -lt $a -or $b -gt $fl.Count) {
            $problems += "OUT-OF-RANGE  ROADMAP:$($i+1)  ``$rel`:$a$(if ($b -ne $a) { "-$b" }) points outside $($hits[0]) ($($fl.Count) lines)"
            continue
        }
        if ($m.Groups['anchor'].Success) {
            $needle = $m.Groups['anchor'].Value
            $found = $false
            for ($n = $a; $n -le $b; $n++) { if ($fl[$n - 1].Contains($needle, [StringComparison]::Ordinal)) { $found = $true; break } }
            if (-not $found) { $problems += "ANCHOR-MISS  ROADMAP:$($i+1)  ``$rel`:$a$(if ($b -ne $a) { "-$b" }) does not contain `"$needle`"" }
        }
    }
}
```
And in the summary section add `OUT-OF-RANGE`, `ANCHOR-MISS` to `$falseTokens` (they are checked-and-false), and change the final OK line to `... holds ($unchecked pointer(s) not checkable)`. The Step 2 row 'counts it as unchecked' matches `2 pointer\(s\) not checkable`.

- [ ] **Step 5: Run green, then fix the real ROADMAP**

Run the suite: all new rows green EXCEPT the real-repo row at `:389` if the real ROADMAP carries out-of-range pointers. For each `OUT-OF-RANGE` line the checker prints for the real ROADMAP: open the cited file, find the line that now holds the quoted text, and correct the pointer; if the pointer cannot be recovered, append `(pointer superseded 2026-10-08: <what it pointed at>)` and remove the backticks. Do NOT edit history prose. The §14 skill table (`ROADMAP.md` ~1236-1247) is the known case: convert its five pointers to the anchored form using the quoted text already beside each one.
Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/check-roadmap-claims.Tests.ps1 -Output Detailed -CI"` → `Failed: 0` including 'passes on the committed ROADMAP'.

- [ ] **Step 6: Mutants** - change `$b -gt $fl.Count` to `$b -gt $fl.Count + 1` → 'fails a pointer past the end' red; change `.Contains($needle ...)` to `$true` → the ANCHOR-MISS row red; remove the fence toggle → 'ignores a pointer inside a fenced code block' red.

- [ ] **Step 7: Update the script header comment** (`TWO CHECKS` → `THREE CHECKS`, add check C and its stated limit), update `scripts/README.md`'s `check-roadmap-claims.ps1` row to mention pointers, flip ROADMAP §77's status in Task 4 (not here).

- [ ] **Step 8: Commit** - `git add scripts/check-roadmap-claims.ps1 scripts/tests/check-roadmap-claims.Tests.ps1 scripts/README.md clavity-dotnet/ROADMAP.md && git commit -m "feat(gates): check C - ROADMAP path:N pointers are range-checked, anchored ones content-checked (section 77)"`

---

### Task 3: Teach agents the format - excerpt in 3 skills x 2 plugins, with a parity check

**Files:** Modify `clavity-dotnet/plugin/skills/{open-issues,agy-capstone,agy-test-audit}/SKILL.md` and the three byte-identical twins under `clavity-classic/plugin/skills/`; create `scripts/check-tracker-format-excerpt.ps1`, `scripts/tests/check-tracker-format-excerpt.Tests.ps1`.

- [ ] **Step 0 (driver): load `superpowers:writing-skills`** and read it before any SKILL.md edit (project memory: the linter proves text ships, not that an agent obeys it).

- [ ] **Step 1: Write the parity suite** - rows: (a) passes when the block between `<!-- tracker-format:begin -->` and `<!-- tracker-format:end -->` in each of the six skill files equals the block in `docs/tracker-format.md` (fixture: a temp tree with those 7 files); (b) exits 1 and names the file when one skill's block differs by one character; (c) exits 1 when a skill has NO block; (d) exits 1 when a block appears twice; (e) exits 1 when `docs/tracker-format.md` has no block; (f) the real-repo row (last). The script takes `-RepoRoot` like its siblings and exits 0/1/2 (2 = a required file unreadable).

- [ ] **Step 2: Write `scripts/check-tracker-format-excerpt.ps1`** (dry-run: clean / one-character drift / missing / duplicate / canonical gone gave exit 0 / 1 / 1 / 1 / 2 with the expected `EXCERPT-*` lines):

```powershell
#!/usr/bin/env pwsh
# The tracker-format excerpt in docs/tracker-format.md must appear, byte for byte, in the promote-step skills of BOTH plugins.
# EXIT: 0 every copy equals the canonical block · 1 a copy is missing, duplicated or differs · 2 the canonical block cannot be read.
[CmdletBinding()]
param([string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).ProviderPath }
$begin = '<!-- tracker-format:begin -->'; $end = '<!-- tracker-format:end -->'
# EXPLICIT list: the suite's real-repo row proves it equals the set of skills that carry a promote step.
# (PowerShell variable names are CASE-INSENSITIVE: the loop variable below is $skill, never $s/$S next to another $S.)
$skills = foreach ($plugin in 'clavity-dotnet', 'clavity-classic') { foreach ($skill in 'open-issues', 'agy-capstone', 'agy-test-audit') { "$plugin/plugin/skills/$skill/SKILL.md" } }

function Get-Blocks([string]$Rel) {
    $path = Join-Path $RepoRoot ($Rel -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $t = [IO.File]::ReadAllText($path) -replace "`r`n", "`n"
    $found = [System.Collections.Generic.List[string]]::new(); $i = 0
    while (($b = $t.IndexOf($begin, $i, [StringComparison]::Ordinal)) -ge 0) {
        $e = $t.IndexOf($end, $b, [StringComparison]::Ordinal); if ($e -lt 0) { break }
        $found.Add($t.Substring($b + $begin.Length, $e - $b - $begin.Length).Trim()); $i = $e + $end.Length
    }
    return , $found.ToArray()
}

$canon = Get-Blocks 'docs/tracker-format.md'
if ($null -eq $canon -or $canon.Count -ne 1 -or -not $canon[0]) { Write-Host 'check-tracker-format-excerpt: docs/tracker-format.md must contain exactly one non-empty excerpt block' -ForegroundColor Yellow; exit 2 }
$bad = 0
foreach ($rel in $skills) {
    $b = Get-Blocks $rel
    if ($null -eq $b)             { Write-Host "EXCERPT-MISSING    $rel (file not found)" -ForegroundColor Red; $bad++ }
    elseif ($b.Count -eq 0)       { Write-Host "EXCERPT-MISSING    $rel" -ForegroundColor Red; $bad++ }
    elseif ($b.Count -gt 1)       { Write-Host "EXCERPT-DUPLICATE  $rel" -ForegroundColor Red; $bad++ }
    elseif ($b[0] -cne $canon[0]) { Write-Host "EXCERPT-DRIFT      $rel" -ForegroundColor Red; $bad++ }
}
if ($bad -gt 0) { Write-Host "check-tracker-format-excerpt: $bad of $(@($skills).Count) copies are wrong" -ForegroundColor Red; exit 1 }
Write-Host "check-tracker-format-excerpt: OK - $(@($skills).Count) copies equal docs/tracker-format.md" -ForegroundColor Green
exit 0
```
The suite's rows (a)-(f) from Step 1 drive it with a fixture tree built like the dry run (docs file + six `SKILL.md`); row (f), the real-repo row, also asserts that the three skill NAMES in `$skills` are exactly the skills whose text routes a deferral to a ROADMAP: `Select-String -Path clavity-dotnet/plugin/skills/*/SKILL.md -Pattern 'ROADMAP\.md'` restricted to skills that mention `local-anomalies.md` equals `open-issues, agy-capstone, agy-test-audit` (a fourth skill gaining a promote step fails the row until it is enrolled).

- [ ] **Step 3: Insert the excerpt** - paste the block from `docs/tracker-format.md` (verbatim, including both marker lines) into each skill:
  - `open-issues/SKILL.md`: directly after the "1. **PROMOTE** ..." list item paragraph (ends with `which already carries the cross-cutting sections.` at ~line 207), as its own paragraph.
  - `agy-test-audit/SKILL.md`: directly after item 4's sentence ending `... cannot degrade into run-then-defer theater.` (~line 231-232), as its own paragraph.
  - `agy-capstone/SKILL.md`: directly after the paragraph ending `... a subagent REPORTS, the driver VERIFIES, the driver WRITES.` (~line 317).
  Classic gets the identical paste at the identical anchor text (the files are byte-identical today; confirm with `diff` before and after).

- [ ] **Step 3b: Update the line-count claims this edit breaks (panel finding, MEASURED)** - `clavity-dotnet/ROADMAP.md:1243` claims `agy-test-audit/SKILL.md` (484 lines) and `:1244` claims `agy-capstone/SKILL.md` (542 lines); inserting the excerpt adds lines to both and Check A of `check-roadmap-claims.ps1` (and its real-repo row, and CI) goes red. Run `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1`, read the `STALE` lines, and set each claimed number to the printed actual. The insertion points (after `:216`, `:89`, `:92`, `:103` in the §14 table's citations) are chosen so those line POINTERS are unaffected; the executor confirms by running Check C (Task 2) afterwards. `open-issues/SKILL.md` has no count claim (measured: only the two above).

- [ ] **Step 4: Run the gates the edit can trip**

```bash
bash scripts/check-seed-artifacts-synced.sh                     # expect: seed agent artifacts in sync
pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1  # expect exit 0 (it pins capstone/test-audit content)
pwsh -NoProfile -File scripts/check-tracker-format-excerpt.ps1  # expect OK
pwsh -NoProfile -File scripts/check-roadmap-claims.ps1          # expect OK after Step 3b
pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/check-tracker-format-excerpt.Tests.ps1','scripts/tests/check-seed-artifacts-synced.Tests.ps1','scripts/tests/check-agy-discipline-skills.Tests.ps1') -Output Detailed -CI"   # Failed: 0
```
Mutants: change one word inside one classic skill's block → parity row (b) red AND `check-seed-artifacts-synced` red; delete a block → row (c) red.

- [ ] **Step 5: Wire and register** - `justfile`: `check-tracker-format-excerpt` recipe; add the suite to `test-scripts-fast`; `lefthook.yml` pre-push gets `tracker-excerpt: run: just check-tracker-format-excerpt`; `scripts/README.md` row; `_partition.md` row. Run `test-suite-registration` + `scripts-readme-inventory` (`Failed: 0`).

- [ ] **Step 6: Commit** - `git add` the six SKILL.md, the script, its suite, `justfile`, `lefthook.yml`, `scripts/README.md`, `scripts/tests/_partition.md`; `git commit -m "feat(skills): tracker-format excerpt in open-issues/agy-capstone/agy-test-audit (both plugins) + parity gate"`.

---

### Task 4: One-time normalisation of the four trackers (driver applies; Sonnet writes the script)

**Files:** Modify `clavity-dotnet/ROADMAP.md`, `docs/backlog/*.md` (19), `agy-autotrain/docs/fix-the-tool-backlog/*.md` (14 + `_template.md` + `README.md`), `review-relay/ROADMAP.md`, `agy-autotrain/ROADMAP.md`, `docs/backlog-triage-runbook.md`, `docs/coverage-debt.md`, `scripts/tests/check-tracker-status.Tests.ps1` (real-repo row), `justfile`/`lefthook.yml`/`.github/workflows/ci-scripts.yml` (wire the gate).

The decided-token table is `docs/superpowers/plans/2026-10-08-branch-t-normalisation-table.tsv` (120 rows: tracker, id, line, token, note). **Before any apply, the driver shows the owner the 5 `JUDGE` rows and the 7 `SHIPPED-no-sha` rows (below) as ONE batch and records each ruling in the TSV `note` column.** Current JUDGE rows: `§59` (closed + scheduled words), `dev-box-background-load-contaminates-every-timing-figure.md`, `docs-audit-findings-are-invisible-to-git.md`, `peer-scratch-dir-contains-executable-session-hooks.md`, review-relay `D2`.

- [ ] **Step 1: Resolve evidence the gate will demand (driver)**
  - For every `SHIPPED` row with no backticked sha in its legacy header: find it with `git log -S'<id title phrase>' --oneline -- clavity-dotnet/ROADMAP.md` or from the entry body's closure line; record `id<TAB>sha` in `docs/superpowers/plans/2026-10-08-branch-t-sha-overrides.tsv`. A SHIPPED row for which NO sha can be recovered is reported to the owner (token becomes `CLOSED-BY-RULING` with a Non-goals bullet, or the owner supplies the sha) - never a placeholder.
  - The 7 fix-the-tool entries that are `fixed-in-repo`/`released` but lack `fixed-by:` (only `curate-nudge-age-reads-drain-log-dates.md` and `idle-wait-false-modal.md` have it): recover from `git log --diff-filter=A -- <file>` plus the entry text; same override file.
  - ADD these Non-goals bullets to `clavity-dotnet/ROADMAP.md` (full text, from the owner batch ruling), after the existing step-0 bullets:
    - `- **§7 (b) - the five coverage gaps backfilled onto the conveyor** (closed by ruling 2026-10-08): \`docs/coverage-debt.md\` tracks the gaps instead. Reopen if that file stops being maintained.`
    - `- **§13c - does a growth-region write append or replace?** (closed by ruling 2026-10-08, answered by reading): \`GoldenHeader.cs:286-287\` writes a temp file then \`File.Move(tmp, path, overwrite: true)\` - a REPLACE; the classic writer was re-checked during normalisation. Reopen if either writer changes.`
    - `- **§15 - the spec section 3b-vs-6 ordering tension** (closed by ruling 2026-10-08): the build follows 3b; the shipped behaviour is the ruling. Reopen if the two sections are ever made to disagree in code.`
    - `- **§21 - whether the anti-wrap-up clause is sufficient** (closed by ruling 2026-10-08): the clause stays as necessary; isolating it is a quota-costing experiment. Reopen if a report is displaced despite the clause.`
    - `- **§37 - release notes from commit subjects** (closed by ruling 2026-10-08): the convention stays. Reopen on a reader complaint.`
    - `- **§58 - older clones keep CRLF until refreshed** (closed by ruling 2026-10-08): measured 2026-10-08, this clone shows only the two declared CRLF exceptions in \`git ls-files --eol\`; the refresh procedure stays documented. Reopen if a fresh clone shows CRLF blobs.`
  - Also record in the Task 4 commit message the two batch-ruling rows that need NO Non-goals bullet (they are `SHIPPED`): §18 (`11484a57`), §27 (§39/§40 fixes `cda6a6f4`, `e23d81ee` - confirm the match to the 2026-09-07 audit during this step).

- [ ] **Step 2: Write the transform script** (scratchpad, never committed; its sha256 goes in the commit message). Full algorithm - the executor writes it exactly so:

```python
# normalise_trackers.py  - run with:  python -I normalise_trackers.py <repo-root> <table.tsv> <sha-overrides.tsv>  [--dry-run]
# Reads/writes bytes; ASSERTS the file has no CR before and after (all tracked blobs are LF); never rewrites a line it did not own.
import re, sys, io, os, glob
STATUS_GLYPH_SEP = re.compile(r'\s+[—·]\s+(?=[~*]*(?:✅|▶|🔴|🚫|⚠|~~))')   # " — ✅ ..." or " · 🚫 ..."
DATE = re.compile(r'\d{4}-\d{2}-\d{2}')
SHA  = re.compile(r'`([0-9a-fA-F]{7,40})(?:\.\.([0-9a-fA-F]{7,40}))?`')
NORMALISED = '2026-10-08'

def split_heading(line):
    """### §N — Title — <tail>  ->  (heading_without_tail, tail). The tail starts at the FIRST glyph-led separator; a heading
    with no glyph-led separator is title-only and tail=''. Strike-through markers around the title are removed."""
    m = STATUS_GLYPH_SEP.search(line)
    head, tail = (line[:m.start()], line[m.end():]) if m else (line, '')
    head = head.replace('~~', '')            # '### ~~1. Title~~' -> '### 1. Title'
    return head.rstrip(), tail

def status_line(token, tail, entry_lines, overrides, eid, note):
    d = (DATE.search(tail) or DATE.search('\n'.join(entry_lines[:40])) or [NORMALISED])
    date = d.group(0) if hasattr(d, 'group') else d[0]
    text = {'SHIPPED': 'merged to main', 'CLOSED-BY-RULING': 'closed by ruling, see Non-goals / accepted limitations',
            'KILLED': 'will not be done - ' + (re.sub(r'\*\*|~~|[✅▶🔴🚫⚠]', '', tail)[:90].strip() or 'see the legacy status below'),
            'OPEN': 'not yet scheduled', 'SCHEDULED': 'scheduled - ' + note, 'IMPLEMENTED': 'built on an unmerged branch'}[token]
    if token == 'SHIPPED':
        sha = overrides.get(eid) or next((m.group(1) for m in SHA.finditer(tail)), None) \
              or next((m.group(1) for l in entry_lines if re.search(r'SHIPPED|FIXED|CLOSED', l) for m in SHA.finditer(l)), None)
        if not sha: raise SystemExit('NOSHA ' + eid)        # reported, never papered over
        text += ' in `%s`' % sha
    return '**Status:** %s %s - %s' % (token, date, text)

# For each table row (tracker == dotnet-roadmap): locate the heading line BY ID, never by the table's line column (Tasks 2 and 3
# and the Non-goals additions in step 1 shift lines before this runs; the line column is informational only): the unique line
# matching '^### (~~)?' + re.escape(id-as-written) + r'[ .]' - assert exactly ONE match, else STOP with `AMBIGUOUS-HEADING <id>`; replace it with split_heading(...)[0]; insert after it  '' , status_line(...) , and, when tail is non-empty,
# '> **Legacy status (verbatim, before the 2026-10-08 normalisation):** ' + tail  (kept so no history is lost); then the original body.
# Rows with line == 'NEW'  -> append the new entry (title, status line, the verbatim paragraph named in the table note) BEFORE '## Non-goals'.
# backlog-stub rows: line 3 '**Status:** <old>' -> '**Status:** <TOKEN> ...' + a '> **Legacy status (verbatim...):** <old>' line;
#   CLOSED-BY-RULING stubs also gain '**Reopen if:** <text from the table note>'.
# fix-the-tool rows: rewrite the 'status:' frontmatter value to the token, add 'fixed-by:'/'fixed-on:' from overrides for SHIPPED,
#   keep 'released-in:', and for KILLED (wont-fix) add 'reason:' from the entry's existing wont-fix paragraph.
# review-relay / agy-autotrain-roadmap rows: same transform on their headings; their existing '**Status:**' lines are replaced.
# Every apply path ends with:  assert b'\r' not in data ; re-read the file ; print a per-file diffstat.
```

- [ ] **Step 3: Dry-run** - `python -I normalise_trackers.py . <table> <overrides> --dry-run` prints, per file, the planned heading/status pairs. The driver reads ALL 120 pairs against the table before the apply (the heuristic failed on §20/§26/§65 because of "was:" text). Any disagreement → fix the table row, not the script.

- [ ] **Step 4: Apply, then run the gate** - `python -I normalise_trackers.py . <table> <overrides>` then `pwsh -NoProfile -File scripts/check-tracker-status.ps1`. Iterate (fix the table/override, re-run from a clean `git restore` of the five tracker paths) until it prints `OK`. The gate's output is the oracle; no hand-edit of a status line.

- [ ] **Step 5: Splits and stale-text corrections (hand edits, each located by grep first)**
  - §29 → body keeps §29a; the 29b paragraph (`ROADMAP.md` ~2538-2542, quoted in the table) is copied VERBATIM into the new `§79 - The 13b completeness false-flag whose cause is not determined (formerly §29b)`; the original paragraph stays, prefixed `(now tracked as §79)`.
  - §31 → the sentence "`.no-agy` should make `agy-liveness-check.sh` SILENT ... OPEN, deliberately not decided here" becomes `§80 - .no-agy should make agy-liveness-check.sh silent (formerly §31)`, status `SCHEDULED 2026-10-08 - Branch H; owner ruled 2026-10-08: the hook is SILENT`; the original sentence stays in §31's legacy line.
  - Stale statements: append `(superseded 2026-10-08: <fact>)` after each of: item 0's `1b — PROMPT (deferred deliberately)` line (`:376`: steps 2/1a/1b SHIPPED 2026-08-07, see `:222`); §65's "Forks 2 and 3 DEFERRED" body (`:3764-3769`: closed by ruling, Non-goals); §14's "KNOWN OPEN HOLE" (`:1191`: accepted limitation, Non-goals); §74's "capstone + test-audit pending" (recorded in `docs/agy-capstone-ledger.md` / `docs/agy-test-audit-ledger.md`); §61's "branch `release` must exist" (it exists: `git ls-remote origin refs/heads/release`); §27's "push is HELD / panel is PAUSED"; §21's "ACCEPTED, NOT STARTED" plan block; `peer-scratch-dir-contains-executable-session-hooks.md`'s leftover SCHEDULED line; the `golden-header-per-ask-token-optimization.md` "never measured" probe; §14c's residual limit (add it to the §14 Non-goals bullet). The driver verifies each fact by command before writing it.

- [ ] **Step 6: Update the prose that describes the old enum** - `agy-autotrain/docs/fix-the-tool-backlog/_template.md` (frontmatter uses the closed token set and the `fixed-by`/`fixed-on`/`released-in`/`reason` keys; delete the `open | fixed-in-repo | released | wont-fix` line), `agy-autotrain/docs/fix-the-tool-backlog/README.md`, `docs/backlog-triage-runbook.md:104` and `:276` (both state the stale enum `open | fixed | wont-fix`), `docs/coverage-debt.md` boundary H (heading `### H. ... — VOIDED 2026-10-08`, a **VOIDED** paragraph in the style of boundary E at line 402 naming `check-tracker-status.ps1` as the enforcement; keep the original text as "Original gap (for the record)"), the ROADMAP preamble (`clavity-dotnet/ROADMAP.md` line ~24-27: one sentence pointing at `docs/tracker-format.md`).

- [ ] **Step 7: Flip the Branch T items' own status lines** (they are now in the new format): §77 → `IMPLEMENTED 2026-10-08 - Check C on branch sweep/branch-t-format-and-gates`; §34/§36/§56 stay `SCHEDULED` until their tasks land and are flipped to `IMPLEMENTED` in the task that completes them, then to `SHIPPED <merge sha>` after the merge; `docs/backlog/pester-temp-dirs-orphan-on-killed-runs.md` likewise.

- [ ] **Step 8: The Done-check hand scans stay as the cross-check** (spec "Done-check"): `grep -nE '^### (~~)?[0-9]+\. ' clavity-dotnet/ROADMAP.md` (the 14 numbered items all carry a valid status line - the gate proved it), plus `pwsh -NoProfile -File scripts/check-tracker-status.ps1 -List` printed in full for the owner.

- [ ] **Step 9: Add the real-repo row, wire the gate** - append to `check-tracker-status.Tests.ps1`:
```powershell
Describe 'check-tracker-status.ps1 - the real repository' {
    It 'passes on the committed trackers and sees all five' {
        $r = Invoke-Gate $script:RepoRoot
        $r.Code | Should -Be 0 -Because "the trackers must satisfy docs/tracker-format.md; output was:`n$($r.Out)"
        $r.Out | Should -Match 'OK - \d+ entries'
        (Invoke-Gate $script:RepoRoot -List).Out | Should -Match 'check-tracker-status: \d+ open item'
    }
}
```
  `lefthook.yml` pre-push: `tracker-status: run: just check-tracker-status`; `.github/workflows/ci-scripts.yml`: the scripts suite already runs `Invoke-Pester scripts/tests`, so the new real-repo row IS the CI enforcement (no extra step - the same pattern as `check-roadmap-claims`; the existing deepen-history step covers the sha check).
  Run: `pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/check-tracker-status.Tests.ps1','scripts/tests/check-roadmap-claims.Tests.ps1') -Output Detailed -CI"` → `Failed: 0`.

- [ ] **Step 10: Verify nothing was lost and endings are LF** -
```bash
git diff --stat | tail -3
for f in $(git diff --name-only); do python -I -c "import sys,subprocess;b=subprocess.run(['git','show',':'+sys.argv[1]],capture_output=True).stdout;print(sys.argv[1],'CR' if b'\r' in b else 'LF')" "$f"; done | grep -v ' LF$' || echo "all LF"
```
and a history-preservation oracle: for each of the 65+14 ROADMAP headings, the OLD heading text (from `git show HEAD:clavity-dotnet/ROADMAP.md`) appears verbatim, either as the new heading + the `Legacy status` line or in the new heading alone - the script prints `LOST <id>` otherwise (must print nothing). Mutant: truncate one tail in the script → the oracle prints `LOST`.

- [ ] **Step 11: Commit** - explicit paths only (`git status --short` first; the five tracker groups, the three prose docs, the suite, `lefthook.yml`, the TSVs); message states the script's sha256 and the table commit.

---

### Task 5: §34 - null-safe removal, and allocation inside `try` (10 files, 96 sites)

**Files:** Create `scripts/tests/TestTemp.ps1` (partly; the temp-root half arrives in Task 6), `scripts/tests/TestTemp.Tests.ps1`; modify `scripts/tests/BashHookHelpers.ps1`; the 10 suites.

- [ ] **Step 1: Write the failing helper rows** in `scripts/tests/TestTemp.Tests.ps1`:
```powershell
BeforeAll { . (Join-Path $PSScriptRoot 'TestTemp.ps1') }
Describe 'Remove-TestPath' {
    It 'removes existing paths and tolerates $null elements without throwing' {
        $d = Join-Path $TestDrive 'a'; New-Item -ItemType Directory $d | Out-Null
        { Remove-TestPath $null, $d } | Should -Not -Throw
        Test-Path $d | Should -BeFalse
    }
    It 'tolerates ALL-null and empty input (the case Remove-Item itself throws on)' {
        { Remove-TestPath $null, $null } | Should -Not -Throw
        { Remove-TestPath @() } | Should -Not -Throw
        { Remove-TestPath } | Should -Not -Throw
    }
    It 'tolerates a path that does not exist' { { Remove-TestPath (Join-Path $TestDrive 'nope') } | Should -Not -Throw }
    It 'removes a FILE as well as a directory' {
        $f = Join-Path $TestDrive 'f.txt'; 'x' | Set-Content $f
        Remove-TestPath $f; Test-Path $f | Should -BeFalse
    }
    It 'is the shape a failed second allocation needs: the first handle is still cleaned' {
        $a = $null; $b = $null
        try { $a = Join-Path $TestDrive 'first'; New-Item -ItemType Directory $a | Out-Null; throw 'second allocation failed' }
        catch { } finally { Remove-TestPath $a, $b }
        Test-Path (Join-Path $TestDrive 'first') | Should -BeFalse
    }
}
```
Run red (`TestTemp.ps1` missing → BeforeAll throws).

- [ ] **Step 2: Implement `Remove-TestPath` in `scripts/tests/TestTemp.ps1`**
```powershell
# Shared test hygiene. Dot-sourced by BashHookHelpers.ps1 and by suites that do not use it.
function Remove-TestPath {
    # MEASURED (pwsh 7): `Remove-Item $null,$x -ErrorAction SilentlyContinue` THROWS ParameterBindingValidationException
    # (the error action does not cover binding), and so does an empty set. So filter, and skip when nothing is left.
    param([Parameter(ValueFromRemainingArguments)] $Path)
    $p = @($Path | ForEach-Object { $_ } | Where-Object { $_ })
    if ($p.Count -eq 0) { return }
    Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
}
```
Run green (`Tests Passed: 5`). Mutant: remove the `Where-Object { $_ }` → rows 1-2 red.
In `BashHookHelpers.ps1`, add as its first executable line `. (Join-Path $PSScriptRoot 'TestTemp.ps1')`.

- [ ] **Step 3: The §34 transformation rule** (applied per file by a Sonnet subagent; the pattern below is the ONLY edit shape):

Before (e.g. `agy-liveness-check.Tests.ps1:40-47`):
```powershell
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            ...body...
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
```
After:
```powershell
        $cfg = $null; $h = $null
        try {
            $cfg = New-ConfigFixture $true; $h = New-CleanHome
            ...body...
        } finally { Remove-TestPath $cfg, $h }
```
Rules: (1) every variable allocated on the line(s) before `try` is initialised to `$null` on its own line, its allocation moves to the first statements INSIDE `try`, in the original order; (2) the `finally`'s `Remove-Item <vars> -Recurse -Force -ErrorAction SilentlyContinue` becomes `Remove-TestPath <vars>` with the SAME variable list; (3) a `finally` that also does something else (e.g. `& icacls ...`) keeps that statement, only the Remove-Item changes; (4) nothing else in the file changes - no test is renamed, merged, or has an assertion touched.

- [ ] **Step 4: The per-file oracle** (the subagent runs it; the driver re-runs it): `scripts/tests/_t34_scan.ps1` is NOT committed; the scan is this one-liner per file, which must print `0`:
```bash
awk 'prev ~ /\$[A-Za-z_]+ = New-[A-Za-z]+[^;]*;[ \t]*\$[A-Za-z_]+ = New-/ && $0 ~ /^[ \t]*try[ \t]*\{/ {c++} {prev=$0} END{print c+0}' scripts/tests/<file>.Tests.ps1
```
plus, per file, the suite's test COUNT before and after is identical and `Failed: 0` (the subagent records both numbers; the driver spot-checks two files). The 10 files and their pre-edit site counts are listed under "Measured facts". `hook-spawn-budget.Tests.ps1` (1 site at `:101`) is the proof that the scan found a tenth file the ROADMAP never named.

- [ ] **Step 5: Failing control for the converted shape** (driver, once): in `agy-liveness-check.Tests.ps1` temporarily make `New-CleanHome` throw (`throw 'boom'` as its first line) and run one converted test: expected - that test FAILS with 'boom' (not with `ParameterBindingValidationException`) and `ls $env:TEMP/sp-d-cfg-*` shows NO new directory from this run. Restore with `git restore`. (Before the conversion the same mutant leaves the config directory behind - recorded in the commit message from a pre-edit run on a scratch copy.)

- [ ] **Step 6: Register `TestTemp.Tests.ps1`** (fast list, `_partition.md` row), run `test-suite-registration` + each of the 10 edited suites individually (`Failed: 0`).

- [ ] **Step 7: Commit** - `git add scripts/tests/TestTemp.ps1 scripts/tests/TestTemp.Tests.ps1 scripts/tests/BashHookHelpers.ps1 <the 10 suites> justfile scripts/tests/_partition.md`; message `fix(tests): null-safe cleanup and in-try allocation across the 10 hook suites (section 34)`. Flip §34 and nothing else to `IMPLEMENTED` in the same commit.

---

### Task 6: One shared Pester temp root, a 24 h sweep, and a gate (pester-temp-dirs)

**Files:** Modify `scripts/tests/TestTemp.ps1`, `scripts/tests/TestTemp.Tests.ps1`, `scripts/tests/BashHookHelpers.ps1`, every `*.Tests.ps1` that touches temp (58 suites; the exact list is the output of Step 2's scan), `scripts/tests/check-seed-artifacts-synced.Tests.ps1`; create `scripts/tests/test-temp-discipline.Tests.ps1`.

- [ ] **Step 1: Failing rows for the root and the sweep** (append to `TestTemp.Tests.ps1`):
```powershell
Describe 'the shared test temp root' {
    BeforeAll { $script:Saved = $env:CLAVITY_TEST_TEMP_ROOT; $env:CLAVITY_TEST_TEMP_ROOT = Join-Path $TestDrive 'root' }
    AfterAll  { if ($null -eq $script:Saved) { Remove-Item Env:CLAVITY_TEST_TEMP_ROOT -ErrorAction SilentlyContinue } else { $env:CLAVITY_TEST_TEMP_ROOT = $script:Saved } }
    It 'Get-TestTempRoot honours the override and creates the directory' {
        (Get-TestTempRoot) | Should -Be (Join-Path $TestDrive 'root'); Test-Path (Get-TestTempRoot) | Should -BeTrue
    }
    It 'New-TestTempPath returns a unique path UNDER the root, prefixed, and does not create it' {
        $a = New-TestTempPath 'abc'; $b = New-TestTempPath 'abc'
        $a | Should -Not -Be $b
        $a | Should -BeLike (Join-Path (Get-TestTempRoot) 'abc-*')
        Test-Path $a | Should -BeFalse
    }
    It 'the sweep removes children older than the age and KEEPS younger ones' {
        $old = Join-Path (Get-TestTempRoot) 'old-1'; $new = Join-Path (Get-TestTempRoot) 'new-1'
        New-Item -ItemType Directory $old, $new | Out-Null
        (Get-Item $old).LastWriteTime = (Get-Date).AddHours(-30)
        Invoke-TestTempSweep -MaxAgeHours 24
        Test-Path $old | Should -BeFalse
        Test-Path $new | Should -BeTrue
    }
    It 'the sweep never touches anything OUTSIDE the root' {
        $outside = Join-Path $TestDrive 'outside'; New-Item -ItemType Directory $outside | Out-Null
        (Get-Item $outside).LastWriteTime = (Get-Date).AddHours(-99)
        Invoke-TestTempSweep -MaxAgeHours 24
        Test-Path $outside | Should -BeTrue
    }
    It 'the sweep tolerates a child it cannot delete' {
        { Invoke-TestTempSweep -MaxAgeHours 0 } | Should -Not -Throw
    }
}
```

- [ ] **Step 2: Implement** (append to `TestTemp.ps1`):
```powershell
function Get-TestTempRoot {
    # ONE parent for every suite's scratch, so a killed run orphans files under ONE directory that the sweep can age out,
    # instead of 30 000 siblings in %TEMP% (measured 2026-10-08: 30 765 directories).
    $root = if ($env:CLAVITY_TEST_TEMP_ROOT) { $env:CLAVITY_TEST_TEMP_ROOT } else { Join-Path ([IO.Path]::GetTempPath()) 'clavity-tests' }
    $null = New-Item -ItemType Directory -Path $root -Force
    $root
}
function New-TestTempPath {
    # Returns a path (not created): '<root>/<prefix>-<guid>'. $Suffix is for the few callers that need an extension.
    param([Parameter(Mandatory)][string]$Prefix, [string]$Suffix = '')
    Join-Path (Get-TestTempRoot) ("$Prefix-" + [Guid]::NewGuid().ToString('N') + $Suffix)
}
function Invoke-TestTempSweep {
    # Deletes children of the shared root older than MaxAgeHours. 24 h by default: a paused or overnight run keeps its scratch
    # (agy and the driver agreed 2026-10-08); scratch is small, so a day of slack costs nothing.
    param([double]$MaxAgeHours = 24)
    $root = Get-TestTempRoot
    $cut = (Get-Date).AddHours(-$MaxAgeHours)
    foreach ($c in @(Get-ChildItem -LiteralPath $root -Force -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $cut })) {
        Remove-Item -LiteralPath $c.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# Once per process, at dot-source time (not on every call): a sweep is cheap but not free.
if (-not (Test-Path variable:script:TestTempSwept)) { $script:TestTempSwept = $true; try { Invoke-TestTempSweep } catch { } }
```
Run green. Mutants: sweep compares `-gt` instead of `-lt` → 'older ... KEEPS younger' red; sweep takes `$root = $env:TEMP` → 'never touches anything OUTSIDE' red.

- [ ] **Step 3: Write the discipline gate FIRST (red)** - `scripts/tests/test-temp-discipline.Tests.ps1`:
```powershell
# No suite may reach for the system temp directory directly: scratch goes through scripts/tests/TestTemp.ps1 so a killed
# run orphans files under ONE swept parent. The two EXEMPT sites are listed below, each with its reason.
BeforeAll {
    $script:RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath
    $script:Suites = @(
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'scripts' 'tests') -Filter '*.Tests.ps1' -File
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet' 'install') -Filter '*.Tests.ps1' -File -ErrorAction SilentlyContinue
    ) | Where-Object { $_.Name -ne 'test-temp-discipline.Tests.ps1' -and $_.Name -ne 'TestTemp.Tests.ps1' }
    # file -> quoted line fragment -> reason. A fragment, not a line number, so an ordinary edit cannot move it out of coverage.
    $script:Exempt = @(
        @{ File = 'check-seed-artifacts-synced.Tests.ps1'; Fragment = "'clavity-classic-hooks-json.testbak'"; Reason = 'parks a TRACKED file at a fixed name outside the swept root: a sweep deleting it would destroy the file the test restores' }
        @{ File = 'check-seed-artifacts-synced.Tests.ps1'; Fragment = "'clavity-dotnet-golden-header.testbak'"; Reason = 'same as above' }
    )
    # IgnoreCase: PowerShell environment-variable names are case-insensitive, so `$env:Temp` is the same hole as `$env:TEMP`
    # (measured: no lowercase spelling exists today - 58 suites / 222 lines either way - so this closes a latent evasion).
    $script:Direct = [regex]::new('GetTempPath\s*\(|\$env:TEMP\b|\$env:TMP\b|\[Environment\]::GetEnvironmentVariable\(\s*[''"]TEMP', 'IgnoreCase')
}
Describe 'test temp discipline' {
    It 'found a plausible population of suites' { $script:Suites.Count | Should -BeGreaterThan 60 }
    It 'no suite uses the system temp directory directly, except the named exemptions' {
        $bad = foreach ($s in $script:Suites) {
            $n = 0
            foreach ($l in [IO.File]::ReadAllLines($s.FullName)) {
                $n++
                if ($l.TrimStart().StartsWith('#') -or -not $script:Direct.IsMatch($l)) { continue }
                $ex = @($script:Exempt | Where-Object { $_.File -eq $s.Name -and $l.Contains($_.Fragment) })
                if ($ex.Count -eq 0) { "$($s.Name):$n  $($l.Trim())" }
            }
        }
        $bad -join "`n" | Should -BeExactly '' -Because 'route scratch through New-TestTempPath / Get-TestTempRoot (scripts/tests/TestTemp.ps1)'
    }
    It 'every exemption still matches a real line (a stale exemption is a hole)' {
        foreach ($e in $script:Exempt) {
            $hit = [IO.File]::ReadAllLines((Join-Path $script:RepoRoot 'scripts' 'tests' $e.File)) | Where-Object { $_.Contains($e.Fragment) }
            @($hit).Count | Should -BeGreaterThan 0 -Because "exemption '$($e.Fragment)' in $($e.File) must still exist"
        }
    }
    It 'every suite that uses New-TestTempPath or Get-TestTempRoot can reach TestTemp.ps1' {
        $missing = foreach ($s in $script:Suites) {
            $t = [IO.File]::ReadAllText($s.FullName)
            if ($t -match 'New-TestTempPath|Get-TestTempRoot|Remove-TestPath' -and $t -notmatch 'TestTemp\.ps1|BashHookHelpers\.ps1') { $s.Name }
        }
        $missing -join ', ' | Should -BeExactly ''
    }
}
```
Run: red - the second row lists ~58 suites.

- [ ] **Step 4: The migration rule and the file list**

The list is the second row's failure output, pasted into the dispatch (the executor runs `Invoke-Pester scripts/tests/test-temp-discipline.Tests.ps1`, copies the `file:line` list; it is the oracle's own list, not an assumption). Transformation rule, the ONLY edit shapes:
  1. `Join-Path ([IO.Path]::GetTempPath()) ("PFX-" + [Guid]::NewGuid().ToString('N'))` (any equivalent spelling: `[guid]::NewGuid().Guid`, `"$PID"`, `Get-Random` as the unique part) → `New-TestTempPath 'PFX'`.
  2. A fixed-name file under temp (`'vanished-transcript.jsonl'`, `"mktemp-$tag.sh"`, `"scoped-ghidrust-$PID.json"`) → `Join-Path (Get-TestTempRoot) '<same name>'`.
  3. `$env:TEMP`/`$env:TMP` joined with a prefix → `New-TestTempPath` / `Join-Path (Get-TestTempRoot) ...`. Where a suite SETS `$env:TMPDIR`/`$env:TEMP` for a child process (`assertion-strength-reminder.Tests.ps1:73-75`), the value becomes the new path; the restore logic is untouched.
  4. Add `. (Join-Path $PSScriptRoot 'TestTemp.ps1')` as the first line of that suite's `BeforeAll` ONLY if the suite does not already dot-source `BashHookHelpers.ps1`.
  5. `assertion-strength-reminder.Tests.ps1` and `docs-audit-reminder.Tests.ps1`, which never removed what they created: add `AfterAll { Remove-TestPath <their dir variable(s)> }` (the sweep is the backstop, not the plan).
  6. `BashHookHelpers.ps1`'s `New-TempRepo` and every `sp-d-*` allocation use `New-TestTempPath`.
  Nothing else: no assertion, no test name, no `It` count changes. Per-suite oracle: the suite's `Passed` count before == after, `Failed: 0`.
  Batches (Sonnet, one dispatch per batch, driver reviews each diff): the list from Step 3 sorted alphabetically, 8 files per batch; the order does not matter.

- [ ] **Step 5: The `.testbak` hazard (pre-existing, found by this consult)** - `check-seed-artifacts-synced.Tests.ps1:104-111` and `:168`: a kill between `Move-Item $f $bak` and the `finally` leaves the TRACKED `clavity-classic/plugin/hooks/hooks.json` / golden-header seed missing from the working tree with the only copy in `%TEMP%`. Add a `BeforeAll` recovery: if either `.testbak` exists at suite start, `Move-Item` it back to its tracked path (and report `RESTORED-FROM-KILLED-RUN` via `Write-Warning`). Failing control first: a row that creates a `.testbak`, removes the tracked file, runs the recovery function, and asserts the tracked file is back. Mutant: remove the `Move-Item` → that row red.

- [ ] **Step 6: Run everything this touches** - `pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-temp-discipline.Tests.ps1 -Output Detailed -CI"` → `Failed: 0`; then, BACKGROUNDED by the driver (the full fast gate can exceed 600 s... it is the FAST gate, ~480 s measured; the slow gate certainly does): `just test-scripts-fast` and `just test-scripts-slow`, each to a task output file, one at a time, with NO other tool call during a run (timing discipline). Expected: `Tests Passed:` lines with `Failed: 0` for both. Afterwards: `ls "$TEMP/clavity-tests" | wc -l` is small and `ls "$TEMP" | wc -l` did not grow by hundreds (record both numbers). The 30 765 pre-existing directories are the OWNER's to delete from their own `%TEMP%`; the plan does not touch them.

- [ ] **Step 7: Register + commit** - justfile fast list: `test-temp-discipline.Tests.ps1`; `_partition.md` rows; the stub `docs/backlog/pester-temp-dirs-orphan-on-killed-runs.md` status → `IMPLEMENTED` with the corrected scope (58 suites, not 29); `git add` the explicit file list (`git status --short` first); `git commit -m "fix(tests): one swept temp root for every Pester suite + a gate that forbids direct temp use"`.

---

### Task 7: §56 - never-audited roster docs become visible

**Files:** Modify `scripts/docs-audit-lib.ps1:152-189`, `scripts/docs-audit.ps1:279`, `scripts/tests/docs-audit.Tests.ps1`, `scripts/tests/docs-audit-reminder.Tests.ps1`.

- [ ] **Step 1: Failing rows** (`docs-audit.Tests.ps1`, in the `FindingsStore merge/write/render` Describe near `:236`):
```powershell
    It 'Get-FindingsSummary counts roster docs that have NO store entry as NeverAudited' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R1' -Result @{ Outcome='CLEAN'; ClaimsInspected=3; Findings=@() } | Out-Null
        $sum = Get-FindingsSummary -Store $s -Roster @('A.md','B.md','C.md')
        $sum.NeverAudited | Should -Be 2
        $sum.Unconfirmed  | Should -Be 0
    }
    It 'Get-FindingsSummary does not count a retired doc (in the store, off the roster) as anything' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'Gone.md' -RunId 'R1' -Result @{ Outcome='FINDINGS'; ClaimsInspected=1; Findings=@(@{kind='X';docPath='Gone.md';docLine=1;codeRef='c';text='t'}) } | Out-Null
        (Get-FindingsSummary -Store $s -Roster @('A.md')).NeverAudited | Should -Be 1
        (Get-FindingsSummary -Store $s -Roster @('A.md')).Findings | Should -Be 0
    }
    It 'Render-FindingsView renders a never-audited roster doc as an AUDIT-NEVER section' {
        $s = Read-FindingsStore $script:Json
        Render-FindingsView -Store $s -Path $script:Md -Roster @('B.md')
        $t = Get-Content -LiteralPath $script:Md -Raw
        $t | Should -Match '(?m)^## B\.md — AUDIT-NEVER \(claims inspected: 0\)$'
        $t | Should -Match '<!-- doc:B\.md start -->'
    }
    It 'Render-FindingsView with NO roster renders no never-audited section (no roster, nothing to be missing from)' {
        $s = Read-FindingsStore $script:Json
        Render-FindingsView -Store $s -Path $script:Md
        (Get-Content -LiteralPath $script:Md -Raw) | Should -Not -Match 'AUDIT-NEVER'
    }
    It 'a roster doc that IS in the store is rendered once, not also as never-audited' {
        $s = Read-FindingsStore $script:Json
        Merge-DocResult -Store $s -DocPath 'A.md' -RunId 'R1' -Result @{ Outcome='CLEAN'; ClaimsInspected=3; Findings=@() } | Out-Null
        Render-FindingsView -Store $s -Path $script:Md -Roster @('A.md')
        ([regex]::Matches((Get-Content -LiteralPath $script:Md -Raw), '## A\.md')).Count | Should -Be 1
    }
```
and in `docs-audit-reminder.Tests.ps1` (after the row at `:64`): a row whose view contains `"## N.md $($script:Dash) AUDIT-NEVER (claims inspected: 0)", '', '- (no findings)'` and asserts the nudge reports `1 unconfirmed doc`. Run red (`NeverAudited` property absent; no section).

- [ ] **Step 2: Implement** - in `Get-FindingsSummary` (`:180`):
```powershell
function Get-FindingsSummary([hashtable]$Store, [string[]]$Roster) {
    $findings = 0; $withFindings = 0; $unconfirmed = 0
    foreach ($doc in @($Store.docs.Keys | Where-Object { $Roster -contains $_ })) {
        $e = $Store.docs[$doc]
        $n = @($e['findings']).Count
        if ($n -gt 0) { $findings += $n; $withFindings++ }
        if (@('CLEAN','FINDINGS') -notcontains $e['outcome']) { $unconfirmed++ }
    }
    # A roster doc with NO store entry has never been audited (ROADMAP section 56): invisible before, because both the view and this
    # summary were built from the store alone.
    $never = @($Roster | Where-Object { $_ -and -not $Store.docs.ContainsKey($_) }).Count
    [pscustomobject]@{ Findings = $findings; DocsWithFindings = $withFindings; Unconfirmed = $unconfirmed; NeverAudited = $never }
}
```
In `Render-FindingsView` (`:152`), after the `foreach ($doc in $keys)` loop and before `$tmp = ...`:
```powershell
    # Roster docs with no store entry: render them as AUDIT-NEVER so the SessionStart nudge (re_unc='^## .+ — AUDIT-') counts them
    # with no hook change. Only when a roster was supplied.
    if ($null -ne $Roster) {
        foreach ($doc in @($Roster | Where-Object { $_ -and -not $Store.docs.ContainsKey($_) } | Sort-Object)) {
            $lines.Add("<!-- doc:$doc start -->")
            $lines.Add("## $doc — AUDIT-NEVER (claims inspected: 0)")
            $lines.Add('- (no findings)')
            $lines.Add("<!-- doc:$doc end -->")
            $lines.Add('')
        }
    }
```
(the dash is the em dash `—`, as in the existing line 166). `docs-audit.ps1:279`: append `; $($sum.NeverAudited) roster doc(s) never audited.` to the end-of-run `Write-Host`.
Note the interaction: a store holding a non-confirming outcome (`AUDIT-TIMEOUT`) is NOT "never audited" (it is in the store) - covered by the existing rows at `:236-250`, which must stay green.

- [ ] **Step 3: Green + mutants** - `pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/docs-audit.Tests.ps1','scripts/tests/docs-audit-reminder.Tests.ps1') -Output Detailed -CI"` → `Failed: 0` (both are in the SLOW list; the driver runs them backgrounded). Mutants: drop the `-not $Store.docs.ContainsKey` filter in Render → 'rendered once, not also as never-audited' red; render `AUDIT NEVER` (no hyphen) → the reminder row red.

- [ ] **Step 4: Update the ROADMAP entry text** - §56's fix outline claimed the `AUDIT-` regex would match a `NEVER AUDITED` header; append `(superseded 2026-10-08: the section is named AUDIT-NEVER, which does match; measured)`; status → `IMPLEMENTED`. `scripts/README.md`/`docs-spec` need no change (no new file).

- [ ] **Step 5: Commit** - `git add scripts/docs-audit-lib.ps1 scripts/docs-audit.ps1 scripts/tests/docs-audit.Tests.ps1 scripts/tests/docs-audit-reminder.Tests.ps1 clavity-dotnet/ROADMAP.md`; `fix(docs-audit): a roster doc that was never audited shows up in the view, the summary and the nudge (section 56)`.

---

### Task 8: §36 - one test recipe for both dotnet projects, and the zero-collection record

**Files:** Modify `clavity-dotnet/justfile:11-14`, `clavity-dotnet/ROADMAP.md` (§36 body), `docs/superpowers/specs/2026-10-08-final-sweep-sequence-design.md` row 26 (the spec's "small closure" text, corrected).

- [ ] **Step 1: Failing control** - measure the gap first: `cd clavity-dotnet && just --dry-run test 2>&1` prints exactly ONE `dotnet test` line (the control; it must show only `tests/Clavity.Ls.Tests`).

- [ ] **Step 2: Edit the recipe**
```just
# Unit + integration tests - the SAME two projects ci-dotnet.yml runs (it calls this recipe).
# Clavity.Live.Acceptance is DELIBERATELY not here: it needs a live agy peer (owner-run only, ROADMAP section 36).
test:
    dotnet test tests/Clavity.Ls.Tests
    dotnet test tests/Clavity.Integration.Tests
```
Verify: `cd clavity-dotnet && just --dry-run test 2>&1` prints TWO lines, the expected pair. Then the driver runs `just dotnet::test` from the repo root (backgrounded; expect both suites `Passed`, counts recorded; the Ls count is the memory banner's 433-class number, the Integration 151-class number - record what is measured).
Root `justfile:17` (`test: dotnet::test classic::test`) now runs both dotnet projects: note it in the commit message; `just test` takes longer by the integration suite (~20 s, measured in `ci-dotnet.yml:26-32`'s comment).

- [ ] **Step 3: Record the rest of §36 in its body** (no code): (a) shape 1 (`classic::pytest` CI wiring) was closed 2026-09-05 and is confirmed by `ci-classic.yml:48-90`; (b) `Clavity.Live.Acceptance` is a named exemption (owner-run, needs a live agy); (c) three zero-collection python files `test_client.py`, `test_isolation.py`, `tests/test_hooked_commit.py` under `clavity-classic/agy-mcp-bridge/` are recorded as collecting zero tests (state the measurement command: `uv run pytest --collect-only -q <file>` printing `no tests collected`; the driver runs it and pastes the output); (d) the three `test-scripts*` recipes decision is: keep `-fast`/`-slow` explicit (the partition is measured, `_partition.md`), `test-scripts` stays the glob and is documented as "everything under scripts/tests"; the full redesign (directory partitioning vs census gate vs CI-as-dumb-executor) is recorded as NOT built, with `CLOSED-BY-RULING` and a Non-goals bullet `- **§36 - the full orphaned-tests redesign** (closed by ruling 2026-10-08): ...Reopen if a suite is found unregistered by hand.` Status of §36 → `IMPLEMENTED` (the recipe) - but because the redesign is ruled out and the recipe is the closure, the entry's final token after merge is `SHIPPED`.
Correct the spec row 26 text ("the recipe decision plus whatever measurement shows is cheap" → "make `just dotnet::test` run both projects; record the exemptions and the zero-collection files; the redesign is not built") and its stale premise ("pytest not in CI").

- [ ] **Step 4: Commit** - `git add clavity-dotnet/justfile clavity-dotnet/ROADMAP.md docs/superpowers/specs/2026-10-08-final-sweep-sequence-design.md`; `fix(dotnet): just dotnet::test runs both test projects, like CI (section 36)`.

---

### Task 9: ci-dotnet calls `just test` (separable; the owner can drop this task)

**Files:** Modify `.github/workflows/ci-dotnet.yml:26-32`.

**MEASURED PREMISE:** no workflow in this repository installs or invokes `just` today. This task introduces `just` into CI for the first time, so it cannot be verified locally (circuit-breaker rule: do not iterate remotely to dodge a missing local tool).

- [ ] **Step 1: Decide the install step against the repo's own conventions** - read how the other workflows install tools (`choco install ... --no-progress -y` with a retry loop at `ci-scripts.yml:112-122`; `actions/setup-dotnet@v6`). The runner here is the `ci-dotnet.yml` job's `runs-on` (read it first). Pin to an exact, at least two-weeks-old version per the repo's action-pinning style. If a first-party-or-widely-used action cannot be pinned to a verified exact version from within this repository's existing usage, STOP and report `STATE_MISMATCH: no verifiable just-install step` to the driver - the fallback is to leave `ci-dotnet.yml` unchanged and add a CI-side drift check instead: a Pester row in `check-roadmap-claims`'s neighbour suite asserting the two `dotnet test` lines in `ci-dotnet.yml` are exactly the projects the `clavity-dotnet/justfile` `test` recipe lists. (That fallback fully closes shape 2 mechanically without `just` in CI, and is the recommendation if there is any doubt.)
- [ ] **Step 2 (only if Step 1 found a pinned install step):** replace `- run: dotnet test tests/Clavity.Ls.Tests` and `- run: dotnet test tests/Clavity.Integration.Tests` with the install step plus `- run: just test`, keeping the explanatory comment (updated). Commit; the owner pushes and the first CI run is the proof - state in the handoff that this is the one change in Branch T that only a pushed CI run verifies.
- [ ] **Step 3 (fallback path):** create `scripts/tests/dotnet-test-parity.Tests.ps1` (register it in `test-scripts-fast`, give it a `_partition.md` row), red first by editing the justfile recipe temporarily to list one project, then green:
```powershell
# ci-dotnet.yml and clavity-dotnet/justfile `test` must run the same dotnet test projects (ROADMAP section 36, shape 2).
BeforeAll {
    $script:Root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..' '..')).ProviderPath
    function Get-TestProjects([string]$Rel, [string]$LinePattern) {
        $raw = [IO.File]::ReadAllLines((Join-Path $script:Root ($Rel -replace '/', [IO.Path]::DirectorySeparatorChar)))
        @($raw | Where-Object { $_ -match $LinePattern } | ForEach-Object { [regex]::Match($_, 'dotnet test\s+(\S+)').Groups[1].Value }) | Sort-Object
    }
}
Describe 'dotnet test projects: local recipe and CI agree' {
    It 'the justfile recipe and ci-dotnet.yml run exactly the same projects' {
        $local = Get-TestProjects 'clavity-dotnet/justfile' '^\s+dotnet test\s'
        $ci    = Get-TestProjects '.github/workflows/ci-dotnet.yml' '^\s*-\s*run:\s*dotnet test\s'
        $local.Count | Should -BeGreaterThan 1 -Because 'the recipe must name both Ls.Tests and Integration.Tests'
        ($local -join ',') | Should -BeExactly ($ci -join ',')
    }
}
```
Mutant: remove the Integration line from the justfile → the row goes red. Commit `test(ci): ci-dotnet and the dotnet justfile run the same test projects`. (If Step 2 ran instead, ci-dotnet.yml calls `just test`, the `^\s*-\s*run:\s*dotnet test` pattern finds nothing, and this suite is not created.)

---

### Task 10: Branch gates, capstone, test-audit, merge (driver)

- [ ] **Step 1: Full gates, one at a time, backgrounded, no other tool call during a run** - `just test-scripts-fast`, then `just test-scripts-slow`, then `bash scripts/check-seed-artifacts-synced.sh`, `just check-tracker-status`, `just check-tracker-format-excerpt`, `just check-agy-skills`, `just check-doc-stubs`, `just check-user-facing-docs`, `just check-member-docs`, `just check-control-bytes`, `cd clavity-dotnet && just test`. Expected: every `Tests Passed:` line shows `Failed: 0` (no `Tests Passed:` line = an aborted run); every gate exits 0. Report timings as ranges with "background load uncontrolled".
- [ ] **Step 2: AGY-CAPSTONE** on `c1e92abd..HEAD` (executable code and tests only - the gate, Check C, the helpers, the §56 code, the recipe; the migration's text diff is reviewed for LOSS by the Task 4 oracle, not by the peer), rounds until GREEN, reading probe and envelope diff-after every round, ledger row BEFORE the marker, marker at the reviewed tip. Seams under `.clavity/seams/branch-t-capstone*.md`.
- [ ] **Step 3: AGY-TEST-AUDIT** over the same range; fold the verified gaps the owner scopes; ledger; marker.
- [ ] **Step 4: Flip statuses to the post-merge state** in the same commit as the merge notes: `IMPLEMENTED` → `SHIPPED <merge sha>` for §34, §36, §56, §77 and the pester-temp-dirs stub (the merge sha is known only after the merge: do it as the first commit on `main` after `git merge --no-ff`, a docs-only commit citing the merge commit), run `just check-tracker-status`.
- [ ] **Step 5: Merge** `git merge --no-ff sweep/branch-t-format-and-gates` into local `main`; the OWNER pushes. Update the durable index (`project_final-sweep_execution.md`, the MEMORY.md resume point) after EACH commit, not in a batch.

---

## Self-review

**Spec coverage** (spec Branch T row + format decision + batch ruling): format file + excerpt in `open-issues`/`agy-capstone`/`agy-test-audit` of both plugins + parity check → Tasks 1, 3. Gate refusing malformed lines / requiring evidence per closed token / listing open items / covering fix-the-tool and voiding boundary H → Tasks 1, 4 (steps 6, 9). §77 absorbed → Task 2. Normalisation of all trackers with the batch rulings (§18, §27, §7, §13c, §58, §14h*, §15, §16, §21, §37, `agy-verify-needed` outside the bar) and the §29b/§31 splits → Task 4 and the TSV. §34 → Task 5. pester-temp-dirs → Task 6. §56 → Task 7. §36 small closure → Tasks 8-9. (*§14h is inside §14, closed by the step-0 ruling and its Non-goals bullet; §16's sub-question is closed by the step-0 §16 bullet - both already present.) The spec's Done-check scans → Task 4 step 8. Fourth tracker (`agy-autotrain/ROADMAP.md`) → in the gate and the table.

**Placeholder scan:** the only deliberate non-literal items are (1) the Task 4 transform script, given as an algorithm with its helper functions in code and the per-file-kind rules in comments, because the apply is driven by the TSV and the gate is its oracle; (2) the Task 6 file list, which is the discipline gate's own failure output (an oracle, not a guess); (3) Task 9's install step, which cannot be decided without reading the workflow and has a fully specified fallback. `UNMEASURED` in `_partition.md` rows is filled by the driver.

**Type/name consistency:** `Remove-TestPath`, `Get-TestTempRoot`, `New-TestTempPath`, `Invoke-TestTempSweep` (Tasks 5-6); `CLAVITY_TEST_TEMP_ROOT` (Task 6 only); gate tokens `NO-STATUS BAD-TOKEN BAD-DATE HEADING-STATUS NO-SHA PHANTOM NO-NONGOALS NO-REOPEN NO-REASON RELEASED-ON-UNSHIPPED BAD-RELEASED NO-TITLE NO-DATE MISSING-TRACKER SHALLOW` (Task 1, used by Task 4's row); Check C tokens `OUT-OF-RANGE ANCHOR-MISS` (Task 2); `AUDIT-NEVER` / `NeverAudited` (Task 7).

**Open items surfaced for the owner at handoff:** (1) Fork 3's agreed scope (all suites + named exemptions) awaits confirmation; (2) the measured correction that no workflow runs `just` (Task 9 separable, fallback recommended if in doubt); (3) the Task 4 batch of JUDGE and no-sha rows; (4) the pre-existing `.testbak` hazard folded into Task 6 step 5; (5) the 30 765 existing `%TEMP%` directories are the owner's to delete.
