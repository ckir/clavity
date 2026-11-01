# Product Hunt Launch Listing (Draft)

## Basic Information

- **Product Name:** Clavity
- **Tagline:** Two AI coding agents in one folder, every step cross-checked
- **Category:** Developer Tools, Artificial Intelligence, Open Source
- **Website Link:** https://ckir.github.io/clavity/
- **GitHub Link:** https://github.com/ckir/clavity

---

## Short Description (60 words)
Clavity is a developer tool ecosystem that pairs Claude Code (driver) and Google Antigravity (peer) in the same workspace. Instead of letting a single agent write and approve its own code, Clavity enforces an adversarial driver-peer discipline: expert panel spec reviews, pre-completion capstone audits, and automated mutation test hardening.

---

## Detailed Description (Maker Comment)

Hey Product Hunt community! 👋

We built Clavity to solve the biggest bottleneck in agentic software development: **who reviews the agent?**

Today, when an AI coding assistant implements a feature, it acts as author, reviewer, and tester all in one. Unsurprisingly, it easily overlooks its own subtle bugs, writes vacuous tests, and declares victory prematurely.

Clavity introduces a real-time, adversarial pairing protocol between two distinct AI tools:
1. **Claude Code drives:** Formulates plans, writes code, runs compilers, executes test suites.
2. **Google Antigravity reviews:** Acts as an independent peer. Convenes expert panels (Security, Architecture, Performance), reviews implementation plans, and conducts a strict capstone review on committed diffs before your task is marked complete.

### Core Highlights:
- **Zero Cloud Proxies:** Runs locally via a lightweight Language Server MCP bridge over stdio.
- **Cross-Platform:** Supports Windows, Linux, and macOS.
- **Capstone & Test Audits:** Peer cites exact file:line proofs; test audits ensure tests catch future regressions.
- **Automated Bug Triage:** Captures pre-existing repository defects during development and organizes them into a ranked backlog with `start the triage`.

Clavity is completely free for developer evaluation during our public beta under the PolyForm Noncommercial 1.0.0 license.

Check it out on GitHub, try pairing in your terminal, and let us know your feedback!
