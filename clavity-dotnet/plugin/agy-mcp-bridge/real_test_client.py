"""Real (non-mock) end-to-end test for the claudavity MCP bridge.

Unlike test_client.py (which mocks the agent via MOCK_AGENT_RESPONSE), this drives the
real google.antigravity Agent. It is fully self-contained: it creates a throwaway git
repo, installs SKILL.md, runs a real delegation, verifies the file was created AND merged
back into the sandbox, then deletes the sandbox.

Auth: reads GEMINI_API_KEY from a local .env (never printed). Get a free key at
https://aistudio.google.com/app/apikey.

Run:  uv run python real_test_client.py
"""

import asyncio
import os
import shutil
import subprocess
import sys
import tempfile

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

HERE = os.path.dirname(os.path.abspath(__file__))
TASK = "Create a file named hello_from_subagent.txt containing exactly: It works!"
EXPECTED_FILE = "hello_from_subagent.txt"


def _load_dotenv(path: str) -> None:
    """Load KEY=VALUE pairs from a .env into os.environ (no value is printed)."""
    if not os.path.exists(path):
        return
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            os.environ.setdefault(key.strip(), val.strip().strip('"').strip("'"))


def _git(cwd: str, *args: str) -> None:
    subprocess.run(["git", "-C", cwd, *args], check=True, capture_output=True)


def make_sandbox() -> str:
    """Create a throwaway git repo with SKILL.md installed; return its path."""
    sandbox = tempfile.mkdtemp(prefix="claudavity-realtest-")
    _git(sandbox, "init", "-q")
    with open(os.path.join(sandbox, "README.md"), "w", encoding="utf-8") as f:
        f.write("# claudavity real-test sandbox\n")
    _git(sandbox, "add", "-A")
    _git(
        sandbox,
        "-c",
        "user.email=test@test",
        "-c",
        "user.name=test",
        "commit",
        "-qm",
        "init",
    )
    skill_dir = os.path.join(sandbox, ".agent", "mcp_bridge")
    os.makedirs(skill_dir, exist_ok=True)
    shutil.copy(os.path.join(HERE, "SKILL.md"), os.path.join(skill_dir, "SKILL.md"))
    return sandbox


async def main() -> int:
    _load_dotenv(os.path.join(HERE, ".env"))
    if os.environ.get("GEMINI_API_KEY", "").strip() in ("", "paste-your-key-here"):
        print("ERROR: GEMINI_API_KEY not set in .env (still the placeholder).")
        return 1

    env = os.environ.copy()
    env.pop("MOCK_AGENT_RESPONSE", None)  # ensure the REAL agent path runs

    sandbox = make_sandbox()
    print(f"Sandbox: {sandbox}")
    try:
        server_params = StdioServerParameters(
            command=sys.executable, args=["server.py"], env=env
        )
        print(f"Task: {TASK}\nConnecting to server.py (REAL agent path)...\n")
        async with stdio_client(server_params) as (read, write):
            async with ClientSession(read, write) as session:
                await session.initialize()
                result = await session.call_tool(
                    "delegate_to_antigravity",
                    arguments={
                        "task_prompt": TASK,
                        "target_dir": sandbox,
                        "timeout_seconds": 180,
                    },
                )
                print("==== JSON Result Payload ====")
                for content in result.content:
                    print(content.text)
                print("=============================\n")

        # Verify the round-trip actually persisted into the sandbox.
        merged = os.path.join(sandbox, EXPECTED_FILE)
        if os.path.exists(merged):
            with open(merged, encoding="utf-8") as f:
                print(f"VERIFIED: {EXPECTED_FILE} merged into sandbox -> {f.read()!r}")
            log = subprocess.run(
                ["git", "-C", sandbox, "log", "--oneline", "-3"],
                capture_output=True,
                text=True,
            )
            print("git log:\n" + log.stdout)
            return 0
        print(
            f"FAILED: {EXPECTED_FILE} not found in sandbox root (merge did not persist)."
        )
        return 1
    finally:
        # worktrees hold the dir open; prune then remove.
        subprocess.run(["git", "-C", sandbox, "worktree", "prune"], capture_output=True)
        shutil.rmtree(sandbox, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
