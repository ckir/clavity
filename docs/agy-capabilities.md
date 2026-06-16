# agy capability profile — what agy can do, and how to route to it

> **Verified against: agy 1.0.8** · active model here: **Gemini 3.1 Pro (High)** (launch default is
> Gemini 3.5 Flash (High) `[doc]`). Provenance-tagged: `[corpus]` user's validated knowledge ·
> `[doc]` web (docs + user findings) · `[local]` this install · `[bus]` agy self-report · `[verified]`
> ≥2 sources agree · `[conflict]` sources disagree (`[local]`/`[corpus]` win for our version).
>
> Companion to the **empirical** [`agy-assumptions.md`](agy-assumptions.md) (what's verified here + how
> to re-verify) and the **how-to-ask** [`agy-remote-control-protocol.md`](agy-remote-control-protocol.md).
> The auto-consult policy (when to ask agy before showing the user) is the `agy-first-brainstorm.sh` hook.
>
> **agy is a dynamic, multi-model platform, not a static model:** effective capability =
> *active model + agy's orchestration + native tools + currently-loaded skills & MCP servers*. The
> profile below is the baseline; the **live config is the truth** — check `/model`, `/mcp`, `/skills`.

## A. Strengths (route toward)

- **Critical review & verification** `[verified: corpus + doc/user]` — agy **verifies far better than it
  discovers**. Calibration: on a real review its 🔴 "must-fix" tier ran ~2-real / 1-misscoped, one real
  find with a wrong first rationale `[corpus]`. → seed the specific invariants to confirm/refute.
- **Generative / divergent design input** `[corpus]` — its highest-value contribution; always pair the
  critique with a "what's missing / simpler / stronger?" ask (the two-mode rule).
- **Independent second-model perspective** `[local + doc]` — agy can run a *different provider's* model
  (Gemini / Claude / GPT-OSS), so it's a genuine outside view on Claude-authored work (Axis C/F).
- **Strict multi-step protocol adherence** `[bus]` (e.g. the claudavity responder) — reliable at
  following an exact, ordered procedure.
- **Precise non-contiguous native edits** `[bus]` (`multi_replace_file_content`) — good for surgical
  multi-site edits when delegated implementation (verify the diff).
- **Async sub-agent orchestration** `[verified: bus + doc]` — `/agent` spawns non-blocking sub-agents,
  `/agents` monitors them, `/teamwork-preview` runs a Worker/Reviewer/Critic/Auditor team; diffs post
  back to the main thread; reactive (no polling). Strong for long, parallel orchestrations.
- **Reactive async shell execution** `[verified: bus + doc]` — agy can background a slow shell command
  (full test suite, build, long pipeline), **sleep, and be reactively woken when it finishes — no
  polling, no context/token burn** (`/tasks` monitors/cancels). A real routing differentiator: hand agy
  slow *local* pipelines you'd otherwise babysit, not just LLM work. Sync vs async is controlled by the
  `RUN_COMMAND` tool's **`WaitMsBeforeAsync`** param (ms; `[local]` — observed `"5000"`): a high value
  runs a *quick* command synchronously; a low value backgrounds it. Long background tasks can be bounded
  with a wake/`schedule` timer (`TimerCondition` param, `[local]`; value `"never"` observed, agy also
  cites `"any"`) so a silently-dead task doesn't hang forever.
