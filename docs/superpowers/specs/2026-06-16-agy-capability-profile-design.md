# Design — agy capability profile (for delegation routing), and wiring it into how we ask

> Status: approved design (brainstormed 2026-06-16). Next step: implementation plan (writing-plans).
> Supersedes the earlier `2026-06-16-driving-agy-skill-design.md`, which conflated three distinct
> concerns into one skill.

## 1. Framing — agy is, to Claude, another subagent model

Claude already drives subagent models (Haiku / Sonnet / Opus). Driving agy well decomposes into the
**same three layers** Claude uses for any subagent — and exactly one of them is currently missing:

| Layer | For a Claude subagent | For agy | Status |
|---|---|---|---|
| **WHAT it can do** → route by capability | Claude *already knows* Haiku≠Sonnet≠Opus, so it doesn't hand Haiku an architecture task | Claude does **not** know agy's capabilities → must **discover** them | **MISSING — this spec builds it (#1)** |
| **HOW to ask it** → dispatch in its language | Claude knows the dispatch-prompt discipline | Claude knows *what* it wants, but agy won't understand unless it's phrased in **agy's language** (the "wording protocol"). Transport already exists (clavity `ask`/bus); the wording discipline already exists | **EXISTS — extend to cite #1 (#2)** |
| **WHEN to ask automatically** → a gate | n/a | The user's policy: consult agy automatically **before presenting things to the user** (e.g. divergent review before showing design options) | **EXISTS — reference only (#3)** |

**This spec's deliverable is #1**: agy's **capability profile** — the equivalent of the capability
knowledge Claude relies on to route work to the right model. #2 and #3 already exist; the spec
defines a small, surgical extension to #2 and only *references* #3.

## 2. The three artifacts (What / How / When)

- **#1 — Capability profile (NEW): `docs/agy-capabilities.md`.** A model-card-style profile of agy:
  what it's reliably good at, what it's weak at, its limits and operational reach — the basis for
  *deciding what to delegate to agy at all*. A **doc** (reference knowledge), sibling to
  `agy-assumptions.md`; provenance-tagged, version-pinned, refreshable. Not a skill — a skill is for
  "how to act" (that's #2).
- **#2 — Wording protocol (EXTEND existing): `docs/agy-remote-control-protocol.md` → "Driving
  conventions".** clavity's local "how to ask agy in its language." Extend it to (a) **link to #1**
  and (b) add *capability-aware* asking (route per the profile). The wording **discipline** lives
  here, not in #1. **Local-first, then promote:** validate the additions locally in clavity, then
  promote them up to the global AGENTS.md "Working with Antigravity" (the shared upstream) — §5.
  **Status:** local validation done; **global promotion NOT done** — an attempt to promote into the
  `corelib` repo was reverted (wrong target: corelib is an unrelated project). The conventions live in
  clavity only; pick a correct shared destination before promoting.
- **#3 — When-gate (UNCHANGED): `~/.claude/hooks/agy-first-brainstorm.sh`.** The user's policy for
  when to consult agy automatically before presenting to the user. Referenced from #2; **not edited**.

Data flow: **research → #1 capability profile → cited by #2 (how to ask) → fired per #3 (when).**

## 3. #1 — The capability profile (`docs/agy-capabilities.md`)

Framed as a **routing tool**, not a CLI manual. **agy is a *dynamic, multi-model platform*, not a
static model** (its own framing, [bus]): effective capability = *the active model + baseline
orchestration + native tools + currently-loaded skills & MCP servers*. So the profile must capture
**how to check what's active/loaded now** (selected model, skills, MCP — not just a frozen list) and
treat that configuration as part of the capability surface. Sections are the axes that decide *what to
hand agy — and on which model*:

- **A. Strengths (route toward).** Classes of work agy does reliably — e.g. critical review &
  verification; generative/divergent design input; well-scoped code generation; `[bus]` strict
  multi-step **protocol adherence**, precise non-contiguous **native edits**
  (`multi_replace_file_content`), and **native async/reactive task management** (woken when a
  background shell task finishes — no polling; good for long orchestrations) — each with a
  **calibration note** (how reliable, observed hit/miss where known; `[bus]` claims to be verified).
- **B. Weaknesses & failure modes (route away / guardrail).** Open-ended "find bugs" → over-escalation
  & hallucination; cross-graph cascade and concurrency interleavings (reasons locally/sequentially);
  **worktree/gitignore-blind until it actively probes** (`list_dir`/`grep_search`) & wrong-folder
  reads; **open-ended discovery in large trees burns context fast** (tool-call response volume);
  backend-overload mid-turn aborts.
- **C. Reasoning profile & model selection (a primary lever).** agy is a **multi-model router across
  providers**, not a single model — so "agy's capability" is really *agy's orchestration + native
  tools + the **active model**'s capability*. The selected model + its reasoning-effort tier is the
  **dominant capability dial**. Available in this install (`[local]`, the `/model` menu):
  Gemini 3.5 Flash (Low/Medium/High), Gemini 3.1 Pro (Low / **High — current**), Claude Sonnet 4.6
  (Thinking), Claude Opus 4.6 (Thinking), GPT-OSS 120B (Medium). The profile must give a **per-model
  capability note** (what each is good/cheap/strong at) so a delegation can pick the right one. Also:
  a **separate context window** from Claude's; sequential/local bias.
- **D. Operational reach (what it can act on).** File writes — **`[conflict]`**: `[corpus]`/empirical
  (`agy-assumptions.md #8`) observed writes rejected outside cwd (artifact-path rule → shell fallback),
  but `[bus]` agy claims native tools (`write_to_file`, `replace_file_content`,
  `multi_replace_file_content`) write anywhere OS perms allow. **Resolve by triangulation; do not
  assert either until reconciled.** Plus: shell (pwsh), the **agentmemory MCP** (save/recall durable
  cross-agent context — a core collaboration capability to route to), other MCP tools, sub-agents
  (`/agents`), git checkpoints, headless/print behavior.
- **E. Control surface that changes capability.** Model selection (`--model` / `models`), **which
  skills/MCP servers are loaded (= which tools agy has — the dynamic part of the profile)**,
  permissions mode — **only** insofar as they bound what's delegable.
- **F. Routing: whether agy, and on which model.** Two linked decisions: (i) **agy vs a Claude
  subagent** — agy is the right pick for an *independent second-model* perspective (divergent review,
  generative design partner), while a Claude subagent is better for mechanical sweeps / well-specified
  implementation (Claude's own tiering rules); and (ii) **which model to set agy to** for the task
  (deep review/reasoning → Opus 4.6 Thinking or Gemini 3.1 Pro High; bulk/cheap/mechanical → Flash
  Low/Medium; open-weight/cost-sensitive → GPT-OSS 120B). Note the redundancy guard: don't route to
  *agy-on-a-weak-model* what you'd keep on Claude; agy's value is often the *different* provider's
  perspective (e.g. a Gemini or GPT-OSS second opinion on Claude-authored work).
- **G. Version & drift.** `Verified against: agy <version>`; changelog-tracked capability changes.

**Provenance on every claim** (the central risk is "true upstream, wrong for our version"):
`[corpus]` (the user's validated agy knowledge) · `[doc]` (official docs/codelab/changelog, cite URL)
· `[local]` (introspecting the installed agy) · `[bus]` (agy's self-report) · `[verified]` (≥2 sources
agree) · `[conflict: …]` (sources disagree; `[local]`/`[bus]` win for our version). Capability claims
carry their **calibration source** (e.g. "`[corpus]` over-escalates on open discovery — observed
~2-real/1-misscoped on MarketMonitor Safeguards Phase 3"). No untagged claims.

## 4. Research execution (Hybrid — passes + synthesis)

The research *produces* #1. Output is the capability profile, not raw trivia. **Source priority
(agy is closed-source — this overrides agy's own "demote the web" advice):** Claude **cannot study
agy's code** to learn its capabilities, and local introspection sees only **configuration files +
observable behavior**, not the implementation. So the **web is a PRIMARY avenue** — official docs
(`antigravity.google/docs`, the Google codelab, `agy changelog`) **plus real user findings**
(StackOverflow, GitHub issues, community guides) — alongside the **user's validated corpus**. **Local
introspection** (config files + observed behavior) grounds *which* capabilities are actually
loaded/configured here; the **bus self-report** is **cross-check only** (agy overstates — see Axis D).
agy's valid point still holds: effective capability = baseline + currently-loaded skills/MCP, so local
enumeration of the loaded toolset matters — but the *baseline* surface comes from web + corpus.

- **Pass 0 — Harvest the existing corpus (main thread; PRIMARY).** Seed from the user's validated
  knowledge: `~/.claude/skills/token-discipline-installer/templates/AGENTS-antigravity-protocol.md`;
  the `feedback_agy_review_wording.md` / `project_antigravity_protocol.md` /
  `feedback_agy_consult_before_user.md` memories; the `agy-first-brainstorm.sh` hook; and clavity's
  own `agy-assumptions.md` / protocol doc / responder skill. Much of A/B/F is already here.
- **Pass 1 — Web research (parallel, delegated; PRIMARY).** One research subagent per area (lower
  tier; high-volume/low-judgment fan-out). Seed known URLs (`antigravity.google/docs/*`, the Google
  codelab, `agy changelog`) **and** community/user findings (StackOverflow, GitHub issues, guides) +
  free search. **Include a per-model capability sweep** for the models agy can run — Gemini 3.5 Flash,
  Gemini 3.1 Pro, Claude Sonnet 4.6, Claude Opus 4.6, GPT-OSS 120B (strengths, reasoning depth, speed/
  cost, context, tool-use) — so Axis C can advise model choice per task. Strict dispatch contract:
  deliver **atomic, source-cited facts** + an explicit "couldn't confirm" list; **do not invent**,
  never reshape a flag/path/command, paste exact strings, no elided enumerations; return raw findings,
  not prose. (agy being closed-source, the web + corpus are how we learn the baseline capability
  surface — there is no code to read.)
- **Pass 2 — Local introspection (main thread; config + behavior only).** Bounded to what's readable
  without source: `agy --help`, `--version`, `models`, `changelog`; inspect **config files** under
  `~/.gemini/antigravity-cli/` (skills, `cli.log`), `~/.gemini/config/`, `~/.gemini/skills/`; and
  **enumerate the currently-loaded skills + MCP servers** (the dynamic part of the profile, §3).
  Confirms what's loaded/configured + observed behavior here — **not** the implementation.
- **Pass 3 — agy self-report (main thread; via the bus; CROSS-CHECK).** `clavity ask` agy (two-mode)
  to describe its own strengths/limits/reach — dogfooding clavity; one source, **cross-checked** (it
  overstates reach — see Axis D conflict).
- **Synthesis & cross-verify (main thread).** Merge the four sources into the profile, tag each claim,
  promote agreements to `[verified]`, surface disagreements as `[conflict]`. "Verify inversely to
  tier": lower-tier web findings checked harder; any routing-critical claim confirmed against
  `[local]`/`[corpus]` before being stated unqualified.

## 5. #2 — Extending the wording protocol (surgical)

`docs/agy-remote-control-protocol.md` already has a "Driving conventions" section (agy's stated
wording preferences). Extend it minimally to:
1. **Link to #1** (`docs/agy-capabilities.md`) as the routing reference — "consult the capability
   profile to decide *whether* and *what* to delegate before phrasing the ask."
2. Make the existing discipline **capability-aware**: the two-mode ask (critical **+** generative —
   never review-only-by-content), severity-gating, evidence mandate (`file:line` + trace), no
   hyperbolic priming, front-load context (agy is worktree-blind / separate context), and the
   delegation boundary — each cross-referenced to the relevant profile axis.

The wording **discipline stays here** (not duplicated into #1).

**Local-first, then promote.** Extend and validate the wording protocol **locally** in clavity first
(the bus-transport instance, where we can dogfood `clavity ask` against the live agy). Once it proves
out, **promote the capability-aware additions up to the global AGENTS.md "Working with Antigravity"**
(the canonical upstream all projects share). Test local → promote global; don't edit the global until
the local version is validated.

> **Status 2026-06-16:** local extension validated (acceptance suite 10/10 against agy 1.0.8). Global
> promotion is **NOT done** — an attempt to add this to the `corelib` repo's AGENTS.md was **reverted**,
> because corelib is an unrelated project (wrong target). The capability-aware conventions live in
> clavity only for now; choose the correct shared destination before promoting.

## 6. #3 — The when-gate (reference only)

`~/.claude/hooks/agy-first-brainstorm.sh` is the user's policy: during brainstorming, get a divergent
agy review **before** presenting scope/design options to the user, and relay at each artifact (spec,
plan). #2 references it as "the trigger"; the hook is **not edited** by this work.

## 7. Lifecycle — refresh procedure (in #1's footer)

After any `agy update`: (1) `agy changelog` → diff vs the pinned version; (2) re-run Pass 2
introspection; (3) targeted re-check of `antigravity.google/docs` + changelog; (4) update changed
claims, re-tag provenance, bump `Verified against`; (5) if a capability changed enough to alter
routing, note it and cross-link `agy-assumptions.md`. Mirrors `agy-assumptions.md`'s re-verify ethos.

## 8. Success criteria

- `docs/agy-capabilities.md` exists as a **routing-oriented** profile (axes A–G), not a CLI dump.
- Every claim is provenance-tagged; **no untagged claims**; routing-critical claims are `[verified]`
  (cross-checked) or grounded in `[corpus]`/`[local]`; web-only `[doc]` capability claims are marked
  "unconfirmed"; capability claims carry a calibration source. `[conflict]` items listed.
- A `Verified against: agy <version>` header + a runnable refresh procedure are present.
- #2's "Driving conventions" links to #1 and is capability-aware; the wording discipline is **not**
  duplicated into #1; capability-aware additions validated locally first, then promoted to global.
- #1 links to (does not duplicate) `agy-assumptions.md`, the protocol doc, and references the hook.
- Spot-check: a few routing-relevant claims (a strength, a weakness, an operational limit) hold up
  against the installed agy / the corpus evidence.

## 9. Out of scope (YAGNI)

- The Antigravity **IDE/desktop** app — CLI (`agy`) only.
- Studying agy's **source code** — it is **closed-source**; we learn capabilities from web + corpus +
  config files + observed behavior + agy's (cross-checked) self-report, never from its implementation.
- **Editing** the wording protocol beyond the #2 extension (local) + its promotion to global, or
  **editing** the hook (#3).
- A standalone "driving-agy" skill — superseded by the doc (#1) + extended protocol (#2).
- Automated/scheduled re-research — the refresh (§7) is a manual runbook.

## 10. Risks

- **Closed-source + sparse/contradictory web coverage** for a young tool → no code to read, so lean on
  *multiple* web sources (official docs **and** user findings) + corpus + observed behavior;
  triangulate; `[conflict]` tag; `[local]`/`[corpus]` win for our version.
- **Capability claims are softer than facts** (e.g. "good at X") → require a calibration source; prefer
  `[corpus]` observed behavior and corroborated user findings over `[doc]` marketing claims.
- **Profile drifts as agy updates** → provenance + `Verified against` pin make staleness visible; §7
  refresh.
- **agy mis-reports its own strengths** → `[bus]` is one source, cross-checked against `[corpus]`/`[local]`.
