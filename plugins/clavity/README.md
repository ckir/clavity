# clavity (universal dual-plugin) — Phase 1

A bidirectional Claude<->Antigravity bridge. Phase 1 ships the synchronous
**Claude → agy** direction: an `ask_agy` MCP tool that delegates a task to a fresh
headless Antigravity (agy) sub-agent running in the current project folder.

## Prerequisites
- The `clavity` Python package installed so `clavity-mcp` is on PATH:
  `uv tool install --editable /path/to/clavity`
- A non-interactive agy credential: `GEMINI_API_KEY`. Provide it any of these ways
  (real shell env wins): export it, put it in a project-local `.env` (see
  `.env.example`), or in `~/.clavity/.env`. clavity loads `.env` at startup.

## Install
Installs in BOTH CLIs from this one directory (disjoint manifest filenames coexist):

    claude plugin install ./plugins/clavity
    agy    plugin install ./plugins/clavity

## Use
In Claude: "use ask_agy to have agy review X" → Claude calls the `ask_agy` tool and
reports agy's result. No psmux, no terminal automation.

## Layout
- `.claude-plugin/plugin.json` + `.mcp.json` — Claude Code manifest + MCP config
- `plugin.json` + `mcp_config.json` — Antigravity manifest + MCP config
- `skills/ask-agy/SKILL.md` — usage skill (read by both)

Phase 2 adds the reverse direction (agy → Claude via a `claude/channel` driver) and
the clavity daemon/watchers.
