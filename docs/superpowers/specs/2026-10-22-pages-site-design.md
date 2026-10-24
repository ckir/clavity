# clavity GitHub Pages site — design

Date: 2026-10-22 · Status: approved by the owner 2026-10-22 (headline/section copy still to be approved when written)

> **Amended 2026-10-24.** `main` commit `c89ab699` deleted the README `### WARNING` section (the
> `--prompt-interactive` workaround, judged obsolete by the owner). The page therefore no longer quotes it or
> links the pairing INSTALL file, and checks 3, 6 and 7 no longer reference either. Sections below are
> updated to match; the review-history records at the end are left as written.

## Intent and why

A single-page, modern site for the `clavity` umbrella repo, published on GitHub Pages
(`https://ckir.github.io/clavity/`). Its one job: a visitor understands within ~30 seconds the
**Claude-drives-a-live-agy-peer workflow** — Claude Code is the *driver* (implements, verifies),
Antigravity (`agy`) is the *peer* (reviews, recommends), and every stage is cross-checked.
Installing and choosing a product come second to that understanding.

## Goals

- Hero that explains the workflow immediately (see "Hero" below; chosen as mockup **A**).
- Show the six stages, each tagged driver (orange) or peer (blue).
- Tell a visitor which of the five products they need, and give the install commands.
- Reuse the premade artwork in `/home/user/Pictures/Clavity` (neon bridge banner, profile image, SVG).
- Fast and dependency-free: no build step, no Node toolchain in the repo.
- Looks good on phones. The page is **intentionally dark in every OS colour scheme** (the banner has an
  opaque dark background, so a light variant would clash): declare `<meta name="color-scheme" content="dark">`
  and do not ship a light theme.

## Non-goals

- Multi-page site, blog, search, or a docs portal. Deep docs stay in the repo and are linked.
- Greek (or any) translation **now**. The user chose "Greek later"; keep the markup
  translation-friendly (all copy in the HTML, no text baked into images other than the banner).
- A static site generator, JS framework, or analytics/tracking.
- Editing the README's `HUMAN ONLY` block. The site paraphrases its workflow description and quotes only
  the two waiver paragraphs verbatim (see "How it works"); it does not restate the block otherwise.

## Anti-goals (a failure even if it technically works)

- A visitor leaves still unsure what "agy peer" means or who does what.
- The page implies affiliation with Google or Anthropic (the banner shows their logos; the
  README trademark disclaimer must appear in the footer verbatim in meaning).
- Install instructions that drift from the README, or claim cross-platform support the README does not.
- Heavy page: large unoptimised art blocking first paint.

## Constraints

- GitHub Pages deployed via a **GitHub Actions workflow** (`actions/upload-pages-artifact` +
  `actions/deploy-pages`), not the legacy `gh-pages` branch. Measured 2026-10-22 via
  `gh api repos/ckir/clavity/pages`: the repo is public, Pages is **already enabled with
  `build_type: workflow`**, no custom domain/CNAME, URL `https://ckir.github.io/clavity/`. If that setting
  were ever off, `deploy-pages` would fail and mark `main` red, so the builder re-checks it before
  landing the workflow.
- Site source lives in a new top-level `site/` folder. It is not a "product": it must not be added to
  `build/members.json` (the validator enforces exactly 5 members), and existing CI must stay green.
  Do **not** put a `README.md` inside `site/`: `ci-member-docs.yml` triggers on `*/README.md`.
- Workflow filename `pages.yml`. Triggers (`on:`): `pull_request` and `push` to `main`, each with
  paths `site/**`, **`README.md`** (the drift checks below must run when the README changes) **and
  `.github/workflows/pages.yml`**, plus `workflow_dispatch`. Two jobs:
  - `build` — **no event condition, so it runs for every trigger above** (a skipped `build` would also
    skip `deploy`, which `needs` it): packages `site/` with `upload-pages-artifact` and runs the
    checks in Verification. This gives a `site/`-only PR a real check (`merge-gate.yml` only waits for
    checks that register, so without it such a PR would be unverified).
  - `deploy` — `needs: build`, `if: github.event_name != 'pull_request'`, `environment: github-pages`.
  - Workflow-level `permissions: contents: read`; the deploy job adds `pages: write` and
    `id-token: write`. Put `concurrency: { group: pages, cancel-in-progress: false }` on the **deploy
    job only**, so PR `build` runs stay parallel and are not queued behind each other.
  - Pin the two Pages actions to their **current major tag at build time**, matching the repo's
    convention (`actions/checkout@v7`). Measured 2026-10-22: `deploy-pages` v5.0.1,
    `upload-pages-artifact` v5.0.0. The builder re-checks; do not copy older versions from memory.
- **URL shape.** The site is served from the subpath `https://ckir.github.io/clavity/`, so every
  asset and anchor link inside the page is **document-relative** (`./style.css`, `./assets/…`) — never
  root-relative (`/style.css`). Anything that must be absolute (`og:image`, `og:url`, canonical) uses the
  full `https://ckir.github.io/clavity/…` URL.
- **Links out of `site/`.** Only `site/` is deployed, so every link to a repo file (LICENSE, product
  READMEs, `docs/USER_GUIDE.*`, the pairing INSTALL file) is a full
  `https://github.com/ckir/clavity/blob/main/<path>` URL, never a relative path.
- License of the repo is PolyForm Noncommercial 1.0.0; the footer states it and links `LICENSE`.
- Art provenance: the user supplied the files in `/home/user/Pictures/Clavity` (a path on the owner's
  machine only). The builder copies the needed files **once** into `site/assets/`; nothing in the repo or
  the workflow may reference that path. `ClavityNeonConnectorBridge.png` is 1.5 MB / 1670×941 and
  `profile_clavity.png` 244 KB.
- Image budget (my call): **every raster file under `site/assets/` is ≤ 300 KB**. The hero banner is
  WebP (or AVIF) with **no PNG fallback** — current browsers all decode WebP — checked for banding on
  the neon gradients. The exact conversion command is recorded in a comment at the top of
  `site/index.html` (or the commit message) so it can be repeated.
- Zero third-party requests: a system font stack (`system-ui, -apple-system, "Segoe UI", Roboto,
  sans-serif`), no external font stylesheets, CDNs, or analytics. Everything the page loads comes from
  `site/`.
- Planned layout (my call): `site/index.html`, `site/style.css`, `site/script.js`,
  `site/assets/…` (banner, favicon, og image).

## Approaches considered

1. **Hand-written static HTML/CSS/JS in `site/` + Pages workflow — chosen.** No toolchain,
   fastest, fully custom neon look. Greek later = a second `el/index.html` with a language toggle;
   risk is drift between two pages (mitigate with a small same-sections check when Greek lands).
2. Astro or similar generator. Better i18n and components, but adds `package.json`, a lockfile,
   Dependabot churn and a CI build for a one-page site. Rejected for now; migrating later is cheap
   because content would already be plain HTML.
3. Jekyll / docs theme from Markdown. Zero workflow, but the theme fights the custom hero and
   gives the least visual control. Rejected.

## Decided design

### Hero (mockup A)

- Full-width banner (`ClavityNeonConnectorBridge`) at the top.
- Headline (**proposed copy — builder may tune, owner approves**): *Claude Code drives. Antigravity reviews.*
  Subline: *Two AI agents, one folder, every step cross-checked.*
