# commonmemory (universal dual-plugin)

Shared cross-agent memory conventions for **Claude Code** and **Antigravity (`agy`)**. Both already
connect to the same **agentmemory** store, so a memory one agent saves is recallable by the other —
this plugin ships the *convention* (a single skill) that makes that shared store useful on purpose:
tag `[common]` notes, and proactively recall them on task start / handoff. No binary, no MCP server.

## How it works
- **Recall:** `memory_smart_search query="[common] <repo>"` before acting; honor the newest note's
  `Status:`; ignore stale handoffs.
- **Save:** `[common] (<repo>) — <what> · Why: <why> · Status: <…> · Next: <…>` for handoffs, shared
  decisions, codebase gotchas, and fixed bugs.

See `skills/commonmemory/SKILL.md` for the full convention.

## Install
### Prerequisite
**agentmemory** MCP server configured in BOTH CLIs (the same global `@agentmemory/agentmemory`
module → one shared store). Same setup as `clavity-classic` (see its README step 1). That is the
only dependency.

**Recommended (end users):** run the standalone **commonmemory** installer
(`commonmemory-setup-<ver>.exe`) from the [clavity release page](../../../releases). It stages the
plugin and registers it locally — a scoped `clavity-commonmemory` marketplace under its own install
dir — against every detected agent (Claude Code / agy). No manual `plugin install`, and no remote
marketplace: the plugin ships inside the installer.

**From a clone (developers):** install this plugin folder directly into both CLIs:
```
claude plugin marketplace add ./commonmemory
claude plugin install commonmemory@clavity-commonmemory-dev
agy    plugin install ./commonmemory
```

## Configuration
Installing the plugin makes the skill *available* but does **not** make either agent auto-search on
its own. Add a one-line rule to each agent's global instructions so they recall `[common]` notes at
the start of a task:
- **agy** — in `~/.gemini/GEMINI.md` (inside its `<user_rules>` block):
  > At the start of a task, `memory_smart_search` for `[common] <repo>` notes (repo = the current
  > repository name) and read them before acting.

  (The bundled `rules/commonmemory.md` ships the same rule; if your agy auto-applies plugin
  `rules/`, the GEMINI.md edit is redundant — verify once.)
- **Claude** — add the same one-line rule to your `CLAUDE.md` (project or user scope).

## Docs
- `skills/commonmemory/SKILL.md` — the shared-memory convention (read by both CLIs)
- `rules/commonmemory.md` — agy-native proactive-recall rule (Claude ignores it)
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests
