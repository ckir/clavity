# SP-D -- Degradation guards, hook-activation tests, anti-drift -- Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the final ship-agy-workflow subproject -- a SessionStart liveness/degradation notice, a jq-guard
retrofit, a comprehensive hook-activation test category, anti-drift enrollment, prerequisite docs, and the
owner-folded SP-0 namespace-gate regression test -- so the productized agy disciplines can never silently die.

**Architecture:** Best-effort, in-flow prompt discipline (NOT a code-enforced sandbox). SP-D adds one new
per-plugin SessionStart bash hook (`agy-liveness-check.sh`) shipped byte-identical in both driver plugins,
hardens `agy-after-reminder.sh` against a missing `jq`, and adds Pester coverage + a seed-sync anti-drift
diff. The user-visible boot notice is emitted the ONE documented way a SessionStart hook can reach the user:
**stderr + `exit 2`** (never `additionalContext`/stdout, which is silently absorbed at boot).

**Tech stack:** Bash hooks (`*.sh`, LF-pinned by `.gitattributes:12`), per-plugin `hooks.json` manifests, `jq`,
Pester (`scripts/tests/*.Tests.ps1`, run via `just test-scripts`), the bash seed-sync gate
(`scripts/check-seed-artifacts-synced.sh`, `just seed-sync-check`).

**Design source:** `docs/superpowers/specs/2026-07-25-sp-d-degradation-tests-anti-drift-design.md` (double-GREEN:
AGY-AFTER panel 3 rounds + hardening delta 3 rounds).

---

## Measured platform facts (verified before this plan was written -- do NOT re-derive; re-verify only if a step fails)

- **`agy-drive-session-reset.sh` lives ONLY in `clavity-classic`** (its variant-specific SessionStart entry);
  `clavity-dotnet` has NO `SessionStart` block today. Verified via `git ls-files clavity-*/plugin/hooks/`.
- **`Get-Command bash` is non-deterministic:** locally it resolves to WSL's `C:\WINDOWS\system32\bash.exe`
  (own filesystem, cannot run a Windows-path hook); CI (GitHub Actions windows runner, no WSL) resolves to
  Git Bash `C:\Program Files\Git\bin\bash.exe`. **All hook tests MUST pin Git Bash** and reject the system32
  WSL bash. The existing SP-C smoke uses `Get-Command bash` and is therefore fragile locally -- Task 5 fixes it.
- **Git Bash accepts forward-slash Windows hook paths** (`C:/Users/.../x.sh`) and returns the hook's real exit
  code; `$errFile` capture via `2>$errFile` works; `exit 2` surfaces as `$LASTEXITCODE = 2`.
- **Env passthrough (Git Bash / MSYS):** `CLAUDE_CONFIG_DIR` and `CLAUDE_PROJECT_DIR` set from PowerShell reach
  the hook as usable POSIX-converted paths when set to ABSOLUTE Windows paths. `HOME` is MSYS-special: a
  non-absolute value is mangled; an absolute fixture path is the required form (Task 1 validates this
  empirically before the suite relies on it).
- **`.gitignore:32` = `docs/superpowers/*`** ignores this plan file's tree; commit new plan/spec files with
  `git add -f`. **`.gitattributes:12` = `*.sh text eol=lf`** -- every new/edited `.sh` MUST stay LF.
- **`just test-scripts` = `pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"`** -- a new
  `scripts/tests/*.Tests.ps1` is auto-discovered. **`just seed-sync-check` = `bash scripts/check-seed-artifacts-synced.sh`.**

---

## File structure (what each touched file is responsible for)

**New files:**
- `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` + `clavity-classic/plugin/hooks/agy-liveness-check.sh`
  -- the SessionStart liveness/degradation notice (byte-identical).
- `scripts/tests/BashHookHelpers.ps1` -- shared, dot-sourced Pester helpers (Git-Bash pin, temp-repo fixture,
  stderr+exit-capturing invoker with env overrides).
- `scripts/tests/agy-liveness-check.Tests.ps1` -- the new hook's full activation matrix.
- `scripts/tests/agy-after-reminder.Tests.ps1` -- the AGY-AFTER hook's full activation category (incl. jq-missing).

**Modified files:**
- `clavity-dotnet/plugin/hooks/agy-after-reminder.sh` + classic copy -- jq-guard retrofit (byte-identical).
- `clavity-dotnet/plugin/hooks/hooks.json` -- add a `SessionStart` block.
- `clavity-classic/plugin/hooks/hooks.json` -- add the liveness hook to the existing `SessionStart` startup group.
- `scripts/check-seed-artifacts-synced.sh` -- enroll the liveness hook (byte-identical list + shared SessionStart diff).
- `scripts/tests/agy-seam-inject.Tests.ps1` -- retrofit the Git-Bash pin + `$HOME` isolation + add the jq-missing test.
- `scripts/tests/check-plugin-namespace.Tests.ps1` -- add the D6 regression tests (git-fixture + self-match).
- `clavity-dotnet/plugin/README.md`, `clavity-classic/plugin/README.md` -- the superpowers-prerequisite line.
- `scripts/README.md` -- update the seed-sync row + Pester-suite count.

---

## Task 1: Shared bash-hook test helper + harness validation spike

