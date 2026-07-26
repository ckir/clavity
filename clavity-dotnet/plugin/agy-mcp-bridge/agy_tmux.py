"""tmux/psmux primitives for the agy remote control (component C3).

The live ``agy`` (Antigravity CLI) session runs inside a psmux/tmux session (default
name ``claude_agy``), started signed-in by a human. Claude drives it on demand by
injecting a short "doorbell" keystroke (``send-keys``) and reads its TUI state by
classifying the captured pane footer. Real task payloads travel over the agentmemory
signal bus, NOT through here — this module only handles the wake + state-detection
plumbing.

Verified facts this module relies on (psmux v3.3.5, a "tmux alternative" for Windows):
  - ``capture-pane -p -t <s>`` prints the visible pane to stdout.
  - the agy TUI footer reads ``? for shortcuts`` when idle and ``esc to cancel`` when busy.
  - ``has-session -t <s>`` exits 0 iff the session exists.
  - ``send-keys -t <s> -l "<text>"`` sends literal text (no key re-parsing); a following
    ``send-keys -t <s> Enter`` submits it. Input sent while agy is busy is safely QUEUED
    and processed as the next turn (no interleaving).
"""

import asyncio
import os

# The psmux/tmux binary. Override with AGY_TMUX_BIN.
TMUX_BIN = os.environ.get("AGY_TMUX_BIN", r"C:\!PORTABLES\!BIN\tmux.exe")

# The tmux session hosting the live, signed-in agy. Override with AGY_SESSION.
DEFAULT_SESSION = os.environ.get("AGY_SESSION", "claude_agy")

# Canonical single-line doorbell. The agy-side "claudavity responder" skill is keyed to
# this string: on seeing it, agy reads its inbox and acts. Real instructions go on the
# bus, never in the doorbell (keeps send-keys to short, escaping-safe single lines).
CANONICAL_DOORBELL = os.environ.get(
    "AGY_DOORBELL",
    "claudavity: check your inbox and act on any request from claude, then reply on the bus.",
)

# Footer markers from the agy TUI. These are TUI-version-specific; override via env if
# agy's footer text changes.
IDLE_MARKER = os.environ.get("AGY_IDLE_MARKER", "? for shortcuts")
BUSY_MARKER = os.environ.get("AGY_BUSY_MARKER", "esc to cancel")

# Pane state constants.
IDLE = "idle"
BUSY = "busy"
DEAD = "dead"
UNKNOWN = "unknown"


class SessionNotFound(RuntimeError):
    """Raised when the target tmux session does not exist or has died."""


