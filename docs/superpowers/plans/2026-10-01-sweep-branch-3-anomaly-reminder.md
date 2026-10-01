# ROADMAP sweep Branch 3 - `agy-anomaly-reminder.sh` (section 32) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close ROADMAP section 32 in the SessionStart hook `agy-anomaly-reminder.sh` (both driver plugins): a FILE `cwd` must not defeat the `.no-agy` kill-switch (32a), and an empty `PATH` must not write to stderr (32b).

**Architecture:** Two small edits to one bash hook, made in `clavity-dotnet/plugin/hooks/` and COPIED byte-for-byte to `clavity-classic/plugin/hooks/` (pinned identical by `scripts/tests/plugin-hooks-payload.Tests.ps1` and `scripts/check-seed-artifacts-synced.sh`). Four Pester rows in `scripts/tests/agy-anomaly-reminder.Tests.ps1`, each proven non-vacuous by a logic mutant. Then a plugin version bump (a same-version reinstall is a measured no-op) and the owner's reinstall.

**Tech Stack:** bash (Git Bash) hook, jq, PowerShell 7 + Pester 6, `just`, lefthook, Inno Setup (ISCC).

**Spec:** `docs/superpowers/specs/2026-09-29-roadmap-sweep-sequence-design.md` ("The sequence" (a)-(f), "Closing a header", "Plugin-pair branches"). Branch 3 = section 32 only (section 41 stays deferred, owner ruling at step 0; section 57 is its own Branch 14).

## Owner rulings this plan implements (2026-09-30, after AGY-FIRST `.clavity/seams/branch3-forks.md` + `-negotiate.md`, ALIGNED)

- **32a:** resolve a non-directory `cwd` to its directory BEFORE the root walk, on BOTH paths, with the exact line the sibling hook already uses (`clavity-dotnet/plugin/hooks/agy-seam-inject.sh:84`): parameter expansion, no external command.
- **32b:** replace `input=$(cat)` with the bash builtin `IFS= read -r -d '' input`, so no external command runs before the jq check. No `2>/dev/null` suppression.
- **Order:** this branch runs after Branch 15 (merged `b1228a86`), cut from that sha.

## Re-measurement at the branch start (spec step (a)), measured 2026-09-30, re-checked on `b1228a86`

- **32a REPRODUCES.** Repo with `.no-agy` at its root, payload `cwd=<root>/afile.txt`, `PATH=/usr/bin` (no jq): the hook prints the `guard inactive: missing jq` envelope. Control `cwd=<root>`: silent. On the jq path the same file cwd is silent - but only by accident (masked by `[ -f "$f" ] || exit 0`), and for the same reason a file cwd also MISSES the root's anomalies file and never reports (`.clavity/scratch/branch3/probe-a.sh`).
- **32b REPRODUCES**, with the mechanism the peer originally predicted: `/usr/bin/bash <hook>` under `PATH=` writes `agy-anomaly-reminder.sh: line 33: cat: command not found`. The ROADMAP's "the error comes from bash itself" was a PROBE artifact (`PATH='' bash <hook>` cannot find `bash`).
- **The test helper cannot reach 32b.** `Get-GitBashOrThrow` returns `C:\Program Files\Git\bin\bash.exe`, a WRAPPER that re-adds `/mingw64/bin:/usr/bin` to `PATH`: measured, a child launched through `Invoke-BashHook -Env @{ PATH = '' }` sees `/mingw64/bin:/usr/bin:/c/Users/user/bin`, and the UNFIXED hook writes no stderr. Claude Code itself runs `C:\Program Files\Git\usr\bin\bash.exe` (`$BASH` = `/usr/bin/bash`), which does NOT rewrite `PATH`. So the 32b row must launch `usr\bin\bash.exe` directly (`.clavity/scratch/branch3/probe-helper-path.ps1`).
- **The builtin read is safe here.** Under `PATH=''`, `IFS= read -r -d '' input` returns rc=1 at EOF with the WHOLE payload, multi-line JSON and backslashes intact; it keeps a trailing newline that `$(cat)` strips, which neither jq nor the degraded regex reads (`.clavity/scratch/branch3/probe-read.sh`).

## Standing rules for every task (paste into every dispatch)

