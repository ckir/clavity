# Pester script suites on Windows AND Linux - design

**Status:** owner-ruled 2026-10-13 (policy HYBRID + per-OS skip baseline file). AGY-FIRST consult
`.clavity/seams/linux-windows-suites.md` ALIGNED on HYBRID; the peer's "173 skips" figure was invented and is
not used anywhere below.

## Intent and why

`just release` (`scripts/release.ps1:151`) runs `just test-scripts` as a pre-flight gate. On 2026-10-13 that gate
failed on the owner's Linux box (1890 passed / 306 failed) and left a dead `chore(release): clavity-v26` commit
(`a9f5b644`) on local `main`. Re-measured after installing `yq`: 1940 passed / 268 failed / 51 skipped, 26 failing
suites of 83 (`.clavity/scratch/linux-windows-suites/census.txt`). Every failure is a TEST-HARNESS assumption that
only holds on Windows + Git for Windows (MSYS); no product defect was found. The hooks themselves run under bash on
Linux too, so a suite that only runs on Windows cannot catch a Linux regression in a hook.

Goal: `just test-scripts` exits 0 on Windows AND on Linux, with no failing row, no row that passes without
running, and no coverage lost on either OS without a NAMED, reviewed skip.

## Goals / non-goals / anti-goals

- Goals: (1) every row whose subject exists on both OSes RUNS on both; (2) a row whose subject is Windows-only
  (Win32 Job Objects, Inno Setup / ISCC, the registry, NTFS junction creation by `cmd`, `FileShare.None` locks,
  backslash-only paths) SKIPS on Linux and is LISTED by name with a reason; (3) the release gate fails on any skip
  not in the list and on any `always` entry that stopped skipping.
- Non-goals: a Linux process counter for the 167 hook-spawn-budget rows (the budget is calibrated to Windows
  process-creation cost; a `strace`/`/proc` counter would measure a different quantity - agy and the driver agree);
  running ISCC under wine; porting `clavity-dotnet/install/clavity-install.Tests.ps1` (Windows installer, not
  under `scripts/tests`, already green on Linux); the `guardtest` shared session id (ROADMAP §89 item, not a
  census failure - stays open under §89).
- Anti-goals: a skip that hides a Linux regression in a hook; a fixture that passes because an ambient tool (jq,
  the real `ast-grep`, the real `gh`) answered instead of the shim; a numeric skip count as the gate.

## Root-cause families (measured; see the census and `.clavity/seams/linux-windows-suites.md`)

| Family | Rows | Disposition |
|---|---|---|
| A. Git-Bash core resolution (`usr\bin\bash.exe`) and the Win32 Job Object counter | 167 hook-spawn-budget + 7 BashHookHelpers + 2 empty-PATH callers + 2 local copies | PORT the resolution (bash on Linux IS the core); SKIP the Job Object rows |
| B. `icacls` / `attrib` to make a file unreadable / read-only | 6 rows in 4 suites | PORT via helpers (`chmod` branch, enforcement probed, root skips) |
| C. jq-absent fallback rows that rebuild PATH as `/usr/bin[:/bin]` or Git `usr\bin` | ~14 rows in 6 suites | PORT via a sandbox PATH built from the real PATH minus jq, with the existing "jq still reachable" controls kept |
| D. dash rows launched through `cygpath` | 7 rows | PORT (guard `cygpath`) |
| E/F. `cygpath` in fixtures; shims written without an exec bit; `sh` assumed to be bash | 8 + 27 + 1 rows | PORT |
| G. Backslash assertions, `C:` / `$env:TEMP` / `$env:USERPROFILE`, `.cmd` shims, `;` PATH joins, `cmd /c mklink`, `FileShare.None` | ~20 rows in 11 suites | PORT where Linux has the same semantic (symlink for junction, non-writable dir for an undeletable child); SKIP the case-insensitive-FS and backslash-only-path rows. Stated trade-off: the two "undeletable child" rows (`TestTemp.Tests.ps1:68-80`, `review-relay-scripts.Tests.ps1:445-459`) measure an open-handle lock on Windows and directory write permission on Linux - the product behaviour under test (the sweep tolerates / the rebuild aborts when a delete fails) is the same, the cause of the failed delete is not |
| H. ISCC + `HKCU:` registry | 4 rows | SKIP on non-Windows (CI builds the installer) |

## Decisions (the owner's, or the driver's call where marked)

