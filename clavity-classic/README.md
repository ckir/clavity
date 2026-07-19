# clavity

[![CI](https://github.com/ckir/clavity/actions/workflows/ci-classic.yml/badge.svg)](https://github.com/ckir/clavity/actions/workflows/ci-classic.yml)
[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
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
- [Platform support](#platform-support)
- [Docs](#docs)
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
- **Either** the [Windows installer](https://github.com/ckir/clavity/releases/latest) (no toolchain)
  **or** **Rust** (`cargo`) to build from source — currently **Windows** only (see
  [Platform support](#platform-support)).

### 1. Wire up the agentmemory bus (both agents)

Register the **same** agentmemory MCP server in **both** Claude Code and agy, pointing at the same
daemon (default `:3111`). **Nothing works without it** — it is clavity's data channel.

**Config snippets for both agents, and how to verify:**
[`plugin/README.md` § MCP configuration](plugin/README.md#mcp-configuration).

### 2. Install clavity

**Recommended (Windows, no toolchain) — the installer.** Download `clavity-classic-setup.exe` from the
[latest release](https://github.com/ckir/clavity/releases/latest) and run it. It puts `clavity` on your
`PATH`, sets a mutual-exclusion marker (it will **not** co-install with the .NET **clavity-dotnet** variant),
and optionally installs the `delegate_to_antigravity` **bridge** add-on (opt-in, default off — needs Python
3.10+ and [uv](https://docs.astral.sh/uv/)). When it finishes, a **`MANUAL-SETUP.md`** opens with the
remaining one-time wiring — the agentmemory bus (step 1 above) and the `GEMINI.md` pointer (step 3 below).
Classic wires those **manually by design**; the installer does not edit your agent configs.

> Per-user install (`%LOCALAPPDATA%`, HKCU — no admin). **Unsigned** (owner decision): SmartScreen warns —
> *More info → Run anyway*. Verify the download against the published `clavity-classic-setup.exe.sha256`.

**From source** (developers / other platforms):

```bash
cargo build --release
# put it on PATH, e.g. next to your psmux:
cp target/release/clavity.exe "C:/!PORTABLES/!BIN/"   # Windows
# cp target/release/clavity   ~/.local/bin/            # elsewhere
```

### 3. Install the agy-side responder skill

`clavity start` **auto-installs/refreshes** this skill on every launch, so you don't copy it by hand.
You do need a **one-time pointer in `~/.gemini/GEMINI.md`** so agy reliably invokes it.

**The rule text to paste, plus the checkpoint behaviour and the skill-caching caveat:**
[`plugin/README.md` § agy's responder trigger](plugin/README.md#agys-responder-trigger-required-one-time).

### 4. Launch both agents in a folder

Run from your normal shell so `agy` inherits your signed-in session. `start` is the default action,
so you can omit it:

```pwsh
clavity C:\path\to\project           # folder (bare = start)
clavity -c                           # current folder; forwards -c (continue) to claude
clavity C:\path\to\project --resume  # folder + flags forwarded to claude
clavity start C:\path                # explicit form, identical
```

The folder must be the **first** argument and must not start with `-`. If it's omitted — or the first
argument is a flag — the **current** folder is used and every argument is forwarded to `claude`. So
write `clavity C:\proj --resume`, **not** `clavity --resume C:\proj` (there the folder would be cwd
and `C:\proj` would be passed to claude).
**On first launch a visible "watch" tab opens** (Windows Terminal) attached to agy, so you can
answer agy's auth/login prompts — it asks fairly often. Disable with `AGY_WATCH=0`. You can also
attach manually anytime: `tmux attach -t claude_agy`. To hide agy while keeping it alive, **detach**
with `Ctrl-b d` — **closing** the tab tears down the whole session (the next `clavity start`/`-c` is
then a fresh launch).

### 5. Drive agy from Claude

**You don't run these commands — Claude does.** In the Claude Code chat, just ask Claude to drive
agy; it has the agentmemory bus tools and invokes `clavity` itself. For that, **Claude needs to know
the protocol**: point it at [`docs/agy-remote-control-protocol.md`](docs/agy-remote-control-protocol.md)
(or install that as a Claude skill/command). The optional SessionStart hook below injects a one-line
reminder, but the full procedure lives in the runbook.

Under the hood it's **one command** — `clavity ask` mints the request, puts it on the bus, rings the
doorbell, blocks for agy's correlated reply, and prints it:

```bash
clavity ask "refactor foo() to return Result"          # -> agy's reply on stdout, exit 0
clavity ask --review-only "review src/foo.rs vs the spec; verdict only, no edits"
```

No polling, no pane-scraping: `ask` correlates the reply by signal id + the `[req_id=..]` echo and
returns its content directly (exit 1 on timeout). To block on a reply for a request you sent via the
MCP tool yourself, use `clavity await-reply --req-id <id> --thread-id <thr>` (pass the `threadId` from
your `memory_signal_send` response — it scopes the read to that thread). The agentmemory daemon is
reached over its REST API (default `http://127.0.0.1:3111`, override with `AGENTMEMORY_URL`).

> **After launch, give agy a moment.** It loads its MCP servers (agentmemory included) a few seconds
> after starting, and `clavity state` can read `idle` before that finishes. Gate your first task on
> **`clavity ping`** (one call: send `[ping]`, ring, block for `READY`) and retry until it exits 0 —
> see the runbook. The manual equivalent is typing `list your active mcp servers` in the watch tab.

**Optional — auto-detect clavity sessions.** `clavity start` exports `CLAVITY_SESSION=<session>` to the
Claude it launches. Add a **SessionStart hook** to `~/.claude/settings.json` that, when that var is set,
injects a note telling Claude it has a live agy peer and how to drive it (so you don't have to remind it):
```json
{ "hooks": { "SessionStart": [ { "hooks": [ {
  "type": "command", "shell": "bash",
  "command": "if [ -n \"$CLAVITY_SESSION\" ]; then printf 'clavity: live agy peer in psmux session %s — drive via clavity req-id|ring + memory_signal_send/read; readiness: [ping].' \"$CLAVITY_SESSION\"; fi"
} ] } ] } }
```
Plain `claude` sessions print nothing, so it's inert outside clavity.

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
| `clavity ask "<INSTRUCTION>" [--review-only] [--no-ring] [--to A] [--type T] [--timeout N]` | **One-shot round-trip:** mint a req-id, send the request on the bus, ring, block for agy's correlated reply, print its content. Exit 0 reply / 1 timeout / 2 daemon-unreachable. `--review-only` prepends the no-edit banner. |
| `clavity await-reply --req-id ID --thread-id THR [--timeout N] [--poll-interval MS]` | Block until agy's reply correlated to `ID` lands; print its content (exit 1 on timeout). For a request you sent yourself via the MCP tool — pass the `threadId` from that send's response (`--thread-id` is **required**; the read is scoped to that thread so it never consumes unrelated inbox unread). |
| `clavity ping [--timeout N]` | Readiness round-trip: send `[ping]`, ring, block for agy's `READY`. |
| `clavity info` | Print the detected platform + effective configuration (diagnostic). |
| `clavity doctor` | Preflight: check tmux/claude/agy are on `PATH` and the session is reachable. |
| `clavity cancel` | Interrupt agy's current turn (sends Escape to the pane; pair with a bus `alert` from Claude). |
| `clavity stop` | Tear down the agy session (kill the psmux session) so it doesn't orphan. |
| `clavity curate-commit` | Read the compiled golden header from stdin and atomically write it (+ a `.sha256` sidecar) to the resolved golden-header growth path — the write path `agy-curate` invokes. |
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
| `AGENTMEMORY_URL` | `http://127.0.0.1:3111` | agentmemory daemon REST base URL — used by `ask` / `await-reply` / `ping`. |
| `AGENTMEMORY_SECRET` | _none_ | Bearer token for the daemon; sent only when set (the daemon requires it only when it too has a secret configured). |
| `RUST_LOG` | `clavity=info` | Log verbosity, e.g. `RUST_LOG=clavity=debug`. |

---

## Platform support

| Platform | Status |
| --- | --- |
| Windows | ✅ Built and verified end-to-end against a live `agy` (incl. the autonomous safety checkpoint). |
| Linux | 🚧 **Compiles + unit-tests in CI** on `ubuntu-latest` (a Linux binary is built as a CI artifact), but the live end-to-end path is **unverified**. See the porting guide under [Contributing](#contributing). |
| macOS | 🚧 Wanted — should be close to Linux; unverified. |

---

## Docs

- **Design spec** _(internal design provenance — not published)_ — the full
  architecture and the empirical spikes it rests on (bus round-trip, `send-keys` wake, idle/busy
  detection, doorbell-while-busy queueing, the pwsh shell reality, the safety checkpoint).
- **[Protocol runbook](docs/agy-remote-control-protocol.md)** — the exact Claude-side procedure,
  including the **capability-aware "Driving conventions"** (how to phrase requests in agy's language:
  the per-mode request templates + what to avoid).
- **[agy capability profile](plugin/knowledge/agy-capabilities.md)** — **what agy can do and how to
  route to it** (strengths, weaknesses, the multi-model table, operational reach), treating agy as an
  external peer model. Provenance-tagged and version-pinned; the live config is the truth, so
  re-derive it for your install via its refresh procedure. Pairs with the protocol runbook (how to
  ask).
- **[agy acceptance test suite](docs/agy-test-suite.md)** — copy-pasteable `clavity ask` tests (the
  four request-mode templates + skill-cache and write-scope re-verifications) to **re-run after an
  `agy update`** and confirm the profile + protocol still hold.
- **[agy assumptions & re-verification playbook](plugin/knowledge/agy-assumptions.md)** — the external `agy` /
  `psmux` / `agentmemory` behaviors clavity depends on (footer markers, pwsh shell, skill caching,
  headless-print hang, the daemon REST API, …), the versions verified against, and **how to
  re-verify/fix after an agy update**. Read this first if something breaks.

---

## Contributing

Contributions welcome — **especially Linux/macOS support**. See **[CONTRIBUTING.md](CONTRIBUTING.md)**
for the full guide: dev setup, the two test tiers (hermetic + the **live acceptance runbook**), the
Linux/macOS **porting checklist**, conventions, and PR expectations.

The quick test loop, the **project layout** table, and the porting checklist all live there — this
README does not duplicate them.

---

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) © Costas Kirgoussios — free for non-commercial use
(personal, academic, non-profit). Matches `clavity-classic/Cargo.toml`'s
`license = "PolyForm-Noncommercial-1.0.0"` and the umbrella
[root README](../README.md#license); all five products ship under the same licence.
