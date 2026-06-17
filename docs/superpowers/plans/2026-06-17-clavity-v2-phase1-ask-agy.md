# clavity v2 — Phase 1: Synchronous Claude→agy Bridge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an all-Python MCP server exposing an `ask_agy` tool that delegates a task to a fresh headless Antigravity (agy) sub-agent — running in the live project folder via the `google-antigravity` SDK with stable non-interactive auth — and returns its result to Claude.

**Architecture:** A standard stdio MCP server (`clavity-mcp`) with one tool, `ask_agy`. The tool resolves a non-interactive credential, runs the agy SDK in a worker thread, and returns the output. No daemon, no channels, no agentmemory — Phase 2 adds the bidirectional async layer (daemon bus + `claude/channel` wake + watchers).

**Tech Stack:** Python ≥3.11, **uv** (project + scripts + `uv tool install` distribution), the **MCP Python SDK** (`mcp`), the **`google-antigravity`** SDK, `pytest` + `pytest-asyncio`.

**Spec:** `docs/superpowers/specs/2026-06-17-clavity-v2-bidirectional-bridge-design.md` (this plan implements §4.4 agy spawn-driver, §4.5 packaging, §3 D3/D6, and the §8.2 credential default; the daemon/channel/watchers in §4.2–4.3 are Phase 2).

**Scope boundary:** Phase 1 delivers **Claude→agy** only (synchronous). It does **not** wake an idle Claude (no `claude/channel`) and does **not** run the daemon/bus/watchers — those are Phase 2.

---

## File Structure

| Path | Responsibility |
|---|---|
| `pyproject.toml` | uv project `clavity`; console scripts `clavity`, `clavity-mcp`; deps |
| `src/clavity/__init__.py` | package marker + version |
| `src/clavity/auth.py` | `resolve_credential()` — non-interactive agy credential → env dict |
| `src/clavity/agy.py` | `run_agy()` + isolated `_invoke_sdk()` — headless agy via the SDK |
| `src/clavity/server.py` | MCP server: `ask_agy` tool (entry point `clavity-mcp`) |
| `src/clavity/cli.py` | launcher: `clavity doctor` / `clavity info` (entry point `clavity`) |
| `tests/test_auth.py` `tests/test_agy.py` `tests/test_server.py` `tests/test_cli.py` | unit tests |
| `plugins/clavity/` | the universal dual-plugin manifests + skill |
| `docs/agy-sdk-notes.md` | Task 2 spike output: the verified SDK surface |

---

## Task 1: Retire the Rust skeleton; establish the uv Python project

**Files:**
- Delete: `Cargo.toml`, `crates/`, `xtask/`, `plugins/scaffold/` (Rust skeleton — preserved in git history and on the `v1` branch)
- Create: `pyproject.toml`, `src/clavity/__init__.py`, `tests/__init__.py`, `.gitignore` (update)

- [ ] **Step 1: Verify state**

Run: `git rev-parse --abbrev-ref HEAD`
Expected: `main`. If not, STOP and report `STATE_MISMATCH: not on main`.

- [ ] **Step 2: Remove the Rust skeleton**

```bash
git rm -r Cargo.toml crates xtask plugins/scaffold
```
Expected: those paths staged for deletion. (`plugins/` remains for `plugins/clavity/`; `docs/`, `samples/`, `README.md`, `LICENSE` stay.)

- [ ] **Step 3: Write `pyproject.toml`**

```toml
[project]
name = "clavity"
version = "0.2.0"
description = "Bidirectional Claude<->Antigravity bridge (Phase 1: synchronous ask_agy)."
requires-python = ">=3.11"
dependencies = [
    "mcp>=1.2",
    "google-antigravity",
]

[project.scripts]
clavity = "clavity.cli:main"
clavity-mcp = "clavity.server:main"

[dependency-groups]
dev = ["pytest>=8", "pytest-asyncio>=0.23"]

[tool.pytest.ini_options]
asyncio_mode = "auto"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"
```

