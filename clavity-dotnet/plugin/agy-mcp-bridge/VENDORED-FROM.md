# agy-mcp-bridge — canonical source & provenance

This directory **is** the `delegate_to_antigravity` bridge source — the **canonical development home**, in-branch
on `clavity-classic`. The installer + release CI build it from a **single checkout** (no cross-repo fetch). It is
an opt-in installer add-on with a Python/uv prerequisite.

## Provenance

This code originated as a snapshot of the **claudavity prototype** (`~/Development/Rust/claudavity` @
`fae54fa768fe7bcbefa9ca10ad17b73eaf8fc20b`, copied 2026-06-30). As of 2026-06-30 that prototype is
**frozen/deprecated** and kept only for reference — it is **NOT** an upstream to track, and there is **no
re-sync**. Develop the bridge **here**, like any other code in this repo.

## Files

**Runtime** (shipped by the installer — Spec B's 7.8 whitelist; `scripts/build-classic-release.ps1` stages
exactly these): `server.py`, `agy_bus.py`, `agy_tmux.py`, `isolation.py`, `telemetry.py`, **`SKILL.md`**,
`pyproject.toml`, `uv.lock`, `start-claudavity.ps1`, `.env.example`, `LICENSE`.

> **`SKILL.md` is RUNTIME, not docs:** `server.py` loads it as `CANONICAL_SKILL`
> (`os.path.dirname(__file__)/SKILL.md`) and injects it into every spawned sub-agent — it is the sub-agent's
> JSON output contract. It MUST sit beside `server.py`. (Distinct from the agy-side `claudavity-responder`
> skill, which is NOT here — that lives at `agy_skills/claudavity-responder/SKILL.md`, embedded in the binary.)

**Dev-only** (present here for maintenance; NOT shipped — the build recipe excludes them): the test suite
(`test_agy_bus.py`, `test_agy_tmux.py`, `test_client.py`, `test_isolation.py`, `real_test_client.py`,
`tests/*.py`).

## Secret boundary

The live `.env` (holds `GEMINI_API_KEY`) is **never** committed: only `.env.example` ships, and the local
`.gitignore` in this dir blocks a `uv sync` / bridge run from ever committing `.env` / `.venv` / caches.

## Dependencies

Manage deps normally **here**: edit `pyproject.toml`, run `uv lock` to refresh `uv.lock`, commit it. The
installer materializes the venv with `uv sync --frozen` — the committed `uv.lock` is the pin, never re-resolved
at install time. Bridge changes ride a `clavity-classic-v*` release with the rest of the crate.
