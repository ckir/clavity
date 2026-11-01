# X (Twitter) Launch Thread (Draft)

### 1/8
Single AI coding agents have a major flaw: they approve their own work.

When an agent writes both the implementation and the tests, its own blind spots get baked into your codebase.

Today, we're launching the public beta of Clavity: Two AI agents. One folder. Every step cross-checked. 🧵👇

---

### 2/8
Clavity pairs Claude Code and Google Antigravity as driver and peer in the exact same repository.

- Claude Code DRIVES: writes code, edits files, executes builds.
- Antigravity PEERS: reviews specs, audits plans, and runs adversarial capstone code checks.

Independent model architectures checking each other.

---

### 3/8
How the pairing workflow works:
1. Brainstorm -> Claude drafts design spec
2. Spec Review -> Antigravity convenes SecOps, Arch, and Perf review seats
3. Plan Review -> Peer audits task order
4. Build -> Claude implements in thin slices
5. Capstone -> Multi-round diff audit before completion
6. Test Audit -> Hardens test suite against vacuous passes

---

### 4/8
The capstone audit (`agy-capstone`) is strict:
The Antigravity peer cites exact `file:line` proof of defects. Claude measures and folds the changes until the verdict is GREEN.

No more premature "I'm done!" claims from an agent.

---

### 5/8
Bonus: while navigating your repo, Claude captures pre-existing defects it encounters along the way.

At the end of any task, just say "start the triage" and Clavity formats them into a prioritized backlog.

---

### 6/8
Architecture & Privacy:
- Powered by `clavity-dotnet`, a fast .NET 10 Language Server exposing Antigravity as an in-process MCP server over stdio.
- Runs 100% locally on macOS, Linux, and Windows.
- Zero source code or prompts ever leave your machine.

---

### 7/8
Free for public evaluation under the PolyForm Noncommercial 1.0.0 license.

Install via Claude Code in two commands:
```bash
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity
```

---

### 8/8
Try it out, read the guides, and join our public beta:

🌐 Website: https://ckir.github.io/clavity/
💻 GitHub: https://github.com/ckir/clavity
📖 Docs: https://ckir.github.io/clavity/docs/

Feedback and star welcome! Let us know what you think.
