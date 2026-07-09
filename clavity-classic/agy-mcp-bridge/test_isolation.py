import asyncio
import os
import sys

# add current dir to sys.path
sys.path.insert(0, os.path.abspath("."))
from isolation import run_git_command


async def main():
    print("Testing git command...")
    code, out, err = await run_git_command(".", "status")
    print(f"Code: {code}")
    print(f"Out: {out}")
    print(f"Err: {err}")


if __name__ == "__main__":
    asyncio.run(main())
