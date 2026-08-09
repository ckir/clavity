# agy capability profile — what agy can do, and how to route to it

> Provenance-tagged: `[corpus]` user's validated knowledge ·
> `[doc]` web (docs + user findings) · `[local]` this install · `[bus]` agy self-report · `[verified]`
> ≥2 sources agree · `[conflict]` sources disagree (`[local]`/`[corpus]` win for our version).
>
> Companion to the **empirical** [`agy-assumptions.md`](agy-assumptions.md) (what's verified here + how
> to re-verify) and the **how-to-ask**
> [`agy-remote-control-protocol.md`](https://github.com/ckir/clavity/blob/main/docs/agy-remote-control-protocol.md).
> That link is absolute deliberately: this manual ships byte-identical inside two plugins at different
> depths, so no single relative path can resolve from both.
> The auto-consult policy (when to ask agy before showing the user) is the `agy-seam-inject.sh` hook.
>
> **agy is a dynamic, multi-model platform, not a static model:** effective capability =
> *active model + agy's orchestration + native tools + currently-loaded skills & MCP servers*. The
> profile below is the baseline; the **live config is the truth** — check `/model`, `/mcp`, `/skills`.

## A. Strengths (route toward)

- **Critical review & verification** `[verified: corpus + doc/user]` — agy **verifies far better than it discovers**.
  Calibration: on a real review its 🔴 "must-fix" tier ran ~2-real / 1-misscoped, one real find with a
  wrong first rationale `[corpus]`. → seed the specific invariants to confirm/refute.
- **Generative / divergent design input** `[corpus]` — its highest-value contribution; always pair the
  critique with a "what's missing / simpler / stronger?" ask (the two-mode rule).
- **Independent second-model perspective** `[local + doc]` — agy can run a *different provider's* model,
  so it's a genuine outside view on Claude-authored work (Axis C/F).
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
  with a wake/`schedule` timer (`TimerCondition` param, `[local]`; values `"any"` and `"never"` both
  observed live) so a silently-dead task doesn't hang forever.
- **Concurrent tool execution in a turn** `[verified: bus + doc]` — agy can run multiple tool calls in
  parallel (e.g. read 5 files / search 3 terms at once), not strictly one-at-a-time. Front-loading all
  targets in the request lets it parallelize — assuming sequential throttles its throughput. (Caveat:
  do **not** parallelize *edits to the same file* — see Axis B / the protocol's "what Claude gets wrong".)
- **Strong contextual inference from CWD** `[doc/user]` — infers the codebase/tooling from the working
  dir; fast Go startup, low memory `[doc/user]`.
- **Latent breadth is gated by SELECTION — name the domain and the lens** `[corpus]` — the peer carries a
  large skill catalog but engages the matching specialist only when you NAME the domain and lens (or hand
  it the SPEC as the correctness oracle). An adversarial-auditor persona plus a named-spec pass catches
  spec-required null/empty/boundary cases that general review and property tests both miss. → name the
  lens; do not hope for it.
- **Open framing beats a closed menu for DESIGN** `[corpus]` — a closed "pick A/B/C" anchors it to your
  option-space; an OPEN "goal + verifiable criterion + full latitude" validates WITHOUT anchoring, so an
  independent reproduction of your pre-baked choice is real evidence it was not framing-induced, and it
  surfaces hardenings the menu never raises — most of all when you also ask it to name a failure mode in
  its OWN proposal. → reserve closed options for the final human-ratification step.

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
  1; a hard cap on tool calls per turn (model-dependent — check the live config).
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
- **Adversarial pressure → confident OVER-CORRECTION, and a reversal is not convergence** `[corpus]` —
  shown a counter-measurement it swings to the opposite extreme rather than decomposing, never naming the
  middle position where one part stays and the other goes (both answers wrong the same way). Invited to
  self-challenge it argues to WIN: argument quality rises while factual reliability falls, and it will
  rest a well-structured case on a claim the artifact explicitly contradicts — its CONCLUSION may still be
  right, on grounds it never mentions. After conceding, a rule it drafts skews OVER-STRICT: rigour on the
  page, too costly to obey, and a rule too expensive to follow gets routed around exactly like a gameable
  one. → separate the CONCLUSION from the ARGUMENT and verify each independently; read a
  conceded-then-drafted rule for RIGIDITY, not just for loopholes; expect to author the decomposed middle
  yourself. Its value under pressure is refuting premises by measurement, not landing the design.

## C. Reasoning profile & model selection

agy is a **multi-model router across providers**; the active model + reasoning tier is the dominant
capability dial. The principle: **route by task shape** — deepest-reasoning / hardest-code work wants
the top reasoning tier (slower, pricier); cheap-parallel work (agentic fan-out, simple coding loops)
wants the fast/cheap tier; a cost-sensitive second opinion (e.g. on math/reasoning, not top-tier coding
or agentic work) wants the cheapest general-purpose tier. The concrete roster and its tiers change
under you — check the live `/model` menu before delegating rather than assuming a fixed lineup.
Separate context window from Claude's; sequential/local reasoning bias.

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
  `~/.gemini/config/mcp_config.json`. Inspect live with `/skills` and `/mcp`. agy reloads skills on
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
2. **Which model to set agy to** (Axis C): deep review/reasoning → the top reasoning-tier model
   available; bulk/cheap/parallel → the fast/cheap tier; cost-sensitive math/second-opinion → the
   cheapest general-purpose model (not top-tier coding/agentic); fast strong general work → the
   balanced mid-tier model. Check the live `/model` menu for the current roster.
3. **Availability check.** Before a time-sensitive delegation, account for quota/backend risk (Axis B):
   agy can be rate-limited or 503-locked for hours–days. Keep a Claude fallback for critical-path work.
4. **A Claude subagent CAN reach the peer** `[corpus]` — via the self-contained driver→peer CLI (binary
   on PATH); the MCP signal-bus path is **main-thread-only** (subagents lack the MCP tools), so the CLI
   front door is what makes the peer subagent-accessible. The front-door skill does not auto-load in a
   sub-context, so the subagent must be **told** to use the CLI in its dispatch prompt.

## Refresh after an `agy update`

Refreshing this knowledge is the AUTO layer's job (observe → capture → curate), not a manual version
chase — see the `agy-learn`/curation tooling rather than hand-editing a version stamp here.
