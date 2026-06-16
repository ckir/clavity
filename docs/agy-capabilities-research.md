# agy capability research — raw findings (evidence log)

Raw, source-tagged findings that `agy-capabilities.md` distills. Each fact carries a tag; `[doc]`
facts cite a URL. Legend: `[corpus]` user's validated knowledge · `[doc]` web · `[local]` installed
agy (config/behavior) · `[bus]` agy self-report. Conflicts noted inline. Verified against **agy 1.0.8**.

## Pass 0 — corpus (`[corpus]`)

Sources: `~/.claude/skills/token-discipline-installer/templates/AGENTS-antigravity-protocol.md`;
MarketMonitor memories `feedback_agy_review_wording.md`, `project_antigravity_protocol.md`,
`feedback_agy_consult_before_user.md`; `agy-first-brainstorm.sh` hook; clavity's `agy-assumptions.md`,
`agy-remote-control-protocol.md`, responder `SKILL.md`.

- `[corpus]` agy **verifies far better than it discovers** — seed specific invariants to confirm/refute;
  open-ended "find bugs" makes it over-escalate and hallucinate. (feedback_agy_review_wording)
- `[corpus]` Calibration: on a real review (MarketMonitor Safeguards Phase 3) its 🔴 "must-fix" tier ran
  ~2-real / 1-misscoped, and one real find had a wrong first rationale — fixable in prompt wording.
- `[corpus]` **Reasons locally & sequentially** — do not trust it solo on cross-graph cascade or
  concurrency interleavings; supply whole-graph context or handle yourself. (feedback_agy_review_wording)
- `[corpus]` **Worktree/gitignore-blind** — can't see gitignored spec/plan; front-load context + an
  ignorance boundary (trusted black-box deps) + a calibration table of prior dispositions.
- `[corpus]` Highest value is **generative**, not just validation — every handoff asks BOTH a critical
  review AND a creative "what's missing / simpler / stronger" question. **Never review-only-by-content.**
  (AGENTS-antigravity-protocol; project_antigravity_protocol)
- `[corpus]` REVIEW-ONLY **banner** (user-mandated 2026-06-16) = no file edits/commits; agy honors it
  ("Changes Made: None"). Distinct from the two-mode content rule above. (feedback_agy_review_wording)
- `[corpus]` Evidence mandate: require `file:line` + a trace before asserting; no trace → downgrade.
  Always verify agy's file/line claims against disk (wrong-folder reads observed).
- `[corpus]` Stop hyperbolic priming ("red-team hard/destroy this") — induces false 🔴s; use neutral,
  specific verbs + grant explicit "no must-fix is a valid result" permission.
- `[corpus]` **agy never edits code in the review pattern** — its only write target is
  `ANTIGRAVITY-TO-CLAUDE.md` (review/design mode). Implementation mode (edits & merges) is an explicit,
  scoped relaxation. (AGENTS-antigravity-protocol; project_antigravity_protocol)
- `[corpus]` **Transport options:** MarketMonitor uses **bridge-first** (`delegate_to_antigravity`
  primary → headless sub-agent in an isolated worktree, merges committed output; manual paste failover).
  clavity uses the **bus** (`clavity ask`). The bridge derives success from a **committed git diff** —
  a review must *write* findings to `ANTIGRAVITY-TO-CLAUDE.md` and commit, else it reports "no changes"
  (observed this session). (project_antigravity_protocol)
- `[corpus]` Decision protocol: consult agy on design forks **before** presenting to the user, then show
  the user BOTH agy's and Claude's recommendation; user decides; never delegate final approval to agy.
  (feedback_agy_consult_before_user; mirrors the #3 hook)
- `[corpus]` Empirical (agy-assumptions #8): **writes only within its workspace (cwd)** — outside paths
  rejected (`artifacts must be in …/brain/…`) → shell fallback. **[conflict vs [bus] Axis D — to resolve]**
- `[corpus]` Shell tool = **PowerShell (pwsh)** (agy-assumptions #5). Reads files relative to its own cwd
  even given absolute paths (#…) — verify file claims against disk.
- `[corpus]` Reads its responder skill **once per session and caches it** (agy-assumptions #6); MCP servers
  load a few seconds after launch (readiness ping needed).

## Pass 2 — local introspection (`[local]`; config + observed behavior only — agy is closed-source)

- `[local]` `agy --version` → **1.0.8**.
- `[local]` Loaded MCP servers (`~/.gemini/config/mcp_config.json`): **agentmemory** (`cmd /c npx
  @agentmemory/agentmemory mcp`), **agy-mcp-bridge** (`uv run … claudavity/server.py` — the
  `delegate_to_antigravity` bridge), **serena** (`serena.exe start-mcp-server`). Confirmed live in the
  `/mcp` menu earlier (agentmemory, agy-mcp-bridge, serena).
- `[local]` `~/.gemini/antigravity-cli/` layout: `bin/ brain/ builtin/ cache/ conversations/ implicit/
  knowledge/ log/ mcp/ plugins/ scratch/ skills/ updater/`; files: `antigravity-oauth-token`, `cli.log`,
  `history.jsonl`, `keybindings.json`, `settings.json`, `installation_id`, `last_check.timestamp`,
  `import_manifest.json`.
- `[local]` Skills: a **large library** under `~/.gemini/antigravity-cli/skills/` (global, CLI-only —
  many entries: `00-andruia-consultant`, `007`, `2slides-ppt-generator`, `3d-web-experience`,
  `ab-test-setup`, `accessibility-*`, … [full enumeration in synthesis if routing-relevant]), plus a
  shared `~/.gemini/skills/SKILL.md` (+ `references/`). Matches the doc'd split: global =
  `~/.gemini/antigravity-cli/skills`, shared = `~/.gemini/skills`.
- `[local]` Auth: `antigravity-oauth-token` present (consumer OAuth via keyring, agy-assumptions #9).
- `[local]` `keybindings.json` + `settings.json` exist (config surface for `/keybindings`, `/config`).
- `[local]` Model list (from the `/model` menu, user-reported): Gemini 3.5 Flash (Low/Medium/High),
  Gemini 3.1 Pro (Low / **High — current/default**), Claude Sonnet 4.6 (Thinking), Claude Opus 4.6
  (Thinking), GPT-OSS 120B (Medium).

## Pass 1 — web (`[doc]`)

_(pending — 4 parallel research agents in flight: CLI/config, skills/MCP/TUI, per-model sweep, quirks/user-findings)_

## Pass 3 — bus self-report (`[bus]`, cross-check)

_(pending — `clavity ask` self-report round-trip in flight)_
