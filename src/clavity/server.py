"""clavity MCP server (Phase 1): one tool, `ask_agy`. Entry point: `clavity-mcp`.

Standard stdio MCP — no `claude/channel` capability yet (that is Phase 2). The
tool logic is factored into `handle_ask_agy` so it is unit-testable without the
MCP transport.
"""

from __future__ import annotations

import anyio
from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import TextContent, Tool

from .agy import AgyError, run_agy
from .config import load_env

ASK_AGY = Tool(
    name="ask_agy",
    description=(
        "Delegate a task to a fresh headless Antigravity (agy) sub-agent running in "
        "the current project folder; returns agy's result. Use for reviews, second "
        "opinions, or analysis you want agy to do."
    ),
    inputSchema={
        "type": "object",
        "properties": {"task": {"type": "string", "description": "What agy should do."}},
        "required": ["task"],
    },
)


async def handle_ask_agy(arguments: dict) -> str:
    """Await the (async) agy delegation; return its text (or an ERROR: line)."""
    task = arguments.get("task", "")
    try:
        result = await run_agy(task)
    except AgyError as exc:
        return f"ERROR: {exc}"
    return result["output"]


def build_server() -> Server:
    server: Server = Server("clavity")

    @server.list_tools()
    async def _list_tools() -> list[Tool]:
        return [ASK_AGY]

    @server.call_tool()
    async def _call_tool(name: str, arguments: dict) -> list[TextContent]:
        if name != "ask_agy":
            raise ValueError(f"unknown tool: {name}")
        text = await handle_ask_agy(arguments)
        return [TextContent(type="text", text=text)]

    return server


async def _run() -> None:
    server = build_server()
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


def main() -> None:
    load_env()
    anyio.run(_run)
