# ghidrust

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](../LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

**ghidrust** attaches a persistent, headless Ghidra JVM to your AI agent and exposes it as an MCP
tool/plugin: 19 reverse-engineering tools over MCP stdio — 14 read/navigate (decompile, disassemble,
list symbols/strings/data/segments, resolve symbols, xrefs, read bytes, …) plus 5 durable writes saved
to disk (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`). One part of the
[`clavity`](../README.md) umbrella.

## How it works

ghidrust is a single pure-Rust binary. `ghidrust serve` launches and holds a headless Ghidra JVM
worker for the life of the MCP session, so tool calls hit an already-warm process instead of paying
Ghidra startup cost per call.

It **attaches** to a Ghidra project you have already created and fully analyzed in the Ghidra GUI,
then closed — it does not (yet) import or analyze binaries itself.

## Quick start

### Prerequisites

You supply these — they are not bundled.

- **Ghidra 12.1.2** — set `GHIDRA_INSTALL_DIR` to its install root (the installer offers to set this
  for you).
- **JDK 21** — required by Ghidra 12.1.2 (`application.java.min=21`).
- A Ghidra project, already analyzed and closed in the GUI.

### Install

Grab the standalone `ghidrust-setup-<version>.exe` installer from the umbrella
[release page](../../../releases) and run it. It installs the `ghidrust` binary to your PATH and
registers the ghidrust plugin (locally, no remote marketplace) against each detected agent
(Claude Code / agy).

### First run

Confirm the binary is on `PATH` and answers `--help` (exit 0, usage on stderr):

```bash
ghidrust --help
```

```
ghidrust <version>
usage: ghidrust serve        (env: GHIDRA_INSTALL_DIR, GHIDRUST_PROJECT_DIR, GHIDRUST_PROJECT_NAME, GHIDRUST_BOOTSTRAP_PROGRAM)
       ghidrust boot-smoke   (dev; env: GHIDRA_INSTALL_DIR, GHIDRUST_FIXTURE_*)
```

## Command reference

| Command | Description |
| --- | --- |
| `ghidrust serve [--ghidra-install-dir DIR] [--project-dir DIR] [--project-name NAME] [--bootstrap-program NAME] [--bootstrap-program-path PATH] [--max-heap SIZE]` | Run the MCP stdio server — what the plugin's `.mcp.json` invokes. Each flag has an equivalent env var (`GHIDRA_INSTALL_DIR`, `GHIDRUST_PROJECT_DIR`, `GHIDRUST_PROJECT_NAME`, `GHIDRUST_BOOTSTRAP_PROGRAM`, `GHIDRUST_BOOTSTRAP_PROGRAM_PATH`, `GHIDRUST_MAX_HEAP`); a CLI flag overrides its env var. |
| `ghidrust skill --emit` | Print the embedded `ghidra-re-driver` skill to stdout (maintainer use — see [CONTRIBUTING.md](CONTRIBUTING.md)). |
| `ghidrust boot-smoke` | Dev-only smoke test: boots the worker and drives attach + decompile end to end. Needs `GHIDRA_INSTALL_DIR` and `GHIDRUST_FIXTURE_*` env vars; not for normal use. |
| `ghidrust --help` (or any unrecognized/missing command) | Print version + usage to stderr, exit 0. |

## Platform support

| Platform | Status |
| --- | --- |
| Windows | Verified — CI (`ci-ghidrust.yml`, `build-ghidrust.yml`, `e2e-ghidrust.yml`) builds, tests, and live-E2E-tests exclusively on `windows-latest`; the installer targets `x64compatible` Windows only. |
| Linux / macOS | Not supported. The worker lifecycle holds the Ghidra JVM in a Windows Job Object (`crates/ghidra-worker-ctl/src/job_object.rs`, `#[cfg(windows)]`) with no non-Windows equivalent. |

## Docs

- [`plugin/README.md`](plugin/README.md) — the full operator doc: what the plugin provides, required
  configuration env vars, per-workspace `.mcp.json` setup, logs & quirks, and uninstall behavior.
- [`skill/SKILL.md`](skill/SKILL.md) — the bundled agent-facing skill describing how to drive the
  ghidrust tools.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Licensed under the **PolyForm Noncommercial License 1.0.0** — free for
non-commercial use (personal, academic, non-profit). See [LICENSE](../LICENSE).
