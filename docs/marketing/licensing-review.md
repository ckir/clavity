# Clavity Licensing Review & Commercial Dual-Licensing Assessment

Research and analysis of current licensing constraints, dependency compliance, and commercial dual-licensing pathways.

> [!CAUTION]
> **Legal Disclaimer:** This document constitutes engineering and product research, not formal legal advice. A qualified intellectual property attorney must review any commercial licensing changes prior to execution.

---

## 1. Existing License Inventory

- **Governing Repository License:** PolyForm Noncommercial License 1.0.0 (`LICENSE`).
  - **Permitted Uses:** Noncommercial evaluation, research, personal study, open-source development that generates no commercial revenue.
  - **Restrictions:** Explicitly prohibits commercial use, meaning businesses generating revenue cannot deploy Clavity for commercial software development without an exemption.
- **Copyright Ownership:** Held by Costas Kirgoussios and the clavity authors (per `NOTICE`).

## 2. Third-Party Dependency Analysis

Per the audit of `NOTICE` and crate/project manifests:
- **First-Party Code:** All core logic across `clavity-dotnet`, `clavity-classic`, `agy-autotrain`, `commonmemory`, and `review-relay` is first-party code.
- **Permissive Ecosystem Dependencies:**
  - Rust crates (in `clavity-classic`): Permissive (MIT / Apache-2.0).
  - .NET assemblies (in `clavity-dotnet`): Microsoft Public / MIT.
  - Python scripts (in `review-relay` / bridge test helpers): MIT / PSF.
- **Zero Copyleft Contamination:** No GPL, AGPL, or LGPL dependencies are bundled or statically linked into binary distributions.
- **External Interoperability:** External tools driven by Clavity (Claude Code, Antigravity, Ghidra, JDK) are not bundled; they are supplied independently by the end-user.

## 3. Contribution Ownership & Contributor Agreements

- **Current State:** The repository does not currently enforce a formal Contributor License Agreement (CLA) or Developer Certificate of Origin (DCO) beyond standard GitHub pull request submission terms.
- **Impact on Commercialization:** To re-license or dual-license software with commercial exemptions, the copyright holders must possess the legal authority to do so.
  - If all significant contributions are authored by the primary maintainer, commercial licensing remains straightforward.
  - If external contributors submit code under PolyForm Noncommercial without a CLA/DCO granting commercial relicensing rights, relicensing external contributions commercially could require contributor consent.
- **Recommendation:** Implement a Developer Certificate of Origin (DCO) or lightweight Contributor License Agreement for external pull requests.

## 4. Commercial Dual-Licensing Alternatives

To enable a future commercial edition, three primary models are viable:

### Model A: Pure Dual-Licensing (e.g. MySQL / Qt Model)
- The codebase remains identical. Users who qualify for noncommercial use use PolyForm (or AGPL-3.0).
- Commercial enterprises purchase a commercial license from the copyright owner that waives the noncommercial/copyleft restriction.
- **Pros:** Maximum transparency, single codebase.
- **Cons:** Enterprises sometimes find dual-licensing negotiations complex.

### Model B: Open Core with Proprietary Commercial Extensions
- Core engine (`clavity-ls`, CLI bridge, local review disciplines) remains open under PolyForm or a permissive license (MIT/Apache).
- Advanced team features (centralized policy server, CI/CD PR bots, enterprise SSO, team audit aggregators) are packaged as separate commercial proprietary plugins/binaries.
- **Pros:** Standard SaaS/developer tool pattern; clean separation of concerns.
- **Cons:** Requires maintaining two distinct codebases/repositories.

### Model C: Business Source License (BSL / FSL)
- Code is released under a Fair Source or Business Source License that allows free non-production/free individual usage, transitioning to Apache 2.0 after a defined period (e.g. 2–3 years), while requiring commercial licenses for large enterprise deployments.
- **Pros:** Single codebase with explicit commercial boundaries.
- **Cons:** Community perception varies.

## 5. Key Questions Requiring Specialist Legal Review

1. Does using PolyForm Noncommercial 1.0.0 create unintended hesitation among individual developers who work on open-source projects at commercial employers?
2. What specific contributor agreement (DCO vs. CLA) is best suited to safeguard future commercial relicensing without discouraging community PRs?
3. What is the recommended trademark usage policy for "Clavity", and how should third-party trademark disclaimers (Google Antigravity, Anthropic Claude) be formatted in commercial collateral?
