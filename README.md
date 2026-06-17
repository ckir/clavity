# clavity

A Cargo workspace that produces **universal, dual-installable plugins** for agent
collaboration between **Claude Code** and **Antigravity (`agy`)**. One generated
plugin directory installs in *both* CLIs:

    claude plugin install ./dist/<plugin>
    agy    plugin install ./dist/<plugin>

> **Status: skeleton.** This tree lays out the structure, sample configs, and stubs.
> Real implementation (`mcp-core`, the `xtask` packager, and the first plugins) lands
> incrementally. The previous single-binary `clavity` is preserved on the **`v1`** branch.

## How a universal plugin works

The two CLIs read **disjoint filenames**, so both manifest sets coexist in one directory
while skills, hook scripts, and the server binary are shared:

| Concern | Claude reads | agy reads |
| --- | --- | --- |
| Manifest | `.claude-plugin/plugin.json` | `plugin.json` |
| MCP config | `.mcp.json` | `mcp_config.json` |
| Hooks | `hooks/hooks.json` | `hooks.json` |

See [`docs/plugin-formats.md`](docs/plugin-formats.md) for the verified formats and
[`samples/scaffold/`](samples/scaffold/) for a fully-assembled example.

## Layout

| Path | Role |
| --- | --- |
| `crates/mcp-core/` | shared MCP server primitives (stdio JSON-RPC, stderr-only logging) |
| `plugins/<name>/` | one plugin: `plugin.toml` SSOT + bin crate + shared `skills/ rules/ hooks/` |
| `xtask/` | packager: generate both hosts' files from `plugin.toml` -> `dist/<plugin>/` |
| `samples/` | assembled reference output (committed; `dist/` itself is gitignored) |
| `docs/` | design spec, implementation plan, verified plugin-formats reference |

## Build (planned)

    cargo run -p xtask -- package <plugin> [--mode universal|split]

Produces `dist/<plugin>/` (pre-built binary + both manifest sets + shared payload),
installable by both CLIs.

## Planned plugins

- **`clavity`** — bidirectional Claude<->agy collaboration (psmux doorbell + agentmemory bus); role assigned per project.
- **`commonmemory`** — shared memory between Claude and agy via the existing agentmemory daemon (config-only).

## License

[MIT](LICENSE) (c) Costas Kirgoussios
