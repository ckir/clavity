# clavity — a remote control for Antigravity (agy)

**clavity** lets [Claude Code](https://claude.com/claude-code) drive a **live, signed-in
[Antigravity](https://pypi.org/project/google-antigravity/) (`agy`) CLI session running in the same
folder** — an ongoing, bidirectional, stateful collaboration where `agy` works directly in the live
working tree as a peer. No headless re-spawning, no polling, no idle token cost.

It combines two off-the-shelf channels:

- **Doorbell (wake):** Claude injects a short instruction into `agy`'s real terminal via
  [`psmux`](https://github.com/psmux/psmux) `send-keys`, waking the live session **on demand**.
- **Bus (data):** structured request/response payloads travel over the **agentmemory** signal bus
  (`memory_signal_send` / `memory_signal_read`), addressed `claude` ↔ `agy`.

`agy` sleeps at its prompt for free between doorbells. The only manual step is a one-time-per-session
bootstrap: start `agy` inside a named `psmux` session (the included launcher does this).

> **Not** a re-spawning bridge. If you want the isolated, one-shot "delegate a task to a throwaway
> headless sub-agent" pattern, that's a different tool. clavity is about driving the *real, running*
> `agy` you already have open.

---

## How it works

```
                       same folder (live working tree)
  ┌──────────────┐                                        ┌─────────────────────────────┐
  │  Claude Code │                                        │  psmux session "claude_agy" │
  │  (master)    │                                        │   └ live, signed-in agy     │
  └──────┬───────┘                                        └───────────┬─────────────────┘
         │ 1. memory_signal_send(to=agy, type=request, <payload>)     │
         │ ───────────────────────────────────────────►  agentmemory  │
         │                                                signal bus    │
         │ 2. psmux send-keys -t claude_agy "<doorbell>" Enter         │
         │ ───────────────────────────────────────────────────────────►  (wakes agy)
         │                                                              │ 3. read own inbox
         │                                                              │ 4. git stash checkpoint
         │                                                              │ 5. act in the LIVE folder
         │ ◄───────────────────────────────────────────  bus  ◄────────┤ 6. reply (response/info)
         ▼                                                              ▼ 7. return to idle (free)
```

The whole design — including the empirical spikes it rests on (bus round-trip, `send-keys` wake,
idle/busy detection, doorbell-while-busy queueing, the pwsh shell reality) — is written up in
[`docs/superpowers/specs/2026-06-16-agy-remote-control-design.md`](docs/superpowers/specs/2026-06-16-agy-remote-control-design.md).
The Claude-side procedure is in
[`docs/agy-remote-control-protocol.md`](docs/agy-remote-control-protocol.md).

## Components

| File | Role |
| --- | --- |
| `agy_tmux.py` | **C3** — psmux primitives: `has_session`, `capture`, footer/activity state detection (`idle`/`busy`/`dead`), `send_keys`, idle-gated `ring_doorbell`; plus a `state`/`capture`/`wait-idle`/`ring` CLI. |
| `agy_bus.py` | **C5** — pure agentmemory-bus conventions: request-id minting, the `[req_id=...]` envelope, response correlation (`replyTo`-preferred, content-echo fallback). |
| `agy_skills/claudavity-responder/SKILL.md` | **C2** — the `agy`-side responder skill: read inbox → non-intrusive `git stash` checkpoint → act → reply → return to idle. Install into agy's skills dir. |
| `start-claudavity.ps1` | One-shot launcher: starts `agy` in a `psmux` session **and** Claude Code in the same folder. |
| `docs/` | Protocol runbook + full design spec. |

## Prerequisites

- **Windows** (this is psmux/PowerShell-oriented; `agy`'s shell tool runs **pwsh**).
- **[Claude Code](https://claude.com/claude-code)** with the **agentmemory** MCP server configured
  (provides `memory_signal_send` / `memory_signal_read`).
- **`agy`** (Antigravity CLI), signed in, also with agentmemory available.
- **[psmux](https://github.com/psmux/psmux)** (ships as `psmux`/`pmux`/`tmux`).
- **[uv](https://docs.astral.sh/uv/)** for running the tests.

## Setup

1. **Install the responder skill** into agy's skills dir, and add a pointer in your `GEMINI.md`:
   ```pwsh
   Copy-Item -Recurse agy_skills/claudavity-responder `
     "$HOME/.gemini/antigravity-cli/skills/claudavity-responder"
   ```
   (See the design spec for the exact GEMINI.md pointer text. The responder runs `agy`'s shell —
   which is **pwsh** — so its checkpoint command is PowerShell, not bash.)

2. **Launch both agents in a folder** (run from your normal pwsh so `agy` is signed in):
   ```pwsh
   start-claudavity.ps1 C:\path\to\project          # folder
   start-claudavity.ps1 C:\path\to\project --resume # extra args forward to claude
   ```
   The first non-dash argument is the folder; everything else is forwarded to `claude`. agy's own
   flags come from `$env:AGY_START_ARGS` (default `--dangerously-skip-permissions`). Session name
   defaults to `claude_agy` (override via `$env:AGY_SESSION`); psmux path via `$env:AGY_TMUX_BIN`.

3. From Claude, drive agy by following the protocol runbook: put a request on the bus, ring the
   doorbell (`uv run python agy_tmux.py ring`), and await the reply. Watch agy live anytime:
   ```pwsh
   tmux attach -t claude_agy   # detach with Ctrl-b d
   ```

## Tests

```bash
uv run pytest -q          # pure-logic unit tests (state classifier, activity, bus conventions)
uv run ruff check .
```

The unit tests pin the verified behavior; the end-to-end behavior (doorbell → checkpoint → reply)
was validated live against a real `agy` session and is documented in the spec.

## Status

Built and verified end-to-end against a live `agy` session, including the autonomous safety
checkpoint. Windows-first; the bus/skill pieces are portable, the psmux/pwsh pieces are not.

## License

MIT — see [LICENSE](LICENSE).
