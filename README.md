# clavity

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

**clavity** is a host for several tools that pair AI coding agents with live peers. The umbrella
`clavity-v<N>` release is the **canonical** download and bundles every tool's installer in one place; this
repo is the shared home for their plugins, docs, and release machinery.

## Tools hosted here

| Tool | What it is | Docs | Release lineage |
|------|-----------|------|-----------------|
| **clavity** | Pairs [Claude Code](https://claude.com/claude-code) with [Antigravity (`agy`)](https://antigravity.google) — `.NET` + `classic` variants, plus `agy-autotrain` / `commonmemory` add-ons. | [README-CLAVITY.md](README-CLAVITY.md) | `clavity-v<N>` |
| **ghidrust** | Drives a persistent headless Ghidra JVM — 19 reverse-engineering tools over MCP (attach + decompile + durable edits). | [plugins/ghidrust/README.md](plugins/ghidrust/README.md) | `clavity-v<N>` (umbrella; standalone `ghidrust-v<N>` is dispatch-only) |

## Adding a tool

New tools follow one repeatable pattern (code on a branch; plugin under `plugins/<tool>/` on `main`; an
Inno-Setup installer; its own release lineage). See the playbook: [`docs/hosting-a-tool.md`](docs/hosting-a-tool.md).

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0** — free for non-commercial
use (personal, academic, non-profit). See [LICENSE](LICENSE).

---

> **Looking for clavity install & usage?** It moved to **[README-CLAVITY.md](README-CLAVITY.md)**.
