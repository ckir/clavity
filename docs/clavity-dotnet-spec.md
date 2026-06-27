# clavity (.NET) — design spec

> **Status:** DRAFT spec (forward-writable; not a line-level plan — the .NET code does not exist yet).
> **Authored:** 2026-06-27 · **Verified against:** Antigravity CLI (`agy`) **1.0.11**, Windows 11, pwsh.
> **Review:** AGY-AFTER review done 2026-06-27 (web-Gemini relay). **Transport/control facts since
> VERIFIED LIVE** against a logged-in, quota-live agy (write round-trip, same-instance drive, token
> not enforced, gRPC/h2c wire format, RPC map) — see §2/§6/§9 and memory `agy-language-server-agentapi`.

This supersedes the Rust `clavity` (branch `clavity-classic`). It keeps **one** behavior from the old
tool and redesigns everything else around a capability discovered by reverse-engineering agy 1.0.11:
**every live agy session runs a local gRPC control server (cleartext HTTP/2).** We drive that, instead
of a terminal multiplexer.

---

## 1. Goal

`antigravity-cli` (`agy`) becomes an **interactive superpower for Claude**: from a Claude session,
Claude can **look into**, **control**, and **pull data from** a live agy instance running in a sibling
Windows Terminal tab — on demand — while the human keeps a **real interactive console** for that same
agy (login, `/commands`, watching it work).

**Direction of control (load-bearing): Claude drives agy.** Claude is the primary operator — it issues
the tasks and reads the results, via clavity -> the LS API. The visible agy tab is **auxiliary**: it
exists only so the human can log in, run slash-commands, and observe — it is **not** the primary control
path, and the human is not the primary driver. agy is the driven side; Claude is the driver.

### Non-goals
- Re-implementing the old psmux doorbell, the agentmemory bus dependency, or screen-scraping.
- Driving agy by injecting keystrokes. We never touch the human's keyboard.
- A headless one-shot model (`agy --print`) as the primary path — it spawns a throwaway instance, not
  *the* live one the human sees.

---

## 2. Key discovery (the architecture pivot)

Verified live (throwaway agy, no quota), see memory `agy-language-server-agentapi`:

- **Every agy session starts a local "Language Server" (LS)** on `127.0.0.1`: a **gRPC/HTTPS** port `N`
  and an **HTTP** port `N+1` (logged as `Language server listening on random port at <N> for HTTPS
  (gRPC)` / `<N+1> for HTTP`). Ports are random per session but **discoverable**.
- A **hidden `agy agentapi` subcommand** (`agy.exe agentapi …`) is a **gRPC client** to that LS. It
  connects to the **HTTP port** (`N+1`), which despite the "HTTP" log label speaks **gRPC over h2c
  (cleartext HTTP/2)** — NOT REST/JSON. The `N` port is the same gRPC service **TLS-wrapped** (refuses
  plaintext). agentapi's JSON stdout is its *rendering* of the protobuf response, not the wire. CLI ops:
  - `get-conversation-metadata <conversation_id>` — **read** (look into / pull data)
  - `new-conversation [--model=flash_lite|flash|pro] [--title] <prompt>` — **control** (spawn work)
  - `send-message [--title] <recipient_id> <content>` — **control** (inject a message)
- **Underlying gRPC service** (from `agy.exe` strings + a live relay capture, see §6):
  `exa.language_server_pb.LanguageServerService` (the Codeium/Windsurf LS proto lineage). Every clavity
  capability is a native RPC there — drive (`SendUserCascadeMessage`), turn-status
  (`WaitForConversationFullyIdle`), transcript (`GetCascadeTrajectory*`, `ConvertTrajectoryToMarkdown`),
  list (`SearchConversations`), interrupt (`CancelCascadeInvocation`/`ForceStopCascadeTree`), worktree
  (`CreateWorktree`/`CheckoutWorktree`/`GetWorktreeDiff`/`DeleteWorktree`).
- It reads three env values: `ANTIGRAVITY_LS_ADDRESS` (`127.0.0.1:<httpport>`),
  `ANTIGRAVITY_CSRF_TOKEN`, `ANTIGRAVITY_PROJECT_ID`.
