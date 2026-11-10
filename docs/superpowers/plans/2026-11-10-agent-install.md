# Agent-driven install Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A newcomer pastes one sentence to their coding agent (Claude Code or agy) and ends up with the clavity plugins installed and `clavity-ls` resolving in a new terminal, with the human's only remaining step being `clavity-ls start <folder>`.

**Architecture:** The plugin's existing SessionStart fetch hook gains a sourced library that keeps a `clavity-ls` launcher on PATH (Unix symlink in `~/.local/bin`, Windows user-PATH entry), idempotent and zero-process in steady state. A root `install.sh` runs the `claude plugin` commands, runs that hook by hand so nothing waits for a restart, registers the plugin with agy, verifies, and prints the launch line with a four-valued exit code. A root `INSTALL.md` is the agent-facing contract, harness-neutral, with a bash and a PowerShell invocation.

**Tech Stack:** bash (hooks, `install.sh`), Pester 5 under pwsh for the shell suites (`scripts/tests/*.Tests.ps1`, helpers in `BashHookHelpers.ps1`/`TestTemp.ps1`), Python stdlib unittest for the site checker, xUnit for `CliHelpTests.cs`, Markdown/HTML for the surfaces.

**Spec:** `docs/superpowers/specs/2026-11-10-agent-install-design.md` (every section number below refers to it)

## Global Constraints

- Steady-state SessionStart path spawns ZERO processes and prints nothing: `scripts/tests/hook-spawn-budget.Rows.ps1:444-449` pins `-Max 0 -Silent` for "binary installed, stamp matches".
- Every hook message is a `msg*=` assignment on its own line passed to `_say` (`fetch-clavity-ls.sh:50-52` comment); `just check-injected-context` must stay green.
- Hooks fail open: any failure is a message and `exit 0`.
- New shell suites are registered in the `test-scripts-slow` list in `justfile:130` (`scripts/tests/test-suite-registration.Tests.ps1` pins the list) and the hand-oracle note in `scripts/tests/_partition.md` gets one line.
- A new dotnet-only hook file is added to `$script:DotnetOnly` in `scripts/tests/plugin-hooks-twin-parity.Tests.ps1:19`; a sourced library is named `*-lib.sh` (registration-test carve-out, `plugin-hooks-registration.Tests.ps1:181-185`).
- The sentence, verbatim everywhere: ``Tell your agent: `Fetch and follow the instructions at https://raw.githubusercontent.com/ckir/clavity/main/INSTALL.md` ``. The terminal line, verbatim everywhere: `curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s --`.
- On the site these two are page TEXT inside `<code>` without `data-cmd`/`data-copy` and are never an `href` (Check 3, `check_site.py:282-283`, inspects `href` only); no page text outside `#install` data-cmd may contain `claude plugin` (Check 6, `check_site.py:493-500`).
- Site Check 6 pins the `#install` `<code data-cmd>` list to the README's first fenced block containing `claude plugin marketplace add` (`check_site.py:420-445`, `474-516`); the fixtures in `.github/site-checks/test_check_site.py:68-79` pin the same list.
- `claude plugin install` is always `claude plugin install <id> -y --scope user` (`ProfileSetup.cs:101`).
- Launch line, verbatim: `If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: clavity-ls start <folder>`.
- Exit codes of `install.sh`: 0 done and resolvable, 1 precondition missing, 2 binary not runnable or plugin not enabled, 3 done but `clavity-ls` not on PATH yet.
- Specs and plans are published through a `.gitignore` negation line (`.gitignore:20-49`); this plan's line is added in Task 8.
- Never run `just release` or push a `clavity-v*` tag (owner policy).
- Every Pester row that reaches the launcher step sets `HOME` to a fixture directory (and `PATH` explicitly), so no suite ever touches the developer's real `~/.local/bin` or user PATH; the fake `powershell.exe` is on the shim PATH in every Windows-branch row.

## Review Focus

1. A `~/.local/bin/clavity-ls` that is a user's own regular file (a hand copy, as on the owner's machine): the launcher step must leave it alone and say so; pinned in Task 1.
2. `CLAUDE_PLUGIN_DATA` in Windows form (`C:\Users\...`) while `$PATH` holds the git-bash form (`/c/users/...`): both must compare equal; pinned in Task 1.
3. `claude plugin list --json` listing clavity LAST after agy-autotrain and superpowers: the `installPath` extraction must still pick clavity's; pinned in Task 3.
4. A rerun of `install.sh` within 10 minutes of a failed fetch: the fail stamp must be gone before the hook runs, or the run is a silent no-op; pinned in Task 3.
5. `install.sh` run with `CLAVITY_SKIP_PATH=1` on Windows: must end in exit 3, never 2 (hard checks do not include the launcher); pinned in Task 3.

---

### Task 0: Measure first (spec "Measure first", items 1 and 2)

**Files:**
- Modify: `docs/superpowers/specs/2026-11-10-agent-install-design.md` ("Measure first" section: append the measured result)

**Interfaces:**
- Produces: a recorded yes/no on whether a `claude plugin install` run from a Bash tool call inside a running Claude session survives that session's exit. Task 4's INSTALL.md closing text depends on "yes"; on "no" the closing message changes per the spec's item 1.
- Produces: a dispatched Windows handoff (spec item 2, items (a)-(c) of Task 7 Step 3) whose id is recorded in the execution memory; Task 1 Step 3 consumes item (a), Task 7 Step 3 consumes all of it.

- [ ] **Step 1: Make a throwaway config dir that can sign in and sees the clavity marketplace**

The spec says "in a throwaway `CLAUDE_CONFIG_DIR`"; the host's own plugin store is never touched.
Run:
```bash
export CLAUDE_CONFIG_DIR="$(mktemp -d)"
cp -p "$HOME/.claude/.credentials.json" "$CLAUDE_CONFIG_DIR/"   # measured 2026-11-10: exists on this host, mode 600
claude plugin marketplace add ckir/clavity
claude plugin list --json
```
Expected: the marketplace add succeeds and the list is `[]` (a fresh config dir holds no plugins, so `review-relay@clavity` is the harmless one to install). If the credentials file is absent (keychain-backed sign-in) or Step 2 reports "not signed in", run `claude` once in this config dir, sign in, `/exit`, and continue.

