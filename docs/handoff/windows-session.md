# Handoff: the Windows measurement session

For a Claude session started on the owner's real Windows machine, after `git pull` of `main`. The Linux session that wrote this could not run
any of it: its box has no Windows VM (Docker is Linux only, no `/dev/kvm`), so every item below is a measurement only Windows can give.
Date written: 2026-10-28, `main` at the commit that merged this file.

## Ground rules (from the owner; they bind this session too)
- **No release.** Never run `just release` / `scripts/release.ps1` or push a `clavity-v*` tag unless the owner asks in this session. Unreleased
  clavity-ls work sits on `main` by policy.
- **Commit and push only when asked.** Main is protected: work goes on a branch, a PR, and `gh pr merge N --merge --auto` (merge commit; the
  `merge-gate` check is required). Commits end with `Co-Authored-By: <the model that wrote them>`.
- **Measure, then claim.** A statement about how a tool behaves needs a measured output or a `path:line` into its source. Do not say a capability is
  missing before checking it.
- **Timing figures are top level only.** No subagents for timing; launch the run in the background, make no other tool call until it ends, check
  the field is clear first (no stale Pester/pwsh/dotnet runs), run twice and quote the range, say what background load you did not control.
- Never touch the local branch `main` (a dead release commit) or `stash@{0}`. `.clavity/` is gitignored runtime state; never commit it.
- agy disciplines still apply to code branches (consult agy on design forks; capstone then test audit before calling a branch done). Pure
  measurement plus a ROADMAP edit needs neither.
- Prerequisites to check first: PowerShell 7 (`pwsh`), Git for Windows (`C:\Program Files\Git\usr\bin\bash.exe` is the one that matters),
  `just`, Pester 6.x (`Get-Module -ListAvailable Pester`), and `gh` logged in. `pwsh -File scripts/run-pester-parallel.ps1 ...` is the runner.

## The items (all in `clavity-dotnet/ROADMAP.md`; read the section before measuring)
Do them in this order; 1 gates the rest.

1. **Generate the `## windows` skip inventory** (section 93, items 6 and 7).
   `pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory`
   in an NON-elevated shell (reject any `NotAsRoot` row that appears). Review the diff: the `## windows` section is new. Also check that
   non-ASCII row names survive the child JSON (item 7: it travels over stdout in the console code page; look for `?`) and whether
   `Set-TestFileReadOnly`'s MSYS `[ -w ]` probe agrees with `attrib +R` (if not, use `(Get-Item).IsReadOnly` on Windows).
   Until the section exists the runner's gate fails closed on Windows.
2. **Spawn budget, serial** (sections 86 and 100). Run `scripts/tests/hook-spawn-budget.Tests.ps1` once, alone. Record the real counts. Section 86:
   the row `PINNED consult: MCP agy_ask, inconclusive return (after its pre)` allows `PostMcp + 1`; if the measured count differs set its `-Max`
   to the measured value (rows live in `scripts/tests/hook-spawn-budget.Rows.ps1`). Section 100: re-pin `$ConsultPin` from the run (the current
   pins are ceilings; a lowered pin needs a Windows run to prove it stays green) and run the row `worst: snooze expired + 16 recent entries`.
3. **Spawn budget, parallel** (sections 82 and 83). Run the same suite through the runner at `-ThrottleLimit 4` and compare counts and wall time
   against item 2. If counts are identical and no wall-clock bound (120 s hook, 10 s pipes, 30 s job drain) trips, the suite can join the parallel
   slow lane (`test-scripts-slow-parallel` in the `justfile`). For section 83 time the full sweep: serial `Invoke-Pester scripts/tests` versus the
   runner, each twice. The CI sweep checks three things the runner does not reproduce (every container ran, the registration oracle ran, a
   total-count floor); the runner has `-MinTests`/`-RequireSuite` now, so state what still differs before proposing CI use.
4. **`agy-consult-recovery.sh` per-seam loop** (section 88): build 1031 synthetic seams of the shape the hook reads in a throwaway repo and time the
   whole hook three times (Linux: 0.18 to 0.26 s). If Windows is slow (the 2026-10-06 figure was 6 s) the bound described in section 88 becomes worth
   building; otherwise close it.
5. **Section 100 leftovers**: junction and UNC aliases of one folder for the folder lock (section 101 says they were read through the same link API
   but not measured), and the Mac `date`/`find -mmin` item cannot be done here (no Mac) so leave it open.

## How to finish
- Update each section's **Status** line with the measured result and date (`docs/tracker-format.md` has the grammar; run `just check-tracker-status`).
  Anything you cannot finish stays OPEN with what you learned.
- One branch, one PR for the ROADMAP/inventory/pin changes; run the whole suite (`pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests
  -SkipInventory scripts/tests/_skip-inventory.md -ShowMessages -MinTests 100 -RequireSuite test-suite-registration`) before pushing, because
  targeted runs miss the repo-wide gates.
- Windows CI has been flaky in two known ways: a Windows registrar test timing out (exit 124) and Chocolatey/PowerShell Gallery outages. Re-run the
  failed job once before treating either as a regression.
- Test-writing traps measured on Windows CI: `Invoke-BashHook` captures through `Out-String`, so multi-line stdout arrives with CRLF; and lint
  diagnostics wrap at the console width, so match on text with whitespace and `| ` prefixes collapsed.
