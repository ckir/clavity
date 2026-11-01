# Clavity Pricing Research & Commercial Validation Methodology

Methodological framework for assessing developer willingness-to-pay, conducting discovery interviews, and validating commercial demand.

> [!NOTE]
> **No Pricing Established:** In compliance with project constraints, this document defines research protocols and interview questions. No specific price points are invented or published.

---

## 1. Research Objectives

1. Determine whether engineering organizations view agent review as a critical software quality tool worthy of a dedicated software budget.
2. Uncover the primary value metrics (e.g. per active developer seat, per repository, or flat team tier).
3. Compare customer appetite for recurring SaaS subscriptions versus perpetual workstation licenses with maintenance.
4. Establish criteria for recruiting paid pilot customers for initial commercial validation.

## 2. Customer Interview Guide

The following questions should be used in 20–30 minute discovery interviews with engineering managers, tech leads, and autonomous AI developers.

### Section A: Current Workflow & Friction
1. How many developers on your team currently use AI coding assistants (Claude Code, Antigravity, Cursor, Copilot)?
2. How do you currently prevent subtle AI hallucinations or untested edge cases from reaching production?
3. What percentage of human PR review time is currently spent reviewing AI-generated code versus writing new features?
4. What happens when an agent hallucinates a passing unit test that fails under real production loads?

### Section B: Clavity Experience & Value Perception
5. In your evaluation of Clavity, what was the most valuable review gate (`adversarial-panel-review`, `agy-capstone`, or `agy-test-audit`)?
6. Did the dual-agent review catch real defects that a single agent missed? Could you provide a concrete example?
7. How much developer time per week did the automated triage or capstone review save your team?

### Section C: Licensing & Commercial Structure
8. How does your company currently purchase developer tools (e.g., corporate credit card expense, centralized IT procurement, GitHub Marketplace)?
9. For developer tools with local execution, do you prefer annual per-seat subscriptions or perpetual licenses with maintenance?
10. Does your legal team have policies prohibiting noncommercial licenses (such as PolyForm Noncommercial) in commercial codebases?
11. If a commercial version included centralized team review policies and CI/CD pull-request automation, would that justify enterprise procurement?

## 3. Van Westendorp Price Sensitivity Protocol

When conducting pricing discovery with qualified buyers, utilize the standard 4-question Van Westendorp Price Sensitivity Meter (PSM):
1. At what price point would you consider Clavity to be so expensive that you would not consider buying it? (Too expensive)
2. At what price point would you consider Clavity to be priced so low that you would question its quality or reliability? (Too cheap)
3. At what price point would you say Clavity is starting to get expensive, but you would still consider purchasing it? (Expensive / High end)
4. At what price point would you consider Clavity to be a great value for the money? (Bargain / Good value)

## 4. Paid Pilot Validation Program

Before developing proprietary enterprise infrastructure, validate willingness-to-pay via structured paid pilots:
- **Cohort Size:** 3–5 commercial teams.
- **Pilot Term:** 60 days.
- **Incentive:** Direct weekly pairing with Clavity maintainers, custom CI/CD integrations, and roadmap influence.
- **Success Criteria:** 80% of pilot participants sign commercial letters of intent (LOI) or convert into initial commercial contracts upon conclusion.

## 5. Commercial Interest Tracking

Track inbound commercial interest through the website beta intake form (`/beta/`):
- Monitor selection of "Team / Company" applicant category.
- Log voluntary responses indicating "Interested in Commercial Edition".
- Follow up within 48 business hours with the qualitative interview invitation.
