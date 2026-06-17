"""Delegate a task to a fresh headless agy sub-agent via the google-antigravity SDK.

The SDK surface is isolated in `_invoke_sdk` so (a) tests can mock it and (b) the
exact API lives in one place. The body below matches docs/agy-sdk-notes.md
(google-antigravity==0.1.3); if the SDK changes, the notes win.
"""

from __future__ import annotations

from pathlib import Path

from .auth import resolve_api_key


class AgyError(RuntimeError):
    """A headless agy delegation failed."""


async def _invoke_sdk(task: str, cwd: str, api_key: str) -> str:
    """Run a headless agy one-shot in `cwd` and return its final text.

    Real API per docs/agy-sdk-notes.md: `from google.antigravity import Agent,
    LocalAgentConfig`; `Agent` is an async context manager; `chat()` and
    `response.text()` are coroutines; `workspaces=[cwd]` sets the file scope;
    `policies=[]` is read-only (no writes without confirm — safe for Phase 1
    review/analysis delegation).
    """
    from google.antigravity import Agent, LocalAgentConfig

    config = LocalAgentConfig(workspaces=[cwd], api_key=api_key, policies=[])
    async with Agent(config) as agent:
        response = await agent.chat(task)
        return await response.text()


async def run_agy(task: str, cwd: str | None = None) -> dict:
    """Delegate `task` to a fresh headless agy in `cwd`. Returns
    {"ok": True, "output": <str>} or raises AgyError."""
    if not task.strip():
        raise AgyError("empty task")
    cwd = cwd or str(Path.cwd())
    api_key = resolve_api_key()
    try:
        output = await _invoke_sdk(task, cwd, api_key)
    except Exception as exc:  # noqa: BLE001 — surface any SDK failure uniformly
        raise AgyError(f"agy delegation failed: {exc}") from exc
    return {"ok": True, "output": output}
