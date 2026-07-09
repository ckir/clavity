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

_(all 4 agents landed: CLI/config, skills/MCP/TUI, per-model, quirks/user-findings.)_

### Quirks & real-world user findings (Agent D; routing-relevant distillation)

- `[doc]` **Headless `-p`/`--print` drops stdout in any non-TTY** (pipe/redirect/subprocess/CI): exit 0,
  empty output, round-trip actually ran (`text_drip.go` non-TTY flush bug, issue #76, open). PowerShell
  `Start-Process` w/ redirected streams **hangs**. → **Confirms clavity assumption #1** (why we drive
  the live pane). Workarounds: `script`/`unbuffer` PTY wrappers, or read the transcript file (below).
  `--output-format json` **does not exist**. Use `agy --version` (bare `agy version` can hang). Source: gh #76, #7.
- `[doc]` **Auth is fragile:** macOS keyring 1s-timeout → falls back to fresh OAuth (issue #85);
  Linux/WSL needs `org.freedesktop.secrets` D-Bus or re-login every session (#57). Confirms/qualifies
  assumption #9 (keyring auth). **[conflict]** on API-key env support: Agent A said `ANTIGRAVITY_API_KEY`/
  `GEMINI_API_KEY` accepted (issue #78); Agent D said OAuth-only, key support is an *open request* (#78).
  → mark **unconfirmed** (do not rely on API-key auth).
- `[doc]` **Quota/backend is a real routing risk:** opaque quota (`/usage` shows trend, not balance);
  **5-hour sprint + weekly baseline caps**; multi-day lockouts; HTTP 503 `MODEL_CAPACITY_EXHAUSTED`
  outages across all models (hours–weeks). Blind retry on 429 worsens cooldown. → **Confirms clavity's
  "backend-overload aborts turn" gotcha**; agy may be unavailable for extended periods. Source: discuss.ai.google.dev; gh.
- `[doc]` **Workspace write quirks:** rejects any path with a **dot-prefixed ancestor dir**
  (`"is hidden: ignore uri"`, issue #20) → falls back to `~/.gemini/antigravity-cli/scratch`
  (clavity-relevant: a cwd under a `.`-dir breaks agy writes). `--dangerously-skip-permissions` +
  `--sandbox` can write **outside** the workspace (security bug #36) — another Axis D widening path.
- `[doc]` **Strengths (user-reported):** strong contextual inference from CWD; transparent step-by-step
  reasoning; non-blocking async sub-agents (`/tasks`); fast Go startup; `/export` to the desktop app;
  **one user ran agy headless as a sub-agent inside Claude Code** (HN). Source: howtogeek; dev.to; HN.
- `[doc]` **Weaknesses (user-reported):** **"plausible code with subtle bugs — review before
  production"**; no manual `/compact` (auto only); no persistent processes across sessions; ~23–25k
  tokens of system prompt/tools burned on turn 1; max **512 tool calls** (Gemini, v1.0.7). Source: dev.to; gh; HN.
- `[doc]` **Headless-output workaround (useful):** the model response persists at
  `~/.gemini/antigravity-cli/brain/<conv-uuid>/.system_generated/logs/transcript.jsonl` (last
  `source=MODEL,status=DONE,type=PLANNER_RESPONSE`) — undocumented internal, version-fragile. Source: gh; antigravitylab.
- `[doc]` Telemetry is **opt-in by default** (collected unless disabled) — privacy note for sensitive repos. Source: agentpedia; discuss.ai.google.dev.

### Skills / MCP / sub-agents / TUI (Agent B; routing-relevant distillation)

- `[doc]` **Sub-agent orchestration (key reach):** `/agent [task] "prompt"` spawns an **async sub-agent**;
  `/agents` panel shows status (running/done/killed) + full per-agent transcript; async sub-agent
  **diffs post back to the main conversation when finished** (matches `[bus]` reactive-async claim).
  `/teamwork-preview` orchestrates a multi-agent team (**Worker / Reviewer / Critic / Auditor**) —
  observability still "basic" (issue #301). Source: dev.to/arindam_1729; datacamp; github issue #301.
- `[doc]` **Skills load by semantic match on the `SKILL.md` `description`** (not by slash name); dirs:
  `~/.gemini/skills/` (shared) vs `~/.gemini/antigravity-cli/skills/` (CLI-only) vs workspace
  `.agents/skills/`. **v1.0.8 release note: "Fixed dynamic reloading of custom skills … instantly
  discovered … upon conversation switch or `/add-dir`."** → **may update agy-assumptions #6** (which says
  skills are cached per-session and need a restart); re-verify. Source: codelabs; github releases (1.0.8).
- `[doc]` **TUI idle footer** confirmed form: `? for shortcuts        <Model> (<tier>)` — corroborates
  clavity's idle-marker assumption #3 (`? for shortcuts`). Status bar shows active model + token usage +
  running sub-agents; `/statusline` customizes it. Source: medium tutorial-series; dev.to.
- `[doc]` **MCP config gotchas:** remote servers use `"serverUrl"` (NOT `url`/`httpUrl`) — wrong key =
  **silent failure** surfacing only on tool call; workspace `.agents/mcp_config.json` may be silently
  ignored (issue #60 — only HOME-level reliably spawns servers); `env` var substitution is buggy.
  Source: medium configuring-mcp; inventivehq; github issue #60.
- `[doc]` `settings.json` keys: `colorScheme, editor, enableTerminalSandbox, model, notifications,
  permissions, runningLightSpeed, trustedWorkspaces`. Source: antigravitylab.net.
- `[doc]` COULD NOT CONFIRM: exact busy-footer text/spinner; skills cache-invalidation lifecycle;
  skills discovery priority order; extra SKILL.md frontmatter fields.

### CLI & config surface (Agent A; representative cites — full set in transcript)

- `[doc]` Binary is **`agy`**, written in **Go**; installed to `~/.local/bin/agy` (mac/Linux) /
  `%LOCALAPPDATA%\Antigravity\` (Win). Source: inventivehq.com; agentpedia.codes.
- `[doc]` **Launch flags:** `-p`/`--print`/`--prompt` (non-interactive single prompt), `-i`
  (`--prompt-interactive`), `-c`/`--continue`, `--conversation <id>`, `--add-dir` (repeatable — add
  dirs to workspace), `--model`, `--dangerously-skip-permissions`, `--sandbox`, `--print-timeout`
  (default `5m0s`), `--log-file`, `--version`, `--help`. Source: codelabs; hermes-agent docs; dev.to.
- `[doc]` **Subcommands:** `changelog`, `help`, `install` (`--dir/--skip-aliases/--skip-path`),
  `models`, `plugin`/`plugins` (list/import/install/uninstall/enable/disable/validate/link),
  `update`. `agy plugin import gemini` migrates Gemini-CLI extensions. Source: CHANGELOG; hermes-agent.
- `[doc]` **Permission modes:** `request-review` (default), `proceed-in-sandbox`, `always-proceed`,
  `strict` (**read-only**). Source: medium.com/google-cloud tutorial-series.
- `[doc]` **Slash commands** (capability/control-relevant): `/model`, `/mcp`, `/skills`, `/agents`,
  **`/agent [task] [prompt]` — dispatch an async sub-agent**, `/tasks` (inspect/kill background tasks),
  `/context`, `/usage`, `/permissions`, `/fast` (skip planning), `/grill-me` (asks clarifying Qs
  first), `/goal`, `/schedule`, `/rewind`, `/fork`, `/export` (push to Antigravity 2.0 desktop), `!`
  (shell mode). Source: codelabs; antigravitylab.net; datacamp; dev.to.
- `[doc]` **Config layout** (confirms `[local]`): `~/.gemini/` root; `~/.gemini/antigravity-cli/`
  (`settings.json`, `keybindings.json`, `plugins/`, `skills/` = global CLI-only skills, `cache/`,
  `log/`); `~/.gemini/config/mcp_config.json` (global MCP); `~/.gemini/skills/` (**shared** across
  Antigravity tools); workspace `.agents/` (`mcp_config.json`, `skills/`, `hooks.json`, `hooks/`).
  Context files: `GEMINI.md` > `AGENTS.md`; `.antigravity.md` also seen. Source: medium configuring-mcp;
  migrating-to-antigravity-cli; agentpedia user-rules.
- `[doc]` **agy has its OWN hooks system** (`PreToolUse`/`PostToolUse`/`PreInvocation`/`PostInvocation`/
  `Stop`; workspace `.agents/hooks.json` + global `~/.gemini/config/hooks.json`). Source: danicat.dev.
- `[doc]` **`allowNonWorkspaceAccess`** settings.json key (+ `trustedWorkspaces[]`, `--add-dir`) — **the
  knob that widens file access beyond the workspace.** *Resolves the Axis D `[conflict]`:* workspace-
  restricted by default (matches `[corpus]`/#8), but native tools can write wider when this is enabled
  / dirs are added / mode is `always-proceed`. Source: hermes-agent docs.
- `[doc]` **Auth:** browser Google OAuth stored in OS keyring; `ANTIGRAVITY_API_KEY` / `GEMINI_API_KEY`
  env; `/logout`. Source: hermes-agent; issue #78; agentpedia.
- `[doc]` **Default model at launch = Gemini 3.5 Flash (High)** (this agy is user-set to Gemini 3.1 Pro
  High). Source: datacamp.com/tutorial/antigravity-cli.
- `[doc]` COULD NOT CONFIRM: discrete `agy auth`/`agy config`/`agy tasks` subcommands (single low-conf
  source); `.antigravity.md` vs `GEMINI.md` precedence (sources disagree); some hook event names.

### Per-model capability sweep (routing-relevant distillation; full cites in Agent C transcript)

- `[doc]` **Gemini 3.5 Flash** (L/M/H thinking; default medium) — high-efficiency multimodal, "optimized
  for coding proficiency and parallel agentic execution loops" + sub-agent deployment; 1M ctx, 65k out;
  cheap ($1.50/$9 per 1M). **Route to:** fast/cheap agentic loops, parallel fan-out, simpler coding.
  Source: ai.google.dev/gemini-api/docs/interactions/whats-new-gemini-3.5; openrouter.ai/google/gemini-3.5-flash
- `[doc]` **Gemini 3.1 Pro** (native L/M/H, default **high**; OpenAI-compat exposes **Low/High** — matches
  this agy's menu) — top-tier reasoning (ARC-AGI-2 77.1%; SWE-bench ~80.6% *secondary*), 1M ctx, concise
  output, **high latency to first token (~23s)**, "somewhat expensive" ($2/$12, more >200k). **Route to:**
  hardest reasoning/code/agentic, deep review. **This is agy's current/default model.**
  Source: ai.google.dev/gemini-api/docs/gemini-3; artificialanalysis.ai/models/gemini-3-1-pro-preview
- `[doc]` **Claude Sonnet 4.6 (Thinking)** — "best combination of speed and intelligence," adaptive
  thinking (low/med/high/max), 1M ctx, 64k out, $3/$15; SWE-bench ~79.6% *secondary*. **Route to:** fast,
  strong general coding/review. Source: platform.claude.com/docs/en/about-claude/models/overview
- `[doc]` **Claude Opus 4.6 (Thinking)** — legacy flagship tier, adaptive thinking, 1M ctx, **128k out**,
  moderate latency, $5/$25 (priciest here). **Route to:** deepest reasoning/design review among the
  Claude options. Source: platform.claude.com/docs/en/about-claude/models/overview
- `[doc]` **GPT-OSS 120B (Medium)** — open-weight MoE (~120B total / 5.1B active), **text-only**, 131k
  ctx, **very fast (~354 t/s)**, very cheap; strong math (AIME'25 93.4%) but **weaker coding (#97) &
  agentic (#106)** ranks; no safety RLHF; **knowledge cutoff Jun 2024**. **Route to:** cheap/fast
  math/reasoning second opinion; **avoid** for top-tier coding/agentic. Source:
  developers.openai.com/api/docs/models/gpt-oss-120b; designforonline.com/ai-models/openai-gpt-oss-120b
- `[doc]` Caveats (Agent C "could not confirm"): several 3.1 Pro/Sonnet benchmark numbers are from
  secondary aggregators, not primary; GPT-OSS pricing sources conflict. Treat benchmarks as indicative.

## Pass 3 — bus self-report (`[bus]`, cross-check)

_The dedicated self-report `clavity ask` **timed out** (agy busy; idle-gate timeout, 200s). These
`[bus]` facts are from agy's earlier divergent spec-review round-trip (same session). Re-ask when agy
is idle to enrich._

- `[bus]` Self-describes as a **dynamic platform**: capability = baseline + native tools + currently-
  loaded skills/MCP (not a static model).
- `[bus]` Strengths: strict multi-step **protocol adherence**; precise **non-contiguous native edits**
  (`multi_replace_file_content`); **native reactive async task management** — woken when a background
  shell task finishes, no polling (efficient for long orchestrations).
- `[bus]` Weaknesses: **worktree-blind until it actively probes** (`list_dir`/`grep_search`); open-ended
  discovery in large trees **burns context fast**.
- `[bus]` Operational: the **agentmemory MCP** is a core capability (save/recall durable cross-agent
  context) to route to.
- `[bus]` **Axis D claim:** native tools (`write_to_file`/`replace_file_content`/`multi_replace_file_content`)
  write **anywhere OS perms allow**, not only the workspace. **Conflicts with `[corpus]`/#8 (workspace-
  only).** → **RESOLVED by `[doc]`:** the `allowNonWorkspaceAccess` setting / `--add-dir` /
  `trustedWorkspaces` gate this — restricted by default, wider when enabled. Both are right, config-dependent.
