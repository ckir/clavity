# clavity

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

**clavity** is a host for several tools that pair AI coding agents with live peers. This is the
umbrella repo — a monorepo with one top-level folder per product, each independently built/tested,
plus the shared release machinery that bundles them into one umbrella download. The umbrella
`clavity-v<N>` release is the **canonical** download and bundles every product's installer in one
place.

## Products

| Product | Folder | Build |
|---------|--------|-------|
| clavity-dotnet | clavity-dotnet/ | cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests |
| clavity-classic | clavity-classic/ | cd clavity-classic && cargo test --all --features test-fakes |
| ghidrust | ghidrust/ | cd ghidrust && just test |
| agy-autotrain | agy-autotrain/ | (plugin only) |
| commonmemory | commonmemory/ | (plugin only) |

- **clavity-dotnet** / **clavity-classic** — two variants that pair [Claude Code](https://claude.com/claude-code)
  with [Antigravity (`agy`)](https://antigravity.google). See [clavity-dotnet/README.md](clavity-dotnet/README.md)
  for install & usage (the installer lets you choose the **.NET** (Primary) or **Classic** (Failover)
  host variant, and opt in to `agy-autotrain` / `commonmemory` extras).
- **ghidrust** — drives a persistent headless Ghidra JVM: 19 reverse-engineering tools over MCP
  (attach + decompile + durable edits). See [ghidrust/README.md](ghidrust/README.md).
- **agy-autotrain** / **commonmemory** — plugin-only add-ons (no standalone build); installed alongside
  clavity via the umbrella installer.

## Adding a product

New products follow one repeatable pattern (its own top-level folder; an Inno-Setup installer; its own
release lineage bundled into the umbrella release). See the playbook:
[`docs/hosting-a-tool.md`](docs/hosting-a-tool.md).

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0** — free for non-commercial
use (personal, academic, non-profit). See [LICENSE](LICENSE). **clavity-classic** ships under its own
**MIT** license — see [clavity-classic/LICENSE](clavity-classic/LICENSE).
