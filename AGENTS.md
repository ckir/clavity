# AGENTS.md — clavity

Guidance for AI coding agents working in this repository. Humans: start with [README.md](README.md) and
[CONTRIBUTING.md](CONTRIBUTING.md).

clavity is an umbrella repo hosting several tools that pair an AI coding agent with a live
Antigravity (`agy`) peer. Each product lives in its own top-level folder and ships independently.

## Products

| Product | Folder | Stack | Build / test |
|---------|--------|-------|--------------|
| clavity-dotnet (primary) | `clavity-dotnet/` | .NET 10 MCP language server (`Clavity.Ls`) + plugin | `just dotnet::test` |
| clavity-classic (failover) | `clavity-classic/` | Rust CLI + Python MCP bridge (`agy-mcp-bridge/`) | `just classic::test` |
| agy-autotrain | `agy-autotrain/` | plugin only (skills, hooks, knowledge) | — |
| commonmemory | `commonmemory/` | plugin only | — |
| review-relay | `review-relay/` | plugin only (+ browser extension) | — |

Product-specific notes live in each folder's `CLAUDE.md` / `CONTRIBUTING.md` / `README.md`. The plugin
marketplace manifest is `.claude-plugin/marketplace.json`.

## Commands

The repo uses a two-tier [`just`](https://github.com/casey/just) runner: the root `justfile` delegates to
each product's own `justfile` (`mod dotnet`, `mod classic`). Run `just` to list every recipe.

```bash
just build | just test | just lint | just fmt   # all products (fmt mutates)
just dotnet::test                                # one product
just classic::lint
just test-scripts-fast                           # fast Pester gate over scripts/ (inner loop)
```

- `just test-scripts-slow` and `just test-scripts` each take **more than 10 minutes**. Run them in the
  background, never in a foreground call with a timeout.
- Repo-level `check-*` recipes (`just --list` shows them all) are **not** part of `just lint`. If you
  touch plugin, seed, or skill content, run `just check-injected-context` by hand; CI runs it on every push.
- Most tooling is PowerShell 7 (`pwsh`) — scripts under `scripts/` assume it is on PATH.

## Git hooks

Run `lefthook install` once per clone ([lefthook.yml](lefthook.yml)).

- **pre-commit:** `ruff` on staged Python under `clavity-classic/agy-mcp-bridge/`; cheatsheet guards
  when the cheatsheet files are staged.
- **pre-push:** fast (seconds-range) consistency gates only. `lint` and `test` are deliberately **not**
  in the hook — run them yourself before pushing; CI enforces both.

## Generated and pinned files — do not hand-edit

- `clavity-classic/src/driver_cheatsheet.rs` and `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` are
  generated from `agy-autotrain/knowledge/driver-cheatsheet.core.md`. Edit `core.md`, run
  `just gen-cheatsheet-literals`, and stage all three together.
- `installer/_shared/register-plugin.ps1` is SHA-256 pinned: after changing it run
  `just sync-register-hash`.
- Seed agent artifacts must stay byte-identical across the two driver plugins (`just seed-sync-check`).
- `docs/USER_GUIDE.html` is generated.

## Conventions

- **Licence header:** every first-party source file carries the text of [header.txt](header.txt)
  (CI: `ci-license-headers.yml`).
- **Commits:** Conventional Commits (`feat(scope): …`, `fix(plugin): …`, `docs: …`); release notes and
  version bumps are computed from them. External contributors also sign off (DCO) — see CONTRIBUTING.md.
- **Windows installer surface** must stay pure ASCII (`just check-installer-ascii`) — it runs on stock
  Windows PowerShell 5.1.
- **README.md:** never edit the block between `HUMAN ONLY SECTION START` and `HUMAN ONLY SECTION END`.
  The `AI SECTION` below it may be updated.
- **New top-level files:** a new tracked path at the repo root must be classified in
  `scripts/lib/release-lib.ps1` (`$DevOnlyPaths` or a member), or the release computation refuses it.
- **Trackers** (ROADMAPs, backlog) follow [docs/tracker-format.md](docs/tracker-format.md)
  (`just check-tracker-status`).
- **Releases are owner-gated.** Never run `just release` or push a `clavity-v*` tag unless the owner
  explicitly asks; `just release-dry` is a safe preview.

## agy-facing code

`clavity-dotnet`, `clavity-classic` and `agy-autotrain` drive a live, frequently-updated external tool
(`agy`) whose behaviour is empirically derived, not a stable contract. **Before changing anything
agy-facing, or when it misbehaves, read
[clavity-dotnet/plugin/knowledge/agy-assumptions.md](clavity-dotnet/plugin/knowledge/agy-assumptions.md)**
— it lists each load-bearing assumption, how it was verified, and how to re-verify and fix it (often an
`AGY_*` env override rather than a code change). LS wire assumptions: [docs/agy-ls-assumptions.md](docs/agy-ls-assumptions.md).

## Further reading

- [docs/README.md](docs/README.md) — documentation portal
- [docs/hosting-a-tool.md](docs/hosting-a-tool.md) — adding a new product to the umbrella
- [docs/release-runbook.md](docs/release-runbook.md) — how releases are cut
- `clavity-dotnet/ROADMAP.md`, each product's `CHANGELOG.md` — current state (prefer these over any
  dated note)