- [ ] **Step 2: Install it from INSIDE a headless session, then let the session exit**

Run (same shell, so the session and its Bash tool inherit `CLAUDE_CONFIG_DIR`):
```bash
claude -p --allowedTools "Bash(claude plugin *)" "Run exactly this shell command and print its output: claude plugin install review-relay@clavity -y --scope user" ; echo "session exit: $?"
```
Expected: the session prints the CLI's success line and exits 0.

- [ ] **Step 3: Verify persistence after exit, from a fresh process**

Run: `claude plugin list --json | python3 -I -c "import json,sys;print([p['enabled'] for p in json.load(sys.stdin) if p['id']=='review-relay@clavity'])"`
Expected: `[True]`

- [ ] **Step 4: Restore the machine**

Run: `rm -rf "${CLAUDE_CONFIG_DIR:?}" && unset CLAUDE_CONFIG_DIR && claude plugin list --json | grep -c review-relay` (the `:?` guard refuses to run with the variable unset)
Expected: count `0` (the host config never saw the plugin).

- [ ] **Step 5: Record the result in the spec**

Append under "Measure first" item 1: `Measured <date>: <yes|no>, command and output quoted.` In the same edit, change the sentence at `spec:142-143` ("is measured on Windows before the normalisation is written") to: "is measured on Windows (handoff dispatched in the plan's Task 0) before the Windows acceptance; if the measurement is late, the normalisation is written to accept both forms and the spec records `UNVERIFIED-WINDOWS` until Task 7 clears it." Commit:
```bash
git add docs/superpowers/specs/2026-11-10-agent-install-design.md
git commit -m "docs(spec): measure in-session plugin-install persistence"
```

- [ ] **Step 6: Dispatch the Windows measurements now (spec item 2)**

Invoke `clavity:platform-handoff` with items (a) the textual form of `CLAUDE_PLUGIN_DATA` and `CLAUDE_PLUGIN_ROOT` as a `Bash` tool call inside Claude Code sees them under git-bash (`C:\...` or `/c/...`), (b) `git --exec-path` output and its depth below the Git root on a machine-wide, per-user and Scoop install (whichever exist), (c) whether `CHERE_INVOKING=1 bash -lc pwd` prints the current folder. Record the handoff id and location in the execution memory. Do not wait for it: Task 1 proceeds.

---

### Task 1: The launcher library

