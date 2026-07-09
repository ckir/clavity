import asyncio
import logging
import json
import uuid
import os
from mcp.server.stdio import stdio_server
from mcp.server import Server
import mcp.types as types
from google.antigravity import Agent, LocalAgentConfig
from google.antigravity.types import McpServerConfig, McpStdioServer

from telemetry import init_db, log_start, log_completion
from isolation import create_worktree, cleanup_worktree, commit_worktree

# Canonical skill governing the sub-agent's JSON output contract. Injected on every
# delegation unless the target workspace ships its own override (see handle_call_tool).
# Resolved relative to this file so it is independent of the process working directory.
CANONICAL_SKILL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "SKILL.md")

# --- Confused-deputy hardening -------------------------------------------------
# The SDK launches its executor (localharness) via subprocess.Popen with no env=,
# so the harness — which runs the delegated sub-agent's run_command shells —
# inherits this process's full os.environ. To stop an untrusted task_prompt from
# exfiltrating host AI-platform credentials, scrub_host_secrets() POPs them out of
# os.environ before we serve (os.environ.pop calls unsetenv, so no child process
# can inherit them) and captures the Gemini key for EXPLICIT pass-through to the
# SDK via LocalAgentConfig(api_key=...) — auth then never needs the key in the env.
#
# Denylist scope is deliberately the infra keys that fund/compromise the agent loop
# ONLY. Operational tokens (GITHUB_TOKEN, NPM_TOKEN, …) are LEFT in place so the
# autonomous coder can still clone private repos and fetch packages — blanket
# *_TOKEN/*_SECRET stripping would neuter it. Extend via AGY_BRIDGE_SCRUB_EXTRA
# (comma-separated names) for paranoid deployments.
_SECRET_ENV_DENYLIST = (
    "GEMINI_API_KEY",
    "GOOGLE_API_KEY",
    "GOOGLE_APPLICATION_CREDENTIALS",
    "ANTHROPIC_API_KEY",
    "CLAUDE_API_KEY",
    "OPENAI_API_KEY",
)

# Captured Gemini key (None when the operator authenticates via Vertex/ADC instead
# of a key). Populated by scrub_host_secrets(); read when building a delegation.
_gemini_api_key: str | None = None


def scrub_host_secrets() -> str | None:
    """Pop host AI-platform credentials from os.environ so the localharness-spawned
    sub-agent shells cannot read them, capturing GEMINI_API_KEY for explicit
    pass-through to the SDK. Idempotent; returns the captured key (or None when
    unset — e.g. Vertex/ADC auth). Operational tokens are deliberately preserved."""
    global _gemini_api_key
    captured = os.environ.pop("GEMINI_API_KEY", None)
    if captured is not None:
        _gemini_api_key = captured
    extra = os.environ.get("AGY_BRIDGE_SCRUB_EXTRA", "")
    names = [n for n in _SECRET_ENV_DENYLIST if n != "GEMINI_API_KEY"]
    names += [n.strip() for n in extra.split(",") if n.strip()]
    for name in names:
        os.environ.pop(name, None)
    return _gemini_api_key


# Ensure .agent exists for logging
os.makedirs(".agent", exist_ok=True)
logging.basicConfig(
    filename=".agent/server.log",
    level=logging.DEBUG,
    format="%(asctime)s %(levelname)s %(message)s",
)
logging.info("Starting server")


def extract_json(text: str) -> dict:
    """Parse a JSON object from agent output that may be wrapped in markdown fences
    or surrounded by prose. Agents rarely emit *pure* JSON, so we scan for the first
    brace-balanced object (respecting string literals) and parse exactly that — which
    is robust to trailing commentary that contains its own braces."""
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    start = text.find("{")
    if start == -1:
        raise json.JSONDecodeError("no '{' in agent output", text, 0)

    depth = 0
    in_str = False
    esc = False
    for i in range(start, len(text)):
        ch = text[i]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        elif ch == '"':
            in_str = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return json.loads(text[start : i + 1])

    raise json.JSONDecodeError("no balanced JSON object in agent output", text, start)