- **Concurrent tool execution in a turn** `[verified: bus + doc]` — agy can run multiple tool calls in
  parallel (e.g. read 5 files / search 3 terms at once), not strictly one-at-a-time. Front-loading all
  targets in the request lets it parallelize — assuming sequential throttles its throughput. (Caveat:
  do **not** parallelize *edits to the same file* — see Axis B / the protocol's "what Claude gets wrong".)
- **Strong contextual inference from CWD** `[doc/user]` — infers the codebase/tooling from the working
  dir; fast Go startup, low memory `[doc/user]`.

## B. Weaknesses & failure modes (route away / guardrail)

- **Open-ended discovery → over-escalation & hallucination** `[corpus, calibrated]` — don't ask it to
  "find bugs"; seed invariants and grant "no must-fix is valid" permission.
- **Cross-graph cascade & concurrency interleavings** `[corpus]` — reasons locally & sequentially;
  supply whole-graph context or keep this work on Claude.
- **Worktree/gitignore-blind until it probes** `[verified: corpus + bus]` (`list_dir`/`grep_search`);
  reads files relative to its own cwd even given absolute paths `[corpus]` → **always verify agy's
  file/line claims against disk**; front-load context (it has a separate context window).
- **Plausible code with subtle bugs** `[doc/user]` — "review before production"; never merge agy code
  unreviewed.
- **Context burn** `[doc]` — open discovery is expensive; ~23–25k tokens of system prompt/tools on turn
  1; hard cap **512 tool calls** per turn (Gemini, v1.0.7).
- **Quota / backend availability is a real routing risk** `[verified: corpus gotcha + doc]` — opaque
  quota (`/usage` = trend, not balance), **5-hour sprint + weekly caps**, multi-day lockouts, and
  HTTP 503 `MODEL_CAPACITY_EXHAUSTED` outages (hours–weeks) that **abort a turn with no bus reply**.
  Blind 429 retry worsens cooldown. → agy may be unavailable; have a Claude fallback; on a silent
  timeout, `clavity capture` to check, wait, and **re-`ask`** (fresh req-id).
- **Headless `-p`/`--print` drops stdout in non-TTY** `[verified: corpus #1 + doc #76]` (PowerShell
  `Start-Process` w/ redirected streams hangs). → this is why clavity drives the **live pane**, not
  `agy -p`. (Output can be recovered from the transcript file — Axis D.)
- **Dot-prefixed ancestor path rejected** `[doc #20]` — a workspace under a `.`-dir logs "is hidden:
  ignore uri" and writes fall back to `…/scratch`. Keep agy's cwd off hidden-dir paths.

## C. Reasoning profile & model selection

agy is a **multi-model router across providers**; the active model + reasoning tier is the dominant
capability dial. Models available here `[local]` (the `/model` menu) and when to pick each `[doc]`:

| Model (tier) | Pick it for | Notes |
|---|---|---|
| **Gemini 3.1 Pro (High)** — *current/default here* | hardest reasoning / code / agentic; deep review | top-tier (ARC-AGI-2 77.1%); concise; **~23s to first token** (high latency); pricier |
| Gemini 3.1 Pro (Low) | the above, lower latency/cost | OpenAI-compat exposes Low/High (matches this menu) |
| Gemini 3.5 Flash (High/Med/Low) | fast/cheap agentic loops, parallel fan-out, simpler coding | "optimized for parallel agentic execution"; 1M ctx; cheap |
| Claude Sonnet 4.6 (Thinking) | fast, strong general coding/review | "best speed+intelligence balance"; 1M ctx |
| Claude Opus 4.6 (Thinking) | deepest reasoning/design review (of the Claude options) | priciest; 128k output; moderate latency |
| GPT-OSS 120B (Medium) | cheap/fast math/reasoning second opinion | **avoid for top-tier coding (#97) / agentic (#106)**; text-only; cutoff Jun 2024 |

Benchmarks above are indicative (several `[doc]` from secondary aggregators). Separate context window
from Claude's; sequential/local reasoning bias.

## D. Operational reach (what it can act on)

- **Shell:** PowerShell (pwsh) on Windows `[corpus #5]`; `!` toggles a shell mode in the TUI `[doc]`.
- **File writes** `[verified — resolves the old conflict]`: two levels. *Model-level*, agy's native
  tools (`write_to_file`, `replace_file_content`, `multi_replace_file_content`) are **path-agnostic**
  (absolute path + OS permissions — "I don't experience a sandbox", `[bus]`). *Wrapper-level*, the
  Antigravity CLI **gates** it: **workspace-only by default** (outside paths rejected → shell/scratch
  fallback, `[corpus]`/#8), **widened** by `allowNonWorkspaceAccess`, `--add-dir`, `trustedWorkspaces[]`,
  or (insecurely) `--sandbox --dangerously-skip-permissions` `[doc #36]`. Net: **default = workspace-only;
  config-dependent beyond that** — both the `[corpus]` and `[bus]` views reconcile at the wrapper.
- **Background shell** `[verified: bus + doc]`: can run slow commands async and be reactively woken on
  completion (`/tasks`) — see Axis A "Reactive async shell execution".
- **MCP tools** `[local]`: **agentmemory** (durable cross-agent save/recall — the clavity bus), **serena**
  (LSP/symbol tools), **agy-mcp-bridge** (`delegate_to_antigravity`). Remote MCP uses `"serverUrl"`
  (wrong key = silent failure) `[doc]`.
- **Sub-agents** `[doc]`: `/agent` (async), `/teamwork-preview` (multi-role team) — agy can fan out work itself.
- **Own hooks system** `[doc]`: `PreToolUse`/`PostToolUse`/`PreInvocation`/`PostInvocation`/`Stop`.
- **Headless** `[verified: corpus #1 + doc #76]`: limited — `-p` stdout is unreliable (Axis B); response recoverable from
  `~/.gemini/antigravity-cli/brain/<conv>/.system_generated/logs/transcript.jsonl` `[doc, version-fragile]`.
- **Safety checkpoint**: the responder makes a non-intrusive `git stash` snapshot before editing `[corpus]`.

## E. Control surface that changes capability

- **Model** `[verified: local + doc]` — `--model` / `/model` (persists); the biggest lever (Axis C).
- **Loaded skills & MCP** `[verified: local + doc]` — the *dynamic* toolset: skills in `~/.gemini/skills/` (shared),
  `~/.gemini/antigravity-cli/skills/` (CLI-only), workspace `.agents/skills/`; servers in
  `~/.gemini/config/mcp_config.json`. Inspect live with `/skills` and `/mcp`. v1.0.8 reloads skills on
  conversation switch / `--add-dir` `[doc]`.
- **Permission mode** `[doc]`: `request-review` (default) · `proceed-in-sandbox` · `always-proceed` ·
  `strict` (read-only); `--dangerously-skip-permissions` for full autonomy; fine-grained
  `permissions.allow`/`deny` in `settings.json`.
- **Auth** `[verified: corpus #9 + doc]`: Google OAuth via OS keyring (fragile: macOS 1s timeout,
  Linux/WSL needs D-Bus). **`[conflict]` API-key env (`ANTIGRAVITY_API_KEY`/`GEMINI_API_KEY`):** sources
  disagree (issue #78 read as "supported" vs "open request") — **treat as unconfirmed; rely on OAuth.**

## F. Routing: whether agy, and on which model

1. **agy vs a Claude subagent.** Use **agy** for an *independent second-model* view: divergent review,
   generative design partner, a different provider's opinion on Claude's work, or non-blocking async
   orchestration. Use a **Claude subagent** for mechanical sweeps / well-specified implementation
   (Claude's own tiering rules). **Redundancy guard:** don't route to *agy-on-a-weak-model* what Claude
   should just keep — agy's value is the *different* perspective + parallel async, not raw horsepower.
2. **Which model to set agy to** (Axis C): deep review/reasoning → **Opus 4.6 Thinking** or **Gemini
   3.1 Pro High**; bulk/cheap/parallel → **Flash Low/Med**; cost-sensitive math/second-opinion →
   **GPT-OSS 120B** (not top coding/agentic); fast strong general → **Sonnet 4.6**.
3. **Availability check.** Before a time-sensitive delegation, account for quota/backend risk (Axis B):
   agy can be rate-limited or 503-locked for hours–days. Keep a Claude fallback for critical-path work.

## G. Version & drift

- **Verified against agy 1.0.8** (`agy --version`), active model Gemini 3.1 Pro (High), `[local]` 2026-06-16.
- Recent relevant changelog: v1.0.8 **skills dynamic reload** — **re-verified `[local]` 2026-06-16:
  this is autocomplete discovery on conversation-switch / `--add-dir`, NOT re-reading edited skill
  content on a plain doorbell, so empirical assumption #6 (skills cached per session; edits need a
  restart) STILL HOLDS** for clavity's usage (test: edited `[ping]` reply to a marker, pinged the
  running session, got plain `READY`). v1.0.7: 512 tool-call cap, configurable MCP launch timeout.
  v1.0.6: sandbox-flag propagation in headless mode. `[doc]`/`[local]`
- Changelog source: `github.com/google-antigravity/antigravity-cli` (CHANGELOG / releases).
- Open `[conflict]`/unconfirmed to watch: API-key auth (#78); whether the headless `-p` stdout bug (#76)
  is fixed post-1.0.8.

## Refresh after an `agy update`

1. `agy changelog` (or the GitHub CHANGELOG) → diff against the pinned **1.0.8**; note added/removed
   flags, subcommands, models, permission modes.
2. Re-run local introspection: `agy --version`, the `/model` menu, `/mcp`, `/skills`, and the
   `~/.gemini/` config layout (the *dynamic* toolset).
3. Targeted web re-check of `antigravity.google/docs` + the changelog + recent issues for capability
   changes (esp. headless, auth, quota, model lineup).
4. Update changed claims, re-tag provenance, bump the `Verified against` header + the active model.
5. If a capability change alters **routing** (Axis F) or contradicts an empirical assumption, update
   here **and** cross-link/fix [`agy-assumptions.md`](agy-assumptions.md).
6. **Re-run the acceptance suite** [`agy-test-suite.md`](agy-test-suite.md) — the four mode-template
   tests + the skill-cache (#6) and write-scope (Axis D) re-verifications — and log the result there.

> Evidence trail with full citations: [`agy-capabilities-research.md`](agy-capabilities-research.md).
