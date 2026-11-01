# Clavity Website Specification & Information Architecture

Technical specification, navigation hierarchy, component models, and design standards for `site/`.

## 1. Information Architecture & Sitemap

The website maintains a clean, static, multi-route hierarchy hosted directly from the `site/` directory on GitHub Pages.

```text
site/
├── index.html                   # Homepage (/)
├── style.css                    # Unified design system styles
├── script.js                    # Interactive controls & copy handlers
├── assets/                      # Brand raster & vector assets
│   ├── banner.webp
│   ├── clavity.svg
│   ├── og.jpg
│   └── profile.png
├── products/                    # Product deep-dive pages
│   ├── bridge/index.html        # Flagship bridge (clavity-dotnet & classic)
│   ├── agent-knowledge/index.html # Empirical learning engine (agy-autotrain)
│   ├── shared-memory/index.html # Cross-agent notebook (commonmemory)
│   ├── review-relay/index.html  # External web model review (review-relay)
│   └── ghidrust/index.html      # Archival notice & redirection to standalone project
├── how-it-works/index.html      # Workflow breakdown & stage explanations
├── docs/index.html              # Documentation gateway
├── community/index.html         # GitHub Discussions, contributing, and feedback
├── roadmap/index.html           # Public engineering milestones and status
├── changelog/index.html         # Release notes and history
├── beta/index.html              # Public beta overview & optional interest form
├── pricing/index.html           # Dual-edition overview & commercial validation
└── about/index.html             # Philosophy, authors, and noncommercial licensing
```

## 2. Homepage Section Specifications

1. **Global Header & Navigation:**
   - Brand logo (`assets/clavity.svg`) linking to `/`.
   - Links: Products (dropdown/group), How it works, Docs, Roadmap, Community, Beta.
   - Primary Header CTA: "Join Beta" or "Install".
2. **Hero:**
   - Banner graphic (`assets/banner.webp`).
   - Main Headline: "Claude Code drives. Antigravity reviews."
   - Subline: "Two AI agents, one folder, every step cross-checked."
   - Visual Workflow Stages: Interactive/scannable chips showing Driver vs. Peer stages.
   - Primary CTA: Direct jump to `#install` and link to `/beta/`.
3. **Product Demonstration / Interactive Preview:**
   - Visual simulation or terminal recording placeholder showcasing terminal split-screen (Claude on left, Antigravity on right).
4. **Core Value Propositions:**
   - 3-column benefit cards: Independent Peer Review, Automated Test Hardening, Shared Memory & Continuous Learning.
5. **Flagship Bridge Introduction:**
   - Deep dive into `clavity-dotnet` (Language Server / MCP stdio) and `clavity-classic` (failover).
6. **Product Ecosystem Overview:**
   - Card grid for `clavity-dotnet`, `clavity-classic`, `agy-autotrain`, `commonmemory`, `review-relay`.
7. **How Collaboration Works:**
   - Detailed visual breakdown of Brainstorm -> Spec Review -> Plan Review -> Build -> Capstone -> Test Audit.
8. **Install Section (`id="install"`):**
   - **Crucial CI Parity Requirement:** Must contain verbatim code commands matching `README.md` and pass `check_site.py`.
   - Accessible copy buttons with `role="status"` feedback.
9. **Guides & Documentation Links:**
   - Direct links to User Guides (PDF/HTML) and repo markdown resources.
10. **Public Beta Invitation:**
    - Callout banner inviting developers to evaluate the beta and submit feedback.
11. **Global Footer:**
    - Brand emblem (`assets/profile.png`), PolyForm Noncommercial license notice, trademark disclaimer, GitHub repo, and legal links.

## 3. Product Page Template Contract

Each product page under `site/products/*/index.html` adheres to a standard, accessible template:
- **Product Title & Role:** Clear designation of driver vs. peer vs. add-on.
- **Problem Solved:** Clear explanation of developer frustration addressed.
- **Verified Capabilities:** Bulleted list of code-verified features.
- **Installation & Setup:** Specific plugin or binary install instructions.
- **Requirements & Compatibility:** OS, prerequisite tools (e.g. `superpowers`), model versions.
- **Known Limitations:** Honest, developer-first disclosure of current constraints.
- **GitHub Destination:** Direct link to product subfolder on GitHub (`/tree/main/<member>`).
- **Related Products:** Cross-links to companion tools in the ecosystem.

## 4. Beta Conversion Flow

- **Zero-Friction Access:** Developers can install directly from terminal without registration.
- **Optional Registration:** `/beta/` features an optional interest intake form.
- **Form Submissions:** Client-side validated, privacy-respecting form connecting to a configurable webhook/API handler or structured development placeholder.
- **Success State:** Immediate confirmation screen with direct link to GitHub Discussions.

## 5. Responsive & Accessibility Standards

- **Mobile First:** Single-column layout on small viewports (<640px), 2-column cards at >=640px, full multi-column grid at >=960px.
- **Accessible Contrast:** Text contrast ratios exceeding WCAG AA (minimum 4.5:1 for normal text).
- **Reduced Motion:** Honor `prefers-reduced-motion` across all animations and smooth scrolling.
- **Screen Reader Support:** All actionable buttons must carry descriptive `aria-label` attributes; status updates use `role="status"` regions.
- **No Third-Party Runtime Bloat:** All CSS, fonts, and scripts bundled locally to prevent privacy leakage and satisfy `check_site.py` Check 5.

## 6. Technical SEO & Social Metadata

- Standardized OpenGraph cards (`og:title`, `og:description`, `og:image`, `og:url`, `og:type`).
- Canonical `<link rel="canonical" ...>` tags on every route.
- Valid semantic HTML tags (`<main>`, `<header>`, `<nav>`, `<article>`, `<section>`, `<footer>`).
- Fast static loading with zero layout shift (CLS < 0.1).