def _build_mcp_servers() -> list[McpServerConfig]:
    """MCP servers exposed to the delegated sub-agent.

    By default the sub-agent runs with ONLY the Antigravity SDK's built-in tools
    (file ops, run_command, …) and no MCP — so it cannot reach the shared
    agentmemory store or any other MCP tool the interactive `agy` CLI has. Wiring
    servers here gives delegated tasks parity. Tool calls fall through to the
    SDK's default-open policy (the existing workspace_only + confirm_run_command
    policies don't match MCP tools), so the wired tools are usable without adding
    an explicit allow policy.

    Default: agentmemory (shared cross-agent memory). On Windows `npx` is a `.cmd`
    shim with no `.exe`, so it must be launched via `cmd /c` (native process spawn
    can't resolve a bare `npx`); elsewhere `npx` is invoked directly. The launched
    `… mcp` process connects to the running agentmemory daemon (:3111) or falls
    back to its standalone store.

    Escape hatch: set AGY_BRIDGE_NO_MCP=1 to restore the previous MCP-less
    behavior (e.g. if the daemon/npx is unavailable and connection setup would
    otherwise fail the delegation, since the SDK aborts startup on a failed MCP
    connect).
    """
    if os.environ.get("AGY_BRIDGE_NO_MCP", "").strip().lower() in ("1", "true", "yes"):
        logging.info("AGY_BRIDGE_NO_MCP set — delegating without MCP servers")
        return []

    if os.name == "nt":
        command, args = "cmd", ["/c", "npx", "@agentmemory/agentmemory", "mcp"]
    else:
        command, args = "npx", ["@agentmemory/agentmemory", "mcp"]

    return [McpStdioServer(name="agentmemory", command=command, args=args)]


server = Server("agy-mcp-bridge")


@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    return [
        types.Tool(
            name="delegate_to_antigravity",
            description="Delegates a codebase modification task to the Antigravity background daemon.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task_prompt": {
                        "type": "string",
                        "description": "The strict instruction for the sub-agent.",
                    },
                    "target_dir": {
                        "type": "string",
                        "description": "The absolute path to the project workspace.",
                    },
                    "timeout_seconds": {
                        "type": "integer",
                        "description": "Dynamic circuit breaker limit (default 120s).",
                        "default": 120,
                    },
                },
                "required": ["task_prompt", "target_dir"],
            },
        )
    ]


