# Clavity Marketing & Repository Audit

**Date:** 2026-11-01  
**Auditor:** Clavity Agentic Engineering  
**Scope:** Repository structure, product architecture, documentation, website implementation, and GTM readiness.

---

## 1. Executive Summary

This audit assesses the Clavity monorepo (`https://github.com/ckir/clavity`) as the single source of truth for planning and scaffolding the Go-to-Market (GTM), public beta, and developer marketing infrastructure.

Clavity is a developer tool ecosystem enabling live peer-collaboration between AI coding agents. Its flagship integration pairs **Claude Code** (driver: implements, verifies) with **Google Antigravity** (`agy`) (peer: reviews, recommends via expert panels and capstone audits) within the same workspace.

---

## 2. Repository Structure & Monorepo Roster

The repository is an umbrella monorepo hosting five active member tools/plugins, centralized documentation, an installer/packaging toolchain, and a single-page static website.

### Top-Level Organization

| Path | Purpose / Description |
|---|---|
| `clavity-dotnet/` | **Primary bridge:** .NET 10 Language Server (`clavity-ls`) exposing Antigravity as an MCP server to Claude Code. Cross-platform. |
| `clavity-classic/` | **Failover bridge:** Original Rust-based bridge utilizing `psmux` (`send-keys`/`capture-pane`) and the `agentmemory` bus. Windows installer. |
| `agy-autotrain/` | **Knowledge engine (Add-on):** Auto-trains clavity's Antigravity knowledge from live usage; verifies assumptions and compiles manuals. |
| `commonmemory/` | **Shared memory (Add-on):** Shared cross-agent memory convention using the `@agentmemory/agentmemory` signal bus. |
| `review-relay/` | **Web model review (Add-on):** Assisted copy-paste review rounds with web AI models (ChatGPT, Gemini, Meta AI) via AiSave extension. |
| `site/` | Single-page static website published via GitHub Pages. |
| `docs/` | Monorepo-level specifications, runbooks, trackable ledgers, and guides. |
| `scripts/` | PowerShell automation scripts for releases, doc audits, tracker verification, and CI checks. |
| `seed/` | Compiled driver knowledge header (`golden-header.md`) and cheatsheet. |
| `build/` | Monorepo roster manifest (`build/members.json`). |
| `.github/` | GitHub workflows (`pages.yml`, `ci-*.yml`), issue templates, site checker suite. |
| `archive/` | Historical and retired code (e.g., retired Inno installers). |

### Important Historical & Roster Discrepancies

- **Ghidrust Retirement:** Former member `ghidrust` (headless Ghidra reverse-engineering MCP server) was fully retired from this monorepo on 2026-09-14 and superseded by the standalone project `re-ghidra-mcp-cc`. References in prior marketing specs to `/products/ghidrust/` must be treated as archival or redirected to the standalone project.
- **Roster Count:** As defined in `build/members.json`, exactly 5 members currently exist: `clavity-dotnet`, `clavity-classic`, `agy-autotrain`, `commonmemory`, and `review-relay`.

---

## 3. Website Architecture & Routes

### Current Implementation

- **Location:** `site/` directory in the repository root.
- **Technology Stack:** Pure static HTML5, CSS3, and vanilla JavaScript (ES5/ES6). No npm, node build pipelines, bundlers, or external CSS/JS frameworks.
- **Hosting:** GitHub Pages via GitHub Actions (`.github/workflows/pages.yml`).
- **Domain:** `https://ckir.github.io/clavity/` (canonical link).

### Existing Routes & Anchor Targets

Currently, the website is a single page (`site/index.html`):
- `/` (Home page)
  - `#how` — "How it works" overview of the driver/peer relationship.
  - `#products` — Product cards for the 5 tools.
  - `#install` — Interactive terminal command list with copy-to-clipboard functionality.
  - `#guides` — Links to PDF and HTML user guides in `docs/`.

### Design System & Visual Assets

