# Clavity Launch & Rollout Plan

Operational roadmap for staged deployment, channel campaigns, release coordination, and launch verification.

## 1. Staged Rollout Strategy

To prevent unexpected scaling friction and gather early developer feedback safely, the launch is structured in two distinct phases:

### Phase A: Soft Launch (Weeks 1–3)
- **Target Audience:** Select group of power users, active contributors to AI coding tools, and personal developer networks (approx. 50–100 testers).
- **Primary Channels:** Direct developer outreach, Discord/GitHub invitation, and targeted forum discussions.
- **Goals:**
  - Verify zero-install friction across diverse Linux distributions, macOS versions, and Windows environments.
  - Stress-test the background Language Server binary download mechanism.
  - Triage early edge cases in `agy-capstone` and `adversarial-panel-review`.
  - Validate website form submission reliability.

### Phase B: Public Beta Launch (Weeks 4+)
- **Target Audience:** Broad developer community across GitHub, Hacker News, Reddit, and technical social media.
- **Primary Channels:** Show HN, r/programming, r/ClaudeAI, Product Hunt, X developer community, LinkedIn engineering groups.
- **Goals:**
  - Achieve widespread brand recognition for dual-agent collaboration.
  - Drive organic installations of `clavity-dotnet`.
  - Collect structured feedback and measure commercial pilot interest.

## 2. Channel-Specific Campaigns

| Channel | Format | Core Hook | Call to Action |
|---|---|---|---|
| **Hacker News (Show HN)** | Text post + terminal demo link | "Show HN: Clavity – Pairing Claude Code and Antigravity as Driver and Peer" | GitHub Repository & Free Install |
| **Reddit (r/ClaudeAI, r/programming)** | Technical case study + benchmarks | "How we stopped single coding agents from approving their own buggy code" | Discussion & Feedback |
| **Product Hunt** | Product listing + 60s demo video | "Clavity: Dual-agent AI coding that cross-checks every commit" | Try Free Public Beta |
| **X (Twitter)** | Thread + video GIF + ASCII diagram | "Two AI agents are better than one: pairing Claude Code with Antigravity" | GitHub Repo Link |
| **LinkedIn** | Engineering leadership post | "Solving AI code quality with adversarial multi-agent review" | Read Architectural Spec |

## 3. Release Coordination Protocol

1. **Tag Monorepo Release:** Coordinate with umbrella release workflow (`just release`) to ensure `clavity-v<N>` binary assets (`win-x64`, `linux-x64`, `osx-arm64`, `osx-x64`) are built and attached with verified `.sha256` checksums.
2. **Synchronize Documentation & Site:** Run `python3 .github/site-checks/check_site.py --site site --readme README.md` to guarantee complete command parity between the repository README and the public website.
3. **Verify Marketplace Availability:** Test plugin installation from a clean virtual environment using `claude plugin marketplace add ckir/clavity` and `claude plugin install clavity@clavity`.
4. **Deploy Website:** Push approved changes to `main` to trigger the automated GitHub Pages deployment workflow.

## 4. Pre-Launch Verification Checklist

### Technical & Environmental Verification
- [ ] Language server binaries verified on Ubuntu 22.04+, macOS Sonoma (ARM & Intel), and Windows 11.
- [ ] Static website passes all structural, anchor, and image size checks in `check_site.py`.
- [ ] Copy-to-clipboard functionality verified on Chromium, Firefox, and Safari.
- [ ] Optional beta intake form functions properly and rejects invalid inputs with clear UI messages.
- [ ] Monorepo passes all local gates (`just test`, `just lint`, `just check-control-bytes`).

### Content & Communications Verification
- [ ] Root `README.md` and website installation instructions are 100% synchronized.
- [ ] GitHub issue templates (`bug_report.md`, `feature_request.md`, `beta_feedback.md`) deployed and operational.
- [ ] Launch copy drafted, fact-checked against verified claims, and staged for distribution.
- [ ] GitHub Discussions categories configured for Community, Q&A, and Beta Feedback.
- [ ] No commercial gating or paywalls introduced into free public beta code paths.
