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

## Half B — does an idle Claude actually wake? ⏳ PENDING (needs a live Claude)
Requires a live Claude Code launched with the research-preview channels dev flag. Procedure +
pass/fail in `spike/channel/README.md`. This is the load-bearing assumption for the whole
agy→Claude direction — confirm it before committing to the Phase 2 plan.

**RESULT: pending** — update this line with PASS/FAIL + Claude version after running the live test.
