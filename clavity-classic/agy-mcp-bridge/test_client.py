import asyncio
import os
import sys
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


async def main():
    # Define how to start our MCP server subprocess
    # We use the current python executable to run server.py
    env = os.environ.copy()
    env["MOCK_AGENT_RESPONSE"] = '{"status": "completed", "summary": "Success!"}'

    server_params = StdioServerParameters(
        command=sys.executable, args=["server.py"], env=env
    )

    print("Starting MCP Client and connecting to server.py...")

    # Establish the stdio connection
    async with stdio_client(server_params) as (read, write):
        async with ClientSession(read, write) as session:
            # Must initialize the session before calling tools
            await session.initialize()
            print("Connected and initialized.\n")

            # List tools to verify our server is working
            tools = await session.list_tools()
            print(f"Available tools: {[t.name for t in tools.tools]}\n")

            # Use the current directory as the target workspace
            target_directory = os.path.abspath(".")

            print(f"Calling 'delegate_to_antigravity' in {target_directory}...")
            print(
                "This will take a moment as the sub-agent creates a worktree and executes the task.\n"
            )

            try:
                # Execute the tool
                result = await session.call_tool(
                    "delegate_to_antigravity",
                    arguments={
                        "task_prompt": "Create a dummy file named 'hello_from_subagent.txt' containing 'It works!'",
                        "target_dir": target_directory,
                        "timeout_seconds": 120,
                    },
                )

                print("====================================")
                print("Task Completed!")
                print("JSON Result Payload:")
                for content in result.content:
                    print(content.text)
                print("====================================")

            except Exception as e:
                print(f"\nError calling tool: {e}")


if __name__ == "__main__":
    asyncio.run(main())
