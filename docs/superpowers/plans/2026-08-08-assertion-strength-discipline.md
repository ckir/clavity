# PINNING-ASSERTION-STRENGTH Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship assertion-strength as a mechanical, peer-free discipline: a `PostToolUse` hook that, the FIRST
time each test file is touched in a session, names the three structural assertion-strength smells and points
at the canonical prose.

**Architecture:** One new byte-identical hook per driver plugin (`assertion-strength-reminder.sh`), registered
on `PostToolUse` `Write|Edit`, gated by a strict test-file filename predicate and a per-file-per-session
debounce marker held OUTSIDE `.clavity/agy-marks/`. The canonical prose is the existing
`agy-test-audit/SKILL.md` Step 5 paragraph, WIDENED to reach tests written during ordinary implementation.
No new skill, no `CLAUDE.md` residue, no peer consult.

**Tech Stack:** bash (hook), Pester 5 (tests), `jq` (payload parse, with a mandatory field-bounded-grep
fallback), `justfile` (explicit suite registration).

---

## CRITICAL CONSTRAINTS - read before Task 1

1. **PURE ASCII in every file you touch.** `scripts/check-installer-ascii.ps1` gates the 5.1 domain and
   `check-agy-discipline-skills.ps1:66-69` gates SKILL bodies. Use `-` not an em-dash. No smart quotes.
2. **BYTE-IDENTICAL PAIR.** `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/` are compared
   file-by-file by `scripts/check-seed-artifacts-synced.sh:26-40`, which DISCOVERS files (`find hooks skills
   knowledge -type f`) and exempts only the five names in its `divergent()` list. The new hook is NOT exempt.
   **Mirror by `cp`, NEVER by retyping** - a retyped mirror has drifted every time it has been tried here.
3. **`docs/superpowers/*` is gitignored** (`.gitignore:32`). This plan file needs `git add -f`.
4. **Test registration is an EXPLICIT LIST in `justfile`, not a glob**, enforced by
   `scripts/tests/test-suite-registration.Tests.ps1`. A new `*.Tests.ps1` that is not listed FAILS that suite.
5. **`.clavity/` is gitignored** (`.gitignore:45`). Never `git add -f` anything under it.
6. **NO-PUSH WINDOW: end of Task 3 to end of Task 4.** Task 3 commits deliberately RED (the mirror-parity
   test), Task 4's `cp` clears it. Verified safe to COMMIT red: `.git/hooks/pre-commit` -> lefthook runs only
   `ruff` on staged Python (`lefthook.yml:47+`), and `check-seed-artifacts-synced.sh` is a PRE-PUSH gate. So a
   mid-window PUSH would land red in CI. Do not push inside the window.
7. **The owner owns every push.** This plan never pushes.

---

## What is ALREADY SETTLED - do not re-derive

From `clavity-dotnet/ROADMAP.md:704-719` ("Agreed shape ... these are settled") and the owner's rulings of
2026-08-08:

- **Mechanical, no peer.** The detector was a test runner, not a reviewer.
- **Plugin-only home**, canonical prose at `agy-test-audit/SKILL.md` Step 5. **No `CLAUDE.md` copy.**
- **Drop the `AGY-` prefix** (`ROADMAP.md:712` - every `AGY-*` discipline convenes the peer; this one does not).
- **Trigger:** `PostToolUse` on `Write|Edit`, debounced to the FIRST touch of each test file per session.
- **The three structural smells** are fixed and are quoted verbatim in Task 3's hook message.
- **Test-file predicate = STRICT FILENAME PATTERNS** (owner ruling 2026-08-08). Prefer false-NEGATIVES.
- **Straight to a plan, no spec** (owner ruling 2026-08-08).

**Section 11's "defect #4" is NOT an open decision.** It asks whether this hook may write a marker, given
`agy-test-audit-reminder.sh:10` says that hook never does. The repo already made that decision in writing at
`agy-anomaly-capture-reminder.sh:49-53`:

> `# THIS MARKER IS NOT A DISCIPLINE MARKER. It must never live in .clavity/agy-marks/, must never be read as`
> `# evidence that anything was DELIVERED, and must never be named *.head. docs/agy-disciplines-marker-contract.md`
> `# forbids a hook writing a .head marker, and gives the reason: a hook fires before the consult and cannot`
> `# know its outcome. That reason does not apply here -- this records a fact the hook does know, that it`
> `# already emitted -- but the two must stay visibly separate or the next reader will conflate them.`

Confirmed by `docs/agy-disciplines-marker-contract.md:1` (*"skill writes, auto-fire hook reads"*). So: a
debounce marker is permitted, MUST NOT be named `*.head`, and MUST NOT live in `.clavity/agy-marks/`.

---

## THE ONE UNVERIFIED FACT - Task 1 exists to settle it

**The per-session debounce depends on `session_id` being present in the `PostToolUse` payload, and that is
NOT verified.** Measured 2026-08-08:

- `agy-anomaly-capture-reminder.sh:61` reads `session_id`, but its gate at `:60` is `UserPromptSubmit`.
- `agy-discipline-reaching.sh:42` reads `session_id`, but it is registered on `SessionStart`
  (`hooks.json`, verified by `jq`).
