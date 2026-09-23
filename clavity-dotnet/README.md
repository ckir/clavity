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

Opens a visible `agy` tab in that folder and launches Claude Code in the foreground. Warns (without
blocking) if the folder is not a git repository. To uninstall, run `claude plugin uninstall
clavity@clavity`.

## Command reference

- `clavity-ls start <folder> [claude-args...]` — launch a visible agy tab + Claude Code in `<folder>`
  (per-session log; defaults to the current directory).
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
