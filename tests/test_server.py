import clavity.server as srv


async def test_handle_ask_agy_returns_output(monkeypatch):
    async def fake_run(task):
        return {"ok": True, "output": f"ran {task}"}

    monkeypatch.setattr(srv, "run_agy", fake_run)
    text = await srv.handle_ask_agy({"task": "review foo"})
    assert text == "ran review foo"


async def test_handle_ask_agy_reports_error(monkeypatch):
    async def boom(task):
        raise srv.AgyError("no creds")

    monkeypatch.setattr(srv, "run_agy", boom)
    text = await srv.handle_ask_agy({"task": "x"})
    assert text.startswith("ERROR:")
    assert "no creds" in text


def test_build_server_lists_ask_agy_tool():
    server = srv.build_server()
    assert server.name == "clavity"