- [ ] **Step 4: Create the package + test markers**

`src/clavity/__init__.py`:
```python
"""clavity — bidirectional Claude<->Antigravity bridge."""

__version__ = "0.2.0"
```

`tests/__init__.py`:
```python
```

- [ ] **Step 5: Update `.gitignore`**

Overwrite `.gitignore`:
```gitignore
/target
/dist
.venv/
__pycache__/
*.pyc
.pytest_cache/
```

- [ ] **Step 6: Sync the environment and confirm it builds**

Run: `uv sync`
Expected: resolves and installs `mcp`, `google-antigravity`, and dev deps into `.venv` with no error. (If `google-antigravity` fails to resolve from the index, confirm the exact package name with the user — it is already installed for the existing `agy-mcp-bridge`.)

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "chore: retire Rust skeleton; establish uv Python project for clavity v2"
```

---

## Task 2: SPIKE — pin the `google-antigravity` SDK surface

**Files:**
- Create: `docs/agy-sdk-notes.md`

This is a verification spike (spec §8). It records the EXACT SDK API so `_invoke_sdk` (Task 4) is correct, not guessed. No production code.

- [ ] **Step 1: Inspect the installed SDK**

Run:
```bash
uv run python -c "import google_antigravity as g; print(g.__file__); print([n for n in dir(g) if not n.startswith('_')])"
```
Expected: prints the package path and its public names (e.g. an `Agent` / config class). If the import name differs (e.g. `antigravity`), note the real one.

- [ ] **Step 2: Find the headless chat entry point and auth/cwd knobs**

Run:
```bash
uv run python -c "import google_antigravity as g, inspect; A=getattr(g,'Agent',None); print(inspect.signature(A.__init__) if A else 'no Agent'); print(inspect.signature(A.chat) if A and hasattr(A,'chat') else 'no chat')"
```
Expected: the constructor signature (how to set the working directory) and the `chat` signature (how to pass the prompt, what it returns). Also check how the SDK reads auth (does it honor `GEMINI_API_KEY` env, per agy's `req-djbgp9ij…`?).

- [ ] **Step 3: Record findings in `docs/agy-sdk-notes.md`**

Write the file with: the exact import name, the exact constructor call to set `working_directory`/cwd, the exact `chat(prompt)` call and its return type, and the confirmed env var(s) for non-interactive auth. Include a minimal verified snippet. Mark anything still uncertain as `UNVERIFIED`.

- [ ] **Step 4: Commit**

```bash
git add docs/agy-sdk-notes.md
git commit -m "docs: pin google-antigravity SDK surface for the agy spawn-driver"
```

> **Oracle for Task 4:** `docs/agy-sdk-notes.md` is the source of truth for `_invoke_sdk`. If the real API differs from the snippet in Task 4, follow `agy-sdk-notes.md` and adjust the code (do not adjust tests — they mock `_invoke_sdk`).

---

## Task 3: `auth.py` — resolve a non-interactive credential (TDD)

**Files:**
- Create: `src/clavity/auth.py`, `tests/test_auth.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_auth.py`:
```python
import pytest
from clavity.auth import resolve_credential, AuthError


def test_prefers_gemini_api_key():
    env = {"GEMINI_API_KEY": "k1", "GOOGLE_API_KEY": "k2"}
    assert resolve_credential(env) == {"GEMINI_API_KEY": "k1"}


def test_falls_back_to_google_api_key():
    env = {"GOOGLE_API_KEY": "k2"}
    assert resolve_credential(env) == {"GOOGLE_API_KEY": "k2"}


def test_service_account_path_when_present(tmp_path):
    sa = tmp_path / "sa.json"
    sa.write_text("{}")
    env = {"GOOGLE_APPLICATION_CREDENTIALS": str(sa)}
    assert resolve_credential(env) == {"GOOGLE_APPLICATION_CREDENTIALS": str(sa)}


def test_raises_when_no_credential():
    with pytest.raises(AuthError):
        resolve_credential({})