- **Auth (verified live, logged-in agy 1.0.11): the CSRF token is NOT enforced — for BOTH reads AND
  writes.** `get-conversation-metadata` returned full JSON with a *wrong* token; `send-message`
  succeeded with a bogus token. **Port-only access to `127.0.0.1:<httpport>` is sufficient for full
  read+write control of a logged-in, quota-live agy.** (Writes still need the session itself to be
  logged-in + quota-live + initialized to clear agy's "start cascade" stage.) SECURITY NOTE: any local
  process can drive the live agy via the port.

**Consequence:** Claude controls/inspects agy over a local HTTP API. No multiplexer. No bus. No
screen-scraping. The human's visible interactive tab and Claude's programmatic access are the *same*
running instance.

---

## 3. Components

1. **`clavity` (.NET CLI)** — the launcher + the operator surface. Subcommands (`start`, `doctor`,
   `info`, `stop`, plus the operator verbs below). Native-AOT single-file binary.
2. **`clavity` MCP server** — the Claude-facing surface. Same binary in an MCP mode (stdio), exposing
   agy as tools (§5). Built on the official **MCP C# SDK**.
3. **The live agy tab** — a normal interactive `wt` tab running agy (the human's console). clavity
   launches it; the human owns it.
4. **The agy LS** — agy's own per-session gRPC server (h2c on the "HTTP" port). clavity talks to it via
   **`Grpc.Net.Client`** (`agy agentapi` shelling is only a throwaway capture spike).

### Data flow
```
Human  -- types / login / slash-commands -->  agy tab (interactive TUI)
                                                 |  (same process exposes...)
Claude --> clavity MCP tool --> clavity -->  agy LS (127.0.0.1 gRPC/h2c) --> look-into / control
```

---

## 4. The kept primitive — `start <folder>`

`clavity start <folder> [claude-args...]` (default action when no subcommand), preserving old clavity's
one valued behavior **and** the human-console requirement:

1. Resolve `<folder>` (default cwd); warn if not a git repo.
2. Launch a **visible interactive agy tab**: a `wt new-tab` running pwsh that sets the launch env
   (see §6) then runs `agy` in `<folder>`. The human logs in / uses slash-commands here.
   - `--dangerously-skip-permissions` is opt-in via config/flag (the user authorized it for this
     project), not default.
3. Launch **Claude Code** in `<folder>` (foreground), marking it clavity-launched (env var) so a
   SessionStart hook can surface the agy peer (as today).
4. Record the session->LS-port mapping for the operator/MCP layer (§7).

No psmux. The agy tab is interactive and human-owned; clavity never sends keystrokes to it.

---

## 5. Claude-facing MCP tool surface

Exposed by the MCP server, implemented over the LS API. Names indicative:

| Tool | Maps to | Status |
|------|---------|--------|
| `agy_look` / `agy_status` | `GetConversationMetadata` + `WaitForConversationFullyIdle` | VALIDATED (read works port-only; idle-RPC identified) |
| `agy_ask` (one round-trip) | `SendUserCascadeMessage` to the live conversation → `WaitForConversationFullyIdle` → read reply | VALIDATED — `send-message` into the live conv surfaced in the human's tab; agy replied with the exact requested string |
| `agy_new_task` | `new-conversation <prompt>` (`NewConversation`-family RPC) | PENDING `new-conversation` round-trip |
| `agy_pull <conversation_id>` | `GetCascadeTrajectory*` / `ConvertTrajectoryToMarkdown` (transcript) + metadata | metadata VALIDATED; transcript RPCs identified, decode TBD |

The MCP server keeps the **review-only / framing conventions** the old tool had (a banner prepended to
control payloads) where useful.

**Bounded views (required).** Read tools MUST return paginated / filtered / summarized data — never raw
conversation trees or full tool-use logs. agy's metadata/transcripts are verbose (large id arrays, etc.)
and would bloat Claude's context window; the .NET layer does the trimming before returning to Claude.

---

## 6. LS access mechanics

- **Port discovery.** For a session clavity launched, get the agy PID and read its listening
  `127.0.0.1` ports (HTTP = the higher of the adjacent pair), or parse the session's cli-log line
  `listening on random port at <N> for HTTP`. clavity should set `--log-file` to a known path at launch
  to make this deterministic.
- **Env at launch.** clavity sets `ANTIGRAVITY_CSRF_TOKEN` (a known value — harmless since not enforced,
  but future-proofs if enforcement returns), and supplies `ANTIGRAVITY_PROJECT_ID` for control calls
  (from `~/.gemini/antigravity-cli/cache/default_project_id.txt` / `projects.json`).
- **Transport — direct gRPC (h2c), not HttpClient/JSON, not the subprocess.** Wire format CAPTURED
  2026-06-27 via a localhost relay in front of the HTTP port: it is **gRPC over cleartext HTTP/2**
  (request opened with the `PRI * HTTP/2.0` preface; DATA frames carry gRPC-framed protobuf). So the
  .NET client uses **`Grpc.Net.Client`** against `http://127.0.0.1:<httpport>` with **h2c** enabled
  (`HttpClient` `DefaultRequestVersion = 2.0`, `DefaultVersionPolicy = RequestVersionExact`, and the
  AppContext switch `System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport = true`), calling
  `exa.language_server_pb.LanguageServerService` methods. We need the `.proto` (or a hand-written
  partial) for the handful of RPCs in §5/§2; reconstruct from the relay-captured protobuf + `agy.exe`
  strings, or extract via gRPC reflection if the LS exposes it. Shelling `agy agentapi` remains only a
  throwaway **spike** to confirm a message shape, never the shipped transport.
- **Hang / TUI-modal guard.** Every LS call has a bounded timeout. On hang/timeout, fall back to a
  **flaui-mcp tab inspection** to detect a terminal modal (auth-refresh / quota / consent prompt) and
  surface it — never block silently. Read current metadata before a write to catch human `/model` or
  project switches (state desync).

---

## 7. Operator CLI (human / diagnostic surface)

Mirrors old clavity's diagnostics, re-pointed at the LS:
- `clavity doctor` — agy/claude/wt on PATH; a live agy LS reachable.
- `clavity info` — detected paths, session, discovered LS port.
- `clavity look [<conversation_id>]` — print conversation metadata (read).
- `clavity stop` — close the launched agy tab/session.
- (No `capture`/`ring`/`wait-idle`/`cancel` — those were multiplexer artifacts.)

---

## 8. Empirically-derived-contract discipline

The LS / `agentapi` surface is **undocumented and version-fragile** — exactly like the old tmux/bus
assumptions. Port a `docs/agy-assumptions.md` analog enumerating each load-bearing fact (LS ports,
agentapi ops, token-not-enforced, env names, project_id requirement), how it was verified, and how to
re-verify when agy updates. Most breakages should be config/knobs, not code.

---

## 9. Open items / verify-gates

**RESOLVED 2026-06-27 against a live, logged-in, quota-live agy (1.0.11, PID 30728, LS 61954/61955):**
1. ✅ **Write round-trip** — `send-message <conv_id> "<text>"` returned `{sendMessage:{recipientId,content}}`
   exit 0. (`new-conversation` round-trip still untested — see below.)
2. ✅ **`send-message` drives the SAME live instance** — `recipient_id` == `conversation_id`; the message
   injected into the conversation the human sees, agy **queued it while busy** then on idle replied with
   the **exact requested string in the visible tab**. The "drive the live instance" promise holds.
3. ✅ **Turn-status primitive** — it is the **`WaitForConversationFullyIdle` RPC** (not a gRPC-port event
   probe as previously guessed). Use it as a blocking "agy is done" wait; no footer-polling, no brittle
   retry loop. Reply retrieval = `GetCascadeTrajectory*` after idle.
5. ✅ **Token enforcement when logged-in** — NOT enforced, for reads OR writes (see §2 auth). Port-only.

**Still open (do not block increment-1):**
- **`new-conversation` round-trip** — confirm a fresh `NewConversation` task spawns + completes.
- **Exact `:path` for `send-message`** — almost certainly `SendUserCascadeMessage`; the captured HEADERS
  frame was HPACK-compressed. Confirm by HPACK-decoding a relay capture or matching the request protobuf.
- **Transcript decode** — `GetCascadeTrajectory*` / `ConvertTrajectoryToMarkdown` proto field shapes for
  bounded read views (§5).

---

## 10. Distribution
- .NET, **Native AOT**, single-file, `win-x64` primary; trim/AOT for small fast binary.
- GitHub Releases via CI matrix; optional `dotnet tool` packaging.

---

## 11. Decisions locked
- Greenfield .NET; discard Rust `clavity`.
- Keep only same-folder co-launch (+ visible interactive agy console).
- Drop tmux/psmux and the agentmemory-bus dependency.
- Comms = agy's Language Server (HTTP), surfaced to Claude as MCP tools.
- **Scope: clavity-dotnet is ONLY the launcher + the LS-API MCP bridge.** Auth (browser OAuth),
  terminal modals, and browser use are OUT of scope — covered by Claude's runtime tools
  (claude-in-chrome, flaui-mcp) and agy's own native browser tools, not by clavity. (No FlaUI /
  Playwright / Puppeteer / WebView2 baked into the binary.)
- **End-state goal: clavity gives Claude maximum control over agy and eventually replaces the
  `agy-mcp-bridge` `delegate_to_antigravity` tool, which is then retired (§12).**

---

## 12. Roadmap — agy as a Claude-delegatable agent (and retiring `delegate_to_antigravity`)

**Goal:** maximum Claude control over agy via the LS API, until clavity fully supersedes the
`agy-mcp-bridge` `delegate_to_antigravity` MCP tool — which is then retired. agy becomes a
delegatable external agent ("go have agy do X, return the result"), not a model like sonnet/haiku
(that layer is Anthropic-internal and out of reach); the practical ceiling is the auth/quota
availability gap, not the transport.

**Today's two delegation paths:**
- `delegate_to_antigravity` (existing) — autonomous **code-mod** delegation; runs agy in a git
  worktree, gates success on **committed changes**. Good for "build X and commit it"; fails by
  construction for review-only / consult (no commit).
- clavity LS (this spec) — **interactive / synchronous**: ask, control, look-into, read reply. No
  commit gate; serves consult/review **and** live steering.

**Path to parity / maximum control** (each builds on the LS transport):
1. **Reliable ask -> reply** (closes §9.1–§9.3): send a task, poll status, read the final answer.
   -> clavity matches consult/review, which `delegate_to_antigravity` cannot do.
2. **Autonomous task delegation in an ISOLATED worktree.** Run autonomous code-mod against a
   **separate, worktree-scoped agy session** (a second agy whose cwd is a git worktree, driven via
   *its* LS) — NOT the human's live workspace. **agy has FIRST-CLASS worktree RPCs** —
   `CreateWorktree` / `CheckoutWorktree` / `GetWorktreeDiff` / `DeleteWorktree` / `UpdatePRForWorktree`
   on `LanguageServerService` — so clavity drives isolation natively rather than shelling `git worktree`.
   Detect completion via `WaitForConversationFullyIdle`, capture the diff via `GetWorktreeDiff`, gate
   before merge. This preserves the **isolation + atomic rollback** the bridge's value rests on, leaves
   the human's live dir untouched, AND resolves split-brain concurrency (the human-interactive agy and
   the autonomous agy are different sessions/dirs; a failed multi-file change never strands the human's
   workspace).
3. **Session control:** resume/pick a conversation, run many tasks against one warm agy, cancel a
   turn, set the model (`flash_lite`/`flash`/`pro`). -> "maximum control."
4. **Auth / availability** (the ceiling — OUT of clavity scope): browser OAuth login is handled by
   Claude via claude-in-chrome; agy terminal modals via flaui-mcp; agy already has native browser
   tools. clavity only **surfaces auth/quota state** so delegation degrades gracefully, never hangs.

**Retirement criteria for `delegate_to_antigravity`** (ALL must hold):
- clavity LS does autonomous code-mod delegation **in an isolated worktree with diff capture + atomic
  rollback** at parity or better (the bridge's core value is isolation, not just the write APIs);
- AND interactive consult / review / steering (which the bridge never did);
- AND graceful failure / quota-state handling (state surfaced to Claude, not auto-resolved by clavity);
- AND it is the documented default path.
Then remove the bridge from config. Until then the bridge stays as the proven autonomous-code-mod
fallback; clavity is **additive**, not a regression.
