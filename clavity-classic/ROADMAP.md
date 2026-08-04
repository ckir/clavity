# clavity ROADMAP

> Provenance: authored from a real driving session (Claude driving `agy` through clavity,
> 2026-06-16) — 6 review/red-team round-trips (a readiness ping, three spec reviews, two
> convergent gates). The items below are the concrete frictions hit in that session, written
> so they can be implemented in a separate session without further context.

---

## ✅ STATUS: COMPLETE (2026-06-17)

Everything below is **shipped and on `main`** (`ckir/clavity`). Summary:

- **Theme 1 — blocking round-trips:** `ask` (+ `--review-only`/`--no-ring`), `await-reply`, `ping`,
  the `src/membus.rs` agentmemory daemon REST client, and the hermetic fake-endpoint test harness —
  all delivered. Step 0 (daemon API discovery) recorded in `agy-assumptions.md` #13.
- **Theme 2 — protocol & docs hygiene:** pane-scrape/poll-loop deprecated; REVIEW-ONLY banner
  codified; README / protocol runbook / `agy-assumptions.md` / `bus.rs` comment all updated.
- **Acceptance criteria (1–4):** all met — one-shot `ask` round-trip verified live; no path requires
  `capture | grep` or a hand-rolled poll loop; existing commands unchanged with the full suite green
  (`cargo test` / `clippy -D warnings` / `fmt --check`); docs updated.
- **Follow-up — pre-flight thread discovery:** resolved as **Option D** (`await-reply --thread-id`,
  thread-scoped; unsafe unscoped path dropped) after an agy design consult; tested + live-validated.

Beyond this ROADMAP, the same effort produced the **agy capability profile** + capability-aware
**wording protocol** + a re-runnable **acceptance suite** (see `plugin/knowledge/agy-capabilities.md`,
`docs/agy-remote-control-protocol.md`, `docs/agy-test-suite.md`). No open items remain.

---

## Theme 1 — First-class blocking round-trips (the big one)

### The friction (observed)

The delegation loop today is **send → ring → (figure out the reply yourself)**. There is no
first-class "wait for agy's correlated reply" step, so the master (Claude) is forced into one of two
poor patterns:

1. **Poll `memory_signal_read(agentId=claude, unreadOnly=true)` in a loop** — N MCP calls, manual
   timing, easy to read too early (empty) or too late.
2. **Scrape agy's pane**: `clavity capture | grep <req_id>` in a timer loop. This was the actual
   workaround used. It is fragile — it matches terminal text, races pane redraws, and depends on the
   reply being *visible* in the viewport.

`clavity wait-idle` does **not** solve this: it blocks on **pane idle** (agy stopped typing), not on
a **correlated bus reply landing**. So there is no reliable, low-overhead "block until agy answers
request X, then give me the answer" primitive. Each round-trip this session cost a ~2-minute wait
plus hand-rolled polling overhead.

### The goal

The master issues **one** call per delegation and gets the reply **content** back, with a timeout —
no polling, no pane-scraping.

### Core architectural decision — DO THIS FIRST

clavity is currently **bus-agnostic by design** — `src/bus.rs` (lines 3–5) states the bus is driven
by the MCP tools `memory_signal_send` / `memory_signal_read`, "which only the agent runtime
(Claude / agy) can call — **not this binary**." bus.rs holds only *pure conventions* (req-id minting,
the `[req_id=..]` envelope).

To wait on (and optionally send) bus messages, **clavity must become a direct client of the
agentmemory daemon** — the shared store both agents' MCP servers connect to (README: it runs a
shared daemon, default `:3111`). This is a deliberate reversal of the "never touches the bus" stance
and **must be recorded** in `docs/agy-assumptions.md` as a new, load-bearing external dependency.

#### Step 0 — discover the agentmemory daemon API (UNKNOWN — verify before building anything)

Do **not** guess the API. First determine how to read/write signals out-of-band from the MCP tools:

