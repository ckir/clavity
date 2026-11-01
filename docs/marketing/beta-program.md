# Clavity Public Beta Program Plan

Framework for developer recruitment, participant feedback loops, issue triage, and privacy boundaries during the evaluation period.

## 1. Beta Objectives

1. **Verify Environmental Robustness:** Ensure smooth cross-platform execution of the Language Server across diverse shell environments (Bash, Zsh, Fish, PowerShell) and operating systems.
2. **Refine Adversarial Review Heuristics:** Measure whether `adversarial-panel-review` and `agy-capstone` offer actionable, high-signal recommendations without excessive false positives.
3. **Validate Commercial Interest:** Identify workflow friction points in team environments and evaluate willingness to pay for enterprise coordination features.
4. **Grow Organic Advocates:** Cultivate a core group of enthusiastic open-source contributors and power users.

## 2. Participant Eligibility & Requirements

### Target Participants
- Software developers actively using **Claude Code** and **Google Antigravity**.
- Individual developers, open-source maintainers, and engineering teams.
- Anyone building non-trivial software where code correctness and test rigor matter.

### System Prerequisites
- Claude Code installed and authenticated.
- Antigravity (`agy`) installed and authenticated with active model quota.
- `superpowers` installed in Claude Code (`https://github.com/obra/superpowers`).
- Supported OS: Windows 10/11 x64, Linux x64 (glibc 2.31+), macOS 12+ (Apple Silicon or Intel).

## 3. Recruitment & Onboarding

- **Open Access (No Gatekeeping):** The public beta is completely unblocked. Anyone can install and evaluate Clavity without creating an account or joining a waitlist.
- **Optional Registration:** Developers who wish to receive direct release notifications, participate in commercial pilot interviews, or provide in-depth feedback can submit their email via the website beta form (`/beta/`).
- **Onboarding Flow:**
  1. User reads quickstart command on `/` or `/beta/`.
  2. Runs `claude plugin marketplace add ckir/clavity` and installs desired plugins.
  3. Executes their first dual-agent task using standard `/brainstorm`.
  4. Accesses documentation or submits feedback via GitHub Discussions.

## 4. Feedback Collection Channels

### Structured GitHub Issue Templates
- Dedicated `beta_feedback.md` template capturing:
  - Operating system and shell environment.
  - Model configurations (e.g. Claude Opus 5 + Gemini 3.1 Pro).
  - Component evaluated (dotnet, classic, autotrain, commonmemory, review-relay).
  - Concrete pairing experience and failure mode observations.

### GitHub Discussions
- Open categories for:
  - **Show and Tell:** Community members sharing dual-agent review logs and success stories.
  - **Q&A:** Installation troubleshooting and configuration advice.
  - **Feature Ideas:** Brainstorming potential integrations and enhancements.

### Voluntary Developer Interviews
- 20-minute video interviews with active beta participants to explore workflow integration and potential team features.

## 5. Tester Communication Standards

- **Release Announcements:** Posted transparently on GitHub Discussions and repository Releases with detailed changelogs.
- **Respectful Inboxes:** No promotional spam or aggressive drip campaigns. Registered beta contacts receive at most 1–2 updates per month covering major stability improvements and milestone releases.
- **Unsubscribe Rights:** Every direct email communication provides an explicit, frictionless opt-out mechanism.

## 6. Privacy & Telemetry Commitments

- **Zero Source Code Ingestion:** Clavity never transmits customer code, git diffs, prompt contents, or terminal output to external marketing servers.
- **Local Execution:** All peer communications occur locally over localhost stdio or local IPC buses.
- **Isolated Registration Data:** Email addresses collected via the beta intake form are stored securely and used solely for developer notifications and commercial research interviews.