async def run_tmux(*args: str) -> tuple[int, str, str]:
    """Run the psmux/tmux binary, returning ``(returncode, stdout, stderr)``."""
    process = await asyncio.create_subprocess_exec(
        TMUX_BIN,
        *args,
        stdin=asyncio.subprocess.DEVNULL,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await process.communicate()
    return (
        process.returncode,
        stdout.decode(errors="replace"),
        stderr.decode(errors="replace"),
    )


async def has_session(session: str = DEFAULT_SESSION) -> bool:
    """True iff the tmux session exists (``has-session`` exits 0)."""
    code, _, _ = await run_tmux("has-session", "-t", session)
    return code == 0


async def capture(session: str = DEFAULT_SESSION) -> str:
    """Return the visible pane content. Raises SessionNotFound if the session is gone."""
    code, out, err = await run_tmux("capture-pane", "-p", "-t", session)
    if code != 0:
        raise SessionNotFound(
            f"capture-pane failed for session {session!r}: {err.strip() or out.strip()}"
        )
    return out


def classify_pane(text: str) -> str:
    """Pure classifier: map captured pane text to IDLE / BUSY / UNKNOWN.

    BUSY takes precedence over IDLE: while agy works, the input line still shows a ``>``
    prompt, but the footer switches to the busy marker — so a stray idle-looking prompt
    must not mask an active turn.
    """
    if BUSY_MARKER in text:
        return BUSY
    if IDLE_MARKER in text:
        return IDLE
    return UNKNOWN


def changed(samples: list[str]) -> bool:
    """Pure: True if any consecutive captures differ (marker-free activity = busy)."""
    return any(a != b for a, b in zip(samples, samples[1:]))


async def busy_by_activity(
    session: str = DEFAULT_SESSION,
    *,
    samples: int = 3,
    interval: float = 1.0,
) -> bool | None:
    """Marker-free busy detector: capture ``samples`` times ``interval`` apart and report
    whether the pane content changed (busy) or stayed identical (idle).

    Returns True (busy), False (idle), or None if the session is gone. This is the
    *fallback* used only when the footer markers are absent (e.g. agy restyled its TUI).
    Caveat: a busy agy that is momentarily silent (mid tool-call) can read as stable, so
    the footer markers are preferred when present; extra samples reduce false idles.
    """
    captures: list[str] = []
    for i in range(max(2, samples)):
        if i:
            await asyncio.sleep(interval)
        try:
            captures.append(await capture(session))
        except SessionNotFound:
            return None
    return changed(captures)


async def pane_state(session: str = DEFAULT_SESSION) -> str:
    """Return IDLE / BUSY / DEAD for the live agy session.

    Fast path: footer markers. If they are absent (UNKNOWN — e.g. the TUI changed), fall
    back to marker-free activity detection so state stays usable across TUI restyles.
    """
    if not await has_session(session):
        return DEAD
    try:
        text = await capture(session)
    except SessionNotFound:
        return DEAD
    state = classify_pane(text)
    if state != UNKNOWN:
        return state
    busy = await busy_by_activity(session)
    if busy is None:
        return DEAD
    return BUSY if busy else IDLE


async def send_keys(session: str, text: str, *, enter: bool = True) -> None:
    """Send literal text to the pane, optionally followed by Enter to submit.

    Uses ``-l`` (literal) so the text is never reinterpreted as key names, then sends
    Enter as a separate key press. Raises SessionNotFound on failure.
    """
    code, _, err = await run_tmux("send-keys", "-t", session, "-l", text)
    if code != 0:
        raise SessionNotFound(
            f"send-keys failed for session {session!r}: {err.strip()}"
        )
    if enter:
        code, _, err = await run_tmux("send-keys", "-t", session, "Enter")
        if code != 0:
            raise SessionNotFound(
                f"send-keys Enter failed for session {session!r}: {err.strip()}"
            )


async def wait_idle(
    session: str = DEFAULT_SESSION,
    *,
    timeout: float = 120.0,
    poll_interval: float = 1.0,
) -> bool:
    """Block until the session is IDLE, or until ``timeout`` seconds elapse.

    Returns True if idle was reached, False on timeout. Raises SessionNotFound if the
    session dies while waiting.
    """
    loop = asyncio.get_event_loop()
    deadline = loop.time() + timeout
    while True:
        state = await pane_state(session)
        if state == IDLE:
            return True
        if state == DEAD:
            raise SessionNotFound(f"session {session!r} is gone while waiting for idle")
        if loop.time() >= deadline:
            return False
        await asyncio.sleep(poll_interval)


async def ring_doorbell(
    session: str = DEFAULT_SESSION,
    *,
    doorbell: str = CANONICAL_DOORBELL,
    idle_gate: bool = True,
    idle_timeout: float = 120.0,
) -> None:
    """Wake the live agy: optionally wait for idle (clean ordering), then send the
    doorbell.

    Doorbell-while-busy is safe (the TUI queues input and processes it as the next
    turn), so ``idle_gate`` is a politeness/ordering optimization, not a correctness
    requirement.
    """
    if idle_gate:
        await wait_idle(session, timeout=idle_timeout)
    await send_keys(session, doorbell, enter=True)


def _main() -> int:
    """Small CLI so the skill/orchestrator (and humans) can drive the doorbell from a
    shell. All subcommands target ``--session`` (default: AGY_SESSION / ``claude_agy``)."""
    import argparse
    import sys

    # The pane content is UTF-8 (Braille spinners, box-drawing). Windows stdout defaults
    # to cp1252, which can't encode it — force UTF-8 so `capture` doesn't crash.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass

    parser = argparse.ArgumentParser(
        description="psmux/agy remote-control primitives (C3)."
    )
    parser.add_argument("--session", default=DEFAULT_SESSION, help="tmux session name")
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("state", help="print pane state: idle/busy/dead/unknown")
    sub.add_parser("capture", help="print the visible pane content")
    p_wait = sub.add_parser(
        "wait-idle", help="block until idle; exit 0 idle, 1 timeout"
    )
    p_wait.add_argument("--timeout", type=float, default=120.0)
    p_ring = sub.add_parser("ring", help="idle-gate then send the doorbell to wake agy")
    p_ring.add_argument("--doorbell", default=CANONICAL_DOORBELL)
    p_ring.add_argument("--no-idle-gate", action="store_true")
    p_ring.add_argument("--idle-timeout", type=float, default=120.0)
    args = parser.parse_args()

    if args.cmd == "state":
        print(asyncio.run(pane_state(args.session)))
        return 0
    if args.cmd == "capture":
        print(asyncio.run(capture(args.session)))
        return 0
    if args.cmd == "wait-idle":
        ok = asyncio.run(wait_idle(args.session, timeout=args.timeout))
        print("idle" if ok else "timeout")
        return 0 if ok else 1
    if args.cmd == "ring":
        asyncio.run(
            ring_doorbell(
                args.session,
                doorbell=args.doorbell,
                idle_gate=not args.no_idle_gate,
                idle_timeout=args.idle_timeout,
            )
        )
        print("rung")
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(_main())
