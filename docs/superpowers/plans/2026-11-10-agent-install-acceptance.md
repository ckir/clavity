# Agent-driven install: acceptance evidence

Branch `feat/agent-install`, HEAD f65ca579, run on 2026-11-10. The URLs in INSTALL.md and the README point at `main`, which does not carry this feature yet, so each run uses two substitutions: the sentence carries the branch's raw INSTALL.md URL followed by the line "Wherever that file says `main` in a URL, use `feat/agent-install`.", and the environment exports `CLAVITY_INSTALL_RAW_BASE` pointing at the branch. After the merge, one re-run with the plain sentence (no substitution line, no `CLAVITY_INSTALL_RAW_BASE`) is appended to this file before any release. Home directory paths are shown as `$HOME` (the only edit to quoted output).

## 1. Claude Code (headless, Linux)

Form used: `--verbose --output-format stream-json` (accepted by this CLI). An interactive session cannot be driven by an agent, so the host sign-in file was copied into the throwaway config dir and the session ran headless with `claude -p`.

Prompt (verbatim, two lines):

```
Fetch and follow the instructions at https://raw.githubusercontent.com/ckir/clavity/feat/agent-install/INSTALL.md
Wherever that file says `main` in a URL, use `feat/agent-install`.
```

Command (cfg and repo are `mktemp -d` dirs under /tmp; repo is an empty `git init`):

```
( export CLAUDE_CONFIG_DIR="$cfg" CLAVITY_SKIP_PATH=1 CLAVITY_SKIP_AGY=1 \
    CLAVITY_INSTALL_RAW_BASE=https://raw.githubusercontent.com/ckir/clavity/feat/agent-install
  cd "$repo"
  claude -p '<prompt above>' --allowedTools 'Bash,WebFetch' --verbose --output-format stream-json )
```

Environment exported: `CLAUDE_CONFIG_DIR` (throwaway), `CLAVITY_SKIP_PATH=1`, `CLAVITY_SKIP_AGY=1`, `CLAVITY_INSTALL_RAW_BASE` (branch). Model reported by the transcript: claude-opus-5-5. 6 turns, about 42 s.

### (a) Commands the agent ran (in order)

1. `mkdir -p /tmp/clavity-dl && curl -fsSL <branch>/INSTALL.md -o /tmp/clavity-dl/INSTALL.md && cat /tmp/clavity-dl/INSTALL.md`
2. `command -v claude; curl -fsSL <branch>/install.sh -o /tmp/clavity-dl/install.sh && wc -l /tmp/clavity-dl/install.sh`
3. a `Read` of the downloaded script (permission denied: Read was not in --allowedTools), then `cat /tmp/clavity-dl/install.sh` to review it
4. the install, bash form:

```
CLAVITY_INSTALL_RAW_BASE=https://raw.githubusercontent.com/ckir/clavity/feat/agent-install bash /tmp/clavity-dl/install.sh; echo "EXIT=$?"
```

(the harness ran it with `cd <repo>` in front.) `<branch>` is `https://raw.githubusercontent.com/ckir/clavity/feat/agent-install`.

### (b) install.sh stdout (verbatim)

```
[clavity install] added marketplace ckir/clavity
[clavity install] added marketplace obra/superpowers-marketplace
[clavity install] installed superpowers@superpowers-marketplace
[clavity install] installed clavity@clavity
[clavity install] clavity@clavity 0.17.0 at /tmp/tmp.171WkjvMIy/plugins/cache/clavity/clavity/0.17.0
[clavity install] running the plugin's fetch hook (downloads clavity-ls now)
[clavity-ls] fetched clavity-ls-linux-x64-0.17.0.tar.gz -> /tmp/tmp.171WkjvMIy/plugins/data/clavity-clavity/bin/clavity-ls.exe. If the clavity-ls MCP server failed to start in this session, run /mcp and reconnect it.
[clavity install] agy registration skipped (CLAVITY_SKIP_AGY=1)
[clavity install] PATH launcher step skipped (CLAVITY_SKIP_PATH=1)
[clavity install] clavity-ls is NOT on PATH yet: the PATH launcher step was skipped (CLAVITY_SKIP_PATH=1), so there is no $HOME/.local/bin/clavity-ls; link it yourself (ln -s "/tmp/tmp.171WkjvMIy/plugins/data/clavity-clavity/bin/clavity-ls.exe" "$HOME/.local/bin/clavity-ls") or use the launch line below
If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: export PATH="/tmp/tmp.171WkjvMIy/plugins/data/clavity-clavity/bin:$PATH"; clavity-ls.exe start /tmp/tmp.euzHbA6EVv
EXIT=3
```

