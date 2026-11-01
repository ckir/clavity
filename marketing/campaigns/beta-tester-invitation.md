# Beta Tester Direct Invitation (Draft)

**Subject:** Invitation: Evaluate Clavity dual-agent pairing (Claude Code + Antigravity)

Hi {{FirstName}},

I noticed your work on {{Project/Community}} and thought you might be interested in an experiment we are running on AI agent collaboration.

Most autonomous coding agents suffer from self-confirmation bias: when a single agent writes both the implementation and its tests, edge cases and subtle logical flaws slip through unnoticed.

We built **Clavity** (https://github.com/ckir/clavity) to test an adversarial driver-peer model:
- **Claude Code** acts as the driver (implements, executes builds).
- **Google Antigravity** acts as the peer (runs multi-seat panel reviews on specs, and conducts a strict capstone audit on committed diffs before completion).

The core tool runs as a local Language Server bridging the two tools via MCP stdio without cloud relays.

We have just opened our public beta and would value your feedback on pairing ergonomics, false-positive rates during review, and how it performs in non-trivial codebases.

You can install it directly in Claude Code:
```bash
claude plugin marketplace add ckir/clavity
claude plugin install clavity@clavity
```

If you are open to sharing your impressions, you can reply directly to this email or join our GitHub Discussions (https://github.com/ckir/clavity/issues).

Best regards,

Costas Kirgoussios & the Clavity Team
https://ckir.github.io/clavity/