**Files:**
- Create: `clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh`
- Create: `scripts/tests/clavity-ls-launcher-lib.Tests.ps1`
- Modify: `scripts/tests/plugin-hooks-twin-parity.Tests.ps1:19` (`$script:DotnetOnly` gains `'clavity-ls-launcher-lib.sh'`)
- Modify: `justfile:130` (append `'scripts/tests/clavity-ls-launcher-lib.Tests.ps1'` to the `test-scripts-slow` list); `scripts/tests/_partition.md` (one line naming the new slow suite, unmeasured)
- Modify: `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh:55` (after the `_note` definition: define `_launcher_say() { _say "$1"; }` and dot-source the lib from the HOOK'S OWN DIRECTORY, silently skipped when absent; NO call yet, Task 2 adds the two call sites). Own directory, not `$ROOT/hooks/`: `fetch-clavity-ls.Tests.ps1` and `hook-spawn-budget.Rows.ps1:444-449` hand the hook a fixture `CLAUDE_PLUGIN_ROOT` that holds only `plugin.json`, so `$ROOT/hooks/<lib>` never resolves under test. Use the sibling idiom at `agy-consult-guard-pre.sh:34`: `d=${0%[/\\]*}; [ "$d" = "$0" ] && d=.; [ -z "$d" ] && d=/`. This keeps `plugin-hooks-registration.Tests.ps1:170-217` green at this commit: that row reddens on any hook-dir `*.sh` that no manifest, hook or skill references, and the suite runs in `test-scripts-fast`.

**Interfaces:**
- Produces, when sourced: function `clavity_ls_launcher_ensure TARGET BIN_DIR VER` where `TARGET` is the binary path (`$BIN_DIR/clavity-ls.exe`), `BIN_DIR` its directory, `VER` the plugin version string (may be empty). Returns 0 when a new terminal will resolve `clavity-ls`, 3 when the launcher is in place but its directory is not on PATH, 2 when it could not be placed, 0 with no action when skipped. Emits every message through `_launcher_say "<text>"`, a function the caller may define before sourcing; the lib defines a default (text to stderr) only when none exists (`declare -F _launcher_say >/dev/null || _launcher_say() { ...; }`). Every message text is a `msg*=` assignment on its own line.
- Produces, standalone: `bash clavity-ls-launcher-lib.sh TARGET BIN_DIR [VER]` runs the same function and exits with its return code (guard: `[ "${BASH_SOURCE[0]}" = "$0" ]`).
- Produces: reads env `CLAVITY_SKIP_PATH` (`1` skips), marker file `$BIN_DIR/.no-launcher` (skips), stamp `$BIN_DIR/.path-note.$VER` (the not-on-PATH note is emitted once per VER). Reads `$OSTYPE` (`msys*|cygwin*` is Windows). On Windows reads `$PATH`, and when the dir is absent runs `cygpath -w "$BIN_DIR"` and `powershell.exe -NoProfile -NonInteractive -Command <append-if-absent script>`; `powershell.exe` missing is a message and return 2.
- Consumes: Task 0 Step 6's handoff item (a), the Windows form of `CLAUDE_PLUGIN_DATA`, when it has returned (optional; see Step 3).

- [ ] **Step 1: Write the failing suite**

`scripts/tests/clavity-ls-launcher-lib.Tests.ps1` (one top-level `Describe 'clavity-ls-launcher-lib'`: the inventory keys below depend on that name), modelled on `fetch-clavity-ls.Tests.ps1:16-80` (dot-source `BashHookHelpers.ps1`, `Get-GitBashOrThrow`, `New-TestTempPath`, a per-row fixture with a fake `powershell.exe` and `cygpath` shim dir prepended INSIDE bash via `Get-BashCygpathPrelude`). Each row runs the lib standalone with `HOME` pointed at the fixture (so `~/.local/bin` is the fixture's), `OSTYPE` pinned explicitly (never inherited: Git Bash reports `msys`), `PATH` set, and asserts exit code, stderr text, and filesystem state. OS split: every row that creates or inspects a symlink is `-Tag 'LinuxOnly' -Skip:($IsWindows)` (Git for Windows' `ln -s` makes a COPY unless `MSYS=winsymlinks:native*` is set, so `[ -L ]` can never be true there; the Windows branch of the lib never touches symlinks anyway); every `windows:` row pins `OSTYPE=msys` and runs on EVERY OS through the shim `cygpath` and fake `powershell.exe` (the fetch suite already runs its msys rows on Linux the same way). Both tags are listed by regenerating the skip inventory in Step 5. Rows (names are the `It` strings):

- `creates the ~/.local/bin symlink to TARGET and returns 0 when ~/.local/bin is on PATH` (LinuxOnly; asserts `[ link -ef target ]` true via bash)
- `returns 3 and says NOT on PATH once per version when ~/.local/bin is not on PATH` (LinuxOnly; second run: no message, still 3; stamp `.path-note.9.9.9` exists)
- `repairs a dangling symlink` (LinuxOnly; pre-create link to a missing target; after: `-ef` true, exit 0)
- `repairs a symlink into another data dir` (LinuxOnly; pre-create link to a second fixture binary; after: `-ef` the right target)
- `leaves a regular file alone and names it` (pre-create a regular file; after: still a regular file, stderr names the path, exit 2)
- `skips with CLAVITY_SKIP_PATH=1 and says so` (no link, exit 0, stderr contains `skipped`)
- `skips when .no-launcher exists and names the marker` (no link, exit 0, stderr contains `.no-launcher`)
- `windows: spawns nothing when the data dir is already in PATH in either form` (OSTYPE `msys`, BIN_DIR `C:\Users\u\d\bin`, PATH contains `/c/users/u/d/bin`; fake powershell logs calls to a file; assert the log is absent; exit 0)
- `windows: appends via powershell when absent, never setx` (fake powershell records its `-Command` argument; assert it contains `GetEnvironmentVariable('Path','User')` and `SetEnvironmentVariable` and not `setx`; exit 0)
- `windows: a missing powershell.exe is a message and exit 2`
- `unix steady state runs on builtins alone: exit 0 and silence with PATH holding only the link dir` (LinuxOnly; `OSTYPE=linux-gnu`, link present, `PATH` set to the fixture `.local/bin` ONLY, so `[ -L ]`, `[ -ef ]` and `case` are all that can succeed and any external command would print `command not found` to stderr; assert exit 0 and stderr empty)
- `windows steady state runs on builtins alone: exit 0 and silence with PATH holding only BIN_DIR` (every OS; `OSTYPE=msys`, `PATH` set to the fixture `data/bin` ONLY in the `/c/...` form the normalisation accepts, no shim dir, so a wrongly-taken `cygpath` or `powershell.exe` call prints `command not found`; assert exit 0 and stderr empty)
- `windows steady state spawns zero processes` (`-Tag 'WindowsOnly' -Skip:(-not $IsWindows)`: `Measure-BashHookProcesses` at `BashHookHelpers.ps1:246` is a kernel32 job-object counter and `hook-spawn-budget.Tests.ps1:60` skips its rows the same way; `OSTYPE=msys`, BIN_DIR on PATH; wrapper that sources the lib and calls the function; expect 0. This is the branch Windows runs in production, so it is the one the counter pins)

- [ ] **Step 2: Run the suite to verify it fails**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/clavity-ls-launcher-lib.Tests.ps1 -Output Detailed"`
Expected: every row fails (`No such file` for the lib).

- [ ] **Step 3: Implement `clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh`**

Header comment as the sibling hooks (copyright block, "dotnet-only, dot-sourced by fetch-clavity-ls.sh and run standalone by install.sh"). Builtins only on the steady-state checks: Unix `[ -L "$link" ] && [ "$link" -ef "$TARGET" ]` and a `case ":$PATH:" in *":$HOME/.local/bin:"*)` test; Windows: normalise with parameter expansion (`${x//\\//}`, `${x,,}`, drive `c:` to `/c`) and loop `IFS=:` over `$PATH`; the normalisation accepts BOTH `C:\...` and `/c/...` inputs, and if Task 0's handoff has returned item (a) its measured form is the one the Windows rows feed, otherwise the rows feed both forms and the spec's item 2 gets `UNVERIFIED-WINDOWS` (cleared by Task 7 Step 3). Placement: `mkdir -p "$HOME/.local/bin"` then `ln -sfn "$TARGET" "$link"`. The PowerShell script text (one string): read User Path, split on `;`, append the dir if no entry equals it case-insensitively, `SetEnvironmentVariable('Path', $new, 'User')`.
Then in `fetch-clavity-ls.sh`, after the `_note` definition (line 55), add `_launcher_say() { _say "$1"; }`, the `d=` idiom from Files, and `[ -f "$d/clavity-ls-launcher-lib.sh" ] && . "$d/clavity-ls-launcher-lib.sh"` (no call, no message when absent; every existing row of `fetch-clavity-ls.Tests.ps1` and the budget row must stay green since sourcing spawns nothing).

- [ ] **Step 4: Run the suite to verify it passes**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/clavity-ls-launcher-lib.Tests.ps1 -Output Detailed"`
Expected: all rows PASS.

- [ ] **Step 5: Register the suite and the file, run the registration gates**

Edit `justfile:130` (append the suite), `_partition.md` (one line), twin-parity `$script:DotnetOnly`. Update the skip inventory. `-WriteSkipInventory` rewrites ONLY the section of the OS it runs on (`run-pester-parallel.ps1:253-257`, `Read-InvSection $lines $script:Os`), so on this Linux machine: run `pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory` (captures the `WindowsOnly` row under `## linux`), then add the `LinuxOnly` rows under `## windows` / `### static` by hand in the generated row format, sorted with their neighbours, exactly these five:
```
| clavity-ls-launcher-lib.Tests.ps1 | clavity-ls-launcher-lib.creates the ~/.local/bin symlink to TARGET and returns 0 when ~/.local/bin is on PATH | LinuxOnly | - |
| clavity-ls-launcher-lib.Tests.ps1 | clavity-ls-launcher-lib.repairs a dangling symlink | LinuxOnly | - |
| clavity-ls-launcher-lib.Tests.ps1 | clavity-ls-launcher-lib.repairs a symlink into another data dir | LinuxOnly | - |
| clavity-ls-launcher-lib.Tests.ps1 | clavity-ls-launcher-lib.returns 3 and says NOT on PATH once per version when ~/.local/bin is not on PATH | LinuxOnly | - |
| clavity-ls-launcher-lib.Tests.ps1 | clavity-ls-launcher-lib.unix steady state runs on builtins alone: exit 0 and silence with PATH holding only the link dir | LinuxOnly | - |
```
(Without them the Windows job fails `SKIP-INVENTORY STALE` at this commit. Task 7 Step 3 (d) regenerates the `## windows` section on a real Windows machine and commits any diff.)
Run: `pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/test-suite-registration.Tests.ps1','scripts/tests/plugin-hooks-twin-parity.Tests.ps1','scripts/tests/plugin-hooks-registration.Tests.ps1','scripts/tests/fetch-clavity-ls.Tests.ps1','scripts/tests/hook-spawn-budget.Tests.ps1') -Output Detailed"` then `just check-injected-context`
Expected: all PASS (the budget rows skip off Windows); exit 0. (The injected-context check walks the whole plugin tree, so the lib's `msg*=` rule is gated here, not only in Task 2.)

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh scripts/tests/clavity-ls-launcher-lib.Tests.ps1 scripts/tests/plugin-hooks-twin-parity.Tests.ps1 scripts/tests/_partition.md scripts/tests/_skip-inventory.md justfile
git commit -m "feat(hooks): clavity-ls launcher library (symlink on Unix, user PATH on Windows)"
```

---

### Task 2: The fetch hook keeps the launcher

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh:92` (the stamp-current early exit) and `:181-185` (after the success message)
- Modify: `scripts/tests/fetch-clavity-ls.Tests.ps1` (`New-Fx` and `Invoke-Fetch` at lines 25-85 gain a fixture HOME for EVERY row; new rows) and `scripts/tests/hook-spawn-budget.Rows.ps1:444-449` (fixture gains HOME and the launcher link)

**Interfaces:**
- Consumes: `clavity_ls_launcher_ensure TARGET BIN_DIR VER` and `_launcher_say` from Task 1.
- Produces: unchanged hook JSON contract; the launcher step runs on the stamp-current path and after a successful fetch, skipped on every failure path.

- [ ] **Step 1: Write the failing rows in `fetch-clavity-ls.Tests.ps1`**

First the suite-level change, which protects the HOST: `Invoke-Fetch` (line 59) sets `HOME` from the host today, so once the hook keeps a launcher, every stamp-current row would write a link into the real `~/.local/bin`. In `New-Fx` create `$fx.Home` = `<fixture>/home` with `.local/bin` inside; in `Invoke-Fetch` add `HOME = $Fx.Home` to `$vars` (line 63) and prepend `$Fx.Home/.local/bin` to the PATH built inside the bash command (line 76, `PATH="$p:$PATH"`) unless a new `[switch]$HomeOffPath` is given. Existing rows keep their assertions: the fixture dir is on PATH, so the stamp-current path stays silent. Then the new rows, using `New-Fx`/`Invoke-Fetch`/`Get-Message`:
(The fetch suite runs on both CI jobs with `OSTYPE=linux-gnu` by default, so the rows below take the lib's Unix branch; the two that assert a symlink are `-Tag 'LinuxOnly' -Skip:($IsWindows)` for the `ln -s` reason in Task 1, and the inventory is regenerated here too.)
- `on the stamp-current path, creates the launcher and stays silent when ~/.local/bin is on PATH` (LinuxOnly; pre-place binary and stamp as the row at line 190 does; after: `$fx.Home/.local/bin/clavity-ls` is a link `-ef` the fixture binary; stdout empty)
- `on the stamp-current path, says NOT on PATH once when ~/.local/bin is off PATH` (`-HomeOffPath`; stdout is one JSON message naming `export PATH`; second run: stdout empty)
- `after a successful fetch, the launcher exists` (LinuxOnly; mode `ok`; link `-ef` target)
- `on a failed lookup, no launcher is created` (mode `fail`; no link)
- `CLAVITY_SKIP_PATH=1 creates no launcher on the stamp-current path`

- [ ] **Step 2: Run the suite to verify the new rows fail**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/fetch-clavity-ls.Tests.ps1 -Output Detailed"`
Expected: the five new rows FAIL, the existing rows PASS (now under the fixture HOME).

- [ ] **Step 3: Update the budget fixture BEFORE the hook changes**

`hook-spawn-budget.Rows.ps1:444-449` (steady state, `-Max 0 -Silent`). This suite runs ONLY on Windows (`hook-spawn-budget.Tests.ps1:60`, `-Skip:(-not $IsWindows)`), where `$OSTYPE` is `msys` and the lib takes its WINDOWS branch: the steady-state test there is "`$BIN_DIR` is on `$PATH`", not a symlink. So the fixture puts its own `data/bin` (the hook's `BIN_DIR`, from `$fx.Env.CLAUDE_PLUGIN_DATA`) on the PATH the hook sees through `$fx.Env.PATH`, and sets `$fx.Env.HOME` = `<fixture>/home` so nothing can reach the host home. The row's `-Max 0` is the oracle that the harness forwarded both. Without this, the first run after Step 4 would spawn `cygpath` and `powershell.exe` against the HOST user PATH and fail the budget. Run the budget suite now: Expected: PASS (the hook does not call the launcher yet).

- [ ] **Step 4: Modify the hook**

Task 1 already sources the lib from the hook's own directory and defines `_launcher_say` after `_note`; a missing lib stays SILENT (no `_note`: `_note` feeds the manual-install message, and fixtures that lack the lib would emit JSON on stdout). Replace line 92 `if [ -x "$TARGET" ] && [ "$_st" = "$VER" ]; then exit 0; fi` with the same test calling `clavity_ls_launcher_ensure "$TARGET" "$BIN_DIR" "$VER"` before `exit 0`. After the success `_say` at line 183 call it again. The function's return code is ignored by the hook (fail-open).

- [ ] **Step 5: Run the suite and the budget rows**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/fetch-clavity-ls.Tests.ps1 -Output Detailed"` then `pwsh -NoProfile -c "Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1 -Output Detailed"`
Expected: all PASS, the steady-state row still at `-Max 0 -Silent` (a count above 0 means the fixture's link or PATH from Step 3 is not what the hook sees: fix the fixture, never the budget).

- [ ] **Step 6: Run the injected-context gate and commit**

Run: `just check-injected-context` then `pwsh -NoProfile -c "Invoke-Pester scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed"` then add the two `LinuxOnly` rows under `## windows` / `### static` of `scripts/tests/_skip-inventory.md` by hand (the writer only rewrites the host OS section, see Task 1 Step 5), keys `fetch-clavity-ls.sh tells the user what happened.<It string>`:
```
| fetch-clavity-ls.Tests.ps1 | fetch-clavity-ls.sh tells the user what happened.after a successful fetch, the launcher exists | LinuxOnly | - |
| fetch-clavity-ls.Tests.ps1 | fetch-clavity-ls.sh tells the user what happened.on the stamp-current path, creates the launcher and stays silent when ~/.local/bin is on PATH | LinuxOnly | - |
```
Expected: exit 0; PASS (still green: the lib has been referenced since Task 1); `pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md` (check mode, no write) passes on Linux.
```bash
git add clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh scripts/tests/fetch-clavity-ls.Tests.ps1 scripts/tests/hook-spawn-budget.Rows.ps1 scripts/tests/_skip-inventory.md
git commit -m "feat(hooks): fetch-clavity-ls keeps the clavity-ls launcher on PATH"
```

---

### Task 3: `install.sh`

**Files:**
- Create: `install.sh` (repository root, mode 755)
- Create: `scripts/tests/install-sh.Tests.ps1`
- Modify: `justfile:130` (append the suite), `scripts/tests/_partition.md` (one line)

**Interfaces:**
- Consumes: Task 1's standalone invocation `bash <lib> TARGET BIN_DIR VER`; the hook's CLI contract (env `CLAUDE_PLUGIN_ROOT` = the plugin's `installPath`, `CLAUDE_PLUGIN_DATA` = `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/clavity-clavity` per spec:198, layout `<config>/plugins/data/<plugin>-<marketplace>` measured 2026-11-10; stderr text, stdout JSON, exit 0); `claude plugin marketplace list --json` (array of `{name, source, repo|url}`), `claude plugin list --json` (array of `{id, version, scope, enabled, installPath, installedAt, lastUpdated, projectEnabled}` where `id` is the FIRST key of every object and an object may carry a nested `mcpServers` object, measured 2026-11-10 on `clavity@clavity`); `clavity-dotnet-setup.sh:55-66,81-84` (agy registration pair and the `$DATA/.agy-registered` stamp holding the plugin version).
- Produces: CLI `install.sh [--with a,b,c] [--all] [--dry-run] [--no-launcher] [--launcher]`; env `CLAUDE_CONFIG_DIR` (default `$HOME/.claude`), `CLAVITY_SKIP_PATH`, `CLAVITY_SKIP_AGY`, `CLAVITY_INSTALL_LIB` (path to a local launcher lib; when set, no fetch of the lib), `CLAVITY_INSTALL_RAW_BASE` (default `https://raw.githubusercontent.com/ckir/clavity/main`; the lib is fetched from `$CLAVITY_INSTALL_RAW_BASE/clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh`, its path in this repository, which is what spec:216 "next to install.sh" means: the same branch, not the repository root). Exit codes 0/1/2/3 as in Global Constraints. The last line of stdout is the launch line.

- [ ] **Step 1: Write the failing suite**

`scripts/tests/install-sh.Tests.ps1`: a fixture with a shim dir holding fake `claude` (records argv to a log file; serves canned `--json` for `plugin marketplace list` and `plugin list`, driven by env `FAKE_MARKETS` and `FAKE_PLUGINS` JSON strings), fake `agy` (records argv), fake `powershell.exe` (records its `-Command`, returns a configurable User Path), fake `curl` (copies from a served dir). The fixture also holds a fake plugin dir with `plugin.json` (`"version": "9.9.9"`), a stub `hooks/fetch-clavity-ls.sh` that writes `BIN` to `$CLAUDE_PLUGIN_DATA/bin/clavity-ls.exe` and prints one line to stderr, and the real launcher lib passed through `CLAVITY_INSTALL_LIB`. Rows:

- `adds the clavity marketplace only when no entry has repo ckir/clavity`
- `adds the superpowers marketplace only when absent AND no superpowers@* plugin is enabled`
- `installs superpowers only when no superpowers@* id is enabled, with -y --scope user`
- `installs clavity@clavity then each --with add-on, and --all installs all three`
- `reports an enabled plugin as already installed and does not reinstall`
- `extracts installPath for clavity@clavity when it is listed LAST` (Review Focus 3)
- `extracts installPath and version when the clavity@clavity object carries a nested mcpServers object and another plugin with its own installPath follows` (the canned `FAKE_PLUGINS` for this row is the measured shape: `id, version, scope, enabled, installPath, installedAt, lastUpdated, mcpServers{clavity-ls{command,args[],env{}}}, projectEnabled`, then a second object)
- `unescapes a JSON-encoded Windows installPath` (`"C:\\Users\\u\\.claude\\plugins\\cache\\clavity\\clavity\\9.9.9"` in the JSON yields single backslashes)
- `deletes the fail stamp before running the hook` (Review Focus 4)
- `runs the hook with CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA exported`
- `runs the agy pair and writes .agy-registered with the version when agy is on PATH`
- `says registration happens at the first session start when agy is absent`
- `skips the agy pair with CLAVITY_SKIP_AGY=1 and says so`
- `exit 0 happy path: link in place, dir on PATH, plugin enabled, launch line last`
- `exit 1 when claude is not on PATH`
- `exit 2 when the binary does not run after the hook, naming it`
- `exit 2 when clavity@clavity is not enabled after install`
- `exit 3 with CLAVITY_SKIP_PATH=1 on Unix, status line says NOT on PATH, launch line carries export PATH`
- `exit 3 with CLAVITY_SKIP_PATH=1 on Windows, never 2` (Review Focus 5; OSTYPE `msys`, fake powershell returns a Path without the dir; launch line names the full data path)
- `--no-launcher writes .no-launcher and exits 3 naming the marker; --launcher removes it and exits 0`
- `--dry-run prints the commands and runs none` (claude log empty)
- `an unknown flag prints the usage line and exits 1 before running anything` (claude log empty)
- `a truncated script runs nothing` (feed the first half of the file to `bash`; claude log empty)
- `fetches the lib from RAW_BASE/clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh when CLAVITY_INSTALL_LIB is unset` (fake curl records its URL argument; the served dir holds the lib at that relative path; exit 0 afterwards)
- `a failed lib fetch is a warning naming the URL, not exit 2` (fake curl fails for that URL only; status line still printed; exit is 3 on Unix with CLAVITY_SKIP_PATH unset and no link, never 2)
- `launch line names the git toplevel when run inside a repo, else the placeholder`

- [ ] **Step 2: Run the suite to verify it fails**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/install-sh.Tests.ps1 -Output Detailed"`
Expected: all rows FAIL (`install.sh: No such file`).

- [ ] **Step 3: Implement `install.sh`**

Functions in order: `parse_args` (walks `"$@"` into `WITH` (comma list), `ALL`, `DRY_RUN`, `LAUNCHER_MODE` = `""|no|yes`; an unknown argument prints one usage line naming the five flags and returns 1, before any command runs), `preconditions`, `ensure_marketplaces`, `ensure_plugins`, `locate_plugin` (bash only, no jq, and NO brace-bounded `[^{}]*` match: the object nests `mcpServers`, so such a match fails. Do: `[[ $json =~ \"id\"[[:space:]]*:[[:space:]]*\"clavity@clavity\"(.*) ]]` and take `rest=${BASH_REMATCH[1]}`; cut it at the next plugin's id key with `obj=${rest%%\"id\"*}` (`%%` removes the longest suffix, so it cuts at the FIRST following `"id"`); then `[[ $obj =~ \"installPath\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]` and the same for `\"version\"`; JSON-unescape the path: `\\` to `\` and `\/` to `/`), `run_hook` (`ROOT=<installPath from locate_plugin>`, `DATA="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/data/clavity-clavity"`, `mkdir -p "$DATA/bin"`; delete `$DATA/bin/.clavity-ls.version.fail`; `export CLAUDE_PLUGIN_ROOT="$ROOT" CLAUDE_PLUGIN_DATA="$DATA"`; `bash "$ROOT/hooks/fetch-clavity-ls.sh" >/dev/null`), `register_agy`, `run_launcher` (unless `CLAVITY_INSTALL_LIB` is set, `curl -fsSL "$CLAVITY_INSTALL_RAW_BASE/clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh"` into a `mktemp -d` removed on exit; a failed fetch is a warning naming the URL and the step is SKIPPED (`[ -f "$lib" ] && bash "$lib" "$DATA/bin/clavity-ls.exe" "$DATA/bin" "$VERSION"`: running bash on a missing path would exit 127 and abort before the status line); `verify` still runs and reports exit 3 when nothing resolves), `verify` (two tiers), `launch_line`, `main "$@"` on the last line. All messages to stdout one line each, prefixed `[clavity install]`.

- [ ] **Step 4: Run the suite to verify it passes**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/install-sh.Tests.ps1 -Output Detailed"`
Expected: all PASS.

- [ ] **Step 5: Register the suite, run the registration gate, commit**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/test-suite-registration.Tests.ps1 -Output Detailed"`
Expected: PASS.
```bash
git add install.sh scripts/tests/install-sh.Tests.ps1 scripts/tests/_partition.md justfile
git commit -m "feat: install.sh - agent-runnable clavity install (plugins, hook, agy, launcher, launch line)"
```

---

### Task 4: `INSTALL.md`

**Files:**
- Create: `INSTALL.md` (repository root)

**Interfaces:**
- Consumes: Task 3's CLI, env and exit codes; Task 0's measured result.
- Produces: the agent-facing contract the sentence points at.

- [ ] **Step 1: Write `INSTALL.md`** with exactly these sections, in this order, each a short paragraph or list (spec section 3):

1. Opening two lines: "You are a coding agent (Claude Code, Antigravity, or another) installing clavity for the person you are working with. Follow these steps in order and relay the closing message verbatim."
2. Preconditions the agent checks: `claude` on PATH; `curl`, `tar`, `sha256sum` or `shasum`. Missing: tell the human what to install and stop.
3. The command, two forms: the bash form (Linux, macOS, Claude Code on Windows) and the pwsh form (an agent whose shell is PowerShell, such as agy on Windows), both copied verbatim from spec section 3 including the `try/finally`. `--with agy-autotrain,commonmemory,review-relay` appended only when the human asked for add-ons; name what commonmemory and review-relay need outside the plugin.
4. Verify: `clavity-ls --version` in a NEW terminal, `claude plugin list`.
5. Exit codes and what to do with each: 0, 1, 2, 3 as in spec section 3.
6. Closing message, verbatim (the launch line), plus: do not run `clavity-ls start` yourself; if you are Claude Code, do not claim the `agy_*` tools work in this session; if you are agy, this session is not the pair.
7. clavity-classic note (Windows-only, mutually exclusive, Releases page by the human).
8. Troubleshooting: fetch failed (offline, rate-limited); `~/.local/bin` not on PATH; Windows new console window, not an editor tab; `.no-launcher` present (`--launcher`).

If Task 0 measured "no", section 6 instead tells the agent to end with the terminal line for the human to run, and section 3 is marked "humans in a terminal".

- [ ] **Step 2: Check the file against the two agent kinds by reading it as each** (no tool; a reviewer pass): every command is runnable as pasted, no `claude plugin` command is left for the human. Then commit:
```bash
git add INSTALL.md
git commit -m "docs: INSTALL.md - agent-facing clavity install contract"
```

---

### Task 5: README, Greek README, site

**Files:**
- Modify: `README.md:67-90` (install section)
- Modify: `README.el.md:61-82` (same section in Greek)
- Modify: `site/index.html:198-213` (`#install` section)
- Modify: `.github/site-checks/test_check_site.py:68-79` (`CLEAN_COMMANDS`, `README_COMMANDS`)

**Interfaces:**
- Consumes: the sentence, the terminal line, the two superpowers commands (Global Constraints).
- Produces: README's first `marketplace add` fenced block now has SEVEN `claude plugin` lines, in this order: `claude plugin marketplace add obra/superpowers-marketplace`, `claude plugin install superpowers@superpowers-marketplace`, `claude plugin marketplace add ckir/clavity`, `claude plugin install clavity@clavity          # clavity-dotnet`, then the three add-ons unchanged.

- [ ] **Step 1: Update the site-check fixtures first (the failing test)**

In `test_check_site.py:68-79` set `CLEAN_COMMANDS` to the seven commands above (the fourth without the comment) and set `README_COMMANDS` to exactly:
```python
README_COMMANDS = [
    *CLEAN_COMMANDS[:3],
    CLEAN_COMMANDS[3] + "          # clavity-dotnet",
    *CLEAN_COMMANDS[4:],
]
```
(today's list derives index 1 and splices `[2:]`; keeping that splice with index 3 would drop one command and duplicate another).
Run: `python3 -m unittest discover -s .github/site-checks`
Expected: PASS (fixtures are self-consistent). Then run the real check:
Run: `python3 .github/site-checks/check_site.py --site site --readme README.md`
Expected: Check 6 reports the two superpowers commands missing from both page and README (this is the failing state).

- [ ] **Step 2: Edit `README.md:67-77`**

Replace the paragraph and block with, in order: one line "Tell your agent" carrying the sentence verbatim (as a blockquote); a line "From a terminal:" with the terminal line in a fenced block (bash); one sentence "Add `--with agy-autotrain,commonmemory,review-relay` for the add-ons."; then the heading-free sentence "What those do, by hand:" followed by the seven-line fenced block. Keep lines 79-90 (binary fetch, release branch, migration link) but change `so nothing lands on your PATH` to `and keeps a clavity-ls launcher on your PATH (a symlink in ~/.local/bin, or the plugin's data dir on the Windows user PATH)`.

- [ ] **Step 3: Edit `README.el.md:61-82` with this Greek copy**

The sentence and the terminal line stay in English (they are pasted as-is). Prose:
- "Πείτε στον πράκτορά σας:" before the sentence.
- "Από τερματικό:" before the terminal line; "Προσθέστε `--with agy-autotrain,commonmemory,review-relay` για τα πρόσθετα."
- "Τι κάνουν αυτά, χειροκίνητα:" before the seven-line block.
- Replace "επομένως τίποτα δεν προστίθεται στο PATH σας" with "και διατηρεί έναν εκκινητή `clavity-ls` στο PATH σας (symlink στο `~/.local/bin`, ή ο φάκελος δεδομένων του προσθέτου στο PATH χρήστη των Windows)".

- [ ] **Step 4: Edit `site/index.html:198-213`**

Inside `<section id="install">`, before `<ul class="commands">`: a `<p>` "Tell your agent:" with `<code>` holding the sentence's quoted part; a `<p>` "From a terminal:" with `<code>` holding the terminal line (no `data-cmd`, no `data-copy`, no `<a>`). Add two `<li>` entries at the top of the list for the superpowers commands, each with one `data-cmd` and one matching `data-copy` and an `aria-label`, in the same shape as line 203. Update the intro `<p>` (line 200) so it no longer says "Install superpowers first" but "superpowers is installed by the sentence and the script; the lines below are what they run".

- [ ] **Step 5: Run the site checks**

Run: `python3 -m unittest discover -s .github/site-checks && python3 .github/site-checks/check_site.py --site site --readme README.md`
Expected: both exit 0.

- [ ] **Step 6: Commit**

```bash
git add README.md README.el.md site/index.html .github/site-checks/test_check_site.py
git commit -m "docs(site,readme): tell-your-agent install sentence, terminal line, superpowers in the manual block"
```

---

### Task 6: Product docs and the CLI help

**Files:**
- Modify: `clavity-dotnet/README.md:30-35` (Install), `:60-70` (First run, uninstall note)
- Modify: `docs/migrating-from-the-inno-installers.md:54-63`
- Modify: `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs:40-48`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/CliHelpTests.cs:47-54`

**Interfaces:**
- Produces: help text sentence, verbatim: `  To run clavity-ls start from a terminal: the plugin keeps a clavity-ls launcher on PATH (Unix: ~/.local/bin, Windows: the plugin data dir on the user PATH).` and `  Agent-driven install: see INSTALL.md in the repository (one pasted sentence), or run install.sh.`

- [ ] **Step 1: Change the help test first**

In `CliHelpTests.cs:52` replace `Assert.Contains("must be on PATH", help);` with `Assert.Contains("keeps a clavity-ls launcher on PATH", help);` and add `Assert.Contains("INSTALL.md", help);`.
Run: `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter Help_tells_a_cold_reader_how_to_install`
Expected: FAIL.

- [ ] **Step 2: Replace `CliVerbs.cs:44-48`** (the "You do not install this binary separately ..." through "... (Linux/macOS: chmod +x).") with the two produced sentences.
Run the same test. Expected: PASS. Run `dotnet test tests/Clavity.Ls.Tests`. Expected: all PASS.

- [ ] **Step 3: Edit the three docs**

- `clavity-dotnet/README.md:30-35`: after the two commands add "Or paste the sentence in the repository's README to your agent; see INSTALL.md." Lines 62-64 ("First run"): add "clavity-ls is on PATH from the first session start (a launcher the plugin keeps)". Lines 69-70 (uninstall): add "then `rm -f ~/.local/bin/clavity-ls` on Linux/macOS, and remove the plugin data dir from your user PATH on Windows (a reinstall needs neither)."
- `docs/migrating-from-the-inno-installers.md:57-63`: replace "It is **not** placed on your PATH." and the consequence bullet "typing clavity-ls in a terminal no longer resolves" with "The plugin keeps a `clavity-ls` launcher on PATH on every session start (Linux/macOS `~/.local/bin/clavity-ls`, Windows: the data dir on the user PATH), so `clavity-ls start` keeps working from a terminal."

- [ ] **Step 4: Run the docs gates and commit**

Run: `pwsh -NoProfile -c "Invoke-Pester @('scripts/tests/check-member-docs.Tests.ps1','scripts/tests/check-user-facing-docs.Tests.ps1') -Output Detailed"`
Expected: PASS.
```bash
git add clavity-dotnet/README.md docs/migrating-from-the-inno-installers.md clavity-dotnet/src/Clavity.Ls/CliVerbs.cs clavity-dotnet/tests/Clavity.Ls.Tests/CliHelpTests.cs
git commit -m "docs(dotnet): launcher on PATH in README, migration note and clavity-ls --help"
```

---

### Task 7: Acceptance runs and the Windows handoff

**Files:**
- Create: `docs/superpowers/plans/2026-11-10-agent-install-acceptance.md` (transcripts and outputs; published like the plan)
- Modify: `docs/superpowers/specs/2026-11-10-agent-install-design.md` ("Measure first" item 2: record the Windows results)
- Modify: `.gitignore:49` (after the last `!docs/superpowers/plans/...` line add `!docs/superpowers/plans/2026-11-10-agent-install-acceptance.md`; `.gitignore:44` ignores `docs/superpowers/plans/*`, so without this line the `git add` below is refused)

**Interfaces:**
- Consumes: everything above, pushed to the feature branch. The URLs inside INSTALL.md and README point at `main`, which carries none of this until the PR merges. So each acceptance prompt is the sentence with the branch's raw INSTALL.md URL, followed by one line: "Wherever that file says `main` in a URL, use `feat/agent-install`." The runs also export `CLAVITY_INSTALL_RAW_BASE=https://raw.githubusercontent.com/ckir/clavity/feat/agent-install`. The transcript records both substitutions; after the merge, one re-run with the plain sentence (no substitution line) is appended to the evidence file before any release.

- [ ] **Step 1: Claude Code acceptance**

Keep the paths OUTSIDE the subshell so they survive: `cfg="$(mktemp -d)"; repo="$(mktemp -d)"; git -C "$repo" init -q`, then in a SUBSHELL so no flag leaks into Task 8's gates: `( export CLAUDE_CONFIG_DIR="$cfg" CLAVITY_SKIP_PATH=1 CLAVITY_SKIP_AGY=1 CLAVITY_INSTALL_RAW_BASE=https://raw.githubusercontent.com/ckir/clavity/feat/agent-install; cd "$repo"; claude )`; sign in when asked (a new config dir carries no credentials); paste the sentence with the branch's raw INSTALL.md URL followed by the substitution line from Interfaces ("Wherever that file says `main` in a URL, use `feat/agent-install`."). Nothing else. Expected: the agent runs the bash form, reports exit 3 with the status line and the launch line, claims nothing about the current session. Save the transcript and the output of `CLAUDE_CONFIG_DIR="$cfg" claude plugin list --json` (a bare `claude plugin list` would read the HOST config), then `rm -rf "${cfg:?}" "${repo:?}"`.

- [ ] **Step 2: agy acceptance**

Through `agy_ask`: the ask text tells agy to run first, in its own shell, `export CLAUDE_CONFIG_DIR="$(mktemp -d)" CLAVITY_SKIP_PATH=1 CLAVITY_SKIP_AGY=1 CLAVITY_INSTALL_RAW_BASE=https://raw.githubusercontent.com/ckir/clavity/feat/agent-install` and to print `$CLAUDE_CONFIG_DIR` (agy's shell has no `$cfg`; an unset value would fall back to the HOST config), then the sentence with the branch URL and the substitution line. Expected: same outcome shape; the printed dir is under `/tmp`. Save the reply; afterwards tell agy to `rm -rf` that dir and `unset` the four variables.

- [ ] **Step 3: Windows checks via `clavity:platform-handoff`**

Hand off: (a) the textual form of `CLAUDE_PLUGIN_DATA`/`CLAUDE_PLUGIN_ROOT` under git-bash; (b) `git --exec-path` depth on a machine-wide, per-user and Scoop install (whichever exist); (c) `CHERE_INVOKING=1` keeps `bash -l` in the current folder; (d) `pwsh -NoProfile -c "Invoke-Pester scripts/tests/install-sh.Tests.ps1, scripts/tests/clavity-ls-launcher-lib.Tests.ps1, scripts/tests/fetch-clavity-ls.Tests.ps1, scripts/tests/hook-spawn-budget.Tests.ps1"` green on Windows, then `pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory` to regenerate the `## windows` section (the hand-added rows from Tasks 1 and 2 must come back byte-identical; any diff is committed with the evidence). Record results in the spec's "Measure first" item 2.

- [ ] **Step 4: Add the negation line and commit the evidence**

Add the `.gitignore` negation line named in Files, then:
```bash
git add .gitignore docs/superpowers/plans/2026-11-10-agent-install-acceptance.md docs/superpowers/specs/2026-11-10-agent-install-design.md
git commit -m "docs: agent-install acceptance transcripts and Windows measurements"
```

---

### Task 8: Publish the plan files and finish the branch

**Files:**
- Modify: `.gitignore` (after the acceptance line Task 7 added, add `!docs/superpowers/plans/2026-11-10-agent-install.md`)

- [ ] **Step 1: Add the negation line and the plan file; run the gitignore policy suite**

Run: `pwsh -NoProfile -c "Invoke-Pester scripts/tests/gitignore-policy.Tests.ps1 -Output Detailed"`
Expected: PASS.

- [ ] **Step 2: Full gates**

Run: `just test-scripts-fast` then `just test-scripts-slow` (backgrounded, it exceeds the foreground cap) then `cd clavity-dotnet && just test`.
Expected: all green; quote the pass lines.

- [ ] **Step 3: Commit and hand off to `superpowers:finishing-a-development-branch`** (PR to `main`; no release).

```bash
git add .gitignore docs/superpowers/plans/2026-11-10-agent-install.md
git commit -m "docs(plan): publish the agent-install plan"
```
