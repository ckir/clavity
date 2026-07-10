# agy classic transport — psmux + agentmemory bus mechanics

**This is the classic (psmux/bus) transport manual** — the driver-specific companion to the agnostic
[`../plugin/knowledge/agy-assumptions.md`](../plugin/knowledge/agy-assumptions.md)
manual. That file states version-agnostic peer-truth about agy itself; this file states how
**clavity-classic specifically** reaches agy — the psmux verbs, the agentmemory bus REST schema, the
doorbell/footer-marker mechanics, and the env knobs that tune them. If clavity-classic misbehaves (or
before you change anything psmux/bus-facing), read this alongside the agnostic manual.

## Quick re-verification playbook (run these first)

1. `clavity doctor` — tmux/claude/agy on PATH + session reachable.
2. `clavity capture --viewport` while agy is **idle**, then again while it's **generating** — confirm
   the idle/busy footer markers.
3. **Bus ping:** `memory_signal_send(from=claude,to=agy,type=request,content="[req_id=x] [ping]")` →
   `clavity ring` → `memory_signal_read(agentId=claude)` expects `[req_id=x] READY`.
4. agy's own logs: `~/.gemini/antigravity-cli/cli.log` and `~/.gemini/antigravity-cli/log/`.

## Transport-specific assumptions

| # | Assumption | Why clavity-classic needs it | Re-verify | Fix / knob if it changed |
|---|------------|----------------------|-----------|--------------------------|
| 2 | **psmux verbs**: `has-session -t`, `capture-pane -p [-S -]`, `send-keys -t -l` + key names (`Enter`/`Escape`/`C-u`), `new-session -d -s -c` | All of `src/tmux.rs` | `tmux -V`; `clavity doctor`; `tmux capture-pane -p -S - -t claude_agy` | `AGY_TMUX_BIN` to point at a different binary; adjust `src/tmux.rs` if verbs/flags changed |
| 3 | **Footer markers**: idle = `? for shortcuts`, busy = `esc to cancel` | Idle/busy state detection (`clavity state`, `ring` idle-gate) | `clavity capture --viewport` idle vs generating | `AGY_IDLE_MARKER` / `AGY_BUSY_MARKER`; the marker-free **activity fallback** in `pane_state` keeps working regardless |
| 4 | **Cancel key = `Escape`** (busy footer literally says "esc to cancel") | `clavity cancel` | Check the busy footer wording | Change the key in `Cmd::Cancel` dispatch (`src/main.rs`) |
| 7 | **`send-keys` reaches the prompt; a doorbell sent while busy is QUEUED** (not interleaved) | The whole doorbell mechanism + `ring` being safe even if mistimed | Ring while agy is busy; confirm it processes sequentially | If queueing breaks, make `ring` strictly idle-gate (it already clears the line with `C-u` first) |
| 10 | **agentmemory bus**: `memory_signal_send`/`memory_signal_read`; reading an agent's inbox **consumes its unread**; `threadId` filter exists; types `info/request/response/alert`; agentIds `claude`/`agy` | The entire data channel | A bus ping round-trip (playbook #3) | Conventions live in `src/bus.rs` + the protocol doc; read by `threadId` to avoid consuming unrelated unread |
| 11 | **A psmux session outlives agy** — agy is launched into a pwsh pane, so when agy *exits* (with the tab still open) the pane falls back to the shell and the **session persists with no agy** | Why `start` checks `agy_running` (pane's `#{pane_current_command}`), not just `has_session`, before reusing; and re-attaches a watch tab via `#{session_attached}` | `tmux display-message -p -t <s> '#{pane_current_command}'` → `agy` vs `pwsh`; `'#{session_attached}'` → `1`/`0` | `start` relaunches agy in a stale session and reuses only a live one (`src/main.rs`) |
| 12 | **Closing agy's terminal TAB kills the whole session** — on this psmux/Windows build the server exits when the hosting terminal is closed (it does *not* keep a detached session alive like real tmux). So `has_session` → false and `state` → `dead`. | Distinguishes *closing the tab* (session dies → next `clavity start` is a fresh launch) from *detaching* (`Ctrl-b d`, session survives) and from *agy exiting* (#11, session survives as a shell). | Close the watch tab, then `clavity state` → `dead`; `tmux has-session` → "no server running" | None needed — `start` correctly does a fresh launch when dead. To keep agy alive while hiding it, **detach** (`Ctrl-b d`) instead of closing the tab. |
| 13 | **agentmemory daemon REST API** on `http://127.0.0.1:3111` (`AGENTMEMORY_URL` override): `POST /agentmemory/signals/send` (JSON `{from,to,content,type?,replyTo?,threadId?}`, req `from`+`content` → `201 {success,signal:{id,from,to,content,type,threadId,replyTo,createdAt}}`); `GET /agentmemory/signals?agentId=&unreadOnly=&threadId=&limit=` → `{success,signals:[…]}`; `GET /agentmemory/health` (public). **Reading marks `to===agentId` unread signals read (consume); reading from the SENDER's view (`agentId=<from>`) does NOT mark read.** Bearer auth only when `AGENTMEMORY_SECRET` is set. | `clavity await-reply` / `ask` / `ping` talk to this daemon directly (out-of-band from the MCP tools) — see `src/membus.rs`. | `curl http://127.0.0.1:3111/agentmemory/health` → `{"status":"healthy",…}`; round-trip: `POST …/signals/send` then `GET …/signals?agentId=<from>` and confirm the schema/`readAt` behavior above. | `AGENTMEMORY_URL` / `AGENTMEMORY_SECRET` env (read in `src/membus.rs`). If routes/schema change, the daemon's full route list is in agentmemory's `src/triggers/api.ts` (compiled into `dist/index.mjs`; grep `api_path`). Bus conventions (req-id, envelope) stay in `src/bus.rs`. |

## How `await-reply` / `ask` read without clobbering inboxes (read-state decision)

The read endpoint **consumes** (`readAt`) any unread signal whose `to` equals the queried `agentId`,
and there is **no peek flag**. clavity resolves this by **always reading `agentId=claude` scoped by
`threadId`** — so the consume hits **only the awaited reply** in that thread, never agy's request (it
is `to=agy`, untouched) and never unrelated inbox traffic. Both commands have the threadId: `ask`
*sent* the request and got it back; **`await-reply` takes a required `--thread-id`** (the master passes
the `threadId` from its own `memory_signal_send` response). **There is no unscoped path** — no thread,
no read. Correlation matches on `replyTo == <request signal id>` **OR** `[req_id=<ID>]` in `content`
(`bus::extract_req_id`). The reply `content` is returned directly, so it is **authoritative** — do
**not** also `memory_signal_read(agentId=claude)` the same reply (the direct return replaces it).

> Two alternatives were rejected (agy design consult): clavity-side **thread discovery**
> and a **sender-view poll** (`agentId=agy`) both require an *unscoped* `agentId=agy` read, which marks
> *all* unread `to=agy` signals read — if clavity polls before agy's own `unreadOnly` read, it
> **consumes agy's pending request** and the round-trip hangs. Passing the threadId the master already
> has avoids touching agy's inbox entirely.

## agentmemory daemon flap (bus-side gotcha, not a clavity bug)

**The agentmemory daemon (`:3111`) can flap up/down within seconds.** Observed during one live test
the daemon went up → down → up → down across consecutive `ping`/`ask` calls (seconds apart). When
down, the REST health check fails (`os error 10060`, connection timeout) and `ask`/`await-reply`/`ping`
**fail-fast with exit 2 and `agentmemory daemon unreachable at …`** — by design (the `MemBus::health()`
preflight), **not a hang and not a clavity bug**. The same process also serves agy's MCP bus, so a flap
can disrupt agy mid-turn too.

- **Diagnose:** `curl http://127.0.0.1:3111/agentmemory/health` a few times — alternating `200` /
  timeout confirms flapping (vs. steadily down = daemon dead/restarting).
- **Recover:** it usually self-heals in seconds; just **retry** when health returns `200` (a short
  probe-until-200 loop before the call works well). If it stays down, restart the agentmemory daemon.
- Related: the daemon being load-bearing for `ask`/`await-reply`/`ping` is the bus assumption above;
  the agnostic capability profile's routing-risk axis also flags quota/backend lockouts generally.

## All the knobs (so a fix is usually config, not code)

`AGY_SESSION`, `AGY_TMUX_BIN`, `AGY_DOORBELL`, `AGY_IDLE_MARKER`, `AGY_BUSY_MARKER`, `AGY_START_ARGS`,
`AGY_WATCH`, `AGENTMEMORY_URL`, `AGENTMEMORY_SECRET`, `RUST_LOG` (see the README's Configuration table).
Behavior that *isn't* env-tunable lives
in `src/tmux.rs` (psmux), `src/bus.rs` (bus), `src/platform.rs` (per-OS), and
`agy_skills/claudavity-responder/SKILL.md` (agy-side protocol incl. the shell-specific checkpoint).

## Deferred / known gaps (transport-specific)

Not yet addressed — candidates if you're improving robustness: **bus has no auth** (any bus writer can
command agy in the live tree); **multi-folder collision** (two agy instances share `agentId="agy"` —
needs session-scoped ids).