- A horizontal strip of **six** stage chips (owner's decision), each tagged driver (orange) or peer
  (blue), arrow-linked, so every driver stage visibly has its peer gate:
  1. Brainstorm — Claude (driver)
  2. Spec review — agy panel (peer) [`adversarial-panel-review`]
  3. Plan review — agy panel (peer) [`adversarial-panel-review`]
  4. Build — Claude (driver)
  5. Capstone — agy (peer) [`agy-capstone`]
  6. Test audit — agy (peer) [`agy-test-audit`]
- One prominent **Install** call to action that scrolls to the install section.
- On narrow screens the strip wraps or becomes a vertical list; it must not scroll horizontally.

### Sections below the hero (order)

1. **How it works** — owner's decision (c): **paraphrase the workflow, quote the two waiver
   lines verbatim.** The paraphrase covers brainstorm → panel-reviewed spec → panel-reviewed plan →
   implementation → capstone → test audit, the driver/peer roles, and the auto-triage bonus, and links to
   the README. Exactly two README paragraphs are quoted **verbatim** (rendered as quotes, with a link
   to the README), each in its own element carrying a fixed id value in a `data-readme-quote` attribute
   (used by check 7):
   - `data-readme-quote="waiver-1"` — the paragraph starting "All the above can be waived by prompts.";
   - `data-readme-quote="waiver-2"` — the paragraph starting "In case you have problem to start agy".
   The builder writes the paraphrase and the owner approves it.
2. **Which product do you need?** — five cards. `clavity-dotnet` (primary) and `clavity-classic`
   (failover) are visibly marked *pick exactly one*; `agy-autotrain`, `commonmemory`, `review-relay`
   are opt-in add-ons. Each card: one line, link to its `README.md`.
3. **Install** — exactly these commands (the fenced block under "How to get started" in README.md; note
   `clavity-dotnet`'s plugin name is `clavity`), **one copy-to-clipboard button per line**, with the
   trailing `# clavity-dotnet` comment shown but not copied. The page says plainly that `clavity-dotnet`
   and `clavity-classic` are mutually exclusive, so a visitor copies only the lines they want:
   ```
   claude plugin marketplace add ckir/clavity
   claude plugin install clavity@clavity          # clavity-dotnet
   claude plugin install agy-autotrain@clavity
   claude plugin install commonmemory@clavity
   claude plugin install review-relay@clavity
   ```
   plus a short, **Windows-only** note for the `clavity-classic` installer (summarise the README's
   three steps: take `clavity-classic-setup-<version>.exe` from the `clavity-v<N>` release on the Releases
   page, check the `.sha256`, run it; never imply it is cross-platform). Also: superpowers must be installed
   first. (The `--prompt-interactive` workaround note and its pairing INSTALL link were removed 2026-10-24; see
   the amendment at the top.)
4. **Guides** — links to `docs/USER_GUIDE.pdf` and `docs/USER_GUIDE.html` on GitHub (the Greek guide
   is a later-phase addition alongside the Greek page).
5. **Footer** — license (PolyForm Noncommercial), repo/issues links, and the trademark/non-affiliation
   disclaimer.

### Visual language

- Dark-only, taken from the artwork: deep navy background, orange = Claude/driver, blue/cyan =
  agy/peer, white wordmark. Glow accents used sparingly. Honour `prefers-reduced-motion`. Exact colour
  values are sampled by the builder from `clavity.svg` (its `bg`, `orange` and `cyan` gradient stops)
  and defined once as CSS custom properties.
- Only light interactivity: copy buttons, an optional subtle scroll reveal. No frameworks.
- Accessibility: real text for all copy, alt text on art, sufficient contrast, keyboard-usable
  copy buttons, `lang="en"` on `<html>`.
- Tab icon / social card: derive favicon from `clavity.svg`; `og:image` from the banner.

### Verification the builder should do

- Serve `site/` **under a `/clavity/` prefix** locally (e.g. serve its parent directory with `site/`
  symlinked or copied as `clavity/`) so a root-relative path that would 404 in production fails
  locally too; check desktop + phone widths and both OS colour schemes (the page must stay dark).
- The `build` job fails if any of these structural checks fails (each is a mechanical test, not a
  judgement about intent):
  1. In `site/*.html`, any `href`, `src`, `srcset` or `content` value, or in `site/*.css` any `url(...)`,
     starts with a single `/` (root-relative; `//host` and `https://…` are not).
  2. Any local reference (relative `href`/`src`/`srcset`/`url()`) does not resolve to an existing file
     inside `site/`; `#anchor` links must match an `id` in the page.
  3. Any `href` is relative and climbs out of `site/` (`../…`), or any `https://github.com/ckir/clavity…`
     URL is not one of: the repo root, `/blob/main/…`, `/tree/main/…`, `/releases…`, `/issues…`; no
     `raw.githubusercontent.com/ckir/clavity/…` link is permitted.
  4. Any raster file under `site/assets/` exceeds 300 KB.
  5. Any resource the page *loads* (`src`, `srcset`, `<link rel=stylesheet|icon|preload href>`, CSS
     `url()`) is an `http(s)://` or `//` URL. Plain `<a href>` links to other sites are fine; the
     only absolute URLs allowed in head/metadata positions are the `og:` `<meta content>` values and
     `<link rel="canonical" href="…">`.
  6. **Install parity (owner's decision: automated).** Every `claude plugin …` command line in the
     README's fenced install block (the first fenced block containing `claude plugin marketplace add`),
     with any trailing `# comment` stripped, appears verbatim in the page's Install section, and the Install
     section contains no `claude plugin …` line that the README lacks. Every copy-to-clipboard payload in the Install section (the `data-copy`
     attribute each button must carry) equals its command line exactly, comment stripped, so a button
     cannot copy something other than what is displayed.
  7. **Quote parity.** `site/index.html` contains **exactly two** elements with `data-readme-quote`,
     with the values `waiver-1` and `waiver-2` (so forgetting the attribute fails instead of
     passing on an empty set). For each, the element's text — tags stripped, HTML entities decoded
     (`&quot;` → `"`), curly quotes folded to straight quotes, whitespace collapsed — must appear in
     README.md after the same folding and after stripping markdown emphasis and link syntax.
  Consequence, accepted: a README change that touches those lines turns the `build` check red until
  `site/` is updated in the same PR, which is the point. If such a README change reaches `main` anyway,
  `build` goes red and `deploy` is skipped, so the live site simply stays on its previous, internally
  consistent version until `site/` is fixed. Any other README edit on `main` also triggers a redeploy of
  an unchanged site: a few seconds of Actions time per README edit, accepted rather than adding
  change-detection logic (the peer's suggested `github.event.commits.*.modified` condition was not adopted:
  the push payload's `commits` array is capped, and `modified` omits added and removed files).
  Residual risk, not mechanically checked: the paraphrased prose in "How it works" and the product cards
  can drift from the README. The owner accepts this by approving the spec.
  Implementation notes for checks 1, 2 and 5: strip optional quotes from CSS `url()` values before
  testing; split `srcset` into its comma-separated candidates and drop the `1x`/`640w` descriptors
  before testing each URL. The check script's language is the builder's call (any available on
  `ubuntu-latest`; no new dependency to install).
- One-time manual checks by the builder (**not** CI gates; CI does no network link-checking): every
  outbound link resolves (README paths, `docs/USER_GUIDE.*`, Releases, LICENSE). Install parity is **not**
  manual any more: checks 6 and 7 compare by content, never by README line number.
- After the workflow lands, confirm it deploys and `https://ckir.github.io/clavity/` loads.

## Left to the builder

File/CSS organisation, image tooling and formats, exact chip/card styling, the scroll-reveal
details, favicon sizes, whether to inline critical CSS.

## Owner actions required (cannot be done in code)

- None to enable: Pages is already on with the Actions source (measured above).
- Approve final copy for the headline/subline and the section prose (spec itself is approved).

## Open points

- Repo housekeeping decided by me, not discussed (already applied in `.gitignore`): `.superpowers/` is
  ignored, and this spec is allowlisted so it can be committed.
- (Settled: the profile image and `clavity.svg` appear on the page; see Decisions. Their exact placement
  is the builder's call.)

## Decisions the owner made (2026-10-22)

- Build approach: option 1, hand-written static site in `site/` (with agy's agreement; see Stand-downs).
- Hero: layout A with **six** chips (spec review and plan review are separate gates).
- README text: **(c)** paraphrase the workflow, quote the two waiver paragraphs verbatim (was three, including the warning, until 2026-10-24).
- Install drift: **automated** in the `build` job (checks 6 and 7), and `pages.yml` also triggers on
  `README.md` changes.
- Single page; Greek later.
- Spec approved as written (2026-10-22), with one change: the profile image (`profile_clavity.png`) and
  `clavity.svg` **appear on the page itself**, not only as favicon/`og:image`. Placement (e.g. the SVG as
  the wordmark/header mark, the profile image in the footer or product area) is left to the builder; both
  need alt text and the ≤ 300 KB raster budget still applies (the SVG is exempt, being vector). Final
  headline and section prose are still approved by the owner once written.

## Calls the spec author made (not discussed with the owner)

- Single-colour-scheme dark page; WebP-only hero with no PNG fallback; 300 KB per raster; system fonts.
- Per-line copy buttons on the install block; the `# clavity-dotnet` comment is not copied.
- Windows-only wording for the `clavity-classic` installer note. (The raw-URL pairing INSTALL link was dropped 2026-10-24.)
- Manual (not CI) outbound-link resolution checking; no network checks in CI.
- `build` job on PRs; `deploy` only on push/dispatch; concurrency on `deploy` only.
- Directory layout `site/{index.html,style.css,script.js,assets/}`; no `site/README.md`.

## Stand-downs

Panel review, round 1 (agy peer + driver measurements). No finding was discarded below the floor and
none is `UNVERIFIED-ACCEPTED`.

- FOLDED: color-scheme claim (dark-only), image-conversion reproducibility and budget, Pages-must-be-enabled
  ordering, workflow-file path filter, links out of `site/` as absolute GitHub URLs, art staged into
  `site/assets/` (no local path), permissions/environment/concurrency block, literal install commands,
  directory layout, stale open point, subpath-relative URLs, PR-time `build` job.
- REJECTED: the peer's suggested action versions (`upload-pages-artifact@v3`, `deploy-pages@v4`) — measured
  with `gh api` 2026-10-22: latest are v5.0.0 and v5.0.1. The finding (pin + permissions) stands; the
  version numbers do not.
- SURFACED TO OWNER (challenged a choice the owner made): hero chip count. Owner ruled for six chips, so this
  finding is now `FOLDED` (see Decisions the owner made).

Round 2 (agy peer; driver verified against GitHub Actions job-skipping semantics and repo files). No
finding discarded below the floor; none `UNVERIFIED-ACCEPTED`.

- FOLDED: `build` must run on every trigger incl. `workflow_dispatch` (else `deploy` is skipped);
  concurrency moved to the deploy job only; every raster ≤ 300 KB with no PNG fallback; system-font /
  zero-third-party rule; build-job checks rewritten as five structural, mechanical assertions
  (CSS `url()`, `srcset`, `content`, escaping `site/`, loaded third-party resources).
- FOLDED WITH A CORRECTED FIX: the peer proposed requiring every `ckir/clavity` link to match
  `/blob/main/`; that would fail legitimate links to Releases and Issues, so the rule allows the repo
  root, `/blob/main/`, `/tree/main/`, `/releases` and `/issues`.

Round 3 (agy peer; driver checked the folds against the spec text). No MATERIAL finding. FOLDED: canonical
URL is a `<link rel="canonical" href>`, not a `content` value; checks 1/2/5 now say to strip CSS `url()`
quotes and split `srcset` candidates; colour values sourced from `clavity.svg`. The peer's Literal
Implementer census ranked the unwritten section copy as the main remaining guess: left to the builder on
purpose, with the owner approving final copy (see Owner actions). The peer's claims about Actions
semantics were labelled VERIFIED without a stated method; they match documented behaviour and the round-2
fixes rest on the job-skipping rule, which is standard, so they are not relied on beyond that.
The hero chip-count decision was open at this point and has since been settled by the owner.

Build-approach consult (agy-first, 2026-10-22, `[VERDICT: ALIGNED]`): the peer also picked option 1 and
proposed adding an automated install-drift check (see Open points). Caveat recorded: the peer's thread
already contained this spec with option 1 chosen, so its pick is weak evidence of independent agreement.
Its repo citations were verified (`.github/dependabot.yml:50`, `lefthook.yml:10-17`,
`scripts/validate-members-manifest.ps1:11`) but only the dependabot one bears on the choice, and it
overstates: the npm entry covers `review-relay/extension/test` only, which shows Node is already in the
repo for tests, not that a site build is forbidden. Its suggestion of an embedded terminal recording in
the hero was not adopted (the owner chose the static strip, layout A, over the animated two-terminal one).

Round 4 (agy peer, narrowed to the post-round-3 edits; its reply had the content of all four seats but
closed with a `[VERDICT: NEGOTIATE …]` token from a different discipline instead of `PANEL VERDICT:`, so
it was recovered from the reply file and read in full before folding). FOLDED: check 7 could pass on an
empty set and fail on `&quot;`/curly quotes (now: exactly three ids, entity decode, quote folding); check 6
did not cover the clipboard payload (now `data-copy` must equal the displayed command); the `### WARNING`
quote boundary (body only, not the heading). RESIDUAL RISK recorded: paraphrase drift is unchecked.
NOT ADOPTED: the peer's `contains(toJson(github.event.commits.*.modified), 'site/')` deploy condition;
the push payload's `commits` array is capped and `modified` omits added/removed paths, so it would skip
deploys it should run (stated from GitHub's documented payload shape, not re-measured here). The peer's
claim that a red `main` blocks later PRs through `merge-gate.yml` is only half right: the gate waits for
checks on a PR's head commit, so it blocks PRs whose own `build` check fails (e.g. a README edit that
breaks parity), not unrelated PRs.