```

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/test_auth.py -q`
Expected: FAIL — `ModuleNotFoundError: clavity.auth`.

- [ ] **Step 3: Implement**

`src/clavity/auth.py`:
```python
"""Resolve a non-interactive credential for the headless agy SDK (spec §8.2).

Precedence: GEMINI_API_KEY, then GOOGLE_API_KEY, then a service-account JSON at
GOOGLE_APPLICATION_CREDENTIALS. (Reusing the interactive OAuth refresh_token is a
verify-at-impl alternative; not implemented here.)
"""

from __future__ import annotations

import os


class AuthError(RuntimeError):
    """No usable non-interactive agy credential was found."""


def resolve_credential(env: dict[str, str] | None = None) -> dict[str, str]:
    env = os.environ if env is None else env
    if env.get("GEMINI_API_KEY"):
        return {"GEMINI_API_KEY": env["GEMINI_API_KEY"]}
    if env.get("GOOGLE_API_KEY"):
        return {"GOOGLE_API_KEY": env["GOOGLE_API_KEY"]}
    sa = env.get("GOOGLE_APPLICATION_CREDENTIALS")
    if sa and os.path.exists(sa):
        return {"GOOGLE_APPLICATION_CREDENTIALS": sa}
    raise AuthError(
        "No non-interactive agy credential found. Set GEMINI_API_KEY (or GOOGLE_API_KEY, "
        "or GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account JSON)."
    )
```

- [ ] **Step 4: Run to verify pass**

Run: `uv run pytest tests/test_auth.py -q`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/clavity/auth.py tests/test_auth.py
git commit -m "feat(auth): resolve non-interactive agy credential"
```

---

## Task 4: `agy.py` — headless agy via the SDK (TDD, SDK isolated)

**Files:**
- Create: `src/clavity/agy.py`, `tests/test_agy.py`

- [ ] **Step 1: Write the failing tests** (they mock `_invoke_sdk`, so no real SDK/auth needed)

`tests/test_agy.py`:
```python
import pytest
import clavity.agy as agy
from clavity.agy import run_agy, AgyError


def test_empty_task_raises():
    with pytest.raises(AgyError):
        run_agy("   ")


def test_success_returns_output(monkeypatch):
    monkeypatch.setattr(agy, "resolve_credential", lambda: {"GEMINI_API_KEY": "k"})
    monkeypatch.setattr(agy, "_invoke_sdk", lambda task, cwd, cred_env: f"did: {task}")
    result = run_agy("review foo.py", cwd="/tmp/proj")
    assert result == {"ok": True, "output": "did: review foo.py"}


def test_sdk_failure_becomes_agyerror(monkeypatch):
    monkeypatch.setattr(agy, "resolve_credential", lambda: {"GEMINI_API_KEY": "k"})

    def boom(task, cwd, cred_env):
        raise RuntimeError("sdk exploded")

    monkeypatch.setattr(agy, "_invoke_sdk", boom)
    with pytest.raises(AgyError) as exc:
        run_agy("x")
    assert "sdk exploded" in str(exc.value)
```

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/test_agy.py -q`
Expected: FAIL — `ModuleNotFoundError: clavity.agy`.

- [ ] **Step 3: Implement** (the `_invoke_sdk` body follows `docs/agy-sdk-notes.md` from Task 2 — adjust the SDK call to the verified surface)

