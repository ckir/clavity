# agy Remote Control — Claude-side orchestration protocol (C1)

The procedure Claude follows to drive the live, signed-in `agy` session in the same folder.
Transport is the **agentmemory signal bus** (Claude's own `memory_signal_send` / `memory_signal_read`
MCP tools) for payloads; the **doorbell** (`clavity ring`) wakes agy. The `clavity` binary provides
the psmux/state plumbing and the bus id convention (`clavity req-id`). See the design spec at
`docs/superpowers/specs/2026-06-16-agy-remote-control-design.md`.

> **Correctness rests on the bus, not the TUI.** State detection (idle/busy) is best-effort and
> never load-bearing — a misread only affects ordering, because a doorbell sent while agy is busy is
> safely queued and processed as the next turn.

## Preconditions (bootstrap — one human step per session)
1. A human has started the session, signed in, in the target folder. Easiest is **`clavity start
   <folder>`** — it starts agy in the `claude_agy` psmux session (skip-permissions) *and* Claude
   Code in the same folder. Manual equivalent: `<psmux> new-session -s claude_agy -c <folder>` then
   `agy --dangerously-skip-permissions` (or `agy --continue`).
2. Verify reachability: `clavity state` → expect `idle`/`busy` (not `dead`). If `dead`, ask the
   human to bootstrap; do not proceed.

## Readiness — agy's MCP servers load lazily after launch

`clavity state` reaching `idle` does **not** mean agy can use the bus yet: after launch agy takes a
few seconds to load its MCP servers (agentmemory included), and its idle prompt can appear *before*
that finishes. There is no reliable pane marker for "MCP ready", so gate first contact on a **bus
round-trip** — agy can only reply once agentmemory is loaded. Use the one-shot command:

```bash
clavity ping            # send [ping] + ring + block for READY; prints "[req_id=…] READY", exit 0
```

`ping` mints the id, sends `[req_id=<id>] [ping]`, rings, and blocks until the reply lands (exit 1 on
timeout). The `[ping]` marker triggers the responder's **fast-path**: agy replies `READY` immediately,
skipping the checkpoint and any file work. If `ping` exits non-zero, agy's bus isn't up yet — wait a
moment and retry. Once `READY` arrives, agy + its bus are live.

> The old manual form (`memory_signal_send … [ping]` → `clavity ring` → poll `memory_signal_read`) is
> still valid as a fallback, but `clavity ping` collapses it into one call with no polling.

(The human equivalent, in the watch tab, is typing `list your active mcp servers` and seeing
`agentmemory` listed.)

## Driving conventions (agy's stated preferences)

agy defined these — follow them when phrasing requests for best results.

**Route by capability first.** Before phrasing an ask, consult the capability profile
([`agy-capabilities.md`](agy-capabilities.md)) to decide **whether** to delegate to agy at all,
**what** to delegate, and **which model** to set it to — agy is an external, multi-model platform, so
treat picking it (and its model) like choosing a subagent tier:
- **Route toward agy** for an *independent second-model* perspective: divergent review, generative
  design input, a different provider's opinion on Claude's work, or non-blocking async orchestration
  (profile §A/§F). **Keep on Claude** mechanical sweeps / well-specified implementation (§F redundancy
  guard — don't hand agy-on-a-weak-model what Claude should just do).
- **Pick the model for the task** (§C): deep review/reasoning → Opus 4.6 Thinking or Gemini 3.1 Pro
  High; bulk/cheap/parallel → Flash Low/Med; cost-sensitive second opinion → GPT-OSS 120B (not top
  coding/agentic). Set it with `--model` / `/model`.
- **Respect the weaknesses** (§B): seed specific invariants instead of open "find bugs" (it
  over-escalates); supply whole-graph context for cross-file/concurrency work (it reasons locally);
  always verify its file/line claims against disk (worktree-blind); and account for quota/backend
  lockouts on critical-path work (keep a Claude fallback).

**Request shape — DO:**
- Lead with a clear **imperative goal** ("Implement X in `src/y.rs`").
- List the **exact file paths in scope** (saves agy searching).
- Give a **Definition of Done / how to verify** (e.g. "verify with `cargo test --test foo`") — agy is
  biased toward acting and verifying.
- State **guardrails** explicitly ("Do NOT modify `src/legacy.rs`").
- Prefer Markdown sections: `### Goal`, `### Files in scope`, `### Verification`, `### Guardrails`.
- **Carry your own context** — you and agy have *separate* context windows. If you just read a long
  log, paste the relevant stack trace into the request; agy can't see what you saw.
- **Front-load ALL targets to trigger parallelism** — agy can run tool calls concurrently in a turn
  (read N files / search M terms at once). List every file/term upfront ("read `a.rs`, `b.rs`, `c.rs`")
  rather than dribbling them — assuming sequential work throttles its throughput.
- For analysis/review only, say it outright: **"Just REPLY on the bus — do NOT write or edit files."**
  agy's default bias is to start coding. For scripts, say whether to *write* or *run* them.

**AVOID:**
- Vague scope ("fix the bug") — give the error/trace or the precise behavior mismatch.
- Guessing **line numbers** — agy's edit tools need exact string matches; point to function/class names.
- Interactive confirmations ("does this make sense?") — agy can't chat; it replies only when done or blocked.

### Per-mode request templates (agy's stated preferences)

agy works best when the request is shaped to the task **mode**. Pick the mode, state it explicitly, and
use its sections. (Source: agy self-report, 2026-06-16; cross-ref capability profile §A/§B/§F.)

- **Critical review / red-team** — *"Just REPLY on the bus — do NOT edit"* (or the REVIEW-ONLY banner).
  Sections: `### Goal` · `### Files in Scope` (exact paths) · `### Invariants to Verify` · `### Guardrails`.
  Tell agy *what to check against*, not "find bugs": e.g. **"Verify these 3 invariants; if they hold,
  say 'No issues found'; ignore style nits"** (open "find any bugs" → hallucinated over-escalation, §B).
- **Generative / divergent design** — *"Brainstorming mode. High-level architecture. No implementation code."*
  Sections: `### Current Design` · `### The Problem/Limitation` · `### Options Already Explored` ·
  `### Desired Output`. Paste the core interface/types inline; list discarded ideas so agy won't re-propose
  them. Ask **"Propose 2 alternatives to [Problem], simpler/stronger than [Current]"**, not "make this better".
- **Scoped implementation** — *"Implementation mode. Edit files directly; run the verification command before reporting done."*
  Sections: `### Goal` · `### Files to Edit` · `### Reference Context` · `### Verification Steps`. Provide
  interfaces/types from *other* files agy must interact with but not edit (saves discovery calls). Target by
  **function name / exact snippet, never line numbers** (its edit tools need exact string matches).
- **Async shell orchestration** — *"Orchestration mode. Launch the background task and await your reactive wakeup."*
  Sections: `### Command` · `### Working Directory` · `### Success Criteria`. e.g. **"Launch `cargo test`
  as an async background task; rely on your reactive wakeup when it finishes; do not poll; report the failed
  test names."** Include required env + exact cwd.
  - **Slow vs quick:** for a genuinely slow task (build/test suite) use the async/wakeup flow above; for a
    *quick* command (fast linter, syntax check) tell agy to run it **synchronously** — it controls this via
    its `RUN_COMMAND` `WaitMsBeforeAsync` (ms; e.g. "wait ~5000ms before backgrounding"), avoiding a
    needless wakeup round-trip.
  - **Bound long tasks:** for a long background task or sub-agent, ask agy to set a wake/`schedule`
    bounding timer (its `TimerCondition` param) so a silently-dead task doesn't hang forever.

### What Claude most often gets wrong (agy's top 3 — fix these)

1. **Line numbers instead of snippets.** agy's `multi_replace_file_content` needs *exact string matches*;
   line numbers drift and the edit fails. Give function names or exact snippets to target.
2. **Assuming shared context.** Separate context windows — agy is blind to what Claude just read. Paste
   the relevant trace/snippet/types into the request payload; never "fix the error we just saw".
3. **"Find bugs" unscoped discovery.** agy is worktree-blind; this burns its context on dozens of
   `list_dir`/`view_file` calls. Give specific files **and** specific invariants to check.
4. **Parallelizing edits to the same file.** agy *can* run tools concurrently (good — front-load
   targets, see DO), but **multiple edit calls against the same file race and corrupt it.** For several
   scattered edits in one file, tell agy to use a **single `multi_replace_file_content` call with
   multiple chunks**, not parallel edit calls. (agy self-report; sound concurrency guard.)

**Scoping:** one focused task, or a few closely-related ones ("add endpoints A, B, C to `api.rs`").
Don't batch disparate/complex work or anything touching >5 files — split into sequential phases
(rule of thumb: one focused PR's worth per request).

**Clarify / cancel:** agy reads the bus **only at the start of a turn** — it cannot ingest new
instructions mid-turn. To pivot: `clavity cancel` (Escape) + an `alert` `[req_id=…] cancel`, let it
return to idle, then send the new request.

**Reply envelope** agy returns (`type=response`, `replyTo` = your request's signal id):
```
[req_id=<id>] done: <one-line summary>
checkpoint=<sha|clean|none>

### Changes Made
- <files changed + what>
### Verification
- <commands run + outcomes>
### Notes/Issues
- <warnings / follow-ups / blockers>
```
On failure it leads with `[req_id=<id>] failed: <reason>`. A `[ping]` gets just `[req_id=<id>] READY`.

## Send a request and await the reply — `clavity ask`

The whole round-trip is **one command**: mint id → send on the bus → ring → block for the correlated
reply → print its `content` (exit 0). Exit 1 on timeout, 2 if the agentmemory daemon is unreachable.

```bash
clavity ask "<self-contained instruction for agy>"              # default: to=agy, type=request, rings
clavity ask --review-only "<review/red-team request>"           # prepend the no-edit banner (below)
clavity ask --no-ring "<instruction>"                           # agy is mid-turn; don't ring
clavity ask --timeout 300 "<long task>"                         # widen the deadline
```

`ask` correlates the reply by `replyTo` (it knows the request's signal id, since it sent it) **and**
by the `[req_id=…]` echo, scoped to the request's thread — so it consumes only the awaited reply,
never agy's request or unrelated inbox traffic. The reply `content` is returned directly.

> **Do NOT detect replies by pane-scraping or hand-rolled polling.** Specifically: do **not**
> `clavity capture | grep <req_id>` in a timer loop, and do **not** hand-roll a
> `memory_signal_read(agentId=claude, unreadOnly=true)` poll loop to find the reply. Both are fragile
> (racing pane redraws / consuming unrelated unread). `clavity ask` (or `await-reply`) is the one true
> path and is **authoritative** — when you use it, don't *also* `memory_signal_read` the same reply
> (the direct return replaces that read).

**Just want to block for a reply you've already sent** (e.g. you sent via the MCP tool and need to
wait)? Use `clavity await-reply --req-id <id> [--timeout N]` — it blocks until the correlated reply
arrives and prints its content (exit 1 on timeout).

**On timeout:** capture context with `clavity capture` (what agy was doing) and report a typed
timeout. Do not silently assume failure. If the pane shows a transient backend error (e.g. agy's
"high traffic" message), agy aborted to idle with no reply — wait ~1 min, then **re-`ask`** (a fresh
req-id; the old request was likely consumed when agy read its inbox, so re-ringing alone won't
re-surface it). (See `docs/agy-assumptions.md` → "Transient runtime gotchas".)

> **Manual fallback** (bus or `ask` unavailable): `clavity req-id "<instruction>"` → `memory_signal_send(from="claude", to="agy", type="request", content=<envelope>)` (record the returned signal `id`) → `clavity ring` → `clavity await-reply --req-id <id>`.

### REVIEW-ONLY banner (the `--review-only` convention)

For review / red-team delegations where agy must **not** edit or commit, `clavity ask --review-only`
prepends this canonical banner to the instruction (agy honors it, replying `Changes Made: None`):

```
╔══════════════════════════════════════════════╗
║  REVIEW ONLY — DO NOT EDIT, DO NOT COMMIT.    ║
║  No file writes. No git stage/commit/push.    ║
║  Output is a written verdict ONLY.            ║
╚══════════════════════════════════════════════╝
```

This is the easy, consistent form of the "Just REPLY on the bus — do NOT write or edit files" rule
above. The wording is stored as a constant in `src/main.rs` (`REVIEW_ONLY_BANNER`); keep the two in sync.

## Cancel an in-flight task
- **`clavity cancel`** interrupts agy's *current* turn (sends `Escape` — agy's busy footer reads
  "esc to cancel"). This is the way to stop work already in progress.
- Also post `memory_signal_send(from="claude", to="agy", type="alert", content="[req_id=<id>] cancel")`
  so the responder skips the task if it hasn't started — but the responder only reads the bus at the
  **start** of a turn, so a mid-task alert isn't seen until the turn ends. Hence `clavity cancel` for
  in-progress work; the `alert` for not-yet-started work.

## Notes
- **Payloads always go on the bus**, never in the doorbell — keeps `send-keys` to a short, fixed,
  escaping-safe line (verified: special chars survive, but the bus avoids the question entirely).
- **Long tasks:** the responder emits `type="info"` progress signals; surface them, or
  `capture-pane` to watch live.
- **Failover:** if the bus or psmux is unavailable, fall back to relaying between Claude and agy **by
  hand** — paste messages into agy's watch tab and paste its replies back. Slower, but dependency-free.
- **Teardown:** `clavity stop` kills the psmux session when you're done, so agy doesn't orphan.
- **agy's file-write scope is config-gated (default = workspace-only).** agy's native edit tools are
  themselves path-agnostic (absolute path + OS permissions), but the Antigravity CLI **wrapper gates
  writes to the workspace by default** — outside paths are rejected (observed: `artifacts must be in
  …/brain/…`, project-audit logs; empirical assumption #8). So by default, **frame requests against
  the launch folder.** To let agy write *outside* it, **widen the wrapper** — enable
  `allowNonWorkspaceAccess`, pass `--add-dir`, or add to `trustedWorkspaces[]` — rather than forcing a
  shell fallback (shell is the last resort, not the fix). Full reconciliation: capability profile
  **Axis D** ([`agy-capabilities.md`](agy-capabilities.md)).
- This runbook can later be promoted to a harness skill so Claude invokes it automatically.
