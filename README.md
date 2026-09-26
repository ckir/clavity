# clavity

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

<!-- HUMAN ONLY SECTION START - AI AGENTS DO NOT EDIT THIS SECTION -->

## HUMAN ONLY

### WARNING
In Latest versions of Antigravity the "--prompt-interactive" option is not working as expected. The workaround until I fix it is simple.
Copy/paste the exact content of this file **[pairing](https://raw.githubusercontent.com/ckir/clavity/refs/heads/main/clavity-dotnet/pairing/agy-pairing-INSTALL.md)** to Antigravity's prompt before start your work on Claude Code or use the classic version.


### What it does
Starts a Claude Code and an Antigravity Code instance at the same folder.
Once started Claude Code gets the role of driver (implement, verify) and Antigravity (agy) gets the role of peer (review, recommend).

### How it works
Before use you MUST have [superpowers](https://github.com/obra/superpowers) installed.
You MUST start by /brainstorming (Activates before writing code. Refines rough ideas through questions, explores alternatives, presents design in sections for validation. Saves design document). After the brainstorm you have a comprehensive design document.
When claude creates the design document it will run the adversarial-panel-review and your design gets reviewed by "expert panels" via agy.
After the specs review claude will write the implementation plan. Again same adversarial-panel-review treatment here (see the examples below).
You choose the implementation mode (Subagent-Driven or Inline).
After the implementation claude will run agy-capstone. Sit back and relax watching your code improving from naive to professional.
After the agy-capstone the final step is the agy-test-audit. This will harden your test suites before claude declares the plan as completed.

All the above can be waived by prompts. Say for example "Waive agy for this step" and claude will execute the step solo.
In case you have problem to start agy (e.g. quota exhausted, Google's servers are down) you can switch to subagents mode by prompt. Say for example "Waive agy for this and use subagents".

**Bonus** Automatic debugging for your repo. Claude will capture pre-existing defects in your code (both main and subagents). At the end of a plan just say "start the triage" and any defects found will be organized into a ranked backlog.

Tested using Opus 5 and Gemini 3.1 Pro (Other models should work but that's not tested).
What if you don't like Gemini 3.1 Pro? Install the agy-autotrain and claude will learn to drive your favorite model by usage.
Want claude and agy share memories? Install commonmemory (needs [`@agentmemory/agentmemory`](https://www.npmjs.com/package/@agentmemory/agentmemory))

<!-- HUMAN ONLY SECTION END -->

---

<!-- AI SECTION START - AI AGENTS MAY MODIFY THIS SECTION -->

## AI SECTION

The rest of this file is technical documentation for AI agents and developers. Feel free to update this section to reflect current state and improvements.

### Which product do I need?

This repository contains four independent products. You only need to install the ones you actually want to use.

#### I want Claude Code to drive a live `agy` peer
These two tools are **mutually exclusive** — pick exactly one. They let Claude Code delegate tasks, get second opinions, or collaborate with `agy`.

*   **[clavity-dotnet](clavity-dotnet/README.md) (Primary):** The modern .NET 10 rebuild. It exposes `agy` to Claude as an MCP server via a local Language Server. Each Claude instance drives its own isolated lifecycle and state.
*   **[clavity-classic](clavity-classic/README.md) (Failover):** The original Rust-based bridge. It uses a psmux doorbell and the agentmemory bus to drive a live `agy` peer in the same folder. Use this as a fallback if clavity-dotnet unavailable.

#### I want my agents to learn and share knowledge (Opt-in Add-ons)
*   **[agy-autotrain](agy-autotrain/README.md):** Auto-trains clavity's `agy` knowledge from everyday usage. It captures insights, verifies them, and compiles them into a project-agnostic manual.
*   **[commonmemory](commonmemory/README.md):** A shared cross-agent memory convention. Teaches Claude and `agy` to tag notes (decisions, gotchas, bug fixes) and proactively share context via the agent memory signal bus.

### How to get started

The four products install one of two ways. **Three install with `claude plugin`** —
clavity-dotnet, agy-autotrain and commonmemory — from this repository's marketplace.
Cross-platform (Windows, Linux, macOS):

```
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity          # clavity-dotnet
claude plugin install agy-autotrain@clavity
claude plugin install commonmemory@clavity
```

clavity-dotnet fetches its `clavity-ls` binary on first run from the matching `clavity-v<N>` GitHub
release (win-x64 / linux-x64 / osx-arm64 / osx-x64), so nothing lands on your PATH. Checksum-verified
when a `.sha256` companion asset is published and `sha256sum` is on PATH; otherwise the fetch proceeds
unverified.

Upgrading from an old `<member>-setup-<version>.exe` installer? See
[`docs/migrating-from-the-inno-installers.md`](docs/migrating-from-the-inno-installers.md).

**One ships a standalone Windows installer** — clavity-classic:

1. Go to the [Releases](../../releases) page. The `clavity-v<N>` umbrella release carries the installer.
2. Download it — the asset is named `clavity-classic-setup-<version>.exe`, with a `.sha256`.
3. Run it. It registers the product's plugin locally with every agent it detects (Claude Code and/or
   `agy`) and puts its binary on your PATH.

Installing clavity-dotnet or clavity-classic? Their review disciplines are multi-round; see
**Running this economically** in that product's `plugin/README.md` before you start.

### Developer workflow

If you want to build from source or contribute to the project, see [CONTRIBUTING.md](CONTRIBUTING.md); to add a new tool to the umbrella, follow the [hosting playbook](docs/hosting-a-tool.md).

The repository uses a two-tier `just` task runner (`just test`, `just lint`, `just release`). Before push, `lefthook` runs the pre-push gates to keep `main` green; the heavier `just lint` and `just test` runs locally (both are in CI).

Pre-commit runs `ruff` on staged Python files, plus `curate-in-progress` and `cheatsheet-parity` checks when the driver-cheatsheet files are staged.

### License

This project is licensed under the **PolyForm Noncommercial License 1.0.0** — free for non-commercial use (personal, academic, non-profit). See [LICENSE](LICENSE). All four products (clavity-dotnet, clavity-classic, agy-autotrain, commonmemory) ship under the same licence.

_Trademarks:_ Antigravity is a trademark of Google LLC; Claude and Claude Code are trademarks of Anthropic. This is an independent project — not affiliated with, endorsed by, or sponsored by Google or Anthropic.

<!-- AI SECTION END -->
