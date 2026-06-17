import pytest
import clavity.agy as agy
from clavity.agy import run_agy, AgyError


async def test_empty_task_raises():
    with pytest.raises(AgyError):
        await run_agy("   ")


async def test_success_returns_output(monkeypatch):
    monkeypatch.setattr(agy, "resolve_api_key", lambda: "k")

    async def fake_invoke(task, cwd, api_key):
        return f"did: {task}"

    monkeypatch.setattr(agy, "_invoke_sdk", fake_invoke)
    result = await run_agy("review foo.py", cwd="/tmp/proj")
    assert result == {"ok": True, "output": "did: review foo.py"}


async def test_sdk_failure_becomes_agyerror(monkeypatch):
    monkeypatch.setattr(agy, "resolve_api_key", lambda: "k")

    async def boom(task, cwd, api_key):
        raise RuntimeError("sdk exploded")

    monkeypatch.setattr(agy, "_invoke_sdk", boom)
    with pytest.raises(AgyError) as exc:
        await run_agy("x")
    assert "sdk exploded" in str(exc.value)
