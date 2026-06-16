# agy Remote Control — Claude-side orchestration protocol (C1)

The procedure Claude follows to drive the live, signed-in `agy` session in the same folder.
Transport is the **agentmemory signal bus** (Claude's own `memory_signal_send` / `memory_signal_read`
MCP tools) for payloads; the **doorbell** (`agy_tmux.py`) wakes agy. Pure conventions live in
`agy_bus.py`; psmux primitives in `agy_tmux.py`. See the design spec at
`docs/superpowers/specs/2026-06-16-agy-remote-control-design.md`.

> **Correctness rests on the bus, not the TUI.** State detection (idle/busy) is best-effort and
> never load-bearing — a misread only affects ordering, because a doorbell sent while agy is busy is
> safely queued and processed as the next turn.

## Preconditions (bootstrap — one human step per session)
1. A human has started the session, signed in, in the target folder. Easiest is the launcher
   (on PATH at `C:\!PORTABLES\!BIN\`, source in this repo): **`start-claudavity.ps1 <folder>`** —
   it starts agy in the `claude_agy` psmux session (skip-permissions) *and* Claude Code in the same
   folder. Manual equivalent: `C:\!PORTABLES\!BIN\tmux.exe new-session -s claude_agy -c <folder>`
   then `agy --dangerously-skip-permissions` (or `agy --continue`).
2. Verify reachability: `uv run python agy_tmux.py state` → expect `idle`/`busy` (not `dead`).
   If `dead`, ask the human to bootstrap; do not proceed.

## Send a request and await the reply
1. **Mint id + envelope** (`agy_bus`): `req_id = new_req_id()`;
   `content = make_request(req_id, "<self-contained instruction for agy>")`.
2. **Put it on the bus:** call `memory_signal_send(from="claude", to="agy", type="request",
   content=content)`. **Record the returned signal `id`** (`request_signal_id`) — it is the robust
   correlation key.
3. **Ring the doorbell:** `uv run python agy_tmux.py ring` (idle-gated; sends the canonical
   doorbell). The doorbell carries no payload — agy reads the request from its inbox.
4. **Await the response** (bounded loop, e.g. ≤ `timeout` seconds, poll every ~2–3 s):
   - `memory_signal_read(agentId="claude", unreadOnly="true")` — **only your own inbox** (reading
     another agent's inbox consumes its unread state).
   - Find the match with `agy_bus.match_response(signals, req_id, request_signal_id)` — matches on
     `replyTo == request_signal_id` (robust) or the `req_id` echoed in `content` (fallback).
   - On match → return it. On no match → liveness-check `agy_tmux.py state`; if `dead`, abort with
     "agy session down — re-bootstrap"; else keep waiting until the deadline.
5. **On timeout:** capture context with `uv run python agy_tmux.py capture` (what agy was doing) and
   report a typed timeout. Do not silently assume failure.

## Cancel an in-flight task
- Send `memory_signal_send(from="claude", to="agy", type="alert", content="[req_id=<id>] cancel")`
  (the responder checks for an `alert`/cancel at the top of its turn), and/or interrupt the pane:
  `tmux send-keys -t claude_agy C-c`.

## Notes
- **Payloads always go on the bus**, never in the doorbell — keeps `send-keys` to a short, fixed,
  escaping-safe line (verified: special chars survive, but the bus avoids the question entirely).
- **Long tasks:** the responder emits `type="info"` progress signals; surface them, or
  `capture-pane` to watch live.
- **Failover:** if the bus or psmux is unavailable, fall back to the file relay
  (`CLAUDE-TO-ANTIGRAVITY.md` / `ANTIGRAVITY-TO-CLAUDE.md`, human-couriered).
- This runbook can later be promoted to a harness skill so Claude invokes it automatically.
