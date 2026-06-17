import pytest
from clavity.auth import resolve_api_key, AuthError


def test_returns_gemini_api_key():
    assert resolve_api_key({"GEMINI_API_KEY": "k1"}) == "k1"


def test_raises_when_missing():
    with pytest.raises(AuthError):
        resolve_api_key({})


def test_raises_when_blank():
    with pytest.raises(AuthError):
        resolve_api_key({"GEMINI_API_KEY": ""})
