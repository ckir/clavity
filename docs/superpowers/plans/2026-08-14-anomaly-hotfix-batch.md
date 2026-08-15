# Anomaly hot-fix batch - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax
> for tracking.

**Goal:** Clear the seven triaged ROADMAP defects (14a, 14b, 14c, 14d, 14e, 13a, 13c) as one reviewable
batch on `feature/injected-context-governance`.

**Architecture:** A new sourced POSIX helper (`agy-shield-lib.sh`) turns the content-blind `.clavity/`
shield assertion into an effect check, and every shipped artifact that writes under `.clavity/` is wired
to it. A new PowerShell generator makes the three "byte-pinned" cheatsheet files structurally impossible
to diverge, enforced by a pre-commit hook that compares INDEX to INDEX. The remaining four items are
small, independent edits to gate scripts, the `justfile` and CI.

**Tech Stack:** POSIX `sh` (shipped plugin hooks), PowerShell 7 (`pwsh`, all `scripts/`), Pester v5,
xUnit (C#), `cargo test` (Rust), `just`, `lefthook`, GitHub Actions.

**Source spec:** `docs/superpowers/specs/2026-08-14-anomaly-hotfix-batch-design.md` (owner-approved,
re-panel GREEN at `3ee37f9`, 16 rounds, probed and held).

---

## READ THIS BEFORE TASK 1

### Plan-authoring measurements (2026-08-14, at `3ee37f9`) - do NOT re-derive

Every line number in this plan was opened and verified while it was written. Two measurements made
during authoring changed the batch, and three more constrain it. They are stated here once.

| # | measurement | consequence |
|---|---|---|
| **M1** | **`$CLAUDE_PLUGIN_ROOT` is UNSET in a skill-context shell call.** Control passed: the same `env` probe saw nine other `CLAUDE_*` variables in the same environment. | Fires the spec's own outcome table at `:652`. **Owner ruled 2026-08-14: measure the fourth locator first (Task 1), auto-fallback to hook-only.** |
| **M2** | **`agy-seam-inject.sh:124` reads the debounce marker at `$cwd_path/.clavity/agy-marks/<d>.head`,** and `:118-122` explicitly forbids the git root: *"Do NOT anchor to git-toplevel: that would diverge from the cwd-relative writer in a launched-from-subdir session and defeat the debounce."* The spec's `agy-mark.sh` contract at `:614` specifies `git rev-parse --show-toplevel`. | **A real spec defect.** `agy-mark.sh` must anchor `head` and `log` to **cwd**, not toplevel. See Task 6. |
| **M3** | `agy-discipline-reaching.sh:2` declares **"CAPTURE ONLY, NO SUBPROCESSES"** and `hooks.json:56` registers it with **`"timeout": 10`**. | Task 5 places the helper call AFTER every early exit and **rewrites that header comment**. |
| **M4** | `check-curate-in-progress.Tests.ps1:335-375` copies the real `lefthook.yml` (`:355`) but only ONE script (`:358`) into a fixture repo, stages a pinned path (`:359`), and asserts `lefthook run pre-commit` exits **0** (`:367`). | Task 11's new lefthook block **would red this existing row**. The fixture is taught the new script in the same task. |
| **M5** | ROADMAP carries the wrong "seven hooks" fact at **three** sites: `:982`, `:988` (*"this entry is the existing seven"*), `:991`. | Task 8 sweeps all three. A grep shaped like `:991`'s wording misses `:988`. |

### The two anchors are DIFFERENT ON PURPOSE - do not harmonise them

| file under `.clavity/` | writer anchors to | reader | verified |
|---|---|---|---|
| `agy-marks/<discipline>.head`, `agy-marks/skipped.log` | **the agent's cwd** (bare relative path) | `agy-seam-inject.sh:124`, cwd-anchored | `agy-first/SKILL.md:109`, `agy-capstone/SKILL.md:266`, `agy-test-audit/SKILL.md:222` |
| `local-anomalies.md` | **`git rev-parse --show-toplevel`** | the SessionStart hook, same resolution | `open-issues/SKILL.md:63-67` - the comment states the pairing |
| `seams/<topic>.md`, `scratch/<topic>/` | **the agent's cwd** (bare relative path) | no programmatic reader | `agy-first/SKILL.md:37`, `agy-capstone/SKILL.md:41`, `:43` |

**Both are correct.** A change to either anchor breaks a reader/writer pairing. This table is the oracle
for Task 6.

### Standing rules that bind EVERY task

1. **Write the failing control BEFORE the fix.** Every task below is ordered that way. A guard whose
   deletion leaves the suite green is untested.
2. **Mutation, not presence.** Each task names the mutation and the row that must turn RED.
3. **Byte-identical pair discipline.** Any change under `clavity-dotnet/plugin/` must be mirrored to
   `clavity-classic/plugin/` and pass `scripts/tests/plugin-hooks-payload.Tests.ps1` and
   `scripts/check-seed-artifacts-synced.sh`. **Verified: all 13 shipped hooks are currently byte-identical
   across the two trees.**
4. **`plugin-hooks-payload.Tests.ps1:26` globs `*.sh`**, so both new plugin files are automatically
   covered by its ASCII row (`:32`) and its byte-identity row (`:47`). They MUST be mirrored.
5. **Pure ASCII inside `$DomainRoots`** (`check-injected-context.ps1:44-53`: `clavity-dotnet/plugin`,
   `clavity-classic/plugin`, `agy-autotrain`, `seed`, and others). Run `just check-injected-context`
   before committing any governed file.
6. **A new top-level `scripts/*.ps1` must be added to `scripts/README.md`** or
   `scripts/tests/scripts-readme-inventory.Tests.ps1:33` reds (it is in the fast partition).
7. **Nothing is pushed** (184 commits ahead of `origin/main` at plan time). **CI cannot gate any of this.**
   Run every oracle locally, BY NAME, and read the COUNT - `dotnet test --filter` exits 0 on no match.
8. **`docs/superpowers/*` is gitignored** (`.gitignore:32`). Committing this plan or the spec needs
   `git add -f`. **Never force-add `.clavity/`.**

### A line number this plan itself invalidates is not a citation (panel R4)

**Five tasks register a test suite, and the first one to run makes every later task's line citation
stale.** Tasks 3, 6, 11 and 13 all add an entry to the same `test-scripts-slow` recipe and Task 10 adds
one to `test-scripts-fast`; each edit changes that line's content, and any edit above it moves its number.
So this plan names the **RECIPE**, never the line, for every `justfile` registration - and the same rule
binds anything else this plan edits more than once. **Re-derive a line number at the moment you use it;
a citation that was true when the plan was written is a claim about a file the plan is actively changing.**

### Stated toolchain assumptions (panel R2, Dependency Cynic)

The shipped helper calls `grep`, `find`, `mkdir`, `mv`, `mktemp` and `git`. **These are pre-existing
platform assumptions of every hook this plugin already ships**, not new ones this batch introduces:
`assertion-strength-reminder.sh:125` and `agy-anomaly-capture-reminder.sh:107` both already run
`find ... -maxdepth 1 ... -delete`, and every hook greps. They are recorded here rather than engineered
around, because the failure modes are real but shared:

| tool | if absent or failing | disposition |
|---|---|---|
| `grep` | A2 falls through to the append branch on **every** call, so the shield grows without bound while Stage B still reports it effective | pre-existing; a plugin without `grep` has larger problems. The idempotence row pins the normal case |
| `find` | the two sweeps fail silently (stderr is redirected); temp files and markers leak | pre-existing and identical to the two sibling hooks. Leakage is bounded by the `-mtime +30` intent, not by correctness |
| `mktemp` | the A2 prepend writes nothing; B3 then correctly reports the negation, so the outcome is a **loud** no-repair rather than a silent one | acceptable - it degrades to reporting, which is Stage B's job |

**`tail` was deliberately removed from the append branch** in favour of an unconditional leading newline on
a non-empty file - one less tool assumed, one less silent failure mode, and a blank line in `.gitignore` is
inert.

### Suite cadence (the 600s foreground cap)

- `just test-scripts-fast` - **cap-adjacent**; background it, block on its `Tests Passed:` line.
- `just test-scripts-slow` - **exceeds the cap**; MUST be backgrounded, blocked on its
  `Tests completed` line, **never on a process count**.
- **Never run two Pester suites at once** (file-lock false red).
- **A log with no `Tests Passed:` line is an ABORTED run, not a pass.**

---

## Task 1: Measure the skill base-directory locator (GATES Task 6 and Task 7)

**Why this is first.** M1 measured `$CLAUDE_PLUGIN_ROOT` as unset in a skill-context shell call, which
fires the spec's blocking outcome at `:652`. The owner ruled that one further locator is measured before
14c is narrowed: the agent harness tells a skill its own base directory at invocation time. If that holds
for a `clavity:`-namespaced skill, the skill body can carry the identical text
`bash "<base>/../../hooks/agy-mark.sh" ...` in both plugins and resolve to a different absolute path in
each - which satisfies the byte-identical-body constraint at `agy-first/SKILL.md:111-112` rather than
violating it, and is none of the three fallbacks the spec forbids at `:652`.

**Files:**
- Read only: `clavity-dotnet/plugin/skills/agy-first/SKILL.md:109-114`
- Read only: `docs/agy-disciplines-marker-contract.md:13-17`
- Create: `docs/superpowers/plans/2026-08-14-anomaly-hotfix-batch-task1-measurement.md`

- [ ] **Step 1: Confirm the blocking measurement still holds, WITH its control**

The control is not optional. A probe that reports "unset" because it cannot see the environment at all is
not an oracle.

```bash
echo "PROBE: CLAUDE_PLUGIN_ROOT=[${CLAUDE_PLUGIN_ROOT:-<UNSET>}]"
echo "CONTROL: the same probe must see OTHER CLAUDE_* variables:"
env | grep -c '^CLAUDE'
```

Expected: `PROBE: CLAUDE_PLUGIN_ROOT=[<UNSET>]` and a CONTROL count **greater than zero**. If the control
prints `0`, the probe is blind and its result means nothing - stop and report
`STATE_MISMATCH: env probe cannot see CLAUDE_* variables`.

- [ ] **Step 2: Measure whether a `clavity:` skill is told its own base directory**

Invoke a clavity-namespaced skill that has **no side effects** and read the harness preamble. Use
`clavity:ls-driving` - it is pure orientation and fires no discipline, no consult and no marker write.

Run (as an agent, via the Skill tool, NOT via bash): `Skill(skill="clavity:ls-driving")`

Read the text the harness emits BEFORE the skill body. Record verbatim whether a line of the form
`Base directory for this skill: <path>` is present, and the exact path if so.

**Do not infer this from the superpowers plugin.** That plugin was measured during plan authoring and
DOES emit the line; the question is whether the `clavity:` plugin does, and only invoking one answers it.

- [ ] **Step 3: Record the measurement and its consequence**

Create `docs/superpowers/plans/2026-08-14-anomaly-hotfix-batch-task1-measurement.md`:

```markdown
# Task 1 measurement - the skill base-directory locator

**Date:** <YYYY-MM-DD>   **Commit:** <output of `git rev-parse HEAD`>

## Probe A - $CLAUDE_PLUGIN_ROOT in a skill-context shell call
- Result: <UNSET | the value>
- Control (count of other CLAUDE_* vars visible to the same probe): <N>

## Probe B - the harness base-directory line for a `clavity:` skill
- Skill invoked: clavity:ls-driving
- Line present: <YES | NO>
- Verbatim line: <the line, or "none emitted">

## Consequence (tick exactly one)
- [ ] **RESOLVED** - Probe B is YES. Tasks 6 and 7 proceed, using
      `bash "<skill base directory>/../../hooks/agy-mark.sh"` as the invocation.
- [ ] **BLOCKED** - Probe B is NO. Tasks 6 and 7 are SKIPPED and recorded as a
      tracked ROADMAP item. Tasks 5 and 8 (the hook half and the ROADMAP rewrite) still ship.
      **Do NOT invent a glob, a search path, or a hardcoded install location** (spec `:652`).
```

- [ ] **Step 4: Commit the measurement**

```bash
git add -f docs/superpowers/plans/2026-08-14-anomaly-hotfix-batch-task1-measurement.md
git commit -m "docs(plan): task 1 - measure the skill base-directory locator"
```

- [ ] **Step 5: Branch the remaining plan**

If **BLOCKED**, mark Tasks 6 and 7 as SKIPPED in this plan file, and add one line to
`clavity-dotnet/ROADMAP.md` section 14c during Task 8 recording that the skill half is deferred and why.
If **RESOLVED**, proceed unchanged.

---

## Task 2: Item 14a - `.clavity` joins `PrunedSegments`

**Why first among the fixes.** `.clavity` is absent from `PrunedSegments`, so the injected-context gate
walks that directory today - and this batch actively creates content there. Landing 14a first removes a
class of spurious gate failures from every task after it.

**Files:**
- Modify: `scripts/check-injected-context.ps1:91-92`
- Test: `scripts/tests/check-injected-context.Tests.ps1`

**Verified current state:**

```powershell
$script:PrunedSegments = @('.git','node_modules','target','bin','obj','.venv','__pycache__','dist','publish','.vs',
                           '.ruff_cache','.pytest_cache','.mypy_cache','.worktrees')
```

and at `:99` the regex is built with per-entry escaping:

```powershell
$script:PruneRx = '(?:^|/)(?:' + (($script:PrunedSegments | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')/'
```

- [ ] **Step 1: Write the failing test**

Append inside the existing top-level `Describe` block in
`scripts/tests/check-injected-context.Tests.ps1`. The controls are LEXICALLY ADJACENT near-misses, not
arbitrary paths: an arbitrary control like `src/foo.md` would pass before the change too and proves
nothing about the new entry.

```powershell
    Context '14a - .clavity is pruned from the reference walk' {
        It 'prunes a path inside .clavity/' {
            Test-IsPrunedPath -RelPath '.clavity/seams/topic.md' | Should -BeTrue -Because '.clavity is runtime state and must never enter the reference index'
        }
        It 'prunes .clavity at the repository root as well as nested' {
            Test-IsPrunedPath -RelPath '.clavity/local-anomalies.md' | Should -BeTrue
            Test-IsPrunedPath -RelPath 'sub/.clavity/local-anomalies.md' | Should -BeTrue
        }
        It 'does NOT prune a PREFIX near-miss' {
            # PruneRx is (?:^|/)<segment>/ so only an EXACT segment match may prune. A control like
            # src/foo.md would pass before this change too and would prove nothing.
            Test-IsPrunedPath -RelPath '.clavity-tmp/foo.md' | Should -BeFalse -Because 'only an exact path SEGMENT may prune'
        }
        It 'does NOT prune a SUFFIX near-miss' {
            Test-IsPrunedPath -RelPath 'x.clavity/foo.md' | Should -BeFalse -Because 'only an exact path SEGMENT may prune'
        }
    }
```

- [ ] **Step 2: Run the test to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"
```

Expected: the two `Should -BeTrue` rows FAIL (`.clavity` is not yet a pruned segment); the two near-miss
rows PASS. **Read the counts** - a run reporting 0 tests is a discovery failure, not a pass.

- [ ] **Step 3: Make the minimal change**

Edit `scripts/check-injected-context.ps1:91-92`, adding `.clavity` to the array:

```powershell
$script:PrunedSegments = @('.git','node_modules','target','bin','obj','.venv','__pycache__','dist','publish','.vs',
                           '.ruff_cache','.pytest_cache','.mypy_cache','.worktrees','.clavity')
```

Change nothing else. `:99` escapes every entry by construction, so no escaping is needed here.

- [ ] **Step 4: Run the test to verify it PASSES**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"
```

Expected: all four new rows PASS and the pre-existing rows are unchanged. Record the total count.

- [ ] **Step 5: Mutation control - the new entry must be load-bearing**

Temporarily remove `,'.clavity'` from the array and re-run. The two `Should -BeTrue` rows MUST turn RED.
If they stay green, the rows are vacuous. Restore the entry afterwards.

- [ ] **Step 6: Run the gate itself over the real tree**

```bash
just check-injected-context
```

Expected: `check-injected-context: OK`.

- [ ] **Step 7: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "fix(gate): 14a - prune .clavity from the injected-context reference walk"
```

---

## Task 3: Item 14d - the shield helper

Build `agy-shield-lib.sh`: a sourced POSIX function that replaces the content-blind
`[ -f "$R/.clavity/.gitignore" ]` idiom with an effect check.

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-shield-lib.sh`
- Create: `clavity-classic/plugin/hooks/agy-shield-lib.sh` (byte-identical mirror)
- Create: `scripts/tests/agy-shield-lib.Tests.ps1`
- Modify: `justfile:107-108` (register the new suite in the SLOW partition)
- Modify: `scripts/tests/_partition.md` (the census table)

### The contract, restated as code obligations

| obligation | why |
|---|---|
| `return 0` **always**, never `exit` | Measured: a sourced `exit 0` ends the CALLER before its next line, and the caller still reports success. A helper written to "always exit 0" would disable every guard after it in every hook that sources it. |
| Three arguments: root, root-relative path, debounce key | The helper must NOT re-derive the root (two derivations can disagree), and a sourced function cannot see the hook's stdin payload where `session_id` lives. |
| An **EMPTY** debounce key is LEGAL | It is the sanctioned way to disable debouncing. `[A-Za-z0-9._-]+` requires at least one character, so running the regex over every key makes the legal empty key a loud never-debounced fault on every call. |
| Every probe redirects stderr | Measured: `grep -qx` on a missing file exits **2** and writes to stderr; `git rev-parse` outside a repo prints `fatal:`; `git ls-files --error-unmatch` prints *"Did you forget to 'git add'?"* on the ordinary untracked path - advice exactly backwards here. |
| `-q` decides, `-v` only explains | Measured: `git check-ignore -v` exits **0** on a file that is NOT ignored, while `-q` exits **1**. One invocation for both inverts B2 and B3. |
| Stage A is unconditional | Measured: with the file TRACKED, `check-ignore` returns 1 whether the shield is intact or emptied. Conditioning Stage A on that made one tracked file disable protection for the whole directory. |
| A2 PREPENDS when a `!` line exists with no bare `*` | Measured: a blind APPEND flips `check-ignore` from 1 to 0, silently overriding a line a human wrote and making the B3 report unreachable. Writing nothing instead exposed every OTHER file in the directory. |
| The prepend temp file lives INSIDE `<root>/.clavity/` | `mv` is atomic only within a filesystem. `mktemp` with no argument defaults to `$TMPDIR`, a different mount, where `mv` degrades to copy-then-delete - and still produces the right bytes whenever nothing races, so the loss is invisible. |

- [ ] **Step 1: Write the failing test suite**

Create `scripts/tests/agy-shield-lib.Tests.ps1`. **Every fixture is a THROWAWAY repo** - a control run
inside this repository reports a FALSE PASS, because the root `.gitignore` already covers `.clavity/` and
git cannot re-include a file whose parent directory is excluded.

```powershell
# Tests for the shipped shield helper, clavity-dotnet/plugin/hooks/agy-shield-lib.sh.
#
# EVERY FIXTURE IS A THROWAWAY REPO, DELIBERATELY. This repository's own root .gitignore covers
# .clavity/, and git cannot re-include a file whose PARENT DIRECTORY is excluded - so the negation
# leak this suite exists to detect is MASKED here and a fixture rooted at the repo would report a
# false pass. Measured 2026-08-14.
#
# The helper is SOURCED, never executed: it returns, it never exits. A test that runs it as a
# process would not exercise the contract that matters.

Describe 'agy-shield-lib.sh' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Lib = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-shield-lib.sh'
        Test-Path -LiteralPath $script:Lib | Should -BeTrue -Because 'the helper must exist for any row here to mean anything'

        # Run a snippet with the helper sourced, inside a fixture repo. Returns an object carrying
        # stdout, stderr and the exit code SEPARATELY - the contract is about stderr specifically,
        # so a merged stream cannot test it.
        function Invoke-Shield {
            param(
                [string]$Root,          # fixture repo root (bash-style path)
                [string]$Body,          # sh to run after sourcing
                [hashtable]$Env = @{}
            )
            $libSh = ($script:Lib -replace '\\', '/')
            $script = ". '$libSh'`n$Body`n"
            $sf = Join-Path ([IO.Path]::GetTempPath()) ("shield-" + [guid]::NewGuid().ToString('N') + ".sh")
            [IO.File]::WriteAllText($sf, ($script -replace "`r`n", "`n"))
            $outF = "$sf.out"; $errF = "$sf.err"
            $prev = @{}
            foreach ($k in $Env.Keys) { $prev[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
            try {
                $p = Start-Process -FilePath 'bash' -ArgumentList @($sf) -WorkingDirectory $Root `
                        -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
                [pscustomobject]@{
                    ExitCode = $p.ExitCode
                    Out      = (Get-Content -Raw -LiteralPath $outF -ErrorAction SilentlyContinue)
                    Err      = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue)
                }
            }
            finally {
                foreach ($k in $Env.Keys) { [Environment]::SetEnvironmentVariable($k, $prev[$k]) }
                Remove-Item -LiteralPath $sf, $outF, $errF -Force -ErrorAction SilentlyContinue
            }
        }

        # A throwaway git repo with NO root .gitignore, so the negation leak is observable.
        function New-FixtureRepo {
            param([string]$Shield, [switch]$NoClavityDir, [string[]]$Track = @())
            $d = Join-Path ([IO.Path]::GetTempPath()) ("shieldfx-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            & git -C $d init -q
            & git -C $d config user.email t@t.t
            & git -C $d config user.name t
            & git -C $d config core.autocrlf false
            if (-not $NoClavityDir) {
                New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
                if ($null -ne $Shield) {
                    [IO.File]::WriteAllText((Join-Path $d '.clavity/.gitignore'), $Shield)
                }
            }
            # A seed commit so HEAD resolves; without it several git probes behave differently.
            [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
            & git -C $d add seed.txt
            & git -C $d commit -q -m seed
            foreach ($t in $Track) {
                $full = Join-Path $d $t
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
                [IO.File]::WriteAllText($full, "tracked`n")
                & git -C $d add -f $t
                & git -C $d commit -q -m "track $t"
            }
            ($d -replace '\\', '/')
        }

        function Get-Shield { param([string]$Root) Get-Content -Raw -LiteralPath (Join-Path $Root '.clavity/.gitignore') -ErrorAction SilentlyContinue }
    }

    Context 'Stage A - shield integrity' {
        It 'leaves a healthy shield untouched (control - it must not churn)' {
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            (Get-Shield $r) | Should -BeExactly $before
            $res.Err | Should -BeNullOrEmpty -Because 'the healthy path is SILENT by contract - it runs on every capture'
        }

        It 'restores an EMPTIED shield (the 14d defect)' {
            $r = New-FixtureRepo -Shield ''
            Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null
            (Get-Shield $r) | Should -Match '(?m)^\*$'
        }

        It 'creates .clavity/ and the shield on a FRESH CLONE (A1)' {
            # Every other row presupposes the directory, so A1 was untestable by the rest of the matrix.
            $r = New-FixtureRepo -NoClavityDir
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            (Test-Path -LiteralPath (Join-Path $r '.clavity')) | Should -BeTrue
            (Get-Shield $r) | Should -Match '(?m)^\*$'
            $res.Err | Should -BeNullOrEmpty -Because 'A1-success is a SILENT branch'
        }

        It 'does NOT concatenate onto a shield with NO trailing newline (panel R1)' {
            # MEASURED with a control: `printf '%s\n' '*' >> file` against a file ending `foo.txt` with no
            # final newline produced the single line `foo.txt*`, while the same append against a file that
            # DID end in a newline produced two lines. The bare * then never exists as its own line, the
            # [ -f ] test still passes, and the shield is silently broken - so this branch would corrupt
            # the file again on every subsequent call.
            $r = New-FixtureRepo -Shield 'foo.txt'   # New-FixtureRepo writes it verbatim, no trailing LF
            Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null
            $lines = (Get-Shield $r) -split "`n"
            $lines | Should -Contain '*' -Because 'the bare * must be its OWN line, not appended to foo.txt'
            (Get-Shield $r) | Should -Not -Match 'foo\.txt\*'
        }

        It 'treats a CRLF shield as already correct - it must not append forever (panel R1)' {
            # This shield is gitignored and never checked out, so .gitattributes cannot normalise it and a
            # human editing it on Windows can leave CRLF - the "created by hand" case 14d exists for.
            # Measured on Git Bash `grep -qx '*'` DID match `*\r\n` (LF control also matched), but that is
            # a platform property, not a guarantee. This row pins the behaviour on BOTH.
            $r = New-FixtureRepo
            [IO.File]::WriteAllText((Join-Path $r '.clavity/.gitignore'), "*`r`n")
            1..3 | ForEach-Object { Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null }
            ([regex]::Matches((Get-Shield $r), '\*')).Count | Should -Be 1 -Because 'a shield that never matches would be appended to on every call and grow without bound'
        }

        It 'is IDEMPOTENT - three runs leave exactly one bare * line' {
            $r = New-FixtureRepo -Shield ''
            1..3 | ForEach-Object { Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null }
            $stars = ([regex]::Matches((Get-Shield $r), '(?m)^\*$')).Count
            $stars | Should -Be 1
        }
    }

    Context 'A2 middle case - a negation with no bare *' {
        # THREE properties, because each one failed in a different draft of this branch. Asserting
        # only "a fault was reported" passes against BOTH broken versions.
        BeforeEach {
            $script:R = New-FixtureRepo -Shield "!local-anomalies.md`n"
            $script:Res = Invoke-Shield -Root $script:R -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
        }

        It '(a) the human INTENT survives - the named file is still NOT ignored' {
            # The blind-append version destroyed this: appending * after a negation INVERTS it.
            & git -C $script:R check-ignore -q -- '.clavity/local-anomalies.md'
            $LASTEXITCODE | Should -Be 1 -Because 'last-match-wins: the human !line must still win for the file it names'
        }

        It '(b) the DIRECTORY is protected - another file in it IS ignored' {
            # The write-nothing version broke this: it exposed every other file to protect one.
            [IO.File]::WriteAllText((Join-Path $script:R '.clavity/other-marker.md'), "x`n")
            & git -C $script:R check-ignore -q -- '.clavity/other-marker.md'
            $LASTEXITCODE | Should -Be 0 -Because 'the bare * must cover everything the negation does not name'
        }

        It '(c) the ! line is still present and unmodified' {
            (Get-Shield $script:R) | Should -Match '(?m)^!local-anomalies\.md$'
        }

        It 'PREPENDS - the bare * is the FIRST line' {
            (Get-Shield $script:R) -split "`n" | Select-Object -First 1 | Should -BeExactly '*'
        }

        It 'reports the negation loudly (B3, untracked)' {
            $script:Res.Err | Should -Match 'local-anomalies\.md'
        }

        It 'leaves NO temp file behind' {
            @(Get-ChildItem -LiteralPath (Join-Path $script:R '.clavity') -Filter '.gitignore.tmp.*' -Force -ErrorAction SilentlyContinue).Count |
                Should -Be 0 -Because 'the prepend temp is consumed by mv on success and removed on every failure path'
        }
    }

    Context 'Stage B - effect verification' {
        It 'reports the git rm --cached remedy for a TRACKED path, shield intact afterwards' {
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            $res.Err | Should -Match 'git rm --cached'
            (Get-Shield $r) | Should -Match '(?m)^\*$'
        }

        It 'restores an EMPTIED shield even when the path is TRACKED (the Stage A regression pin)' {
            # Broken until re-panel round 2: a per-file condition suppressed a per-directory guarantee.
            $r = New-FixtureRepo -Shield '' -Track @('.clavity/local-anomalies.md')
            Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"' | Out-Null
            (Get-Shield $r) | Should -Match '(?m)^\*$' -Because 'Stage A is UNCONDITIONAL; one tracked file must never disable the directory guarantee'
        }

        It 'outside a git work tree: the text fallback runs and NOTHING is reported' {
            $d = Join-Path ([IO.Path]::GetTempPath()) ("shieldbare-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            $r = ($d -replace '\\', '/')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "k1"'
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) | Should -Match '(?m)^\*$'
            $res.Err | Should -BeNullOrEmpty -Because 'B1 is a SILENT branch - Stage A has already guaranteed the text'
        }
    }

    Context 'A0 - argument validation is LOUD and never silent' {
        It 'refuses an empty root, writes nothing, and WARNS' {
            $r = New-FixtureRepo -Shield "*`n"
            $res = Invoke-Shield -Root $r -Body 'agy_shield "" ".clavity/local-anomalies.md" "k1"'
            $res.Err | Should -Not -BeNullOrEmpty -Because 'a bad argument means the CALLER is broken and is about to write private data'
            (Test-Path -LiteralPath '/.clavity') | Should -BeFalse -Because 'mkdir -p "$1/.clavity" with an empty $1 would create a directory at the filesystem root'
        }

        It 'refuses a root that is not a directory, writes nothing, and WARNS' {
            $r = New-FixtureRepo -Shield "*`n"
            $res = Invoke-Shield -Root $r -Body 'agy_shield "/definitely/not/here" ".clavity/local-anomalies.md" "k1"'
            $res.Err | Should -Not -BeNullOrEmpty
        }

        It 'refuses a path OUTSIDE .clavity/, writes nothing, and WARNS' {
            # No false "repaired" report for a file left fully exposed - and no silence either.
            $r = New-FixtureRepo -Shield "*`n"
            $before = Get-Shield $r
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" "docs/secret.md" "k1"'
            $res.Err | Should -Not -BeNullOrEmpty
            (Get-Shield $r) | Should -BeExactly $before
        }

        It 'refuses a path containing ..' {
            $r = New-FixtureRepo -Shield "*`n"
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/../../escape.md" "k1"'
            $res.Err | Should -Not -BeNullOrEmpty
        }

        It 'ALWAYS returns 0 - it must never hard-block a caller' {
            $r = New-FixtureRepo -Shield "*`n"
            foreach ($args in @('"" "x" "k"', '"$PWD" "docs/secret.md" "k"', '"$PWD" ".clavity/local-anomalies.md" "k"')) {
                $res = Invoke-Shield -Root $r -Body "agy_shield $args; echo RC=`$?"
                $res.Out | Should -Match 'RC=0'
            }
        }

        It 'does NOT kill its CALLER - the line after the call still runs' {
            # Measured: a sourced `exit 0` ended the parent before its next line, and the parent
            # still reported success. This row is the pin for `return`, never `exit`.
            $r = New-FixtureRepo -Shield "*`n"
            $res = Invoke-Shield -Root $r -Body 'agy_shield "" "x" "k"' -Env @{}
            $res2 = Invoke-Shield -Root $r -Body "agy_shield `"`" `"x`" `"k`"`necho STILL_ALIVE"
            $res2.Out | Should -Match 'STILL_ALIVE' -Because 'a sourced exit would terminate the caller silently'
        }
    }

    Context 'the debounce key' {
        It 'emits a PERSISTENT fault ONCE for the same key' {
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k = 'samekey-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k`""
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 1
        }

        It 'emits the SAME fault AGAIN under a DIFFERENT key' {
            # WITHOUT THIS ROW THE KEY IS NEVER EXERCISED: an implementation that ignores the key and
            # writes one hardcoded global marker satisfies the same-key row trivially, while destroying
            # the per-session isolation the key exists for.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $k1 = 'k1-' + [guid]::NewGuid().ToString('N')
            $k2 = 'k2-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k1`"`nagy_shield `"`$PWD`" `".clavity/local-anomalies.md`" `"$k2`""
            ([regex]::Matches($res.Err, 'git rm --cached')).Count | Should -Be 2
        }

        It 'an EMPTY key is LEGAL - debouncing off, no validation fault' {
            # [A-Za-z0-9._-]+ requires >=1 char, so running the regex over EVERY key made the
            # sanctioned empty key a loud never-debounced fault on every single call.
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" ""'
            $res.Err | Should -Match 'git rm --cached'
            $res.Err | Should -Not -Match 'REFUSING'
        }

        It 'a VALIDATION fault is emitted BOTH times under the same key' {
            # Only a repeat test can tell the two debounce policies apart.
            $r = New-FixtureRepo -Shield "*`n"
            $k = 'vk-' + [guid]::NewGuid().ToString('N')
            $res = Invoke-Shield -Root $r -Body "agy_shield `"`$PWD`" `"docs/secret.md`" `"$k`"`nagy_shield `"`$PWD`" `"docs/secret.md`" `"$k`""
            ([regex]::Matches($res.Err, 'REFUSING')).Count | Should -Be 2 -Because 'a broken CALLER must not be silenced by a marker'
        }

        It 'a MALFORMED key does not disable the guard' {
            $r = New-FixtureRepo -Shield "*`n" -Track @('.clavity/local-anomalies.md')
            $res = Invoke-Shield -Root $r -Body 'agy_shield "$PWD" ".clavity/local-anomalies.md" "../../escape"'
            $res.Err | Should -Match 'git rm --cached' -Because 'a malformed session id must never disable a data-leak guard'
            (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) '../../escape')) | Should -BeFalse
        }
    }
}
```

- [ ] **Step 2: Run the suite to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-shield-lib.Tests.ps1 -Output Detailed -CI"
```

