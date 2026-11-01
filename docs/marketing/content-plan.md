# Clavity Technical Content & Publishing Plan

Editorial schedule, tutorial briefs, video specifications, and distribution cadence for developer onboarding.

## 1. Initial Technical Articles

### Article 1: "Why Single AI Coding Agents Fail (And Why Adversarial Pairing Works)"
- **Core Concept:** Analysis of self-confirmation bias in autonomous LLM coding agents. When an agent creates both the code and the test, subtle flaws and invalid test assertions slip through undetected.
- **Key Takeaways:** Demonstrates how Anthropic's Claude Code and Google's Antigravity (Gemini-backed) cross-check each other to catch silent defects.
- **Target Channels:** Clavity Blog, Dev.to, Hacker Noon, Substack.

### Article 2: "Inside Clavity-LS: Bridging Claude Code and Antigravity via MCP and Stdio"
- **Core Concept:** Deep dive into the systems architecture of `clavity-dotnet`. Explaining how a .NET 10 Language Server acts as an in-process MCP server bridging two distinct AI CLI harnesses without cloud relays.
- **Key Takeaways:** Clean process isolation, low-latency IPC, and handling cross-platform filesystem discrepancies.
- **Target Channels:** Clavity Engineering Docs, Reddit (r/dotnet, r/rust, r/ClaudeAI).

### Article 3: "Hardening Agent-Written Tests: Beyond Naive Coverage"
- **Core Concept:** Introduction to the `agy-test-audit` discipline. Why 100% line coverage often masks zero-assertion or vacuous tests, and how adversarial mutation probing exposes genuine behavioral gaps.
- **Key Takeaways:** Practical examples of real-world test audits generated in live open-source repositories.
- **Target Channels:** Hacker News, Medium, Clavity Documentation.

## 2. Technical Tutorials

### Tutorial 1: "Quickstart: Zero to Dual-Agent Pairing in Under 5 Minutes"
- Prerequisites (`superpowers`, Claude Code, Antigravity).
- One-line marketplace install.
- Walking through the initial `/brainstorm` and watching the peer review fire.

### Tutorial 2: "Capturing and Triaging Repo Bugs Automatically"
- Running a task with Clavity.
- Observing how Claude notes pre-existing defects during tool execution.
- Executing `start the triage` to generate a prioritized backlog without manual issue writing.

### Tutorial 3: "Sharing Cross-Agent Memory with CommonMemory"
- Installing `@agentmemory/agentmemory` and the `commonmemory` plugin.
- Setting up persistent agent notes that persist across terminal sessions.

## 3. Demo Video Specifications

### Video 1: "The 60-Second Terminal Split" (Short Form)
- **Format:** 1080x1920 (Vertical for YouTube Shorts / X) + 1920x1080 (Landscape).
- **Duration:** 45–60 seconds.
- **Script Outline:**
  - 0:00–0:10: Claude Code writes a complex algorithm with a subtle off-by-one error.
  - 0:11–0:25: Antigravity peer triggers `agy-capstone`, flags the exact file and line with an adversarial proof.
  - 0:26–0:45: Claude folds the feedback, fixes the algorithm, and runs tests green.
  - 0:46–0:60: CTA: "Install free via Claude marketplace."

### Video 2: "Full Architecture Walkthrough" (Long Form)
- **Format:** 1920x1080 Landscape, 60fps, crisp terminal font rendering.
- **Duration:** 8–12 minutes.
- **Scope:** Complete end-to-end lifecycle from design spec to final test audit.

## 4. Social Media Content Series

- **"Agent Gotcha of the Week" (X & LinkedIn):** Real-world edge cases where single agents hallucinated passing tests, but Antigravity caught the flaw.
- **Architecture Highlights:** Short code snippets and diagrams showing Language Server MCP protocol messages.
- **Changelog Snapshots:** Clean, visual summary of every new release and bug fix.

## 5. Publishing Schedule

| Week | Focus Milestone | Deliverables |
|---|---|---|
| Week 1 | Foundation | Publish Article 1 ("Why Single Agents Fail") + Quickstart Tutorial |
| Week 2 | Video & Social | Release 60-second split terminal demo + social announcement |
| Week 3 | Deep Technical | Publish Article 2 (Language Server Architecture) + r/ClaudeAI walkthrough |
| Week 4 | Community & Testing | Publish Article 3 (Test Audits) + Developer feedback roundup |
| Week 5+ | Bi-weekly Cadence | Regular release updates, bugfix highlights, and guest user workflows |
