"""Tests for confused-deputy hardening (scrub_host_secrets).

The SDK runs the delegated sub-agent's shells in a harness that inherits the
bridge's os.environ, so host AI-platform credentials must be popped out before
serving — while operational tokens the autonomous coder legitimately needs
(GITHUB_TOKEN, NPM_TOKEN, …) are preserved. The Gemini key is captured for
explicit pass-through to LocalAgentConfig(api_key=...).
"""

import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import server  # noqa: E402


def test_scrub_pops_gemini_and_captures_it(monkeypatch):
    monkeypatch.setattr(server, "_gemini_api_key", None, raising=False)
    monkeypatch.setenv("GEMINI_API_KEY", "g-secret")
    captured = server.scrub_host_secrets()
    assert captured == "g-secret"
    assert "GEMINI_API_KEY" not in os.environ


def test_scrub_pops_other_infra_keys(monkeypatch):
    infra = (
        "GOOGLE_API_KEY",
        "GOOGLE_APPLICATION_CREDENTIALS",
        "ANTHROPIC_API_KEY",
        "CLAUDE_API_KEY",
        "OPENAI_API_KEY",
    )
    for k in infra:
        monkeypatch.setenv(k, "x")
    server.scrub_host_secrets()
    for k in infra:
        assert k not in os.environ


def test_scrub_preserves_operational_tokens(monkeypatch):
    monkeypatch.setenv("GITHUB_TOKEN", "gh")
    monkeypatch.setenv("NPM_TOKEN", "npm")
    server.scrub_host_secrets()
    assert os.environ.get("GITHUB_TOKEN") == "gh"
    assert os.environ.get("NPM_TOKEN") == "npm"


def test_scrub_absent_gemini_returns_none(monkeypatch):
    monkeypatch.setattr(server, "_gemini_api_key", None, raising=False)
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    assert server.scrub_host_secrets() is None


def test_scrub_extra_denylist_is_honored(monkeypatch):
    monkeypatch.setenv("MY_CUSTOM_SECRET", "s")
    monkeypatch.setenv("AGY_BRIDGE_SCRUB_EXTRA", "MY_CUSTOM_SECRET")
    server.scrub_host_secrets()
    assert "MY_CUSTOM_SECRET" not in os.environ
