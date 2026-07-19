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

## What's in here

```
commonmemory/
  .claude-plugin/plugin.json · plugin.json   # dual manifests (Claude + agy)
  skills/commonmemory/SKILL.md   # the shared-memory convention (read by both CLIs)
  rules/commonmemory.md          # agy-native proactive-recall rule (Claude ignores it)
```

## Install
### Prerequisite
**agentmemory** MCP server configured in BOTH CLIs (the same global
[`@agentmemory/agentmemory`](https://www.npmjs.com/package/@agentmemory/agentmemory) module → one
shared store). Register the same agentmemory MCP server in both Claude Code and agy, pointing at the
same daemon (default `:3111`). Nothing works without it — it is the shared data channel this
plugin's convention runs over. That is the only dependency.

**Recommended (end users):** run the standalone **commonmemory** installer
(`commonmemory-setup-<version>.exe`) from the
[clavity release page](https://github.com/ckir/clavity/releases). It stages the plugin and
registers it locally — a scoped `clavity-commonmemory` marketplace under its own install dir —
against every detected agent (Claude Code / agy). No manual `plugin install`, and no remote
marketplace: the plugin ships inside the installer.

**From a clone (developers):** install this plugin folder directly into both CLIs:
```
claude plugin marketplace add ./commonmemory
claude plugin install commonmemory@clavity-commonmemory-dev
agy    plugin install ./commonmemory
```

## Configuration
**Required — one line per agent. The plugin does not work without this.**

Installing the plugin makes the skill *available* but does **not** make either agent auto-search on
its own. Add a one-line rule to each agent's global instructions so they recall `[common]` notes at
the start of a task:
- **agy** — in `~/.gemini/GEMINI.md` (inside its `<user_rules>` block):
  > At the start of a task, `memory_smart_search` for `[common] <repo>` notes (repo = the current
  > repository name) and read them before acting.

  (The bundled `rules/commonmemory.md` ships the same rule; if your agy auto-applies plugin
  `rules/`, the GEMINI.md edit is redundant — verify once.)
- **Claude** — add the same one-line rule to your `CLAUDE.md` (project or user scope).

## Troubleshooting

- **`memory_smart_search` fails, or notes never show up.** The **agentmemory** MCP server is not
  configured (or not running) in one or both CLIs — see Prerequisite above. Registration alone
  does not install it; if you have not set up agentmemory yet, the shared notebook stays inactive
  (source: `installer/commonmemory.iss` post-install message).
- **Neither agent ever recalls `[common]` notes on its own.** The one-line rule under Configuration
  is missing from that agent's global instructions — installing the plugin only makes the skill
  available, it does not wire up proactive recall.
- **Install/uninstall silently fails to (de)register the plugin.** Claude Code was running during
  setup — it rewrites the plugin registration on its own startup/exit and overwrites what the
  installer just did. Close Claude Code completely, then run the installer again (source:
  `installer/commonmemory.iss`).

## Docs
- `skills/commonmemory/SKILL.md` — the shared-memory convention (read by both CLIs)
- `rules/commonmemory.md` — agy-native proactive-recall rule (Claude ignores it)
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`) — free for
non-commercial use. See [NOTICE](NOTICE) for the copyright line.
