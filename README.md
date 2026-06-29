# clavity — tools for collaboration between the Claude Code CLI and the Antigravity (`agy`) CLI

A collection of **tools that facilitate collaboration between
[Claude Code](https://claude.com/claude-code) and [Antigravity](https://antigravity.google)
(`agy`)**, shipped as **universal dual-plugins** — one directory that installs in **both** CLIs.
Claude installs from a marketplace (this repo ships a `.claude-plugin/marketplace.json`); `agy`
installs from the path directly:

    # Claude (marketplace)
    claude plugin marketplace add github:ckir/clavity   # or a local path to this repo
    claude plugin install <name>@clavity

    # agy (path)
    agy plugin install ./plugins/<name>

The two CLIs read **disjoint filenames**, so both manifest sets coexist in one directory while
`skills/` and other assets are shared:

| Concern | Claude reads | agy reads |
| --- | --- | --- |
| Manifest | `.claude-plugin/plugin.json` | `plugin.json` |
| MCP config | `.mcp.json` | `mcp_config.json` |
| Hooks | `hooks/hooks.json` | `hooks.json` |

See [`docs/plugin-formats.md`](docs/plugin-formats.md) for the verified format reference.

## Install (one command)

The **`clavity-dotnet`** variant ships a one-command Windows installer. Run this in **PowerShell**
(not `cmd.exe`):

    irm https://raw.githubusercontent.com/ckir/clavity/main/install/clavity-install.ps1 | iex

It resolves the latest version-pinned setup from GitHub Releases, **verifies its SHA-256** against the
companion checksum, runs it, and registers the `clavity-ls` plugin into whichever agents it finds
(Claude Code / `agy`) — adding `clavity-ls` to your PATH. Optional add-ons (`agy-autotrain`,
`commonmemory`) are opt-in checkboxes. Then start a paired session:

    clavity-ls start C:\path\to\your\project

To remove it, use **Add/Remove Programs** — the uninstaller cleanly de-registers the plugin from each
agent first. The installer is **unsigned** for now, so Windows SmartScreen may warn on first run
(choose *More info → Run anyway*).

> The packaged installer currently covers **clavity-dotnet**. The **clavity-classic** (Rust) variant
> installs via `cargo install --git https://github.com/ckir/clavity --branch clavity-classic` for now;
> a packaged classic installer is a planned follow-on.

## Plugins

- **[`clavity-classic`](plugins/clavity-classic/)** — Claude drives a live, signed-in `agy` peer in
  the same folder over a **psmux doorbell** + the **agentmemory bus** (review, second opinions,
  delegated work). Its `clavity` binary builds from the `clavity-classic` branch
  (`cargo install --git https://github.com/ckir/clavity --branch clavity-classic`). See its
  [README](plugins/clavity-classic/README.md) — note the one-line `escape-time` setup that makes the
  live driving smooth.
- **[`commonmemory`](plugins/commonmemory/)** — a shared cross-agent memory convention. Claude and
  `agy` already share the **agentmemory** store, and this skills-only plugin teaches them to tag
  `[common]` notes (handoffs, decisions, gotchas, fixed bugs) and proactively recall them. See its
  [README](plugins/commonmemory/README.md).
- **[`agy-autotrain`](plugins/agy-autotrain/)** — gives Claude **one front door to drive `agy` like a
  model** (`clavity ask`, no human `/command`) and **auto-trains** clavity's agy knowledge from everyday
  usage (capture → curate → verify → golden-header, project-agnostic). Ships a portable agy instruction
  manual + a live verification harness. See its [README](plugins/agy-autotrain/README.md).

## clavity-dotnet — driving `agy` over its Language Server (.NET)

> On the **`clavity-dotnet`** branch: a greenfield **.NET 10** rebuild that turns `agy` into an
> **interactive superpower for Claude**. Rather than only the psmux doorbell, Claude drives a paired
> `agy` through that instance's **local Language Server** (gRPC over h2c) — the visible `agy` tab is
> auxiliary. Scope is deliberately narrow: a **session launcher** + an **LS-API MCP bridge** (no UI
> automation is baked into the binary).

- **`clavity start`** mints a per-session id, launches `agy` with a per-session `--log-file`, and
  exports `CLAVITY_AGY_LOG` + `CLAVITY_SESSION_ID` into Claude's environment, so every pair is
  self-identifying.
- **`clavity --mcp`** is the MCP server Claude spawns. It discovers that session's LS from the log,
  resolves the active conversation **from the LS** (not from disk), and exposes three tools:
  - **`agy_look`** — a size-bounded, id-free summary of the active conversation's trajectory.
  - **`agy_status`** — cascade id, total step count, and whether the look was truncated.
  - **`agy_ask`** — send a message and return `agy`'s reply once the conversation goes idle. This is a
    live **write** (consumes quota, posts a visible message); it is verified by a gated live-acceptance
    test rather than in CI.
- **Multi-session:** N independent Claude⇄agy pairs run concurrently — each Claude drives its **own**
  `agy` instance, isolated by that instance's per-session Language Server.

The Language Server contract is **empirically derived** (`agy` ships no public schema for it) and
version-fragile; every load-bearing assumption — and how to re-verify it — lives in
[`docs/agy-ls-assumptions.md`](docs/agy-ls-assumptions.md). The solution (`clavity.slnx`) is split into
`Clavity.Cli` (the `start` / `--mcp` host), `Clavity.Ls` (LS discovery, h2c client, the `agy_*`
surface), `Clavity.Ls.Proto` (the partial, wire-verified protos), and `Clavity.Mcp` (the MCP tools),
plus unit, integration, and gated live-acceptance test projects.

**Build & test:**

    dotnet build -c Release
    dotnet test -c Release --filter "Category!=LiveAgy"   # live-agy tests are gated out of CI

## Layout

| Path | Role |
| --- | --- |
| `plugins/<name>/` | a universal dual-plugin (both manifest sets + `skills/`, ± a server) |
| `docs/plugin-formats.md` | verified Claude + agy plugin-format reference |
| `docs/agy-*.md`, `docs/superpowers/` | agy behavior/assumptions references + design specs & plans |

## Adding a plugin
Create `plugins/<name>/` with both manifest sets (`.claude-plugin/plugin.json` + root
`plugin.json`), any `skills/`, and a `README.md`, following `docs/plugin-formats.md`.
`clavity-classic` and `commonmemory` are the working examples.

## License
[MIT](LICENSE) © Costas Kirgoussios
