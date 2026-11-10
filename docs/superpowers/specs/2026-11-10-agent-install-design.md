# Agent-driven install ("tell your agent to install clavity") - design

Date: 2026-11-10. Status: APPROVED 2026-11-10 (commit 592e216f); implemented on feat/agent-install

## Intent and why

A newcomer who has just found the clavity README should be able to hand the install to their coding
agent with one pasted sentence, the way superpowers does for OpenCode ("Tell OpenCode: Fetch and
follow instructions from <INSTALL.md>"). Today the newcomer performs three steps by hand: get the
platform `clavity-ls` binary somewhere they can run it, add this repository as a Claude Code
marketplace, and install the plugins. The owner wants an agent to do all three.

**The agent may be Claude Code or Antigravity (agy), or another agent with a shell and a URL
fetch (owner, 2026-11-10).** A clavity newcomer may well have agy open and no Claude session yet.
Everything agent-facing is therefore written harness-neutral: the sentence says "your agent", the
install file assumes nothing about which agent is reading it, and the one thing that differs between
them, the shell (agy runs pwsh on Windows and bash elsewhere, see
clavity-dotnet/plugin/knowledge/agy-assumptions.md; Claude Code runs git-bash on Windows), is handled
by giving both invocations.

The one step that stays with the human is accepted and fixed: after the install, exit Claude Code and
launch the pair with `clavity-ls start <folder>`. The plugin's MCP server reads its pairing variables
when a session starts, so a session that was already running when clavity was installed cannot pair.
Removing that relaunch would be a change inside `clavity-ls` and is out of scope here.

A defect this fixes on the way: the README "First run" section (clavity-dotnet/README.md:62-64) tells
the user to type `clavity-ls start <folder>`, but nothing in the repository puts `clavity-ls` on
PATH. The plugin's SessionStart hook fetches the binary into `${CLAUDE_PLUGIN_DATA}/bin/clavity-ls.exe`
for the MCP server only, and docs/migrating-from-the-inno-installers.md:57-63 says so. A newcomer
following the README today hits "command not found".

## Goals

- One pasted sentence in the README that a Claude Code session can follow end to end, with no
  `claude plugin` command typed by the human.
- The same steps runnable from a terminal by a human, with one script.
- `clavity-ls` resolves in a new terminal on Windows, Linux and macOS after the install, and keeps
  resolving across plugin updates.
- superpowers is installed when missing, because the README states it as a prerequisite (README.md:17).
- The three add-ons (agy-autotrain, commonmemory, review-relay) are opt-in, one flag away.

## Non-goals

- Removing the exit-and-relaunch step (an MCP-server change; separate project).
- Installing clavity-classic. It ships only as a Windows Inno installer and is mutually exclusive
  with clavity-dotnet (README.md:55-58); the agent-facing file points at the Releases page for it.
- Configuring what the add-ons need outside the plugin (the `@agentmemory/agentmemory` npm package for
  commonmemory, the AiSaveDev browser extension for review-relay). The install file names those needs
  and leaves them to the human.
- A PowerShell install script. Claude Code on Windows runs its shell as git-bash, and the plugin hooks
  are bash already, so one bash script covers all three platforms. A pwsh-only user is told to run it
  from Git Bash.

## Anti-goals

- The pasted sentence must never leave the newcomer believing the clavity tools work in the session
  that ran the install. The agent's last message is the relaunch instruction, every time.
- No second copy of the download logic. The plugin hook is the only code that knows how to fetch,
  verify and place the binary. A copy drifts, and a plugin update would refresh one and not the other.
- No persistent PATH edit that the hook cannot redo idempotently on every session start.

## Constraints (measured 2026-11-10 at 39d9a414)

- `clavity-dotnet/plugin/hooks/fetch-clavity-ls.sh` runs on SessionStart (startup, resume, clear,
  compact; hooks.json:51-54), detects the RID (lines 73-85), lists releases through api.github.com
  (line 120), verifies the `.sha256`, places `${CLAUDE_PLUGIN_DATA}/bin/clavity-ls.exe` on every
  platform under that fixed name, and writes a version stamp so it is first-run-only. It fails open:
  every outcome goes out as hook JSON (`_say` for the user, `_note` for failures) and exit 0. It is
  tested by `scripts/tests/fetch-clavity-ls.Tests.ps1` (Pester, run by `just test-scripts-slow`).
- `${CLAUDE_PLUGIN_DATA}` is the per-plugin persistent dir, kept across plugin updates and cleared on
  uninstall. Observed path: `<config>/plugins/data/clavity-clavity/`, with `<config>` being
  `$CLAUDE_CONFIG_DIR` or `~/.claude`. The installed version's cache path is recorded in
  `<config>/plugins/installed_plugins.json` under the key `clavity@clavity` (`installPath`).
- `claude plugin marketplace add`, `claude plugin install` and `claude plugin list` run
  non-interactively and from inside a running Claude session (measured in this session).
  `claude plugin list --json` returns an array of `{id, version, scope, enabled, installPath, ...}`
  with ids like `clavity@clavity`; `installPath` is the plugin directory itself (it holds `hooks/`,
  `plugin.json`, `skills/`). `claude plugin marketplace list --json` returns an array of
  `{name, source, repo|url, installLocation}`; the superpowers marketplace is named
  `superpowers-marketplace` with repo `obra/superpowers-marketplace`, clavity's is `clavity` with
  repo `ckir/clavity`. No `installed_plugins.json` parsing is needed.
- The hook has a pinned process budget: `scripts/tests/hook-spawn-budget.Rows.ps1:444-449` requires
  ZERO processes and no output on the steady-state path (binary installed, stamp matches). Every
  `_say` text must be a `msg*=` assignment for `scripts/check-injected-context.ps1`. After a failed
  lookup the hook writes `.clavity-ls.version.fail` and skips retries for 600 s (lines 98-110).
- Site Check 3 (raw.githubusercontent.com forbidden) applies to `href` attributes only
  (check_site.py:311-323); a URL in page text or inside `<code>` is not checked.
- `clavity-dotnet/src/Clavity.Ls/ProfileSetup.cs:38-40` refuses to run without the `agent-profile`
  tool on PATH, so its marketplace-and-install loop cannot be reused as-is. It stays untouched.
- The site is contract-bound to the README: `.github/site-checks/check_site.py` Check 6 (lines
  474-516) requires the `#install` section's `<code data-cmd>` list to equal, as a multiset, the
  `claude plugin ...` lines of the README's first fenced block containing `claude plugin marketplace
  add`, and flags any `claude plugin` text anywhere else on the page. Check 3 (lines 282-283) rejects
  any raw.githubusercontent.com link to this repository on the site. The comment at
  site/index.html:196 says a README install-block change must change the page in the same PR.
  README.el.md:61-70 mirrors the block in Greek.
- Release assets are `clavity-ls-<rid>-<ver>.tar.gz` plus `.sha256` under the `clavity-v<N>` release,
  one file inside the archive. The `clavity` plugin is served from the `release` branch
  (.claude-plugin/marketplace.json), the add-ons from the default branch.

## Approaches considered

1. **Bootstrap scripts do everything** (agy's recommendation line). `install.sh` and `install.ps1`
   detect the platform, download and verify the binary, put it on PATH, add the marketplaces and
   install the plugins. Deterministic and human-runnable, but a second copy of the download logic,
   and the PATH copy goes stale when a plugin update re-fetches the hook's copy.
2. **The hook keeps a launcher on PATH, plus a thin install file** (driver's recommendation, and the
   disposition agy named as the one that "collapses the problem"). The existing fetch hook also
   maintains a `clavity-ls` launcher on PATH pointing at its own copy. The agent-facing file then only
   runs plugin commands and the hook once. One download path; updates refresh the launcher for free.
   Cost: a Windows user-PATH write from a bash hook, through PowerShell.
3. **A `clavity-ls setup` verb** reusing `ProfileSetup`. Dropped: the code refuses without
   agent-profile, and the verb that puts the binary on PATH cannot be invoked before the binary is on
   PATH.

**Owner's pick (2026-11-10): "Both"** - approach 2 for the plugin, plus a single `install.sh` that
wraps the same steps for terminal users and is also what the agent runs. The script holds no download
logic; it calls the hook.

## The design

### 1. The fetch hook maintains a launcher on PATH

The launcher logic lives in its own file, `clavity-dotnet/plugin/hooks/clavity-ls-launcher-lib.sh`
(the `-lib.sh` suffix is the convention `scripts/tests/plugin-hooks-registration.Tests.ps1:181` carves
out for dot-sourced libraries that are not registered in hooks.json; the file is also added to the
`$DotnetOnly` list of `scripts/tests/plugin-hooks-twin-parity.Tests.ps1`, which otherwise flags any
hook file missing from clavity-classic). It holds one function and a guarded standalone entry point.
`fetch-clavity-ls.sh` sources it (the `.` builtin costs no process) and calls it on every
SessionStart whenever `$TARGET` exists: after a successful fetch, and on the "stamp is current" early
exit, so an existing install gains the launcher on its next session start. `install.sh` (below) runs
the same file standalone. Its messages are its own `msg*=` lines passed to `_say`; it never uses
`_note`, whose text appends "install clavity-ls manually and place it at $TARGET", which is wrong for
a launcher failure.

- **Steady state spawns nothing.** The check that the launcher is already right uses builtins only:
  on Linux and macOS `[ -L "$link" ] && [ "$link" -ef "$TARGET" ]` (`-ef` is a builtin that follows
  the link and compares inodes, measured 2026-11-10: true through a live link, false for a dangling
  one or a link into another profile's data dir, so both are recreated); on Windows a `case` match of
  the data dir against `$PATH` after normalising both to lower case with forward slashes and the
  `/c/` drive form (parameter expansion only). `readlink` is never used. The pinned budget row stays
  at zero. The form Claude Code gives `CLAUDE_PLUGIN_DATA` under git-bash on Windows (`C:\...` or
  `/c/...`) is unknown and is measured on Windows (handoff dispatched in the plan's Task 0) before the Windows
  acceptance; if the measurement is late, the normalisation is written to accept both forms and the
  spec records `UNVERIFIED-WINDOWS` until Task 7 clears it.
- **Linux and macOS, when missing or wrong:** create `~/.local/bin` if needed and `ln -sfn` the
  `clavity-ls` link there to `$TARGET` (`-f` because plain `ln -s` fails with "Already exists" on a
  dangling link, measured; the binary is an ELF or Mach-O under a cosmetic `.exe` name, and the link
  gives it the plain name). A regular file already at that path is never replaced: say so, with the
  path, in a `msg*=` line. If `~/.local/bin` is not
  in `$PATH`, `_say` one line with the export to add to the shell profile, once per fetched version
  (a `.path-note.<ver>` stamp beside the version stamp, checked with `[ -f ]`), not on every start.
- **Windows (git-bash, `$OSTYPE` msys or cygwin), when missing:** the native name is already
  `clavity-ls.exe`, so no copy or shim; append the Windows form of `$BIN_DIR` (via `cygpath -w`,
  only on this path) to the user PATH (HKCU) through `powershell.exe -NoProfile -NonInteractive`
  using `[Environment]::GetEnvironmentVariable('Path','User')` and `SetEnvironmentVariable`, never
  `setx` (it truncates at 1024 characters). A missing `powershell.exe` is a `_note`. `_say` that new
  terminals will see it. Plugin uninstall clears the data dir and leaves that PATH entry dangling
  on Windows, and the `~/.local/bin/clavity-ls` symlink dangling on Unix; accepted, and the uninstall
  note of clavity-dotnet/README.md (currently lines 69-70, which name only the `claude plugin
  uninstall` command) gains the two cleanup lines: `rm -f ~/.local/bin/clavity-ls` on Unix, and
  removing the data dir from the user PATH on Windows. A reinstall needs neither: the `-ef` check
  recreates the link and the PATH check finds the entry already there.
- Opt-out, two forms, both honoured by the hook and by `install.sh`: the env var
  `CLAVITY_SKIP_PATH=1` skips the step for that one run (tests, the acceptance run), and the marker
  file `<data>/bin/.no-launcher` skips it durably for anyone who manages PATH themselves (a
  builtin `[ -f ]` check, so the steady-state path stays at zero processes). The hook never writes
  that marker itself; the user creates it, and `install.sh --no-launcher` creates it for them. An
  env-var-only opt-out would be undone at the next session start, since the hook runs the launcher
  step on the "stamp is current" path too.
- Fail-open like the rest of the hook: any failure is a `_note`, exit 0. Every new message is a
  `msg*=` assignment so `check-injected-context.ps1` sees it.

Output stays the hook JSON contract. When the script below runs the hook by hand, it reads that JSON
and prints the `systemMessage` text for the terminal.

### 2. `install.sh` at the repository root

One bash script, usable under Linux, macOS and Git Bash on Windows. Its whole body is a function
invoked on the last line, so a download truncated by a dropped connection executes nothing (the
standard `curl | bash` guard). Steps, each idempotent and each reported on one line:

1. Preconditions: `claude` on PATH; `curl`, `tar`, and `sha256sum` or `shasum`. Missing: print what
   to install, exit 1.
2. `claude plugin marketplace list --json`; add `ckir/clavity` when no entry has that `repo`, and
   `obra/superpowers-marketplace` when no entry has that `repo` AND no `superpowers@*` plugin is
   installed (superpowers may already come from the official marketplace).
3. `claude plugin list --json`; install `superpowers@superpowers-marketplace` when no enabled id
   starts with `superpowers@`, then `clavity@clavity`, then each add-on named by
   `--with agy-autotrain,commonmemory,review-relay` (or `--all`). An id already present and enabled
   is reported as "already installed", not reinstalled.
4. Read `installPath` for `clavity@clavity` from that same JSON (bash regex, as the hook parses the
   release JSON; no `jq`, no python). The extraction is anchored on the object whose `"id"` is
   `clavity@clavity`: it isolates that object's text first and reads `installPath` from it, never
   the first `installPath` in the file (the array also holds `agy-autotrain@clavity` and
   `superpowers@...`; the test feeds a multi-plugin listing with clavity last). Delete
   `<data>/bin/.clavity-ls.version.fail` if present, so a failure within the last 10 minutes does
   not turn this run into a silent no-op. Export `CLAUDE_PLUGIN_ROOT=<installPath>` and
   `CLAUDE_PLUGIN_DATA=<config>/plugins/data/clavity-clavity` for the rest of the script (steps 4
   and 5 both need them), with `<config>` = `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, then run
   `bash <installPath>/hooks/fetch-clavity-ls.sh`. This fetches the binary now instead of at the
   next session start. The hook is fail-open: it exits 0 on every outcome, prints its message as
   plain text on stderr (`fetch-clavity-ls.sh:46`) and as hook JSON on stdout. The script lets
   stderr through untouched and discards stdout, so no JSON parsing, and a rate-limited or offline
   fetch shows the hook's own "download failed" or "no release asset" line right there; step 6 then
   decides pass or fail. Plugin installs pass `-y --scope user`, the flags `ProfileSetup.cs:101`
   already uses non-interactively.
   Then, when `agy` is on PATH, register the plugin with agy exactly as
   `clavity-dotnet/plugin/hooks/clavity-dotnet-setup.sh:81-84` does at session start
   (`agy plugin uninstall clavity` then `agy plugin install <installPath>`), and on success write
   the hook's own stamp, `<data>/.agy-registered` holding the plugin version from
   `<installPath>/plugin.json` (setup hook lines 55-66), so the next session start sees it as done
   and does not repeat the pair. A failure is a warning carrying the same manual remedy the hook
   prints, never an exit 2. When `agy` is not on PATH, say so in one line: registration then happens
   at the first Claude session start, by that hook. (`clavity-ls install` is NOT used: it is the
   retired installer's PowerShell registrar path, `Install/PluginInstaller.cs:14-21`.)
5. Run the launcher step through `clavity-ls-launcher-lib.sh` fetched from this repository at
   `main` next to `install.sh` itself, not the installed plugin's copy. This covers an installed
   plugin whose hook predates the launcher step (the plugin is served from `release`, which advances
   only on an owner-approved release, while `install.sh` and README come from `main`). The step is
   idempotent, so when the hook already did it, it does nothing. A failed fetch of this file is a
   warning, not a failure: step 6 decides.
6. Verify, in two tiers. Hard checks (exit 2 when any fails, naming which one, with the hook's own
   message repeated): `<data>/bin/clavity-ls.exe --version` succeeds (the data path, not the
   current shell's PATH, which may predate the edit), and `claude plugin list --json` shows
   `clavity@clavity` enabled. Resolution check (exit 3 when it fails, never 2, on every platform):
   a new terminal will resolve `clavity-ls`, meaning on Unix the link satisfies `[ link -ef target ]`
   AND its directory is in `$PATH`, and on Windows the data dir is present in the USER PATH as read
   back through `powershell.exe` from the registry (never from the running git-bash's `$PATH`, which
   cannot see a registry change made during its own lifetime; a fresh append by the hook counts,
   since new consoles read the registry). One visible status line reports it:
   `clavity-ls will resolve in new terminals` (on Windows the line adds: a new console window, not a
   new tab inside an editor whose terminal was already open, since that tab inherits the editor's
   environment), or `clavity-ls is NOT on PATH yet: <what to do>`,
   which on Unix is the export line (or the missing link, if the launcher step was skipped) and on
   Windows is the manual PATH edit. Step 6 never reports plain success for a `clavity-ls` that a new
   terminal cannot resolve without that stated action, and the exit code says so (below).
7. Print the launch line last, verbatim:
   `If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: clavity-ls start <folder>`.
   An agy that performed this install is not the pair: `clavity-ls start` opens its own agy tab and
   waits for that one. `<folder>` is the top of the git repository the script runs in
   (`git rev-parse --show-toplevel`, stderr suppressed), else the literal placeholder. When step 6
   reported "NOT on PATH yet", the line still works as pasted on every platform: on Unix it carries
   the `export PATH=...` prefix, on Windows it names the binary by its full data path
   (`& "<data>\bin\clavity-ls.exe" start <folder>`), so a status line that scrolled away costs
   nothing.

Exit codes: 0 all steps done and `clavity-ls` will resolve in new terminals, 1 precondition
missing, 2 binary not runnable or plugin not enabled after the steps (which one is on stderr), 3 all
steps done but `clavity-ls` is NOT on PATH yet (the status line and the launch line carry the
action; an agent must not report plain success on 3). `--dry-run` prints the commands it would
run. `--no-launcher` writes the durable `<data>/bin/.no-launcher` marker and skips the launcher
step; `--launcher` removes that marker and runs the step, which is the way back (a plain run never
touches the marker). When the marker is the reason the launcher step was skipped, the step-6 status
line says so by name, so an exit 3 is never unexplained. `CLAVITY_SKIP_PATH=1` skips the launcher step for this run and `CLAVITY_SKIP_AGY=1` skips
the agy registration step, each with a visible line (both exist for tests and the acceptance run).
Add-on
prerequisites that live outside the plugin (the agentmemory npm package, the AiSaveDev extension) are
printed as notes, not installed.

### 3. `INSTALL.md` at the repository root (agent-facing)

Written for the agent, like superpowers' `.opencode/INSTALL.md`, and harness-neutral: it never
assumes the reader is Claude Code. It is short and must contain:

- What it is doing and for whom, in two lines: "You are a coding agent (Claude Code, Antigravity, or
  another) installing clavity for the person you are working with."
- Preconditions the agent checks first: Claude Code installed (`claude` on PATH), because the plugins
  are Claude Code plugins even when agy performs the install.
- The one command to run: fetch `install.sh` from this repository at `main`
  (`https://raw.githubusercontent.com/ckir/clavity/main/install.sh`) and run it with bash, passing
  `--with ...` only if the human asked for add-ons. Two invocations, the agent picks by its shell:
  the bash form (Linux, macOS, and Claude Code on Windows, whose shell is git-bash):
  `curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s -- [--with ...]`
  (`-s --` is what lets a piped script take flags; measured: `| bash --with x` fails with
  "invalid option", `| bash -s -- --with x` passes it through), and the pwsh form for an agent whose
  shell is PowerShell (agy on Windows), given in full:
  `$bash = if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $env:CLAUDE_CODE_GIT_BASH_PATH } else { Join-Path (Resolve-Path (Join-Path (git --exec-path) '..\..\..')) 'bin\bash.exe' }; try { $env:CHERE_INVOKING = 1; & $bash -lc 'curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s --' } finally { Remove-Item Env:CHERE_INVOKING -ErrorAction SilentlyContinue }`
  (the `try/finally` keeps `CHERE_INVOKING` out of the agent's own shell session afterwards)
  with the `--with` flags appended inside the single quotes when asked for. `bash.exe` is located
  from `git --exec-path` (`<Git>\mingw64\libexec\git-core`, three levels below the Git root), which
  resolves through Scoop or Chocolatey shims and holds for the machine-wide and per-user layouts
  alike; the env var is only an override when a Claude Code user has set it. The login shell (`-l`)
  is needed for Git's `usr/bin` (where `sha256sum` lives) to be on PATH, and `CHERE_INVOKING=1`
  stops that login shell from changing directory to `$HOME` (MSYS2 `/etc/profile` behaviour, to be
  confirmed in "Measure first" item 2), so the launch line still names the project folder. Git for
  Windows is present on any machine with Claude Code installed, which the preconditions require.
- The exit-code contract and what the agent does with each: 0, relay the launch line as success;
  1, a precondition is missing, relay the script's line naming it and stop; 2, a step failed, relay
  the script's stderr and stop, do not retry in a loop; 3, installed but `clavity-ls` is not on PATH
  yet, relay BOTH the status line's action and the launch line, and never call it plain success.
- How to verify (`clavity-ls --version`, `claude plugin list`).
- The exact closing message to give the human, which is the launch line above, and the rules that the
  agent must not run `clavity-ls start` itself, and (when it is Claude Code) must not claim the
  `agy_*` tools are usable in the current session. For agy the message is the same: `clavity-ls start`
  opens its own agy tab and Claude session; the agy session that ran the install is not the pair.
- The clavity-classic note: Windows-only, mutually exclusive with clavity-dotnet, installed from the
  Releases page by the human.
- Troubleshooting: the fetch failed (offline, rate-limited): rerun later, or place the binary by hand
  as the hook's own message says; `~/.local/bin` not on PATH: the export line.

### 4. The sentence, and the three surfaces that carry it

The sentence is identical everywhere, and uses the raw URL as superpowers does, because that is what
an agent's fetch tool reads most reliably:

> Tell your agent: `Fetch and follow the instructions at https://raw.githubusercontent.com/ckir/clavity/main/INSTALL.md`

The terminal line is likewise identical everywhere:

> `curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s --`

Driver's call: both are page TEXT inside `<code>` on the site, never an `href`, which is all Check 3
inspects. Neither contains the words `claude plugin`, so Check 6's page-text rule is untouched.

- **README.md install section** (lines 67-100): the sentence first, then "From a terminal" with the
  `curl | bash` line (add-on flags shown once), then the manual command block, which gains two
  lines at its top (`claude plugin marketplace add obra/superpowers-marketplace` and
  `claude plugin install superpowers@superpowers-marketplace`) so the block documents exactly what
  the script does, including the prerequisite README.md:17 already states. README.el.md mirrors
  all three.
- **site/index.html `#install`**: the sentence and the terminal line as plain `<code>` (no
  `data-cmd`, no `data-copy`) above the `<ul class="commands">` list, which gains the same two
  superpowers `<li>` entries (Check 6 pins the list to the README block). Check 6 and Check 3 need
  no code change, but their test fixtures do: `.github/site-checks/test_check_site.py:68-79`
  (`CLEAN_COMMANDS`, `README_COMMANDS`) pin the five current commands and gain the two superpowers
  lines in the same PR. If the builder finds a check itself must change, it changes in the same PR
  with its tests.
- **clavity-dotnet/README.md** "Install" and "First run": say that the plugin now keeps `clavity-ls`
  on PATH and point at INSTALL.md. **`clavity-ls --help`** (`CliVerbs.cs:40-48`) currently tells the
  user to download the tarball and put the binary on PATH by hand; it changes to the same two
  sentences (the plugin keeps the launcher on PATH; the agent sentence and `install.sh` do the rest).
  `tests/Clavity.Ls.Tests/CliHelpTests.cs:52` asserts the old "must be on PATH" wording and changes
  with it, keeping an assertion on the new sentence. **docs/migrating-from-the-inno-installers.md:54-63**: the "not
  placed on your PATH" statement becomes "placed as a launcher by the plugin on every session start".

## Measure first (before any code)

Two facts the design rests on are unverified and cheap to measure; the plan's first task measures
them and records the output in this document.

1. A `claude plugin install` run from a Bash tool call INSIDE a running Claude Code session still
   shows as installed and enabled after that session exits. Measure in a throwaway
   `CLAUDE_CONFIG_DIR` with a harmless plugin. This is the feature's core promise; if it fails, the
   agent-facing file must instead end with "exit Claude Code and run the terminal line", and the
   sentence survives only as a pointer.

   Measured 2026-11-10: yes. The install ran inside a headless session (`claude -p`, exit 0) and a
   fresh process afterwards still listed it as enabled. Commands and output, in a throwaway
   `CLAUDE_CONFIG_DIR`:

       claude -p "Run exactly this shell command and print its output: claude plugin install review-relay@clavity -y --scope user" --allowedTools "Bash(claude plugin *)" ; echo "session exit: $?"
       Installing plugin "review-relay@clavity"...✔ Successfully installed plugin: review-relay@clavity (scope: user)
       session exit: 0

       claude plugin list --json | python3 -I -c "import json,sys;print([p['enabled'] for p in json.load(sys.stdin) if p['id']=='review-relay@clavity'])"
       [True]

   (The prompt precedes `--allowedTools` because that flag is variadic and otherwise swallows the
   prompt: "Input must be provided either through stdin or as a prompt argument".)
2. On Windows, via the platform-handoff procedure if no Windows machine is at hand: the textual form
   of `CLAUDE_PLUGIN_DATA` and `CLAUDE_PLUGIN_ROOT` as the hook sees them under git-bash (`C:\...`
   or `/c/...`); that `git --exec-path` sits three levels below the Git root on a machine-wide, a
   per-user and a Scoop install; and that `CHERE_INVOKING=1` keeps `bash -l` in the current folder.

   UNVERIFIED-WINDOWS 2026-11-10: handoff dispatched (docs/handoff/windows-session-3.md, items (a)-(c)); the launcher library's normalisation accepts both forms until Task 7 records the measured one.

## What is tested

- Pester for the hook (`scripts/tests/fetch-clavity-ls.Tests.ps1`): launcher created on Unix after a
  fetch and on the stamp-current path, a foreign regular file left alone with a note, the PATH note
  emitted once per version, `CLAVITY_SKIP_PATH` honoured, the Windows branch's PowerShell invocation
  captured through a fake `powershell.exe` and skipped when `$PATH` already holds the dir, a missing
  `powershell.exe` noted. The spawn-budget row "binary installed, stamp matches" stays at `-Max 0
  -Silent` with the launcher already present in its fixture.
- Pester for `install.sh` with a fake `claude` on PATH recording its argv and serving canned
  `--json` output: marketplaces added only when absent, superpowers installed only when no
  `superpowers@*` is enabled, add-on flags, fail stamp removed, the hook invoked with the right env,
  the launcher script run, the agy registration pair run against a fake `agy` on PATH and the
  `.agy-registered` stamp written on success (and the visible line when `agy` is absent or
  `CLAVITY_SKIP_AGY=1`), exit codes 0, 1, 2 and 3 each reached by a named fixture, the exit-0
  happy path end to end with NO skip flags (fake `claude`, fake `agy`, a fake `powershell.exe` on
  the Windows branch, a temp HOME for the Unix link), `--no-launcher`/`--launcher`, the launch
  line printed last, `--dry-run`. The exit-0 path is proven here, under fakes; the live acceptance
  runs below prove the agents' reading and the exit-3 branch, not the launcher.
- The existing site checks run on the changed page; `just test-scripts-fast`, `check-injected-context`
  and the docs checks (`check-member-docs`, `check-user-facing-docs`) stay green.
- An end-to-end run of INSTALL.md by each agent kind before the PR: a fresh Claude Code session
  given only the sentence, and the live agy peer given only the sentence, each a REAL run (not
  `--dry-run`, which executes nothing) with `CLAUDE_CONFIG_DIR` pointed at a throwaway directory so
  this machine's own plugins are untouched, `CLAVITY_SKIP_PATH=1` so the host's `~/.local/bin`
  link and user PATH are untouched too, and `CLAVITY_SKIP_AGY=1` so the host's agy registration is
  not re-pointed at a throwaway `installPath` that is deleted after the run (agy's plugin registry
  lives in the user's home, outside `CLAUDE_CONFIG_DIR`). Both env vars are honoured by `install.sh`
  (the agy one skips the registration step with a visible line). The launcher and registration
  steps have their own Pester coverage above; the acceptance run therefore ends with exit code 3
  and the "NOT on PATH yet" status, which is itself part of what is checked. Each run ends with the launch line, the right exit code relayed, and
  nothing claimed about the current session. Their transcripts plus `claude plugin list --json` from
  that throwaway config are the acceptance evidence.

## Left to the builder

- Exact wording of the hook's `_say` lines and INSTALL.md prose, within the rules above.
- The bash-regex extraction of `installPath` from `claude plugin list --json` (the hook's release
  JSON parsing is the model; python3 and `jq` are not assumed).
- Whether the Windows PATH entry is the data dir itself or a `~/bin` with a `.cmd` shim. The design
  prefers the data dir because the native name already resolves; switch only if the data path
  contains characters the PATH write cannot carry.
- How `install.sh` fetches `clavity-ls-launcher-lib.sh` (a second `curl` of the raw file at `main` is
  the expected form) and where it keeps it (a temp dir removed on exit).

## Stand-downs

- DISCARDED-BELOW-FLOOR: two Claude sessions starting at once on a Windows machine with no launcher
  could both append the data dir to the user PATH. The PowerShell snippet re-reads PATH before
  appending, so the window is the read-append gap; a duplicate PATH entry has no effect on
  resolution. Benign, not guarded further.
- UNVERIFIED-ACCEPTED (pending "Measure first" item 1): persistence of an in-session
  `claude plugin install` across that session's exit.
- DISCARDED-BELOW-FLOOR (agy panel r1, BS-1): `clavity-ls-launcher-lib.sh` is fetched from `main`
  without a checksum. It comes from the same origin, at the same moment, as `install.sh` itself,
  which the human or agent already chose to execute from that origin (section 2 header); the second
  fetch adds no trust zone the first did not already cross.
- DISCARDED-BELOW-FLOOR (agy panel r1, DC-1): `cygpath -w` is one extra process on Windows. It runs
  only on the one-time "launcher missing" path; the zero-process requirement is pinned on the
  steady-state row only (`scripts/tests/hook-spawn-budget.Rows.ps1:444-449`).
- DISCARDED-BELOW-FLOOR (agy panel r2, RV-1): the unauthenticated GitHub release lookup is one API
  call per `install.sh` run (`fetch-clavity-ls.sh:120`, a single `curl`); the 60-per-hour limit is
  reachable only by a human re-running the installer dozens of times in an hour. Token support in
  the hook is pre-existing behaviour and not part of this design.
- DISCARDED-BELOW-FLOOR (agy panel r2, RV-2): the launcher lib is fetched once per `install.sh`
  run; install runs are rare by construction (section 2 is idempotent and the hook does the
  steady-state work), so one small extra fetch is not a resource concern.
