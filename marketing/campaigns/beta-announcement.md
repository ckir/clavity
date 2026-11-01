# Public Beta Announcement (Draft)

**Title:** Announcing Clavity: Pair Claude Code and Antigravity as Driver and Peer

Today we are launching the public beta of **Clavity**, an open developer tool ecosystem that pairs two distinct AI coding agents in the same workspace.

### The Problem: Single-Agent Confirmation Bias
When you assign a complex coding task to a single AI agent, it creates both the code and the unit tests. If the model makes a flawed assumption, it writes tests that reflect that exact flaw. The tests pass, but your codebase breaks in production.

### The Solution: Adversarial Driver-Peer Collaboration
Clavity implements a formal division of labor between two independent model architectures:
- **Claude Code (Anthropic) is the driver:** It explores your codebase, drafts designs, edits files, and executes builds.
- **Google Antigravity (Gemini) is the peer:** It convenes multi-seat review panels before coding begins, audits implementation plans, and runs an adversarial capstone review on committed diffs before your task is declared complete.

### What is Included in the Public Beta
1. **Clavity Bridge (`clavity-dotnet`):** A cross-platform Language Server exposing Antigravity as an in-process MCP server to Claude Code over stdio.
2. **Adversarial Panel Review:** Multi-expert review discipline (`adversarial-panel-review`) challenging architecture, security, and performance assumptions.
3. **Capstone Code Audit (`agy-capstone`):** Convergent, rounds-until-green code review citing exact file and line proofs.
4. **Test Suite Hardening (`agy-test-audit`):** Mutation-tested test audit to ensure tests catch future regressions.
5. **Automatic Defect Backlog Triage:** Detects pre-existing bugs during execution and ranks them into an actionable backlog.

### How to Get Started
The public beta is free for noncommercial developer evaluation under the PolyForm Noncommercial 1.0.0 license. No waitlist or registration is required:

```bash
# 1. Add marketplace
claude plugin marketplace add ckir/clavity

# 2. Install bridge
claude plugin install clavity@clavity
```

Prerequisites: Claude Code CLI, Google Antigravity CLI (`agy`), and the `superpowers` plugin installed in Claude Code.

- Website: https://ckir.github.io/clavity/
- Repository: https://github.com/ckir/clavity
- Public Beta Program: https://ckir.github.io/clavity/beta/