Expected: every row FAILS or errors - `agy-shield-lib.sh` does not exist yet. The `Test-Path` guard in
`BeforeAll` fires first. **Read the count.**

- [ ] **Step 3: Write the helper**

Create `clavity-dotnet/plugin/hooks/agy-shield-lib.sh`. **Pure ASCII. LF line endings.**

```sh
#!/usr/bin/env bash
# .clavity/ shield helper (plugin-shipped). SOURCED, never executed.
#
# WHY THIS EXISTS. The idiom it replaces - `[ -f "$R/.clavity/.gitignore" ]` - restores a DELETED
# shield and nothing else. Measured in a throwaway repo, it is WRONG in three of four states: an
# emptied shield, a shield carrying a `!` negation, and a file already TRACKED all pass the file-exists
# test while the directory is leaking.
#
# RETURN, NEVER EXIT. This file is sourced into the calling hook, so `exit` terminates the CALLER.
# MEASURED: a sourced snippet containing `exit 0` ended the parent before its next line ran, the
# parent's remaining guards were silently skipped, and the parent still reported success. A helper
# written to "always exit 0" would disable every check that follows it in every hook that sources it.
# These hooks fail open by design (exit 2 on PreToolUse BLOCKS an agent), and the mechanism for that
# is `return`.
#
# EVERY PROBE REDIRECTS STDERR AND IS JUDGED BY ITS EXIT CODE ALONE. Measured: `grep -qx` on a missing
# file exits 2 (not 1) AND writes to stderr; `git rev-parse --is-inside-work-tree` prints `fatal:`
# outside a repo, which is a NORMAL state for a skill shipping into non-repositories; and
# `git ls-files --error-unmatch` prints "Did you forget to 'git add'?" on the ordinary UNTRACKED path -
# advice exactly backwards here, since the whole point is that the file must NOT be added. The
# helper's own messages are the only thing it may print.
#
# `-q` DECIDES, `-v` ONLY EXPLAINS. Measured: `git check-ignore -v` exits 0 on a file that is NOT
# ignored (it treats having output as success) while `-q` exits 1 on the same file. Reusing one `-v`
# invocation for both the decision and the message INVERTS B2 and B3 - a leaking file would be read as
# ignored, and the guard would pass on exactly the state it exists to catch.
#
# Args: $1 = repository root  $2 = path to protect, RELATIVE to that root, under .clavity/
#       $3 = debounce key (the caller's session id; EMPTY is legal and disables debouncing)
# Returns: 0, always.

_AS_CR=$(printf '\r')   # a literal CR, for the optional-trailing-CR shield match in A2.

# Emit one line on stderr, at most once per (key, class). An empty key disables debouncing.
# Class VALIDATION is NEVER debounced - a broken caller must be visible on every call.
_agy_shield_say() {
    _ass_class=$1
    _ass_key=$2
    _ass_msg=$3

    if [ "$_ass_class" = "validation" ] || [ -z "$_ass_key" ]; then
        printf 'agy-shield: %s\n' "$_ass_msg" >&2
        return 0
    fi

    _ass_dir=''
    for _ass_cand in "${TMPDIR:-/tmp}" "$HOME/.clavity-tmp"; do
        [ -n "$_ass_cand" ] || continue
        mkdir -p "$_ass_cand" 2>/dev/null || continue
        if [ -w "$_ass_cand" ]; then _ass_dir=$_ass_cand; break; fi
    done
    if [ -z "$_ass_dir" ]; then
        # No writable marker location: emit rather than swallow. A data-leak notice must never be
        # lost because the debounce store is unavailable.
        printf 'agy-shield: %s\n' "$_ass_msg" >&2
        return 0
    fi

    _ass_marker="$_ass_dir/.clavity-shield-$_ass_class-$_ass_key"
    if [ -f "$_ass_marker" ]; then
        return 0
    fi
    : > "$_ass_marker" 2>/dev/null
    # PRUNE OUR OWN PREFIX ONLY, and only on the run that CREATED a marker - never on the hot path.
    # The siblings prune '.clavity-anomaly-*' and '.clavity-assert-*'; reusing either prefix would
    # delete another hook's markers on our schedule, and a broader glob would delete them all.
    # -mtime +30, NOT +7: the markers of a session that is still OPEN are as old as that session.
    find "$_ass_dir" -maxdepth 1 -name '.clavity-shield-*' -mtime +30 -delete 2>/dev/null
    printf 'agy-shield: %s\n' "$_ass_msg" >&2
    return 0
}

agy_shield() {
    _as_root=$1
    _as_rel=$2
    _as_key=$3

    # ---------------------------------------------------------------- A0: validate the inputs.
    # A validation failure is a FAULT for output purposes: LOUD, NEVER debounced, and it names the
    # argument it rejected. Silence here is a fail-open - a hook that passes the wrong path would get
    # a clean return, proceed to write its anomaly, and leave the file unshielded with nothing said.
    if [ -z "$_as_root" ] || [ ! -d "$_as_root" ]; then
        _agy_shield_say validation '' "REFUSING - root argument is not an existing directory: [$_as_root]"
        return 0
    fi
    case "$_as_rel" in
        '')        _agy_shield_say validation '' 'REFUSING - path argument is empty'; return 0 ;;
        /*)        _agy_shield_say validation '' "REFUSING - path argument must be relative to the root: [$_as_rel]"; return 0 ;;
        *..*)      _agy_shield_say validation '' "REFUSING - path argument contains '..': [$_as_rel]"; return 0 ;;
        .clavity/?*) : ;;
        *)         _agy_shield_say validation '' "REFUSING - path must resolve under .clavity/: [$_as_rel]"; return 0 ;;
    esac
    # THE KEY LANDS IN A FILENAME, so an unvalidated key is a path-traversal primitive. An EMPTY key
    # is LEGAL - it is the sanctioned way to disable debouncing - so validate only a NON-empty one,
    # and on rejection fall back to empty (debouncing off, warn every time) rather than refusing:
    # a malformed session id must never disable a data-leak guard.
    if [ -n "$_as_key" ]; then
        case "$_as_key" in
            *[!A-Za-z0-9._-]*)
                _agy_shield_say validation '' "ignoring a malformed debounce key (debouncing disabled for this call): [$_as_key]"
                _as_key='' ;;
        esac
    fi

    _as_dir="$_as_root/.clavity"
    _as_shield="$_as_dir/.gitignore"

    # ---------------------------------------------------------------- A1: ensure the directory.
    # An append into a missing directory fails "No such file or directory" on a fresh clone. The
    # shipped open-issues snippet already does this at its own :69, for exactly this reason.
    if [ ! -d "$_as_dir" ]; then
        if ! mkdir -p "$_as_dir" 2>/dev/null; then
            _agy_shield_say environment "$_as_key" "could not create $_as_dir - the shield cannot be asserted"
            return 0
        fi
    fi
    # Sweep abandoned prepend temps. AFTER the mkdir, never before it: on a fresh clone the directory
    # does not exist, so a sweep running first has nothing to sweep and fails every time. Stderr is
    # redirected because a GENUINE failure (a read-only mount) must not break a silent branch - not
    # because it is hiding the avoidable error the ordering already removes.
    #
    # GATED, NOT UNCONDITIONAL - and the sibling hooks say why in terms. assertion-strength-reminder.sh
    # :114-119: "THE EXISTS AND CREATE CASES MUST STAY SEPARATE, and the prune belongs ONLY to create...
    # Collapsing these into a single `[ -f ] || : >` condition puts `find` - a SUBPROCESS - on EVERY
    # test-file write, which is the hottest path this plugin has. Do not re-merge them." An unconditional
    # sweep here is that same anti-pattern one level over, and it lands in a hook registered with
    # "timeout": 10 (hooks.json:56). So it runs ONLY when this session has not swept yet, keyed off the
    # same marker directory the debounce uses - at most once per session, never on the hot path.
    _as_sweep="${TMPDIR:-/tmp}/.clavity-shield-swept-${_as_key:-nosession}"
    if [ ! -f "$_as_sweep" ]; then
        : > "$_as_sweep" 2>/dev/null
        find "$_as_dir" -maxdepth 1 -name '.gitignore.tmp.*' -mtime +30 -delete 2>/dev/null
    fi

    # ---------------------------------------------------------------- A2: ensure the shield text.
    # THREE cases, not two. Treating ANY non-zero grep as "absent" is required: on a missing file
    # grep exits 2, and an implementer keying on `exit 1` alone fails to restore a shield that does
    # not exist - the original 14d defect, reintroduced.
    # AN OPTIONAL TRAILING CR IS ACCEPTED, and the reason is a measurement that came out the OTHER way.
    # This shield is gitignored and never checked out, so .gitattributes cannot normalise it, and a human
    # editing it on Windows can leave CRLF - which is exactly the "created by hand" case 14d exists for.
    # MEASURED on Git Bash: `grep -qx '*'` DID match a `*\r\n` shield, with a passing LF control. That is a
    # property of THIS platform's grep, not a guarantee: on Linux `*\r` is a different line, and a shield
    # that never matches would be appended to on every single call and grow without bound. Costs one extra
    # grep, and only on the path where the first already failed.
    if grep -qx '*' "$_as_shield" 2>/dev/null || grep -qx "*$_AS_CR" "$_as_shield" 2>/dev/null; then
        :                                       # a bare * is present: append nothing.
    elif [ -f "$_as_shield" ] && grep -q '^!' "$_as_shield" 2>/dev/null; then
        # PREPEND. .gitignore is LAST-MATCH-WINS, so appending * to a file that begins with a
        # negation INVERTS that negation - measured: check-ignore flips 1 -> 0, the file silently
        # becomes ignored, and the B3 report below is never reached. Prepending satisfies BOTH
        # obligations: the human's ! line still wins for the file it names, and * covers everything
        # else. Writing NOTHING satisfies neither - measured, it left every other file in the
        # directory exposed to `git add -A`.
        #
        # THE TEMP FILE'S LOCATION IS LOAD-BEARING. `mv` is atomic only WITHIN a filesystem; across
        # a boundary it degrades to copy-then-delete and the guarantee is silently gone. `mktemp`
        # with no argument defaults to $TMPDIR, normally a different mount - and copy-then-delete
        # still produces the right bytes whenever nothing races, so the loss is invisible. Create it
        # beside the shield. Unique per invocation, never a fixed name: two sessions can be open on
        # the same repository, and a fixed name races exactly when the guard matters.
        _as_tmp=$(mktemp "$_as_dir/.gitignore.tmp.XXXXXX" 2>/dev/null)
        if [ -n "$_as_tmp" ] && [ -f "$_as_tmp" ]; then
            if printf '%s\n' '*' > "$_as_tmp" 2>/dev/null && cat "$_as_shield" >> "$_as_tmp" 2>/dev/null; then
                mv -f "$_as_tmp" "$_as_shield" 2>/dev/null || rm -f "$_as_tmp" 2>/dev/null
            else
                rm -f "$_as_tmp" 2>/dev/null
            fi
        fi
    else
        # A FILE WHOSE LAST LINE HAS NO TRAILING NEWLINE WOULD OTHERWISE CONCATENATE. Measured, with a
        # control: a shield containing `foo.txt` with no final newline became the single line `foo.txt*`,
        # while the same append against a file that DID end in a newline correctly produced two lines. The
        # bare `*` then never exists as its own line, so the shield is still broken, this branch runs
        # again on the next call, and the file grows a corrupted line every time.
        # $(...) strips trailing NEWLINES but not a CR, so a last byte of \n yields an empty substitution.
        # NO `tail` PROBE, and that is the point: an unconditional leading newline on a NON-EMPTY file is
        # both simpler and safer than probing for the last byte. A blank line in .gitignore is ignored by
        # git, so the worst case is one cosmetic empty line - whereas a `tail` that is missing, shadowed,
        # or fails for any reason makes the probe return empty, silently selects the bare append, and
        # reproduces the exact corruption this branch exists to prevent. One less subprocess, one less
        # tool assumed present, and no silent failure mode.
        if [ -s "$_as_shield" ]; then
            printf '\n%s\n' '*' >> "$_as_shield" 2>/dev/null
        else
            printf '%s\n' '*' >> "$_as_shield" 2>/dev/null
        fi
    fi

    # ---------------------------------------------------------------- Stage B: verify the EFFECT.
    # B1: not inside a work tree. check-ignore returns 128 there, indistinguishable from a genuine
    # error, so the effect check cannot run. Stage A has already guaranteed the text. Isolate this
    # exactly as scripts/check-core-integrity.ps1:39-46 does for the same ambiguity. SILENT.
    git -C "$_as_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    git -C "$_as_root" check-ignore -q -- "$_as_rel" 2>/dev/null
    _as_ci=$?

    if [ "$_as_ci" -eq 0 ]; then
        return 0                                # B2: ignored. Done. SILENT.
    fi

    if [ "$_as_ci" -eq 1 ]; then
        # B3: AMBIGUOUS - a broken shield and an already-TRACKED file both land here. Measured: with
        # a correct * shield and the file force-tracked, check-ignore returns 1 and `git add -A`
        # stages it anyway. Without this split a naive "non-zero implies the shield is broken" helper
        # would rewrite a healthy shield forever and never surface the only remedy that works.
        if git -C "$_as_root" ls-files --error-unmatch -- "$_as_rel" >/dev/null 2>&1; then
            _agy_shield_say persistent "$_as_key" \
                "$_as_rel is TRACKED by git, so .gitignore cannot hide it. Stage A secured the directory; this file needs: git rm --cached -- \"$_as_rel\""
        else
            # Untracked and STILL not ignored after Stage A restored the shield text. The only way to
            # reach this is a negation line. REPORT; do NOT silently rewrite - auto-deleting a line a
            # human deliberately wrote is a destructive footgun, and a missing shield is trivially
            # restorable where a destroyed intent is not.
            _as_why=$(git -C "$_as_root" check-ignore -v -- "$_as_rel" 2>/dev/null | head -n 1)
            _agy_shield_say persistent "$_as_key" \
                "$_as_rel is NOT ignored: a negation line in $_as_shield overrides the shield [${_as_why:-no matching rule reported}]. It stays visible to git until you remove that line."
        fi
        return 0
    fi

    # B4: a real git error INSIDE a work tree. Stage A has already done what it can, which is the
    # safe direction for a data-leak guard. Say so and stop. Through this function's front door A0
    # rejects every cheap way of producing a 128, so this branch is reachable only by genuine
    # repository corruption - it has NO honest oracle and deliberately has no test row.
    _agy_shield_say environment "$_as_key" \
        "git check-ignore failed (exit $_as_ci) inside a work tree; the shield text was asserted but its effect could not be verified for $_as_rel"
    return 0
}
```

- [ ] **Step 4: Mirror to classic, byte-identically**

```bash
cp clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
git hash-object clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh
```

Expected: the two hashes are IDENTICAL. If they differ, the copy re-encoded the file - stop and report
`STATE_MISMATCH: mirror is not byte-identical`.

- [ ] **Step 5: Register the new suite in the SLOW partition**

Registration is an EXPLICIT LIST, not a glob, enforced by `test-suite-registration.Tests.ps1`. Add
`'scripts/tests/agy-shield-lib.Tests.ps1'` to the array in the `test-scripts-slow` recipe in `justfile`. It is a
fixture-heavy suite that shells out to `git` and `bash` many times; the fast half is cap-adjacent.

Then add a row for it to the `## Measured runtimes` fenced table in `scripts/tests/_partition.md` -
`test-suite-registration.Tests.ps1:119` asserts that table is a complete census of `scripts/tests/`.

- [ ] **Step 6: Run the suite to verify it PASSES**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-shield-lib.Tests.ps1 -Output Detailed -CI"
```

Expected: every row PASSES. **Read the count** and record it for `_partition.md`.

- [ ] **Step 7: Mutation controls - one per branch**

Run each of these, confirm the named row turns RED, then REVERT the mutation. If a mutation leaves the
suite green, that branch is untested regardless of how many rows exist.

| mutation | row that must turn RED |
|---|---|
| change the A2 prepend back to an append (`>> "$_as_shield"`) | `(a) the human INTENT survives` |
| change the A2 prepend to writing nothing | `(b) the DIRECTORY is protected` |
| delete the `elif ... grep -q '^!'` branch entirely | both (a) and (b) |
| drop the trailing-newline probe from the append branch | `does NOT concatenate onto a shield with NO trailing newline` |
| drop the optional-CR alternative from the A2 match | `treats a CRLF shield as already correct` |
| make the A1 temp sweep unconditional again | **NONE - this is a COST regression, not a correctness one, and no row can catch it.** Verify by reading that the sweep stays gated behind `$_as_sweep`. Recorded here rather than left implied, because a mutation table with a silent gap is how a guard gets credited with coverage it does not have |
| delete the `ls-files --error-unmatch` split in B3 | `reports the git rm --cached remedy` |
| make Stage A conditional on B3's outcome | `restores an EMPTIED shield even when the path is TRACKED` |
| replace `_ass_marker` with a fixed global name (ignore `$_ass_key`) | `emits the SAME fault AGAIN under a DIFFERENT key` |
| debounce the `validation` class like the others | `a VALIDATION fault is emitted BOTH times` |
| run the key regex over EVERY key including empty | `an EMPTY key is LEGAL` |
| drop `2>/dev/null` from the A2 `grep` | `creates .clavity/ and the shield on a FRESH CLONE` (stderr assertion) |
| replace `return 0` with `exit 0` in A0 | `does NOT kill its CALLER` |
| use `check-ignore -v` for the DECISION instead of `-q` | `(a) the human INTENT survives` |

- [ ] **Step 8: Run the pair gates**

```bash
bash scripts/check-seed-artifacts-synced.sh
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed -CI"
just check-injected-context
```

Expected: all three clean. `plugin-hooks-payload.Tests.ps1:26` globs `*.sh`, so the new file is picked up
by the ASCII row and the byte-identity row automatically.

- [ ] **Step 9: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-shield-lib.sh clavity-classic/plugin/hooks/agy-shield-lib.sh \
        scripts/tests/agy-shield-lib.Tests.ps1 justfile scripts/tests/_partition.md
git commit -m "feat(shield): 14d - effect-checking .clavity shield helper, mirrored across both plugins"
```

