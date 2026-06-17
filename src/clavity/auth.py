"""Resolve the GEMINI_API_KEY for non-interactive agy auth (spec §8.2).

The google-antigravity SDK (==0.1.3) reads GEMINI_API_KEY from the environment, or
accepts an explicit api_key= on LocalAgentConfig — see docs/agy-sdk-notes.md §4.
GOOGLE_API_KEY and service-account ADC are NOT used by this SDK. (Reusing the
interactive OAuth refresh_token is a verify-at-impl alternative; not implemented here.)
"""

from __future__ import annotations

import os


class AuthError(RuntimeError):
    """No usable non-interactive agy credential was found."""


def resolve_api_key(env: dict[str, str] | None = None) -> str:
    env = os.environ if env is None else env
    key = env.get("GEMINI_API_KEY")
    if not key:
        raise AuthError(
            "No GEMINI_API_KEY set. The google-antigravity SDK requires it for "
            "non-interactive auth (set GEMINI_API_KEY, or pass api_key=)."
        )
    return key