`src/clavity/agy.py`:
```python
"""Delegate a task to a fresh headless agy sub-agent via the google-antigravity SDK.

The SDK surface is isolated in `_invoke_sdk` so (a) tests can mock it and (b) the
exact API lives in one place. The body below MUST match docs/agy-sdk-notes.md
(plan Task 2 spike); if they differ, the notes win.
"""

from __future__ import annotations

import os
from pathlib import Path

from .auth import resolve_credential


class AgyError(RuntimeError):
    """A headless agy delegation failed."""


def _invoke_sdk(task: str, cwd: str, cred_env: dict[str, str]) -> str:
    """Run agy headlessly and return its final text output. Verify the SDK call
    against docs/agy-sdk-notes.md (Task 2)."""
    from google_antigravity import Agent, AgentConfig  # verify names in Task 2

    previous = {k: os.environ.get(k) for k in cred_env}
    os.environ.update(cred_env)
    try:
        agent = Agent(AgentConfig(working_directory=cwd))
        return agent.chat(task)
    finally:
        for key, old in previous.items():
            if old is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = old


def run_agy(task: str, cwd: str | None = None) -> dict:
    """Delegate `task` to a fresh headless agy in `cwd`. Returns
    {"ok": True, "output": <str>} or raises AgyError."""
    if not task.strip():
        raise AgyError("empty task")
    cwd = cwd or str(Path.cwd())
    cred_env = resolve_credential()
    try:
        output = _invoke_sdk(task, cwd, cred_env)
    except Exception as exc:  # noqa: BLE001 — surface any SDK failure uniformly
        raise AgyError(f"agy delegation failed: {exc}") from exc
    return {"ok": True, "output": output}
```

- [ ] **Step 4: Run to verify pass**

Run: `uv run pytest tests/test_agy.py -q`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/clavity/agy.py tests/test_agy.py
git commit -m "feat(agy): headless agy spawn-driver over the SDK (isolated, stable auth)"
```

---

## Task 5: `server.py` — the `ask_agy` MCP tool (TDD)

**Files:**
- Create: `src/clavity/server.py`, `tests/test_server.py`

- [ ] **Step 1: Write the failing tests** (test the pure handler `handle_ask_agy`, mocking `run_agy`)

`tests/test_server.py`:
```python
import pytest
import clavity.server as srv


@pytest.mark.asyncio
async def test_handle_ask_agy_returns_output(monkeypatch):
    monkeypatch.setattr(srv, "run_agy", lambda task: {"ok": True, "output": f"ran {task}"})
    text = await srv.handle_ask_agy({"task": "review foo"})
    assert text == "ran review foo"


@pytest.mark.asyncio
async def test_handle_ask_agy_reports_error(monkeypatch):
    def boom(task):
        raise srv.AgyError("no creds")

    monkeypatch.setattr(srv, "run_agy", boom)
    text = await srv.handle_ask_agy({"task": "x"})
    assert text.startswith("ERROR:")
    assert "no creds" in text


def test_build_server_lists_ask_agy_tool():
    server = srv.build_server()
    assert server.name == "clavity"
```

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/test_server.py -q`
Expected: FAIL — `ModuleNotFoundError: clavity.server`.

- [ ] **Step 3: Implement**

`src/clavity/server.py`:
```python
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

ASK_AGY = Tool(
    name="ask_agy",
    description=(
        "Delegate a task to a fresh headless Antigravity (agy) sub-agent running in "
        "the current project folder; returns agy's result. Use for reviews, second "
        "opinions, or work you want agy to do."
    ),
    inputSchema={
        "type": "object",
        "properties": {"task": {"type": "string", "description": "What agy should do."}},
        "required": ["task"],
    },
)


async def handle_ask_agy(arguments: dict) -> str:
    """Run the agy delegation off the event loop; return text (or an ERROR: line)."""
    task = arguments.get("task", "")
    try:
        result = await anyio.to_thread.run_sync(run_agy, task)
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
    anyio.run(_run)
```

- [ ] **Step 4: Run to verify pass**

Run: `uv run pytest tests/test_server.py -q`
Expected: PASS (3 tests).

- [ ] **Step 5: Smoke-test the server starts and lists the tool**

Run:
```bash
printf '%s\n%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | uv run clavity-mcp
```
Expected: two JSON-RPC response lines on stdout; the second contains `"name":"ask_agy"`. (Diagnostics, if any, go to stderr.)

- [ ] **Step 6: Commit**

```bash
git add src/clavity/server.py tests/test_server.py
git commit -m "feat(server): clavity-mcp stdio server exposing ask_agy"
```

---