---

## Task 4: Item 14d - `open-issues/SKILL.md` calls the helper (GATED on Task 1)

> **GATED ON TASK 1, exactly as Tasks 6 and 7 are.** Panel round 1 measured that this task's first draft
> would have shipped 14d as a **pure no-op** - see the box below. If Task 1 recorded **BLOCKED**, this
> task ships the *append-corruption* fix only (Step 1b) and the helper call is deferred with 14c's skill
> half.

### PANEL R1 - the locator in this task's first draft was broken, and it would have shipped silently

The first draft sourced the helper with `. "$(dirname "${BASH_SOURCE[0]:-$0}")/../../hooks/agy-shield-lib.sh"`.
**That does not resolve.** Measured in an agent-run shell snippet, with a control:

```
dirname $0      = [/usr/bin]
BASH_SOURCE[0]  = [<empty>]
ls /usr/bin/../../hooks/  ->  No such file or directory
```

A `SKILL.md` snippet is text an agent pastes into an arbitrary shell; `$0` is the SHELL, not the skill
file. So the `source` would fail **every time**, `command -v agy_shield` would be false **every time**, and
the `else` fallback would run the OLD content-blind idiom **every time**. 14d - the item this whole batch
is named for - would have shipped as a no-op that passes its own presence-grep.

**This is the same defect as M1, one task over**, and it is why Task 4 is now gated on the same
measurement. The peer's independent seat found it too; its stated mechanism (`dirname` yields `.`) was
wrong - the measured value is `/usr/bin` - but the conclusion was right.

**Files:**
- Modify: `clavity-dotnet/plugin/skills/open-issues/SKILL.md:62-89`
- Modify: `clavity-classic/plugin/skills/open-issues/SKILL.md` (byte-identical mirror)

**Verified current state** - `open-issues/SKILL.md:79` is the sole shield assertion:

```bash
[ -f "$R/.clavity/.gitignore" ] || printf '%s\n' '*' >> "$R/.clavity/.gitignore"
```

Its own adjacent comment at `:74-78` claims it covers "the file was created by hand", which is precisely
what it misses.

**This skill is NOT routed through `agy-mark.sh`** - it keeps its own inline snippet, deliberately. That
is stated in the spec at `:576-577`: `open-issues` is item 14d, whose whole job is to fix that snippet in
place.

- [ ] **Step 1: Replace the snippet's shield lines**

In `clavity-dotnet/plugin/skills/open-issues/SKILL.md`, replace lines `:70-79` (the comment block and the
`[ -f ]` assertion) with a call into the shipped helper. **Leave `:67-69` and `:80-88` untouched** - the
root resolution and the `>>`-not-`>` header discipline are correct and are load-bearing for other reasons.

Replacement text for `:70-79`:

```bash
# Self-ignoring directory. This makes .clavity/ invisible to git REGARDLESS of the host repository's
# own .gitignore, which matters because this plugin ships to repositories whose .gitignore we do not
# control. Without it, the "capture is private" property holds only in the repo where it was written.
#
# CHECKED ON EVERY CAPTURE, deliberately NOT nested inside the file-exists branch below - any later
# loss of the shield would otherwise leave the anomalies file visible to git forever after.
#
# THE HELPER CHECKS THE EFFECT, NOT THE TEXT. The previous line here was
# `[ -f "$R/.clavity/.gitignore" ] || printf '%s\n' '*' >> ...`, which restores a DELETED shield and
# nothing else: measured in a throwaway repo it passes while the directory is leaking in three other
# states - an EMPTIED shield, a shield carrying a `!` negation, and a file already TRACKED by git.
# The helper always returns 0 and never blocks a capture.
#
# <BASE> IS THE LOCATOR RECORDED BY TASK 1 - this skill's own base directory, supplied by the harness at
# invocation time. It is NOT $0 and NOT ${BASH_SOURCE[0]}: measured, in an agent-run shell snippet those
# give /usr/bin and the empty string, so a path built from them resolves nowhere and this whole block
# would silently degrade to the else branch on every single capture.
. "<BASE>/../../hooks/agy-shield-lib.sh" 2>/dev/null || true
if command -v agy_shield >/dev/null 2>&1; then
  agy_shield "$R" ".clavity/local-anomalies.md" "${AGY_SESSION_ID:-}"
else
  # THE SAFE APPEND, not the shipped idiom - see Step 1b. Do not paste `[ -f ] || printf '%s\n' '*' >>`
  # here: round 1 measured that it concatenates onto a shield with no trailing newline, and round 2
  # caught that exact idiom being re-pasted into a fallback branch one task over.
  mkdir -p "$R/.clavity" 2>/dev/null
  # `! -s` covers MISSING and EMPTY together. Measured (panel R3): the `[ ! -f ] ... elif [ -s ]` form ran
  # neither branch for a zero-byte shield, leaving the 14d defect itself unfixed in the fallback.
  if [ ! -s "$R/.clavity/.gitignore" ]; then
    printf '%s\n' '*' >> "$R/.clavity/.gitignore"
  elif ! grep -qx '*' "$R/.clavity/.gitignore" 2>/dev/null; then
    printf '\n%s\n' '*' >> "$R/.clavity/.gitignore"
  fi
fi
```

**The `else` branch is deliberate and is not a weakening.** Falling back to the OLD idiom is strictly
better than capturing with no shield at all. The helper is the improvement; the fallback is the floor.

**`mkdir -p "$R/.clavity"` at `:69` stays, and it is NOT redundant.** It runs UNCONDITIONALLY, above this
whole block, so the directory exists whichever branch is taken - including the case where the helper loads
but its own Stage A1 `mkdir` fails and it returns 0 by contract. **Do not move it inside the `else`, and
do not delete it:** a reviewer read the first draft as putting it inside the `else` and concluded the
capture would be dropped. It is outside; that reading is wrong, and this line is here so the next reader
does not have to re-derive it.

- [ ] **Step 1b: The append-corruption fix - ships EVEN IF Task 1 recorded BLOCKED**

Independent of the helper, the fallback idiom's own append is unsafe on a shield whose last line has no
trailing newline. **Measured, with a control:** appending `*` to a file containing `foo.txt` with no final
newline produced the single line `foo.txt*`, while the same append against a file that DID end in a
newline correctly produced two lines. So the bare `*` never becomes its own line, the `[ -f ]` test still
passes, and the shield is silently broken.

```bash
[ -f "$F" ] || printf '%s\n\n' '# Untriaged anomalies (local, never committed)' >> "$F"
```

is unaffected, but the shield fallback must become:

```bash
if [ ! -s "$R/.clavity/.gitignore" ]; then
  printf '%s\n' '*' >> "$R/.clavity/.gitignore"
elif ! grep -qx '*' "$R/.clavity/.gitignore" 2>/dev/null; then
  printf '\n%s\n' '*' >> "$R/.clavity/.gitignore"
fi
```

> **PANEL R4 - this block was the LAST unswept copy, and it had accumulated BOTH earlier defects.** Until
> round 4 it read `if [ ! -f ] ... elif [ -s ] && [ -n "$(tail -c 1 ...)" ]`, which carried the round-2
> `tail` probe that round 2 removed everywhere else, AND the round-3 zero-byte fail-open that round 3 fixed
> everywhere else. **Two consecutive rounds each fixed this defect in the sibling sites and missed this
> one.** The lesson is the plan's own global rule 4, turned on the plan itself: when a fix changes a FACT,
> grep the whole document for every copy of that fact before calling it folded.

- [ ] **Step 2: Mirror to classic and verify byte-identity**

```bash
cp clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md
git hash-object clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md
```

Expected: identical hashes.

- [ ] **Step 3: Completion check - the file WAS edited**

There is deliberately no behavioural test for a `SKILL.md` edit: the only available oracle is a regex
asserting the file CONTAINS the instruction, and the mutation that must turn it red (a model ignoring the
instruction at runtime) leaves the string sitting in the file. **A presence-grep is a vacuous oracle for
"does the model obey" and a sound one for "was the file edited at all"** - and the cross-product gates
cannot close that hole, because they compare the two PRODUCTS against each other, so a file left unedited
in BOTH passes byte-identity happily.

**Grep for the thing this task actually shipped, which depends on Task 1** - under BLOCKED only Step 1b
lands, and it contains no `agy_shield` at all, so an `agy_shield` grep returns 0 and reads as a task that
was never done.

```bash
# Task 1 = RESOLVED:
grep -c 'agy_shield' clavity-dotnet/plugin/skills/open-issues/SKILL.md
grep -c 'agy_shield' clavity-classic/plugin/skills/open-issues/SKILL.md
# Task 1 = BLOCKED (Step 1b only):
grep -c '! -s "\$R/.clavity/.gitignore"' clavity-dotnet/plugin/skills/open-issues/SKILL.md
grep -c '! -s "\$R/.clavity/.gitignore"' clavity-classic/plugin/skills/open-issues/SKILL.md
```

Expected: a non-zero count from BOTH, for whichever pair applies. Record both in the Task 16 checklist.

- [ ] **Step 4: Run the gates**

```bash
bash scripts/check-seed-artifacts-synced.sh
just check-injected-context
```

Expected: both clean.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/skills/open-issues/SKILL.md clavity-classic/plugin/skills/open-issues/SKILL.md
git commit -m "fix(shield): 14d - open-issues asserts the shield's EFFECT, not the file's existence"
```

---
## Task 5: Item 14c - wire the hook to the helper

`agy-discipline-reaching.sh` writes `.clavity/discipline-reaching.jsonl` and asserts no shield. It is a
HOOK, so it sources the helper **directly** - it does not need the `agy-mark.sh` wrapper.
`agy-consult-guard-pre.sh:14` is the precedent: `. "$(dirname "$0")/agy-consult-guard-lib.sh"`.
**Verified: `hooks.json` invokes every hook as `bash "${CLAUDE_PLUGIN_ROOT}/hooks/<name>.sh"`, so `$0` is
an absolute path and `dirname "$0"` resolves.**

**This task ships whether or not Task 1 resolved.** It has no dependency on the skill locator.

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh:1-15` (header) and `:96-97` (the wiring)
- Modify: `clavity-classic/plugin/hooks/agy-discipline-reaching.sh` (byte-identical mirror)
- Test: `scripts/tests/agy-discipline-reaching.Tests.ps1`

### M3 - the subprocess budget is real and bounds WHERE the call goes

`agy-discipline-reaching.sh:2` declares **"CAPTURE ONLY, NO SUBPROCESSES"**, and `hooks.json:56`
registers it with **`"timeout": 10`**. The helper spawns `git`, `grep`, `mkdir` and `find`. Two
consequences, both mandatory:

1. **The call goes AFTER every early exit** - `:53` (`$HOME/.claude/.no-agy`), `:81` (no `.git`), `:87`
   (workspace `.no-agy`). Past `:81` the hook has already established it is inside a repository, so the
   git probes are local and bounded. The header's own measurement - 20314ms walking an unreachable UNC
   share versus 9282ms gated - is about the ROOT WALK, which is already complete by then.
2. **The header comment at `:2` becomes FALSE and must be rewritten in the same commit.** Global rule 4:
   when a fix changes a FACT, sweep the fact. Leaving "NO SUBPROCESSES" in place would teach the next
   reader a rule the file no longer follows.

- [ ] **Step 0: STATE VERIFICATION**

Open `clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh` and confirm:
- `:2` contains the string `NO SUBPROCESSES`
- `:42` parses `session_id` into `sid`
- `:96` reads `out="$root/.clavity"` and `:97` is the `mkdir` guard
- `:108-109` is the `printf ... >> "$out/discipline-reaching.jsonl"`

If any differs, STOP and report `STATE_MISMATCH: <what>` rather than adapting.

- [ ] **Step 1: Write the failing test**

Append to `scripts/tests/agy-discipline-reaching.Tests.ps1`. **The test must BREAK THE SHIELD FIRST** -
the helper is silent on the healthy path by contract, so a run against a healthy repository observes
nothing and would pass while asserting nothing.

```powershell
    Context '14c - the hook asserts the .clavity shield' {
        BeforeAll {
            # A throwaway repo with NO root .gitignore: in THIS repository the root .gitignore covers
            # .clavity/, which MASKS a broken shield and reports a false pass.
            function New-ReachingFixture {
                param([string]$Shield)
                $d = Join-Path ([IO.Path]::GetTempPath()) ("reachfx-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path $d | Out-Null
                & git -C $d init -q
                & git -C $d config user.email t@t.t
                & git -C $d config user.name t
                New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
                [IO.File]::WriteAllText((Join-Path $d '.clavity/.gitignore'), $Shield)
                [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
                & git -C $d add seed.txt; & git -C $d commit -q -m seed
                $d
            }
            function Invoke-Reaching {
                param([string]$Dir, [string]$SessionId = 'sess-abc')
                $hook = (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -replace '\\','/'
                $payload = (@{ cwd = ($Dir -replace '\\','/'); session_id = $SessionId; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
                $errF = Join-Path ([IO.Path]::GetTempPath()) ("reach-" + [guid]::NewGuid().ToString('N') + ".err")
                try {
                    $payload | & bash $hook 2> $errF | Out-Null
                    [pscustomobject]@{ Err = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue) }
                } finally { Remove-Item -LiteralPath $errF -Force -ErrorAction SilentlyContinue }
            }
        }

        It 'RESTORES an emptied shield - an observable effect' {
            $d = New-ReachingFixture -Shield ''
            Invoke-Reaching -Dir $d | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) |
                Should -Match '(?m)^\*$' -Because 'the hook must assert the shield before it writes into .clavity/'
        }

        It 'still writes its row (the shield call must not break capture)' {
            $d = New-ReachingFixture -Shield ''
            Invoke-Reaching -Dir $d | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/discipline-reaching.jsonl')) | Should -Match '"v":3'
        }

        It 'the FALLBACK restores an EMPTIED shield when the helper cannot be sourced (panel R3)' {
            # THE FALLBACK PATH NEEDS ITS OWN ORACLE. Every other row here exercises the helper, so a
            # broken else-branch is invisible to all of them - and it WAS broken: measured, the
            # `[ ! -f ] ... elif [ -s ]` form ran neither branch against a zero-byte shield, leaving the
            # 14d defect itself unfixed on exactly the path that exists to be a floor.
            $d = New-ReachingFixture -Shield ''
            $hookDir = Join-Path ([IO.Path]::GetTempPath()) ("nolib-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $hookDir | Out-Null
            # Copy the hook WITHOUT agy-shield-lib.sh beside it, so the source fails and the else runs.
            Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh') -Destination (Join-Path $hookDir 'agy-discipline-reaching.sh')
            $payload = (@{ cwd = ($d -replace '\\','/'); session_id = 'sess-x'; source = 'startup'; model = 'm'; transcript_path = 't' } | ConvertTo-Json -Compress)
            $payload | & bash ((Join-Path $hookDir 'agy-discipline-reaching.sh') -replace '\\','/') 2>$null | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) |
                Should -Match '(?m)^\*$' -Because 'the fallback is the floor; an emptied shield must still be restored without the helper'
            Remove-Item -LiteralPath $hookDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        It 'FORWARDS the payload session_id as the debounce key' {
            # THE ORACLE IS A LINE COUNT AGAINST A PERSISTENT FAULT, and it has to be: Stage A runs
            # unconditionally and ignores the key entirely, so a hook passing an empty or hard-coded key
            # still restores the shield and passes every row above. Shield restoration cannot detect a
            # broken forward. The TRACKED-file fault reports on every call until a human intervenes, so
            # two runs with the same real session_id emit ONCE and with an empty key emit TWICE.
            $d = New-ReachingFixture -Shield "*`n"
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
            [IO.File]::WriteAllText((Join-Path $d '.clavity/discipline-reaching.jsonl'), '')
            & git -C $d add -f '.clavity/discipline-reaching.jsonl'
            & git -C $d commit -q -m 'track the jsonl to create a PERSISTENT fault'

            $sid = 'sess-' + [guid]::NewGuid().ToString('N')
            $a = Invoke-Reaching -Dir $d -SessionId $sid
            $b = Invoke-Reaching -Dir $d -SessionId $sid
            $total = ([regex]::Matches(("$($a.Err)$($b.Err)"), 'git rm --cached')).Count
            $total | Should -Be 1 -Because 'with the real session_id forwarded, a persistent fault is reported ONCE across two runs'
        }
    }
```

- [ ] **Step 2: Run it to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed -CI"
```

Expected: the three new rows FAIL (no shield call exists yet). Read the count.

- [ ] **Step 3: Rewrite the header fact at `:1-15`**

Replace the two header lines that now misdescribe the file:

```sh
#!/usr/bin/env bash
# AGY-ANOMALIES discipline-reaching recorder (plugin-shipped). SessionStart. CAPTURE ONLY.
# ROADMAP section 0 step 1a. Design + measurements: docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md
#
# IT CAPTURES; IT DOES NOT ANALYSE. One small row naming the session and its transcript, then stop. All
# scanning happens later in scripts/discipline-reaching-report.ps1, which runs on demand with no time limit.
#
# WHY THE EXTRACTION IS WRITTEN WITHOUT jq, date, OR git.
# NOT because of teardown pressure - that was a wrong diagnosis that cost three rounds. The real cause of
# the v17 failure was that ${CLAUDE_PLUGIN_ROOT} DOES NOT RESOLVE at SessionEnd (cancelled 3/3 with the
# variable at 20,9s / 1,5s / 0,6s; an absolute path from the same manifest worked 2/2 - one axis varied,
# the other never). Duration was a confound: a SLOWER hook registered elsewhere survived.
# The subprocess-free form is kept for the PARSE and the ROOT WALK on its own merits: a hook that runs at
# EVERY session start should be cheap, and the rewrite carries three fixes worth keeping - byte-exact
# Windows paths, CR stripping, and pipe-safe stdin.
#
# ONE EXCEPTION, ADDED DELIBERATELY (ROADMAP 14c): the .clavity shield assertion below sources
# agy-shield-lib.sh, which does spawn processes. It is placed AFTER every early exit, so it runs only
# once the walk has already proved this is a real repository - the header's 20314ms unreachable-share
# measurement is about the WALK, which is complete by then. This hook is registered with "timeout": 10
# in hooks.json; keep any future addition on the far side of those exits for the same reason.
```

- [ ] **Step 4: Wire the helper in, immediately before the write**

Replace `:96-97` with:

```sh
out="$root/.clavity"

# ROADMAP 14c: assert the shield BEFORE creating or writing anything under .clavity/. Sourced, not
# executed - the helper returns and never exits, so it cannot terminate this hook. It always returns 0;
# its value carries no information and must not be branched on. $sid is the payload's session_id (:42),
# forwarded as the debounce key so a persistent fault is reported once per session rather than on every
# start; an empty $sid legally disables debouncing.
. "$(dirname "$0")/agy-shield-lib.sh" 2>/dev/null || true
if command -v agy_shield >/dev/null 2>&1; then
  agy_shield "$root" ".clavity/discipline-reaching.jsonl" "$sid"
else
  # FALLBACK, and its absence was a real asymmetry. If the helper is missing, unreadable, or contains a
  # syntax error, `|| true` swallows the failure and `command -v` correctly reports it gone - and without
  # this branch the hook would proceed to write into an UNSHIELDED .clavity/ and exit 0 with nothing said.
  # The old content-blind idiom is a weak shield; no shield at all is the leak this item exists to stop.
  #
  # PANEL R2 - THIS FALLBACK USES THE SAFE APPEND, NOT THE SHIPPED IDIOM. Round 1 proved
  # `[ -f ] || printf '%s\n' '*' >>` corrupts a shield whose last line has no trailing newline (measured:
  # `foo.txt` + `*` -> the single line `foo.txt*`). Round 1's own fix then pasted that unpatched idiom
  # into this brand-new else branch, recreating the defect it had just closed one task over. A fix is
  # unreviewed code; this is what that costs when it is not re-reviewed.
  mkdir -p "$root/.clavity" 2>/dev/null
  # `! -s` COVERS MISSING **AND** EMPTY IN ONE TEST, and that is the whole point. PANEL R3 measured that
  # the round-2 form - `if [ ! -f ] ... elif [ -s ] ...` - ran NEITHER branch for a shield that exists at
  # zero bytes, leaving an EMPTIED shield unrestored. That is the literal 14d defect, reintroduced in the
  # fallback by the fix for the previous round's defect. Third consecutive round in which a fix created
  # one; do not "simplify" this test back apart.
  if [ ! -s "$root/.clavity/.gitignore" ]; then
    printf '%s\n' '*' >> "$root/.clavity/.gitignore" 2>/dev/null
  elif ! grep -qx '*' "$root/.clavity/.gitignore" 2>/dev/null; then
    printf '\n%s\n' '*' >> "$root/.clavity/.gitignore" 2>/dev/null
  fi
fi

[ -d "$out" ] || mkdir -p "$out" 2>/dev/null || exit 0
```

Leave `:108-109` unchanged.

- [ ] **Step 5: Run it to verify it PASSES**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-discipline-reaching.Tests.ps1 -Output Detailed -CI"
```

Expected: all rows PASS.

- [ ] **Step 6: Mutation controls**

| mutation | row that must turn RED |
|---|---|
| delete the `agy_shield` call **and** the new `else` fallback | `RESTORES an emptied shield` |
| delete ONLY the `else` fallback, then make the helper unsourceable | a new row must assert the shield is STILL restored by the fallback - add it if absent |
| replace `"$sid"` with `""` in the call | `FORWARDS the payload session_id as the debounce key` |
| replace `"$sid"` with a hard-coded literal | same row |

Revert each after confirming.

- [ ] **Step 7: Mirror, gate, commit**

```bash
cp clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh
git hash-object clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh
bash scripts/check-seed-artifacts-synced.sh
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed -CI"
just check-injected-context
git add clavity-dotnet/plugin/hooks/agy-discipline-reaching.sh clavity-classic/plugin/hooks/agy-discipline-reaching.sh scripts/tests/agy-discipline-reaching.Tests.ps1
git commit -m "feat(shield): 14c - the SessionStart recorder asserts the shield before writing"
```

---

## Task 6: Item 14c - `agy-mark.sh` (CONDITIONAL on Task 1 = RESOLVED)

> **SKIP THIS TASK ENTIRELY if Task 1 recorded BLOCKED.** With the skill half blocked, `agy-mark.sh` has
> **no caller at all** - the hook sources the helper directly (Task 5) and `open-issues` keeps its own
> inline snippet (Task 4). Shipping it would be dead code. Record the deferral in Task 8 instead.

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-mark.sh`
- Create: `clavity-classic/plugin/hooks/agy-mark.sh` (byte-identical mirror)
- Create: `scripts/tests/agy-mark.Tests.ps1`
- Modify: the `test-scripts-slow` recipe in `justfile` (SLOW partition) and `scripts/tests/_partition.md`

### M2 - the root anchor is cwd, NOT `git rev-parse --show-toplevel`

**The spec's contract table at `:614` is WRONG on this point, and following it would destroy the debounce
it exists to serve.** Measured:

- The READER, `agy-seam-inject.sh:124`: `marker="$cwd_path/.clavity/agy-marks/$discipline.head"`, and
  `:118-122` states in terms: *"Do NOT anchor to git-toplevel: that would diverge from the cwd-relative
  writer in a launched-from-subdir session and defeat the debounce."*
- The WRITERS today, `agy-first/SKILL.md:109`, `agy-capstone/SKILL.md:266`,
  `agy-test-audit/SKILL.md:222`: a bare relative `.clavity/agy-marks/<discipline>.head`.

A toplevel-anchored writer plus a cwd-anchored reader means `agy-seam-inject.sh:125`'s
`[ -f "$marker" ]` never matches in a subdirectory session, so the hook falls through and **re-injects
the discipline on every single trigger, forever.**

