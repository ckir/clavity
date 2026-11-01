# Clavity Positioning & Messaging Architecture

Core product positioning, differentiators, value messaging, and verification registry for all marketing claims.

## 1. Product Positioning

### Tagline
> **Two AI agents. One folder. Every step cross-checked.**

### Core Positioning Statement
For software developers and engineering teams leveraging AI coding agents, **Clavity** is the multi-agent collaboration platform that pairs **Claude Code** and **Google Antigravity** in the same workspace. Unlike single-agent tools that suffer from unverified assumptions and self-confirmation bias, Clavity implements an adversarial driver-peer discipline that inspects specifications, plans, code changes, and test coverage before anything ships.

## 2. Primary Value Proposition

- **Driver-Peer Division of Labor:** Claude Code drives execution (implements, edits, executes builds) while Antigravity acts as a critical peer (reviews specs, audits plans, and runs adversarial capstone checks).
- **Reduced Hallucination & Self-Approval:** Breaking the single-agent confirmation loop by submitting code to an independent model architecture (Gemini-backed Antigravity cross-checking Anthropic-backed Claude).
- **Hardened Test Suites:** Dedicated test audits (`agy-test-audit`) that measure edge cases, untested failure modes, and vacuous assertions before completion.
- **Empirical Grounding:** Backed by live empirical probing and driver cheatsheets rather than speculative prompt chains.

## 3. Audience-Specific Messaging

### Individual Developers
- **Message:** "Stop babysitting your coding agent. Let a second agent challenge assumptions, review edge cases, and ensure tests actually test what they claim."
- **Focus:** Quality of life, confidence in autonomous commits, automated backlog triage.

### Technical Team Leads & Engineering Managers
- **Message:** "Standardize AI code generation with adversarial quality gates. Ensure agent-generated code meets production standards before reaching human PR review."
- **Focus:** Regression prevention, test suite rigor, consistent engineering standards.

### Framework & Open-Source Maintainers
- **Message:** "An open, modular ecosystem for agent interoperability via Language Server protocol, MCP stdio, and signal buses."
- **Focus:** Protocol architecture, extensibility, zero lock-in.

## 4. Key Differentiators

| Capability | Single-Agent Tools (Cursor, Copilot, Solo Claude) | Clavity Multi-Agent Architecture |
|---|---|---|
| Review Mechanism | Self-review (agent checks its own output) | Adversarial peer review by independent model family |
| Workflow Protocol | Linear prompt-and-edit | Formal stages: Brainstorm -> Spec Review -> Plan Review -> Build -> Capstone -> Test Audit |
| Runtime Integration | Closed IDE extension | Open MCP Language Server (`clavity-ls`) + terminal integration |
| Cross-Agent Memory | Ephemeral per-session context | Shared persistent memory bus (`commonmemory`) |
| Model Training/Feedback | Static documentation | Empirical self-updating knowledge store (`agy-autotrain`) |

## 5. Claims Verification Registry

Every claim published on the website, documentation, or social channels must be classified as either verified in code or requiring ongoing empirical evidence.

### Verified Claims (Approved for Immediate Use)
- [x] **Cross-Platform MCP Bridge:** `clavity-dotnet` runs as a Language Server on Windows, Linux, and macOS, providing MCP stdio transport.
- [x] **Adversarial Panel Review:** Multi-expert review discipline (`adversarial-panel-review`) with configurable expert seats.
- [x] **Pre-Completion Capstone:** Convergent rounds-until-green code review (`agy-capstone`) that checks file:line citations before human completion gate.
- [x] **Automated Test Audit:** Exhaustive test suite analysis (`agy-test-audit`) checking untested behaviors and assertion rigor.
- [x] **Defect Capture & Triage:** Automatic detection of pre-existing repo defects during execution, categorized into a ranked backlog upon prompting.
- [x] **Zero Cloud Tracking:** The core product sends zero telemetry, prompts, source code, or credentials to third-party marketing servers.

### Claims Requiring Evidence (Do Not Publish As Fact Without Empirical Benchmarks)
- [ ] *X% reduction in production bug escapes* (Requires controlled user cohort measurement).
- [ ] *Supports any arbitrary model with identical performance* (Requires benchmarks beyond Gemini 3.1 Pro / Opus 5).
- [ ] *Y% faster feature delivery* (Requires timed comparative developer studies).
- [ ] *Enterprise compliance readiness* (Requires formal SOC2/ISO audit roadmap and policy engine implementation).
