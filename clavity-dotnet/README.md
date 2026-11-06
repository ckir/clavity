# clavity-dotnet — pair Claude with a live agy peer

[English](README.md) | [Ελληνικά](README.el.md)

clavity-dotnet is the modern, greenfield **.NET 10** rebuild of clavity: it pairs
[Claude Code](https://claude.com/claude-code) with a live [Antigravity (`agy`)](https://antigravity.google)
peer, shipped as a universal dual-plugin. It is one member of the [`clavity` umbrella](../README.md) —
see that README to decide whether this variant or `clavity-classic` is the one you want.

## How it works

clavity-dotnet drives a paired `agy` peer from Claude Code over agy's local Language Server (gRPC),
exposed to Claude as three MCP tools served by the `clavity-ls` binary:

- `agy_look` — read agy's active conversation, bounded, no quota.
- `agy_status` — liveness + step count (`CascadeId`, `TotalSteps`, `State`, `LastStepKind`).
- `agy_ask` — send a message and wait for agy's reply — a quota-consuming, human-visible write. Good
  for a second opinion, design review, or delegated parallel work.

Each Claude instance drives its own isolated agy session (multi-session), and `agy_ask` sends using
the model your conversation last used rather than a baked-in default (dynamic send-model).

## Quick start

### Prerequisites

- Claude Code and/or `agy` (Antigravity) installed — at least one detected agent is needed to drive it.
- To build from source: the .NET 10 SDK.

### Install

```powershell
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity
```

clavity-dotnet is cross-platform (Windows, Linux, macOS — RIDs `win-x64`, `linux-x64`, `osx-arm64`,
`osx-x64`). The `clavity-ls` binary is not bundled with the plugin; a plugin SessionStart hook fetches
the RID-matching binary on first run from the matching `clavity-v<N>` GitHub release and verifies it
against the companion `.sha256` asset.

To build from source instead of using a release:

```powershell
dotnet build                          # from clavity-dotnet/
dotnet test tests/Clavity.Ls.Tests    # unit tests — ci-dotnet.yml also runs Clavity.Integration.Tests
```

The release `clavity-ls` binaries are produced by a single-file publish per RID (from
`.github/workflows/build-dotnet.yml`), e.g. for `win-x64`:

```powershell
dotnet publish src/Clavity.Cli -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -o publish
```

The workflow repeats this per RID (`win-x64`, `linux-x64`, `osx-arm64`, `osx-x64`) and attaches each
binary + `.sha256` to the `clavity-v<N>` GitHub release.

### First run

```powershell
clavity-ls start C:\path\to\your\project
```

Opens a visible `agy` tab in that folder, waits until agy has paired (published its endpoint - after 10 s it reminds
you to check agy's tab for a prompt; Ctrl+C aborts; if agy exits first, `start` stops and says so), then launches
Claude Code in the foreground. Warns (without
blocking) if the folder is not a git repository. To uninstall, run `claude plugin uninstall
clavity@clavity`.

On Linux, `start` opens agy as a new tab in the terminal you ran it from (mate-terminal, gnome-terminal, konsole or
xfce4-terminal), otherwise in `xdg-terminal-exec` or `x-terminal-emulator`; set `CLAVITY_TERMINAL` to choose one. With
no display (over ssh, say) it starts nothing and tells you to run `clavity-ls agy <folder>` instead, which runs agy in
that terminal; in a second one, `clavity-ls start <folder> --attach` pairs Claude with it (add the session id agy's
terminal prints if more than one agy is waiting in that folder). Each agy takes one Claude: a second `--attach` to the
same agy is refused. `start` also allows ONE Claude per folder: a second `start`, plain or `--attach`, in a folder that already
has one is refused before it opens anything, so it cannot repeat the first one's work (use `git worktree add` for a second
Claude on the same repository). Only `clavity-ls start` is guarded: running `claude` yourself, or starting `clavity-ls agy`
before an attach, is not blocked. With an id, Claude starts in the folder that agy runs in, and says so if that differs from the one
you gave; if no agy waits in your folder but some wait elsewhere (the same folder through a symlink, say), `start` lists
them with the command to use. Over `ssh -X` (X11 forwarding) DISPLAY is set, so `start` opens agy's terminal window on your own
machine instead. In a folder
neither has seen before, both agy and Claude Code ask you to trust it, each in its own window: answer agy's in its tab,
or it does not pair.

### Running Claude under a profile

The simplest route is `--profile`, which uses [agent-profile](https://github.com/ckir/aiprofiles) to do the setup
for you:

```bash
clavity-ls start ~/path/to/your/project --profile work
```

`--profile <name>` goes directly after the folder, in either order with `--attach`. `agent-profile` and `claude` must
both be on PATH. `start` runs `agent-profile claude create <name>`, reads the profile's directory from
`agent-profile claude doctor <name> --json`, installs `clavity@clavity` and `superpowers@superpowers-marketplace` into it
(adding the marketplaces `ckir/clavity` and `obra/superpowers-marketplace` first if they are missing), enables either
plugin if it is disabled, and then launches Claude with `CLAUDE_CONFIG_DIR` set to that directory. Notes:

- If your shell already has a different `CLAUDE_CONFIG_DIR`, `--profile` overrides it and prints a one-line notice on stderr.
- If any setup step fails, `start` exits 1 with nothing opened.
- A new profile starts empty: its Claude asks you to sign in (credentials are not copied from another profile).
- Only the Claude process gets the variable; the agy tab does not.
- Two `start --profile X` runs in different folders are serialised per profile name, so they do not set the same profile up at once.

#### The manual route

Without `--profile`, `start` launches Claude Code with the environment it inherited from your shell (it adds only the three `CLAVITY_*`
variables below), so a [Claude Code profile](https://docs.anthropic.com/en/docs/claude-code/settings) is selected the
same way as for a bare `claude`: set `CLAUDE_CONFIG_DIR` before running `start`. Everything Claude reads from that
directory - `settings.json`, `CLAUDE.md`, the enabled plugins and their fetched `clavity-ls` binary - comes from the
profile, so the `clavity` plugin must be installed under the same profile (run `claude plugin install clavity@clavity`
with the variable set) or the MCP server has nothing to launch. Claude's own flags pass through after the folder.

Windows (pwsh; the variable lasts for that shell):

```powershell
$env:CLAUDE_CONFIG_DIR = "$HOME\.claude-profiles\test"
clavity-ls start C:\path\to\your\project
```

Linux/macOS (one-off prefix, or `export` it for the shell):

```bash
CLAUDE_CONFIG_DIR=~/.claude-profiles/test clavity-ls start ~/path/to/your/project
```

`--attach` works the same way - the variable only has to reach the shell that runs `start`, not the one running
`clavity-ls agy`.

## Command reference

- `clavity-ls start <folder> [--attach [<session-id>]] [--profile <name>] [claude-args...]` — launch a visible agy tab + Claude Code in `<folder>`
  (per-session log; defaults to the current directory). `--attach` starts Claude only, paired with the agy that
  `clavity-ls agy` started; without an id it picks the one agy waiting in that folder. `--profile` sets up and uses a named
  [agent-profile](https://github.com/ckir/aiprofiles) Claude profile (see above).
- `clavity-ls agy [folder]` — Linux/macOS: run a new session's agy in this terminal and print the `start --attach`
  command for another.
- `clavity-ls --mcp` — run the MCP stdio server (`agy_look` / `agy_status` / `agy_ask`); started
  automatically via `.mcp.json`, not normally run by hand.
- `clavity-ls install [--plugin <name>]` — register a plugin with every detected agent (Claude Code
  and/or agy); default plugin is the core `clavity` plugin. A manual/advanced command — the normal
  install path is `claude plugin install clavity@clavity` (see Install above).
- `clavity-ls uninstall [--purge-data]` — deregister; `--purge-data` also deletes the per-session log
  dir and the golden-header data dir.
- `clavity-ls is-installed <plugin-name>` — exit 0 if `<plugin-name>` is registered with a detected
  agent, 1 otherwise.
- `clavity-ls curate-commit` — read a compiled golden-header from stdin and atomically commit it as
  the GROWTH region; invoked by agy-autotrain's `agy-curate` skill, not typically run by hand.

## Configuration

- `CLAVITY_GOLDEN_HEADER` — override the directory holding `golden-header.seed.md` /
  `golden-header.growth.md` (must be a directory, not a file — `--mcp` warns on stderr if it looks
  like a file path). Default: `%USERPROFILE%\.clavity`.
- `CLAVITY_AGY_LOG` — set automatically by `clavity-ls start`; the per-session agy log path `--mcp`
  reads to resolve that session's Language Server port.
- `CLAVITY_SESSION_ID` — set automatically by `clavity-ls start`; reserved for bus/memory scoping.
- `CLAVITY_AGY_ENDPOINT` — set automatically by `clavity-ls start`; the per-session file agy publishes its endpoint to (the pairing rendezvous). Not normally set by hand.
- `CLAVITY_AGY_IDLE_MAX_SECONDS` — ceiling on how long `agy_ask` waits for agy to go idle (default 600; the plugin's `.mcp.json` raises it to 1800). Read only when the MCP server starts.
- `CLAVITY_AGY_IDLE_STALL_SECONDS` — how long agy may show no step progress before `agy_ask` reports `possible_modal` (stall). Default 120; raise it if your work has long single steps.
- `CLAVITY_AGY_GENERATION_CAP_SECONDS` — how long agy may keep writing ONE long reply (an assistant step visibly still being generated) before `agy_ask` stops extending the wait and reports `possible_modal` (limit `generation_cap`). Default 600; `0` turns the extension off. It never exceeds `CLAVITY_AGY_IDLE_MAX_SECONDS`.
- `CLAVITY_LS_LOG` — also write the server's event log to a file (unset = no file). A directory (existing, or
  ending in a path separator) gets one file per server, `clavity-ls-<CLAVITY_SESSION_ID>.log`, or
  `clavity-ls-pid<pid>.log` when no session id is set; any other value is the file itself, appended to. One JSON
  line per event (`ts`, `tool`, `phase`, `dur_ms`, `model`, `model_src`, `endpoint_src`, `outcome`), flushed per
  line so a killed server keeps its last event. It never holds a prompt, a reply, or the endpoint file's token.
  Without it the server still keeps the last 20 events in memory and echoes each to stderr (Claude Code decides
  whether stderr is kept): a failing `agy_status` returns them as `RecentEvents`, and a failing tool call as
  `recentEvents`. They are absent from a healthy reply. A server that is killed takes the in-memory events with
  it; only the file survives that.
- `CLAVITY_TERMINAL` — Linux: the terminal command `start` opens agy with, run by `/bin/sh` with the script path
  appended as its last argument, so shell quoting works (e.g. `gnome-terminal --tab --`).
- `CLAVITY_DATA_DIR` — overrides the dir removed by `uninstall --purge-data` (default
  `%USERPROFILE%\.clavity`); mainly used by the test suite.

## Platform support

Cross-platform — the CI matrix builds a 4-RID self-contained matrix (`win-x64`, `linux-x64`,
`osx-arm64`, `osx-x64`); `clavity-ls` is fetched on first run rather than bundled with the plugin (see
Install above). Contributions and bug reports for Linux/macOS are welcome (see
[CONTRIBUTING.md](../CONTRIBUTING.md)).

## Docs

- [`plugin/README.md`](plugin/README.md) — the plugin's contents and MCP wiring.
- [`plugin/knowledge/agy-assumptions.md`](plugin/knowledge/agy-assumptions.md) — canonical,
  driver-agnostic agy manual; read it before changing anything agy-facing.
- [`plugin/knowledge/agy-capabilities.md`](plugin/knowledge/agy-capabilities.md) — agy's
  capability/routing profile.
- [`../docs/agy-ls-assumptions.md`](../docs/agy-ls-assumptions.md) — the .NET Language-Server wire
  assumptions.
- [`CHANGELOG.md`](CHANGELOG.md) — release notes.

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md); this member's own build/test commands are in Quick start
above.

## License

PolyForm Noncommercial License 1.0.0 — see [LICENSE](../LICENSE).