- **Step 0 - STATE VERIFICATION.** Open every file the task names and confirm the quoted "current" text is there, verbatim. If it differs, STOP and report `STATE_MISMATCH: <what>`. Locate by quoted text, never by line number alone.
- **SHAPE-DIVERGENCE STOP.** If making something work would change the shape, type or encoding of any value given here, STOP and report `[original] -> [yours] because <reason>`.
- **Tests are already written in this plan - implement until they pass.** Never edit a test to match the code; if a test looks wrong, STOP and report the conflict.
- **Write every script or probe with the Write tool.** The Bash tool on this box drops one backslash from `\\` and runs backticks.
- **Never run two Pester suites at once.** A run with no `Tests Passed:` line was ABORTED, not green.
- **Mirror = copy.** After editing the dotnet hook: `Copy-Item -LiteralPath clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh -Destination clavity-classic/plugin/hooks/agy-anomaly-reminder.sh -Force`, then confirm `(Get-FileHash <a>).Hash -eq (Get-FileHash <b>).Hash`.
- **ASCII only** in the hook and in every new test line. Since Branch 15 every text file is LF; keep it so.
- **Stage explicit paths only; never commit anything under `.clavity/`.** End each commit message with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **ANOMALIES** and **FILES** clauses from the `open-issues` skill go in every implementer dispatch.

