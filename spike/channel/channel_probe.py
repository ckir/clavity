#!/usr/bin/env python
"""clavity channel-feasibility probe — Phase 2 spike, Half B.

A minimal stdio MCP server, written with the Python `mcp` SDK, that:
  1. declares Claude Code's experimental `claude/channel` capability, and
  2. ~`PUSH_DELAY_SECONDS` after a client connects, PUSHES one
     `notifications/claude/channel` event (the custom method the channels
     contract expects), built by writing a raw SessionMessage to the session
     write stream.

Purpose: test whether an IDLE Claude Code session — launched with
`--dangerously-load-development-channels server:channel-probe` — actually wakes
and acts on a server-pushed channel event (the load-bearing assumption for v2
Phase 2's agy->Claude direction).

Half A (already proven hermetically): the Python `mcp` SDK supports both the
capability declaration and the custom notification. This probe is Half B.
"""

from __future__ import annotations

from contextlib import AsyncExitStack

import anyio
from mcp.server.lowlevel import Server
from mcp.server.session import ServerSession
from mcp.server.stdio import stdio_server
from mcp.shared.message import SessionMessage
from mcp.types import JSONRPCMessage, JSONRPCNotification, Tool

PUSH_DELAY_SECONDS = 5
CHANNEL_CONTENT = (
    "Channel probe test from clavity. If you can read this and you are Claude Code, "
    "reply in the session with exactly: CHANNEL-WAKE-OK"
)

server: Server = Server("clavity-channel-probe")


@server.list_tools()
async def _list_tools() -> list[Tool]:
    # One-way channel: no tools needed.
    return []


async def _push_channel_event(session: ServerSession) -> None:
    """Spontaneously emit one `notifications/claude/channel` after a delay.

    Mirrors what `BaseSession.send_notification` does internally, but for a
    CUSTOM method the typed `send_notification` won't accept: build the
    JSONRPCNotification and write the SessionMessage straight to the write stream.
    """
    import sys

    await anyio.sleep(PUSH_DELAY_SECONDS)
    notif = JSONRPCNotification(
        jsonrpc="2.0",
        method="notifications/claude/channel",
        params={"content": CHANNEL_CONTENT, "meta": {"source": "clavity-probe"}},
    )
    # Raw write: the typed `send_notification` won't accept a custom method, so we
    # write the SessionMessage directly to the session write stream (Half A finding).
    await session._write_stream.send(SessionMessage(message=JSONRPCMessage(notif)))
    print("clavity-channel-probe: pushed notifications/claude/channel", file=sys.stderr, flush=True)


async def serve(read_stream, write_stream) -> None:
    """Run the MCP message loop AND the spontaneous push task on one session.

    Replicates `Server.run`'s setup so we get a handle on the live session to
    push from a side task.
    """
    init = server.create_initialization_options(
        experimental_capabilities={"claude/channel": {}}
    )
    async with AsyncExitStack() as stack:
        lifespan_ctx = await stack.enter_async_context(server.lifespan(server))
        session = await stack.enter_async_context(
            ServerSession(read_stream, write_stream, init)
        )
        async with anyio.create_task_group() as tg:
            tg.start_soon(_push_channel_event, session)
            async for message in session.incoming_messages:
                tg.start_soon(server._handle_message, message, session, lifespan_ctx, False)


async def _main() -> None:
    async with stdio_server() as (read_stream, write_stream):
        await serve(read_stream, write_stream)


def main() -> None:
    anyio.run(_main)


if __name__ == "__main__":
    main()
