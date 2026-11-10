# Handoff: Windows measurements for the agent-driven install (third Windows session)

> **See also 2026-11-10:** `docs/handoff/windows-session-4.md` adds item (d), the Windows test run; this file stays the one
> for items (a) to (c). Both can be reported in one PR.

For an agent session started on the owner's real Windows machine, after `git fetch origin && git switch feat/agent-install`
(the work lives on that branch, not on `main`). The Linux session that wrote this has no Windows box (measured 2026-11-10:
`uname` = Linux 7.0.0-43-generic, no `powershell.exe`, no `cygpath` on PATH), so everything below is a measurement only Windows
can give. The design these measurements feed is `docs/superpowers/specs/2026-11-10-agent-install-design.md`, section
"Measure first", item 2; the plan is `docs/superpowers/plans/2026-11-10-agent-install.md` (Task 0 Step 6 and Task 7 Step 3).
Written 2026-11-10 at commit `5db62fe9` on `feat/agent-install`.

This file supersedes `docs/handoff/windows-session-2.md` as the one to read first; the three OPEN items of that file are NOT done
and are listed under "Not for this session" below so they are not lost.

## Ground rules (from the owner; they bind this session too)
- **No release.** Never run `just release` / `scripts/release.ps1` or push a `clavity-v*` tag.
- **Commit and push only when asked, never to `main`.** Work on a branch cut from `origin/feat/agent-install`
  (`git switch -c windows/agent-install-measure origin/feat/agent-install`), and report through a pull request whose BASE is
  `feat/agent-install` (not `main`). Commits end with `Co-Authored-By: <the model that wrote them>`; PR bodies end with the
  Claude Code line the harness gives you.
- **Measure, then claim.** Every answer below is a quoted raw output, or it is unverified. A peer's (agy's) confident facts are
  claims to check.
- **No code changes in this session.** Items (a) to (c) are measurements and a report. Item (d), the Windows run of the new
  test suites, is NOT in this file: the code it needs is not written yet; a later file (`windows-session-4.md`) will carry it.
- **Do not touch the plugin cache or data dir** except where an item says so and only in the way it says. Never edit
  `~/.claude/plugins/cache/...`; the one deletion item (a) asks for is a stamp the hook recreates by itself.
- `.clavity/` is gitignored runtime state; never commit it.
- Prerequisites: PowerShell 7 (`pwsh`), Git for Windows, the clavity plugin installed and enabled in Claude Code
  (`claude plugin list` shows `clavity@clavity ... enabled`), `gh` logged in.

## Already done - do not redo
- "Measure first" item 1 (an in-session `claude plugin install` persists across the session's exit): measured YES on Linux,
  recorded in the spec at commit `5db62fe9`. Nothing to measure on Windows for it.

## Traps
- **`scripts/tests/_skip-inventory.md` is generated per OS.** Do NOT run `scripts/run-pester-parallel.ps1 -WriteSkipInventory`
  in this session (nothing here asks for a test run); windows-session-2.md's trap about that file still holds.
- **Two bashes.** `C:\Program Files\Git\usr\bin\bash.exe` is the Git for Windows bash Claude Code uses; a WSL `bash.exe` in
  `System32` is a different program. Every command below that says `bash` means the Git one; print `(Get-Command bash).Source`
  first and quote it.
- **Elevation changes `git --exec-path` resolution through shims** (Scoop shims are per-user). Run everything as the normal
  user, not elevated.

## The items, in order
Item (a) gates the plan's Task 1 normalisation (the spec accepts both forms until this returns); (b) and (c) gate the pwsh
form of the install command in the agent-facing `INSTALL.md`. None of them is a design fork; nothing here needs "ask the owner
first" unless an output contradicts the decision rule, in which case quote it and stop.

### (a) The textual form of `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` as the hook sees them under git-bash
Goal: learn whether Claude Code hands its plugin hooks `C:\Users\...` (backslashes, drive letter) or `/c/Users/...`
(git-bash form) on Windows. The launcher library compares `CLAUDE_PLUGIN_DATA/bin` against `$PATH` entries, so it must
know which form arrives. Spec reference: section "Measure first" item 2, first sentence.

ROOT, from the debug log (measured on Linux 2026-11-10: the line `Hooks: SessionStart:startup [bash "<resolved
path>/hooks/migrate-inbox.sh"] (plugin agy-autotrain@clavity) finished with status 0` prints the hook command with
`${CLAUDE_PLUGIN_ROOT}` already substituted, so on Windows it shows the form Claude Code uses). Run in pwsh, in any folder:

    claude -p "reply with the single word ok" --debug-to-stderr 2>&1 | Select-String 'Hooks: SessionStart'

Quote every matching line. Decision rule: the quoted path inside `bash "..."` is ROOT's form; write down whether it starts
with a drive letter and backslashes (`C:\Users\...`), a drive letter with forward slashes (`C:/Users/...`), or `/c/...`.

DATA, from the fetch hook's own success message (it embeds `$TARGET` = `$CLAUDE_PLUGIN_DATA/bin/clavity-ls.exe`,
`clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh:182`). The hook re-fetches when its version stamp is missing, so:

    Remove-Item "$env:USERPROFILE\.claude\plugins\data\clavity-clavity\bin\.clavity-ls.version"
    claude -p "reply with the single word ok" --debug-to-stderr 2>&1 | Select-String 'clavity-ls\] fetched'