- **Color Palette:**
  - Backgrounds: `--bg: #020713`, `--bg-mid: #052b70`, `--bg-deep: #001333`, `--panel: rgba(5, 43, 112, 0.35)`
  - Driver accent (Claude Code): `--driver: #ff4b18` (vibrant orange), `--driver-soft: #ffb14a`
  - Peer accent (Google Antigravity): `--peer: #00cfff` (neon cyan), `--peer-soft: #00eaff`
  - Typography: `--font: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`
  - Text colors: `--text: #eaf2ff`, `--muted: #9db3d6`
- **Branding Assets Available in `site/assets/`:**
  - `banner.webp` (144 KB, 1670x941): Glowing neon connector bridge connecting Claude Code and Antigravity terminals.
  - `clavity.svg` (10.6 KB): Primary vector logo.
  - `og.jpg` (92.4 KB, 1200x630): OpenGraph social sharing card.
  - `profile.png` (243.9 KB, 96x96): Circular brand emblem.

---

## 4. Build, Deployment, and Quality Verification

### Website Build & Deployment

The deployment pipeline is defined in `.github/workflows/pages.yml`:
1. Triggers on push to `main` (and PRs for verification) affecting `site/**`, `README.md`, `.github/workflows/pages.yml`, or `.github/site-checks/**`.
2. Runs unit test suite: `python3 -m unittest discover -s .github/site-checks` (137 tests passing).
3. Executes structural and parity checker: `python3 .github/site-checks/check_site.py --site site --readme README.md`.
4. Uploads static artifact and deploys directly to GitHub Pages.

### Strict Website Validation Rules (`check_site.py`)

Any site modifications must satisfy the strict checks enforced by `.github/site-checks/check_site.py`:
- **Check 1:** No root-relative URLs (`/style.css` is forbidden; `./style.css` or relative paths required).
- **Check 2:** Every local reference and in-page anchor must resolve to an existing file or ID within `site/`.
- **Check 3:** External GitHub repository links must use sanctioned allowlist prefixes (`/ckir/clavity`, `/blob/main`, `/tree/main`, `/releases`, `/issues`); no raw github content links.
- **Check 4:** Raster images under `site/assets/` must not exceed 300 KB.
- **Check 5:** Zero third-party asset loads (no external fonts, scripts, stylesheets, or trackers).
- **Check 6:** Exact command and copy-button parity with the installation section of `README.md`.
- **Check 7:** README parity for blockquote waiver text units (`waiver-1` and `waiver-2`).

### Monorepo Quality Gates

Existing pre-push and task-runner gates:
- `just check-user-facing-docs`: Enforces that all user-facing docs are registered in `docs/user-facing-docs.txt` and match voice guidelines.
- `just check-member-docs`: Validates README and CHANGELOG contracts for all monorepo members.
- `just check-control-bytes`: Scans all tracked `.md` and `.ps1` files for illegal C0 control bytes.
- `just check-tracker-status`: Validates backlog items and roadmap statuses.
- `just check-doc-stubs`: Prevents re-expansion of pointer stubs.

---

## 5. Verified Product Capabilities & Installation

Only capabilities verified in source code and existing documentation are listed:

### 1. clavity-dotnet (Flagship / Primary Bridge)
- **Role:** Language Server (`clavity-ls`) that exposes Antigravity (`agy`) as an MCP server to Claude Code.
- **Platform:** Cross-platform (Windows x64, Linux x64, macOS arm64/x64).
- **Installation:**
  ```bash
  claude plugin marketplace add ckir/clavity
  claude plugin install clavity@clavity
  ```
- **Capabilities:**
  - Automated background binary download from GitHub Releases.
  - Multi-round adversarial panel review (`adversarial-panel-review`).
  - Pre-completion code review gate (`agy-capstone`).
  - Test suite exhaustiveness audit (`agy-test-audit`).
  - Automatic repo defect capture and ranked backlog triage (`start the triage`).

### 2. clavity-classic (Failover Bridge)
- **Role:** Standalone Rust binary bridging Claude Code and Antigravity over `psmux` and `agentmemory`.
- **Platform:** Windows only.
- **Installation:** Download `clavity-classic-setup-<version>.exe` from GitHub Releases.
- **Capabilities:** Failover when .NET runtime or language server is unavailable.

### 3. agy-autotrain (Add-on)
- **Role:** Empirical knowledge capture for Antigravity.
- **Installation:** `claude plugin install agy-autotrain@clavity`
- **Capabilities:** Observes driver operations, probes Antigravity behavior, compiles findings into `driver-cheatsheet` and knowledge manuals.