- **Neither PostToolUse test fixture in this repo builds `session_id`.** `agy-after-reminder.Tests.ps1` and
  `agy-test-audit-reminder.Tests.ps1` construct only `cwd`, `file_path`, `hook_event_name`, `tool_input`.

So no hook in this repo has ever read `session_id` on a `PostToolUse` payload. **Task 1 measures it live.**
Both outcomes have a fully specified design below - the executor never has to invent one.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh` | CREATE. The hook: predicate, debounce, emit. | 3 |
| `clavity-classic/plugin/hooks/assertion-strength-reminder.sh` | CREATE by `cp`. Byte-identical mirror. | 4 |
| `clavity-dotnet/plugin/hooks/hooks.json` | MODIFY. Register on `PostToolUse` `Write\|Edit`. | 3 |
| `clavity-classic/plugin/hooks/hooks.json` | MODIFY. Same registration. | 4 |
| `scripts/tests/assertion-strength-reminder.Tests.ps1` | CREATE. The suite. | 2, 3 |
| `justfile` | MODIFY. Add the suite to `test-scripts-fast`'s explicit list. | 2 |
| `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md` | MODIFY. Widen Step 5. | 5 |
| `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` | MODIFY by `cp`. | 5 |
| `clavity-dotnet/ROADMAP.md` | MODIFY. Reconcile section 11 to SHIPPED. | 6 |

---

## Task 1: Settle whether `session_id` reaches a PostToolUse hook

**Files:**
- Create (throwaway, deleted in Step 4): `.clavity/scratch/assertion-strength/probe.sh`

- [ ] **Step 1: Create the scratch dir and a probe hook that dumps its stdin**

```bash
mkdir -p .clavity/scratch/assertion-strength
cat > .clavity/scratch/assertion-strength/probe.sh <<'EOF'
#!/usr/bin/env bash
set +e
input=$(cat)
printf '%s\n' "$input" >> "$HOME/.clavity-tmp/posttooluse-probe.jsonl"
exit 0
EOF
mkdir -p "$HOME/.clavity-tmp"
```

- [ ] **Step 2: Register the probe TEMPORARILY in the user's local settings**

**STOP AND ASK THE OWNER before this step.** It edits `~/.claude/settings.local.json`, which is the owner's
file. Show them this exact block and get explicit approval:

```json
{ "matcher": "Write|Edit",
  "hooks": [ { "type": "command",
               "command": "bash \"C:/Users/user/Development/Rust/clavity/.clavity/scratch/assertion-strength/probe.sh\"" } ] }
```

If the owner declines, **skip to Step 5 and take the NO-SESSION-ID branch** - it is fully specified and costs
only debounce granularity.

- [ ] **Step 3: Trigger one Write and read the captured payload**

```bash
printf 'probe\n' > .clavity/scratch/assertion-strength/trigger.txt   # any Write fires the hook
python -c "import json,io,os; p=os.path.expanduser('~/.clavity-tmp/posttooluse-probe.jsonl'); ls=[l for l in io.open(p,encoding='utf-8') if l.strip()]; d=json.loads(ls[-1]); print('KEYS:', sorted(d.keys())); print('session_id PRESENT:', 'session_id' in d)"
```

Expected: a `KEYS:` line and a `session_id PRESENT: True|False` line. **Record which.**

- [ ] **Step 4: Unregister the probe and delete it**

Remove the block added in Step 2 from `~/.claude/settings.local.json`. Then:

```bash
rm -rf .clavity/scratch/assertion-strength "$HOME/.clavity-tmp/posttooluse-probe.jsonl"
git status --short   # expect empty; .clavity/ is gitignored anyway
```

- [ ] **Step 5: Record the branch in this plan file**

Edit the line below to state the measured answer, then `git add -f` this plan and commit.

> **MEASURED `session_id` on PostToolUse: `<PRESENT|ABSENT>` - measured YYYY-MM-DD by the Task 1 probe.**

```bash
git add -f docs/superpowers/plans/2026-08-08-assertion-strength-discipline.md
git commit -m "docs(plan): record the measured PostToolUse session_id result for section 11"
```

**The two branches, both fully specified:**

- **PRESENT** -> debounce key is the session id. Marker file `"$_cand/.clavity-assert-seen-$sid"`.
- **ABSENT** -> debounce key is the calendar day, via the bash builtin `printf -v today '%(%Y%m%d)T' -1`
  (no subprocess). Marker file `"$_cand/.clavity-assert-seen-day$today"`. Coarser (one nudge per test file
  per day rather than per session) but stable, fork-free, and still satisfies "not on every edit".
  **Everything else in Task 3 is identical**; only the two lines computing `$key` change.

---

## Task 2: Create the test suite skeleton and register it

Registration comes BEFORE the hook exists so `test-suite-registration.Tests.ps1` never sees an unregistered
suite. The suite starts with the one test that can pass with no hook: its own registration.

**Files:**
- Create: `scripts/tests/assertion-strength-reminder.Tests.ps1`
- Modify: `justfile:101`

- [ ] **Step 1: Create the suite with a single passing placeholder test**

```powershell
# scripts/tests/assertion-strength-reminder.Tests.ps1
BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook     = Join-Path $script:RepoRoot 'clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh'
    $script:Mirror   = Join-Path $script:RepoRoot 'clavity-classic/plugin/hooks/assertion-strength-reminder.sh'
}