## Task 6: `cli.py` — the launcher (`doctor` / `info`) (TDD)

**Files:**
- Create: `src/clavity/cli.py`, `tests/test_cli.py`

- [ ] **Step 1: Write the failing tests**

`tests/test_cli.py`:
```python
import clavity.cli as cli


def test_doctor_ok_when_credential_present(monkeypatch, capsys):
    monkeypatch.setattr(cli, "resolve_credential", lambda: {"GEMINI_API_KEY": "k"})
    monkeypatch.setattr(cli.shutil, "which", lambda name: "/usr/bin/claude")
    assert cli.main(["doctor"]) == 0


def test_doctor_fails_without_credential(monkeypatch):
    def raise_auth():
        raise cli.AuthError("missing")

    monkeypatch.setattr(cli, "resolve_credential", raise_auth)
    monkeypatch.setattr(cli.shutil, "which", lambda name: "/usr/bin/claude")
    assert cli.main(["doctor"]) == 1


def test_info_returns_zero(capsys):
    assert cli.main(["info"]) == 0
    assert "clavity" in capsys.readouterr().out
```

- [ ] **Step 2: Run to verify failure**

Run: `uv run pytest tests/test_cli.py -q`
Expected: FAIL — `ModuleNotFoundError: clavity.cli`.

- [ ] **Step 3: Implement**

`src/clavity/cli.py`:
```python
"""clavity launcher CLI (Phase 1): `doctor` and `info`. Entry point: `clavity`.

`start` (launch Claude with the plugin) and the daemon/watchers arrive in Phase 2.
"""

from __future__ import annotations

import argparse
import shutil
import sys

from .auth import AuthError, resolve_credential


def doctor() -> int:
    ok = True
    if shutil.which("claude") is None:
        print("MISSING: claude not on PATH", file=sys.stderr)
        ok = False
    try:
        resolve_credential()
        print("agy credential: OK")
    except AuthError as exc:
        print(f"agy credential: {exc}", file=sys.stderr)
        ok = False
    print("clavity doctor:", "OK" if ok else "PROBLEMS")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="clavity")
    sub = parser.add_subparsers(dest="cmd")
    sub.add_parser("doctor", help="check claude on PATH + agy credential")
    sub.add_parser("info", help="print clavity info")
    args = parser.parse_args(argv)

    if args.cmd == "doctor":
        return doctor()
    if args.cmd == "info":
        print("clavity v2 (Python) — Phase 1: ask_agy MCP bridge")
        return 0
    parser.print_help()
    return 0
```

- [ ] **Step 4: Run to verify pass**

Run: `uv run pytest tests/test_cli.py -q`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite + commit**

Run: `uv run pytest -q`
Expected: PASS (all tests across auth/agy/server/cli).

```bash
git add src/clavity/cli.py tests/test_cli.py
git commit -m "feat(cli): clavity doctor/info launcher"
```

---

## Task 7: Package as the `clavity` universal dual-plugin + live acceptance

**Files:**
- Create: `plugins/clavity/.claude-plugin/plugin.json`, `plugins/clavity/plugin.json`, `plugins/clavity/.mcp.json`, `plugins/clavity/mcp_config.json`, `plugins/clavity/skills/ask-agy/SKILL.md`, `plugins/clavity/README.md`

- [ ] **Step 1: Make `clavity-mcp` available on PATH**

Run: `uv tool install --editable .`
Expected: installs the `clavity` and `clavity-mcp` console scripts onto PATH (isolated env). Verify: `clavity-mcp --help` or the Task 5 smoke-test invoked as `clavity-mcp` (no `uv run`).

- [ ] **Step 2: Write the Claude manifest + mcp config**

`plugins/clavity/.claude-plugin/plugin.json`:
```json
{
  "name": "clavity",
  "version": "0.2.0",
  "description": "Bidirectional Claude<->Antigravity bridge: ask_agy delegates to a headless agy."
}
```

`plugins/clavity/.mcp.json`:
```json
{
  "mcpServers": {
    "clavity": { "command": "clavity-mcp" }
  }
}
```

