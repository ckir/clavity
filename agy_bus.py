"""agentmemory signal-bus conventions for the agy remote control (components C5 + C1 core).

The bus is driven by the MCP tools ``memory_signal_send`` / ``memory_signal_read``, which
only the agent runtime (Claude / agy) can call. This module holds the *pure* conventions
both sides agree on — request-id minting, the request ``content`` envelope, and response
correlation — so they are unambiguous and unit-testable. It performs no I/O.

Correlation contract (see the C2 responder skill):
  - Claude sends a ``request`` whose ``content`` starts with a ``[req_id=...]`` tag.
  - agy replies with a ``response`` that **sets ``replyTo`` to the request's signal id**
    (robust) and echoes the ``req_id`` in its ``content`` (fallback).
  - ``match_response`` accepts either signal, so a reply still correlates even if agy
    forgets one of the two.
"""

import re
import uuid

# agentId names on the bus.
CLAUDE = "claude"
AGY = "agy"

# Message types (the agentmemory signal ``type`` field).
REQUEST = "request"
RESPONSE = "response"
INFO = "info"
ALERT = "alert"

_REQ_ID_RE = re.compile(r"\[req_id=([A-Za-z0-9._-]+)\]")


def new_req_id() -> str:
    """Mint a short, unique request id, e.g. ``req-1a2b3c4d``."""
    return "req-" + uuid.uuid4().hex[:8]


def make_request(req_id: str, instruction: str) -> str:
    """Build a request ``content``: a leading ``[req_id=...]`` tag then the instruction.

    The tag lets agy echo the id back and lets Claude correlate the response even when the
    bus opens a fresh thread.
    """
    return f"[req_id={req_id}] {instruction}"


def extract_req_id(content: str | None) -> str | None:
    """Return the ``req_id`` embedded in a message ``content``, or None."""
    if not content:
        return None
    m = _REQ_ID_RE.search(content)
    return m.group(1) if m else None


def match_response(
    signals: list[dict],
    req_id: str,
    request_signal_id: str | None = None,
) -> dict | None:
    """Find the response for ``req_id`` among inbox ``signals``.

    A signal matches if its ``replyTo`` equals the original request's signal id (robust),
    or if its ``content`` contains the ``req_id`` (fallback — agy may echo it bare or
    tagged). Returns the first matching signal in iteration order, else None.
    """
    for s in signals:
        if request_signal_id and s.get("replyTo") == request_signal_id:
            return s
        content = s.get("content") or ""
        if req_id and req_id in content:
            return s
    return None
