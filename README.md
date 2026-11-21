# clavity

[![Release](https://img.shields.io/github/v/release/ckir/clavity)](https://github.com/ckir/clavity/releases)
[![ci-dotnet](https://github.com/ckir/clavity/actions/workflows/ci-dotnet.yml/badge.svg?branch=main)](https://github.com/ckir/clavity/actions/workflows/ci-dotnet.yml)
[![ci-classic](https://github.com/ckir/clavity/actions/workflows/ci-classic.yml/badge.svg?branch=main)](https://github.com/ckir/clavity/actions/workflows/ci-classic.yml)
[![ci-scripts](https://github.com/ckir/clavity/actions/workflows/ci-scripts.yml/badge.svg?branch=main)](https://github.com/ckir/clavity/actions/workflows/ci-scripts.yml)
[![tests](https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fckir%2Fclavity%2Fbadges%2Fendpoint.json)](https://github.com/ckir/clavity/blob/badges/README.md)
[![Pages](https://github.com/ckir/clavity/actions/workflows/pages.yml/badge.svg?branch=main)](https://ckir.github.io/clavity/)
[![Last commit](https://img.shields.io/github/last-commit/ckir/clavity/main)](https://github.com/ckir/clavity/commits/main)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
[![Platform: Windows | Linux | macOS](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux%20%7C%20macOS-lightgrey.svg)]()

[English](README.md) | [Ελληνικά](README.el.md)

<!-- HUMAN ONLY SECTION START - AI AGENTS DO NOT EDIT THIS SECTION -->

HUMAN ONLY

What it does

Starts a Claude Code and an Antigravity Code (agy) instance in the same folder (agy starts with --dangerously-skip-permissions by design. The prompts sent by Claude are safe).

Preparation

1. Grab the latest release of clavity-dotnet and put it somewhere in your PATH.
2. If you want to use a Claude profile to try clavity-dotnet without touching your existing install, use the aiprofiles tool. It works for many agents and out of the box with clavity-dotnet (see below).
3. Start your Claude (profile or not) and ask it to install the required plugins (see below).
4. Install superpowers (Or from the Anthropic Directory) to your Claude.
5. (Optional) Install rtk on both agents.
6. Exit the Claude session and restart with the clavity-ls command (what you get from clavity-dotnet download).
7. You are good to go. Enjoy!!

Your first project

Open your terminal in the folder of your project and run clavity-ls. Now you see both Claude and agy started in two tabs in your terminal.
Feel free to start as many sessions as your box can handle to work on several projects in parallel.

Once started, Claude Code gets the role of driver (implement, verify), and Antigravity (agy) gets the role of peer (review, recommend).

You MUST start by /brainstorming (Activates before writing code. Refines rough ideas through questions, explores alternatives, presents design in sections for validation. Saves design document). After the brainstorm, you have a comprehensive design document; as best practice, set the strongest model and turn on the /advisor on Claude and agy (The latest Gemini 4 Neon at xhigh appears to be more productive).

At this point, Claude will improve its own design by running the agy-first skill. After you approve the design, Claude will improve the specs by running the adversarial-panel-review skill, and your specs will be reviewed by “expert panels” via agy. You can change this by prompts (see below).

Tip: Before starting the adversarial-panel-review, you can set a lower model on Claude main to save tokens. A Sonnet is enough as the load goes to agy. Remember to /compact before you change the model.

Caveat: The adversarial-panel-review skill can produce many rounds of findings and fixing so there is a cap at six rounds; it is yours to waive if you want the process to continue.

After the specs review, Claude will write the implementation plan. Again, same adversarial-panel-review treatment here (see the examples below).

You choose the implementation mode (Subagent-Driven or Inline).
After the implementation claude will run agy-capstone skill. Sit back and relax, watching your code improve from naive to professional.

The last step before delivery is the agy-test-audit skill. This will harden your test suites before Claude declares the plan as completed.

All the above can be waived by prompts. Say for example, “Waive agy for this step,” and Claude will execute the step solo.
In case you have a problem starting agy (e.g., quota exhausted, Google’s servers are down), you can switch to subagents mode by prompt. Say for example, “Waive agy for this and use subagents”.

Bonus: Automatic debugging for your repo. Claude agents tend to ignore any pre-existing defects in your codebase, not anymore with clavity. Claude will capture any pre-existing defects in your code (both main and subagents). At the end of a plan, just say “run the triage,” and any defects found during the process will be organized into a ranked backlog (promoted to TODO.md / ROADMAP.md so you can start a new brainstorm to fix, like “/brainstorming sequencing fork open items”). This will start a new plan to fix any remaining defects.

Tip: How to use agy for best performance? (As Agy answered during a session in this repo)

For this specific workload — high-leverage adversarial design, fork, and implementation-plan reviews paired against Claude Code — yes, a flagship reasoning model from a different family (Gemini 4 Neon here) is about the best fit you can use.

Where it is genuinely pulling its weight (grounded in this session):

* Different blind spots from Claude: Cross-family review caught real defects that slipped past the first drafts — e.g., scripts/tests/test-suite-registration.Tests.ps1:417-418 rejecting -FilePath on ci-scripts.yml:497, git ls-remote ... origin badges executing outside path: main, Windows CRLF breaking $-anchored regexes, scripts/GitHub_Actions_Storage_Reset.ps1 deleting whole runs rather than artifacts, and the pivot from Option 2 to the refined workflow_call snapshot.
* Strict protocol and epistemic discipline: Holding REVIEW-ONLY boundaries, quoting exact lines, refusing to fabricate unprovable GitHub Actions semantics (cannot determine), and converging cleanly (no new findings on clean seats rather than padding).

Honest limits where no model is enough on its own:

* Platform runtime behavior: No model can prove live GitHub Actions quirks (like fromJSON matrix outputs or inputs.* in concurrency on direct triggers) statically — your Task 8 PR proof run matters more than model choice there.
* Same-session anchoring: After ~8 rounds in one thread on the same feature, any model starts carrying assumptions from earlier rounds. Keeping this thread for Plan Round 2 is fine, and starting a fresh/compacted context before AGY-CAPSTONE / AGY-TEST-AUDIT on the final committed code will give you sharper, less anchored eyes than switching models would.
* Latency/quota trade-off: Lighter models (flash) are fine for routine lookups or mechanical checks, but for adversarial spec/plan/capstone panels, staying on a top-tier reasoning model is worth it.


<!-- HUMAN ONLY SECTION END -->

---

<!-- AI SECTION START - AI AGENTS MAY MODIFY THIS SECTION -->

## AI SECTION

The rest of this file is technical documentation for AI agents and developers. Feel free to update this section to reflect current state and improvements.

> 🚀 **Public Beta:** Clavity is in open public beta for developer evaluation. Visit the [official website](https://ckir.github.io/clavity/) or [learn about the beta program](https://ckir.github.io/clavity/beta/).
>
> 📖 **Documentation:** Explore the [Documentation Portal](docs/README.md), [User Guide (PDF)](docs/USER_GUIDE.pdf), or [User Guide (HTML)](docs/USER_GUIDE.html).
>
> 🗺️ **Roadmap:** Follow active engineering outcomes in [clavity-dotnet/ROADMAP.md](clavity-dotnet/ROADMAP.md) and on the [public roadmap](https://ckir.github.io/clavity/roadmap/).

### Which product do I need?

This repository contains five independent products. You only need to install the ones you actually want to use.

#### I want Claude Code to drive a live `agy` peer
These two tools are **mutually exclusive** — pick exactly one. They let Claude Code delegate tasks, get second opinions, or collaborate with `agy`.

*   **[clavity-dotnet](clavity-dotnet/README.md) (Primary):** The modern .NET 10 rebuild. It exposes `agy` to Claude as an MCP server via a local Language Server. Each Claude instance drives its own isolated lifecycle and state.
*   **[clavity-classic](clavity-classic/README.md) (Failover):** The original Rust-based bridge. It uses a psmux doorbell and the agentmemory bus to drive a live `agy` peer in the same folder. Use this as a fallback if clavity-dotnet unavailable.

#### I want my agents to learn and share knowledge (Opt-in Add-ons)
*   **[agy-autotrain](agy-autotrain/README.md):** Auto-trains clavity's `agy` knowledge from everyday usage. It captures insights, verifies them, and compiles them into a project-agnostic manual.
*   **[commonmemory](commonmemory/README.md):** A shared cross-agent memory convention. Teaches Claude and `agy` to tag notes (decisions, gotchas, bug fixes) and proactively share context via the agent memory signal bus.
*   **[review-relay](review-relay/README.md):** Assisted copy-paste review rounds with web AI models (ChatGPT, Meta AI, Gemini, or any other). Claude prepares each round and verifies the findings against the real text; you carry the text to the sites and save replies with the bundled AiSaveDev extension (or AiSave).

### How to get started

> Tell your agent: `Fetch and follow the instructions at https://raw.githubusercontent.com/ckir/clavity/main/INSTALL.md`

From a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/ckir/clavity/main/install.sh | bash -s --
```

Add `--with agy-autotrain,commonmemory,review-relay` for the add-ons.

What those do, by hand:

```
claude plugin marketplace add obra/superpowers-marketplace
claude plugin install superpowers@superpowers-marketplace
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity          # clavity-dotnet
claude plugin install agy-autotrain@clavity
claude plugin install commonmemory@clavity
claude plugin install review-relay@clavity
```

clavity-dotnet fetches its `clavity-ls` binary on first run from the matching `clavity-v<N>` GitHub
release (win-x64 / linux-x64 / osx-arm64 / osx-x64), and keeps a clavity-ls launcher on your PATH (a symlink in ~/.local/bin, or the plugin's data dir on the Windows user PATH). Checksum-verified
when a `.sha256` companion asset is published and `sha256sum` is on PATH; otherwise the fetch proceeds
unverified.

The `clavity` plugin itself is served from this repository's `release` branch, which CI advances only after a
release has attached every `clavity-ls` binary. So a plugin update and the binary it fetches always arrive
together. If the fetch still fails (offline, rate-limited), the session start shows a message saying where to
place `clavity-ls` by hand.

Upgrading from an old `<member>-setup-<version>.exe` installer? See
[`docs/migrating-from-the-inno-installers.md`](docs/migrating-from-the-inno-installers.md).

**One ships a standalone Windows installer** — clavity-classic:

1. Go to the [Releases](https://github.com/ckir/clavity/releases) page. The `clavity-v<N>` umbrella release carries the installer.
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

clavity is source-available, not open source. It is offered under three licences: the public **PolyForm Noncommercial License 1.0.0** (free for personal, academic and non-profit use, with a 30-day evaluation for any organisation; see [LICENSE](LICENSE)), a **commercial licence** for commercial use, and an **Authorized Training Partner licence** for running paid seminars. [LICENSING.md](LICENSING.md) says which one applies to you and how to get the paid ones. All five products (clavity-dotnet, clavity-classic, agy-autotrain, commonmemory, review-relay) are covered by the same licences.

_Trademarks:_ Antigravity is a trademark of Google LLC; Claude and Claude Code are trademarks of Anthropic. This is an independent project — not affiliated with, endorsed by, or sponsored by Google or Anthropic.

<!-- AI SECTION END -->
