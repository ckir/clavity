# Handoff: Windows test run for the agent-driven install (fourth Windows session)

For an agent session started on the owner's real Windows machine, after `git fetch origin && git switch feat/agent-install`
(the work lives on that branch, not on `main`). The Linux session that wrote this has no Windows box (measured 2026-11-10:
Linux 7.0.0-43-generic, no `powershell.exe`, no `cygpath`). Written 2026-11-10 at commit `f65ca579` on `feat/agent-install`.
Plan: `docs/superpowers/plans/2026-11-10-agent-install.md`, Task 7 Step 3; spec: `docs/superpowers/specs/2026-11-10-agent-install-design.md`,
"Measure first" item 2.

This file ADDS item (d) to `docs/handoff/windows-session-3.md`, which stays the file for items (a) to (c). Do (a) to (c) first if they
have not been reported yet (check for an open or merged PR with base `feat/agent-install` from branch `windows/agent-install-measure`);
then (d) below. Both can go in the same PR.

## Ground rules (from the owner; they bind this session too)
- **No release.** Never run `just release` / `scripts/release.ps1` or push a `clavity-v*` tag.
- **Commit and push only when asked, never to `main`.** Branch from `origin/feat/agent-install`; PR with BASE `feat/agent-install`.
  Commits end with `Co-Authored-By: <the model that wrote them>`; PR bodies end with the Claude Code line the harness gives you.
- **Measure, then claim.** Every result is a quoted raw output or it is unverified.
- **Run every suite as the normal user, not elevated**, from a PowerShell 7 (`pwsh`) prompt at the repo root, with Git for Windows
  installed (`C:\Program Files\Git\usr\bin\bash.exe` is the bash the hooks use).
- `.clavity/` is gitignored runtime state; never commit it.
- Prerequisites: `pwsh`, Git for Windows, `just` (optional), Pester 5 or 6 (`Get-Module -ListAvailable Pester`), `gh` logged in.

## Already done - do not redo
- Tasks 1 to 6 of the plan are implemented and reviewed on this branch (launcher library, hook integration, `install.sh`, `INSTALL.md`,
  README/site, product docs). The Linux acceptance runs are recorded in `docs/superpowers/plans/2026-11-10-agent-install-acceptance.md`
  (published with the plan once Task 7 Step 4 lands). Nothing here needs a code change unless a suite is RED.

## Traps
- **`scripts/tests/_skip-inventory.md` is GENERATED per OS section.** The Linux session HAND-ADDED these rows under `## windows` /
  `### static` because only a Windows run can regenerate that section: five `clavity-ls-launcher-lib.Tests.ps1` rows, three
  `fetch-clavity-ls.Tests.ps1` rows, three `install-sh.Tests.ps1` rows (all `LinuxOnly`). Item (d) regenerates the section; the
  hand-added rows are EXPECTED to come back byte-identical. Any diff in that section is itself a result: commit it with the evidence
  and say which rows changed. Do not edit the file by hand.
- **Symlinks.** Git for Windows' `ln -s` makes a COPY unless `MSYS=winsymlinks:native*` is set. Rows that assert a symlink are tagged
  `LinuxOnly` and must show as Skipped, not Failed. Do not set `MSYS` to make them run.
- **The budget suite and the launcher suite are the ones that have NEVER run on Windows.** Their Windows-only rows pin the production
  path (`hook-spawn-budget.Rows.ps1` "binary installed, stamp matches (steady state)" at `-Max 0 -Silent`;
  `clavity-ls-launcher-lib.Tests.ps1` "windows steady state spawns zero processes"). A RED there is a real finding, not a flake:
  quote it in full and stop; do not change `-Max`, a tag, or a fixture to make it green (that is a code change: ask the owner first).
- **Fixture paths under `%TEMP%`.** The fixtures hand the hook its data dir in the POSIX form `cygpath -u` yields, because MSYS maps
  `%TEMP%` to `/tmp` through its mount table. If a row fails with a message naming `/tmp/...` next to `C:\...`, that mapping is the
  suspect; quote both paths.

## The items, in order
Items (a) to (c): see `docs/handoff/windows-session-3.md` (unchanged). Then:

### (d) The four suites on Windows, then the inventory regeneration
Goal: prove the Windows branch of the launcher and the hook integration on a real Windows machine, and refresh the generated
`## windows` skip inventory. Run from the repo root in pwsh:

    pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/install-sh.Tests.ps1','scripts/tests/clavity-ls-launcher-lib.Tests.ps1','scripts/tests/fetch-clavity-ls.Tests.ps1','scripts/tests/hook-spawn-budget.Tests.ps1') -Output Detailed"

Decision rule: 0 Failed; Skipped rows are exactly the `LinuxOnly` ones (11 across the first three suites) plus whatever
`hook-spawn-budget` skips by design; the two "zero processes" rows named in Traps PASS (not Skipped). Quote the final
`Tests Passed: N, Failed: 0, Skipped: M` line and the per-suite lines.

Then regenerate the inventory (runs EVERY suite; 10 to 15 minutes; background load uncontrolled is fine, this is not a timing):

    pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory

Decision rule: the run ends with `SKIP-INVENTORY ok os=windows` (or a line saying it wrote the section) and `git diff --stat` shows
either no change to `scripts/tests/_skip-inventory.md` or a change limited to the `## windows` section; quote `git diff` of that file
in full (it is short) in the results file. A failure in a suite UNRELATED to this branch is reported, not fixed.

Write back: the four-suite summary lines, the two "zero processes" row results, the inventory command's last 5 lines, and the
inventory diff, in `docs/handoff/windows-session-4-results.md`. Also record whether `sha256sum` resolves in the agent's own
PowerShell (`Get-Command sha256sum`), since INSTALL.md's precondition rule rests on it not resolving there.

## Not for this session
- The Windows ACCEPTANCE run of the install itself (pasting the sentence to Claude Code or agy on Windows in a throwaway
  `CLAUDE_CONFIG_DIR`): it installs real plugins and writes the user PATH; the owner decides whether and when to run it. If asked,
  use a throwaway `CLAUDE_CONFIG_DIR` and `CLAVITY_SKIP_PATH=1`, exactly as the Linux acceptance did.
- The open items of `docs/handoff/windows-session-2.md` (ROADMAP sections 88, 93 item 7, 93 item 8): still waiting on the owner.

## How to finish and report back
- One branch (`windows/agent-install-measure`, or a second one if that PR is already merged), the results file(s), and one pull
  request with BASE `feat/agent-install` whose body quotes the summary lines. If the inventory diff is non-empty, that file is part
  of the commit. No other code change without asking the owner.
- What stays OPEN if an item could not be run: say so per item in the results file rather than leaving it out.
- Keep this file's claims honest: if a path or command here is wrong on your box, correct it in the same PR and say so.
