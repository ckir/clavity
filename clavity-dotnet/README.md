# clavity-dotnet — pair Claude with a live agy peer

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

- Windows 10/11, PowerShell (not `cmd.exe`) — the CI matrix and installer both target `windows-latest`
  / `win-x64`.
- Claude Code and/or `agy` (Antigravity) installed — `clavity-ls install` needs at least one detected
  agent.
- To build from source: the .NET 10 SDK.

### Install

```powershell
irm https://raw.githubusercontent.com/ckir/clavity/main/clavity-dotnet/install/clavity-install.ps1 | iex
```

Downloads the latest release, verifies it against the companion `.sha256` asset, and runs the
installer. It prompts for the variant (`dotnet` or `classic` — the two are mutually exclusive; see the
[root README](../README.md) to choose) unless `-Variant` is passed. The installer is unsigned, so
Windows SmartScreen may warn on first run — choose "More info" -> "Run anyway".

Install places `clavity-ls.exe` under `%LOCALAPPDATA%\Programs\clavity-dotnet`, adds it to PATH
(on by default, opt-out task), and registers the plugin with every detected agent by running
`clavity-ls install --agent all`. Close Claude Code completely before installing or uninstalling — a
running Claude overwrites the plugin registration and leaves it unregistered.

To build from source instead of using a release:

```powershell
dotnet build                          # from clavity-dotnet/
dotnet test tests/Clavity.Ls.Tests    # unit tests — matches ci-dotnet.yml
```

The release installer's exe is produced by a single-file publish (from `.github/workflows/build-dotnet.yml`):

```powershell
dotnet publish src/Clavity.Cli -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -o publish
```

### First run

```powershell
clavity-ls start C:\path\to\your\project
```

Opens a visible `agy` tab in that folder and launches Claude Code in the foreground. Warns (without
blocking) if the folder is not a git repository. To uninstall, use Windows Add/Remove Programs — it
de-registers the plugin from each detected agent.

## Command reference

- `clavity-ls start <folder> [claude-args...]` — launch a visible agy tab + Claude Code in `<folder>`
  (per-session log; defaults to the current directory).
- `clavity-ls --mcp` — run the MCP stdio server (`agy_look` / `agy_status` / `agy_ask`); started
  automatically via `.mcp.json`, not normally run by hand.
- `clavity-ls install [--plugin <name>]` — register a plugin with every detected agent (Claude Code
  and/or agy); default plugin is the core `clavity-dotnet` plugin. Used by the installer's
  post-install step.
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
- `CLAVITY_DATA_DIR` — overrides the dir removed by `uninstall --purge-data` (default
  `%USERPROFILE%\.clavity`); mainly used by the test suite.

## Platform support

Windows only today — the CI matrix and the installer both target `windows-latest` / `win-x64`
self-contained. Contributions for Linux/macOS are welcome (see [CONTRIBUTING.md](../CONTRIBUTING.md));
`clavity-classic` already runs cross-platform and is the fallback if you need that now.

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
