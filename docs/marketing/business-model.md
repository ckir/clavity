# Clavity Business Model & Dual-Edition Strategy

Exploratory framework for future sustainability, dual-edition licensing hypotheses, and commercial boundary planning.

> [!IMPORTANT]
> **Status: Strategic Hypothesis.**  
> The dual-edition strategy documented below represents a commercial hypothesis for evaluation during the public beta. No commercial restrictions, payment processing, or artificial feature gating are implemented in this repository.

---

## 1. Confirmed Decisions vs. Commercial Hypotheses

| Strategic Area | Status | Contractual / Project Reality |
|---|---|---|
| **Core Product Access** | **Confirmed** | Free, open developer evaluation under PolyForm Noncommercial 1.0.0. |
| **Individual Developer Workflow** | **Confirmed** | Fully functional pairing (driver + peer) without registration or payments. |
| **Source Code Availability** | **Confirmed** | Public GitHub repository with open commit history. |
| **Dual-Edition Split** | *Hypothesis* | Commercial edition for enterprise/team features; Community for solo developers. |
| **Pricing Tiers & Seat Fees** | *Hypothesis* | Subject to customer willingness-to-pay research. No pricing is established. |
| **License Transition Model** | *Hypothesis* | Potential dual-licensing (Open Source / PolyForm + Proprietary Commercial). |

---

## 2. Proposed Dual-Edition Structure (Hypothesis)

### Edition 1: Community Edition (Free & Open)
- **Target Audience:** Individual software developers, students, researchers, and open-source contributors.
- **Licensing:** PolyForm Noncommercial 1.0.0 (or permissive open-source alternative if evaluated viable).
- **Distribution:** Public GitHub repository, Claude plugin marketplace, and standalone binaries.
- **Included Capabilities:**
  - Complete local pairing engine (`clavity-dotnet`, `clavity-classic`).
  - Standard review disciplines (`adversarial-panel-review`, `agy-capstone`, `agy-test-audit`).
  - Local defect capture and backlog triage.
  - Standard add-on plugins (`agy-autotrain`, `commonmemory`, `review-relay`).
  - Community-driven support via GitHub Issues and Discussions.

### Edition 2: Commercial / Team Edition (Future Evaluation)
- **Target Audience:** Engineering organizations, security-conscious enterprises, and software agencies.
- **Licensing:** Commercial license granting commercial deployment rights exempt from PolyForm restrictions.
- **Potential Value-Add Capabilities to Investigate:**
  - **Centralized Quality Policies:** Enforcing mandatory capstone review thresholds across entire engineering teams.
  - **CI/CD Quality Gates:** Headless, automated dual-agent verification bots running inside pull request pipelines.
  - **Compliance & Audit Trails:** Cryptographically signed logs of all adversarial review decisions and approvals for SOC2/ISO audits.
  - **Shared Team Knowledge Stores:** Centralized aggregation of `agy-autotrain` cheatsheets across enterprise developer pools.
  - **Priority SLA & Dedicated Support:** Direct engineering support and custom LLM peer harness onboarding.

---

## 3. Features to Investigate During Beta

During public beta interviews, we will evaluate whether engineering leaders perceive sufficient value in:
1. **Centralized License Compliance:** A clean commercial license removing PolyForm noncommercial liabilities.
2. **Multi-Model Orchestration:** Support for proprietary internal LLM endpoints (e.g. self-hosted corporate models acting as peers).
3. **Team Analytics Dashboard:** High-level metrics on common regression patterns caught by the peer before code merge.
4. **Automated PR Bot:** Seamless GitHub Actions bot that runs capstone reviews without requiring local developer invocation.

---

## 4. Unresolved Business Decisions

The following questions require formal evaluation before any commercial release:
1. **Perpetual vs. Subscription Licensing:** Does the developer market prefer annual seat licenses, team volume subscriptions, or perpetual licenses with maintenance contracts?
2. **License Architecture:** Should commercial rights be sold as an alternative commercial license to the source code, or as closed-source enterprise binary extensions built on top of the open core?
3. **Billing Integration Partner:** Evaluation of developer-friendly merchant of record services (e.g. Stripe, Polar.sh, Lemon Squeezy) when ready.
4. **Enterprise Legal Indemnification:** Requirements for IP warranty and enterprise-grade support terms.
