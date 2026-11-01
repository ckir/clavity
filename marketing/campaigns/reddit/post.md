# Reddit Launch Post (Draft)

**Target Subreddits:** r/ClaudeAI, r/LocalLLaMA, r/programming

**Title:** How we stopped Claude Code from approving its own buggy code: Pairing it with Google Antigravity as an adversarial peer

**Post Body:**

Anyone using autonomous coding agents knows the frustration of "vacuous passes":
You ask an agent to implement a feature. It produces 400 lines of code and 5 unit tests. The unit tests pass cleanly, so the agent declares victory. But when you inspect the code, you notice it silently bypassed error handling or failed to account for clock skew, and the tests only passed because they tested trivial mock returns.

The root cause is structural: **single-agent confirmation bias**. When the same LLM writes the code and the test, it validates its own assumptions.

To solve this, we created **Clavity** (https://github.com/ckir/clavity).

### How it works: Driver + Peer in One Directory
Clavity runs Claude Code and Google Antigravity (`agy`) in the same folder.
- Claude Code acts as the **driver**: It brainstorms with you, drafts specs, edits files, and executes builds.
- Antigravity acts as the **peer**: It conducts an independent review before and after implementation.

### The 6-Stage Workflow
1. **Brainstorm:** Claude drafts a design document.
2. **Spec Review:** Antigravity convenes an adversarial expert panel (`adversarial-panel-review`) with Architecture, Security, and Performance seats.
3. **Plan Review:** The implementation plan is vetted by the peer.
4. **Build:** Claude implements in thin, testable slices.
5. **Capstone (`agy-capstone`):** Convergent review of the committed diff. The peer cites specific file:line defects; Claude fixes them before the completion gate.
6. **Test Audit (`agy-test-audit`):** Antigravity audits the test suite with mutation probing to make sure tests would catch real regressions.

Bonus: While navigating your codebase, Claude records existing defects it notices. At the end of a session, just type `start the triage` to get an automatically ranked backlog.

### Tech Stack & Privacy
The primary bridge is `clavity-dotnet`, a .NET 10 Language Server exposing Antigravity as an in-process MCP server over stdio. It runs 100% locally on Windows, Linux, and macOS. Zero source code or telemetry leaves your machine.

### Try the Beta
It's free for evaluation under PolyForm Noncommercial 1.0.0:

```bash
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity
```

*(You will need `superpowers`, Claude Code CLI, and Google Antigravity CLI installed).*

- GitHub: https://github.com/ckir/clavity
- Website & Guides: https://ckir.github.io/clavity/

Curious to hear from others building multi-agent workflows: how are you verifying code quality before merging agent commits?