## How to run the suite

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-anomaly-reminder.Tests.ps1 -Output Detailed -CI"
```

Run it from a shell whose `PATH` puts Git Bash first (the Bash tool does). Expected: `Tests Passed: <N>, Failed: 0`. A mutant is proven by running the same command with the mutant applied and seeing the NAMED row fail; `git add` your real edits BEFORE any mutant, restore with `git checkout -- <file>`.

---

### Task 1: Failing tests first (32a and 32b)

**Files:** Modify `scripts/tests/agy-anomaly-reminder.Tests.ps1`.

- [x] **Step 1: Add the four rows** directly after the row `It 'DOES warn from that subdirectory without .no-agy when jq is absent (degraded positive control)' {` ... its closing `}` (the row whose body matches `'guard inactive: missing jq'`). Insert exactly:

```powershell
    # --- ROADMAP section 32a: a FILE cwd. Claude Code sends a directory, but the payload is not ours, and
    # `.no-agy` is the user-facing off switch. Before the fix the walk was skipped for a file cwd, so both
    # kill-switch probes became <file>/.no-agy and missed; on the degraded path nothing else stopped the
    # notice, and on the jq path the same miss also hid the root's anomalies file.
    It 'honours a root .no-agy when cwd is a FILE, on the DEGRADED (no jq) path (section 32a)' {
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
            $f = Join-Path $r 'afile.txt'; Set-Content -LiteralPath $f -Value 'x' -Encoding ascii
            $x = Invoke-Hook -Payload (RawPayload $f) -Env @{ PATH = $script:NoJqPath; HOME = $h }
            $x.StdOut   | Should -BeNullOrEmpty -Because 'a file cwd must resolve to its directory, so the root opt-out still fires'
            $x.ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'REPORTS the root anomalies when cwd is a FILE, on the jq path (section 32a)' {
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            $f = Join-Path $r 'afile.txt'; Set-Content -LiteralPath $f -Value 'x' -Encoding ascii
            $x = Invoke-Hook -Payload (RawPayload $f) -Env @{ HOME = $h }
            $x.StdOut   | Should -Match '1 untriaged' -Because 'a file cwd must reach the repo root, where the anomalies file lives'
            $x.ExitCode | Should -Be 0
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }
    It 'honours a root .no-agy when cwd is a FILE, on the jq path (pairs the REPORTS row above)' {
        $r = New-RepoWithAnomaly; $h = New-CleanHome
        try {
            New-Item -ItemType File -Path (Join-Path $r '.no-agy') -Force | Out-Null
            $f = Join-Path $r 'afile.txt'; Set-Content -LiteralPath $f -Value 'x' -Encoding ascii
            $x = Invoke-Hook -Payload (RawPayload $f) -Env @{ HOME = $h }
            $x.StdOut | Should -BeNullOrEmpty -Because 'the same repo that reports above must go silent under its root opt-out'
        } finally { Remove-Item $r,$h -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # --- ROADMAP section 32b: an EMPTY PATH. Invoke-BashHook cannot reach this: Get-GitBashOrThrow returns
    # Git\bin\bash.exe, a wrapper that puts /mingw64/bin:/usr/bin back on PATH (measured 2026-09-30), so the
    # unfixed hook found `cat` and stayed silent there. Claude Code runs Git\usr\bin\bash.exe, which does not,
    # so this row launches THAT binary with an environment whose PATH is empty. (MSYS hands the child PATH as
    # `=`, a relative directory that does not exist - measured; no command resolves, which is the condition.)
    # FAILING CONTROL, measured 2026-10-01 with this exact launcher: the unfixed hook writes
    # `line 33: cat: command not found` to stderr.
    It 'writes NOTHING to stderr with an EMPTY PATH, and still says jq is missing (section 32b)' {
        $h = New-CleanHome
        $usrBash = Join-Path (Split-Path -Parent (Split-Path -Parent (Get-GitBashOrThrow))) 'usr\bin\bash.exe'
        try {
            Test-Path -LiteralPath $usrBash | Should -BeTrue -Because 'the row needs the non-wrapper Git Bash'
            $psi = [Diagnostics.ProcessStartInfo]::new($usrBash)
            $psi.ArgumentList.Add(($script:Hook -replace '\\', '/'))
            $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.Environment['PATH'] = ''
            $psi.Environment['HOME'] = $h
            $p = [Diagnostics.Process]::Start($psi)
            $p.StandardInput.Write('{"cwd":".","source":"startup"}'); $p.StandardInput.Close()
            $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
            $err        | Should -BeNullOrEmpty -Because 'no external command may run before the jq check'
            $out        | Should -Match 'guard inactive: missing jq' -Because 'with nothing on PATH, jq IS missing - the designed notice'
            $p.ExitCode | Should -Be 0
        } finally { Remove-Item $h -Recurse -Force -ErrorAction SilentlyContinue }
    }
```

- [x] **Step 2: Run the suite. Expected: FAIL** on exactly three rows - `honours a root .no-agy when cwd is a FILE, on the DEGRADED ...` (stdout carries the envelope), `REPORTS the root anomalies when cwd is a FILE, on the jq path ...` (stdout empty), and `writes NOTHING to stderr with an EMPTY PATH ...` (stderr `line 33: cat: command not found`). The jq-path `.no-agy` pairing row PASSES before the fix (masked), which is why it is a pairing row and not a proof. Any other outcome: STOP and report.

### Task 2: The fix

**Files:** Modify `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh`; copy to `clavity-classic/plugin/hooks/agy-anomaly-reminder.sh`.

- [x] **Step 1 (32b):** replace the line `input=$(cat)` (currently `:33`) with:

```bash
# BUILTIN, not `$(cat)`: with an empty PATH, `cat` is not found and bash writes that to stderr, breaking the
# no-stderr-on-any-path invariant (ROADMAP section 32b). `read -d ''` reads to EOF, returns 1 there (ignored
# under `set +e`) and keeps the payload byte for byte; the trailing newline it keeps is read by neither jq nor
# the regex below. With nothing on PATH the hook then says jq is missing, which is true.
IFS= read -r -d '' input
```

- [x] **Step 2 (32a, degraded path):** directly after the line `  [ -z "$cwd_path" ] && cwd_path="."` (the INDENTED one, inside the no-jq `if`, currently `:46`), insert:

```bash
  # A FILE as cwd is resolved to its DIRECTORY, or the kill-switch below never fires (ROADMAP section 32a):
  # the walk is gated on `[ -d ]`, so both probes became <file>/.no-agy. The same line as
  # agy-seam-inject.sh. Parameter expansion, not `dirname`: an empty PATH must not turn an opt-out into a
  # leak. `%/*` leaves nothing for a path at the root, hence the guard.
  [ -f "$cwd_path" ] && { cwd_path=${cwd_path%/*}; [ -z "$cwd_path" ] && cwd_path="/"; }
```

- [x] **Step 3 (32a, jq path):** directly after the UNINDENTED `[ -z "$cwd_path" ] && cwd_path="."` (currently `:85`), insert:

```bash
# A FILE as cwd is resolved to its DIRECTORY - see the note on the degraded path above. Here the miss was
# masked for the kill-switch (no anomalies file under <file>/ either) but it also HID the root's anomalies.
[ -f "$cwd_path" ] && { cwd_path=${cwd_path%/*}; [ -z "$cwd_path" ] && cwd_path="/"; }
```

- [x] **Step 4:** mirror to classic and confirm the hashes match. Run the suite: expected `Failed: 0`, count = previous + 4.
- [x] **Step 5: Mutants** (`git add` both hooks and the test file first). Each must redden ITS row by name; restore with `git checkout --` after each:
  - **M1** delete the Step 2 line in the dotnet hook -> `honours a root .no-agy when cwd is a FILE, on the DEGRADED ...` red.
  - **M2** delete the Step 3 line -> `REPORTS the root anomalies when cwd is a FILE, on the jq path ...` red.
  - **M3** put `input=$(cat)` back -> `writes NOTHING to stderr with an EMPTY PATH ...` red.
- [x] **Step 6: Commit:**

```powershell
git add clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh clavity-classic/plugin/hooks/agy-anomaly-reminder.sh scripts/tests/agy-anomaly-reminder.Tests.ps1
git commit -m "fix(anomaly-reminder): a file cwd and an empty PATH (section 32)" -m "<what, the three mutants, counts>" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

### Task 3: Registration count

- [x] In `scripts/tests/_partition.md`, the `agy-anomaly-reminder.Tests.ps1` line's `33 tests` becomes `37 tests` (measure the real count from the Task 2 run, do not assume). Run `scripts/tests/test-suite-registration.Tests.ps1` (expect 9/9). Commit.

### Task 4: Bump both plugin versions

- [x] `just bump dotnet 0.9.4` and `just bump classic 0.8.3`. Expect `check-versions: class 'all' OK (dotnet) = 0.9.4` and `... (classic) = 0.8.3`. Each lock file (`clavity-classic/Cargo.lock`, `clavity-classic/agy-mcp-bridge/uv.lock`) must change ONLY its own package's version line; a re-resolved dependency is a STOP.
- [x] Compile the classic installer: `ISCC.exe "/O<scratch>" clavity-classic/installer/clavity-classic.iss` -> `Successful compile`; do not commit the output.
- [x] Commit `chore(version): bump dotnet 0.9.3 -> 0.9.4 and classic 0.8.2 -> 0.8.3` with the files `scripts/bump-version.ps1` wrote (both `plugin.json` per member, `Cargo.toml`, `Cargo.lock`, `pyproject.toml`, `uv.lock`, `clavity-classic.iss`) - stage the exact list `git status` shows, nothing else.

### Task 5: Close the ROADMAP header and publish this plan (LAST commit before the capstone)

- [x] Append to `### §32 ...`: ` · ✅ **FIXED <date> on sweep Branch 3 (`<Task 2 sha>`) - a file cwd resolves to its directory on both paths; the payload is read with a builtin, so an empty PATH writes no stderr**`. Also correct the 32b body's mechanism: the stderr is `line 33: cat: command not found`; the earlier "bash itself" was a probe artifact.
- [x] Gates: `scripts/check-roadmap-claims.ps1`, `scripts/check-control-bytes.ps1`, `scripts/check-injected-context.ps1`.
- [x] Commit `clavity-dotnet/ROADMAP.md` and `git add -f` this plan.

## After the tasks (driver only)

1. **Full gates**, sequentially, from a shell with Git Bash first on `PATH`: `lefthook run pre-push --all-files`, then the FULL `scripts/tests` suite (never `test-scripts-fast` alone - Branch 2 turned CI red that way). It exceeds the tool cap: run it detached and wait on a done-marker.
2. **AGY-CAPSTONE** over `b1228a86..<Task 5 sha>` WITH the live peer (the owner's agy waiver covered Branch 15 only), rounds until GREEN, owner adjudicates; ledger row, then the marker at the reviewed sha.
3. **AGY-TEST-AUDIT** over the same range; ledger row, then the marker at the row's range end.
4. **Merge** `--no-ff` to local `main`; the owner pushes.
5. **HALT for the reinstall** (the spec's reinstall 2). Record the halt in the execution index, ask the owner to reinstall through the plugin manager with Claude Code fully closed (never `clavity-install.ps1`), and start nothing until the owner confirms AND `installed_plugins.json` reports `clavity@clavity` 0.9.4.

## Stand-downs

- **A BARE relative file cwd** (`cwd = "afile.txt"`, no slash): `${cwd_path%/*}` leaves it unchanged, so the walk is still skipped. The sibling hook shares the edge. Below the floor: Claude Code sends an absolute `cwd`, and the line is kept identical to the sibling's on purpose.
- **Removing the class rather than the instance** (a shared cwd-resolution helper sourced by every hook): raised by the peer in the AGY-FIRST consult and judged out of scope for section 32.
- **No `2>/dev/null`** on the payload read: rejected in the AGY-FIRST consult (it hides the one sign the environment is broken).
