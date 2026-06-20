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