### 4. commonmemory (Add-on)
- **Role:** Cross-agent shared memory convention.
- **Installation:** `claude plugin install commonmemory@clavity` (requires npm package `@agentmemory/agentmemory`).
- **Capabilities:** Structured tagging and cross-reading of project facts, gotchas, and architectural decisions.

### 5. review-relay (Add-on)
- **Role:** External web model review coordinator.
- **Installation:** `claude plugin install review-relay@clavity`
- **Capabilities:** Formats review rounds for ChatGPT, Gemini, or Meta AI; integrates with AiSave browser extension to ingest web responses into the workspace.

---

## 6. Current Licensing & Attribution

- **Core Repository License:** PolyForm Noncommercial License 1.0.0 (`LICENSE`).
  - Permitted: Free non-commercial use, modification, and distribution.
  - Prohibited: Commercial use without a separate commercial license from the licensor.
- **Copyright Holder:** (c) 2026 Costas Kirgoussios and the clavity authors.
- **Third-Party Dependencies:** Permissively licensed (MIT, Apache-2.0, BSD, ISC). Zero copyleft (GPL/AGPL/LGPL) dependencies.
- **Trademarks:** "Antigravity" is a trademark of Google LLC; "Claude" and "Claude Code" are trademarks of Anthropic; "Ghidra" is a trademark of the NSA. Clavity is independent and unaffiliated with these entities.

---

## 7. Current Analytics, Registrations & Forms

- **Analytics:** None. No web analytics scripts, telemetry collectors, or tracking pixels currently exist.
- **Forms:** None. No email subscription, waitlist, or beta registration forms are implemented.
- **Telemetry:** Clavity does not transmit user code, prompts, credentials, or terminal content to external servers.

---

## 8. Missing Capabilities & GTM Gap Analysis

1. **Information Architecture:** Single-page site lacks deep-dive product pages (`/products/bridge/`, `/products/agent-knowledge/`, etc.), technical workflow explanations (`/how-it-works/`), and commercial evaluation pages (`/pricing/`, `/roadmap/`).
2. **Beta Lead Intake:** No mechanism for capturing developer interest, team size, primary workflows, or commercial pilot intent.
3. **Analytics & Funnel Measurement:** No event bus or conversion attribution for measuring GitHub click-throughs, install copy clicks, or beta registrations.
4. **GTM & Marketing Documentation:** Monorepo lacks structured marketing strategy, positioning guidelines, launch checklists, content calendars, and licensing review documents.
5. **Community & GitHub Engagement:** Repository lacks issue templates for structured beta feedback, discussion category guidelines, and topic tags.
6. **Campaign Collateral:** Monorepo lacks draft launch copy for developer channels (Show HN, Reddit, X, LinkedIn, Product Hunt).

---

## 9. Recommendations & Implementation Strategy

1. **Preserve Static Architecture:** Keep `site/` as a pure, zero-dependency static site. Subpages will use standard static directory structures (e.g. `site/products/bridge/index.html`) using relative asset links to maintain 100% compatibility with GitHub Pages and `check_site.py`.
2. **Handle Specification vs. Reality Differences:**
   - Map `/products/bridge/` to the flagship `clavity-dotnet` / `clavity-classic` pairing.
   - Map `/products/agent-knowledge/` to `agy-autotrain`.
   - Map `/products/shared-memory/` to `commonmemory`.
   - Add `/products/review-relay/` to represent the complete 5-member roster.
   - Provide an informative archival/status notice for `/products/ghidrust/` clarifying that headless Ghidra support was spun out to the standalone `re-ghidra-mcp-cc` project.
3. **Respect Parity & Gate Invariants:**
   - Keep the `#install` section and the two waiver blockquotes on `site/index.html` byte-identical to `README.md` to guarantee `check_site.py` passes.
   - Register any new tracked `.md` documentation in `docs/user-facing-docs.txt` where required by `scripts/check-user-facing-docs.ps1`, or ensure it conforms to non-touch / internal specifications.
   - Ensure all files are clean of invalid C0 control bytes.
