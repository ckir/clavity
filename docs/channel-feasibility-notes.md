# Channel feasibility — v2 Phase 2 spike

Provenance: live inspection + stdio probe of `mcp==1.28.0` against the Claude Code channels
contract (code.claude.com/docs/en/channels-reference), 2026-06-17.

## The question (spec §8.1)
Phase 2's **agy→Claude** wake relies on Claude Code **"channels"**: a stdio MCP server that
declares `experimental['claude/channel']` and pushes `notifications/claude/channel` to wake an
*idle* Claude. Two unknowns: **(A)** can the channel-driver be **Python** (vs forced to Node), and
**(B)** does an *idle* Claude actually wake on the push?

## Half A — Python feasibility: ✅ PROVEN (hermetic + stdio self-test)
The Python `mcp` SDK (1.28.0) does everything the contract needs:

1. **Declare the capability** (public API):
   ```python
   server.create_initialization_options(experimental_capabilities={"claude/channel": {}})
   ```
   → the `initialize` response carries `capabilities.experimental = {"claude/channel": {}}`
   (verified on the wire).

2. **Push the custom notification.** The typed `ServerSession.send_notification` won't accept a
   non-standard method, but the raw write path — exactly what `send_notification` uses internally —
   does:
   ```python
   from mcp.types import JSONRPCNotification, JSONRPCMessage
   from mcp.shared.message import SessionMessage
   notif = JSONRPCNotification(jsonrpc="2.0", method="notifications/claude/channel",
                               params={"content": "...", "meta": {...}})
   await session._write_stream.send(SessionMessage(message=JSONRPCMessage(notif)))
   ```

`spike/channel/channel_probe.py` (validated by `spike/channel/selftest.py`) emits the exact wire
form over real stdio:
```json
{"method":"notifications/claude/channel","params":{"content":"...","meta":{...}},"jsonrpc":"2.0"}
```
Self-test result: `INIT_CAP_DECLARED: True`, `CHANNEL_PUSH_EMITTED: True`.

### Decision
**The Phase 2 channel-driver is Python — no Node.** Caveat: the push relies on the private
`session._write_stream`; isolate it behind a `push_channel(session, content, meta)` helper so that
single internal dependency lives in one place and is easy to fix if the SDK changes.

## Half B — does an idle Claude actually wake? ✅ PASS (live, 2026-06-17)
A live Claude Code session launched with `--dangerously-load-development-channels
server:channel-probe` registered the channel (banner: *"Channels (experimental) messages from
server:channel-probe inject directly in this session"*), received the probe's pushed
`notifications/claude/channel` event **with no user input**, and **autonomously replied
`CHANNEL-WAKE-OK`**.

**RESULT: ✅ PASS.** Idle channel-wake works. The whole v2 Phase 2 agy→Claude direction is viable
— driven from a **Python** `claude/channel` server. Both §8.1 unknowns are resolved: Python (Half A)
+ idle-wake (Half B).

### Implications for Phase 2
- The **channel-driver is Python** (a stdio MCP server declaring `claude/channel`, pushing events
  from the clavity daemon's `→claude` queue).
- Caveats to carry into the plan: it's **research-preview** (Claude `--channels` / dev flag,
  v2.1.80+, Team/Enterprise admin enable), and the push uses the private `session._write_stream`
  (isolate behind a helper).
