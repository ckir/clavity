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
