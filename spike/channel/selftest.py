"""Self-test the channel probe over real stdio (no live Claude needed).

Spawns channel_probe.py, performs the MCP initialize handshake, keeps the
connection open past PUSH_DELAY_SECONDS, and checks that:
  1. the initialize response declares the experimental `claude/channel` capability, and
  2. the probe spontaneously emits a `notifications/claude/channel` event.

This validates the probe mechanism end-to-end; only "does an idle Claude react"
(Half B proper) still needs a live Claude.
"""

import json
import subprocess
import threading
import time

proc = subprocess.Popen(
    ["uv", "run", "python", "spike/channel/channel_probe.py"],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

initialize = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
        "protocolVersion": "2025-06-18",
        "capabilities": {},
        "clientInfo": {"name": "selftest", "version": "0"},
    },
}
initialized = {"jsonrpc": "2.0", "method": "notifications/initialized"}

assert proc.stdin is not None
proc.stdin.write(json.dumps(initialize) + "\n")
proc.stdin.flush()
proc.stdin.write(json.dumps(initialized) + "\n")
proc.stdin.flush()

lines: list[str] = []
errs: list[str] = []


def _reader() -> None:
    assert proc.stdout is not None
    for line in proc.stdout:
        lines.append(line.strip())


def _errreader() -> None:
    assert proc.stderr is not None
    for line in proc.stderr:
        errs.append(line.rstrip())


threading.Thread(target=_reader, daemon=True).start()
threading.Thread(target=_errreader, daemon=True).start()
time.sleep(9)  # wait past the probe's 6s PUSH_DELAY
proc.terminate()

cap_declared = any("experimental" in ln and "claude/channel" in ln for ln in lines)
push_emitted = any("notifications/claude/channel" in ln for ln in lines)

print("INIT_CAP_DECLARED:", cap_declared)
print("CHANNEL_PUSH_EMITTED:", push_emitted)
print("--- raw stdout lines ---")
for ln in lines:
    print("  <<", ln[:240])
print("--- stderr (last 20) ---")
for ln in errs[-20:]:
    print("  !!", ln[:240])
