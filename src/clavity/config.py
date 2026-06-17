"""Load credentials from a .env file at process startup.

Looks for a project-local `./.env`, then a user-level `~/.clavity/.env`. Both are
loaded with `override=False`, so a value already present in the real environment
always wins. This lets the user drop `GEMINI_API_KEY` in a `.env` file instead of
exporting it before launching Claude / agy (the MCP server is spawned as a
subprocess, so a file is more convenient than the inherited shell env).
"""

from __future__ import annotations

from pathlib import Path

from dotenv import load_dotenv


def load_env() -> None:
    """Populate os.environ from .env files (project-local first, then ~/.clavity).

    Idempotent and safe to call at every entry point; never overrides a variable
    that is already set in the real environment.
    """
    load_dotenv(Path.cwd() / ".env", override=False)
    load_dotenv(Path.home() / ".clavity" / ".env", override=False)