Describe 'assertion-strength-reminder.sh' {
    It 'is registered in the justfile fast suite' {
        $jf = Get-Content -Raw (Join-Path $script:RepoRoot 'justfile')
        $jf.Contains("scripts/tests/assertion-strength-reminder.Tests.ps1") |
            Should -BeTrue -Because 'registration is an explicit list, not a glob'
    }
}
```

- [ ] **Step 2: Add the suite to `test-scripts-fast`**

In `justfile:101`, inside the `Invoke-Pester @(...)` array, insert
`'scripts/tests/assertion-strength-reminder.Tests.ps1', ` immediately after
`'scripts/tests/agy-after-reminder.Tests.ps1', `.

- [ ] **Step 3: Run the suite and the registration gate**

```bash
pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/assertion-strength-reminder.Tests.ps1','scripts/tests/test-suite-registration.Tests.ps1') -CI"
```

Expected: `Failed: 0`. **Read the printed COUNT** - Pester exits 0 on an empty match, so absence-of-failure
is not a pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/assertion-strength-reminder.Tests.ps1 justfile
git commit -m "test(assertion-strength): register the suite before the hook exists"
```

---

## Task 3: Write the hook, TDD, dotnet only (ENDS DELIBERATELY RED)

**Files:**
- Modify: `scripts/tests/assertion-strength-reminder.Tests.ps1`
- Create: `clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh`
- Modify: `clavity-dotnet/plugin/hooks/hooks.json`

- [ ] **Step 1: Write the failing tests**

Replace the `Describe` block from Task 2 with this complete block (keep the `BeforeAll` as written).

🔴 **COHERENCE GATE - read Task 1's measured result first.** The `New-Payload` helper below emits a
`session_id` field. **If Task 1 measured `session_id` ABSENT on `PostToolUse`, DELETE the `$Sid` parameter
and the `"session_id":"$Sid",` fragment from `New-Payload`.** A fixture that supplies a field production
never sends would let the debounce tests pass through the session-id path while the shipped hook runs the
day-fallback path - green tests over an unexercised branch, which is exactly the defect class this whole
discipline exists to catch. Do not leave the fixture richer than reality.