- [ ] **Step 3: Write the agy manifest + mcp config** (disjoint filenames; coexist in one dir)

`plugins/clavity/plugin.json`:
```json
{
  "name": "clavity",
  "version": "0.2.0",
  "description": "Bidirectional Claude<->Antigravity bridge: ask_agy delegates to a headless agy."
}
```

`plugins/clavity/mcp_config.json`:
```json
{
  "mcpServers": {
    "clavity": { "command": "clavity-mcp" }
  }
}
```

- [ ] **Step 4: Write the usage skill**

`plugins/clavity/skills/ask-agy/SKILL.md`:
```markdown
---
name: ask-agy
description: Use to delegate a task or review to Antigravity (agy) from Claude; calls the ask_agy MCP tool.
---

# Ask agy

When the user says "ask agy to …" (review, second opinion, write a module, etc.),
call the `ask_agy` tool exposed by the `clavity` MCP server with a clear `task`
string, then report agy's returned result.
```

- [ ] **Step 5: Write the plugin README**

`plugins/clavity/README.md`: a short doc stating this is the clavity v2 (Phase 1) dual-plugin; requires `uv tool install` of the clavity package so `clavity-mcp` is on PATH; requires a non-interactive agy credential (`GEMINI_API_KEY`); install with `claude plugin install ./plugins/clavity` / `agy plugin install ./plugins/clavity`.

- [ ] **Step 6: Commit**

```bash
git add plugins/clavity
git commit -m "feat(plugin): package clavity v2 phase 1 as the universal dual-plugin"
```

- [ ] **Step 7: Live acceptance (manual runbook — needs a GEMINI_API_KEY)**

1. `export GEMINI_API_KEY=…` (or set it in the environment Claude launches with).
2. `clavity doctor` → expect `OK`.
3. `claude plugin install ./plugins/clavity`; restart Claude.
4. In Claude: confirm the `clavity` MCP server + `ask_agy` tool are listed (`/mcp`).
5. Ask Claude: *"use ask_agy to have agy summarize what this repo does."* Expect a returned result from a headless agy that **did not** re-prompt for auth and **did not** open a terminal/psmux.
6. (Optional) `agy plugin install ./plugins/clavity` and confirm the manifest is accepted.

Record results. If `ask_agy` errors, check `clavity doctor`, the credential, and `docs/agy-sdk-notes.md` against the real SDK.

---

## Self-Review

**Spec coverage (Phase 1 scope):** D3 spawn-on-demand + stable auth → Tasks 3–4; D6 all-Python/uv → Task 1; §4.4 agy spawn-driver → Task 4; §4.5 packaging/dual-plugin → Task 7; §8.1 SDK surface verification → Task 2 spike; §8.2 credential default (GEMINI_API_KEY) → Task 3. **Deferred to Phase 2 (documented, not gaps):** §4.2 daemon/own-bus, §4.3 `claude/channel` driver + agy→Claude wake, watchers, the long-poll API, the `start` launcher.

**Placeholder scan:** none — every code step has complete code; the one SDK uncertainty is isolated in `_invoke_sdk` and explicitly gated on the Task 2 spike (`docs/agy-sdk-notes.md` as oracle), not left vague.

**Type consistency:** `run_agy(task, cwd=None) -> {"ok","output"}` defined in Task 4 and consumed identically in Task 5; `resolve_credential(env=None) -> dict` defined in Task 3 and used in Tasks 4/6; `AgyError`/`AuthError` raised and imported consistently; entry points `clavity`/`clavity-mcp` match `pyproject.toml` (Task 1) and the `.mcp.json` command (Task 7).

---

## Phase 2 (next plan, not this one)
Daemon (own bus + long-poll), `claude/channel` driver to wake idle Claude (gated on the Python-vs-Node channel-feasibility spike, spec §8.1), watchers (CI), and `clavity start`. Produces the full bidirectional bridge on top of this Phase 1 foundation.
