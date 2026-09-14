# clavity

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

**clavity** is a suite of tools that expand the capabilities of AI coding agents like Claude Code and Antigravity (`agy`).

It provides bridges that let agents collaborate, such as Claude driving a live `agy` peer. It also offers plugins to help agents share memory and learn from everyday usage.

## Which product do I need?

This repository contains four independent products. You only need to install the ones you actually want to use.

### I want Claude Code to drive a live `agy` peer
These two tools are **mutually exclusive** — pick exactly one. They let Claude Code delegate tasks, get second opinions, or collaborate with `agy`.

*   **[clavity-dotnet](clavity-dotnet/README.md) (Primary):** The modern .NET 10 rebuild. It exposes `agy` to Claude as an MCP server via a local Language Server. Each Claude instance drives its own isolated `agy`.
*   **[clavity-classic](clavity-classic/README.md) (Failover):** The original Rust-based bridge. It uses a psmux doorbell and the agentmemory bus to drive a live `agy` peer in the same folder. Use this as a fallback if the .NET version breaks.

### I want to reverse-engineer binaries with my agent
This is no longer part of clavity — see **[re-ghidra-mcp-cc](https://github.com/ckir/aiplugins)** (in the
`ckir/aiplugins` repo) for headless Ghidra reverse-engineering over MCP.

### I want my agents to learn and share knowledge (Opt-in Add-ons)
*   **[agy-autotrain](agy-autotrain/README.md):** Auto-trains clavity's `agy` knowledge from everyday usage. It captures insights, verifies them, and compiles them into a project-agnostic manual.
*   **[commonmemory](commonmemory/README.md):** A shared cross-agent memory convention. Teaches Claude and `agy` to tag notes (decisions, gotchas, bug fixes) and proactively share context via the agentmemory bus.

## How to get started

The four products install one of two ways.

**Three install with `claude plugin`** — clavity-dotnet, agy-autotrain and commonmemory — from this
repository's marketplace. Cross-platform (Windows, Linux, macOS):

```
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity          # clavity-dotnet
claude plugin install agy-autotrain@clavity
claude plugin install commonmemory@clavity
```

clavity-dotnet fetches its `clavity-ls` binary on first run from the matching `clavity-v<N>` GitHub
release (win-x64 / linux-x64 / osx-arm64 / osx-x64, checksum-verified), so nothing lands on your PATH.

**One ships a standalone Windows installer** — clavity-classic:

1. Go to the [Releases](../../releases) page. The `clavity-v<N>` umbrella release carries the installer.
2. Download it — the asset is named `clavity-classic-setup-<version>.exe`, with a `.sha256`.
3. Run it. It registers the product's plugin locally with every agent it detects (Claude Code and/or
   `agy`) and puts its binary on your PATH.

Installing clavity-dotnet or clavity-classic? Their review disciplines are multi-round; see
**Running this economically** in that product's `plugin/README.md` before you start.

## Developer workflow

If you want to build from source or contribute to the project, see [CONTRIBUTING.md](CONTRIBUTING.md).
To add a new tool to the umbrella, follow the [hosting playbook](docs/hosting-a-tool.md).

The repository uses a two-tier `just` task runner (`just test`, `just lint`, `just release`). Before push, `lefthook` runs nine local gates to keep the `main` branch green. The heavier gates — `just lint` and `just test-scripts` — run in CI and the release pre-flight, not pre-push, because git holds the SSH connection open while a hook runs.

| Pre-push gate | Catches |
|---|---|
| `just seed-sync-check` | seed-artifact drift between the two driver plugins |
| `just check-agy-skills` | invariant drift in the shipped AGY-* discipline skills |
| `just check-doc-stubs` | duplicate content in placeholder files |
| `just check-member-docs` | missing required docs or bad CHANGELOG format |
| `just check-user-facing-docs` | a curated user-facing doc is missing, or a do-not-touch / unvoiced doc is on the list |
| `just check-register-hash` | stale tamper-check hash for the installer registrar |
| `just check-installer-ascii` | non-ASCII in the Windows PowerShell 5.1 installer surface |
| `check-versions-all.ps1` | version-source drift, across all members |
| `scripts/check-plugin-namespace.ps1` | stray old plugin namespace/skill-dir/identity references left after the SP-0 rename |

Pre-commit only runs `ruff` on staged Python files.

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0** — free for non-commercial use (personal, academic, non-profit). See [LICENSE](LICENSE). All four products (clavity-dotnet, clavity-classic, agy-autotrain, commonmemory) ship under the same license.

_Trademarks:_ Antigravity is a trademark of Google LLC; Claude and Claude Code are trademarks of Anthropic. This is an independent project — not affiliated with, endorsed by, or sponsored by Google or Anthropic.
