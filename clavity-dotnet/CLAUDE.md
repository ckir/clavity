# clavity-dotnet — notes for Claude

This is the **clavity-dotnet** variant of clavity: the `Clavity.Ls` MCP language server behind
`agy_ask` / `agy_status` / `agy_look`, pairing Claude Code with a live Antigravity (`agy`) peer. It is
one of clavity's two variants — see the [root README](../README.md) for the full product palette, and
[clavity-classic/CLAUDE.md](../clavity-classic/CLAUDE.md) for the other variant's driving notes.

clavity drives a **live, external, frequently-updated** tool — Antigravity (`agy`) — over its
gRPC Language-Server surface. Its behavior is **empirically derived, not a stable contract**, so an
agy update can silently change things and break it.

**If clavity misbehaves, or before you change anything agy-facing, read
[`plugin/knowledge/agy-assumptions.md`](plugin/knowledge/agy-assumptions.md) first**
(the canonical, agy-version-current manual). It lists every load-bearing assumption
(footer markers, agy's pwsh shell, skill caching, workspace-scoped writes, headless-print hanging,
the bus, keyring auth, …), the versions verified against, **how each was verified**, and **how to
re-verify and fix** — most breakages are fixable via an `AGY_*` env override or the responder skill,
not code. See also [`../docs/agy-ls-assumptions.md`](../docs/agy-ls-assumptions.md) for the
LS-specific wire assumptions.

Dev (run from this folder, `clavity-dotnet/`): `dotnet build`, `dotnet test tests/Clavity.Ls.Tests`.

## Recent session notes
_(dated — see ROADMAP/plugin.json for current version)_
- 2026-07-04 — `Clavity.Ls` ask-Answer fix + `clavity-v2` release
  — fixed null `Answer` on a tool-terminated agy turn (`BoundedView.ProjectAskReply` now rescues the last
  assistant run's full prose into `Activity` instead of clipping to 200); released as dotnet **0.1.10** / umbrella
  tag **`clavity-v2`**. Includes the release runbook (serial `clavity-v<N>` tag; bump `installer/clavity-dotnet.iss`).
