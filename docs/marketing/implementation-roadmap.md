# Clavity GTM Implementation Roadmap

Prioritized epics, dependency graph, milestone gates, and acceptance criteria for subsequent marketing and commercial execution phases.

## 1. Roadmap Epics & Priority Matrix

| Epic ID | Epic Title | Priority | Phase | Dependencies |
|---|---|---|---|---|
| **E1** | Marketing & GTM Scaffolding (Current) | High (P0) | Phase 0–7 | None |
| **E2** | Technical Content Production & Visual Assets | High (P0) | Post-Scaffolding | E1 (Brand & Spec) |
| **E3** | Soft Launch & Targeted Beta Recruitment | Medium (P1) | Post-Content | E1, E2 |
| **E4** | Public Launch Campaign Execution | High (P0) | Beta Launch | E2, E3 |
| **E5** | Commercial Discovery Interviews & Paid Pilot | Medium (P1) | Evaluation | E3, E4 |
| **E6** | Dual-Edition Architecture & Enterprise Scoping | Low (P2) | Commercial Phase | E5 (Validation Gate) |

---

## 2. Detailed Epic Breakdown

### Epic 1: Marketing & GTM Scaffolding (In Progress)
- **Objective:** Establish documentation, static multi-page website architecture, beta intake forms, GitHub templates, and analytics interface.
- **Acceptance Criteria:**
  - Complete `docs/marketing/` documentation suite written and reviewed.
  - Multi-page website hierarchy deployed in `site/` without changing existing static framework.
  - Parity checks (`check_site.py`) and monorepo gates green.
  - GitHub issue templates and contributing guidelines updated.
  - Draft campaign copy staged in `marketing/campaigns/`.

### Epic 2: Content Production & Asset Creation
- **Objective:** Produce real visual media, terminal recordings, and publish the first technical articles.
- **Key Tasks:**
  - Record high-resolution split-screen demo video (Claude driving on left, Antigravity reviewing on right).
  - Generate animated SVG / GIF diagrams of the 6-stage review lifecycle.
  - Draft and finalize Article 1 ("Why Single AI Coding Agents Fail").
  - Produce Quickstart onboarding guide with terminal screenshots.
- **Acceptance Criteria:**
  - Demo videos rendered and compressed below 5 MB.
  - Article 1 ready for cross-posting to Dev.to and personal blog.

### Epic 3: Soft Launch & Closed Beta Cohort
- **Objective:** Onboard first 50–100 developers to validate the installation pipeline and collect initial feedback.
- **Key Tasks:**
  - Direct outreach to active developers in Claude Code and Antigravity communities.
  - Set up GitHub Discussions categories and monitor early installation queries.
  - Verify Language Server auto-download reliability across non-standard Linux distros.
- **Acceptance Criteria:**
  - 50 confirmed installations without unresolvable process crashes.
  - At least 10 feedback items triaged and cataloged in the backlog.

### Epic 4: Public Launch Campaign
- **Objective:** Execute coordinated announcements across developer channels.
- **Key Tasks:**
  - Submit Show HN with live terminal walkthrough.
  - Post detailed technical breakdown on Reddit (`r/ClaudeAI`, `r/programming`).
  - Publish Product Hunt listing.
  - Coordinate social announcements on X and LinkedIn.
- **Acceptance Criteria:**
  - Front-page presence or active discussion thread on target developer subreddits.
  - Minimum 1,000 unique website visits in first 72 hours.

### Epic 5: Commercial Validation & Paid Pilots
- **Objective:** Validate commercial demand through qualitative interviews and paid pilot letters of intent.
- **Key Tasks:**
  - Filter beta intake registrations for enterprise / team leads.
  - Conduct 15 structured discovery interviews using the pricing interview guide.
  - Propose 60-day paid pilot terms to 3 candidate engineering teams.
- **Acceptance Criteria:**
  - Pricing research report summarizing customer willingness-to-pay and preferred licensing models.
  - Documented decision on whether to proceed with Commercial Edition development.

---

## 3. Milestone Gates

```text
[Scaffolding Complete] ──> [Asset Creation] ──> [Soft Launch Gate]
                                                     │
                                                     ▼
[Commercial Evaluation Gate] <── [Public Launch] <── [Beta Green]
```

- **Gate 1 (Soft Launch Gate):** Clean binary auto-download, zero critical installer bugs, website passes all CI checks.
- **Gate 2 (Public Launch Gate):** At least 20 active beta participants report stable dual-agent pairing without model crashes.
- **Gate 3 (Commercial Gate):** At least 5 enterprise leads request team review policies or CI/CD integration.
