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

For what shipped when, read `CHANGELOG.md` and `ROADMAP.md` — they are generated/maintained and stay
current. (A hand-written "recent session notes" section used to live here; it stopped being recent nine
releases ago, which is exactly the rot this file cannot afford as auto-loaded agent context.)
