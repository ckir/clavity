# clavity-dotnet — pair Claude with a live agy peer (Language-Server bridge)

The core dotnet plugin for clavity. It lets Claude drive a paired `agy` peer over agy's local Language Server
through three MCP tools served by the `clavity-ls` binary:

- **`agy_look`** — read agy's active conversation, bounded (no quota).
- **`agy_status`** — liveness + step count.
- **`agy_ask`** — send a message and get agy's reply (a quota-consuming, human-visible WRITE).

## What's inside

```
clavity-dotnet/
  .claude-plugin/plugin.json · plugin.json   # dual manifests (Claude + agy)
  .mcp.json                                  # registers the clavity-ls --mcp stdio server (Claude side)
  skills/clavity-ls-driving/                 # Claude: when to look vs ask + the anti-misfire protocol
  skills/clavity-ls-pairing/                 # agy: etiquette when LS-driven by a paired Claude
```

## Requires

The `clavity-ls` binary on PATH (installed by the clavity installer). Golden-header injection + the
permanent-learning loop are the optional **agy-autotrain** add-on; this core plugin works without it.

## Install

Ships via the `clavity-dotnet` standalone installer (`clavity-dotnet-setup-<VERSION>.exe`), which
registers this plugin against a local, scoped marketplace for each detected agent (Claude Code / agy) —
there is no remote marketplace to add. See [`clavity-dotnet/README.md`](../README.md) for the Quick
Start.
