import os

import clavity.config as config


def test_load_env_reads_project_dotenv(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".env").write_text("CLAVITY_TEST_VAR=hello\n")
    monkeypatch.delenv("CLAVITY_TEST_VAR", raising=False)
    config.load_env()
    assert os.environ.get("CLAVITY_TEST_VAR") == "hello"


def test_real_env_wins_over_dotenv(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".env").write_text("CLAVITY_TEST_VAR=fromfile\n")
    monkeypatch.setenv("CLAVITY_TEST_VAR", "fromenv")
    config.load_env()
    assert os.environ.get("CLAVITY_TEST_VAR") == "fromenv"
