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
bootstrap, which `clavity start` does for you.

clavity is a **single self-contained Rust binary** — no runtime, no interpreter, no scripts. Drop
`clavity.exe` on your `PATH` next to `tmux.exe`/`psmux.exe`.

> **Not** a re-spawning bridge. If you want the isolated, one-shot "delegate a task to a throwaway
> headless sub-agent" pattern, that's a different tool. clavity drives the *real, running* `agy` you
> already have open.

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
         │ 2. clavity ring   (psmux send-keys "<doorbell>")            │
         │ ───────────────────────────────────────────────────────────►  (wakes agy)
         │                                                              │ 3. read own inbox
         │                                                              │ 4. git stash checkpoint
         │                                                              │ 5. act in the LIVE folder
         │ ◄───────────────────────────────────────────  bus  ◄────────┤ 6. reply (response/info)
         ▼                                                              ▼ 7. return to idle (free)
```

The full design — including the empirical spikes it rests on (bus round-trip, `send-keys` wake,
idle/busy detection, doorbell-while-busy queueing, the pwsh shell reality) — is in
[`docs/superpowers/specs/2026-06-16-agy-remote-control-design.md`](docs/superpowers/specs/2026-06-16-agy-remote-control-design.md).
The Claude-side procedure is in
[`docs/agy-remote-control-protocol.md`](docs/agy-remote-control-protocol.md).

## The `clavity` binary

| Subcommand | Role |
| --- | --- |
| `clavity state` | Print pane state: `idle` / `busy` / `dead`. |
| `clavity capture` | Print the visible pane content (for observing agy live). |
| `clavity wait-idle [--timeout N]` | Block until agy is idle (exit 0) or timeout (exit 1). |
| `clavity ring [--no-idle-gate] [--doorbell S]` | Idle-gate, then send the doorbell to wake agy. |
| `clavity req-id [INSTRUCTION]` | Mint a request id, or wrap an instruction in the `[req_id=..]` envelope. |
| `clavity start [FOLDER] [claude flags…]` | Launch agy (in a psmux session) **and** Claude Code in the same folder. Also the **default** action — bare `clavity [FOLDER] [flags…]` runs this. |

Internally: `src/tmux.rs` (**C3** — psmux primitives + footer/activity state detection) and
`src/bus.rs` (**C5** — the bus id/envelope conventions). The `agy`-side responder skill is
`agy_skills/claudavity-responder/SKILL.md` (**C2/C4** — read inbox → non-intrusive `git stash`
checkpoint → act → reply → return to idle).

stdout carries machine-readable results; diagnostics go to stderr via `tracing`
(`RUST_LOG=clavity=debug` for verbose).

## Prerequisites

- **Windows** (psmux/PowerShell-oriented; `agy`'s shell tool runs **pwsh**).
- **[Claude Code](https://claude.com/claude-code)** with the **agentmemory** MCP server configured
  (provides `memory_signal_send` / `memory_signal_read`).
- **`agy`** (Antigravity CLI), signed in, also with agentmemory available.
- **[psmux](https://github.com/psmux/psmux)** (ships as `psmux`/`pmux`/`tmux`).
- **Rust** (`cargo`) to build.

## Build & install

```bash
cargo build --release
# put the binary on PATH, e.g. next to your psmux:
cp target/release/clavity.exe "C:/!PORTABLES/!BIN/"
```

## Setup

1. **Install the responder skill** into agy's skills dir, and add a pointer in your `GEMINI.md`:
   ```pwsh
   Copy-Item -Recurse agy_skills/claudavity-responder `
     "$HOME/.gemini/antigravity-cli/skills/claudavity-responder"
   ```
   (See the design spec for the exact GEMINI.md pointer text. The responder runs `agy`'s shell —
   which is **pwsh** — so its checkpoint command is PowerShell, not bash.)

2. **Launch both agents in a folder** (run from your normal pwsh so `agy` is signed in). `start` is
   the default action, so you can omit it:
   ```pwsh
   clavity C:\path\to\project              # folder (bare = start)
   clavity -c                              # current folder; forwards `-c` (continue) to claude
   clavity C:\path\to\project --resume     # folder + flags forwarded to claude
   clavity start C:\path                   # explicit form, identical to the above
   ```
   The first non-dash argument is the folder; everything else is forwarded to `claude`. agy's own
   flags come from `$env:AGY_START_ARGS` (default `--dangerously-skip-permissions`). Session name
   defaults to `claude_agy` (override via `$env:AGY_SESSION`); psmux path via `$env:AGY_TMUX_BIN`.

3. From Claude, drive agy via the protocol runbook: put a request on the bus, `clavity ring`, then
   await the reply on the bus. Watch agy live anytime:
   ```pwsh
   tmux attach -t claude_agy   # detach with Ctrl-b d
   ```

## Tests

```bash
cargo test          # pure-logic unit tests (state classifier, activity detection, bus conventions)
cargo clippy --all-targets
```

The unit tests pin the verified behavior; the end-to-end behavior (doorbell → checkpoint → reply)
was validated live against a real `agy` session and is documented in the spec.

## Status

Built and verified end-to-end against a live `agy` session, including the autonomous safety
checkpoint. Windows-first; the bus/skill pieces are portable, the psmux/pwsh pieces are not.

## License

MIT — see [LICENSE](LICENSE).