- Inspect `@agentmemory/agentmemory`: does the daemon expose an HTTP/REST or WebSocket API on
  `:3111` for listing/sending signals? Look for routes like
  `GET /signals?to=claude&unreadOnly=true` and `POST /signals`.
- Decision tree:
  - **HTTP/WS API exists** → clavity speaks it directly (preferred; simplest).
  - **Only stdio MCP exists** → either (a) clavity spawns `npx @agentmemory/agentmemory mcp` as a
    child and speaks MCP JSON-RPC to call `memory_signal_read` / `memory_signal_send`; or
    (b) read the daemon's backing store directly (SQLite/JSON file) for **reads only** (sends still
    need the API/MCP). Prefer (a).
- Record in `docs/agy-assumptions.md`: daemon port/discovery (env override? default 3111?), any auth,
  and the **exact signal schema** — confirmed fields: `id`, `from`, `to`, `type`
  (info|request|response|alert|handoff), `content`, `replyTo`, `threadId`, `readAt`, `createdAt`.

Until Step 0 is resolved the commands below cannot be built. New I/O lives in a **new module
`src/membus.rs`** (the agentmemory daemon client); `bus.rs` stays pure-conventions.

### New commands

> Insertion points: `enum Cmd` at `src/main.rs:50`; dispatch `match cli.cmd` at `src/main.rs:116`.
> Follow the existing exit-code discipline (machine output → stdout; diagnostics → stderr via
> `tracing`; meaningful exit codes).

#### `clavity await-reply --req-id <ID> [--timeout SECONDS] [--poll-interval MS]`

Block until a bus signal addressed to the master (`to=claude`) correlated to `<ID>` arrives; print
its `content` to **stdout**; exit `0`. On timeout, exit `1` (note on stderr).

- **Correlation:** match `replyTo == <request's signal id>` **OR** `content` contains
  `[req_id=<ID>]`. The master usually does not know the request's signal id, so correlate primarily
  on the embedded `req_id` — **reuse `bus::extract_req_id`** (already in the binary, currently
  `#[allow(dead_code)]` — this makes it live) and add a `replyTo` check.
- **Return content directly** so the master needs no second `memory_signal_read`.
- **Read-state semantics:** do NOT mark-read in a way that hides the reply from the master's own MCP
  inbox. Prefer a **non-mutating** read (filter without marking read); OR document that `await-reply`
  is authoritative and the master must not also `memory_signal_read` the same id. Decide per Step 0
  capabilities and document it.