1. **Skip approval = tags + approved reasons + a generated inventory** (owner-accepted 2026-10-13 after an
   AGY-NEGOTIATE of two rounds, `[VERDICT: ALIGNED]`; it replaces the hand-written baseline file the owner first
   chose and the pure-tag gate agy first proposed, each of which fails one of the six criteria below).
   - CLOSED VOCABULARY enforced by the runner: `WindowsOnly`, `LinuxOnly`, `NeedsTool:<name>`, `NotAsRoot`,
     `FsFeature:<name>`. Nothing else approves a skip.
   - STATIC skips (`-Skip:(-not $IsWindows)` on an It or a Context) carry `-Tag 'WindowsOnly'` (or `LinuxOnly`) on
     the same It/Context; effective tags = the test's own plus every enclosing block's (Pester 6.2.0 exposes both;
     measured 2026-10-13).
   - RUN-TIME probe skips (`Set-ItResult -Skipped`) carry a reason beginning `APPROVED:<vocab-tag>: ` (the reason
     survives in `ErrorRecord[0].Exception.Message`; measured). A discovery-time skip has NO reason text, which is
     why it needs the tag - the runner's error names that rule.
   - RUNNER RULES: a skipped row with neither → `UNAPPROVED SKIP <suite> :: <path>` exit 1; a `WindowsOnly` row
     that RAN off-Windows or SKIPPED on Windows (mirror for `LinuxOnly`) → `OS-TAG MISMATCH` exit 1; the
     conditional tags may go either way (their approval lives in the code and leaves with the test).
   - GENERATED, COMMITTED INVENTORY `scripts/tests/_skip-inventory.md`, written by the runner
     (`-WriteSkipInventory`), never hand-edited: per OS, a `static` table (every OS-tagged skipped row; must be
     byte-equal to what the run produces, else `SKIP-INVENTORY STALE`) and a `conditional` table (every
     probe-approved skip ever observed; a run may skip FEWER of them, never an unlisted one). No section for the
     running OS → fail closed. This is the one reviewable PR diff.
   - The six criteria the shape was negotiated against: every skip named and human-reviewed; per-OS; staleness
     detected; unintended skips caught; fail closed on an unmeasured OS; one reviewable diff.
2. **The gate engine** for `just test-scripts` becomes `scripts/run-pester-parallel.ps1` (already written to be
   "exactly as strict as a single Invoke-Pester" and pinned by its own suite), with a new `-Directory` input and a
   `-SkipBaseline` input. Plain `Invoke-Pester` has no hook to read skipped names across containers.
   `.github/workflows/ci-scripts.yml:307` (Windows) keeps its plain `Invoke-Pester` this round; a NEW
   `ubuntu-latest` job runs the runner with the baseline. The parallel engine is measured on Linux only; the
   recipe accepts `-ThrottleLimit 1` as the serial fallback for the owner's first Windows runs.
3. **Shared helpers live in `scripts/tests/BashHookHelpers.ps1`** (already dot-sourced by every family A-F
   suite and it dot-sources `TestTemp.ps1`), plus one link helper in `TestTemp.ps1` for the suites that do not
   load BashHookHelpers. No new helper file (the inventory and registration suites pin the file set).
4. **Windows baseline section is UNMEASURED here.** The driver cannot run Windows. The `## windows` section ships
   with a header comment only; the owner's first `just test-scripts` on Windows fails closed and prints the lines
   to paste. Nothing is fabricated.
5. **Product changes are limited to one**: `installer/_shared/register-plugin.ps1:59-60` reads
   `$env:USERPROFILE`, which is unset on Linux; `$HOME` is the same directory on Windows (PowerShell 5.1 and 7)
   and exists on Linux. Everything else is test-side.
6. **Non-vacuity is proven per port** with a logic mutant of the guarded code or fixture (the repo's
   PINNING-ASSERTION-STRENGTH bar): a PORT that stays green under its mutant is not accepted.
7. **Integration order.** Work on `sweep/linux-pester-suites` branched from current `main` (`a9f5b644`, which is
   the dead release commit on top of `e6f28393`). After the owner approves the merge, `just release -Resume` drops
   `a9f5b644` and replays the suite commits onto `e6f28393` (release.ps1's documented path); a linear history
   (fast-forward) keeps that replay trivial. The owner owns every push.

## What is left to the builder

Exact wording of skip reasons; the `New-NoJqPath` symlink build (bash loop vs PowerShell loop) as long as its
postcondition (`command -v jq` fails under the returned PATH) is asserted; the ubuntu CI job's tool-install steps
(mirror the Windows job; STOP and report if a tool has no simple Linux install).
