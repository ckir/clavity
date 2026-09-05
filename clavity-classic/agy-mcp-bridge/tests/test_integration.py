import pytest
import os
import sys
import json
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
import aiosqlite

# OPT-IN ONLY. Both tests below are SELF-SKIPPING unless CLAVITY_RUN_INTEGRATION_TESTS is set.
#
# They are not unsafe in the "spawns a live agent" sense - both set MOCK_AGENT_RESPONSE, so the agent
# itself is mocked. They are gated because they MUTATE THE CURRENT WORKING DIRECTORY: target_directory
# is os.path.abspath("."), the bridge writes .agent/telemetry.db there, and the second test creates and
# removes pytest_artifact.txt there. Whatever directory pytest is invoked from is what gets written to,
# which makes them unfit for a routine `just` recipe or a bare `pytest` at the bridge root.
#
# Before this guard existed, a plain `pytest` collected these two alongside the 24 hermetic tests with
# nothing to stop them - which is why clavity-classic/justfile lists its test files EXPLICITLY rather
# than pointing at a directory. This marker makes the file safe on its own, so the recipe's explicit
# list is no longer the only thing standing between a routine run and a mutated working directory.
#
# Skip-by-default is right for a developer box AND for CI: a run that silently writes a telemetry
# database into the checkout is not something to opt out of, it is something to opt IN to. Set
# CLAVITY_RUN_INTEGRATION_TESTS=1 (or run `just classic::pytest-integration`) to exercise them.
pytestmark = pytest.mark.skipif(
    not os.environ.get("CLAVITY_RUN_INTEGRATION_TESTS"),
    reason=(
        "integration tests mutate the current working directory "
        "(.agent/telemetry.db, pytest_artifact.txt); "
        "set CLAVITY_RUN_INTEGRATION_TESTS=1 to opt in"
    ),
)


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