### (c) Exit code the agent reported

3 ("installed, but needs a PATH step from you").

### (d) Agent's final message to the human (verbatim)

> clavity is installed, but `clavity-ls` is **not on your PATH yet**, so it won't start by name in a new terminal. The script exited with code 3, which means "installed, but needs a PATH step from you."
>
> What it did:
> - Added the `ckir/clavity` and `obra/superpowers-marketplace` marketplaces.
> - Installed `superpowers@superpowers-marketplace` and `clavity@clavity` 0.17.0.
> - Downloaded the `clavity-ls` binary through the plugin's fetch hook.
>
> Two steps were skipped because your environment already had `CLAVITY_SKIP_AGY=1` and `CLAVITY_SKIP_PATH=1` set (I didn't set them). So the plugin wasn't registered with agy, and no PATH link was created.
>
> Here are the script's own lines, word for word:
>
> > [clavity install] clavity-ls is NOT on PATH yet: the PATH launcher step was skipped (CLAVITY_SKIP_PATH=1), so there is no $HOME/.local/bin/clavity-ls; link it yourself (ln -s "/tmp/tmp.171WkjvMIy/plugins/data/clavity-clavity/bin/clavity-ls.exe" "$HOME/.local/bin/clavity-ls") or use the launch line below
>
> > If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: export PATH="/tmp/tmp.171WkjvMIy/plugins/data/clavity-clavity/bin:$PATH"; clavity-ls.exe start /tmp/tmp.euzHbA6EVv
>
> Your Claude config folder is under `/tmp`, so the binary is too, and it may be deleted when the machine restarts.
>
> Once you've restarted, check it in a new terminal with `clavity-ls --version`, then `claude plugin list` (clavity should be listed and enabled). The `agy_*` tools won't work in this session; they need that restart first.

(Quoted with the same `$HOME` redaction; the agent's text had the literal home path.)

### Plugin list in the throwaway config (`CLAUDE_CONFIG_DIR="$cfg" claude plugin list --json`)

| id | version | scope | enabled |
|----|---------|-------|---------|
| clavity@clavity | 0.17.0 | user | true |
| superpowers@superpowers-marketplace | 7.0.2 | user | true |
| cowork-plugin-management@synced | 0.2.2 | synced | true |

(the third row is synced in by the account, not by the installer.)

### Binary

`ls -la <cfg>/plugins/data/clavity-clavity/bin`: `.clavity-ls.version` (6 bytes) and `clavity-ls.exe` (78258281 bytes, mode 755).
`clavity-ls.exe --version` prints: `clavity-ls 0.17.0+c356375b`

### Host untouched

- `$HOME/.local/bin/clavity-ls` exists on the host: mtime `2026-11-08 00:00:02 +0200` before the run and the same after; size 78258281.
- Host `claude plugin list --json`: `grep -c superpowers-marketplace` = 2 before and after; `grep -c review-relay` = 0 before and after (unchanged).
- Throwaway dirs removed (`/tmp/tmp.171WkjvMIy`, `/tmp/tmp.euzHbA6EVv`). The agent's download dir `/tmp/clavity-dl` was left in place.

### Verdict

Outcome: differs (minor): the agent ran the bash form, reported exit 3 with the `NOT on PATH yet` status line and the launch line quoted verbatim, but its closing paragraph made one claim about the current session ("The `agy_*` tools won't work in this session; they need that restart first"), and it said "restart" although the script's lines say only to exit and open a new terminal.

## 2. agy (Linux)

Run 2026-11-10 through the clavity-ls `agy_ask` tool from the paired Claude session, at branch HEAD f65ca579 (same
substitutions as section 1). agy ran in its own shell on the same Linux box, with the host HOME (its `~/.local/bin`
holds a hand-placed regular file named `clavity-ls`, not a link).

Setup agy ran first (its own throwaway config, printed back as asked):

    export CLAUDE_CONFIG_DIR="$(mktemp -d)" CLAVITY_SKIP_PATH=1 CLAVITY_SKIP_AGY=1 CLAVITY_INSTALL_RAW_BASE=https://raw.githubusercontent.com/ckir/clavity/feat/agent-install
    CONFIG=/tmp/tmp.dgB04SSHVl

Prompt (verbatim): `Fetch and follow the instructions at https://raw.githubusercontent.com/ckir/clavity/feat/agent-install/INSTALL.md`
followed by the substitution line "Wherever that file says `main` in a URL, use `feat/agent-install`."

(a) Command agy ran: `curl -fsSL https://raw.githubusercontent.com/ckir/clavity/feat/agent-install/install.sh | bash -s --`

(b) Script output as agy quoted it:

    [clavity install] added marketplace ckir/clavity
    [clavity install] added marketplace obra/superpowers-marketplace
    [clavity install] installed superpowers@superpowers-marketplace
    [clavity install] installed clavity@clavity
    [clavity install] clavity@clavity 0.17.0 at /tmp/tmp.dgB04SSHVl/plugins/cache/clavity/clavity/0.17.0
    [clavity install] running the plugin's fetch hook (downloads clavity-ls now)
    [clavity-ls] fetched clavity-ls-linux-x64-0.17.0.tar.gz -> /tmp/tmp.dgB04SSHVl/plugins/data/clavity-clavity/bin/clavity-ls.exe. If the clavity-ls MCP server failed to start in this session, run /mcp and reconnect it.
    [clavity install] agy registration skipped (CLAVITY_SKIP_AGY=1)
    [clavity install] PATH launcher step skipped (CLAVITY_SKIP_PATH=1)
    [clavity install] clavity-ls is NOT on PATH yet: the PATH launcher step was skipped (CLAVITY_SKIP_PATH=1), so there is no $HOME/.local/bin/clavity-ls; link it yourself (ln -s "/tmp/tmp.dgB04SSHVl/plugins/data/clavity-clavity/bin/clavity-ls.exe" "$HOME/.local/bin/clavity-ls") or use the launch line below
    If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: export PATH="/tmp/tmp.dgB04SSHVl/plugins/data/clavity-clavity/bin:$PATH"; clavity-ls.exe start $HOME/Development/Rust/clavity

(c) Exit code agy reported: 3.

(d) Closing message agy would relay: the status line and the launch line above, verbatim. Asked whether it counts the
install as a plain success, agy answered no: "exit code 3 indicates that while the plugins and binary were installed,
clavity-ls is not on PATH yet and manual PATH configuration or symlinking is required per INSTALL.md".

Cleanup: agy removed the throwaway config (confirmed absent afterwards) and unset the four variables. The repository
tree was byte-identical before and after (git status snapshot/diff); the host `~/.local/bin/clavity-ls` kept its
2026-11-08 mtime; the host `~/.claude` plugin list was not touched (the run used the throwaway config).

Outcome: matches expectation (bash form, exit 3, status line + launch line relayed, no plain-success claim).
Observation for the final review: with `CLAVITY_SKIP_PATH=1` the status line says "there is no $HOME/.local/bin/clavity-ls"
although a regular file of that name exists on this machine (a hand-placed binary); the `ln -s` advice would fail on it.
The wording should say the file is not a link to the installed binary. Logged in the SDD ledger as a Task 3 minor; the
exit code and the launch line are right.

## 3. Windows

Pending: handed to the owner's Windows machine through `docs/handoff/windows-session-3.md` (items (a)-(c): the textual
form of `CLAUDE_PLUGIN_DATA`/`CLAUDE_PLUGIN_ROOT`, `git --exec-path` depth, `CHERE_INVOKING`) and
`docs/handoff/windows-session-4.md` (item (d): the four suites and the `## windows` skip-inventory regeneration). The
results arrive as a pull request with base `feat/agent-install`; this section and the spec's "Measure first" item 2
(`UNVERIFIED-WINDOWS`) are updated from that PR before any release.
