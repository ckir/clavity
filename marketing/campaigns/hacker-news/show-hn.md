# Show HN: Clavity – Pairing Claude Code and Antigravity as Driver and Peer

**Link:** https://github.com/ckir/clavity  
*(Alternative link: https://ckir.github.io/clavity/)*

**Title:** Show HN: Clavity – Pairing Claude Code and Google Antigravity as driver and peer

**Post Body:**

Hi HN,

Over the past few months of working with coding agents (Claude Code, Antigravity, Cursor), we noticed a recurring defect pattern: single-agent self-approval. When an agent misunderstands a domain requirement or introduces a subtle concurrency edge case, it writes unit tests tailored to its own misunderstanding. The test suite passes green, but the code fails under real production workloads.

To break this confirmation bias, we built Clavity.

Clavity is a developer tool monorepo that pairs two different AI coding agents in the exact same workspace directory:
- **Claude Code is the driver:** It writes code, plans milestones, runs compilers, and executes local tests.
- **Google Antigravity (Gemini) is the peer:** It convenes multi-expert review panels on design documents, audits implementation plans before coding starts, and executes a strict adversarial capstone review (`agy-capstone`) citing exact file:line proofs before any plan is declared complete.

### Architecture
The flagship bridge (`clavity-dotnet`) runs as a lightweight, cross-platform Language Server (`clavity-ls`) that exposes Antigravity to Claude Code as an in-process MCP server over stdio. Everything runs locally on your workstation; there are no third-party cloud relays, telemetry servers, or hosted proxies.

### Key Disciplines
1. **Adversarial Panel Review:** Before coding, Antigravity simulates three distinct review seats (Architecture, Security, Performance) to challenge the driver's assumptions.
2. **Capstone Review (`agy-capstone`):** A rounds-until-green review of committed git diffs. The peer provides actionable citations, and the driver measures and refactors until the verdict is clean.
3. **Test Audit (`agy-test-audit`):** An automated audit measuring untested behaviors and vacuous assertions.
4. **Automatic Defect Capture:** Pre-existing bugs observed during execution are cataloged and ranked into a prioritized backlog upon running `start the triage`.

### Installation
Clavity is free for developer evaluation under the PolyForm Noncommercial 1.0.0 license. If you have Claude Code, Antigravity, and `superpowers` installed, you can try it right from your terminal:

```bash
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity
```

Repository: https://github.com/ckir/clavity  
Documentation: https://ckir.github.io/clavity/docs/

We'd love to hear your thoughts on multi-agent protocol design, review discipline ergonomics, and how you manage agent-generated code quality in production.
