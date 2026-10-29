# Handoff: the second Windows session (what is left after 2026-10-29)

For a Claude session started on the owner's real Windows machine, after the owner pulls `origin/main`. It supersedes
`docs/handoff/windows-session.md`, most of which is done (that file stays as the record). The Linux session that wrote this has no Windows box
(no VM, no `/dev/kvm`), so everything below is a measurement or a check only Windows can give.
Written 2026-10-29. `origin/main` was at `5b21510b` (PR #49) before this file's own PR; anything newer is this file or later work.

## Ground rules (from the owner; they bind this session too)
- **No release.** Never run `just release` / `scripts/release.ps1` or push a `clavity-v*` tag unless the owner asks in this session.
- **Commit and push only when asked.** Never push to `main`: work on a branch cut from `origin/main` (`git fetch; git switch -c <topic> origin/main`),
  open a PR, and merge it with `gh pr merge N --merge --auto` (a merge commit; the `merge-gate` check is required). A local `main` on the Linux box
  is a dead release commit; on this box do not trust a local `main`, use `origin/main`. Commits end with `Co-Authored-By: <the model that wrote them>`;
  PR bodies end with the Claude Code line the harness gives you.
- **Measure, then claim.** A statement about how a tool behaves needs a measured output or a `path:line` into its source. Do not say a capability
  is missing before checking it. A peer's (agy's) confident facts are claims to check: it once said `windows-latest` has 2 vCPUs; measured, it has 4
  logical CPUs and 16 GB.
- **Timing figures are top level only.** No subagents for timing; launch the run in the background, make no other tool call until it ends, check the
  field is clear first (no stale Pester, pwsh, dotnet or bash runs), run twice and quote the range, and say what background load you did not
  control (Defender, indexing, other terminals).
- `.clavity/` is gitignored runtime state; never commit it or an agy marker.
- The agy disciplines apply to a CODE branch (consult agy on a design fork; AGY-CAPSTONE, then AGY-TEST-AUDIT, before calling it done; only the owner
  may waive a gate). A measurement plus a ROADMAP edit needs neither.
- Prerequisites to check first: PowerShell 7 (`pwsh`), Git for Windows (`C:\Program Files\Git\usr\bin\bash.exe` is the one that matters), `just`,
  Pester 6.x (`Get-Module -ListAvailable Pester`), `gh` logged in.

