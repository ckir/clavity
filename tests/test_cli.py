import clavity.cli as cli


def test_doctor_ok_when_credential_present(monkeypatch, capsys):
    monkeypatch.setattr(cli, "resolve_api_key", lambda: "k")
    monkeypatch.setattr(cli.shutil, "which", lambda name: "/usr/bin/claude")
    assert cli.main(["doctor"]) == 0


def test_doctor_fails_without_credential(monkeypatch):
    def raise_auth():
        raise cli.AuthError("missing")

    monkeypatch.setattr(cli, "resolve_api_key", raise_auth)
    monkeypatch.setattr(cli.shutil, "which", lambda name: "/usr/bin/claude")
    assert cli.main(["doctor"]) == 1


def test_info_returns_zero(capsys):
    assert cli.main(["info"]) == 0
    assert "clavity" in capsys.readouterr().out