**Rationale:** Every hook test in this plan needs to (a) pin Git Bash, (b) run a hook with a synthetic payload
capturing stdout **and** stderr **and** exit code, and (c) override env (`HOME`, `CLAUDE_CONFIG_DIR`,
`CLAUDE_PROJECT_DIR`) with fixtures. The MSYS `HOME` behavior is subtle, so this task builds the helper and
PROVES the mechanism before any real hook test depends on it (mirrors SP-C's F10 validation spike).

**Files:**
- Create: `scripts/tests/BashHookHelpers.ps1`
- Create (this task) / Test: `scripts/tests/BashHookHelpers.Tests.ps1`

- [ ] **Step 1: Write the shared helper**

Create `scripts/tests/BashHookHelpers.ps1`:

```powershell
# Shared Pester helpers for driving the shipped bash hooks with synthetic payloads.
# Dot-source from a *.Tests.ps1 BeforeAll: . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')

function Get-GitBashOrThrow {
    # Claude Code runs plugin hooks with Git Bash on Windows; pin it explicitly. `Get-Command bash` is
    # NON-DETERMINISTIC: locally it resolves to WSL's C:\WINDOWS\System32\bash.exe (own filesystem, cannot
    # run a Windows-path hook); CI (no WSL) resolves to Git Bash. Prefer the standard Git install, else the
    # first PATH bash that is NOT the System32 WSL shim.
    $candidates = @(
        'C:\Program Files\Git\bin\bash.exe',
        'C:\Program Files (x86)\Git\bin\bash.exe'
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $onPath = Get-Command bash -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notmatch '\\System32\\bash\.exe$' } |
        Select-Object -First 1 -ExpandProperty Source
    if ($onPath) { return $onPath }
    throw 'Git Bash not found on PATH; the SP-D hook tests require Git Bash (not WSL bash).'
}

function New-TempRepo {
    # A throwaway git repo so a hook's `git -C "$cwd" rev-parse HEAD` has a real HEAD without touching
    # the real repo. Returns the dir path (Windows form); callers forward-slash it for the payload cwd.
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    & git -C $dir init -q
    & git -C $dir -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit --allow-empty -qm init
    return $dir
}

function Invoke-BashHook {
    # Run a bash hook with a synthetic JSON payload on stdin. Captures stdout, stderr, and the exit code
    # separately (SP-D hooks emit user-visible notices on STDERR with exit 2). $Env overrides are applied
    # process-wide for the call then restored; use ABSOLUTE paths for HOME (MSYS mangles relative values).
    param(
        [Parameter(Mandatory)][string]$HookPath,
        [string]$Payload = '{}',
        [hashtable]$Env = @{}
    )
    $bash = Get-GitBashOrThrow
    $hookPosix = ($HookPath -replace '\\','/')
    $saved = @{}
    foreach ($k in $Env.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $Env[$k])
    }
    $errFile = [IO.Path]::GetTempFileName()
    try {
        $out = ($Payload | & $bash $hookPosix 2>$errFile | Out-String)
        $code = $LASTEXITCODE
        $err = (Get-Content -Raw -LiteralPath $errFile -ErrorAction SilentlyContinue)
        if ($null -eq $err) { $err = '' }
        [pscustomobject]@{ StdOut = $out.Trim(); StdErr = $err.Trim(); ExitCode = $code }
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
        foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    }
}
```

- [ ] **Step 2: Write the failing harness validation test**

Create `scripts/tests/BashHookHelpers.Tests.ps1`:

```powershell
Describe 'BashHookHelpers (harness validation)' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        # A throwaway probe hook that echoes the env it sees + writes to stderr and exits 2.
        $script:probeDir = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-probe-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:probeDir -Force | Out-Null
        $script:probe = Join-Path $script:probeDir 'probe.sh'
        @(
            '#!/usr/bin/env bash',
            'echo "CCD=$CLAUDE_CONFIG_DIR"',
            'if [ -f "$HOME/.claude/marker" ]; then echo "HOME_MARKER_FOUND"; else echo "HOME_MARKER_MISSING"; fi',
            'printf ''%s\n'' "on-stderr" >&2',
            'exit 2'
        ) -join "`n" | Set-Content -LiteralPath $script:probe -Encoding ascii -NoNewline
    }
    AfterAll { Remove-Item -LiteralPath $script:probeDir -Recurse -Force -ErrorAction SilentlyContinue }

    It 'pins a non-WSL Git Bash' {
        (Get-GitBashOrThrow) | Should -Not -Match '\\System32\\bash\.exe$'
    }
    It 'captures stderr and exit code 2 separately from stdout' {
        $r = Invoke-BashHook -HookPath $script:probe
        $r.ExitCode | Should -Be 2
        $r.StdErr   | Should -Match 'on-stderr'
    }
    It 'passes CLAUDE_CONFIG_DIR through to the hook' {
        $r = Invoke-BashHook -HookPath $script:probe -Env @{ CLAUDE_CONFIG_DIR = 'C:\some\cfg\dir' }
        $r.StdOut | Should -Match 'CCD=/c/some/cfg/dir'
    }
    It 'isolates HOME to an absolute fixture dir (MSYS passthrough)' {
        $home2 = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-home-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $home2 '.claude') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $home2 '.claude/marker') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:probe -Env @{ HOME = $home2 }
            $r.StdOut | Should -Match 'HOME_MARKER_FOUND'
        } finally { Remove-Item -LiteralPath $home2 -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 3: Run the harness test to verify the mechanism**

Run: `pwsh -c "Invoke-Pester scripts/tests/BashHookHelpers.Tests.ps1 -Output Detailed"`
Expected: all 4 pass. **If `isolates HOME` FAILS** (MSYS did not honor the absolute HOME): STOP and report
`STATE_MISMATCH: absolute-HOME passthrough failed on <bash version>`. Do not proceed to build HOME-dependent
assertions on a broken mechanism -- the fallback (see Task 3 Step note) is to mark the global-`$HOME/.no-agy`
assertions `-Skip` with a loud reason and rely on the cwd-`.no-agy` + `CLAUDE_CONFIG_DIR` cases, which do not
need HOME.

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/BashHookHelpers.ps1 scripts/tests/BashHookHelpers.Tests.ps1
git commit -m "test(sp-d): shared bash-hook Pester helper + harness validation"
```

---

## Task 2: jq-guard retrofit onto `agy-after-reminder.sh` + full activation category

**Rationale (spec D3):** measured today, with `jq` absent `agy-after-reminder.sh` on a spec/plan path produces
NO output and exits 0 -- a silent drop. Retrofit the same guard SP-C shipped on `agy-seam-inject.sh`, seam-gated
(F3) and separator-agnostic (F7). The change is byte-identical in both plugins (seed-sync `for rel` list).

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-after-reminder.sh` (insert after line 11 `input=$(cat)`)
- Modify: `clavity-classic/plugin/hooks/agy-after-reminder.sh` (identical)
- Create/Test: `scripts/tests/agy-after-reminder.Tests.ps1`

- [ ] **Step 1: Write the full activation test file (some cases fail pre-implementation)**

Create `scripts/tests/agy-after-reminder.Tests.ps1`. The fire/silent/`.no-agy` cases pass against the current
hook; the jq-missing cases FAIL until Step 3. (`jq` cannot be uninstalled per-test, so the jq-missing path is
driven by running the hook with a `PATH` that excludes jq -- an override the helper's `$Env` supports.)

```powershell
Describe 'agy-after-reminder.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-after-reminder.sh'

        # A PATH containing bash+coreutils but NOT jq, to exercise the jq-missing branch. Point at the Git
        # usr/bin (bash, grep, printf) only; jq is not shipped there.
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)                 # ...\Git\bin
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')  # ...\Git\usr\bin

        function New-WritePayload { param([string]$FilePath, [string]$Cwd = '.')
            @{ tool_input = @{ file_path = $FilePath }; cwd = $Cwd } | ConvertTo-Json -Compress
        }
    }

    It 'fires the AGY-AFTER reminder on a spec write' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md')
        $r.StdOut | Should -Match 'AGY-AFTER'
        $r.ExitCode | Should -Be 0
    }
    It 'fires on a plan write' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/plans/y.md')
        $r.StdOut | Should -Match 'AGY-AFTER'
    }
    It 'is silent on a non-artifact path' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'src/main.rs')
        $r.StdOut | Should -BeNullOrEmpty
    }
    It 'is suppressed by .no-agy in cwd' {
        $repo = New-TempRepo
        try {
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $cwd = ($repo -replace '\\','/')
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md' $cwd)
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is suppressed by a global $HOME/.claude/.no-agy' {
        $home2 = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-h-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $home2 '.claude') -Force | Out-Null
        New-Item -ItemType File -Path (Join-Path $home2 '.claude/.no-agy') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs/superpowers/specs/x.md') -Env @{ HOME = $home2 }
            $r.StdOut | Should -BeNullOrEmpty
        } finally { Remove-Item $home2 -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'emits a LOUD jq-missing line on a spec path when jq is absent' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'docs\superpowers\specs\z.md') -Env @{ PATH = $script:NoJqPath }
        $r.StdOut | Should -Match 'guard inactive: missing jq'
    }
    It 'is silent (no jq-missing line) on a non-artifact path when jq is absent' {
        $r = Invoke-BashHook -HookPath $script:Hook -Payload (New-WritePayload 'src/main.rs') -Env @{ PATH = $script:NoJqPath }
        $r.StdOut | Should -BeNullOrEmpty
    }
    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run to verify the jq-missing cases fail**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-after-reminder.Tests.ps1 -Output Detailed"`
Expected: the two "when jq is absent" tests FAIL (current hook emits nothing / exits 0 silently on the spec
path). If the "silent on non-artifact" jq-absent test also passes now, that is fine -- it must stay passing.

> If the `$NoJqPath` (`...\Git\usr\bin`) does not actually contain `bash`/`grep`, the jq-missing tests will
> error with "command not found" instead of exercising the branch. Confirm `bash.exe`, `grep.exe`, `printf`
> resolve under `...\Git\usr\bin`; if bash lives only under `...\Git\bin`, set `$NoJqPath = "$bashDir;<usr\bin>"`
> (both dirs, still no jq) rather than a single dir. This is a fixture detail -- do NOT weaken the assertion.

- [ ] **Step 3: Retrofit the jq guard into both hook copies (byte-identical)**

In `clavity-dotnet/plugin/hooks/agy-after-reminder.sh`, insert this block immediately after line 11
(`input=$(cat)`), before the existing `fp=$(...)` line:

```bash

# --- jq guard (spec Decision 4 / SP-D). jq parses the payload + emits structured JSON. Without it,
# fall back to a separator-agnostic, FIELD-BOUNDED grep on the RAW payload's file_path and, ONLY on a
# spec/plan match, emit a loud hard-coded ASCII line so the AGY-AFTER reminder is never a silent no-op.
# Honor the kill-switch first (global; cwd falls back to the process cwd without jq). ---
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ] || [ -f "$HOME/.claude/.no-agy" ]; then exit 0; fi
  if printf '%s' "$input" | grep -Eq '"(file_path|path)"[[:space:]]*:[[:space:]]*"[^"]*docs[\\/]+superpowers[\\/]+(specs|plans)[\\/]+[^"]*\.md'; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"[AGY-DISCIPLINES] guard inactive: missing jq - the AGY-AFTER panel reminder will not fire on spec/plan writes"}}'
  fi
  exit 0
fi
```

Then copy the ENTIRE file verbatim to `clavity-classic/plugin/hooks/agy-after-reminder.sh` (they must stay
byte-identical; the seed-sync gate enforces this). Use:

```bash
cp clavity-dotnet/plugin/hooks/agy-after-reminder.sh clavity-classic/plugin/hooks/agy-after-reminder.sh
```

> SHAPE NOTE: the loud line rides `additionalContext` (model-relay) exactly as SP-C's PreToolUse guard does --
> this is the correct best-effort surface for a PostToolUse event (the boot-time USER-visible dep warning is
> the SessionStart hook's job, Task 3). Do NOT convert this to stderr+exit-2. The grep is `[\\/]+` (one-or-more)
> so the doubled backslashes of a JSON-escaped Windows path (`docs\\superpowers\\...`) match.

- [ ] **Step 4: Run the full file to verify all pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-after-reminder.Tests.ps1 -Output Detailed"`
Expected: all pass (8 tests).

- [ ] **Step 5: Verify seed-sync still green (byte-identical retrofit)**

Run: `just seed-sync-check`
Expected: `seed agent artifacts in sync (dotnet == classic)`

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-after-reminder.sh clavity-classic/plugin/hooks/agy-after-reminder.sh scripts/tests/agy-after-reminder.Tests.ps1
git commit -m "feat(sp-d): jq-guard retrofit on agy-after-reminder.sh + activation tests"
```

---

## Task 3: New SessionStart liveness hook `agy-liveness-check.sh`

**Rationale (spec D1/D2/D3):** one boot-time liveness surface -- silent on a healthy install, loud (stderr +
`exit 2`) when superpowers is not enabled, when `.no-agy` is suppressing the disciplines, or when `jq` is
missing. Detection reads `enabledPlugins` across CC's settings hierarchy (project-local > project > user),
`^superpowers@`-prefix -> `true`. Corrupt/absent settings -> the possibility-framed advisory (never fail-open).

**Files:**
- Create: `clavity-dotnet/plugin/hooks/agy-liveness-check.sh`
- Create: `clavity-classic/plugin/hooks/agy-liveness-check.sh` (byte-identical copy)
- Create/Test: `scripts/tests/agy-liveness-check.Tests.ps1`

- [ ] **Step 1: Write the failing activation-matrix test**

Create `scripts/tests/agy-liveness-check.Tests.ps1`:

```powershell
Describe 'agy-liveness-check.sh' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
        $repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:Hook = Join-Path $repoRoot 'clavity-dotnet/plugin/hooks/agy-liveness-check.sh'
        $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
        $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')

        # Build a fixture config-dir (the CLAUDE_CONFIG_DIR the hook reads as the USER-scope settings home)
        # with an enabledPlugins map. $Enabled = $true|$false|$null (no key) | 'nofile' (no settings.json).
        function New-ConfigFixture { param($Enabled)
            $d = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-cfg-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            if ($Enabled -ne 'nofile') {
                $ep = @{}
                if ($Enabled -eq $true)  { $ep['superpowers@superpowers-marketplace'] = $true }
                if ($Enabled -eq $false) { $ep['superpowers@superpowers-marketplace'] = $false }
                @{ enabledPlugins = $ep } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $d 'settings.json') -Encoding ascii
            }
            return $d
        }
        # An empty HOME fixture so the hook's `$HOME/.claude/.no-agy` global check never hits the host.
        function New-CleanHome {
            $h = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-home-" + [Guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $h '.claude') -Force | Out-Null
            return $h
        }
        function Payload { param([string]$Cwd = '.') @{ cwd = $Cwd; source = 'startup' } | ConvertTo-Json -Compress }
    }

    It 'is SILENT (exit 0, no stderr) when superpowers is enabled' {
        $cfg = New-ConfigFixture $true; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 0
            $r.StdErr   | Should -BeNullOrEmpty
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ADVISES (stderr + exit 2) when superpowers is disabled' {
        $cfg = New-ConfigFixture $false; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'superpowers not detected'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ADVISES when no settings files exist at all' {
        $cfg = New-ConfigFixture 'nofile'; $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honors the settings hierarchy: project-local disable overrides user enable -> ADVISES' {
        $cfg = New-ConfigFixture $true          # user scope: enabled
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
        @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $false } } | ConvertTo-Json -Depth 5 |
            Set-Content (Join-Path $proj '.claude/settings.local.json') -Encoding ascii
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 2
        } finally { Remove-Item $cfg,$proj,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honors the hierarchy: project-local enable overrides user disable -> SILENT' {
        $cfg = New-ConfigFixture $false         # user scope: disabled
        $proj = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-proj-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $proj '.claude') -Force | Out-Null
        @{ enabledPlugins = @{ 'superpowers@superpowers-marketplace' = $true } } | ConvertTo-Json -Depth 5 |
            Set-Content (Join-Path $proj '.claude/settings.local.json') -Encoding ascii
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $proj }
            $r.ExitCode | Should -Be 0
        } finally { Remove-Item $cfg,$proj,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ADVISES on a corrupt (unreadable) settings.json (never fail-open)' {
        $cfg = Join-Path ([IO.Path]::GetTempPath()) ("sp-d-corrupt-" + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $cfg -Force | Out-Null
        '{ this is not json' | Set-Content (Join-Path $cfg 'settings.json') -Encoding ascii
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'announces .no-agy in cwd (exit 2) and does NOT also emit the superpowers/jq notice' {
        $repo = New-TempRepo; $cfg = New-ConfigFixture $false; $h = New-CleanHome  # superpowers disabled too
        try {
            New-Item -ItemType File -Path (Join-Path $repo '.no-agy') -Force | Out-Null
            $cwd = ($repo -replace '\\','/')
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $cwd) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'suppressed by .no-agy'
            $r.StdErr   | Should -Not -Match 'superpowers not detected'   # no triple-spam
            ($r.StdErr -split "`n").Count | Should -Be 1
        } finally { Remove-Item $repo,$cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'announces a global $HOME/.claude/.no-agy' {
        $cfg = New-ConfigFixture $true
        $h = New-CleanHome
        New-Item -ItemType File -Path (Join-Path $h '.claude/.no-agy') -Force | Out-Null
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ CLAUDE_CONFIG_DIR = $cfg; HOME = $h; CLAUDE_PROJECT_DIR = $cfg }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'suppressed by .no-agy'
        } finally { Remove-Item $cfg,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'emits ONE jq-missing warning (exit 2) when jq is absent' {
        $h = New-CleanHome
        try {
            $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $r.ExitCode | Should -Be 2
            $r.StdErr   | Should -Match 'missing jq'
            ($r.StdErr -split "`n").Count | Should -Be 1
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'ships as pure ASCII' {
        ($([IO.File]::ReadAllBytes($script:Hook)) | Where-Object { $_ -gt 127 }).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run to verify it fails (hook does not exist yet)**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-liveness-check.Tests.ps1 -Output Detailed"`
Expected: FAIL -- the hook file does not exist, so every case errors ("No such file or directory").

- [ ] **Step 3: Write the hook**

Create `clavity-dotnet/plugin/hooks/agy-liveness-check.sh` (LF endings, pure ASCII):

```bash
#!/usr/bin/env bash
# AGY-DISCIPLINES liveness/degradation notice (plugin-shipped, SP-D / spec Decision 3). SessionStart(startup):
# the agy-driving disciplines auto-fire only when superpowers is installed+enabled; if it is not -- or a
# .no-agy kill-switch is suppressing them -- the user must be told LOUDLY at boot, else the disciplines die
# silently. This is the ONE boot-time liveness surface (superpowers presence + .no-agy announce + jq guard).
#
# EMISSION = stderr + `exit 2`. For a SessionStart hook that is the ONLY documented USER-visible surface: the
# stderr renders in the transcript and execution CONTINUES (exit 2 is non-blocking for SessionStart, unlike
# PreToolUse). additionalContext/stdout would be injected into Claude's CONTEXT only and silently absorbed at
# boot (no user turn) -- the silent-drop Decision 3 forbids.
#
# EXIT-CODE CONTRACT (three outcomes): (1) healthy / nothing to say -> exit 0, no stderr; (2) a DETECTION
# OUTCOME warranting a notice (superpowers not-live incl. corrupt/unreadable settings, .no-agy active, or jq
# missing) -> the line on stderr + exit 2; (3) a genuine UNEXPECTED internal error OUTSIDE detection -> falls
# through to the terminal `exit 0` (fail-open; `set +e` continues past it). NO blanket `trap ... ERR` -- it
# would swallow the settings-parse path and drop the advisory.
# Byte-identical across both driver plugins (kept honest by the seed-sync gate).
set +e
input=$(cat)

# --- jq guard. jq is needed to parse cwd + merge settings. Without it, honor the kill-switch (global +
# process cwd) then emit ONE loud dep warning (never silent; we cannot do the superpowers check without jq). ---
if ! command -v jq >/dev/null 2>&1; then
  if [ -f "./.no-agy" ]; then
    printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at ./.no-agy" >&2
    exit 2
  fi
  if [ -f "$HOME/.claude/.no-agy" ]; then
    printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $HOME/.claude/.no-agy" >&2
    exit 2
  fi
  printf '%s\n' "[AGY-DISCIPLINES] guard inactive: missing jq - cannot verify the disciplines will auto-fire; install jq" >&2
  exit 2
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)

# --- .no-agy kill-switch: announce LOUDLY (naming the path) then STOP. NOT a silent early-exit (that
# reintroduces the silent-kill Decision 3 forbids); NOT a fall-through to the superpowers/jq notices (that
# would triple-spam one boot). One announce, then exit. ---
if [ -f "$cwd/.no-agy" ]; then
  printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $cwd/.no-agy" >&2
  exit 2
fi
if [ -f "$HOME/.claude/.no-agy" ]; then
  printf '%s\n' "[AGY-DISCIPLINES] suppressed by .no-agy at $HOME/.claude/.no-agy" >&2
  exit 2
fi

# --- superpowers enabled-check across Claude Code's settings hierarchy (more-specific scope wins per plugin
# key): project-local > project > user. Read ONLY files that exist (a missing settings file at a scope is
# NORMAL, not a not-live signal). superpowers is live iff the merged enabledPlugins has a key matching
# ^superpowers@ resolving to true (PREFIX match; the marketplace suffix is not guaranteed). Absent / false /
# corrupt-present -> the possibility-framed advisory (fail-toward-loud). ---
config_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
proj_dir="${CLAUDE_PROJECT_DIR:-$cwd}"
user_settings="$config_dir/settings.json"
proj_settings="$proj_dir/.claude/settings.json"
local_settings="$proj_dir/.claude/settings.local.json"

# Precedence: user (lowest) first, project-local (highest) last, so the later deep-merge overrides per key.
present=()
for f in "$user_settings" "$proj_settings" "$local_settings"; do
  [ -f "$f" ] && present+=("$f")
done

live=0
if [ "${#present[@]}" -gt 0 ]; then
  if result=$(jq -s 'map(.enabledPlugins // {}) | reduce .[] as $m ({}; . * $m)
                     | to_entries | any(.[]; (.key | startswith("superpowers@")) and .value)' \
              "${present[@]}" 2>/dev/null) && [ "$result" = "true" ]; then
    live=1
  fi
fi

if [ "$live" = "1" ]; then
  exit 0   # healthy install: SILENT (an every-session banner would train the user to ignore it)
fi

# Not live: superpowers not detected as enabled (absent, disabled, corrupt settings, or CC changed the
# settings shape). Emit the advisory as a POSSIBILITY, never "disabled" as a certainty.
printf '%s\n' "[AGY-DISCIPLINES] superpowers not detected as enabled - the agy disciplines will not auto-fire. Install/enable superpowers, or invoke agy-first / agy-capstone manually." >&2
exit 2
```

Then copy verbatim to the classic plugin:

```bash
cp clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh
```

> ORACLE NOTE: the stderr+exit-2 emission is the spec's D2 contract, itself confirmed against the Claude Code
> hooks docs (a SessionStart hook's stdout/`additionalContext` is context-only; stderr+exit-2 is the only
> user-visible surface). Do NOT "simplify" any notice to stdout/`additionalContext` -- that silently drops it.

- [ ] **Step 4: Run to verify all pass**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-liveness-check.Tests.ps1 -Output Detailed"`
Expected: all pass (10 tests). If the two `.no-agy` global / `HOME`-dependent cases fail on a box where Task 1
flagged `STATE_MISMATCH` on HOME passthrough, apply the Task-1 fallback (mark just those two `-Skip` with the
loud reason) -- the cwd-`.no-agy` + `CLAUDE_CONFIG_DIR` hierarchy cases do not depend on HOME and must pass.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-liveness-check.sh clavity-classic/plugin/hooks/agy-liveness-check.sh scripts/tests/agy-liveness-check.Tests.ps1
git commit -m "feat(sp-d): SessionStart liveness/degradation notice hook (stderr+exit2)"
```

---

## Task 4: Register the liveness hook in both `hooks.json` + anti-drift SessionStart diff

**Rationale (spec D2/D5):** the hook must be registered as a SessionStart/`startup` hook in BOTH plugins, and
the seed-sync gate must compare only the SHARED liveness entry (classic legitimately carries its extra
`agy-drive-session-reset.sh` entry). To sidestep any "two same-matcher groups" ambiguity, the liveness hook
joins classic's EXISTING startup group's `hooks[]` array; dotnet gets a fresh startup group.

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/hooks.json`
- Modify: `clavity-classic/plugin/hooks/hooks.json`
- Modify: `scripts/check-seed-artifacts-synced.sh`

- [ ] **Step 1: Add the SessionStart block to `clavity-dotnet/plugin/hooks/hooks.json`**

Insert a `SessionStart` array after the existing `PostToolUse` array (add a comma after the `PostToolUse`
array's closing `]`). The result's `hooks` object:

```json
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-after-reminder.sh\"" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh\"" }
        ]
      }
    ]
```

- [ ] **Step 2: Add the liveness hook to classic's EXISTING startup group**

In `clavity-classic/plugin/hooks/hooks.json`, the `SessionStart[0].hooks` array currently holds only the
reset hook. Add the liveness hook as a second entry (a comma after the reset entry):

```json
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-drive-session-reset.sh\"" },
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-liveness-check.sh\"" }
        ]
      }
    ]
```

- [ ] **Step 3: Verify both manifests are valid JSON**

Run: `jq -e . clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 4: Enroll the liveness hook in the seed-sync gate**

In `scripts/check-seed-artifacts-synced.sh`:

(a) Add the liveness script to the byte-identical `for rel in` list (after the `hooks/agy-seam-inject.sh` line,
line 15):

```bash
  hooks/agy-seam-inject.sh \
  hooks/agy-liveness-check.sh \
```

(b) Add a SHARED-SessionStart-entry diff immediately after the existing PreToolUse diff block (after line 40).
It extracts ONLY the liveness hook object across all SessionStart groups, so classic's reset entry is ignored:

```bash
# The SessionStart block diverges by design (classic carries a variant-specific driver-guidance reset that
# dotnet lacks), so compare ONLY the SHARED liveness hook object, identified by its command referencing
# agy-liveness-check.sh. It must be byte-identical across both plugins.
sp_sel='[.hooks.SessionStart[]?.hooks[]? | select(.command | test("agy-liveness-check\\.sh"))]'
if ! diff -q <(jq -S "$sp_sel" "$D/hooks/hooks.json") \
             <(jq -S "$sp_sel" "$C/hooks/hooks.json") >/dev/null 2>&1; then
  echo "SEED-DRIFT: hooks/hooks.json SessionStart (shared liveness hook) differs between the two plugins" >&2
  status=1
fi
```

- [ ] **Step 5: Verify seed-sync passes with the enrollment**

Run: `just seed-sync-check`
Expected: `seed agent artifacts in sync (dotnet == classic)`

- [ ] **Step 6: Prove the new SessionStart diff BITES (drift probe)**

Temporarily perturb the classic liveness command, confirm the gate fails, then restore:

```bash
sed -i 's#hooks/agy-liveness-check.sh#hooks/agy-liveness-check-BROKEN.sh#' clavity-classic/plugin/hooks/hooks.json
just seed-sync-check; echo "exit=$?"   # expect: SEED-DRIFT ... SessionStart (shared liveness hook) ... exit=1
git checkout -- clavity-classic/plugin/hooks/hooks.json
just seed-sync-check                    # expect: back to in-sync
```

Expected: the perturbed run prints the SessionStart SEED-DRIFT line and exits 1; after restore, in sync.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json scripts/check-seed-artifacts-synced.sh
git commit -m "feat(sp-d): register liveness hook in both plugins + seed-sync SessionStart diff"
```

---

## Task 5: Retrofit the Git-Bash pin + $HOME isolation onto the SP-C smoke + add its jq-missing test

**Rationale (spec D4):** `agy-seam-inject.Tests.ps1` uses `Get-Command bash` (fragile: WSL locally) and does
not isolate `$HOME`, so a developer with a real global `~/.claude/.no-agy` gets a spurious failure. Retrofit it
onto the shared helper (Git-Bash pin + `$HOME` isolation) and add the jq-missing loud-line case SP-C deferred.

**Files:**
- Modify: `scripts/tests/agy-seam-inject.Tests.ps1`

- [ ] **Step 1: Replace the BeforeAll bash/helper wiring with the shared helper**

Replace the current `BeforeAll` body (lines 7-35) so it dot-sources `BashHookHelpers.ps1` and uses
`Invoke-BashHook`/`New-TempRepo` instead of the local `$Bash`/`Invoke-Hook`/`New-TempRepo`. New `BeforeAll`:

```powershell
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Hook = Join-Path $RepoRoot 'clavity-dotnet/plugin/hooks/agy-seam-inject.sh'
    $bashDir = Split-Path -Parent (Get-GitBashOrThrow)
    $script:NoJqPath = (Join-Path (Split-Path -Parent $bashDir) 'usr\bin')
    # An empty HOME fixture so a real global ~/.claude/.no-agy on the dev box can't suppress the hook mid-test.
    $script:CleanHome = Join-Path ([IO.Path]::GetTempPath()) ("sp-c-home-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $script:CleanHome '.claude') -Force | Out-Null

    function Invoke-Hook { param([string]$Skill, [string]$Cwd = '.')
        $payload = @{ tool_input = @{ skill = $Skill }; cwd = $Cwd } | ConvertTo-Json -Compress
        (Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ HOME = $script:CleanHome }).StdOut
    }
}
AfterAll { Remove-Item -LiteralPath $script:CleanHome -Recurse -Force -ErrorAction SilentlyContinue }
```

The existing `It` blocks call `Invoke-Hook -Skill ... -Cwd ...` and inspect the returned string -- they keep
working unchanged against the new `Invoke-Hook` shim (it returns `.StdOut`). Delete the now-unused local
`New-TempRepo` (the helper provides it) -- confirm no other reference remains in the file.

- [ ] **Step 2: Add the jq-missing loud-line test (before the pure-ASCII `It`)**

```powershell
    It 'emits the LOUD jq-missing line on a seam match when jq is absent' {
        $repo = New-TempRepo
        try {
            $payload = @{ tool_input = @{ skill = 'superpowers:brainstorming' }; cwd = ($repo -replace '\\','/') } | ConvertTo-Json -Compress
            $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ PATH = $script:NoJqPath; HOME = $script:CleanHome }
            $r.StdOut | Should -Match 'guard inactive: missing jq'
        } finally { Remove-Item $repo -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'is silent (no jq-missing line) on a NON-seam skill when jq is absent' {
        $payload = @{ tool_input = @{ skill = 'superpowers:writing-plans' }; cwd = '.' } | ConvertTo-Json -Compress
        $r = Invoke-BashHook -HookPath $script:Hook -Payload $payload -Env @{ PATH = $script:NoJqPath; HOME = $script:CleanHome }
        $r.StdOut | Should -BeNullOrEmpty
    }
```

- [ ] **Step 3: Run the retrofitted smoke**

Run: `pwsh -c "Invoke-Pester scripts/tests/agy-seam-inject.Tests.ps1 -Output Detailed"`
Expected: all pass (the original 7 + the 2 new jq cases).

- [ ] **Step 4: Commit**

```bash
git add scripts/tests/agy-seam-inject.Tests.ps1
git commit -m "test(sp-d): pin Git Bash + isolate HOME on SP-C smoke; add jq-missing case"
```

---

## Task 6: SP-0 namespace-gate regression tests (owner-folded leftover)

**Rationale (spec D6):** SP-0's Phase-4 hardened `check-plugin-namespace.ps1` to (a) ignore gitignored build
artifacts and (b) self-exclude its own docstring/fixture -- fixes recorded but never locked by a regression
test. The existing suite's fixture is NON-git; the gitignore behavior needs a git fixture with a `.gitignore`.

**Files:**
- Modify: `scripts/tests/check-plugin-namespace.Tests.ps1`

- [ ] **Step 1: Add a git-fixture helper + the two regression tests**

Inside the existing `Describe 'check-plugin-namespace'` block, add to `BeforeAll` a git-fixture builder
(alongside `New-CleanFixture`), then add two `It` blocks. Add this function inside `BeforeAll`:

```powershell
        function New-GitCleanFixture {
            # A CLEAN renamed fixture that is a REAL git repo with a .gitignore, so rg's gitignore-respect
            # (which only engages inside a git repo scanned from within) is exercised.
            $t = New-CleanFixture
            & git -C $t init -q
            & git -C $t -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= add -A
            & git -C $t -c user.email='t@t' -c user.name='t' -c commit.gpgsign=false -c core.hooksPath= commit -qm init
            return $t
        }
```

Then add these `It` blocks:

```powershell
    It 'does NOT flag an old plugin identity that lives only in a GITIGNORED build artifact' {
        $t = New-GitCleanFixture
        try {
            'build/generated/' | Set-Content (Join-Path $t '.gitignore')
            New-Item -ItemType Directory -Force -Path (Join-Path $t 'build/generated') | Out-Null
            # A gitignored generated manifest carrying the OLD identity in a plugins[].name -- must be ignored.
            '{ "name": "clavity-dotnet", "owner": { "name": "x" }, "plugins": [ { "name": "clavity-dotnet" } ] }' |
                Set-Content (Join-Path $t 'build/generated/marketplace.install.json')
            & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because "a gitignored build artifact must not fail the gate"
        } finally { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'does NOT flag its own docstring/fixture patterns (self-match exclusion)' {
        $t = New-GitCleanFixture
        try {
            # A file named like the gate itself, containing the forbidden colon-namespace pattern in a comment
            # (as the real gate's docstring does). The self-exclude globs must keep it from flagging itself.
            New-Item -ItemType Directory -Force -Path (Join-Path $t 'scripts') | Out-Null
            '# example forbidden ref clavity-dotnet:driving documented in the gate docstring' |
                Set-Content (Join-Path $t 'scripts/check-plugin-namespace.ps1')
            & pwsh -File $script:gate -Root $t 2>&1 | Out-Null
            $LASTEXITCODE | Should -Be 0 -Because "the gate must exclude its own two files from the text scans"
        } finally { Remove-Item $t -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [ ] **Step 2: Run to verify the regression tests pass against the current (already-hardened) gate**

Run: `pwsh -c "Invoke-Pester scripts/tests/check-plugin-namespace.Tests.ps1 -Output Detailed"`
Expected: all pass (existing 6 + 2 new). These lock behavior the gate ALREADY has -- they must pass now; if
either FAILS, the gate regressed and that is the finding (do NOT edit the gate to pass without confirming the
SP-0 hardening is intact).

- [ ] **Step 3: Commit**

```bash
git add scripts/tests/check-plugin-namespace.Tests.ps1
git commit -m "test(sp-d): SP-0 namespace-gate regression (gitignored artifact + self-match)"
```

---

## Task 7: Prerequisite docs + anti-drift README enrollment decision

**Rationale (spec D5/D5b):** the superpowers-prerequisite messaging lands in each driver plugin's
`plugin/README.md`; the `scripts/README.md` seed-sync row and suite count are updated to reflect the new hook.

**Files:**
- Modify: `clavity-dotnet/plugin/README.md`
- Modify: `clavity-classic/plugin/README.md`
- Modify: `scripts/README.md`

- [ ] **Step 1: Add the prerequisite note to `clavity-dotnet/plugin/README.md`**

In the `## Install / registration` section, after the existing agy-autotrain sentence (line 26), add:

```markdown

> **superpowers prerequisite (auto-fire only).** The agy disciplines (agy-first / agy-capstone) AUTO-FIRE via
> a superpowers SessionStart/PreToolUse hook. superpowers is required only for that auto-fire; without it the
> disciplines stay manually invokable (`agy-first` / `agy-capstone`). A boot-time notice tells you if it is
> not detected as enabled.
```

- [ ] **Step 2: Add the same note to `clavity-classic/plugin/README.md`**

In its `## Install / registration` section, after the plugin-install step (after line 53), add the identical
blockquote from Step 1.

- [ ] **Step 3: Update `scripts/README.md` seed-sync row + suite count**

Replace the seed-sync row (line 37) so it names the liveness hook + SessionStart shared block:

```markdown
| `check-seed-artifacts-synced.sh` | Fail if the seed agent artifacts (adversarial-panel-review skill, the AGY-AFTER, auto-fire seam-inject, and SessionStart liveness hooks, the two driver knowledge manuals, `hooks.json`'s shared PostToolUse + PreToolUse blocks + the shared SessionStart liveness entry) drift between the two driver plugins | `just seed-sync-check` |
```

Update the `tests/` subdirectory line (line 59) to the correct current count. After SP-D there are 4 new suites
(`BashHookHelpers.Tests.ps1`, `agy-after-reminder.Tests.ps1`, `agy-liveness-check.Tests.ps1`) plus the extended
existing ones; count the actual `*.Tests.ps1` files and write that number:

```markdown
- `tests/` — Pester suites covering the scripts in this folder (count via `ls scripts/tests/*.Tests.ps1`), run via `just test-scripts`.
```

> D5b enrollment decision: the README prerequisite note is prose that is NOT load-bearing the way a hook script
> is, so it is deliberately NOT enrolled in the seed-sync gate (spec D5b: README drift is low-priority). No
> seed-sync change for the READMEs.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/plugin/README.md clavity-classic/plugin/README.md scripts/README.md
git commit -m "docs(sp-d): superpowers-prerequisite note + seed-sync coverage row"
```

---

## Task 8: Definition-of-Done verification + AGY-CAPSTONE handoff

**Rationale:** prove the full DoD before declaring SP-D complete; then the epic-closing AGY-CAPSTONE runs over
the committed SP-D range.

**Files:** none (verification only)

- [ ] **Step 1: Full script test suite green**

Run: `just test-scripts`
Expected: 0 failed. Confirm the new suites (`BashHookHelpers`, `agy-after-reminder`, `agy-liveness-check`) and
the extended ones (`agy-seam-inject`, `check-plugin-namespace`) all appear and pass.

- [ ] **Step 2: Seed-sync green**

Run: `just seed-sync-check`
Expected: `seed agent artifacts in sync (dotnet == classic)`.

- [ ] **Step 3: Manual smoke of the liveness hook (all four states)**

```bash
BASH="/c/Program Files/Git/bin/bash.exe"
H=/c/Program\ Files/Git/bin/bash.exe
# 1. superpowers enabled (real user settings) -> SILENT, exit 0
printf '{"cwd":".","source":"startup"}' | "$BASH" clavity-dotnet/plugin/hooks/agy-liveness-check.sh; echo "exit=$?"
# 2. superpowers absent -> advisory on stderr, exit 2 (point CLAUDE_CONFIG_DIR at an empty dir)
mkdir -p /tmp/sp-d-empty; CLAUDE_CONFIG_DIR=/tmp/sp-d-empty CLAUDE_PROJECT_DIR=/tmp/sp-d-empty printf '{"cwd":".","source":"startup"}' | "$BASH" clavity-dotnet/plugin/hooks/agy-liveness-check.sh; echo "exit=$?"
# 3. .no-agy present -> announce, exit 2
mkdir -p /tmp/sp-d-noagy && touch /tmp/sp-d-noagy/.no-agy; printf '{"cwd":"/tmp/sp-d-noagy","source":"startup"}' | "$BASH" clavity-dotnet/plugin/hooks/agy-liveness-check.sh; echo "exit=$?"
# 4. jq missing -> one warning, exit 2 (run with a PATH lacking jq)
PATH="/c/Program Files/Git/usr/bin" printf '{"cwd":".","source":"startup"}' | "$BASH" clavity-dotnet/plugin/hooks/agy-liveness-check.sh; echo "exit=$?"
```

Expected: (1) no output, exit 0; (2) advisory line, exit 2; (3) `.no-agy` announce, exit 2; (4) jq-missing
line, exit 2. (Adjust the `PATH` in case 4 if jq is reachable there; the goal is a jq-less PATH.)

- [ ] **Step 4: Confirm the SP-D commit range + clean tree**

Run: `git log --oneline -8 && git status --short`
Expected: the 7 SP-D commits (Tasks 1-7) present, working tree clean.

- [ ] **Step 5: AGY-CAPSTONE over the committed SP-D range**

Invoke the `agy-capstone` skill: send agy the committed SP-D diff/range under adversarial lenses citing
file:line; VERIFY every finding BY MEASUREMENT before folding (agy states false claims confidently); fold the
real ones + commit fixes; RE-RUN a fresh round with a do-not-re-raise ledger; repeat UNTIL a full round is
GREEN (human-adjudicated). Only the owner may waive the round cap. This gates SP-D (and the epic) completion.

- [ ] **Step 6: Epic close**

Once AGY-CAPSTONE is GREEN, SP-D is complete and the ship-agy-workflow epic is ready for ONE combined release
(owner-owned push + the SP-0 merge). Do NOT push -- the owner owns every push.

---

## Self-review (spec coverage, placeholders, type consistency)

**Spec coverage (6 scope items + DoD):**
- Item 1 (SessionStart liveness/degradation + `.no-agy` announce) -> Task 3 (hook) + Task 4 (registration).
- Item 2 (jq-guard retrofit + honest bash limit) -> Task 2 (retrofit); the bash-missing limit is documented
  in the hook headers + Task 7 docs (a bash hook cannot detect its own missing interpreter -- doc/install layer).
- Item 3 (comprehensive hook-activation tests) -> Tasks 2, 3, 5 (all three hooks, incl. jq-missing + stderr/exit-2).
- Item 4 (anti-drift enrollment) -> Task 4 (byte-identical list + shared SessionStart diff, proven-to-bite).
- Item 5 (prerequisite docs) -> Task 7.
- Item 6 (SP-0 namespace-gate regression) -> Task 6.
- DoD (test-scripts green, seed-sync green + proven-to-bite, manual smoke, capstone) -> Task 4 Step 6 + Task 8.

**Placeholder scan:** no TBD/TODO; every code step shows complete content; the only conditional is the Task-1
HOME-passthrough fallback, which is fully specified (mark the two HOME-only assertions `-Skip`).

**Type/name consistency:** helper names (`Get-GitBashOrThrow`, `New-TempRepo`, `Invoke-BashHook`) are defined
in Task 1 and used identically in Tasks 2/3/5/6; the hook script name `agy-liveness-check.sh` is identical
across Tasks 3/4/7 and the seed-sync selector; the emit prefix `[AGY-DISCIPLINES]` and the assertion substrings
(`superpowers not detected`, `suppressed by .no-agy`, `guard inactive: missing jq`) match between the hook
bodies (Tasks 2/3) and the test assertions (Tasks 2/3/5).

**Exhaustiveness self-audit:** all six spec items map to tasks; DoD maps to Task 8; the two measured spec-risk
areas (bash non-determinism, HOME passthrough) are pinned in Task 1 with a documented fallback rather than left
vague. Remaining judgment deferred to execution: the exact `...\Git\usr\bin` jq-less PATH is a fixture detail
called out in Task 2 Step 2 with a fix if bash is not co-located there.
