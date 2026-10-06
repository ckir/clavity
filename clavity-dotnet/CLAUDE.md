# clavity-dotnet — notes for Claude

This is the **clavity-dotnet** variant of clavity: the `Clavity.Ls` MCP language server behind
`agy_ask` / `agy_status` / `agy_look`, pairing Claude Code with a live Antigravity (`agy`) peer. It is
one of clavity's two variants — see the [root README](../README.md) for the full product palette, and
[clavity-classic/CLAUDE.md](../clavity-classic/CLAUDE.md) for the other variant's driving notes.

agy-facing guidance lives in the root `CLAUDE.md` (read
[`plugin/knowledge/agy-assumptions.md`](plugin/knowledge/agy-assumptions.md) first); the LS-specific
wire assumptions are in [`../docs/agy-ls-assumptions.md`](../docs/agy-ls-assumptions.md).

Dev (run from this folder, `clavity-dotnet/`): `dotnet build`, `dotnet test tests/Clavity.Ls.Tests`.

For what shipped when, read `CHANGELOG.md` and `ROADMAP.md` — they are generated/maintained and stay
current. (A hand-written "recent session notes" section used to live here; it stopped being recent nine
releases ago, which is exactly the rot this file cannot afford as auto-loaded agent context.)