If `--debug-to-stderr` does not show the hook's message, start an interactive `claude` in any folder instead: the first
message of the session is the hook's `[clavity-ls] fetched <asset> -> <TARGET>` line; quote it verbatim, then `/exit`.
Decision rule: the `-> <TARGET>` path is DATA's form plus `/bin/clavity-ls.exe`; record it the same way as ROOT. Also
quote `echo $PATH | tr ':' '\n' | grep -i clavity` from git-bash (expected: no line, the data dir is not on PATH yet) so the
two forms the library must compare are both on record.

Write back: both quoted lines and the two one-word verdicts (`backslash` / `forward` / `posix`) in the PR body.

### (b) `git --exec-path` depth below the Git root, per install layout
Goal: confirm `Resolve-Path (Join-Path (git --exec-path) '..\..\..')` is the Git root (so `<root>\bin\bash.exe` exists) on
every layout present on this machine. Spec reference: section 3 ("`<Git>\mingw64\libexec\git-core`, three levels below the
Git root"). Run in pwsh, once per layout that exists (skip the ones that do not, and say so):

    (Get-Command git).Source
    git --exec-path
    $root = Resolve-Path (Join-Path (git --exec-path) '..\..\..'); $root; Test-Path (Join-Path $root 'bin\bash.exe')

Layouts to look for: machine-wide (`C:\Program Files\Git`), per-user (`$env:LOCALAPPDATA\Programs\Git`), Scoop
(`$env:USERPROFILE\scoop\apps\git\current`; run it with Scoop's shim first on PATH if Scoop is installed), Chocolatey
(its shim resolves to the machine-wide layout). To test a layout that is installed but not first on PATH, call its
`cmd\git.exe` by full path instead of `git`.

Decision rule: `Test-Path` must print `True` for every layout present. A `False` means the three-level walk is wrong for that
layout; quote the exec-path and stop (the pwsh form in the spec needs a different locator: ask the owner first).

### (c) `CHERE_INVOKING=1` keeps `bash -l` in the current folder
Goal: confirm the login shell stays in the invoking directory instead of changing to `$HOME`. Spec reference: section 3
(the `try/finally` around `CHERE_INVOKING`). Run in pwsh from a folder that is NOT your home (for example the repo root):

    Get-Location
    & bash -lc pwd
    try { $env:CHERE_INVOKING = 1; & bash -lc pwd } finally { Remove-Item Env:CHERE_INVOKING -ErrorAction SilentlyContinue }
    $env:CHERE_INVOKING

Decision rule: the second `pwd` prints the current folder in `/c/...` form and the first prints `/c/Users/<you>` (or the same
folder, if this Git build already stays put; say which). The last line must print nothing (the variable is gone).

## Not for this session
- Item (d) of the plan's Task 7 Step 3: running `install-sh`, `clavity-ls-launcher-lib`, `fetch-clavity-ls` and
  `hook-spawn-budget` on Windows and regenerating the `## windows` skip inventory. The suites do not exist yet; a later
  handoff file will ask for it.
- The three open items of `docs/handoff/windows-session-2.md` (ROADMAP sections 88, 93 item 7, 93 item 8): still open, still
  waiting on the owner's go-ahead; do not start them here.

## How to finish and report back
- One branch (`windows/agent-install-measure`), one results file `docs/handoff/windows-session-3-results.md` holding the RAW
  output of every command above (a figure or path with no output behind it will be treated as unverified), one pull request
  with BASE `feat/agent-install` whose body quotes the three verdicts. No code change, so no test run is needed before
  pushing; `git status` must show only the results file.
- What stays OPEN if an item could not be run: say so per item in the results file rather than leaving it out.
- Keep this file's claims honest: if a path or command here is wrong on your box, correct it in the same PR and say so.