- **Polling:** long-poll server-side if the API supports it; otherwise poll every `--poll-interval`
  (default ~1000–1500 ms — this is clavity-side, so the master's prompt cache is irrelevant).

#### `clavity ask "<INSTRUCTION>" [--to AGENT] [--type TYPE] [--timeout N] [--review-only] [--no-ring]`

The composite one-shot round-trip = **mint req-id + send request on the bus + ring + await-reply +
print reply**. Collapses today's 4-step dance into one call. This is THE ergonomic win:

```
clavity ask --review-only "review docs/specs/foo.md against the code; verify, don't redesign…"
# → prints agy's verdict, or exits 1 on --timeout
```

- Requires daemon **send** capability (Step 0). If out-of-band send proves impossible, ship
  `await-reply` alone and keep send on the master's MCP tool (document that `ask` needs the send path).
- `--to` default `agy`; `--type` default `request`.
- `--no-ring` for cases where agy is already mid-turn / will pick up the queued doorbell.
- Output: reply `content` on stdout; exit `0` reply / `1` timeout.

#### `--review-only` flag (on `ask`)

Prepend the **strict REVIEW-ONLY banner** to the request content. This convention was used every
round this session and agy honored it (replied `Changes Made: None (Review only)`); encoding it as a
flag makes the no-edit/no-commit contract one keystroke and consistent. Store the banner as a
constant. Canonical text:

```
╔══════════════════════════════════════════════╗
║  REVIEW ONLY — DO NOT EDIT, DO NOT COMMIT.    ║
║  No file writes. No git stage/commit/push.    ║
║  Output is a written verdict ONLY.            ║
╚══════════════════════════════════════════════╝
```

#### (optional) `clavity ping [--timeout N]`

Readiness round-trip: send `[ping]` + ring + await `READY`/`pong`. Turns the README "give agy a
moment / gate on a bus-readiness ping" guidance into one command. Implement as `ask` with the ping
fast-path content (the responder skill already fast-paths `[ping]` → `READY`, no checkpoint).

---

## Theme 2 — Protocol & docs hygiene

- **Deprecate pane-scraping for reply detection** in `docs/agy-remote-control-protocol.md`: tell the
  master to use `clavity ask` / `await-reply`, and explicitly **NOT** to `clavity capture | grep` or
  hand-roll a `memory_signal_read` poll loop to find replies.
- **Codify the REVIEW-ONLY banner** in the protocol runbook as the canonical wording for review /
  red-team delegations (with the `--review-only` flag as the easy path).
- **README**: add `await-reply` / `ask` / `ping` to the command table; replace the manual 4-step
  "Drive agy from Claude" example with the single `clavity ask` call.
- **`docs/agy-assumptions.md`**: add the agentmemory daemon API as a new dependency (port, schema,
  re-verify procedure after an agentmemory update) — it becomes load-bearing, unlike today.
- **`src/bus.rs`** doc comment: update the "not this binary" claim once `membus.rs` exists (the
  *conventions* stay pure; the new module does the I/O).

---

## Tests (mirror the existing two tiers)

- Hermetic unit/integration tests for the daemon client against a **fake agentmemory endpoint** —
  same spirit as `src/bin/fake_tmux.rs` + `tests/integration.rs`. A tiny in-process HTTP (or stdio)
  stub that returns a canned `response` signal after K polls. Assert:
  - `await-reply` blocks then returns the stub's `content`; correlation matches on `req_id` and on
    `replyTo`.
  - `await-reply` exits `1` on `--timeout`.
  - `ask` sends the correct envelope (req-id present; banner prepended iff `--review-only`), rings
    (unless `--no-ring`), and returns the stubbed reply.
  - Gate behind a test feature (extend the existing `test-fakes`).
- Keep green: `cargo test --all --features test-fakes`,
  `cargo clippy --all-targets --features test-fakes -- -D warnings`, `cargo fmt --all --check`.

---

## Non-goals / risks

- **True push** to Claude Code (no hook to inject a notification mid-turn) — long-poll `await-reply`
  is the pragmatic equivalent. Don't chase push.
- **Don't make the daemon client mandatory** for the existing commands — `start` / `ring` / `state` /
  `capture` / `doctor` must keep working with zero bus access (setup & diagnostics).
- **Read-state drift** between clavity reads and the master's MCP reads — resolve per Step 0; default
  to non-mutating reads + return-content-directly.
- **agentmemory API instability** across versions — the reason it must live in `agy-assumptions.md`
  with a re-verify step.

---

## Acceptance criteria

1. `clavity ask --review-only "<spec review request>"` performs a full round-trip and prints agy's
   verdict in **one** invocation, honoring `--timeout` (exit `1` on timeout).
2. No protocol path requires `clavity capture | grep` or a hand-rolled `memory_signal_read` poll loop
   for reply detection.
3. Existing commands behave unchanged; `cargo test` / `clippy -D warnings` / `fmt --check` all green.
4. README, protocol runbook, and `agy-assumptions.md` updated to match.

---

## Suggested sequencing

1. **Step 0** (discover agentmemory daemon API) → record in `agy-assumptions.md`.
2. `src/membus.rs` client + fake endpoint test harness.
3. `await-reply` (+ tests).
4. `ask` (+ `--review-only`, + tests) — depends on send capability.
5. `ping` (thin wrapper).
6. Docs sweep (README, protocol runbook, agy-assumptions, bus.rs comment).

---

## Follow-ups (captured post-implementation)

### ▶ DISCIPLINE EFFICACY applies to THIS driver too — see `clavity-dotnet/ROADMAP.md` §0

Owner-directed 2026-08-04, top priority after the current build. **The item is stated once, in the
umbrella backlog** (`clavity-dotnet/ROADMAP.md` §0, which also carries ghidrust's) rather than duplicated
here, because a long entry maintained in two files is the drift this repo keeps paying for. **The
requirement, however, is parity: whatever ships there ships here, byte-identically.**

What it concerns: every gate in this repo measures whether a discipline is PRESENT (files mirrored, ASCII,
registered, seed-sync green) and none measures whether it WORKS. v15 shipped the AGY-ANOMALIES discipline
with a faithful install and correctly-firing hooks, and it still produced nothing.

Classic-side surface, mirrored byte-identically and verified `IDENTICAL` 2026-08-04:
`clavity-classic/plugin/hooks/agy-anomaly-{capture-reminder,dispatch-reminder,model-notice}.sh`, plus
`clavity-classic/plugin/hooks/hooks.json`. Parity is enforced by
`scripts/tests/plugin-hooks-payload.Tests.ps1` and the whole-`.hooks` catch-all in
`scripts/check-seed-artifacts-synced.sh`. **A per-driver literal cannot live in these bodies** — see
`docs/agy-disciplines-marker-contract.md:13` (Option S) for the precedent and the trap.

### Pre-flight thread discovery for standalone `await-reply` (agy's idea, 2026-06-16)

> Source: agy, generative-mode round during the capability-profile test suite (Test C). Captured here
> as a future enhancement, not yet implemented.

**Friction.** `clavity ask` is safe because it *sent* the request itself, so it knows the `threadId`
and scopes its consuming read to that one thread (never touches unrelated unread). But **standalone
`clavity await-reply --req-id <ID>`** — used when the master sent the request via its own MCP
`memory_signal_send`, so clavity does *not* know the `threadId` — currently reads `agentId=claude`
with **no `threadId` scope**. The agentmemory daemon's read **consumes** (marks `readAt`) any returned
unread `to=claude` signal, so this can **consume unrelated replies** sitting in the master's inbox,
hiding them from the master's own later `memory_signal_read`. (Documented today as "authoritative —
don't also MCP-read"; the footgun remains for unrelated traffic.)

**RESOLVED 2026-06-17 → Option D (pass the threadId; don't discover it).** An agy design consult
rejected the original "discover the thread" idea (and a sender-view variant) as **fatally racy**: both
require an **unscoped `agentId=agy` read**, which marks *all* unread `to=agy` signals read — if clavity
polls in the window between the ring and agy's own `unreadOnly` MCP read, it **consumes agy's pending
request**, so agy never processes it and the master hangs. Verified against the daemon semantics
(`agy-assumptions.md` #13); not a small race (clavity polls within ~1s; agy wakes in seconds).

The fix instead leans on a fact we already have: **`memory_signal_send` returns the created signal,
including its `threadId`** (Step 0), so **the master already knows the thread**. So:
1. `clavity await-reply` takes a **required `--thread-id <THR>`** (alongside `--req-id`). The master
   passes the `threadId` it received from its own send.
2. clavity polls `agentId=claude&threadId=<THR>` — scoped to exactly that thread, consuming only the
   awaited reply; it touches **neither agy's inbox nor unrelated `to=claude` messages**. Same safety as
   the composite `ask`.
3. **The unsafe unscoped path is dropped** — `--thread-id` is required (no thread, no read), so there
   is no footgun to document.

**Acceptance:** `await-reply` errors if `--thread-id` is missing; every inbox read it issues is
`agentId=claude&threadId=<THR>`-scoped (fake-endpoint test asserts the recorded GETs carry the
threadId); times out exit 1; `ask` unchanged.

**Rejected alternatives:** (a) clavity-side thread *discovery* — racy, see above; (b) a daemon
`GET /agentmemory/signals?peek=true` no-consume flag — clean but needs an **agentmemory** upstream
change (out of clavity's control); revisit only if the daemon adds it.
