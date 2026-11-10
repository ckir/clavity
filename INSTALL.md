# Install clavity (instructions for the agent)

You are a coding agent (Claude Code, Antigravity, or another) installing clavity for the person you are working with. Follow these steps in order and relay the closing message verbatim.

## 1. Preconditions

Check that `claude` (Claude Code) is on PATH, and that `curl`, `tar` and `sha256sum` or `shasum` exist. The plugins are Claude Code plugins even when agy performs the install. If anything is missing, tell the human what to install and stop.

## 2. The command

Run the script from this repository at `main`. Pick the form that matches your shell. Add `--with agy-autotrain,commonmemory,review-relay` (any subset) only if the human asked for add-ons; otherwise add nothing.

Bash form (Linux, macOS, and Claude Code on Windows, whose shell is git-bash). `-s --` is what lets a piped script take flags:

    curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s -- [--with ...]

PowerShell form (an agent whose shell is PowerShell, such as agy on Windows). Add the `--with` flags inside the single quotes, after `bash -s --`, when asked for:

    $bash = if ($env:CLAUDE_CODE_GIT_BASH_PATH) { $env:CLAUDE_CODE_GIT_BASH_PATH } else { Join-Path (Resolve-Path (Join-Path (git --exec-path) '..\..\..')) 'bin\bash.exe' }; try { $env:CHERE_INVOKING = 1; & $bash -lc 'curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s --' } finally { Remove-Item Env:CHERE_INVOKING -ErrorAction SilentlyContinue }

Outside the plugin, the add-ons need: commonmemory, the agentmemory MCP server configured in both Claude Code and agy, pointing at the same daemon (`commonmemory/README.md`); review-relay, the AiSaveDev browser extension, which the human loads once in Chrome or Edge with "Load unpacked" (`review-relay/README.md`).

Every script message is one line starting `[clavity install]`. The last line of stdout is the launch line.

## 3. Verify

The human does this after the restart, not you: in a NEW terminal, `clavity-ls --version`, then `claude plugin list` (clavity should be listed and enabled). No `claude plugin ...` command is left for the human to run to install.

## 4. Exit codes

- 0: done, and `clavity-ls` resolves in new terminals. Relay the launch line as success.
- 1: a precondition is missing (or a bad argument). Relay the script's line naming it and stop.
- 2: the binary does not run, or the plugin is not enabled. Relay the `[clavity install] FAILED: ...` line (it names which) and stop. Do not retry in a loop.
- 3: installed, but `clavity-ls` is NOT on PATH yet. Relay BOTH the `clavity-ls is NOT on PATH yet: ...` line (it says what to do) and the launch line. Never call this plain success.

## 5. Closing message

Give the human this, exactly as the script printed it (the last line of stdout):

    If Claude Code or agy is already running in this folder, exit them first. Then open a new terminal and run: clavity-ls start <folder>

- Do not run `clavity-ls start` yourself.
- If you are Claude Code, do not claim the `agy_*` tools work in this session; they do not until the restart.
- If you are agy, the message is the same: `clavity-ls start` opens its own agy tab and Claude session. The agy session that ran the install is not the pair.

## 6. clavity-classic

clavity-classic is Windows-only and mutually exclusive with clavity-dotnet. The human installs it from the Releases page; this script does not.

## 7. Troubleshooting

- The fetch failed (offline, rate-limited): run the command again later, or place the binary by hand as the hook's own message says.
- `~/.local/bin` is not on PATH: use the `export PATH=...` line the script prints (exit 3).
- On Windows `clavity-ls start` opens a new console window, not an editor tab.
- `~/.local/bin/.no-launcher` exists, so the launcher is off: run the script again with `--launcher` (`--no-launcher` turns it off).
