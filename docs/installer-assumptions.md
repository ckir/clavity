# Installer ground truth — load-bearing assumptions, and how to re-verify them

The member installers (the C# `clavity-ls install` path and the shared Inno
`installer/_shared/*.iss` path) make a small number of **empirically-observed** assumptions about the
host — chiefly about Claude Code. Like the agy peer, Claude Code is an external, frequently-updated
tool whose internals are not a stable contract, so an update can silently break an assumption here.
This file states each assumption, why it is load-bearing, how it was verified, and how to re-verify it.

## A running Claude Code presents a process named `claude.exe`

**The assumption.** The install/uninstall **refuse guard** (Bug 2) detects a running Claude Code by its
OS process name `claude.exe`:
- Inno path (`installer/_shared/claude-running.iss` → `ClaudeIsRunning()`): `tasklist /FI "IMAGENAME eq claude.exe"`.
- C# path (`Clavity.Ls/Install/CliRouter.cs` → `ClaudeAppRunning()`): `Process.GetProcessesByName("claude")`
  (the framework strips `.exe` and matches case-insensitively).

**Why it is load-bearing.** A running Claude reconciles its plugin registry from `settings.json` and
**overwrites concurrent registration writes** — and flushes stale in-memory state back to disk on exit,
clobbering even a correct write made while it was running (verified 2026-07-13 spike + the live post-v9
install incident). The refuse guard is the primary fix: it aborts the install/uninstall (non-zero exit,
even under `/SUPPRESSMSGBOXES`) while Claude is up. If the process-name probe silently returns `false`,
the guard no-ops and the clobber bug returns.

**How it was verified.** 2026-07-13 read-only spike (`scratchpad/spike-claude-registration.ps1`, run
CLOSED + RUNNING on the repro box): a running Claude Code = a process `claude.exe` at
`C:\Users\user\.local\bin\claude.exe`, a real `.exe` (`CommandType: Application`), not a `.cmd` shim.

**Drift risk (re-verify on every supported-Claude bump).** If Anthropic renames the executable, ships a
Microsoft-Store-app identity, or reparents Claude under `node.exe`, then `tasklist`/`GetProcessesByName("claude")`
returns nothing → the guard silently no-ops. This is not caught by CI (the CI smoke uses a renamed
`PING.EXE` stub literally named `claude.exe`, so it proves the guard *logic*, not the real process name).
**The real-Claude oracle is the owner live-acceptance canary** — see CONTRIBUTING.md → *Live acceptance
runbook → Installer refuse-guard canary*. Run it whenever bumping the supported Claude Code version.

**Backstop.** After a successful install the installer performs a **read-back** (`claude plugin list`,
matching the exact `<plugin>@<marketplace>` token) and exits non-zero if the entry did not land. This
catches a non-persisted install when Claude was **not** running; it cannot catch the delayed on-exit
clobber (that is the refuse guard's job).
