# clavity v2 — Bidirectional Claude↔agy Bridge — Design

**Date:** 2026-06-17
**Status:** Approved (design); implementation plan pending.
**Author:** Costas Kirgoussios (with Claude + extensive agy consults)

---

## 1. Context & charter

v1 of clavity was a Rust binary that let Claude Code (master) drive a live `agy` (Antigravity
CLI) peer over a **psmux doorbell** (`send-keys`) + the **agentmemory signal bus**, with
pane-scraping for state. It was inherently **asymmetric** (Claude→agy) and depended on terminal
automation.

clavity **v2** is a **true bidirectional bridge**: the user, working in their live Claude session,
can delegate to agy ("ask agy to review X") **and** a running agy can delegate to Claude ("ask
claude to write Y"). The original sketch imagined one shared remote MCP server both CLIs subscribe
to, waking each other via `notifications/resources/updated`. **Empirical verification (below)
proved that model non-viable**, and the design that survived contact with the real tools is
materially different — and, after a stack review, **all-Python** (Rust retired).

clavity v2 ships as the `plugins/clavity/` member of the repo's universal dual-plugin suite.

---

## 2. Verified constraints (the evidence base)

Per this repo's discipline (`docs/agy-assumptions.md`): external-tool behavior is **empirically
derived, not a stable contract** — re-verify after a `claude`/`agy`/SDK update.

### Claude Code (official docs, code.claude.com, 2026-06-17)
- Supports remote HTTP/SSE/WebSocket transports **and** stdio. WebSocket can "push events
  unprompted"; HTTP is request/response only; SSE is deprecated.
- **Does NOT support resource subscriptions or sampling** — the sketch's `resources/updated`
  wake mechanism cannot fire on Claude.
- The **only** mechanism that makes an idle Claude *act* on a server push is **"channels"**: a
  local **stdio** MCP subprocess declaring `capabilities.experimental['claude/channel']` that
  emits `notifications/claude/channel`, delivered into the session as a `<channel>` tag so Claude
  "reacts while you're away." Two-way via a `reply` tool. **Research-preview** (Claude Code
  v2.1.80+), gated behind `--channels` / `--dangerously-load-development-channels`; Team/Enterprise
  need admin enablement. Official channel examples are TypeScript/Node.
- Claude is **also** re-engaged in place when a detached **background task completes** (the harness
  re-invokes the session) — a second, non-channel wake path for long-running local work.

### agy (peer consults `req-djbfzw…`, `req-djbg…`, 2026-06-17)
- **No MCP idle-wake.** An idle agy does not act on server notifications; it needs **stdin** to
  begin a turn. No `claude/channel` equivalent, no background sentry.
- **No control channel** (no socket/RPC/`agy send`) to drive a running session — TTY injection is
  the only way, and **any stdin write collides with user typing** (the psmux "keyboard lock").
- **Remote MCP unconfirmed:** all of agy's configured servers are stdio; agy could not confirm it
  supports remote `serverUrl`/SSE/HTTP/WebSocket at all. (Irrelevant to the chosen design.)
- **Headless one-shot:** the raw `agy` CLI hangs in pipes, **but the `google-antigravity` Python
  SDK runs headless sub-agents reliably** (`Agent(config).chat()`), returning clean JSON.
- The installed **`agy-mcp-bridge`** already uses that SDK; its `Agent.chat()` core is generic and
  extensible to read-only/review delegation in the live folder (no worktree/commit required).

### agy auth (agy self-audit `req-djbgp9ij…`)
- Interactive CLI credential: `~/.gemini/antigravity-cli/antigravity-oauth-token`. A
  `~/.gemini/oauth_creds.json` holds a `refresh_token` + `access_token`.
- The headless SDK falls back to Google Cloud **ADC**, which often lacks a durable refresh token →
  **frequent re-prompt** (this is why naive spawn-on-demand failed).
- The SDK supports **non-interactive** auth via **`GEMINI_API_KEY`/`GOOGLE_API_KEY`** or a
  **service-account JSON** — skips OAuth, never re-prompts.

### User constraints
- **psmux is rejected** — `send-keys` causes a keyboard lock (the user cannot type).
- Naive **spawn-on-demand was rejected** — but **only** because of the re-auth above; with stable
  non-interactive auth it is viable.
- **External projects are allowed** (the `google-antigravity` SDK, the `agy-mcp-bridge`).
- **Stack: all-Python** — once the agy SDK makes a Python runtime mandatory, Rust's
  zero-runtime-single-binary benefit is forfeited; polyglot complexity isn't worth it.

---

## 3. Locked decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Hybrid wake**, per-host | No single mechanism wakes both; use each host's reality. |
| D2 | **Claude** = live session, woken **in place** via `claude/channel` | The only act-on-push path Claude supports. |
| D3 | **agy** = **spawn-on-demand headless** via the SDK (extend `agy-mcp-bridge`), with **stable non-interactive auth** | No psmux, no keyboard lock, no re-auth, no live-pane injection. |
| D4 | **No live idle agy to wake.** A live agy tab is allowed for *manual* use; *delegation* always spawns a fresh headless agy. | TTY injection (the only live-wake) collides with typing; rejected. |
| D5 | **Own clavity daemon-bus**, not agentmemory | The pivot to synchronous spawn-on-demand makes agentmemory's threading/read-unread/durable queue overkill; agentmemory is an external, recently-flapping dependency; clavity should be self-contained. |
| D6 | **All-Python** stack; Rust retired | Python runtime mandatory anyway (SDK); cohesion > polyglot. |

---

## 4. Architecture

```
        ┌──────────────────── same folder ────────────────────┐
        │                                                      │
   ┌────┴─────┐  ask_agy(task) ──► clavity daemon ──► spawn-on-demand
   │  Claude  │                    (own bus +          headless agy (SDK,
   │  (live)  │  ◄── result ─────  router/watcher)     stable auth) → JSON
   └────┬─────┘                         │  ▲                │
        │ stdio                         │  │ long-poll      │ returns
   ┌────┴───────────────┐   →claude     │  │ (agy→Claude)   │
   │ Claude channel-    │ ◄─────────────┘  └───────────────┘
   │ driver (MCP server,│   push notifications/claude/channel
   │  claude/channel)   │   ──► wake live Claude IN PLACE as responder
   └────────────────────┘
                         clavity daemon also runs WATCHERS (e.g. CI):
                         on event → wake Claude (channel/in-place) OR spawn agy
```

### 4.1 `clavity` launcher (Python CLI)
Starts the live Claude session in the folder (with the `--channels` enablement for the bundled
channel-driver); starts the clavity daemon; performs the one-time agy credential setup; `doctor`/
`info` diagnostics. A live agy tab is optional (manual use only).

### 4.2 clavity daemon (Python) — the **own bus** + watcher/router
A single background process:
- **Correlation map** keyed by `[req_id]` (request↔reply), in-memory, **ephemeral** (no durable
  queue; in-flight lost on restart — acceptable, since the agy sub-agent is ephemeral anyway).
- **Local API** (loopback HTTP/socket): `send` and **`await-reply` via long-polling** (see §6 —
  Claude replies can take minutes; the agy side must poll, not hold one fragile request).
- **Router/bridge** between the Claude channel-driver and the agy spawn-driver.
- **Watchers** (e.g. GitHub CI): poll an external event; on completion route to Claude (channel /
  in-place) or spawn agy. This is the `watch-ci` pattern generalized — agents never block waiting.

### 4.3 Claude channel-driver (Python MCP server) — wake Claude
A stdio MCP server (spawned by Claude via the plugin's `.mcp.json`) that:
- declares `capabilities.experimental['claude/channel']`,
- runs a poll loop against the daemon for `→claude` messages and pushes them as
  `notifications/claude/channel` → **idle Claude wakes in place as responder**,
- exposes `ask_agy(task)` (→ daemon → spawn agy → return result) and `reply(req_id, text)` tools.

**Verify-at-impl (§8):** confirm the Python MCP SDK can declare `claude/channel` + emit the
notification as cleanly as the Node SDK; **if not, this one component is Node** (the rest stays
Python — still no Rust).

### 4.4 agy spawn-driver (Python, extend `agy-mcp-bridge`)
A generic delegation tool (e.g. `ask_antigravity` / review mode) over `Agent(config).chat()`:
spins up a headless agy **in the live folder**, runs the task, returns JSON, terminates. Uses the
**stable non-interactive credential** (D3) so it never re-prompts. No worktree/commit requirement
for review-only work.

### 4.5 Packaging — the `clavity` universal dual-plugin
Installs in both CLIs from one dir (disjoint-filename trick from the suite design). Claude gets the
channel-driver MCP server (`.mcp.json` + the `--channels` enablement); agy's side is the
spawn-driver bridge + a responder/usage skill. Polyglot Python (+ optional Node channel) is fine.

---

## 5. Data flow

**Claude → agy (synchronous):** user (in Claude) says "ask agy to review X" → Claude calls
`ask_agy` → daemon spawns headless agy (stable auth) in the live folder → agy returns JSON → tool
returns it to Claude → Claude reports. *No bus persistence, no psmux.*

**agy → Claude (async, the only one):** a running agy (a spawned sub-agent mid-task, or a manual
agy tab) posts `[req_id]` to the daemon → the channel-driver pushes it → **idle Claude wakes in
place**, does the work, calls `reply` → daemon matches `[req_id]` → the **long-polling** agy side
receives it.

**Long async event (e.g. CI):** an agent fires the action and **returns immediately (no lock)** →
the daemon's watcher polls → on completion it wakes Claude (channel/in-place) or spawns agy to act.

---

## 6. Error handling

- **Mid-task long replies (agy's key warning):** the `agy→Claude` path **must long-poll / poll
  for-reply**; Claude's generation can take minutes and a single HTTP request would sever. The
  daemon API is built around poll-for-reply with a bounded timeout.
- **Correlation / dedup:** strict `[req_id]` matching; guard the double-process race (an in-place
  wake landing as the user also acts) with idempotent, request-id-keyed handling.
- **Channels gating:** if `--channels`/version/org-policy makes `claude/channel` unavailable,
  **Claude-as-responder degrades** — `ask_agy` (Claude→agy) still works; `agy→Claude` falls back to
  "delivered on Claude's next turn" with a clear warning at launch.
- **Daemon crash:** ephemeral in-flight requests are lost and the blocked (ephemeral) agy sub-agent
  times out — an acceptable failure mode (no durable state by design).
- **agy auth failure:** if the stable credential is missing/invalid, `ask_agy` fails fast with a
  setup message (don't silently fall back to interactive OAuth).

---

## 7. Testing

- **Daemon (Python):** unit tests for `[req_id]` correlation, long-poll await-reply (incl. timeout),
  router dispatch, watcher event→action.
- **Channel-driver:** the poll→push path and `ask_agy`/`reply` tool behavior against a mock daemon;
  a `<channel>` emission test.
- **agy spawn-driver:** a headless `Agent.chat()` round-trip with the stable credential (no
  re-prompt); JSON-shape assertions.
- **Live acceptance runbook** (re-run after a `claude`/`agy`/SDK update, per `docs/agy-test-suite.md`
  discipline): both directions end-to-end — "ask agy to review …" from Claude; "ask claude to …"
  from a running agy; a CI-watcher round-trip. Confirms channels enablement, stable auth, long-poll.

---

## 8. Open items — verify at implementation

1. **Python `claude/channel` feasibility (§4.3):** can the Python MCP SDK declare the experimental
   capability + emit `notifications/claude/channel` cleanly? If not, the channel-driver is **Node**.
2. **agy credential (D3):** **default `GEMINI_API_KEY`** (agy's recommendation — most reliable, but
   metered API billing separate from the interactive Antigravity subscription). **Verify whether
   reusing the existing OAuth `refresh_token`** (`~/.gemini/oauth_creds.json`) works headlessly
   without re-prompting — if it does, prefer it (no extra billing). Service-account JSON is the
   third option for a stable bot identity.
3. **Channels availability:** the launcher must pass `--channels`/`--dangerously-load-development-
   channels`; confirm the exact flag form and that the bundled plugin channel registers.

---

## 9. Dependencies & repo impact

- **Stack flip:** the repo's Rust skeleton (`crates/mcp-core`, `xtask`, `plugins/scaffold`) is
  **retired** (preserved on the branch). The universal dual-plugin **packaging** concept survives;
  the packager becomes a Python script (or static `dist/` assembly). **A sibling task converts the
  skeleton to Python** — prerequisite for `plugins/clavity/` to live consistently in the suite.
- **Python tooling = `uv`** (Astral). The project is a `uv`-managed package (`pyproject.toml`,
  `uv run`, `uv sync`); already consistent with the installed `agy-mcp-bridge`, which launches via
  `uv`. Distribution uses `uv tool install` / `uvx`, which recovers much of the "drop-in install"
  convenience Rust's single binary would have given (one command, isolated env).
- **External deps:** `google-antigravity` SDK (agy), the MCP Python SDK (channel-driver), the
  extended `agy-mcp-bridge`. A Python runtime is required (already present — the SDK mandates it).
- **agentmemory** drops out of clavity's core path (reserved for the separate `commonmemory` plugin
  if shared long-term memory is later wanted).

---

## 10. Risks

- **External-contract drift** — channels are *research-preview* and may change; agy's SDK/auth may
  shift. Mitigated by the re-verification runbook (§7) and feature-gated degradation (§6).
- **Channels gating friction** — the dev/allowlist flag + Team/Enterprise policy may block channels
  for some users; documented, with graceful degradation.
- **API-key billing** (if `GEMINI_API_KEY` chosen) — metered cost distinct from the Antigravity
  subscription; the OAuth-refresh alternative (§8.2) avoids it if it verifies.
- **Polyglot seam** — if the channel-driver must be Node, the plugin spans Python + Node; contained
  to one component, documented.
