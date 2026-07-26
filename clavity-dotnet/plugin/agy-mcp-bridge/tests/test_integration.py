import pytest
import os
import sys
import json
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
import aiosqlite


@pytest.mark.asyncio
async def test_mcp_server_available():
    env = os.environ.copy()
    env["MOCK_AGENT_RESPONSE"] = json.dumps({"status": "completed"})

    server_params = StdioServerParameters(
        command=sys.executable, args=["server.py"], env=env
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # Make sure the delegate_to_antigravity tool is registered
            tools = await session.list_tools()
            tool_names = [t.name for t in tools.tools]
            assert "delegate_to_antigravity" in tool_names


@pytest.mark.asyncio
async def test_delegate_to_antigravity_execution():
    # We use the current directory because isolation requires an active git repo
    target_directory = os.path.abspath(".")

    env = os.environ.copy()
    env["MOCK_AGENT_RESPONSE"] = json.dumps(
        {"status": "completed", "summary": "Mocked creation"}
    )

    server_params = StdioServerParameters(
        command=sys.executable, args=["server.py"], env=env
    )

    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            await session.initialize()

            # We trigger a very small, bounded task to test the entire bridge
            result = await session.call_tool(
                "delegate_to_antigravity",
                arguments={
                    "task_prompt": "Create a dummy file called pytest_artifact.txt containing the word 'SUCCESS'.",
                    "target_dir": target_directory,
                    "timeout_seconds": 60,
                },
            )

            # The result should be parseable JSON according to our SKILL
            assert len(result.content) == 1
            try:
                response_json = json.loads(result.content[0].text)
            except json.JSONDecodeError:
                pytest.fail(
                    f"Agent did not return valid JSON: {result.content[0].text}"
                )

            assert response_json.get("status") in ["completed", "failed"]

            # Verify the telemetry database recorded the invocation
            db_path = os.path.join(target_directory, ".agent", "telemetry.db")
            assert os.path.exists(db_path)

            async with aiosqlite.connect(db_path) as db:
                cursor = await db.execute(
                    "SELECT status FROM invocations ORDER BY start_time DESC LIMIT 1"
                )
                row = await cursor.fetchone()
                assert row is not None
                assert row[0] in ["success", "failed", "timeout"]

    # Cleanup the artifact
    artifact_path = os.path.join(target_directory, "pytest_artifact.txt")
    if os.path.exists(artifact_path):
        os.remove(artifact_path)
