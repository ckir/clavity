# ghidrust

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](../LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

**ghidrust** attaches a persistent, headless Ghidra JVM to your AI agent and exposes it as an MCP
tool/plugin: 19 reverse-engineering tools over MCP stdio — 14 read/navigate (decompile, disassemble,
list symbols/strings/data/segments, resolve symbols, xrefs, read bytes, …) plus 5 durable writes saved
to disk (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`). It is a single pure-Rust
binary; one part of the [`clavity`](../README.md) umbrella.

ghidrust **attaches** to a Ghidra project you have already created and fully analyzed in the Ghidra
GUI, then closed — it does not (yet) import or analyze binaries itself.

## Prerequisites (you supply these — not bundled)

- **Ghidra 12.1.2** — set `GHIDRA_INSTALL_DIR` to its install root (the installer offers to set this
  for you).
- **JDK 21** — required by Ghidra 12.1.2 (`application.java.min=21`).
- A Ghidra project, already analyzed and closed in the GUI.

## Install

Grab the standalone `ghidrust-setup-1.0.0` installer from the umbrella
[release page](../../../releases) and run it. It installs the `ghidrust` binary to your PATH and
registers the ghidrust plugin (locally, no remote marketplace) against each detected agent
(Claude Code / agy).

## Version & license

Current version **1.0.0**. Licensed under the **PolyForm Noncommercial License 1.0.0** — free for
non-commercial use (personal, academic, non-profit). See [LICENSE](../LICENSE).

## More detail

- [`plugin/README.md`](plugin/README.md) — the full operator doc: what the plugin provides, required
  configuration env vars, per-workspace `.mcp.json` setup, logs & quirks, and uninstall behavior.
- [`skill/SKILL.md`](skill/SKILL.md) — the bundled agent-facing skill describing how to drive the
  ghidrust tools.