@server.call_tool()
async def handle_call_tool(
    name: str, arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    if name != "delegate_to_antigravity":
        raise ValueError(f"Unknown tool: {name}")

    if not arguments:
        raise ValueError("Missing arguments")

    task_prompt = arguments.get("task_prompt")
    target_dir = arguments.get("target_dir")
    timeout_seconds = arguments.get("timeout_seconds", 120)

    # Generate unique task ID
    task_id = str(uuid.uuid4())[:8]

    # Initialize DB
    await init_db(target_dir)
    await log_start(target_dir, task_id, task_prompt)

    worktree_path = None
    success = False
    result_text = ""
    error_payload = None

    try:
        logging.info(f"Task {task_id}: Creating worktree")
        # Create isolated worktree
        worktree_path = await create_worktree(target_dir, task_id)
        logging.info(f"Task {task_id}: Worktree created at {worktree_path}")

        # Inject SKILL path: prefer a per-workspace override, else the canonical skill.
        override_skill = os.path.join(target_dir, ".agent", "mcp_bridge", "SKILL.md")
        skill_path = (
            override_skill if os.path.exists(override_skill) else CANONICAL_SKILL
        )

        mock_response = os.environ.get("MOCK_AGENT_RESPONSE")
        if mock_response:
            logging.info(f"Task {task_id}: Using mock agent response")
            await asyncio.sleep(1)  # Simulate some work
            result_text = mock_response

            try:
                parsed = json.loads(result_text)
                if parsed.get("status") in ["completed", "failed"]:
                    success = True
            except json.JSONDecodeError:
                error_payload = "Mock agent did not return valid JSON."

        else:
            config = LocalAgentConfig(
                system_instructions=(
                    "You are a headless execution sub-agent. Execute the delegated "
                    "task on disk. MCP tools may be available (e.g. agentmemory "
                    "memory_recall/memory_save) — recall relevant shared context "
                    "before acting and save durable cross-agent knowledge when useful. "
                    "When done, reply with ONLY a single short JSON object: "
                    '{"status": "completed"|"failed", "summary": "..."}. '
                    "Two fields only — do not list changed files. No prose, no fences."
                ),
                skills_paths=[skill_path],
                workspaces=[worktree_path],
                mcp_servers=_build_mcp_servers(),
                # Pass the captured key EXPLICITLY (None → SDK drops it and falls
                # back to Vertex/ADC). The key is no longer in os.environ, so the
                # harness cannot leak it to the sub-agent's shells.
                api_key=_gemini_api_key,
            )

            logging.info(f"Task {task_id}: Instantiating Agent")
            async with Agent(config) as agy_sub_agent:
                try:
                    logging.info(
                        f"Task {task_id}: Agent instantiated, waiting for chat completion"
                    )
                    response = await asyncio.wait_for(
                        agy_sub_agent.chat(f"Execute: {task_prompt}"),
                        timeout=timeout_seconds,
                    )
                    result_text = await response.text()
                except asyncio.TimeoutError:
                    error_payload = f"Circuit breaker timeout after {timeout_seconds}s."
                    logging.error(f"Task {task_id}: Timeout")

            # Outcome is derived from committed git changes, NOT the model's
            # self-reported JSON — the agent frequently truncates its final object
            # (ending its turn mid-`files_changed`), which previously failed runs
            # whose work had actually succeeded on disk. The agent text now only
            # supplies a best-effort summary / an explicit failure self-report.
            if error_payload is None:
                agent_status = None
                agent_summary = None
                try:
                    parsed = extract_json(result_text)
                    agent_status = parsed.get("status")
                    agent_summary = parsed.get("summary")
                except json.JSONDecodeError:
                    logging.warning(
                        f"Task {task_id}: agent JSON unparseable/truncated; "
                        f"deriving outcome from git. Raw: {result_text!r}"
                    )

                files_changed = await commit_worktree(target_dir, task_id)

                if agent_status == "failed":
                    # Honor an explicit, parseable failure self-report.
                    error_payload = (
                        f"Agent reported failure: {agent_summary or result_text[:200]}"
                    )
                elif files_changed:
                    success = True
                    result_text = json.dumps(
                        {
                            "status": "completed",
                            "summary": agent_summary
                            or "Sub-agent completed (summary unavailable — truncated output).",
                            "files_changed": files_changed,
                        }
                    )
                else:
                    error_payload = (
                        "Agent produced no committed changes in the worktree."
                    )

    except Exception as e:
        logging.error(f"Task {task_id}: Exception {str(e)}")
        error_payload = f"System Error: {str(e)}"

    finally:
        logging.info(f"Task {task_id}: Cleanup")
        # Log completion
        status_str = "success" if success else "failed"
        await log_completion(
            target_dir, task_id, status_str, tokens_used=0, final_error=error_payload
        )

        # Cleanup worktree
        if worktree_path:
            try:
                await cleanup_worktree(target_dir, task_id, success=success)
            except Exception as e:
                # If cleanup fails (e.g., merge conflict), let the error propagate
                if not error_payload:
                    error_payload = f"Worktree cleanup failed: {str(e)}"
                success = False

    # Return final result to Claude
    if success:
        return [types.TextContent(type="text", text=result_text)]
    else:
        failure_json = {"status": "failed", "error": error_payload or "Unknown error"}
        return [types.TextContent(type="text", text=json.dumps(failure_json))]


async def main():
    # Scrub host AI-platform credentials BEFORE serving any delegation (and before
    # any harness subprocess can inherit os.environ). Captures GEMINI_API_KEY for
    # explicit pass-through. See scrub_host_secrets() / _SECRET_ENV_DENYLIST.
    scrub_host_secrets()
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream, write_stream, server.create_initialization_options()
        )


if __name__ == "__main__":
    asyncio.run(main())
