# Copyright (c) 2026 Costas Kirgoussios
#
# This software is licensed under the PolyForm Noncommercial License 1.0.0.
# You may obtain a copy of the License at:
# https://polyformproject.org/licenses/noncommercial/1.0.0/

"""Tests for the MCP-server wiring added to the delegated sub-agent.

The existing integration tests short-circuit via MOCK_AGENT_RESPONSE before the
real Agent/LocalAgentConfig is built, so they do not exercise the mcp_servers
wiring. These cover `_build_mcp_servers()` and that the resulting config is
accepted by the installed google-antigravity SDK.
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from google.antigravity import LocalAgentConfig  # noqa: E402
from google.antigravity.types import McpStdioServer  # noqa: E402

import server  # noqa: E402


def test_build_mcp_servers_default_wires_agentmemory(monkeypatch):
    monkeypatch.delenv("AGY_BRIDGE_NO_MCP", raising=False)
    servers = server._build_mcp_servers()

    assert len(servers) == 1
    s = servers[0]
    assert isinstance(s, McpStdioServer)
    assert s.name == "agentmemory"
    # Launches the agentmemory MCP stdio process regardless of platform.
    assert "@agentmemory/agentmemory" in s.args
    assert "mcp" in s.args
    if os.name == "nt":
        # Windows npx is a .cmd shim with no .exe → must go through cmd /c.
        assert s.command == "cmd"
        assert s.args[:2] == ["/c", "npx"]
    else:
        assert s.command == "npx"


@pytest.mark.parametrize("val", ["1", "true", "YES"])
def test_kill_switch_disables_mcp(monkeypatch, val):
    monkeypatch.setenv("AGY_BRIDGE_NO_MCP", val)
    assert server._build_mcp_servers() == []


def test_local_agent_config_accepts_wired_mcp_servers(tmp_path, monkeypatch):
    monkeypatch.delenv("AGY_BRIDGE_NO_MCP", raising=False)
    # Constructing the config must not raise — validates the wiring contract
    # (mcp_servers param + McpStdioServer shape) against the installed SDK.
    cfg = LocalAgentConfig(
        system_instructions="test",
        workspaces=[str(tmp_path)],
        mcp_servers=server._build_mcp_servers(),
    )
    assert len(cfg.mcp_servers) == 1
    assert cfg.mcp_servers[0].name == "agentmemory"


@pytest.mark.asyncio
async def test_cleanup_failure_is_logged_as_failed_in_telemetry(monkeypatch, tmp_path):
    """When cleanup_worktree raises (e.g. merge conflict), log_completion must run
    AFTER cleanup_worktree and record status='failed' with the cleanup error."""
    recorded = {}

    async def fake_init_db(target_dir):
        pass

    async def fake_log_start(target_dir, task_id, prompt):
        pass

    async def fake_create_worktree(target_dir, task_id):
        return str(tmp_path / "wt")

    async def fake_cleanup_worktree(target_dir, task_id, success=False):
        raise RuntimeError("Merge conflict detected")

    async def fake_log_completion(
        target_dir, task_id, status, tokens_used=0, final_error=None
    ):
        recorded["status"] = status
        recorded["final_error"] = final_error

    monkeypatch.setattr(server, "init_db", fake_init_db)
    monkeypatch.setattr(server, "log_start", fake_log_start)
    monkeypatch.setattr(server, "create_worktree", fake_create_worktree)
    monkeypatch.setattr(server, "cleanup_worktree", fake_cleanup_worktree)
    monkeypatch.setattr(server, "log_completion", fake_log_completion)
    monkeypatch.setenv("MOCK_AGENT_RESPONSE", '{"status": "completed"}')

    res = await server.handle_call_tool(
        "delegate_to_antigravity",
        {"task_prompt": "do work", "target_dir": str(tmp_path)},
    )
    assert recorded["status"] == "failed"
    assert "Merge conflict detected" in (recorded["final_error"] or "")
    assert '"status": "failed"' in res[0].text
