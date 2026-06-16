# clavity

[![CI](https://github.com/ckir/clavity/actions/workflows/ci.yml/badge.svg)](https://github.com/ckir/clavity/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Built with Rust](https://img.shields.io/badge/built%20with-Rust-orange.svg)](https://www.rust-lang.org/)
![Platform: Windows](https://img.shields.io/badge/platform-Windows-blue.svg)

**A remote control for [Antigravity](https://pypi.org/project/google-antigravity/) (`agy`).**
clavity lets [Claude Code](https://claude.com/claude-code) drive a **live, signed-in `agy` session
running in the same folder** — an ongoing, bidirectional, stateful collaboration where `agy` works
directly in the live working tree as a peer. No headless re-spawning, no polling, no idle token cost.

It is a **single self-contained Rust binary** — no runtime, no interpreter, no scripts — that you
drop on your `PATH` next to `tmux`/`psmux`.

> **Not** a re-spawning bridge. If you want the isolated, one-shot "delegate a task to a throwaway
> headless sub-agent" pattern, that's a different tool. clavity drives the *real, running* `agy` you
> already have open.

---

## Contents

- [How it works](#how-it-works)
- [Quick start](#quick-start)
- [Command reference](#command-reference)
- [Configuration](#configuration)
- [Design docs](#design-docs)
- [Platform support](#platform-support)
- [Contributing](#contributing)
- [License](#license)

---

## How it works

clavity combines two off-the-shelf channels:

- **Doorbell (wake):** Claude injects a short instruction into `agy`'s real terminal via
  [`psmux`](https://github.com/psmux/psmux) `send-keys`, waking the live session **on demand**.
- **Bus (data):** structured request/response payloads travel over the **agentmemory** signal bus
  (`memory_signal_send` / `memory_signal_read`), addressed `claude` ↔ `agy`.

`agy` sleeps at its prompt for free between doorbells; Claude only wakes it when there is work.

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

State detection is defense-in-depth and never load-bearing: correctness rests on the bus and on
`has-session`; a doorbell sent while agy is busy is safely queued and processed as the next turn.

---

## Quick start

### Prerequisites

- **[agentmemory](https://www.npmjs.com/package/@agentmemory/agentmemory) MCP server** — the shared
  signal bus (`memory_signal_send` / `memory_signal_read`) that **both** Claude and agy connect to.
  This is clavity's data channel; **nothing works without it.** Configure the *same* agentmemory
  store as an MCP server in **both** Claude Code and agy (it runs a shared daemon, default `:3111`).
- **[Claude Code](https://claude.com/claude-code)** — the master agent, with agentmemory configured.
- **`agy`** (Antigravity CLI) — signed in, with agentmemory configured too.
- **[psmux](https://github.com/psmux/psmux)** (ships as `psmux`/`pmux`/`tmux`) on your `PATH`.
- **Rust** (`cargo`) to build — or grab a release binary.
- Currently **Windows** (see [Platform support](#platform-support)).

### 1. Wire up the agentmemory bus (both agents)

clavity's data channel is the shared agentmemory store, so the **same** MCP server must be
registered in **both** Claude Code and agy, pointing at the same daemon (default `:3111`). The
reference setup on a working machine:

**Claude Code** — `claude mcp add agentmemory -s user -- npx @agentmemory/agentmemory mcp`, i.e. in
`~/.claude.json` under `mcpServers`:
```json
"agentmemory": { "type": "stdio", "command": "npx", "args": ["@agentmemory/agentmemory", "mcp"] }
```

**agy** — in `~/.gemini/config/mcp_config.json` under `mcpServers` (on Windows a bare `npx` must be
launched via `cmd /c`):
```json
"agentmemory": { "command": "cmd", "args": ["/c", "npx", "@agentmemory/agentmemory", "mcp"] }
```

Restart each agent after editing its config. Verify Claude sees the bus (the
`memory_signal_send` / `memory_signal_read` tools are available); `clavity doctor` does not check
this, so confirm it once during setup.

### 2. Build & install

```bash
cargo build --release
# put it on PATH, e.g. next to your psmux:
cp target/release/clavity.exe "C:/!PORTABLES/!BIN/"   # Windows
# cp target/release/clavity   ~/.local/bin/            # elsewhere
```

### 3. Install the agy-side responder skill

**`clavity start` auto-installs/refreshes this skill** into `~/.gemini/antigravity-cli/skills/` on
every launch (it's embedded in the binary), so you normally don't copy it by hand. You do still need
a **one-time pointer in your `GEMINI.md`** so agy reliably invokes it — exact text is in the
[design spec](docs/superpowers/specs/2026-06-16-agy-remote-control-design.md).

The responder makes a **non-intrusive `git stash` checkpoint** before editing the live tree, then
replies on the bus; a `[ping]`-only request is fast-pathed (READY, no checkpoint). On Windows its
checkpoint command is **PowerShell** (agy's shell is pwsh). To install it manually anyway:
```pwsh
Copy-Item -Recurse agy_skills/claudavity-responder `
  "$HOME/.gemini/antigravity-cli/skills/claudavity-responder"
```

> **Note:** agy reads the skill once per session and caches it, so a *running* agy won't see skill
> edits until its next restart.

### 4. Launch both agents in a folder

Run from your normal shell so `agy` inherits your signed-in session. `start` is the default action,
so you can omit it:

```pwsh
clavity C:\path\to\project           # folder (bare = start)
clavity -c                           # current folder; forwards -c (continue) to claude
clavity C:\path\to\project --resume  # folder + flags forwarded to claude
clavity start C:\path                # explicit form, identical
```

The first non-dash argument is the folder; everything else is forwarded verbatim to `claude`.
**On first launch a visible "watch" tab opens** (Windows Terminal) attached to agy, so you can
answer agy's auth/login prompts — it asks fairly often. Disable with `AGY_WATCH=0`. You can also
attach manually anytime: `tmux attach -t claude_agy` (detach with `Ctrl-b d`).

### 5. Drive agy from Claude

Follow the [protocol runbook](docs/agy-remote-control-protocol.md): mint a request, put it on the
bus, ring the doorbell, await the reply.

> **After launch, give agy a moment.** It loads its MCP servers (agentmemory included) a few seconds
> after starting, and `clavity state` can read `idle` before that finishes. Gate your first task on a
> **bus readiness ping** (ping → `clavity ring` → wait for the reply, retry) — see the runbook. The
> manual equivalent is typing `list your active mcp servers` in the watch tab and seeing `agentmemory`.

```bash
clavity req-id "refactor foo() to return Result"   # -> [req_id=req-..] refactor ...
# (Claude) memory_signal_send(from=claude, to=agy, type=request, content=<that envelope>)
clavity ring                                        # wake agy
clavity state                                       # idle | busy | dead
# (Claude) memory_signal_read(agentId=claude, unreadOnly=true)  -> agy's reply
```

---

## Command reference

| Command | Description |
| --- | --- |
| `clavity [FOLDER] [claude flags…]` | **Default** = `start`. Launch agy (psmux) + Claude Code in the folder. |
| `clavity start [FOLDER] [claude flags…]` | Explicit form of the above. |
| `clavity state` | Print pane state: `idle` / `busy` / `dead`. |
| `clavity capture [--lines N] [--viewport]` | Print agy's pane — **full scrollback** by default, last `N` lines with `--lines`, or just the visible viewport with `--viewport`. |
| `clavity wait-idle [--timeout N]` | Block until idle (exit 0) or timeout (exit 1). |
| `clavity ring [--no-idle-gate] [--doorbell S] [--idle-timeout N]` | Idle-gate, then send the doorbell. |
| `clavity req-id [INSTRUCTION]` | Mint a request id, or wrap an instruction in the `[req_id=..]` envelope. |
| `clavity info` | Print the detected platform + effective configuration (diagnostic). |
| `clavity doctor` | Preflight: check tmux/claude/agy are on `PATH` and the session is reachable. |
| `clavity cancel` | Interrupt agy's current turn (sends Escape to the pane; pair with a bus `alert` from Claude). |
| `clavity --session NAME …` | Target a non-default psmux session (global flag). |

**Output discipline:** results go to **stdout** (machine-readable: `idle`, pane text, ids);
diagnostics go to **stderr** via `tracing`. So tools can parse stdout cleanly.

---

## Configuration

All optional; sensible defaults. Environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `AGY_SESSION` | `claude_agy` | psmux session name hosting the live agy. |
| `AGY_TMUX_BIN` | `tmux` (resolved on `PATH`) | psmux/tmux binary; set only if it isn't on `PATH`. |
| `AGY_DOORBELL` | _canonical line_ | The single-line wake string the responder skill keys on. |
| `AGY_START_ARGS` | `--dangerously-skip-permissions` | Flags `start` passes to `agy`. |
| `AGY_WATCH` | _enabled_ | On first launch, `start` opens a visible terminal tab (Windows Terminal) attached to agy so you can answer its auth/login prompts. Set `0`/`false`/`no` to disable. |
| `AGY_IDLE_MARKER` | `? for shortcuts` | Footer text meaning agy is idle. |
| `AGY_BUSY_MARKER` | `esc to cancel` | Footer text meaning agy is busy. |
| `RUST_LOG` | `clavity=info` | Log verbosity, e.g. `RUST_LOG=clavity=debug`. |

---

## Design docs

- **[Design spec](docs/superpowers/specs/2026-06-16-agy-remote-control-design.md)** — the full
  architecture and the empirical spikes it rests on (bus round-trip, `send-keys` wake, idle/busy
  detection, doorbell-while-busy queueing, the pwsh shell reality, the safety checkpoint).
- **[Protocol runbook](docs/agy-remote-control-protocol.md)** — the exact Claude-side procedure.
- **[agy assumptions & re-verification playbook](docs/agy-assumptions.md)** — the external `agy` /
  `psmux` / `agentmemory` behaviors clavity depends on (footer markers, pwsh shell, skill caching,
  headless-print hang, …), the versions verified against, and **how to re-verify/fix after an agy
  update**. Read this first if something breaks.

---

## Platform support

| Platform | Status |
| --- | --- |
| Windows | ✅ Built and verified end-to-end against a live `agy` (incl. the autonomous safety checkpoint). |
| Linux | 🚧 **Compiles + unit-tests in CI** on `ubuntu-latest` (a Linux binary is built as a CI artifact), but the live end-to-end path is **unverified**. See the porting guide under [Contributing](#contributing). |
| macOS | 🚧 Wanted — should be close to Linux; unverified. |

---

## Contributing

Contributions welcome — **especially Linux/macOS support**. See **[CONTRIBUTING.md](CONTRIBUTING.md)**
for the full guide: dev setup, the two test tiers (hermetic + the **live acceptance runbook**), the
Linux/macOS **porting checklist**, conventions, and PR expectations.

Quick loop:

```bash
cargo test --all --features test-fakes                          # unit + integration (fake psmux)
cargo clippy --all-targets --features test-fakes -- -D warnings
cargo fmt --all --check
```

### Project layout

| Path | Role |
| --- | --- |
| `src/main.rs` | clap CLI, dispatch, `start` launcher, `doctor`/`info`. |
| `src/tmux.rs` | **C3** — psmux primitives + pane-state detection. |
| `src/bus.rs` | **C5** — agentmemory-bus conventions (req-id + `[req_id=..]` envelope). |
| `src/platform.rs` | **Platform seam** — OS detection + per-OS assumptions (Unix arms are scaffolding). |
| `src/bin/fake_tmux.rs`, `tests/integration.rs` | Test-only fake psmux + integration tests (CI, no live agy). |
| `agy_skills/claudavity-responder/SKILL.md` | **C2/C4** — the agy-side responder skill. |
| `docs/` | Protocol runbook + design spec. |

---

## License

[MIT](LICENSE) © Costas Kirgoussios