`open-issues/SKILL.md:63-67` legitimately uses toplevel for a DIFFERENT file, and says why: *"The hook
resolves the root the same way, so both sides always agree."* **Two files, two anchors, both correct.
Do not harmonise them.**

**So: every mode of `agy-mark.sh` anchors to the invoking cwd.** `git rev-parse` is still used for the
HEAD sha, which is a different thing and does fail closed.

- [ ] **Step 1: Write the failing test suite**

Create `scripts/tests/agy-mark.Tests.ps1`:

```powershell
# Tests for the shipped marker writer, clavity-dotnet/plugin/hooks/agy-mark.sh.
#
# ANCHORED TO CWD, NOT git-toplevel. agy-seam-inject.sh:124 READS the marker at
# "$cwd_path/.clavity/agy-marks/<d>.head" and :118-122 forbids the git root by name. A toplevel writer
# against a cwd reader defeats the debounce in every launched-from-subdir session. The
# subdirectory row below is the pin for that pairing.

Describe 'agy-mark.sh' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Mark = (Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/agy-mark.sh') -replace '\\','/'
        Test-Path -LiteralPath $script:Mark | Should -BeTrue

        function New-MarkFixture {
            param([string]$Shield = "*`n")
            $d = Join-Path ([IO.Path]::GetTempPath()) ("markfx-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $d | Out-Null
            & git -C $d init -q; & git -C $d config user.email t@t.t; & git -C $d config user.name t
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity') | Out-Null
            [IO.File]::WriteAllText((Join-Path $d '.clavity/.gitignore'), $Shield)
            [IO.File]::WriteAllText((Join-Path $d 'seed.txt'), "seed`n")
            & git -C $d add seed.txt; & git -C $d commit -q -m seed
            $d
        }
        function Invoke-Mark {
            param([string]$Cwd, [string[]]$MarkArgs, [string]$SessionId = '')
            $outF = Join-Path ([IO.Path]::GetTempPath()) ("mk-" + [guid]::NewGuid().ToString('N') + ".out")
            $errF = "$outF.err"
            $prev = $env:AGY_SESSION_ID; $env:AGY_SESSION_ID = $SessionId
            try {
                $p = Start-Process -FilePath 'bash' -ArgumentList (@($script:Mark) + $MarkArgs) -WorkingDirectory $Cwd `
                        -RedirectStandardOutput $outF -RedirectStandardError $errF -NoNewWindow -Wait -PassThru
                [pscustomobject]@{
                    ExitCode = $p.ExitCode
                    Err = (Get-Content -Raw -LiteralPath $errF -ErrorAction SilentlyContinue)
                }
            } finally {
                $env:AGY_SESSION_ID = $prev
                Remove-Item -LiteralPath $outF, $errF -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'head mode' {
        It 'writes the BARE sha and nothing else' {
            # docs/agy-disciplines-marker-contract.md:18 - "the commit sha from git rev-parse HEAD at
            # consult time, and nothing else". Touching the file and ignoring the argument would satisfy
            # a path-only contract, which is why the CONTENT is asserted here.
            $d = New-MarkFixture
            $sha = (& git -C $d rev-parse HEAD).Trim()
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first',$sha)
            $r.ExitCode | Should -Be 0
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')).Trim() | Should -BeExactly $sha
        }

        It 'CREATES .clavity/agy-marks/ on a fresh clone' {
            # Stage A1 of the helper creates .clavity/ and NOTHING BELOW IT, and this batch removes the
            # skills' own mkdir instructions - so without this, head would fail on a fresh clone.
            $d = New-MarkFixture
            Remove-Item -LiteralPath (Join-Path $d '.clavity/agy-marks') -Recurse -Force -ErrorAction SilentlyContinue
            $sha = (& git -C $d rev-parse HEAD).Trim()
            (Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first',$sha)).ExitCode | Should -Be 0
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) | Should -BeTrue
        }

        It 'ANCHORS TO CWD, matching agy-seam-inject.sh:124 - the subdirectory pin' {
            # THE ROW THAT CATCHES A TOPLEVEL ANCHOR. Run from a subdirectory: the marker must land in
            # THAT directory, because that is where the reader looks. A toplevel-anchored writer puts it
            # at the repo root, the reader never finds it, and the discipline re-fires forever.
            $d = New-MarkFixture
            $sub = Join-Path $d 'src/deep'
            New-Item -ItemType Directory -Force -Path $sub | Out-Null
            $sha = (& git -C $d rev-parse HEAD).Trim()
            (Invoke-Mark -Cwd $sub -MarkArgs @('head','agy-first',$sha)).ExitCode | Should -Be 0
            (Test-Path -LiteralPath (Join-Path $sub '.clavity/agy-marks/agy-first.head')) |
                Should -BeTrue -Because 'agy-seam-inject.sh:124 reads $cwd_path/.clavity/agy-marks/<d>.head'
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) |
                Should -BeFalse -Because 'a toplevel anchor would put it here and defeat the debounce'
        }
    }

    Context 'log mode' {
        It 'OWNS the line format - callers pass no preformatted line' {
            $d = New-MarkFixture
            $sha = (& git -C $d rev-parse HEAD).Trim()
            (Invoke-Mark -Cwd $d -MarkArgs @('log','agy-first','SKIPPED-UNREACHABLE',$sha)).ExitCode | Should -Be 0
            $line = (Get-Content -LiteralPath (Join-Path $d '.clavity/agy-marks/skipped.log') | Select-Object -Last 1)
            $line | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\s\sagy-first\s\sSKIPPED-UNREACHABLE\s\sHEAD='
        }

        It 'APPENDS - a second call does not destroy the first' {
            $d = New-MarkFixture
            $sha = (& git -C $d rev-parse HEAD).Trim()
            Invoke-Mark -Cwd $d -MarkArgs @('log','agy-first','SKIPPED-UNREACHABLE',$sha) | Out-Null
            Invoke-Mark -Cwd $d -MarkArgs @('log','agy-capstone','WAIVED',$sha,'breach') | Out-Null
            @(Get-Content -LiteralPath (Join-Path $d '.clavity/agy-marks/skipped.log')).Count | Should -Be 2
        }
    }

    Context 'prepare mode' {
        It 'creates and shields the PARENT of the named FILE' {
            # prepare takes the FILE path, not the directory: passing `seams` throws the filename away
            # and the helper's Stage B evaluates the DIRECTORY, never the file. check-ignore accepts
            # paths that do not exist yet, so passing the eventual file path costs nothing.
            $d = New-MarkFixture -Shield ''
            (Invoke-Mark -Cwd $d -MarkArgs @('prepare','seams/topic.md')).ExitCode | Should -Be 0
            (Test-Path -LiteralPath (Join-Path $d '.clavity/seams')) | Should -BeTrue
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) | Should -Match '(?m)^\*$'
        }
    }

    Context 'argument validation - it CANNOT delegate this' {
        # The 4.1 helper returns 0 on a validation fault BY CONTRACT, so agy-mark.sh receives success
        # and would proceed to write. It must reject traversal itself, BEFORE calling the helper.
        It 'refuses a <discipline> containing a separator or ..' -ForEach @(
            @{ D = '../../escape' }, @{ D = 'a/b' }, @{ D = '..' }
        ) {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('head',$D,'deadbeef')
            $r.ExitCode | Should -Be 1
            @(Get-ChildItem -LiteralPath $d -Recurse -Filter '*.head' -ErrorAction SilentlyContinue).Count | Should -Be 0
        }

        It 'refuses a <relpath> containing .. or a leading /' -ForEach @(
            @{ P = '../escape.md' }, @{ P = '/abs/path.md' }, @{ P = 'seams/../../x.md' }
        ) {
            $d = New-MarkFixture
            $r = Invoke-Mark -Cwd $d -MarkArgs @('prepare',$P)
            $r.ExitCode | Should -Be 1
        }
    }

    Context 'exit codes and failure direction' {
        It 'exits 1 and writes NOTHING when the helper cannot be loaded' {
            $d = New-MarkFixture
            $isolated = Join-Path ([IO.Path]::GetTempPath()) ("iso-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $isolated | Out-Null
            Copy-Item -LiteralPath ($script:Mark -replace '/','\') -Destination (Join-Path $isolated 'agy-mark.sh')
            $outF = Join-Path ([IO.Path]::GetTempPath()) ("iso-" + [guid]::NewGuid().ToString('N') + ".out")
            $p = Start-Process -FilePath 'bash' -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'head','agy-first','deadbeef') `
                    -WorkingDirectory $d -RedirectStandardOutput $outF -RedirectStandardError "$outF.err" -NoNewWindow -Wait -PassThru
            $p.ExitCode | Should -Be 1 -Because 'head fails CLOSED: an absent marker makes the discipline re-fire, which is safe'
            (Test-Path -LiteralPath (Join-Path $d '.clavity/agy-marks/agy-first.head')) | Should -BeFalse
            Remove-Item -LiteralPath $outF, "$outF.err" -Force -ErrorAction SilentlyContinue
        }

        It 'a REFUSED log emits BOTH the line it could not write AND the reason' {
            # skipped.log has NO re-fire path - it is a durable audit breadcrumb - so a refused write
            # destroys a record with nothing to recreate it. Emitting only the payload leaves the
            # operator holding a log line with no idea why it never reached disk.
            $d = New-MarkFixture
            $isolated = Join-Path ([IO.Path]::GetTempPath()) ("iso2-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $isolated | Out-Null
            Copy-Item -LiteralPath ($script:Mark -replace '/','\') -Destination (Join-Path $isolated 'agy-mark.sh')
            $errF = Join-Path ([IO.Path]::GetTempPath()) ("iso2-" + [guid]::NewGuid().ToString('N') + ".err")
            Start-Process -FilePath 'bash' -ArgumentList @(((Join-Path $isolated 'agy-mark.sh') -replace '\\','/'), 'log','agy-first','SKIPPED-UNREACHABLE','deadbeef') `
                -WorkingDirectory $d -RedirectStandardOutput "$errF.out" -RedirectStandardError $errF -NoNewWindow -Wait | Out-Null
            $err = Get-Content -Raw -LiteralPath $errF
            $err | Should -Match 'agy-first' -Because 'the line it could not write must be recoverable from stderr'
            $err | Should -Match 'SKIPPED-UNREACHABLE'
            $err | Should -Match '(?i)(helper|shield|could not|unable)' -Because 'the REASON is what the operator needs in order to fix it'
            Remove-Item -LiteralPath $errF, "$errF.out" -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'the shield is called on EVERY mode' {
        It 'restores a broken shield before writing' -ForEach @(
            @{ Mode = @('head','agy-first','deadbeefdeadbeefdeadbeefdeadbeefdeadbeef') },
            @{ Mode = @('log','agy-first','SKIPPED-UNREACHABLE','deadbeefdeadbeefdeadbeefdeadbeefdeadbeef') },
            @{ Mode = @('prepare','seams/topic.md') }
        ) {
            $d = New-MarkFixture -Shield ''
            Invoke-Mark -Cwd $d -MarkArgs $Mode | Out-Null
            (Get-Content -Raw -LiteralPath (Join-Path $d '.clavity/.gitignore')) | Should -Match '(?m)^\*$'
        }

        It 'FORWARDS $AGY_SESSION_ID to the helper' {
            # The hook's forwarding is pinned in Task 5; the WRAPPER's is a separate code path.
            $d = New-MarkFixture
            New-Item -ItemType Directory -Force -Path (Join-Path $d '.clavity/agy-marks') | Out-Null
            [IO.File]::WriteAllText((Join-Path $d '.clavity/agy-marks/agy-first.head'), '')
            & git -C $d add -f '.clavity/agy-marks/agy-first.head'
            & git -C $d commit -q -m 'track to create a PERSISTENT fault'
            $sid = 'ws-' + [guid]::NewGuid().ToString('N')
            $a = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first','deadbeef') -SessionId $sid
            $b = Invoke-Mark -Cwd $d -MarkArgs @('head','agy-first','deadbeef') -SessionId $sid
            ([regex]::Matches("$($a.Err)$($b.Err)", 'git rm --cached')).Count | Should -Be 1
        }
    }
}
```

- [ ] **Step 2: Run it to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-mark.Tests.ps1 -Output Detailed -CI"
```

Expected: every row FAILS - the script does not exist.

- [ ] **Step 3: Write `agy-mark.sh`**

Create `clavity-dotnet/plugin/hooks/agy-mark.sh`. **Pure ASCII, LF endings.** It lives in `hooks/` even
though it is not a hook - `agy-consult-guard-lib.sh` is the existing precedent for a non-hook file there,
and the placement is what puts it inside `check-seed-artifacts-synced.sh:63-64`'s enumeration and
`plugin-hooks-payload.Tests.ps1:26`'s `*.sh` glob. **No `hooks.json` registration is required or wanted.**

```sh
#!/usr/bin/env bash
# Sanctioned writer for <cwd>/.clavity/ (plugin-shipped). RUN as a process, never sourced - so `exit`
# is correct here, the exact opposite of agy-shield-lib.sh's return-only rule, and the difference is
# load-bearing: the helper runs inside a PreToolUse chain where a non-zero exit BLOCKS an agent, while
# this script is invoked by a skill, where a refusal blocks nothing. DO NOT HARMONISE THEM.
#
# ANCHORED TO THE INVOKING CWD, NOT git-toplevel. agy-seam-inject.sh:124 reads the debounce marker at
# "$cwd_path/.clavity/agy-marks/<discipline>.head", and its comment at :118-122 forbids the git root by
# name: a toplevel writer against that cwd reader diverges in any launched-from-subdir session and
# defeats the debounce, so the discipline re-fires forever. (open-issues/SKILL.md:63-67 legitimately
# uses toplevel for local-anomalies.md, whose reader resolves the root the same way. Two files, two
# anchors, both correct.)
#
# Modes:
#   head    <discipline> <sha>                    -> .clavity/agy-marks/<discipline>.head
#   log     <discipline> <status> <sha> [text...] -> append one line to .clavity/agy-marks/skipped.log
#   prepare <relpath>                             -> create + shield the parent of .clavity/<relpath>
#
# Exit codes: 0 wrote; 1 REFUSED, nothing written; 2 the write itself failed partway. A caller must be
# able to tell "refused" from "wrote", and one non-zero cannot express that.

set -u

_die_refuse() { printf 'agy-mark: REFUSED - %s\n' "$1" >&2; exit 1; }

mode=${1:-}
[ -n "$mode" ] || _die_refuse 'no mode given (expected head|log|prepare)'

root=$PWD
[ -d "$root" ] || _die_refuse "cwd does not resolve: [$root]"

# IT VALIDATES ITS OWN ARGUMENTS - it cannot delegate this. The 4.1 helper returns 0 on a validation
# fault BY CONTRACT, so this script would receive success and proceed to write. <discipline> and
# <relpath> are interpolated into a path, so a value containing / or .. escapes the directory.
_check_discipline() {
    case "$1" in
        ''|*[!A-Za-z0-9._-]*) _die_refuse "discipline must match [A-Za-z0-9._-]+, got: [$1]" ;;
        .|..)                 _die_refuse "discipline must not be a path segment alias: [$1]" ;;
    esac
}
_check_relpath() {
    case "$1" in
        '')    _die_refuse 'relpath is empty' ;;
        /*)    _die_refuse "relpath must not start with '/': [$1]" ;;
        *..*)  _die_refuse "relpath must not contain '..': [$1]" ;;
    esac
}

# Load the shield helper. Hard-wired: there is no way to skip it. Its return value carries no
# information (it is always 0) and must not be branched on.
_lib="$(dirname "$0")/agy-shield-lib.sh"
[ -f "$_lib" ] || _die_refuse "shield helper not found beside this script: [$_lib]"
# shellcheck source=agy-shield-lib.sh
. "$_lib" 2>/dev/null || _die_refuse "shield helper could not be sourced: [$_lib]"
command -v agy_shield >/dev/null 2>&1 || _die_refuse "shield helper loaded but agy_shield is not defined: [$_lib]"

_key=${AGY_SESSION_ID:-}

case "$mode" in
    head)
        discipline=${2:-}; sha=${3:-}
        _check_discipline "$discipline"
        [ -n "$sha" ] || _die_refuse 'head requires a sha argument'
        rel=".clavity/agy-marks/$discipline.head"
        agy_shield "$root" "$rel" "$_key"
        # EVERY mode creates the directory it writes into. The helper's Stage A1 creates .clavity/ and
        # NOTHING BELOW IT, and this batch removes the skills' own mkdir instructions, so without this
        # a fresh clone fails "No such file or directory" on the first discipline that runs.
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || _die_refuse 'could not create .clavity/agy-marks'
        # BARE sha and nothing else (docs/agy-disciplines-marker-contract.md:18).
        printf '%s' "$sha" > "$root/$rel" 2>/dev/null || { printf 'agy-mark: write FAILED partway for %s\n' "$rel" >&2; exit 2; }
        exit 0
        ;;
    log)
        discipline=${2:-}; status=${3:-}; sha=${4:-}
        shift 4 2>/dev/null || true
        text=$*
        rel=".clavity/agy-marks/skipped.log"
        # THE SCRIPT OWNS THE LINE FORMAT. Callers must NOT pass a preformatted line - moving the shape
        # here is the entire point of having a script, and leaving it in the callers keeps copies of a
        # format that must agree.
        printf -v _ts '%(%Y-%m-%dT%H:%M:%SZ)T' -1 2>/dev/null || _ts=$(TZ=UTC date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
        if [ -n "$text" ]; then
            line=$(printf '%s  %s  %s  HEAD=%s  %s' "$_ts" "$discipline" "$status" "$sha" "$text")
        else
            line=$(printf '%s  %s  %s  HEAD=%s' "$_ts" "$discipline" "$status" "$sha")
        fi
        # log has NO re-fire path - skipped.log is a durable audit breadcrumb - so a refused or failed
        # write destroys a record with nothing to recreate it. Emit BOTH the line AND the reason on
        # stderr. This binds on exit 1 AND on exit 2: in both cases the record did not reach disk.
        _log_lost() { printf 'agy-mark: LOG LINE NOT WRITTEN - %s\n  %s\n' "$1" "$line" >&2; }
        _check_discipline_log() {
            case "$discipline" in
                ''|*[!A-Za-z0-9._-]*) _log_lost "discipline must match [A-Za-z0-9._-]+, got: [$discipline]"; exit 1 ;;
            esac
        }
        _check_discipline_log
        [ -n "$status" ] || { _log_lost 'no status given'; exit 1; }
        agy_shield "$root" "$rel" "$_key"
        mkdir -p "$root/.clavity/agy-marks" 2>/dev/null || { _log_lost 'could not create .clavity/agy-marks'; exit 1; }
        # ONE printf >>, never read-modify-write: two sessions can be open on the same repository, and a
        # single short append is atomic on POSIX, so concurrent writers interleave lines rather than
        # corrupting them.
        printf '%s\n' "$line" >> "$root/$rel" 2>/dev/null || { _log_lost 'the append itself failed'; exit 2; }
        exit 0
        ;;
    prepare)
        relpath=${2:-}
        _check_relpath "$relpath"
        rel=".clavity/$relpath"
        agy_shield "$root" "$rel" "$_key"
        _parent=$(dirname "$root/$rel")
        mkdir -p "$_parent" 2>/dev/null || _die_refuse "could not create $_parent"
        exit 0
        ;;
    *)
        _die_refuse "unknown mode: [$mode] (expected head|log|prepare)"
        ;;
esac
```

**Note on the helper-unloadable rows:** `_die_refuse` runs BEFORE any `mkdir` or write, so nothing is
created - which is what those rows assert.

- [ ] **Step 4: Mirror, register, run**

```bash
cp clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
git hash-object clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh
```

Add `'scripts/tests/agy-mark.Tests.ps1'` to the `test-scripts-slow` recipe in `justfile` and a row to `_partition.md`'s census
table. Then:

```bash
pwsh -c "Invoke-Pester scripts/tests/agy-mark.Tests.ps1 -Output Detailed -CI"
```

Expected: all rows PASS.

- [ ] **Step 5: Mutation controls**

| mutation | row that must turn RED |
|---|---|
| neuter the `agy_shield` call in each mode | `restores a broken shield before writing` (all three cases) |
| change `root=$PWD` to `root=$(git rev-parse --show-toplevel)` | `ANCHORS TO CWD ... the subdirectory pin` |
| delete the `mkdir -p "$root/.clavity/agy-marks"` from `head` | `CREATES .clavity/agy-marks/ on a fresh clone` |
| replace `exit 2` on the failed append with `exit 1` | `a write that fails partway` (add if absent) |
| drop the line from the refused-log stderr, keeping only the reason | `a REFUSED log emits BOTH` |
| pass a hard-coded key instead of `${AGY_SESSION_ID:-}` | `FORWARDS $AGY_SESSION_ID to the helper` |
| delete `_check_discipline` | the `refuses a <discipline>` rows |

- [ ] **Step 6: Gates and commit**

```bash
bash scripts/check-seed-artifacts-synced.sh
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed -CI"
just check-injected-context
git add clavity-dotnet/plugin/hooks/agy-mark.sh clavity-classic/plugin/hooks/agy-mark.sh \
        scripts/tests/agy-mark.Tests.ps1 justfile scripts/tests/_partition.md
git commit -m "feat(shield): 14c - agy-mark.sh, the sanctioned .clavity writer for the skills"
```

---

## Task 7: Item 14c - rewrite the three skills (CONDITIONAL on Task 1 = RESOLVED)

> **SKIP THIS TASK ENTIRELY if Task 1 recorded BLOCKED.**

**Files (all byte-identical pairs - six files):**
- `clavity-{dotnet,classic}/plugin/skills/agy-first/SKILL.md`
- `clavity-{dotnet,classic}/plugin/skills/agy-capstone/SKILL.md`
- `clavity-{dotnet,classic}/plugin/skills/agy-test-audit/SKILL.md`

**`open-issues` is NOT in this set** - it is item 14d and was rewritten in Task 4. The WRITER set is five
artifacts; the REWRITE set is three.

**There is deliberately NO behavioural test for these edits.** The strongest available oracle asserts the
`.md` contains the invocation string, which cannot fail against a model that ignores it. The executable
is where the strength lives. **The per-file completion check in Task 16 is the only guarantee that the
edit was made at all**, and that is a different question from whether the model obeys it.

- [ ] **Step 1: Replace each write instruction with an `agy-mark.sh` invocation**

Use the locator recorded in Task 1's measurement file. The invocation is **identical text in both
plugins** and resolves differently at runtime, which is what satisfies `agy-first/SKILL.md:111-112`.

Per-file edits, by verified line:

| file | line(s) | change |
|---|---|---|
| `agy-first/SKILL.md` | `:93-96` | replace "create `.clavity/agy-marks/` ... then append one durable line to `.clavity/agy-marks/skipped.log` (`<iso-8601> agy-first SKIPPED-UNREACHABLE HEAD=<sha>`...)" with a single `log` invocation. **Delete the `mkdir` instruction and the format literal** - the script owns both. |
| `agy-first/SKILL.md` | `:105-107` | replace "Create `.clavity/agy-marks/` first ... then write the current commit sha to the marker" with a single `head` invocation. Keep `:109-121` (the Path/Content/Lifecycle rows) as documentation of what the script produces. |
| `agy-first/SKILL.md` | `:37` | add: name the seam file to `prepare` before writing it. |
| `agy-capstone/SKILL.md` | `:179-180`, `:252-253` | replace both `skipped.log` write instructions with `log` invocations; delete both format literals. |
| `agy-capstone/SKILL.md` | `:265` | replace the marker instruction with a `head` invocation. |
| `agy-capstone/SKILL.md` | `:41`, `:43`, `:174` | add `prepare` for the seam file and for a concrete file inside the scratch directory - **never the directory itself**, see below. |
| `agy-test-audit/SKILL.md` | `:221-222` | replace the marker instruction with a `head` invocation. |
| `agy-test-audit/SKILL.md` | `:36`, `:38` | add `prepare` for the seam file and the scratch directory. |

The canonical invocation block to paste (adjust mode and arguments per site):

```bash
# Write through the shipped marker writer, never by hand: it asserts the .clavity/ shield BEFORE the
# write, owns the log line format, and creates the directory it writes into. <BASE> is this skill's own
# base directory, which the harness supplies at invocation time.
bash "<BASE>/../../hooks/agy-mark.sh" head agy-first "$(git rev-parse HEAD)"
```

**`prepare` ALWAYS takes a FILE path, never a directory - and for a scratch DIRECTORY that is a trap.**
`agy-mark.sh` resolves the target with `_parent=$(dirname "$root/$rel")`, so passing `scratch/<topic>/`
creates `.clavity/scratch` and **not** `.clavity/scratch/<topic>` - the directory the discipline is about
to fill still does not exist, and the next write fails mid-run. Pass a concrete file that will live in
that directory, e.g. `prepare "scratch/<topic>/notes.md"`, which creates and shields
`.clavity/scratch/<topic>/`. **Do not invent a dummy-file convention** and do not add a directory mode:
the file path is what Stage B needs in order to evaluate the tracked-file check for the thing actually
being written.

- [ ] **Step 2: Make the three skills ACT on a `prepare` refusal**

`prepare` fails closed, and the re-fire argument does not cover it: if it refuses, the directory does not
exist and the agent's very next write fails `No such file or directory` **in the middle of the
discipline** rather than re-firing cleanly. Each skill that invokes `prepare` must check the exit status
and **ABORT the discipline with a named reason**, exactly as it already does for an unreachable peer.

Add immediately after each `prepare` invocation:

```bash
if ! bash "<BASE>/../../hooks/agy-mark.sh" prepare "seams/<topic>.md"; then
  # ABORT the discipline and say why. A skill that ignores this exit code converts a clean refusal
  # into a mid-run crash on the next write.
  echo "agy-first: ABORTING - could not prepare a shielded .clavity/seams/ directory." >&2
  exit 1
fi
```

- [ ] **Step 3: Mirror all three to classic and verify byte-identity**

```bash
for s in agy-first agy-capstone agy-test-audit; do
  cp "clavity-dotnet/plugin/skills/$s/SKILL.md" "clavity-classic/plugin/skills/$s/SKILL.md"
  echo "$s: $(git hash-object clavity-dotnet/plugin/skills/$s/SKILL.md) $(git hash-object clavity-classic/plugin/skills/$s/SKILL.md)"
done
```

Expected: each pair of hashes identical.

- [ ] **Step 4: Per-file completion check**

```bash
for p in clavity-dotnet clavity-classic; do
  for s in agy-first agy-capstone agy-test-audit; do
    printf '%s/%s: %s\n' "$p" "$s" "$(grep -c 'agy-mark.sh' $p/plugin/skills/$s/SKILL.md)"
  done
done
```

Expected: **six** non-zero counts. A zero means that file was not edited - which no cross-product gate can
detect, because they compare the two products against each other and a file left unedited in BOTH passes
byte-identity happily.

- [ ] **Step 5: Gates and commit**

```bash
bash scripts/check-seed-artifacts-synced.sh
just check-injected-context
git add clavity-dotnet/plugin/skills clavity-classic/plugin/skills
git commit -m "refactor(shield): 14c - the three disciplines write via agy-mark.sh"
```

---

## Task 8: Item 14c - rewrite ROADMAP section 14c IN PLACE

**Owner decision 2026-08-14: the entry is REWRITTEN IN PLACE, not annotated with a dated correction**, so
no future reader meets the wrong sentence at all. (Both agy and I had recommended the dated-correction
form used at `ROADMAP.md:921-922`; the owner took the rewrite. Do not re-litigate.)

**Files:** Modify `clavity-dotnet/ROADMAP.md` at `:982`, `:988`, `:991`.

### M5 - the wrong fact lives at THREE sites, not two

Verified:

| line | current text (verbatim fragment) |
|---|---|
| `:982` | `**§14c — 7 shipped hooks write into `.clavity/` and none assert the `.gitignore` shield.**` |
| `:988` | `section 6) mandates the shield for the *new* reader; **this entry is the existing seven.**` |
| `:991` | `> EXISTENCE, not content. Fix §14d first, or §14c's seven hooks inherit the weak idiom.` |

**A grep shaped like `:991`'s wording ("seven hooks") misses `:988` ("the existing seven").** Global rule
4: sweep the FACT in several wordings, not the line.

- [ ] **Step 1: Sweep for every wording BEFORE editing**

```bash
grep -n "seven\|7 shipped\|7 hooks" clavity-dotnet/ROADMAP.md
grep -rn "seven hooks\|7 shipped hooks\|existing seven" --include=*.md .
```

Record every hit. Any hit outside the three lines above is a fourth site the plan did not know about -
STOP and report it rather than silently fixing it.

- [ ] **Step 2: Rewrite `:982`'s claim**

Replace the "7 shipped hooks" heading sentence with the measured set. The predicate must appear, because
a count with no stated predicate is what produced the wrong number:

```markdown
**§14c — FIVE shipped artifacts write into `.clavity/` and none asserts the `.gitignore` shield: ONE HOOK
and FOUR SKILLS.** Measured 2026-08-14 under a stated predicate — *a shipped plugin artifact that CREATES
or WRITES a path under `<repo-root>/.clavity/`, traced through variable assignments to the RESOLVED
target*, not by proximity of a write construct to the token `.clavity`. The earlier "7 shipped hooks" came
from that proximity predicate and was wrong in KIND as well as in count. The set:
`plugin/hooks/agy-discipline-reaching.sh` · `plugin/skills/agy-first/SKILL.md` ·
`plugin/skills/agy-capstone/SKILL.md` · `plugin/skills/agy-test-audit/SKILL.md` ·
`plugin/skills/open-issues/SKILL.md` (weakly, at `:79` — that one is §14d).
**Excluded, with the reason:** `adversarial-panel-review/SKILL.md:203` names the path but delegates the
write; the other six hooks write to `${TMPDIR:-/tmp}` or `$HOME/.clavity-tmp` — a DIFFERENT directory —
and say so themselves (`agy-anomaly-capture-reminder.sh:49`, `assertion-strength-reminder.sh:9`).
```

- [ ] **Step 3: Rewrite `:988` and `:991`**

`:988` — replace `**this entry is the existing seven.**` with `**this entry is the existing five.**`

`:991` — replace `§14c's seven hooks inherit the weak idiom` with
`§14c's five artifacts inherit the weak idiom`.

- [ ] **Step 4: If Task 1 recorded BLOCKED, record the deferral here**

Append to the §14c entry:

```markdown
> **PARTIALLY SHIPPED 2026-08-14.** The HOOK half landed (`agy-discipline-reaching.sh` sources the
> shield helper directly). The SKILL half is DEFERRED: `$CLAUDE_PLUGIN_ROOT` is unset in a
> skill-context shell call (measured, with a passing control), and the byte-identical skill body
> cannot carry a per-plugin literal (`agy-first/SKILL.md:111-112`), so the four SKILL.md callers have
> no sanctioned way to locate a shipped executable. **Not worked around** — a glob is ambiguous in the
> both-installed migration state that same line declares supported.
```

- [ ] **Step 5: Verify the sweep is complete**

```bash
grep -n "seven\|7 shipped\|7 hooks" clavity-dotnet/ROADMAP.md
```

Expected: **no hits describing §14c's writer set.** Hits elsewhere in the file about unrelated counts are
fine - read each one before dismissing it.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): 14c - the writer set is five artifacts, one hook and four skills"
```

---
## Task 9: Item 14e - pin the three paths to `eol=lf`

This kills the whole CRLF class at its root, using a mechanism `.gitattributes` already uses for `*.sh`.

**Files:** Modify `.gitattributes`.

**Verified current state:** `.gitattributes` pins `*.sh text eol=lf` (at `:3` and again at `:12` - a
pre-existing duplicate; leave it alone, it is not this batch's) and
`installer/_shared/register-plugin.ps1 text eol=crlf` at `:17`. **None of the three cheatsheet paths is
pinned.** `core.autocrlf` is `true`, so a fresh clone checks out all three as CRLF.

- [ ] **Step 0: PRECONDITION - the three paths must be CLEAN, and this is not optional**

Step 3 overwrites the working tree from the index. A developer running this mid-edit **silently destroys
their own uncommitted changes**.

```bash
git status --short -- .gitattributes \
                      agy-autotrain/knowledge/driver-cheatsheet.core.md \
                      clavity-classic/src/driver_cheatsheet.rs \
                      clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
```

Expected: **empty output**. If anything is listed, STOP - commit or stash first, then resume.

> **`.gitattributes` is in that list for a reason panel R8 found, not for symmetry.** Step 6 commits it
> alongside the three paths, so an unrelated uncommitted edit a developer already had there would be
> silently swept into this task's `chore(eol)` commit. **This repository has already had `git add` carry
> an unintended file twice**, once onto a public repo - the standing rule is explicit paths, and this
> extends it to "check every path you are about to add, not only the ones you are about to change".
> Step 3's destructive `rm -f` + `git checkout --` sequence only reads the three cheatsheet paths, so
> `.gitattributes` is not at risk THERE; the exposure is purely at the commit.

- [ ] **Step 1: Record the BEFORE bytes (the control for step 3)**

```bash
for f in agy-autotrain/knowledge/driver-cheatsheet.core.md clavity-classic/src/driver_cheatsheet.rs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs; do
  printf '%s worktree=%s index=%s crlf=%s\n' "$f" \
    "$(wc -c < "$f")" \
    "$(git show :"$f" | wc -c)" \
    "$(grep -c $'\r' "$f" || true)"
done
git check-attr text eol -- agy-autotrain/knowledge/driver-cheatsheet.core.md clavity-classic/src/driver_cheatsheet.rs
```

Expected today: `core.md` worktree **3515** / index **3508**, CRLF present; `check-attr` reports
**`unspecified`** for both. Record the actual numbers - they are the control for step 4.

- [ ] **Step 2: Add the attribute lines**

Append to `.gitattributes`:

```
# The driver-cheatsheet source and its two GENERATED literals must be LF everywhere. The pre-commit
# parity hook compares the generator's output against the INDEX blob, which git stores as LF, so a
# CRLF checkout of any of these three would mismatch on every commit. Measured 2026-08-14:
# core.autocrlf is true and `git check-attr text eol` reported `unspecified` for all three, so a fresh
# clone checked them out as CRLF. Same mechanism, same reason, as the *.sh pin above.
agy-autotrain/knowledge/driver-cheatsheet.core.md text eol=lf
clavity-classic/src/driver_cheatsheet.rs text eol=lf
clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs text eol=lf
```

- [ ] **Step 3: Renormalise the index, then force the worktree re-checkout**

**The pin governs FUTURE checkouts and does NOT rewrite an existing working tree** - measured in a
throwaway repo with `core.autocrlf=true`: adding `*.md text eol=lf` left a CRLF file **unchanged**, and
`git add --renormalize .` normalised the **INDEX** blob while leaving the **WORKTREE still CRLF**. So the
sequence matters, and step 4 verifies by BYTES rather than by assumption.

```bash
git add --renormalize agy-autotrain/knowledge/driver-cheatsheet.core.md \
                      clavity-classic/src/driver_cheatsheet.rs \
                      clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
# Name each path explicitly - NEVER a directory. A broad checkout is the failure mode this repo
# already carries a rule against.
rm -f agy-autotrain/knowledge/driver-cheatsheet.core.md
git checkout -- agy-autotrain/knowledge/driver-cheatsheet.core.md
rm -f clavity-classic/src/driver_cheatsheet.rs
git checkout -- clavity-classic/src/driver_cheatsheet.rs
rm -f clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
git checkout -- clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
```

- [ ] **Step 4: MEASURE the bytes - do not infer that it worked**

```bash
for f in agy-autotrain/knowledge/driver-cheatsheet.core.md clavity-classic/src/driver_cheatsheet.rs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs; do
  printf '%s worktree=%s index=%s crlf=%s\n' "$f" "$(wc -c < "$f")" "$(git show :"$f" | wc -c)" "$(grep -c $'\r' "$f" || true)"
done
```

Expected: for every file, **worktree bytes == index bytes** and **crlf == 0**. `core.md` should now read
3508/3508. If a file still shows CRLF, the re-checkout did not happen - do not proceed.

- [ ] **Step 5: The pinning suites must still be GREEN - step 3 changed files they compare**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~DriverCheatsheet" ; cd ..
cd clavity-classic && cargo test --all --features test-fakes driver_cheatsheet ; cd ..
```

Expected: **read the COUNT, not just the exit code** - `dotnet test --filter` exits 0 when its filter
matches nothing. Expect at least the `BaselineFloor_matches_the_canonical_core_source` fact and the Rust
`baseline_floor_matches_canonical_core_source` test to have RUN and passed.

- [ ] **Step 6: Commit**

```bash
git add .gitattributes agy-autotrain/knowledge/driver-cheatsheet.core.md \
        clavity-classic/src/driver_cheatsheet.rs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
git commit -m "chore(eol): 14e - pin the three cheatsheet paths to eol=lf and renormalise"
```

---

## Task 10: Item 14e - the generator and its `just` task

**Files:**
- Create: `scripts/generate-cheatsheet-literals.ps1`
- Create: `scripts/tests/generate-cheatsheet-literals.Tests.ps1`
- Modify: `justfile` (a new recipe, alongside the `check-*` family around `:117-130`)
- Modify: `scripts/README.md` (**required** - `scripts-readme-inventory.Tests.ps1:33` reds otherwise)
- Modify: the `test-scripts-slow` recipe in `justfile` (register the new suite - SLOW, see Step 6) and `scripts/tests/_partition.md`

**Verified target shapes** - the generator must reproduce these byte-for-byte:

| target | shape | verified |
|---|---|---|
| `clavity-classic/src/driver_cheatsheet.rs` | ONE line: `pub const BASELINE_FLOOR: &str = "<escaped>";` | `:17` |
| `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` | `public const string BaselineFloor =` at `:30`, then the FIRST segment with **no `+`** at `:31`, middle segments `+ "...\n"` at `:32-36`, and the LAST segment with **no trailing `\n`, ending `;`** at `:37`. All segments indented 8 spaces. | `:30-37` |

**The C# target needs LINE-BOUNDARY logic a whole-string replace cannot produce** - a single
`.Replace()` over the whole text yields either a dangling `+` or a trailing `\n` the file side does not
have. The Rust target has the opposite shape (one line, no splitting), which is why "escaping is
mechanical" is true per-target and misleading if read as one shared routine.

- [ ] **Step 1: Write the failing test - the GENERATOR-CONTROL pattern first**

Create `scripts/tests/generate-cheatsheet-literals.Tests.ps1`:

```powershell
# Tests for scripts/generate-cheatsheet-literals.ps1.
#
# THE GENERATOR-CONTROL PATTERN IS THE FIRST ROW AND THE MOST IMPORTANT ONE: fed the CURRENT core.md,
# the generator must reproduce the CURRENT artifacts BYTE-FOR-BYTE. Only a generator proven against the
# artifact it is replacing may then be trusted to change it. Both existing pinning tests stay and are
# the oracle the generator is proven against - they are NOT to be edited to match generator output.

Describe 'generate-cheatsheet-literals.ps1' {
    BeforeAll {
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Gen  = Join-Path $script:RepoRoot 'scripts/generate-cheatsheet-literals.ps1'
        $script:Core = Join-Path $script:RepoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
        $script:Rs   = Join-Path $script:RepoRoot 'clavity-classic/src/driver_cheatsheet.rs'
        $script:Cs   = Join-Path $script:RepoRoot 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs'
        Test-Path -LiteralPath $script:Gen | Should -BeTrue
    }

    It 'reproduces BOTH current artifacts byte-for-byte from the current core.md (the control)' {
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gen-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'driver_cheatsheet.rs'
            $outCs = Join-Path $tmp 'DriverCheatsheet.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0
            # BYTE comparison, both directions. A text comparison would hide exactly the line-ending
            # and encoding defects this item exists to prevent.
            [IO.File]::ReadAllBytes($outRs) | Should -Be ([IO.File]::ReadAllBytes($script:Rs))
            [IO.File]::ReadAllBytes($outCs) | Should -Be ([IO.File]::ReadAllBytes($script:Cs))
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'NORMALISES CRLF to LF - against a CONSTRUCTED fixture, never the live core.md' {
        # THE FIXTURE MUST BE CONSTRUCTED. core.md's line endings depend on the host: after Task 9 it is
        # LF here, and it is LF in CI. A test that feeds the live file processes LF, emits LF and stays
        # green - AND SO DOES THE MUTANT with normalisation deleted. The test and its own mutation
        # control would both pass while proving nothing, which is the worst kind of green: it looks
        # correct on the machine where it was written.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gencrlf-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllBytes($fx, [Text.Encoding]::ASCII.GetBytes("line one`r`nline two`r`nline three`r`n"))
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0
            # ASSERT ON BYTES, NOT ON A REGEX - panel R3 caught the first version of these two lines as a
            # VACUOUS ORACLE. They read `Should -Not -Match '\\r'`, and in a PowerShell single-quoted
            # string that is backslash-backslash-r, which as a regex matches the two-character TEXT \r -
            # not a carriage return. Deleting the generator's normalisation leaves RAW 0x0D bytes in the
            # output, which do not match that pattern at all, so the row stayed GREEN against the exact
            # break it names. The -Because text said "a bare \r" while the pattern tested the escaped
            # form: intent and implementation disagreed, which is what made it look correct.
            ([IO.File]::ReadAllBytes($outRs) | Where-Object { $_ -eq 13 }).Count |
                Should -Be 0 -Because 'a raw CR (0x0D) must never be baked into the Rust literal'
            ([IO.File]::ReadAllBytes($outCs) | Where-Object { $_ -eq 13 }).Count |
                Should -Be 0 -Because 'a raw CR (0x0D) must never be baked into the C# literal'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'writes the container files with LF endings, not the platform newline' {
        # Measured on pwsh 7: Set-Content/Out-File/WriteAllText all PRESERVE LF for a SINGLE string,
        # but the ARRAY form joins with the PLATFORM newline and emits CRLF. The hazard is the array
        # form specifically, so this row pins the OUTPUT container, not just the escaped content.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genlf-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs
            ([IO.File]::ReadAllBytes($outRs) | Where-Object { $_ -eq 13 }).Count | Should -Be 0
            ([IO.File]::ReadAllBytes($outCs) | Where-Object { $_ -eq 13 }).Count | Should -Be 0
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'escapes BACKSLASH FIRST - a backslash in the source does not become an escaped newline' {
        # ORDER IS PART OF THE CONTRACT. Escaping the newline before the backslash makes the generator
        # escape its OWN output: LF becomes the two characters \n, and a later backslash pass turns
        # that into \\n, which both compilers read as a literal backslash followed by n. The literal
        # then COMPILES CLEANLY and fails the pinning test with a diff no one can see at a glance.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genesc-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllText($fx, "alpha \ beta`ngamma `"quoted`" delta`n")
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs
            $rs = [IO.File]::ReadAllText($outRs)
            $rs | Should -Match 'alpha \\\\ beta'   -Because 'a literal backslash must be emitted as \\'
            $rs | Should -Match 'gamma \\"quoted\\" delta'
            $rs | Should -Not -Match '\\\\n'        -Because 'a newline must be \n, never \\n'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'produces the C# LINE-BOUNDARY shape: no leading +, no trailing \n on the last segment, ends ;' {
        $cs = [IO.File]::ReadAllText($script:Cs)
        $cs | Should -Match '(?m)^public const string BaselineFloor =\r?\n\s+"' -Because 'the FIRST segment carries no +'
        $cs | Should -Match '(?m)^\s+\+ ".*";\s*$'                              -Because 'the LAST segment ends with ; '
        $cs | Should -Not -Match '(?m)^\s+\+ ".*\\n";\s*$'                      -Because 'the LAST segment has no trailing \n'
    }

    It 'REFUSES to write when the anchor is not found EXACTLY once' {
        # A splice on a non-unique anchor deletes the span between matches. The generator must fail
        # loudly rather than mangle a source file.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genanch-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            [IO.File]::WriteAllText($outRs, "// no anchor here`n")
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget $outRs -CsTarget $outCs 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
            [IO.File]::ReadAllText($outRs) | Should -BeExactly "// no anchor here`n" -Because 'a refused run must leave the target untouched'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'SKIPS a target given as an empty string, and still writes the other (panel R6)' {
        # The 14e hook needs this: a literal whose deletion is staged is gone from the worktree, so there
        # is nothing to splice into. Without an empty-target skip the hook must Copy-Item a file that does
        # not exist, which throws under $ErrorActionPreference='Stop' and CRASHES the hook on exactly the
        # case its own test table says must PASS.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genskip-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget '' -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0 -Because 'an empty target means SKIP, not error'
            [IO.File]::ReadAllBytes($outCs) | Should -Be ([IO.File]::ReadAllBytes($script:Cs))
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FAILS on an EMPTY canonical source rather than generating an empty literal (panel R9)' {
        # The generator carries `if ($coreText.Length -eq 0) { Fail ... }` and nothing exercised it. An
        # empty core.md would otherwise splice an empty literal into both binaries and the pinning tests
        # would go red one layer away from the cause.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("genempty-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllText($fx, "   `n  `n")   # whitespace only: empty AFTER Trim()
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            $before = [IO.File]::ReadAllBytes($outRs)
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs *> $null
            $LASTEXITCODE | Should -Not -Be 0
            [IO.File]::ReadAllBytes($outRs) | Should -Be $before -Because 'a refused run must leave the target untouched'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'handles a SINGLE-LINE core.md - no dangling + and no trailing \n (panel R9)' {
        # The generator has a dedicated `if ($coreLines.Count -eq 1)` branch for the C# target and the
        # live core.md is multi-line, so nothing exercised it. A whole-string replace would emit either a
        # dangling + or a trailing \n the file side does not have - the exact shape this branch exists for.
        $tmp = Join-Path ([IO.Path]::GetTempPath()) ("gen1line-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            $fx = Join-Path $tmp 'core.md'
            [IO.File]::WriteAllText($fx, "just one line`n")
            $outRs = Join-Path $tmp 'x.rs'; $outCs = Join-Path $tmp 'x.cs'
            Copy-Item -LiteralPath $script:Rs -Destination $outRs
            Copy-Item -LiteralPath $script:Cs -Destination $outCs
            & pwsh -NoProfile -File $script:Gen -CoreSource $fx -RustTarget $outRs -CsTarget $outCs
            $LASTEXITCODE | Should -Be 0
            $cs = [IO.File]::ReadAllText($outCs)
            $cs | Should -Match '"just one line";'
            $cs | Should -Not -Match '\+ "just one line'  -Because 'a single segment is also the FIRST segment and carries no +'
            $cs | Should -Not -Match 'just one line\\n"'  -Because 'the last segment has no trailing \n'
        }
        finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It 'FAILS when BOTH targets are empty - a no-op run must not report success' {
        & pwsh -NoProfile -File $script:Gen -CoreSource $script:Core -RustTarget '' -CsTarget '' *> $null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'preserves pure ASCII (core.md is inside the ASCII-gated domain)' {
        ([IO.File]::ReadAllBytes($script:Rs) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
        ([IO.File]::ReadAllBytes($script:Cs) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run it to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/generate-cheatsheet-literals.Tests.ps1 -Output Detailed -CI"
```

Expected: all rows FAIL - the generator does not exist.

- [ ] **Step 3: Write the generator**

Create `scripts/generate-cheatsheet-literals.ps1`:

```powershell
#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Generate the two compiled-in cheatsheet literals from the canonical markdown source, making their
  divergence structurally impossible rather than merely detectable (ROADMAP 14e).

.DESCRIPTION
  THE THREE FILES ARE NOT BYTE-IDENTICAL TO EACH OTHER AND NEVER CAN BE - measured 3515 / 11544 / 7801
  bytes with three distinct hashes. One is markdown, one a Rust source carrying a single-line escaped
  literal, one a C# source carrying a concatenated multi-line literal. The lefthook comment calling them
  "pinned byte-identical to each other" is loose wording. THE REAL INVARIANT IS: the DECODED literal
  equals the markdown file's content, which is exactly what both existing pinning tests assert.

  This script only ever READS core.md, so it is correct under either resolution of the ownership
  question tracked as ROADMAP 14f. What it removes is the manual multi-file mirroring that made a
  mistaken edit dangerous - it narrows the hand-edited surface from three files to one.

  ESCAPING ORDER IS PART OF THE CONTRACT: backslash, then double-quote, then newline. Escaping the
  newline first makes the generator escape its own output (LF -> \n -> \\n), which compiles cleanly and
  fails the pinning test with an invisible diff.

  IT WRITES ONE LF-JOINED STRING AND NEVER A LINE ARRAY. Measured on pwsh 7: Set-Content, Out-File and
  WriteAllText all preserve LF for a SINGLE string, but the ARRAY form joins with the PLATFORM newline
  and emits CRLF - which would mismatch the LF index blob on every commit.
#>
[CmdletBinding()]
param(
    [string]$CoreSource,
    [string]$RustTarget,
    [string]$CsTarget
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $CoreSource) { $CoreSource = Join-Path $repoRoot 'agy-autotrain/knowledge/driver-cheatsheet.core.md' }
if (-not $RustTarget) { $RustTarget = Join-Path $repoRoot 'clavity-classic/src/driver_cheatsheet.rs' }
if (-not $CsTarget)   { $CsTarget   = Join-Path $repoRoot 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs' }

function Fail([string]$msg) {
    Write-Host "generate-cheatsheet-literals: $msg" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $CoreSource)) { Fail "canonical source not found: $CoreSource" }
# AN EMPTY TARGET MEANS "SKIP THAT HALF", and it is a real requirement, not a convenience. The 14e
# pre-commit hook must generate for only the literals it will compare: a literal whose deletion is staged
# is gone from the worktree, so there is nothing to splice into, and demanding both targets would make
# the hook crash on exactly the case its test table says must PASS. Only a path that is BOTH non-empty
# AND missing is an error.
$doRust = -not [string]::IsNullOrWhiteSpace($RustTarget)
$doCs   = -not [string]::IsNullOrWhiteSpace($CsTarget)
if (-not $doRust -and -not $doCs) { Fail 'both targets were empty - nothing to generate' }
if ($doRust -and -not (Test-Path -LiteralPath $RustTarget)) { Fail "rust target not found: $RustTarget" }
if ($doCs   -and -not (Test-Path -LiteralPath $CsTarget))   { Fail "C# target not found: $CsTarget" }

# READ AS BYTES AND DECODE EXPLICITLY. Get-Content -Raw would go through the host encoding.
$coreText = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($CoreSource))
# NORMALISE, THEN ESCAPE. The pinning tests normalise only the FILE side and compare it to the literal
# AS-IS, so a generator that bakes \r\n into the literals reddens the exact gate it exists to protect.
$coreText = $coreText.Replace("`r`n", "`n").Trim()
# STRIP A LEADING BOM EXPLICITLY - .Trim() does NOT remove it. Measured: [char]::IsWhiteSpace(0xFEFF) is
# FALSE in .NET, so a BOM survives Trim() and would be baked verbatim into the START of both literals.
# ReadAllBytes + UTF8.GetString is used deliberately here (Get-Content would hide the problem by
# stripping it), so this decode keeps the BOM as U+FEFF. core.md has NO BOM today (measured: it starts
# 44 72 69), which makes this latent rather than live - and latent is exactly when it is cheap to close.
# Left unhandled it would fail LOUDLY but confusingly: the pinning tests read the file with
# File.ReadAllText, which DOES strip the BOM, so only the literal would carry it, and U+FEFF is
# non-ASCII so the injected-context gate would red as well.
$coreText = $coreText.TrimStart([char]0xFEFF)

if ($coreText.Length -eq 0) { Fail "canonical source is empty after trim: $CoreSource" }

# ORDER: backslash, then double-quote, then newline. Never reorder these three lines.
function ConvertTo-EscapedLiteral([string]$s) {
    $s = $s.Replace('\', '\\')
    $s = $s.Replace('"', '\"')
    $s = $s.Replace("`n", '\n')
    return $s
}

# ---------------------------------------------------------------------- Rust: ONE line, no splitting.
# THE GUARD WRAPS THE READ, NOT ONLY THE WRITE. Panel R7 measured that the first version of the
# empty-target skip guarded only the two WriteAllText calls while reading both targets unconditionally -
# and [IO.File]::ReadAllBytes('') THROWS (measured; control: a missing path throws too). So the skip
# crashed the generator, the hook read a non-zero exit, and it aborted BEFORE evaluating parity for the
# literal that was still present - violating the very test row (11) the skip was added to satisfy.
$rustLines = @()
if ($doRust) {
    $rustLiteral = ConvertTo-EscapedLiteral $coreText
    $rustLine    = 'pub const BASELINE_FLOOR: &str = "' + $rustLiteral + '";'

    $rustText  = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($RustTarget)).Replace("`r`n", "`n")
    $rustLines = $rustText -split "`n", -1
    $rustAnchor = @($rustLines | Where-Object { $_ -like 'pub const BASELINE_FLOOR: &str = *' })
    # A SPLICE ON A NON-UNIQUE ANCHOR DELETES THE SPAN BETWEEN MATCHES. Refuse rather than mangle.
    if ($rustAnchor.Count -ne 1) { Fail "expected exactly ONE 'pub const BASELINE_FLOOR' line in $RustTarget, found $($rustAnchor.Count)" }
    for ($i = 0; $i -lt $rustLines.Count; $i++) {
        if ($rustLines[$i] -like 'pub const BASELINE_FLOOR: &str = *') { $rustLines[$i] = $rustLine; break }
    }
}

# ------------------------------------------------------- C#: LINE-BOUNDARY logic, not a whole-string replace.
# The first segment carries no '+', every middle segment is '+ "...\n"', and the LAST segment has no
# trailing \n and ends with ';'. A single .Replace() over the whole text produces either a dangling '+'
# or a trailing \n the file side does not have.
$indent = '        '
$csSegments = @()
$csOut = @()
$coreLines = $coreText -split "`n", -1
for ($i = 0; $i -lt $coreLines.Count; $i++) {
    $esc = ConvertTo-EscapedLiteral $coreLines[$i]
    if ($i -eq 0) {
        $csSegments += ($indent + '"' + $esc + '\n"')
    }
    elseif ($i -eq $coreLines.Count - 1) {
        $csSegments += ($indent + '+ "' + $esc + '";')
    }
    else {
        $csSegments += ($indent + '+ "' + $esc + '\n"')
    }
}
# The FIRST segment must not carry a trailing \n when it is also the last.
if ($coreLines.Count -eq 1) { $csSegments = @($indent + '"' + (ConvertTo-EscapedLiteral $coreLines[0]) + '";') }

if ($doCs) {
$csText  = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($CsTarget)).Replace("`r`n", "`n")
$csLines = $csText -split "`n", -1
$csStart = -1
for ($i = 0; $i -lt $csLines.Count; $i++) {
    if ($csLines[$i] -match '^\s*public const string BaselineFloor\s*=\s*$') {
        if ($csStart -ge 0) { Fail "expected exactly ONE 'public const string BaselineFloor =' line in $CsTarget" }
        $csStart = $i
    }
}
if ($csStart -lt 0) { Fail "no 'public const string BaselineFloor =' anchor found in $CsTarget" }
# The literal ends at the first following line terminating in '";'.
$csEnd = -1
for ($i = $csStart + 1; $i -lt $csLines.Count; $i++) {
    if ($csLines[$i] -match '";\s*$') { $csEnd = $i; break }
}
if ($csEnd -lt 0) { Fail "could not find the end of the BaselineFloor literal in $CsTarget" }

$csOut += $csLines[0..$csStart]
$csOut += $csSegments
if ($csEnd + 1 -lt $csLines.Count) { $csOut += $csLines[($csEnd + 1)..($csLines.Count - 1)] }
}   # end if ($doCs)

# ONE LF-JOINED STRING, WRITTEN ONCE. Never an array - the array form joins with the platform newline.
if ($doRust) { [IO.File]::WriteAllText($RustTarget, ($rustLines -join "`n"), (New-Object Text.UTF8Encoding($false))) }
if ($doCs)   { [IO.File]::WriteAllText($CsTarget,   ($csOut     -join "`n"), (New-Object Text.UTF8Encoding($false))) }

Write-Host "generate-cheatsheet-literals: OK - regenerated both literals from $CoreSource" -ForegroundColor Green
exit 0
```

- [ ] **Step 4: Add the `just` recipe**

Insert after the `check-injected-context` recipe (`justfile:129-130`):

```
# Regenerate the two compiled-in cheatsheet literals from agy-autotrain/knowledge/driver-cheatsheet.core.md.
# core.md is the single source of truth; the two literals are GENERATED OUTPUT and must never be hand-edited.
# The pre-commit parity hook compares what is STAGED, so stage all three together.
gen-cheatsheet-literals:
    pwsh -NoProfile -File scripts/generate-cheatsheet-literals.ps1
```

- [ ] **Step 5: Add the script to `scripts/README.md`**

Required - `scripts/tests/scripts-readme-inventory.Tests.ps1:33` asserts every top-level script in
`scripts/` is named in that index, and it runs in the FAST partition. Add a row naming
`generate-cheatsheet-literals.ps1` in the same style as its neighbours.

- [ ] **Step 6: Register the new suite and run it**

Add `'scripts/tests/generate-cheatsheet-literals.Tests.ps1'` to the **`test-scripts-slow`** recipe in
`justfile`, and a row to `_partition.md`'s census table.

> **SLOW, and the first draft of this step said FAST - which contradicted the plan's own rule in three
> other places.** This suite is genuinely quick (a pure file transform, no `git` fixtures), and speed was
> the reason FAST looked right. But speed is not the binding constraint: the fast half is the agent
> inner-loop recipe and `_partition.md` measures it **cap-adjacent, not cap-safe**, against the 600s
> foreground cap - which is exactly why Task 3 and Task 13 both route their suites to SLOW and say so.
> Adding to FAST here while arguing the opposite twice elsewhere is the internal-inconsistency class this
> batch keeps paying for. **Four of this plan's five new suites now land in SLOW; none lands in FAST.**

```bash
pwsh -c "Invoke-Pester scripts/tests/generate-cheatsheet-literals.Tests.ps1 -Output Detailed -CI"
```

Expected: every row PASSES, **including the byte-for-byte control**. If the control fails, the generator
does not reproduce the current artifacts and NOTHING else about it can be trusted - fix that first.

- [ ] **Step 7: Prove the generator against the REAL oracle**

```bash
just gen-cheatsheet-literals
git diff --stat -- clavity-classic/src/driver_cheatsheet.rs clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs
```

Expected: **no diff at all** - the generator reproduces what is already committed. Then:

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~DriverCheatsheet" ; cd ..
cd clavity-classic && cargo test --all --features test-fakes driver_cheatsheet ; cd ..
```

Expected: both pinning tests GREEN. **Read the counts.** These two suites are the oracle the generator is
proven against and **must not be edited to match generator output.**

- [ ] **Step 8: Mutation control**

Delete the `$s.Replace("`r`n", "`n")` normalisation line and re-run - the CRLF fixture row must turn RED.
Restore. Then reorder the three escape lines to put the newline first - the backslash row must turn RED.
Restore.

- [ ] **Step 9: Commit**

```bash
git add scripts/generate-cheatsheet-literals.ps1 scripts/tests/generate-cheatsheet-literals.Tests.ps1 \
        justfile scripts/README.md scripts/tests/_partition.md
git commit -m "feat(cheatsheet): 14e - generate both literals from core.md"
```

---

## Task 11: Item 14e - the pre-commit parity hook

**Files:**
- Create: `scripts/check-cheatsheet-parity.ps1`
- Create: `scripts/tests/check-cheatsheet-parity.Tests.ps1`
- Modify: `lefthook.yml` (a new `pre-commit` command block)
- Modify: `scripts/tests/check-curate-in-progress.Tests.ps1:358` (**M4** - see below)
- Modify: `scripts/README.md`, `justfile`, `scripts/tests/_partition.md`

### M4 - the new lefthook block WILL red an existing row unless this task fixes it

`check-curate-in-progress.Tests.ps1:335-375` is a BEHAVIOURAL row: it copies the real `lefthook.yml`
(`:355`) into a fixture repo, copies **only** `check-curate-in-progress.ps1` into the fixture's
`scripts/` (`:358`), stages `clavity-classic/src/driver_cheatsheet.rs` (`:359`) - one of the three
globbed paths - and asserts `lefthook run pre-commit` exits **0** (`:367`).

A new block globbing the same three paths and running a script the fixture does not have would make
lefthook exit non-zero, turning `:367` RED. **Teach the fixture the new script in this task**, in the
same commit that adds the block.

### The hook's two obligations, and why each exists

1. **Assert the generator's EXIT STATUS first.** If the generator crashes, the working tree is untouched,
   so a bare `git diff --quiet` returns **0** and the hook PASSES - committing diverged literals with a
   green check. That ZERO means "nothing differed", which is indistinguishable from "nothing ran".
2. **Compare INDEX to INDEX, never HEAD, and never the worktree.** A pre-commit hook validates what is
   about to be COMMITTED. Comparing against HEAD would reject the correct workflow (edit `core.md`, run
   the task, stage all three). Reading the worktree would accept a stale stage.

**Both sides come from the index, extracted the SAME way.** Scoping raw-byte extraction to the
generator's input alone GUARANTEES a mismatch: parity compares the generated output against the STAGED
literals, which must also be read out of the index, and if that second extraction goes through ordinary
stdout capture it is re-encoded - measured, **Windows PowerShell 5.1's `>` produced 7032 bytes of UTF-16LE
where pwsh 7 produced 3508 byte-exact**. Two sides produced by different transports, compared exactly, is
a certainty of failure on the affected engine.

- [ ] **Step 1: Write the failing test suite**

Create `scripts/tests/check-cheatsheet-parity.Tests.ps1` with these rows. Each fixture is a throwaway
repo carrying copies of the three real files plus the generator.

| # | fixture state | asserts |
|---|---|---|
| 1 | generator exits non-zero | hook **FAILS** - it must not pass on an untouched tree |
| 2 | `core.md` staged, literals staged and correct | hook **PASSES** (the correct workflow is not blocked) |
| 3 | `core.md` staged complete + correct literals, THEN further unstaged edits to `core.md` | hook **PASSES** - and this is the END-TO-END PROOF that the hook reads the INDEX. **Mutation control: point the generator at the worktree instead of `git show :<path>` and this row must turn RED** |
| 4 | `core.md` staged, literals stale in the INDEX but correct in the WORKTREE | hook FAILS with **remedy 1** - "`git add` the two literals"; the message must **NOT** name the `just` task |
| 5 | `core.md` staged, literals stale in index AND worktree | hook FAILS with **remedy 2** - names the `just` task |
| 6 | partial stage (`core.md` hunks split), literals generated from the WORKTREE | hook FAILS **and the message says partial staging of `core.md` is unsupported**. Assert the TEXT |
| 7 | literals staged, `core.md` edited but NOT staged at all | hook FAILS with the "you staged the generated literals but not `core.md` itself" message - **not** the partial-staging one. Assert the TEXT: both branches fail, and only the text distinguishes a correct diagnosis from a misleading one |
| 8 | `core.md` deletion staged AND both literals' deletions staged | hook **PASSES**, naming the skip reason |
| 9 | `core.md` deletion staged, a literal still present | hook **FAILS**, naming the literal left behind |
| 10 | ONE literal's deletion staged (either) | hook **PASSES**, naming WHICH literal is being removed |
| 11 | one literal's deletion staged AND the OTHER literal DIVERGED | hook **FAILS** on the surviving literal. **This is the row that catches a per-run skip** - a blanket "any deletion means skip parity" passes here while certifying a diverged pin |
| **11a** | **BOTH literals' deletions staged while `core.md` is UNTOUCHED and present** | hook **PASSES**, naming that both literals are being removed. **Panel R9: the script carries a dedicated `if ($targets.Count -eq 0)` exit for this and no row reached it** - row 8 covers core.md-deleted-too and row 10 covers ONE literal, so this branch sat between them with no oracle. Retiring both pins while keeping their source is a legitimate decision |
| 12 | a fixture `core.md` containing a byte a pwsh text pipeline would alter | the hook's generated output reproduces that byte EXACTLY. Constructed in a throwaway repo, so the ASCII rule governing the real `core.md` does not constrain it |
| 13 | worktree `core.md` CRLF, index LF, literals correct | hook PASSES. **This row does NOT prove the hook reads the index** - it is a regression pin against CRLF breaking the run, nothing more |
| 14 | any exit path, including the failure paths | **no temp file survives the run** |
| 15 | hook run twice | working tree unchanged both times (it must never write in place) |

**Row 3 carries the mutation control that makes "reads the index" load-bearing rather than
belt-and-braces.** Row 13 cannot carry that claim: an index blob is already LF, so the worktree's line
endings are invisible to the hook and that row would pass even if the CRLF handling were entirely deleted.

- [ ] **Step 2: Run it to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-cheatsheet-parity.Tests.ps1 -Output Detailed -CI"
```

Expected: every row FAILS - the script does not exist.

- [ ] **Step 3: Write the hook script**

Create `scripts/check-cheatsheet-parity.ps1`. Structure, in order:

```powershell
#!/usr/bin/env pwsh
# Pre-commit parity gate for the three pinned cheatsheet paths (ROADMAP 14e).
#
# NON-DESTRUCTIVE: it generates to a TEMPORARY location and COMPARES. Writing into the working tree
# during a commit hands the author files they did not edit and can collide with work in progress.
# Repair is the author running `just gen-cheatsheet-literals` deliberately.
#
# IT COMPARES THE INDEX TO THE INDEX. Both the generator's INPUT and the literals it is compared
# against are read with `git show :<path>`, extracted the SAME way - see Get-IndexBytes below.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Core = 'agy-autotrain/knowledge/driver-cheatsheet.core.md'
$Rs   = 'clavity-classic/src/driver_cheatsheet.rs'
$Cs   = 'clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs'

# BYTE-EXACT INDEX EXTRACTION. `>` in PowerShell is NOT a byte redirect - it is Out-File, which decodes
# the stream and re-encodes it. Measured 2026-08-14 on `git show :<core.md>`: pwsh 7 produced 3508
# bytes byte-identical to the index blob, while Windows PowerShell 5.1 produced 7032 bytes - exactly
# double - as UTF-16LE. lefthook invokes this as `pwsh` today, so the shipped path is currently safe,
# which is exactly the kind of incidental safety this item refuses to rely on.
# EVERY temp path this hook creates is registered here as it is handed out, so the finally block at the
# very bottom can remove all of them on EVERY exit path. Panel R6 caught the first draft of this step
# calling New-TempPath four times and iterating $temps once while DEFINING NEITHER - under StrictMode
# that crashes on the first call, and the cleanup block would have thrown as well, stranding the temps it
# exists to remove. Declare them before any function that uses them.
$temps = New-Object System.Collections.ArrayList
function New-TempPath {
    param([string]$Suffix)
    $p = Join-Path ([IO.Path]::GetTempPath()) ('cheatsheet-parity-' + [guid]::NewGuid().ToString('N') + $Suffix)
    [void]$temps.Add($p)
    return $p
}

function Get-IndexBytes {
    param([string]$Path, [string]$OutFile)
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git'
    # `Arguments`, NOT `ArgumentList` - MEASURED, with a control: Windows PowerShell 5.1 (.NET Framework
    # 4.8) has NO ArgumentList property at all (`Get-Member ArgumentList` -> False; `Arguments` -> True),
    # while pwsh 7 has both. The ArgumentList form throws a runtime error on 5.1 - which would destroy
    # the exact cross-engine safety this function exists to provide. Neither path here contains a space,
    # but they are quoted anyway so a future path with one cannot break the split.
    $psi.Arguments = ('-C "{0}" show ":{1}"' -f $RepoRoot, $Path)
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $p = [Diagnostics.Process]::Start($psi)
    $fs = [IO.File]::Create($OutFile)
    try { $p.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Dispose() }
    $p.WaitForExit()
    return $p.ExitCode
}

function Test-InIndex {
    param([string]$Path)
    # $LASTEXITCODE is only meaningful if git actually RAN. With $ErrorActionPreference='Stop' a missing
    # git throws rather than leaving a stale code behind, but assert it explicitly rather than relying on
    # that: a stale exit code from the previous command would otherwise read as a confident answer.
    $global:LASTEXITCODE = $null
    & git -C $RepoRoot ls-files --error-unmatch -- $Path *> $null
    if ($null -eq $LASTEXITCODE) { throw "git did not run for ls-files on $Path" }
    return ($LASTEXITCODE -eq 0)
}
```

**The main body, in this order.** (An earlier draft of this step stopped at the two helpers above and
described steps 1-7 in prose only - which is a plan failure by this plan's own no-placeholders rule, and
the panel's Execution Realist seat named it as the one step that "cannot be performed as written, because
it isn't written".)

```powershell
# Fail REPORTS; it does not decide. Every call site below exits explicitly on the next line, so there is
# deliberately no accumulated $failed flag: a flag nothing reads implies a code path that does not exist,
# and the next reader would add one.
function Fail([string]$msg) { Write-Host "check-cheatsheet-parity: $msg" -ForegroundColor Red }

try {
    # ---- 1. PRESENCE, for ALL THREE, before extracting ANY of them. `git show :<path>` exits 128 with a
    # fatal: when a path's deletion is staged, and guarding only core.md leaves the identical crash on the
    # other side - the operator gets a raw fatal: and a rejected commit with no guidance at all.
    $coreIn = Test-InIndex $Core
    $rsIn   = Test-InIndex $Rs
    $csIn   = Test-InIndex $Cs

    if (-not $coreIn) {
        # The canonical source is going away. There is no parity to assert - but do NOT pass wholesale:
        # a surviving, possibly MUTATED, generated output would be certified on the way out.
        $left = @()
        if ($rsIn) { $left += $Rs }
        if ($csIn) { $left += $Cs }
        if ($left.Count -gt 0) {
            Fail ("$Core is being deleted, but its generated literal(s) are still present: " + ($left -join ', ') + ". Stage their deletion too, or restore $Core.")
            exit 1
        }
        Write-Host "check-cheatsheet-parity: OK - $Core and both generated literals are all being deleted; no parity to assert." -ForegroundColor Green
        exit 0
    }

    # ---- 2. PER-PATH skip, never per-run. A blanket "any deletion means skip" exits 0 while the OTHER
    # literal may have diverged - silently certifying it, which is exactly what 14e exists to prevent.
    $targets = @()
    if ($rsIn) { $targets += @{ Path = $Rs; Kind = 'rust' } } else { Write-Host "check-cheatsheet-parity: $Rs deletion is staged - skipping parity FOR THAT LITERAL ONLY." -ForegroundColor Yellow }
    if ($csIn) { $targets += @{ Path = $Cs; Kind = 'cs' }   } else { Write-Host "check-cheatsheet-parity: $Cs deletion is staged - skipping parity FOR THAT LITERAL ONLY." -ForegroundColor Yellow }
    if ($targets.Count -eq 0) { Write-Host "check-cheatsheet-parity: OK - both literals are being deleted." -ForegroundColor Green; exit 0 }

    # ---- 3. Extract BOTH SIDES from the index, the SAME way. Scoping byte-exact extraction to the
    # generator's INPUT alone guarantees a mismatch: the staged literals would come back re-encoded
    # (UTF-16LE under 5.1, measured) while the generated side is byte-exact, and parity is an EXACT
    # comparison.
    $coreTmp = New-TempPath '.md'
    if ((Get-IndexBytes $Core $coreTmp) -ne 0) { Fail "could not read $Core out of the index"; exit 1 }

    $stagedTmp = @{}
    foreach ($t in $targets) {
        $p = New-TempPath ('.staged.' + $t.Kind)
        if ((Get-IndexBytes $t.Path $p) -ne 0) { Fail ("could not read " + $t.Path + " out of the index"); exit 1 }
        $stagedTmp[$t.Path] = $p
    }

    # ---- 4. Generate into temp copies, then ASSERT THE GENERATOR'S EXIT STATUS FIRST. If the generator
    # crashes the tree is untouched, so any later "no difference" result means "nothing ran", not "nothing
    # differed" - a generator that failed to run is not evidence of parity.
    # ONLY SCAFFOLD THE TARGETS WE WILL ACTUALLY COMPARE. The generator SPLICES into an existing source
    # file, so it needs a copy to work on - but a literal whose deletion is staged is gone from the
    # worktree too, and an unconditional Copy-Item throws under $ErrorActionPreference='Stop'. That would
    # CRASH the hook on exactly the path test-table row 10 says must PASS. An empty target tells the
    # generator to skip that half (see Task 10).
    $genRs = ''; $genCs = ''
    if ($rsIn) { $genRs = New-TempPath '.gen.rs'; Copy-Item -LiteralPath (Join-Path $RepoRoot $Rs) -Destination $genRs }
    if ($csIn) { $genCs = New-TempPath '.gen.cs'; Copy-Item -LiteralPath (Join-Path $RepoRoot $Cs) -Destination $genCs }
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'generate-cheatsheet-literals.ps1') `
        -CoreSource $coreTmp -RustTarget $genRs -CsTarget $genCs *> $null
    if ($LASTEXITCODE -ne 0) { Fail "the generator exited $LASTEXITCODE - parity was NOT established (a generator that failed to run is not evidence of parity)."; exit 1 }
    $genFor = @{ $Rs = $genRs; $Cs = $genCs }

    # ---- 5. Compare generated bytes against the STAGED bytes, exactly.
    $mismatched = @()
    foreach ($t in $targets) {
        $a = [IO.File]::ReadAllBytes($genFor[$t.Path])
        $b = [IO.File]::ReadAllBytes($stagedTmp[$t.Path])
        if (-not [Linq.Enumerable]::SequenceEqual($a, $b)) { $mismatched += $t.Path }
    }

    # ---- 6. Agreement: PASS AND STOP, whatever the worktree looks like. This is the only thing the hook
    # is entitled to validate, and rejecting a correct commit because of unstaged work teaches --no-verify.
    if ($mismatched.Count -eq 0) { Write-Host "check-cheatsheet-parity: OK - the staged literals match the staged $Core." -ForegroundColor Green; exit 0 }

    # ---- 7. DIAGNOSIS ONLY FROM HERE, in the order 3, then 1, then 2. A partial stage also satisfies
    # case 1 or 2, so checking them in table order sends the user advice whose remedy fails again.
    & git -C $RepoRoot diff --quiet -- $Core          # worktree vs index, CRLF-agnostic. NEVER a byte compare.
    $coreDirty = ($LASTEXITCODE -ne 0)
    if ($coreDirty) {
        & git -C $RepoRoot diff --cached --quiet -- $Core
        $coreStaged = ($LASTEXITCODE -ne 0)
        if ($coreStaged) {
            Fail "partial staging of $Core is not supported. The literals are generated from the STAGED text and the just task reads the WORKTREE, so the two cannot agree. Stage $Core in full TOGETHER with the regenerated literals."
        } else {
            Fail "you staged the generated literals but not $Core itself. git add it."
        }
        exit 1
    }

    # Case 1 vs 2: is the generated output already sitting in the WORKTREE? This comparison is
    # temp-file-to-worktree, so no form of `git diff` can express it - normalise both sides and compare
    # the normalised TEXT, exactly as DriverCheatsheetTests.cs:92 already does.
    $worktreeMatches = $true
    foreach ($m in $mismatched) {
        $gen  = [IO.File]::ReadAllText($genFor[$m]).Replace("`r`n", "`n")
        $work = [IO.File]::ReadAllText((Join-Path $RepoRoot $m)).Replace("`r`n", "`n")
        if ($gen -ne $work) { $worktreeMatches = $false }
    }
    if ($worktreeMatches) {
        Fail ("regenerated output is already in your worktree - git add the literal(s): " + ($mismatched -join ', '))
    } else {
        Fail ("run 'just gen-cheatsheet-literals', then git add the literal(s): " + ($mismatched -join ', '))
    }
    exit 1
}
finally {
    # EVERY exit path, including the failure paths. A unique-per-invocation temp with no cleanup is
    # unbounded growth, and this hook runs on every commit that stages one of the three paths.
    foreach ($t in $temps) { Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue }
}
```

**Notes for the implementer, so the code above is not silently altered:**

1. **Presence check for ALL THREE paths, before extracting any of them.** Measured: `git show :<path>`
   exits **128** with a `fatal:` when a path's deletion is staged. Guarding only `core.md` leaves the
   identical crash on the other side - an operator staging the removal of `driver_cheatsheet.rs` gets an
   unhandled `fatal:` and a rejected commit with no guidance at all, strictly worse than a misleading
   message.
2. **If `core.md`'s deletion is staged:** assert **both** literals' deletions are staged too. Pass with a
   named skip reason if so; **FAIL naming any literal left behind** if not. A wholesale pass here
   certifies a surviving - possibly mutated - generated output on its way out.
3. **If a LITERAL's deletion is staged:** skip parity **FOR THAT LITERAL ONLY**, naming it. **"Skip" is
   per-path, never per-run.** A blanket skip when the `.rs` is deleted while the `.cs` has diverged exits
   0 and silently certifies the diverged survivor - the precise outcome 14e exists to prevent, reached
   through the guard added to make deletion survivable.
4. **Extract `core.md` from the index to a temp file, run the generator against temp copies of the
   literals, and ASSERT THE GENERATOR'S EXIT STATUS.** A non-zero generator exit FAILS the hook outright.
   Only after a zero exit does any diff carry information.
5. **Compare the generated bytes against the STAGED literal bytes, EXACTLY**, for each literal still
   present.
6. **If they agree: PASS AND STOP**, whatever the worktree looks like.
7. **Only on disagreement, run the diagnosis - in the order 3, then 1, then 2.** A partial stage also
   satisfies case 1 or 2, so a hook checking them in table order sends the user advice whose remedy
   fails again.

The three diagnosis messages. **This table specifies the required CONTENT, not the exact wording** - the
script body in Step 3 is the authority on the literal text. Panel R6 flagged the two as differing (the
script interpolates the full `$Core` path and says "literal(s)" where the table says "core.md" and "the
two literals"). **The bar is the SPEC's bar, and it is not weaker than the spec's:** `spec:953` says the failure message
is part of the contract *"because a wrong remedy is a trap"*, and the spec's own test row requires
asserting the text because *"only the text distinguishes a correct diagnosis from a misleading one"*.
**So each test asserts the DISTINGUISHING phrase of its row** - "partial staging", "but not ... itself",
"already in your worktree", "run `just`" - **which is exactly strong enough to tell the two branches
apart, and it must not be weakened below that.** What it does not do is pin a whole sentence: that
reddens on any reword and pushes an implementer to edit the message back instead of fixing a real
problem, which would defeat the rule rather than enforce it.

| # | detection | message |
|---|---|---|
| **3** first | `git diff --quiet -- <core.md>` is non-zero. **NEVER a byte comparison** - measured, worktree `core.md` is 3515 bytes and the index blob 3508 because `core.autocrlf` stores LF and checks out CRLF, so a naive byte check fires on EVERY commit. Then SPLIT on `git diff --cached --quiet -- <core.md>`: exit 0 means nothing was staged. | **staged:** "partial staging of `core.md` is not supported. The literals are generated from the STAGED text and the `just` task reads the WORKTREE, so the two cannot agree. Stage `core.md` in full **together with the regenerated literals**." **Never advise committing `core.md` on its own** - parity is evaluated first, so that commit is rejected anyway. **not staged:** "you staged the generated literals but not `core.md` itself. `git add` it." |
| 1 | generated output equals the literal as it sits in the WORKTREE. **Temp-file-to-worktree, so `git diff` cannot make this comparison** - normalise both sides CRLF->LF and compare the normalised text, exactly as `DriverCheatsheetTests.cs:92` already does | "regenerated output is already in your worktree - **`git add` the two literals**" (running the task again changes nothing) |
| 2 | worktree literals also stale | "**run `just gen-cheatsheet-literals`, then `git add` the two literals**" |

8. **Remove every temp file on EVERY exit path**, including the failure paths - use `try/finally`.

- [ ] **Step 4: Add the lefthook block**

Append a new command under `pre-commit` in `lefthook.yml`, after the `curate-in-progress` block:

```yaml
    cheatsheet-parity:
      # ROADMAP 14e: the three pinned paths must agree, and agreement is now STRUCTURAL - the two
      # literals are GENERATED from core.md. This compares what is STAGED against freshly generated
      # output, never the worktree, and never writes in place.
      #
      # SAME GLOB AS curate-in-progress, and for the same cost reason: pwsh cold start is ~6s, far too
      # much on every commit, so lefthook invokes this ONLY when one of the three paths is staged.
      glob:
        - "agy-autotrain/knowledge/driver-cheatsheet.core.md"
        - "clavity-classic/src/driver_cheatsheet.rs"
        - "clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs"
      run: pwsh -NoProfile -File scripts/check-cheatsheet-parity.ps1
```

- [ ] **Step 5: M4 - teach the existing fixture the new script**

In `scripts/tests/check-curate-in-progress.Tests.ps1`, immediately after `:358`, add:

```powershell
        # The fixture runs the REAL lefthook.yml, which now carries a second pre-commit command
        # (cheatsheet-parity, ROADMAP 14e) globbing the same three paths this fixture stages. Without
        # its script present, lefthook fails for a reason that has nothing to do with this suite and
        # the control row below - which asserts exit 0 - goes red.
        # A STUB, NOT THE REAL SCRIPT - and panel R4 caught why copying the real one does not work.
        # This fixture stages clavity-classic/src/driver_cheatsheet.rs (:359) and contains NO core.md at
        # all. The real parity hook would find a literal present in the index with no canonical source,
        # which by Task 11's own rules is the "source gone, literal left behind" case and exits non-zero -
        # so lefthook fails and the control row below (`Should -Be 0`) goes RED. Copying the real script
        # trades one failure for another.
        #
        # A stub is the CORRECT isolation here, not a dodge: this row's claim is that lefthook invokes
        # THE CURATE GUARD and propagates ITS refusal. Any other pre-commit command is noise for that
        # claim, and the parity hook's real behaviour is covered by its own suite in Task 11 - which is
        # where a wiring break in it must be caught, not here.
        Set-Content -LiteralPath (Join-Path $fixtureScripts 'check-cheatsheet-parity.ps1') -Value 'exit 0'
```

- [ ] **Step 6: Run BOTH suites**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-cheatsheet-parity.Tests.ps1 -Output Detailed -CI"
pwsh -c "Invoke-Pester scripts/tests/check-curate-in-progress.Tests.ps1 -Output Detailed -CI"
```

Expected: both fully green. **The second one is the M4 regression check** - if `:367` is red, the fixture
fix did not take. Never run them concurrently (file-lock false red).

- [ ] **Step 7: Mutation controls**

| mutation | row that must turn RED |
|---|---|
| point the generator at the worktree instead of `git show :<path>` | row 3 |
| neuter the generator exit-status assertion | row 1 |
| make the deletion skip per-RUN instead of per-PATH | row 11 |
| guard only `core.md`'s presence, not the literals' | row 10 |
| pass `core.md` deletion wholesale without checking the literals | row 9 |
| evaluate diagnosis case 3 BEFORE parity | row 3 (a correct commit gets rejected) |
| use a byte comparison for case-3 detection instead of `git diff --quiet` | rows 2 and 3 (fires on every commit) |
| drop the split on `git diff --cached --quiet` | row 7 (wrong message) |
| feed the index through a text pipeline instead of `BaseStream` | row 12 |

- [ ] **Step 8: Register, index, commit**

Add the suite to the `test-scripts-slow` recipe in `justfile` (SLOW - it builds many git fixtures), add a `_partition.md` row, and add
`check-cheatsheet-parity.ps1` to `scripts/README.md`.

```bash
git add scripts/check-cheatsheet-parity.ps1 scripts/tests/check-cheatsheet-parity.Tests.ps1 \
        scripts/tests/check-curate-in-progress.Tests.ps1 lefthook.yml justfile \
        scripts/README.md scripts/tests/_partition.md
git commit -m "feat(cheatsheet): 14e - pre-commit parity gate comparing INDEX to INDEX"
```

---

## Task 12: Item 14e - the `agy-curate/SKILL.md` companion change

Generation makes an existing instruction wrong. **Shipping one without the other is an incomplete fold.**

**Files:** Modify `agy-autotrain/skills/agy-curate/SKILL.md` at `:122-126` and `:339`.

**This is a SINGLE copy - measured, not a byte-identical pair - so there is no mirror cost.**

**Verified current state:**

- `:122` - `**[!] THREE files are pinned byte-identical - editing `driver-cheatsheet.core.md` alone RED-GATES both binaries.**`
- `:124` - `If you change `driver-cheatsheet.core.md` you MUST also update:` followed by `:125-126` naming the two literals
- `:112` - `keep it in sync there` (**unchanged** - `core.md` remains the canonical text and is now the ONLY hand-edited one)
- `:339` - documents `core.md` "and its two byte-identical pins may have been edited" as expected uncommitted state

- [ ] **Step 1: Replace `:122-126`**

**Write in the THIRD PERSON.** `SKILL.md` is the CURATOR's document, so "edit `core.md`, then run the
generator" tells the curator it may edit that file - which is precisely what ROADMAP 14f leaves open. The
mechanical instruction is what changes; **who is entitled to trigger it is not this batch's to say.**

```markdown
**[!] The two compiled-in pins are GENERATED OUTPUT and must never be hand-edited.** A pinning test in
each driver asserts its compiled-in baseline equals `driver-cheatsheet.core.md` (normalized CRLF->LF,
then trimmed), and a pre-commit hook now compares what is STAGED against freshly generated output.
Whoever edits `driver-cheatsheet.core.md` runs `just gen-cheatsheet-literals` and stages **all three
files together** - the hook compares the staged content, so staging the source without its regenerated
outputs is rejected, and so is hand-editing an output.
- generated: `clavity-classic/src/driver_cheatsheet.rs` -> `BASELINE_FLOOR` (single-line `\n` literal)
- generated: `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` -> `BaselineFloor` (multi-line `+ "...\n"` concatenation)
```

Leave `:128-130`'s oracle list intact - those commands still apply.

- [ ] **Step 2: Amend `:339`**

Replace "and its two byte-identical pins may have been edited" with
"and its two GENERATED pins may have been regenerated". Still true; the pins are now generated output
rather than hand-edits.

- [ ] **Step 3: Do NOT widen this into the ownership question**

Confirm by reading the diff that no sentence added here states whether the curator may edit `core.md`.
That is tracked as ROADMAP 14f and needs an owner ruling. This change is decision-free: *given* that
someone edits `core.md`, they must run the generator instead of hand-editing two literals - and that holds
under either resolution.

- [ ] **Step 4: Gates**

`agy-autotrain` is in `$DomainRoots`, and this file is named in `ci-scripts.yml:49` and `:57`'s `paths:`
filters, so it is CI-visible.

```bash
just check-injected-context
pwsh -c "Invoke-Pester scripts/tests/check-curate-in-progress.Tests.ps1 -Output Detailed -CI"
```

- [ ] **Step 5: Commit**

```bash
git add agy-autotrain/skills/agy-curate/SKILL.md
git commit -m "docs(curate): 14e - the two pins are generated output, not hand-edits"
```

---
## Task 13: Item 14b - register the orphan suite (THREE parts)

`clavity-dotnet/install/clavity-install.Tests.ps1` runs in no gate at all. **Shipping any subset of the
three parts below leaves the item's own premise true.**

**Files:**
- Modify: the `test-scripts-slow` recipe in `justfile` (SLOW partition) and `scripts/tests/_partition.md`
- Modify: `.github/workflows/ci-scripts.yml` - both `paths:` lists AND both jobs
- Modify: `scripts/tests/test-suite-registration.Tests.ps1` (a narrow pin, NOT a widening)

**Verified:** the suite passes **12/0** under pwsh 7 (4.77s) and **12/0** under Windows PowerShell 5.1
(6.49s). It is a pure unit suite - it mocks, dot-sources the installer so `main` never runs, and makes no
mutating calls. **It is registered as-is; a registered-but-SKIPPED suite is a guard that fails open.**

- [ ] **Step 1: Part 1 - the `paths:` filter, in BOTH lists**

This is not optional; it is the workflow's own written rule at `:21-25`: *"EVERY FILE THE SCRIPTS SUITE
READS AND ASSERTS AGAINST MUST APPEAR BELOW."* `:32` records this precise omission happening once
already, *"MISSED when the first was added, in the very commit that added the row reading it."*

Add `- 'clavity-dotnet/install/**'` to the `push` list (after `:46`) **and** to the `pull_request` list
(after `:54`). **Both.** Verify afterwards:

```bash
grep -c "clavity-dotnet/install/\*\*" .github/workflows/ci-scripts.yml
```

Expected: **2**. A count of 1 means one list was missed - the exact `:32` failure.

- [ ] **Step 2: Part 2 - the engine, in BOTH jobs, and it is NOT symmetrical**

`:15` records the precedent: *"register-plugin.Tests.ps1 runs in BOTH jobs on purpose: it must hold under
either engine."* The suite was measured 12/0 under both, so that precedent applies exactly.

**The two jobs invoke Pester differently, and reading "run it in both" as symmetrical silently skips one:**

- `installer-5-1` names a specific FILE (`:93`, `Invoke-Pester scripts/tests/register-plugin.Tests.ps1`).
  **Add a NEW step rather than extending `:93`** - that step's own assertion at `:99`
  (`if ($r.TotalCount -lt 15)`) is calibrated to the register-plugin suite alone, and folding a second
  suite into the same invocation would silently redefine what that floor means.
- `dev-scripts` **SWEEPS A DIRECTORY** (`:155`, `Invoke-Pester scripts/tests`), and the orphan suite lives
  in `clavity-dotnet/install/`, which that sweep will never reach. **So the pwsh 7 half needs a NEW
  explicit step too; assuming the sweep covers it produces a green job that ran nothing** - the same shape
  as the defect 14b exists to fix, one level up.

Add to `installer-5-1`, after the step ending at `:99`:

```yaml
      - name: Pester - clavity-install (Windows PowerShell 5.1)
        shell: powershell
        # The installer runs on an END-USER Windows box where only 5.1 is guaranteed, so its suite must
        # hold under that engine - the same reasoning as register-plugin above (:15). Measured
        # 2026-08-14: Passed 12, Failed 0 under 5.1 (6.49s) and under pwsh 7 (4.77s).
        # A SEPARATE STEP, not folded into the register-plugin invocation above, whose TotalCount floor
        # is calibrated to that suite alone.
        run: |
          Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force
          $r = Invoke-Pester clavity-dotnet/install/clavity-install.Tests.ps1 -Output Detailed -PassThru
          if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) Pester test(s) failed" }
          $bad = @($r.Containers | Where-Object { $_.Result -ne 'Passed' })
          if ($bad.Count -gt 0) { throw "$($bad.Count) container(s) failed to run or discover" }
          if ($r.TotalCount -lt 12) { throw "only $($r.TotalCount) tests discovered - expected the clavity-install suite (>=12)" }
```

Add to `dev-scripts`, after the step ending at `:159`:

```yaml
      - name: Pester - clavity-install (pwsh 7)
        shell: pwsh
        # NOT covered by the directory sweep above: that runs `Invoke-Pester scripts/tests` and this
        # suite lives in clavity-dotnet/install/. Assuming the sweep reaches it produces a green job
        # that ran nothing.
        run: |
          Import-Module Pester -MinimumVersion 5.0.0 -MaximumVersion 5.99.99 -Force
          $r = Invoke-Pester clavity-dotnet/install/clavity-install.Tests.ps1 -Output Detailed -PassThru
          if ($r.FailedCount -gt 0) { throw "$($r.FailedCount) Pester test(s) failed" }
          $bad = @($r.Containers | Where-Object { $_.Result -ne 'Passed' })
          if ($bad.Count -gt 0) { throw "$($bad.Count) container(s) failed to run or discover" }
          if ($r.TotalCount -lt 12) { throw "only $($r.TotalCount) tests discovered - expected the clavity-install suite (>=12)" }
```

**Every `run:` block above is deliberately pure ASCII** (`ci-scripts.yml:17-19`: Actions writes a run block
to a BOM-less temp `.ps1`).

- [ ] **Step 3: Part 3 - the `justfile` registration, in the SLOW partition**

Registration is an EXPLICIT LIST, not a glob. Add
`'clavity-dotnet/install/clavity-install.Tests.ps1'` to the array in the `test-scripts-slow` recipe in `justfile`.

**It goes SLOW, and the reasoning is on the record.** The fast half is the agent inner-loop recipe and
`scripts/tests/_partition.md` is explicit that it is **cap-adjacent, not cap-safe** against the 600s
foreground cap. The suite costs 4.77s under pwsh 7 - small, but spent on every inner-loop run to gate an
INSTALLER, which is not code the agent loop edits. The slow half is already backgrounded and well past the
foreground cap, so it absorbs this at no cost to the loop.

- [ ] **Step 4: MEASURE the slow partition WITH the suite added - do not assume**

**Backgrounded, blocking on its own `Tests completed` line, never on a process count.** A partition figure
that is asserted rather than measured is exactly what `_partition.md` forbids.

```bash
pwsh -c "just test-scripts-slow" > /tmp/slow-run.log 2>&1
```

Run this in the BACKGROUND. When it finishes, read the log:

```bash
grep -E "Tests Passed:|Tests completed" /tmp/slow-run.log
```

**A log with no `Tests Passed:` line is an ABORTED run, not a pass.** Record the wall-clock and the counts,
and write the measured figure into `_partition.md`'s slow-half entry.

- [ ] **Step 5: Add the narrow registration pin - do NOT widen the guard**

`test-suite-registration.Tests.ps1:52` matches only `scripts/tests/<name>.Tests.ps1`, so an entry naming a
path outside that directory is invisible to every row in that file: neither certified nor rejected. The
file's own header at `:3-6` says the scope is deliberate and that *"widening the scope is a decision about
other products' suites, not a fold."*

**So add a narrow pin instead**, in `scripts/tests/test-suite-registration.Tests.ps1`:

```powershell
    It 'registers the clavity-install suite by PATH, and that path exists' {
        # NARROW BY DESIGN. The parses above are scoped to scripts/tests/ (see the header at :3-6), so
        # this out-of-tree suite is invisible to them - neither certified nor rejected. Widening
        # Get-RecipeSuites would be a decision about other products' suites, not a fold, so this row
        # pins the one entry instead.
        #
        # BOTH HALVES ARE LOAD-BEARING: without the first, the row passes when the entry is deleted;
        # without the second, it passes when the file is renamed.
        $rel = 'clavity-dotnet/install/clavity-install.Tests.ps1'
        $script:Justfile | Should -Match ([regex]::Escape($rel)) -Because 'the suite ran in no gate at all until it was named in a recipe (ROADMAP 14b)'
        Test-Path -LiteralPath (Join-Path $script:RepoRoot $rel) | Should -BeTrue -Because 'a recipe naming a file that does not exist silently shrinks the gate'
    }
```

- [ ] **Step 6: Verify - run the suite, the guard, and the registration pin**

```bash
pwsh -c "Invoke-Pester clavity-dotnet/install/clavity-install.Tests.ps1 -Output Detailed -CI"
pwsh -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed -CI"
```

Expected: **Passed 12, Failed 0** from the first; all green from the second, including the new row.

- [ ] **Step 7: Mutation control**

Delete the `clavity-dotnet/install/...` entry from the `test-scripts-slow` recipe in `justfile` - the new pin's FIRST assertion must turn
RED. Restore it, then temporarily rename the suite file - the SECOND assertion must turn RED. Restore.

- [ ] **Step 8: Check the YAML by READING - it cannot be exercised before merge**

Nothing is pushed, so CI cannot run. Verify by inspection:

```bash
pwsh -c "if (Get-Command yq -EA SilentlyContinue) { yq '.jobs | keys' .github/workflows/ci-scripts.yml } else { 'yq not present - read the file' }"
grep -n "clavity-install" .github/workflows/ci-scripts.yml
```

Expected: **two** `Pester - clavity-install` step names (one per job), and the two `paths:` entries from
Step 1. Confirm indentation matches the sibling steps exactly.

- [ ] **Step 9: Commit**

```bash
git add justfile .github/workflows/ci-scripts.yml scripts/tests/test-suite-registration.Tests.ps1 scripts/tests/_partition.md
git commit -m "fix(ci): 14b - register the orphan installer suite locally and in both CI jobs"
```

---

## Task 14: Item 13a - replace the false promise

**Files:**
- Modify: `scripts/check-injected-context.ps1:932`
- Test: `scripts/tests/check-injected-context.Tests.ps1`

**Verified current state.** `:932` prints:

> `an exemption whose file stops failing its invariant is reported as unused and must be deleted.`

and `unused` occurs **exactly once** in the whole script - inside that message. The gate has no
unused-exemption reporting at all. But the condition IS caught, by
`scripts/tests/check-injected-context.Tests.ps1:666`:

> `It 'every exemption is still NEEDED - the file must fail the invariant without it'`

**REPLACE, do not delete.** Deleting removes true information along with the false claim - an operator
still needs to know a stale exemption is caught. **And the replacement must say the suite FAILS, not that
it "reports"**: it fails a test; it does not emit a report. Saying "reports" substitutes one loose promise
for another.

- [ ] **Step 1: Write the failing test - and note the OBVIOUS test is VACUOUS**

The message lives inside the violations block: `:920` opens with `"$($v.Count) violation(s)"` and `:934`
is `exit 1`. **It is printed ONLY when there is at least one violation.** So a test that runs the gate
over a clean tree and asserts "the output does not contain the false claim" **passes against ANY
implementation** - the string never appears on that path, whether or not it was ever fixed. The setup must
PRODUCE a violation.

```powershell
    Context '13a - the guidance names where stale-exemption detection actually lives' {
        BeforeAll {
            # THE BLOCK IS UNREACHABLE WITHOUT A VIOLATION. A clean-tree run prints none of this text,
            # so an assertion against a clean run passes against every implementation including the
            # unfixed one.
            $script:Fx = Join-Path ([IO.Path]::GetTempPath()) ("ctx13a-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path (Join-Path $script:Fx 'seed') | Out-Null
            # A non-ASCII byte inside a governed root is the cheapest reliable violation.
            [IO.File]::WriteAllBytes((Join-Path $script:Fx 'seed/bad.md'), [byte[]](0x41,0xE2,0x80,0x94,0x42,0x0A))
            $script:Out = & pwsh -NoProfile -File (Join-Path $script:RepoRoot 'scripts/check-injected-context.ps1') -RepoRoot $script:Fx 2>&1 | Out-String
            $script:Rc = $LASTEXITCODE
        }
        AfterAll { Remove-Item -LiteralPath $script:Fx -Recurse -Force -ErrorAction SilentlyContinue }

        It 'the setup actually produced a violation (without this the rows below are vacuous)' {
            $script:Out | Should -Match 'violation\(s\)'
        }
        It 'does NOT repeat the old false claim' {
            $script:Out | Should -Not -Match 'reported as unused'
        }
        It 'names the TEST SUITE as the enforcement point, and says it FAILS' {
            $script:Out | Should -Match 'every exemption is still NEEDED'
            $script:Out | Should -Match '(?i)fail'
        }
        It 'still exits 1 - this item changes TEXT, not behaviour' {
            $script:Rc | Should -Be 1
        }
    }
```

- [ ] **Step 2: Run it to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"
```

Expected: `does NOT repeat the old false claim` and `names the TEST SUITE` FAIL; the vacuity guard and the
exit-code row PASS.

- [ ] **Step 3: Replace the message at `:932`**

```powershell
    Write-Host "an exemption whose file stops failing its invariant is no longer needed. This gate does not"
    Write-Host "detect that - the test suite does, by FAILING 'every exemption is still NEEDED'."
```

Two properties are required of whatever wording lands: it states that **THIS gate does not detect** the
condition, and it **names where the detection actually lives**. A sentence that only deletes the false
claim satisfies neither.

- [ ] **Step 4: Run it to verify it PASSES**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-injected-context.Tests.ps1 -Output Detailed -CI"
just check-injected-context
```

Expected: all rows green; the gate itself still reports `OK` over the real tree.

- [ ] **Step 5: Mutation control**

Revert the message to its old wording - `does NOT repeat the old false claim` must turn RED. Restore.

- [ ] **Step 6: Commit**

```bash
git add scripts/check-injected-context.ps1 scripts/tests/check-injected-context.Tests.ps1
git commit -m "fix(gate): 13a - the guidance names the suite that actually catches a stale exemption"
```

> **Known residual, recorded rather than discovered later.** The replacement sentence lives inside the
> violations block, which prints only when there is at least one violation. **A stale exemption produces
> ZERO violations** - that is precisely what "the file stopped failing its invariant" means - so the
> guidance is never shown at the moment a stale exemption exists. This item corrects a false claim; it
> does not make the guidance reachable at the time of the fault, and it cannot, because reaching it would
> require the detection 13a explicitly declines to build.

---

## Task 15: Item 13c - name which input is missing

**Files:**
- Modify: `scripts/check-growth-budget.ps1:30-31`
- Modify: `scripts/drain-knowledge.ps1:145-147`
- Test: `scripts/tests/check-growth-budget.Tests.ps1` and `scripts/tests/drain-knowledge.Tests.ps1`

**Verified current state.** `Get-RawBytes` (`:23-28`) returns `0` for a missing path (`:26`) **and** `0`
for a present-but-empty one, so a caller handed `0` cannot tell them apart. It has **two** call sites:
`:30` (SEED) and `:31` (GROWTH). **They are NOT the same case:**

| call site | absence is | disposition |
|---|---|---|
| GROWTH (`:31`) | legitimate - a docs-only drain has nothing to publish | distinct message, **exit 0** |
| SEED (`:30`) | never legitimate while a budget check is meaningful | distinct message, **exit NON-ZERO** |

**Why the seed case is worse than a bad message.** With the seed measured at 0, `:36` sets no separator,
`:37` makes `$combined` 0, `:39` compares `0 -gt 16384`, and `:44` prints
`check-growth-budget: OK - SEED (0B) + GROWTH (0B) = 0B <= 16384B` and exits 0. **The gate reports a clean
pass having measured nothing**, and certifies a GROWTH proposal of up to the FULL cap. The binary then
combines the REAL seed with that proposal, overflows, and silently drops GROWTH - the exact failure this
gate exists to prevent.

> **REFUTED at re-panel round 5, and the refuted sentence was the spec's own.** The claim that a non-zero
> exit "would break the drain" is false: `drain-knowledge.ps1:145-147` tests `if ($LASTEXITCODE -ne 0)`,
> prints a warning, and **continues**. The drain is already built to absorb a non-zero exit - that is what
> warn-only means. `:144` is the only production caller and no CI workflow invokes the script.

**The MECHANISM: the call sites test `Test-Path` themselves; `Get-RawBytes` is left alone.** Changing it
to return `-1` or `$null` would push a sentinel into the arithmetic at `:36-37`, where `$seedBytes -gt 0`
and the addition both silently accept it; changing it to throw would turn a WARN-only gate into a crashing
one.

- [ ] **Step 1: Write the failing tests on the GATE's suite**

Add to `scripts/tests/check-growth-budget.Tests.ps1`. **The exit codes now DIFFER by call site, so a row
asserting "0 everywhere" would contradict the table above.**

| state | message asserts | exit |
|---|---|---|
| GROWTH missing | names it as **absent**, not empty | 0 |
| GROWTH present but empty | names it as **empty**, not absent | 0 |
| SEED missing | names the **missing seed**, never an overflow | non-zero |
| SEED present but empty | names it as **empty** | non-zero |
| both present, over cap | the existing overflow message | non-zero (unchanged) |
| both present, under cap | the existing OK line | 0 (unchanged) |

```powershell
    Context '13c - a missing input is distinguishable from an empty one' {
        BeforeAll {
            function New-BudgetFixture {
                param([switch]$NoSeed, [switch]$EmptySeed, [switch]$NoGrowth, [switch]$EmptyGrowth, [int]$GrowthBytes = 100)
                $d = Join-Path ([IO.Path]::GetTempPath()) ("gb-" + [guid]::NewGuid().ToString('N'))
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'seed') | Out-Null
                New-Item -ItemType Directory -Force -Path (Join-Path $d 'docs') | Out-Null
                if (-not $NoSeed)   { [IO.File]::WriteAllText((Join-Path $d 'seed/golden-header.md'), ($EmptySeed ? '' : ('s' * 200))) }
                if (-not $NoGrowth) { [IO.File]::WriteAllText((Join-Path $d 'docs/agy-golden-header.growth.md'), ($EmptyGrowth ? '' : ('g' * $GrowthBytes))) }
                $d
            }
            function Invoke-Budget {
                param([string]$Root, [int]$MaxBytes = 16384)
                $out = & pwsh -NoProfile -File (Join-Path $script:RepoRoot 'scripts/check-growth-budget.ps1') -RepoRoot $Root -MaxBytes $MaxBytes 2>&1 | Out-String
                [pscustomobject]@{ Out = $out; Rc = $LASTEXITCODE }
            }
        }

        It 'GROWTH missing: names it ABSENT, not empty, and exits 0' {
            $r = Invoke-Budget (New-BudgetFixture -NoGrowth)
            $r.Out | Should -Match '(?i)absent|missing|not present'
            $r.Out | Should -Not -Match '(?i)\bempty\b'
            $r.Rc  | Should -Be 0 -Because 'a docs-only drain legitimately has nothing to publish'
        }
        It 'GROWTH present but EMPTY: names it EMPTY, not absent, and exits 0' {
            $r = Invoke-Budget (New-BudgetFixture -EmptyGrowth)
            $r.Out | Should -Match '(?i)\bempty\b'
            $r.Out | Should -Not -Match '(?i)absent|missing'
            $r.Rc  | Should -Be 0
        }
        It 'SEED missing: names the MISSING SEED, never an overflow, and exits NON-ZERO' {
            # The fail-open this item's anomaly never looked at: 0 + 16384 <= 16384 certifies a
            # full-cap proposal, the binary then combines the REAL seed, overflows, and drops GROWTH.
            $r = Invoke-Budget (New-BudgetFixture -NoSeed)
            $r.Out | Should -Match '(?i)seed'
            $r.Out | Should -Not -Match '(?i)exceeds|> '
            $r.Rc  | Should -Not -Be 0
        }
        It 'SEED present but EMPTY: names it EMPTY and exits NON-ZERO' {
            $r = Invoke-Budget (New-BudgetFixture -EmptySeed)
            $r.Out | Should -Match '(?i)\bempty\b'
            $r.Rc  | Should -Not -Be 0
        }
        It 'SEED over the cap with GROWTH ABSENT: still FAILS (panel R4 - the early-return fail-open)' {
            # THE ROW THAT CATCHES 13c's OWN REGRESSION. The first draft returned 0 here while printing
            # "SEED <n>B <= <cap>B" without testing it. The ORIGINAL code had no such hole: with GROWTH
            # absent the separator is 0 and $combined is just $seedBytes, so the cap comparison still ran.
            # Without this row, an early return for the legitimate GROWTH-absent case silently deletes the
            # only check an oversized seed would ever fail - and prints a false statement in green.
            $r = Invoke-Budget (New-BudgetFixture -NoGrowth) -MaxBytes 50   # seed fixture is 200B
            $r.Rc  | Should -Not -Be 0 -Because 'a seed over the cap on its own must never pass, GROWTH present or not'
            $r.Out | Should -Not -Match '(?i)\bOK\b'
        }
        It 'SEED over the cap with GROWTH EMPTY: still FAILS' {
            $r = Invoke-Budget (New-BudgetFixture -EmptyGrowth) -MaxBytes 50
            $r.Rc | Should -Not -Be 0
        }
        It 'both present, over cap: the EXISTING overflow message, non-zero (unchanged)' {
            $r = Invoke-Budget (New-BudgetFixture -GrowthBytes 500) -MaxBytes 300
            $r.Out | Should -Match '(?i)exceeds|FAIL'
            $r.Rc  | Should -Not -Be 0
        }
        It 'both present, under cap: the EXISTING OK line, exit 0 (unchanged)' {
            $r = Invoke-Budget (New-BudgetFixture)
            $r.Out | Should -Match 'check-growth-budget: OK'
            $r.Rc  | Should -Be 0
        }
    }
```

- [ ] **Step 2: Run to verify it FAILS**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-growth-budget.Tests.ps1 -Output Detailed -CI"
```

Expected: the four new distinguishing rows FAIL; the two "unchanged" rows PASS.

- [ ] **Step 3: Edit the gate - test presence at the CALL SITES, leave `Get-RawBytes` alone**

Replace `:30-31` and add the two checks before the arithmetic:

```powershell
$seedPath   = Join-Path $RepoRoot 'seed/golden-header.md'
$growthPath = Join-Path $RepoRoot 'docs/agy-golden-header.growth.md'

# TEST PRESENCE AT THE CALL SITE. Get-RawBytes returns 0 for a missing path (:26) AND 0 for a
# present-but-empty one, so a caller handed 0 cannot tell them apart - the distinction is already
# destroyed by the time it returns. Changing its signature is worse: -1 or $null would flow into the
# arithmetic below, where `-gt 0` and the addition both silently accept a sentinel, and throwing would
# turn a WARN-only gate into a crashing one.
$seedMissing   = -not (Test-Path -LiteralPath $seedPath)
$growthMissing = -not (Test-Path -LiteralPath $growthPath)

$seedBytes   = Get-RawBytes $seedPath
$growthBytes = Get-RawBytes $growthPath

# THE SEED CASE IS A REAL FAIL-OPEN, NOT A REPORTING DEFECT. A missing seed silently measures 0, so
# `0 + <proposal> <= 16384` certifies a proposal of up to the FULL cap; the binary then combines the
# REAL seed with it, overflows, and silently drops GROWTH - the exact failure this gate exists to
# prevent. The gate does not merely report badly; it validates a falsified equation and returns green.
if ($seedMissing) {
    Write-Host "check-growth-budget: FAIL: the SEED is ABSENT at $seedPath - the combined budget cannot be checked at all. This is NOT an overflow: nothing was measured. Restore the seed, then re-run." -ForegroundColor Red
    exit 1
}
if ($seedBytes -eq 0) {
    Write-Host "check-growth-budget: FAIL: the SEED at $seedPath is present but EMPTY (0 bytes) - the combined budget cannot be checked meaningfully. This is NOT an overflow." -ForegroundColor Red
    exit 1
}

# THE SEED MUST STILL BE CHECKED AGAINST THE CAP BEFORE ANY EARLY RETURN. Panel R4 caught this as a
# FAIL-OPEN INTRODUCED BY 13c'S OWN FIX: the first draft of these two branches printed
# "SEED ${seedBytes}B <= ${MaxBytes}B" and exited 0 WITHOUT EVER TESTING THAT CLAIM. The original code
# had no such hole - with GROWTH absent, `$separator` is 0 and `$combined` is just `$seedBytes`, so `:39`
# still compared it to the cap. Adding an early return for the legitimate GROWTH-absent case silently
# deleted the only check that a seed OVER the cap on its own would ever fail, and printed a
# mathematically false sentence in green while doing it. A reporting fix that removes an assertion is not
# a reporting fix.
if ($seedBytes -gt $MaxBytes) {
    Write-Host "check-growth-budget: FAIL: SEED (${seedBytes}B) alone exceeds ${MaxBytes}B, before any GROWTH is added." -ForegroundColor Red
    exit 1
}

# For GROWTH, ABSENCE IS LEGITIMATE - a docs-only drain has nothing to publish - so this half is a
# reporting fix and stays exit 0. Safe to return here ONLY because the seed was just checked above.
if ($growthMissing) {
    Write-Host "check-growth-budget: OK - the GROWTH proposal is ABSENT at $growthPath (a docs-only drain publishes nothing). SEED ${seedBytes}B <= ${MaxBytes}B." -ForegroundColor Green
    exit 0
}
if ($growthBytes -eq 0) {
    Write-Host "check-growth-budget: OK - the GROWTH proposal at $growthPath is present but EMPTY (0 bytes). SEED ${seedBytes}B <= ${MaxBytes}B." -ForegroundColor Green
    exit 0
}
```

Leave `:36-45` (the separator, the combined arithmetic, the overflow branch and the OK line) unchanged.

- [ ] **Step 4: Part two - the CALLER must stop asserting a cause it has not established**

**Without this, part one produces a confidently wrong diagnosis.** `drain-knowledge.ps1:146` prints a
single hardcoded warning for ANY non-zero: *"SEED + GROWTH exceeds the 16 KiB combined cap; GROWTH would
not be injected. Trim docs/agy-golden-header.growth.md and re-drain."* For a missing seed the cap has NOT
been exceeded, and trimming the proposal does nothing to restore the seed.

Replace `:145-147` with a form that defers to the gate's own message:

```powershell
    if ($LASTEXITCODE -ne 0) {
        # DEFER TO THE GATE'S OWN MESSAGE rather than substituting a cause. The previous hardcoded line
        # asserted an overflow for ANY non-zero, which is confidently wrong for a missing or empty SEED:
        # the cap has not been exceeded, and trimming the proposal does nothing to restore the seed.
        # The gate has already printed the specific reason immediately above this line.
        Write-Host "drain-knowledge: WARNING - the combined GROWTH budget check did not pass; see the check-growth-budget line immediately above for the specific reason and remedy. The drain continues (this gate is warn-only)." -ForegroundColor Yellow
    }
```

- [ ] **Step 5: Add the CALLER's mutation control - it belongs to a DIFFERENT suite**

**A mutation in the caller can never redden a unit test of the gate** - they are separate scripts with
separate suites - so demanding it of the gate's table would be an instruction no implementer can satisfy
without inventing an integration harness. **The home for it already exists:**
`scripts/tests/drain-knowledge.Tests.ps1` (6.8 KB, registered once in the slow partition).

Add there: a test that runs the drain with the seed absent and asserts the operator-visible text **names a
missing seed rather than an overflow**. Restoring `drain-knowledge.ps1:146`'s single hardcoded warning must
turn THAT row red.

- [ ] **Step 6: Run both suites (never concurrently)**

```bash
pwsh -c "Invoke-Pester scripts/tests/check-growth-budget.Tests.ps1 -Output Detailed -CI"
```

then, separately:

```bash
pwsh -c "Invoke-Pester scripts/tests/drain-knowledge.Tests.ps1 -Output Detailed -CI"
```

Expected: both green.

- [ ] **Step 7: Mutation controls**

- **On the gate's suite:** collapse the missing and empty branches back into one - at least one row above
  must turn RED.
- **On the caller's suite:** restore the hardcoded "exceeds the cap" warning - the new drain row must turn
  RED.

- [ ] **Step 8: Commit**

```bash
git add scripts/check-growth-budget.ps1 scripts/drain-knowledge.ps1 \
        scripts/tests/check-growth-budget.Tests.ps1 scripts/tests/drain-knowledge.Tests.ps1
git commit -m "fix(gate): 13c - distinguish a missing input from an empty one at both call sites"
```

> **Named residual 1.** On a sparse checkout that excludes `seed/`, the operator now sees a non-zero on
> every drain and may normalise it, dulling the signal for a genuine overflow. **Two DISTINCT messages are
> what keep that signal alive** - a missing seed and an overflow must never print the same line, which is
> exactly what part two fixes.
>
> **Named residual 2, and it is why part two carries the whole weight.** Making the gate exit non-zero does
> NOT stop the drain, and this item deliberately does not change that: `:145-147` warns and continues,
> then `:169` prints a GREEN `drain-knowledge: done` banner and `:175` exits **0**. So on a missing seed
> the operator still ends with a green banner over a GROWTH proposal whose budget was never validly
> checked. **The warning is the only signal there is.** Making the drain ABORT is a larger behaviour change
> than 13c is scoped for - recorded as tracked debt.

---

## Task 16: Closeout - completion checklist, full gates, capstone handoff

- [ ] **Step 1: The per-file completion checklist**

**Nothing else detects that an edit was simply NOT MADE.** `check-seed-artifacts-synced.sh` and
`plugin-hooks-payload.Tests.ps1:47` compare the two PRODUCTS against each other, so a file left unedited
in BOTH passes byte-identity happily. **This checklist names the TABLE, never a count** - a restated count
stops covering whatever the table gains next.

Walk **every row** of the governed-artifacts table and confirm each file was actually edited:

| governed artifact | item | mirrored? | edited? |
|---|---|---|---|
| `plugin/hooks/agy-shield-lib.sh` | 14d | both plugins | ☐ dotnet ☐ classic |
| `plugin/hooks/agy-mark.sh` | 14c | both plugins | ☐ dotnet ☐ classic *(skip if Task 1 = BLOCKED)* |
| `plugin/hooks/agy-discipline-reaching.sh` | 14c | both plugins | ☐ dotnet ☐ classic |
| `plugin/skills/agy-first/SKILL.md` | 14c | both plugins | ☐ dotnet ☐ classic *(skip if BLOCKED)* |
| `plugin/skills/agy-capstone/SKILL.md` | 14c | both plugins | ☐ dotnet ☐ classic *(skip if BLOCKED)* |
| `plugin/skills/agy-test-audit/SKILL.md` | 14c | both plugins | ☐ dotnet ☐ classic *(skip if BLOCKED)* |
| `plugin/skills/open-issues/SKILL.md` | **14d** | both plugins | ☐ dotnet ☐ classic — **check the RIGHT thing:** under Task 1 = RESOLVED grep for `agy_shield`; under **BLOCKED** only Step 1b ships, so grep for `! -s` instead. **A `agy_shield` grep returns 0 under BLOCKED and would read as a skipped task.** |
| `agy-autotrain/skills/agy-curate/SKILL.md` | 14e | single copy | ☐ |

```bash
git diff --stat main...HEAD -- clavity-dotnet/plugin clavity-classic/plugin agy-autotrain/skills
```

Every unticked row is a task that was skipped. **`open-issues/SKILL.md` has no behavioural test either, so
this checklist is its only guarantee.**

- [ ] **Step 2: Run every oracle BY NAME**

Nothing is pushed, so no CI gate will run any of this. **Never infer a gate from a marker.**

```bash
just check-injected-context
bash scripts/check-seed-artifacts-synced.sh
```

Then, one at a time (**never two Pester suites concurrently**):

```bash
pwsh -c "Invoke-Pester scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed -CI"
```

Then the fast half, **backgrounded**, blocking on its `Tests Passed:` line:

```bash
pwsh -c "just test-scripts-fast" > /tmp/fast-run.log 2>&1
```

Then the slow half, **backgrounded**, blocking on its `Tests completed` line:

```bash
pwsh -c "just test-scripts-slow" > /tmp/slow-run.log 2>&1
```

**A log with no `Tests Passed:` line is an ABORTED run, not a pass.** Read the counts in both.

- [ ] **Step 3: Run the two product test suites**

```bash
cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests ; cd ..
cd clavity-classic && cargo test --all --features test-fakes ; cd ..
```

**Read the COUNT, not the exit code** - `dotnet test --filter` exits 0 on no match.

- [ ] **Step 4: Verify the revert story still holds**

State it before it is needed:

- **14d cannot be reverted while 14c stands** - 14c's hook sources the helper and `agy-mark.sh` calls it.
  Revert 14c first, or revert both together.
- **14c is FOUR things that revert together** - `agy-mark.sh`, the hook wiring, the three skill rewrites,
  and the ROADMAP rewrite. Reverting the script while the skills still invoke it leaves three shipped
  skills naming an executable that does not exist. **Revert all four or none.**
- **14e's halves revert together** - reverting the generator while `agy-curate/SKILL.md` still says "run
  the generator" recreates the incomplete fold this batch exists to avoid, pointed the other way.
- **14b is THREE files** - the `justfile`, `ci-scripts.yml` (job steps AND both `paths:` lists), and the
  registration pin. Reverting the workflow while the pin stands leaves a test asserting CI wiring that no
  longer exists.
- **13c is TWO files.** Reverting the CALLER while the gate distinguishes a missing seed restores the
  confidently-wrong "exceeds the cap" advice for a state that is not an overflow.
- 14a and 13a are independently revertible.

- [ ] **Step 5: AGY-CAPSTONE over the batch as a RANGE**

The batch forms ONE review boundary. Run the capstone **immediately on completion, at low context** - the
ROADMAP `:569-573` ruling measured that a capstone at turn 500 pays ~5x the identical capstone at turn 50,
so batching review to the end is the expensive direction.

```bash
git log --oneline <first-batch-commit>..HEAD
```

Send that range to the capstone. **Verify every peer finding by measurement before folding, AND verify its
suggested FIX the same way** - a correct finding routinely arrives with a wrong or incomplete fix.
**Re-run a fresh round after every fold** with a do-not-re-raise ledger, until a full round is GREEN.

- [ ] **Step 6: Update the durable task index**

Refresh `project_anomaly-hotfix-batch.md` with each commit SHA and the new resume point. **A commit not
yet reflected in the index is a recovery hole.**

---

## Self-review

Run against the spec with fresh eyes.

### 1. Spec coverage

| spec section | task | covered |
|---|---|---|
| 3.1-3.6 global rules | "Standing rules" + per-task steps | yes |
| 4.1 - 14d helper (A0, A1, A2 x3, B1-B4) | Task 3 | yes - B4 deliberately has NO test row, per the spec's option (b) |
| 4.1 - `open-issues` snippet | Task 4 | yes |
| 4.2 - 14c hook half | Task 5 | yes |
| 4.2 - `agy-mark.sh` | Task 6 | yes, **conditional on Task 1**, with M2's anchor correction |
| 4.2 - three skill rewrites | Task 7 | yes, conditional |
| 4.2 - ROADMAP rewrite | Task 8 | yes, all three sites (M5) |
| 4.2 - the locator measurement | Task 1 | yes - **owner extended the option space** |
| 4.3 - `.gitattributes` pin (1a) | Task 9 | yes, with the clean-tree precondition |
| 4.3 - generator + constraints 1b, 2, 3, 5 | Task 10 | yes |
| 4.3 - the pre-commit hook + 15 rows + 3 remedies | Task 11 | yes, **plus M4** |
| 4.3 - `agy-curate/SKILL.md` companion | Task 12 | yes, third person |
| 4.4 - 14a | Task 2 | yes, with lexically adjacent controls |
| 4.5 - 14b, all three parts | Task 13 | yes, incl. the non-symmetry of "both jobs" |
| 4.6 - 13a | Task 14 | yes, with the vacuity guard |
| 4.7 - 13c, both call sites | Task 15 | yes, incl. the caller's own suite |
| 5 - ordering and revert | order of tasks + Task 16 Step 4 | yes |

**Ordering deviation, stated:** the spec's order is 14a, 14d, 14c, 14e, then (14b, 13a, 13c). This plan
inserts Task 1 (the locator measurement) FIRST, per the owner's decision, because it determines whether
Tasks 6 and 7 exist at all. Everything else follows the spec's order.

### 2. Placeholder scan

No TBD, no "implement later", no "similar to Task N", no "add appropriate error handling". Two places
carry a deliberate `<placeholder>`:

- `<BASE>` in Task 7 - **resolved by Task 1's recorded measurement**, which is a named prior step, not a
  deferral.
- `<first-batch-commit>` in Task 16 - a runtime value.

**Task 11 Step 1 specifies its 15 rows as a table rather than as complete Pester code.** That is the one
place this plan is thinner than the rest, and it is called out rather than hidden: each row's fixture state
and assertion is fully specified, but the implementer writes the harness. The rows' mutation controls are
given in Step 7.

### 3. Type and name consistency

- `agy_shield` - one name, three call sites (Task 3 defines, Tasks 4/5/6 call). Consistent.
- `agy-shield-lib.sh`, `agy-mark.sh`, `generate-cheatsheet-literals.ps1`,
  `check-cheatsheet-parity.ps1` - each spelled identically everywhere it appears.
- `just gen-cheatsheet-literals` - the recipe name in Task 10, quoted identically in Tasks 11 and 12.
- Helper argument order `(root, relpath, key)` - identical in the definition and all three call sites.
- `agy-mark.sh` modes `head` / `log` / `prepare` - identical in the contract, the script, and the tests.

### 4. Open items carried OUT of this plan

- **ROADMAP 14f** (the `core.md` ownership contradiction) - needs an owner ruling, deliberately not folded.
  Task 12 is written to be correct under either resolution.
- **13c residual 2** - making the drain ABORT on a missing seed is a larger behaviour change; tracked debt.
- **If Task 1 = BLOCKED** - 14c's skill half returns to the owner as a scoping decision, recorded in
  ROADMAP §14c by Task 8 Step 4.

