# channel probe — Half B live test

Tests whether an **idle** Claude Code session wakes and acts on a server-pushed
`notifications/claude/channel` event (the load-bearing assumption for v2 Phase 2's
agy→Claude direction). Half A (Python *can* declare the capability + push the event) is
already proven — see `docs/channel-feasibility-notes.md`. This is Half B.

## Run (in a NEW terminal — not the one driving the main session)
```
cd C:/Users/user/Development/Rust/clavity/spike/channel
claude --dangerously-load-development-channels server:channel-probe
```
Requires Claude Code **v2.1.80+** (channels are a research preview). On Team/Enterprise
plans an admin must have channels enabled.

- On first launch Claude asks consent for the project `.mcp.json` server `channel-probe`
  → choose **Use this MCP server**.
- A dim banner should confirm: `Channels (experimental) messages from
  server:channel-probe inject directly in this session`.
- **Then do nothing.** ~5 s after the server connects, the probe pushes one channel
  event: *"…reply in the session with exactly: CHANNEL-WAKE-OK"*.

## Pass / fail
- **PASS** — with **no** user input, Claude reacts on its own and replies
  `CHANNEL-WAKE-OK` (or visibly processes the `<channel source="channel-probe">` event).
  → idle channel-wake works; Phase 2's agy→Claude direction is viable in Python.
- **FAIL** — nothing happens until you type. → idle-wake doesn't fire here
  (version/policy/flag); the reverse direction needs a rethink (or it only lands on
  Claude's next user-driven turn).

Record the outcome in `docs/channel-feasibility-notes.md` (the Half B `RESULT` line).

## Local self-test (no live Claude — validates the probe mechanism only)
```
uv run python spike/channel/selftest.py
```
Expects `INIT_CAP_DECLARED: True` and `CHANNEL_PUSH_EMITTED: True`.