## What changed since the first Windows handoff (do not redo these)
- Section 83 is done (PR #48): the Windows `dev-scripts` job now runs `scripts/run-pester-parallel.ps1`, the same command as the Linux job. Measured on
  `windows-latest`: serial 915 s against the runner at 531 to 601 s (throttle 4), identical 2353 passed / 0 failed / 17 skipped over 84 files; the PR's own
  run took 814 s for that step (the serial step was 907 to 1386 s on ten earlier runs; the speed-up varies by VM).
- Section 86 (spawn pin `+2`), section 100's Windows half and section 93 items 6 (inventory) are done; section 93 item 7 is CONFIRMED but its fix is open (below).
- Sections 94 and 103 are shipped (wordmark outlined; the folder-lock key follows `subst` and a loopback `\\localhost\C$` share).

## TRAP: do NOT regenerate the `## windows` skip inventory on this box
`scripts/tests/_skip-inventory.md` `## windows` was regenerated ON `windows-latest` (2026-10-28), whose account is ELEVATED, so 7 `NotAsRoot`
read-deny rows skip there and are listed as conditional (8 static + 9 conditional). Those rows do NOT skip on a normal, non-elevated box, which is fine:
a listed conditional row that did not skip passes the gate. Checking is safe: `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory
scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -MinTests 100 -RequireSuite test-suite-registration` must print `SKIP-INVENTORY ok os=windows`.
Running it with `-WriteSkipInventory` here would drop those 7 rows and the elevated CI job would then fail on 7 unapproved skips. If the inventory
ever needs regenerating, do it on the CI image (a temporary workflow that runs the writer and prints the file), not on this box.

## The items, in order

1. **Section 88: re-time `agy-consult-recovery.sh` after the marker hoist.** Option A shipped 2026-10-28 (`077c40c1`): the four marker paths and their
   existence are resolved once above the per-seam loop. Linux strace showed 3749 -> 2979 `newfstatat` calls with byte-identical output, but the
   Windows wall time was never re-measured. BEFORE the change, on this box: 1 seam 0.83 to 1.16 s, 1031 seams 3.46 to 4.55 s (warm about 3.5 s), control
   `bash -c 'sleep 1'` 1.21 s. Build the same fixture: `New-HookFixture`, then `Add-FxSeams` with 1031 mixed names (257 `loose-*`, the other 774
   `agy-capstone-*`, `agy-first-*`, `agy-panel-*`) from `scripts/tests/hook-spawn-budget.Rows.ps1`, and time the whole hook through `Invoke-BashHook`
   (`scripts/tests/BashHookHelpers.ps1`), three runs per arm; print the file count and throw on anything but 1031 unique names (an earlier attempt
   silently produced 4 files). Report the warm figure and the range. Then decide, and tell the owner: if the 1031-seam figure is still well above the
   1-seam figure, option B (one batch `stat` over all seams; it needs nanosecond tie-break parity with `-nt` and a GNU `stat` in both twins,
   `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/`) is the next step and is a design fork (AGY-FIRST, owner decides); if it is
   acceptable, close section 88 with the figures. Update the section's Status line (`docs/tracker-format.md`; `just check-tracker-status`).
2. **Section 93 item 7: child JSON loses non-ASCII under a legacy console code page.** Measured 2026-10-28 on this box: with output code page 437 the
   runner's child JSON turned an em dash (U+2014) into a hyphen while U+03B1 and U+00E9 survived, and many row names contain an em dash. The fix is
   open (set the child's output encoding to UTF-8, or write the child result to a file instead of stdout). It is CODE in `scripts/run-pester-parallel.ps1`
   with a test; reproduce it first with a failing row, prove the fix against a control on this box, and run the capstone and test audit. Ask the owner
   before starting it; it is not urgent.
3. **Section 93 item 8, the stale time text** in `scripts/tests/_partition.md` (the run-pester-parallel suite says 55.0 s; measured about 240 to 270 s).
   Needs an idle, top-level, two-run measurement; skip it if the machine cannot be kept idle.

Not for this session: section 82 (adding the spawn-budget suite to `test-scripts-slow-parallel`) is waiting on the OWNER's decision; the Windows
evidence (169/169 under the runner, twice, and seven more times in the section 83 runs) is already in its Status line. Section 100's remaining item is the BSD
`date` / `find -mmin` check on a Mac and cannot be done on Windows.

## How to finish
- One branch, one PR. Run the whole suite before pushing, because targeted runs miss repo-wide gates:
  `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -ShowMessages -MinTests 100 -RequireSuite test-suite-registration`
  (expect `SKIP-INVENTORY ok os=windows`). Also `just check-tracker-status` and `pwsh scripts/check-roadmap-claims.ps1` after a ROADMAP edit.
- Windows CI is flaky in two known ways: a Windows registrar test timing out (exit 124) and Chocolatey or PowerShell Gallery outages. Re-run the
  failed job once before treating either as a regression.
- Test-writing traps measured on Windows CI: `Invoke-BashHook` captures through `Out-String`, so multi-line stdout arrives with CRLF; lint
  diagnostics wrap at the console width, so match on text with whitespace and `| ` prefixes collapsed; on Pester 6 `Should -CContain` fails with a
  parameter-set error next to `-Because`, so write `(... -ccontains x) | Should -BeTrue -Because '...'`.
- Keep this file's claims honest: if a figure here turns out wrong on your box, correct the file in your PR and say so.
