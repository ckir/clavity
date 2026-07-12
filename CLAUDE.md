# clavity — notes for Claude

**clavity** is a host for several tools that pair AI coding agents with live peers. This is the
umbrella repo: each product lives in its own top-level folder (see [README.md](README.md) for the
full palette). This file carries only cross-cutting, umbrella-level guidance — a product's own
`CLAUDE.md` (where one exists) carries its build/test/driving detail.

## agy-facing guidance (cross-cutting)

`clavity-dotnet`, `clavity-classic`, and `agy-autotrain` all drive a **live, external,
frequently-updated** tool — Antigravity (`agy`) — over `psmux` (`send-keys`/`capture-pane`)/gRPC and
the `agentmemory` signal bus. Its behavior is **empirically derived, not a stable contract**, so an
agy / psmux / agentmemory update can silently change things and break it.

**If anything agy-facing misbehaves, or before you change anything agy-facing, read
[`clavity-dotnet/plugin/knowledge/agy-assumptions.md`](clavity-dotnet/plugin/knowledge/agy-assumptions.md) first**
(the canonical, agy-version-current manual). It lists every load-bearing assumption
(footer markers, agy's pwsh shell, skill caching, workspace-scoped writes, headless-print hanging,
the bus, keyring auth, …), the versions verified against, **how each was verified**, and **how to
re-verify and fix** — most breakages are fixable via an `AGY_*` env override or the responder skill,
not code.

For the maintainer procedure that drains captured `agy-learn` observations into those manuals + the
SEED, see [`docs/drain-knowledge-runbook.md`](docs/drain-knowledge-runbook.md).

## Products

| Product | Folder | Build | Driving notes |
|---------|--------|-------|----------------|
| clavity-dotnet | `clavity-dotnet/` | `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests` | [clavity-dotnet/CLAUDE.md](clavity-dotnet/CLAUDE.md) |
| clavity-classic | `clavity-classic/` | `cd clavity-classic && cargo test --all --features test-fakes` | [clavity-classic/CLAUDE.md](clavity-classic/CLAUDE.md) |
| ghidrust | `ghidrust/` | `cd ghidrust && just test` | [ghidrust/CLAUDE.md](ghidrust/CLAUDE.md) |
| agy-autotrain | `agy-autotrain/` | (plugin only) | — |
| commonmemory | `commonmemory/` | (plugin only) | — |

See [README.md](README.md) for the product palette and [docs/hosting-a-tool.md](docs/hosting-a-tool.md)
for the playbook to add a new one.