```powershell
Describe 'assertion-strength-reminder.sh' {
    BeforeAll {
        # Build a PostToolUse payload. Mirrors the fixture shape used by agy-after-reminder.Tests.ps1.
        function New-Payload {
            param([string]$FilePath, [string]$Cwd, [string]$Sid = 'sess-abc123')
            $fp = $FilePath.Replace('\','\\')
            $cw = $Cwd.Replace('\','\\')
            "{`"session_id`":`"$Sid`",`"hook_event_name`":`"PostToolUse`",`"cwd`":`"$cw`",`"tool_input`":{`"file_path`":`"$fp`"}}"
        }
        function Invoke-Hook {
            param([string]$Payload)
            $Payload | & bash $script:Hook 2>&1
        }
        # Each test gets a private HOME so the debounce marker never leaks between tests.
        function New-IsolatedHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("asrt-" + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force -Path $h | Out-Null
            return $h
        }
    }

    It 'is registered in the justfile fast suite' {
        $jf = Get-Content -Raw (Join-Path $script:RepoRoot 'justfile')
        $jf.Contains("scripts/tests/assertion-strength-reminder.Tests.ps1") |
            Should -BeTrue -Because 'registration is an explicit list, not a glob'
    }

    Context 'test-file predicate (strict filename patterns - owner ruling 2026-08-08)' {
        It 'FIRES on <path>' -ForEach @(
            @{ path = 'C:/repo/scripts/tests/foo.Tests.ps1' }
            @{ path = 'C:/repo/tests/Clavity.Ls.Tests/BoundedViewTests.cs' }
            @{ path = 'C:/repo/tests/thing_test.py' }
            @{ path = 'C:/repo/tests/test_thing.py' }
            @{ path = 'C:/repo/src/lib_test.rs' }
        ) {
            $env:HOME = New-IsolatedHome
            $out = Invoke-Hook (New-Payload -FilePath $path -Cwd 'C:/repo')
            ($out -join "`n") | Should -Match 'ASSERTION-STRENGTH'
        }

        It 'is SILENT on <path>' -ForEach @(
            @{ path = 'C:/repo/src/Thing.cs' }
            @{ path = 'C:/repo/tests/fixtures/members.json' }
            @{ path = 'C:/repo/tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj' }
            @{ path = 'C:/repo/docs/notes.md' }
            @{ path = 'C:/repo/scripts/tests/_partition.md' }
        ) {
            $env:HOME = New-IsolatedHome
            $out = Invoke-Hook (New-Payload -FilePath $path -Cwd 'C:/repo')
            ($out -join "`n") | Should -Not -Match 'ASSERTION-STRENGTH'
        }
    }

    Context 'debounce' {
        It 'fires on the FIRST touch and is SILENT on the second touch of the same file' {
            $env:HOME = New-IsolatedHome
            $p = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo'
            ((Invoke-Hook $p) -join "`n") | Should -Match 'ASSERTION-STRENGTH'
            ((Invoke-Hook $p) -join "`n") | Should -Not -Match 'ASSERTION-STRENGTH'
        }

        It 'fires again for a DIFFERENT test file in the same session' {
            $env:HOME = New-IsolatedHome
            ((Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo')) -join "`n") |
                Should -Match 'ASSERTION-STRENGTH'
            ((Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/b.Tests.ps1' -Cwd 'C:/repo')) -join "`n") |
                Should -Match 'ASSERTION-STRENGTH'
        }

        It 'never writes into .clavity/agy-marks/ and never writes a *.head file' {
            $env:HOME = New-IsolatedHome
            Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo') | Out-Null
            (Get-ChildItem -Recurse -File $env:HOME -Filter '*.head' -ErrorAction SilentlyContinue).Count |
                Should -Be 0 -Because 'agy-anomaly-capture-reminder.sh:49-53 forbids a hook writing a .head marker'
        }
    }

    Context 'kill-switch and safety' {
        It 'is suppressed by .no-agy in cwd' {
            $env:HOME = New-IsolatedHome
            $repo = New-IsolatedHome
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') | Out-Null
            $out = Invoke-Hook (New-Payload -FilePath "$repo/scripts/tests/a.Tests.ps1" -Cwd $repo)
            ($out -join "`n") | Should -Not -Match 'ASSERTION-STRENGTH'
        }

        It 'DOES fire from that same cwd without .no-agy (positive control)' {
            $env:HOME = New-IsolatedHome
            $repo = New-IsolatedHome
            $out = Invoke-Hook (New-Payload -FilePath "$repo/scripts/tests/a.Tests.ps1" -Cwd $repo)
            ($out -join "`n") | Should -Match 'ASSERTION-STRENGTH'
        }

        It 'names all three structural smells in its message' {
            $env:HOME = New-IsolatedHome
            $out = (Invoke-Hook (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo')) -join "`n"
            $out | Should -Match 'cardinality'
            $out | Should -Match 'fallback'
            $out | Should -Match 'distractor'
        }

        It 'ships as pure ASCII' {
            $raw = Get-Content -Raw $script:Hook
            ([regex]::Matches($raw, '[^\x00-\x7F]')).Count | Should -Be 0
        }
    }

    # The degraded branch runs on most real installs (see agy-after-reminder.sh:13-15). It is NOT optional
    # coverage: its own template carries four such tests. PATH is stripped so `command -v jq` fails.
    Context 'degraded path (jq absent)' {
        BeforeAll {
            function Invoke-HookNoJq {
                param([string]$Payload)
                $Payload | & bash -c 'PATH=/nonexistent-for-test exec bash "$0"' $script:Hook 2>&1
            }
        }

        It 'emits a LOUD jq-missing line on a test-file write' {
            $env:HOME = New-IsolatedHome
            $out = Invoke-HookNoJq (New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo')
            ($out -join "`n") | Should -Match 'guard inactive: missing jq'
        }

        It 'is SILENT on a non-test path when jq is absent' {
            $env:HOME = New-IsolatedHome
            $out = Invoke-HookNoJq (New-Payload -FilePath 'C:/repo/src/Thing.cs' -Cwd 'C:/repo')
            ($out -join "`n") | Should -Not -Match 'guard inactive'
        }

        It 'warns at most ONCE per session, not on every test-file write' {
            $env:HOME = New-IsolatedHome
            $p = New-Payload -FilePath 'C:/repo/scripts/tests/a.Tests.ps1' -Cwd 'C:/repo'
            ((Invoke-HookNoJq $p) -join "`n") | Should -Match 'guard inactive: missing jq'
            ((Invoke-HookNoJq $p) -join "`n") | Should -Not -Match 'guard inactive: missing jq'
        }

        It 'carries no AGY- prefix in its emitted tag' {
            $raw = Get-Content -Raw $script:Hook
            $raw | Should -Not -Match '\[AGY-DISCIPLINES\]' -Because 'ROADMAP.md:712 - this discipline convenes no peer'
        }

        It 'is byte-identical to the clavity-classic mirror' {
            (Test-Path $script:Mirror) | Should -BeTrue
            (Get-FileHash $script:Hook).Hash | Should -Be (Get-FileHash $script:Mirror).Hash
        }
    }
}
```

- [ ] **Step 2: Run and watch them FAIL for the right reason**

```bash
pwsh -NoProfile -c "Invoke-Pester 'scripts/tests/assertion-strength-reminder.Tests.ps1' -CI"
```

Expected: many failures, all because the hook file does not exist. **If any test passes that asserts the hook
FIRES, STOP** - a test that passes with no hook is not an oracle.

- [ ] **Step 3: Write the hook**

Create `clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh`. Structure and every safety comment are
lifted from `agy-after-reminder.sh` (the sibling `PostToolUse` `Write|Edit` hook); the debounce block is
lifted from `agy-anomaly-capture-reminder.sh:82-115`.

**SHAPE-DIVERGENCE STOP:** the double-backslash form `${cwd//\\\\//}` on the no-jq path and the single-backslash
form `${cwd//\\//}` on the jq path are BOTH deliberate and MUST NOT be unified -
`agy-after-reminder.sh:53-57` records the measurement showing why. If you find yourself "fixing" one, stop.

```bash
#!/usr/bin/env bash
# PINNING-ASSERTION-STRENGTH (plugin-shipped). PostToolUse(Write|Edit): the FIRST time each test file is
# touched in a session, name the three structural assertion-strength smells and point at the canonical
# prose. This is NOT an agy discipline - it convenes no peer (ROADMAP.md:712), so it carries no AGY- prefix
# and emits an [ASSERTION-STRENGTH] tag. The procedure lives in agy-test-audit/SKILL.md Step 5; this hook
# only POINTS at it. Fail-open: any error -> exit 0. Suppressed by .no-agy (cwd, repo root, or ~/.claude),
# matching every other hook this plugin ships.
#
# THE DEBOUNCE MARKER IS NOT A DISCIPLINE MARKER. It must never live in .clavity/agy-marks/ and must never
# be named *.head - docs/agy-disciplines-marker-contract.md reserves those for a SKILL recording a completed
# consult. The reason that contract gives (a hook fires before the consult and cannot know its outcome) does
# not apply here: this records a fact the hook does know, that it already emitted. Precedent and full
# rationale: agy-anomaly-capture-reminder.sh:49-53.
set +e
input=$(cat)

# --- jq guard. Without jq, fall back to a FIELD-BOUNDED grep on the RAW payload and, ONLY on a test-file
# match, emit a loud hard-coded ASCII line so this is never a silent no-op. Kill-switch honored first. ---
if ! command -v jq >/dev/null 2>&1; then
  [[ $input =~ \"cwd\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && cwd=${BASH_REMATCH[1]}
  cwd_path=${cwd//\\\\//}
  [ -z "$cwd_path" ] && cwd_path="."
  [ -f "$HOME/.claude/.no-agy" ] && exit 0
  if [ -f "$cwd_path/.no-agy" ]; then exit 0; fi
  if printf '%s' "$input" | grep -Eq '"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]*([Tt]ests?\.ps1|Tests?\.cs|_test\.(py|rs)|test_[^"\\/]*\.(py|rs))"'; then
    # DEBOUNCE THE DEGRADED BRANCH TOO, ONCE PER SESSION. agy-after-reminder.sh's degraded branch emits on
    # every match because a spec/plan write is RARE. A test-file write is not - on this trigger an
    # undebounced warning is the high-frequency spam this discipline exists to remove, rebuilt one layer
    # down. One warning per session is enough to tell the operator the guard is inactive.
    [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && dsid=${BASH_REMATCH[1]}
    dsid=${dsid//[^A-Za-z0-9_-]/}
    [ -z "$dsid" ] && printf -v dsid 'day%(%Y%m%d)T' -1
    for _dc in "${TMPDIR:-/tmp}" "$HOME/.clavity-tmp"; do
      [ -d "$_dc" ] || mkdir -p "$_dc" 2>/dev/null
      _dw="$_dc/.clavity-assert-nojq-$dsid"
      [ -f "$_dw" ] && exit 0
      if : > "$_dw" 2>/dev/null; then
        printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[ASSERTION-STRENGTH] guard inactive: missing jq - the assertion-strength reminder will not fire on test-file writes this session"}}'
        exit 0
      fi
    done
    # No writable location: warn the OPERATOR on stderr rather than emit to the model every edit.
    printf '%s\n' "[ASSERTION-STRENGTH] guard inactive: missing jq, and no writable marker location - reminder disabled" >&2
  fi
  exit 0
fi

fp=$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)
[ -z "$fp" ] && exit 0

# THE NORMALIZATION FORM MUST MATCH THE EXTRACTION SOURCE - see agy-after-reminder.sh:53-57. jq -r DECODES
# the JSON escaping, so cwd holds SINGLE backslashes here.
cwd_path=${cwd//\\//}
[ -z "$cwd_path" ] && cwd_path="."

[ -f "$HOME/.claude/.no-agy" ] && exit 0

# Repo root by walking up for .git, in-shell. ONE stat gates the walk - on an unreachable share every level
# pays an SMB timeout (agy-after-reminder.sh:69-72, MEASURED).
root=$cwd_path
if [ -d "$cwd_path" ]; then
  _d=$cwd_path
  while [ -n "$_d" ] && [ "$_d" != "/" ] && [ "$_d" != "." ]; do
    if [ -e "$_d/.git" ]; then root=$_d; break; fi
    case "$_d" in //*/*/*) ;; //*) break ;; esac
    _p=${_d%/*}
    [ "$_p" = "$_d" ] && break
    [ -z "$_p" ] && break
    _d=$_p
  done
fi
if [ -f "$root/.no-agy" ] || [ -f "$cwd_path/.no-agy" ]; then exit 0; fi

# --- STRICT test-file predicate (owner ruling 2026-08-08). Filename patterns ONLY; prefer false-NEGATIVES.
# An over-eager guard trains the operator to ignore it, which is how an earlier guard in this repo died
# (ROADMAP.md:714-716). Deliberately EXCLUDED: anything under a tests/ tree that does not match by NAME -
# fixtures, .json, .csproj, .md. Evaluated with a builtin `case`, no subprocess. ---
norm=${fp//\\//}
base=${norm##*/}
fire=0
case "$base" in
  *.Tests.ps1|*.tests.ps1)   fire=1 ;;
  *Tests.cs|*Test.cs)        fire=1 ;;
  test_*.py|*_test.py)       fire=1 ;;
  test_*.rs|*_test.rs)       fire=1 ;;
esac
[ "$fire" -eq 0 ] && exit 0

# --- Per-file, per-session debounce. Location and naming are constrained by the precedent quoted in the
# header. SANITIZE before any payload-derived value becomes a filename: the captures below are [^"]*, which
# admits "/" and "..", and an unchecked concatenation would let a payload choose where a file lands
# (agy-anomaly-capture-reminder.sh:82-87). ---
[[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
sid=${sid//[^A-Za-z0-9_-]/}
if [ -z "$sid" ]; then
  # NO-SESSION-ID BRANCH (see the plan's Task 1). Degrade to per-day, not to per-edit: firing on every edit
  # is the spam this discipline exists to avoid. printf %(...)T is a bash builtin - no subprocess.
  printf -v sid 'day%(%Y%m%d)T' -1
fi

seen=""
for _cand in "${TMPDIR:-/tmp}" "$HOME/.clavity-tmp"; do
  [ -d "$_cand" ] || mkdir -p "$_cand" 2>/dev/null
  _s="$_cand/.clavity-assert-seen-$sid"
  if [ -f "$_s" ] || : > "$_s" 2>/dev/null; then
    seen=$_s
    # Prune only the location that just proved itself writable. -mtime +30, NOT +7: the markers of a session
    # that is still OPEN are as old as that session (agy-anomaly-capture-reminder.sh:103-106).
    find "$_cand" -maxdepth 1 -name '.clavity-assert-seen-*' -mtime +30 -delete 2>/dev/null
    break
  fi
done

if [ -z "$seen" ]; then
  # BOTH failure directions are bugs. Silent -> permanently inert, the exact defect this item removes.
  # Always-fire -> spam. So warn the OPERATOR on stderr and stay silent to the MODEL. STDERR AT EXIT 0,
  # never exit 2 (exit 2 is BLOCKING on some events) - agy-anomaly-capture-reminder.sh:66-80.
  printf '%s\n' "[ASSERTION-STRENGTH] cannot write a session marker under TMPDIR or HOME - the assertion-strength reminder is disabled for this session" >&2
  exit 0
fi

# Exact membership, no hashing and no slugging: a slug can collide and silently suppress a different file.
# Read with the `read` builtin - no fork on this per-edit path.
while IFS= read -r _line; do
  [ "$_line" = "$norm" ] && exit 0
done < "$seen"
printf '%s\n' "$norm" >> "$seen"

msg="ASSERTION-STRENGTH: you just touched a test file. Before you move on, check this test against the three structural smells that produce a GREEN test over broken code. (1) CARDINALITY over an ordered or filtered collection - asserting only how MANY survived is invariant under any permutation, so assert boundary IDENTITY (which item is first/last/absent), never count alone. (2) A DUAL-PATH FALLBACK masked by the ambient environment - if the primary dependency happens to be present, the fallback branch never runs; strip the dependency to force it. (3) A STRUCTURED-TOKEN matcher with no DISTRACTOR case - a pattern that matches the right token must also be shown to REJECT a near-miss. If you cannot show the test failing against a deliberate logic mutant of the code it guards, it is decoration. Full procedure: the agy-test-audit skill, Step 5."
jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}'
exit 0
```

- [ ] **Step 4: Register it in the dotnet plugin**

In `clavity-dotnet/plugin/hooks/hooks.json`, add to the `PostToolUse` array a new entry AFTER the existing
`Write|Edit` entry:

```json
{
  "matcher": "Write|Edit",
  "hooks": [
    { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/assertion-strength-reminder.sh\"" }
  ]
}
```

- [ ] **Step 5: Run the suite - expect exactly ONE failure**

```bash
pwsh -NoProfile -c "Invoke-Pester 'scripts/tests/assertion-strength-reminder.Tests.ps1' -CI"
```

Expected: `Failed: 1`, and the ONE permitted failure is
`is byte-identical to the clavity-classic mirror`. **Any other failure is a STOP.** Do NOT fix it by
copying to classic here - that would skip Task 4's parity verification.

- [ ] **Step 6: Commit, deliberately red**

```bash
git add clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh clavity-dotnet/plugin/hooks/hooks.json scripts/tests/assertion-strength-reminder.Tests.ps1
git commit -m "feat(assertion-strength): add the PostToolUse hook, dotnet only

Mirror parity test lands RED by design; Task 4's cp clears it."
```

**NO-PUSH WINDOW OPENS HERE.**

---

## Task 4: Mirror to clavity-classic

**Files:**
- Create: `clavity-classic/plugin/hooks/assertion-strength-reminder.sh` (by `cp`)
- Modify: `clavity-classic/plugin/hooks/hooks.json`

- [ ] **Step 1: Copy - never retype**

```bash
cp clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh clavity-classic/plugin/hooks/assertion-strength-reminder.sh
```

- [ ] **Step 2: Add the identical registration block to the classic `hooks.json`**

Same JSON block as Task 3 Step 4. `check-seed-artifacts-synced.sh:43-47` compares the two files'
`.hooks.PostToolUse` with `jq -S`, so the entries must be equal after sorting.

- [ ] **Step 3: Verify parity and the whole suite goes green**

```bash
bash scripts/check-seed-artifacts-synced.sh && echo "SEED SYNC OK"
pwsh -NoProfile -c "Invoke-Pester 'scripts/tests/assertion-strength-reminder.Tests.ps1' -CI"
```

Expected: `SEED SYNC OK`, then `Failed: 0`. **Read the count.**

- [ ] **Step 4: Commit**

```bash
git add clavity-classic/plugin/hooks/assertion-strength-reminder.sh clavity-classic/plugin/hooks/hooks.json
git commit -m "feat(assertion-strength): mirror the hook to clavity-classic"
```

**NO-PUSH WINDOW CLOSES HERE.**

---

## Task 5: Prove the tests are non-vacuous, then widen the canonical prose

**Files:**
- Modify: `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md:88-99`
- Modify: `clavity-classic/plugin/skills/agy-test-audit/SKILL.md` (by `cp`)

- [ ] **Step 1: MANDATORY logic mutant - prove the predicate tests are oracles**

This step is the whole point of the discipline being shipped; do not skip it. Neuter the predicate so it
never fires:

```bash
sed -i 's/^\[ "\$fire" -eq 0 \] && exit 0$/exit 0/' clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh
pwsh -NoProfile -c "Invoke-Pester 'scripts/tests/assertion-strength-reminder.Tests.ps1' -CI"
git checkout -- clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh
```

Expected under the mutant: every `FIRES on <path>` row plus the three-smells row and the positive control go
RED; the `is SILENT on <path>` rows stay green. **If the FIRES rows stay green, the tests are decoration -
STOP and fix them before proceeding.** Record the observed counts in the commit message.

- [ ] **Step 2: Second mutant - prove the debounce test is an oracle**

```bash
sed -i 's|^  \[ "\$_line" = "\$norm" \] && exit 0$|  :|' clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh
pwsh -NoProfile -c "Invoke-Pester 'scripts/tests/assertion-strength-reminder.Tests.ps1' -CI"
git checkout -- clavity-dotnet/plugin/hooks/assertion-strength-reminder.sh
```

Expected: exactly the `fires on the FIRST touch and is SILENT on the second touch` row goes RED.
**Confirm it is that specific test, not merely a non-zero suite.**

- [ ] **Step 3: Widen Step 5 of the canonical prose**

In `clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md`, the Step 5 paragraph currently opens at `:88`
with `5. **Close the chosen gaps - the DRIVER authors each test itself.**` and ends at `:99` with
`target rather than concluding "vacuous."`. Append this paragraph immediately after `:99`, before the blank
line preceding `## Disposition of findings (AGY-SCOPE)`:

```markdown
   **This bar is not audit-only.** It applies to EVERY test authored in this repo, including tests written
   during ordinary implementation that no audit ever asked for - that is the PINNING-ASSERTION-STRENGTH
   discipline, and the `assertion-strength-reminder.sh` hook nudges it on the first touch of each test file
   per session. It convenes no peer, so it carries no `AGY-` prefix. Three structural smells produce a GREEN
   test over broken code and are worth a deliberate check every time: (1) CARDINALITY over an ordered or
   filtered collection - a count is invariant under any permutation before truncation, so assert boundary
   IDENTITY, never count alone; (2) a DUAL-PATH FALLBACK masked by the ambient environment - strip the
   primary dependency to force the fallback branch to run; (3) a STRUCTURED-TOKEN matcher with no DISTRACTOR
   case - show it REJECTS a near-miss, not only that it accepts the real thing.
```

- [ ] **Step 4: Mirror the skill and verify every gate**

```bash
cp clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md
pwsh -NoProfile -Command "./scripts/check-agy-discipline-skills.ps1"
bash scripts/check-seed-artifacts-synced.sh && echo "SEED SYNC OK"
pwsh -NoProfile -c "Invoke-Pester 'scripts/tests/check-agy-discipline-skills.Tests.ps1' -CI"
```

Expected: `agy-discipline skills OK`, `SEED SYNC OK`, `Passed: 35, Failed: 0`. The ASCII gate at
`check-agy-discipline-skills.ps1:66-69` will reject any non-ASCII character you introduced.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/skills/agy-test-audit/SKILL.md clavity-classic/plugin/skills/agy-test-audit/SKILL.md
git commit -m "docs(assertion-strength): widen Step 5 past audit-gap tests

Records both mutant results from Steps 1-2."
```

---

## Task 6: Reconcile the ROADMAP and sweep for the fact that changed

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md:676-733`

- [ ] **Step 1: Flip section 11's heading to SHIPPED**

Change `### 11. PINNING-ASSERTION-STRENGTH - ship assertion-strength as a mechanical discipline · ✅ **KEPT 2026-08-06 (all three clauses)**`
to a SHIPPED heading in the same style as section 12's (`ROADMAP.md:735`). Record the commit SHAs.

- [ ] **Step 2: Correct the two stale claims inside section 11**

Both are now false and MUST NOT be left as-is:
- `:707-708` cites the canonical paragraph as `:88-96`; it is `:88-99` (measured 2026-08-08, after an
  unrelated amendment grew it).
- `:729-730` (draft defect #4) states the marker deviation "needs a deliberate decision". It does not - the
  decision already existed at `agy-anomaly-capture-reminder.sh:49-53`. Replace with a pointer to that
  precedent, so a future reader does not re-open a settled question.

- [ ] **Step 3: Law-3 whole-repo sweep for the fact you changed**

```bash
grep -rn "PINNING-ASSERTION-STRENGTH\|assertion-strength" --include=*.md --include=*.sh --include=*.ps1 . | grep -v '^\./\.clavity/' | grep -v '^\./docs/superpowers/'
```

Read EVERY hit. Any other file asserting this is unbuilt/unshipped must be updated in this same commit -
an incomplete fold is this repo's most common defect class.

- [ ] **Step 4: Full fast gate**

```bash
just test-scripts-fast
```

Expected: a `Tests Passed:` line with `Failed: 0`. Baseline before this plan was **369**; this plan adds the
new suite, so expect **369 + <the new suite's count>**. **A log with no `Tests Passed:` line is an ABORTED
run, not a pass.** This recipe is cap-adjacent - background it and block on its own completion line.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): record section 11 PINNING-ASSERTION-STRENGTH as shipped"
```

---

## After this plan

**AGY-CAPSTONE is MANDATORY** over the committed range (Task 2's commit .. Task 6's commit), rounds until
GREEN, verifying each finding AND its proposed fix by measurement before folding. Then AGY-TEST-AUDIT over
the same range. Neither is optional; both are owner-gated.

---

## Self-review

**Spec coverage.** Every settled item in `ROADMAP.md:704-733` maps to a task: mechanical/no-peer (Task 3, no
consult anywhere) · plugin-only home, no `CLAUDE.md` copy (Tasks 3-5 touch no `CLAUDE.md`) · drop the `AGY-`
prefix (Task 3 filename + the pinning test `carries no AGY- prefix in its emitted tag`) · `PostToolUse`
`Write|Edit` debounced to first touch per test file per session (Tasks 1, 3) · the three smells (Task 3
message + Task 5 prose, both pinned by the `names all three structural smells` test) · byte-identical pair
(Task 4, pinned by the mirror test and the seed-sync gate) · the four draft defects: #1 fabricated
`.clavity/marks/` path is avoided (the hook writes under `TMPDIR`/`HOME`, never `.clavity/`), #2 jq
hard-dependency is avoided (loud degraded branch + a fallback grep), #3 wrong `hooks.json` schema is avoided
(Task 3 Step 4 uses the real nested shape copied from the live file), #4 is resolved by precedent and
Task 6 Step 2 corrects the ROADMAP so it stops being asked.

**Placeholder scan.** No TBD/TODO. Every code step carries complete code. The one genuinely unknown fact
(`session_id` on `PostToolUse`) is not a placeholder: it is measured in Task 1 and BOTH branches are fully
specified, differing only in the two lines that compute `$sid`.

**Type/name consistency.** `assertion-strength-reminder.sh` is the filename in every task and in the test's
`$script:Hook`/`$script:Mirror`. The tag is `[ASSERTION-STRENGTH]` in the hook, the degraded line, and every
assertion. The marker prefix is `.clavity-assert-seen-` in the hook and in the prune glob.

**Known gaps, stated rather than hidden:**
1. **`$env:HOME` in the Pester tests governs the hook's `$HOME` only because bash inherits it.** If the
   execution environment does not propagate it, the debounce tests will share one marker directory and the
   second-touch test will pass for the wrong reason. Task 3 Step 2's "watch it fail" catches this, but the
   executor should confirm isolation explicitly if that step looks odd.
2. **The predicate does not cover Go, Java, or JS/TS test conventions.** Deliberate, per the owner's
   strict-patterns ruling and the false-negative preference. Widening it later is a one-line `case` addition.
3. **Task 1 Step 2 edits the owner's `~/.claude/settings.local.json`** and therefore STOPS for approval. If
   declined, the NO-SESSION-ID branch ships and the only cost is debounce granularity (per-day, not
   per-session).
