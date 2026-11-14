# AGENTS.md — clavity

Guidance for AI coding agents working in this repository. Humans: start with [README.md](README.md) and
[CONTRIBUTING.md](CONTRIBUTING.md).

## About this repo

clavity is an umbrella repo hosting several tools that pair an AI coding agent with a live
Antigravity (`agy`) peer. Each product lives in its own top-level folder and ships independently. This file
carries only cross-cutting, umbrella-level guidance; a product's own notes carry its build, test and driving
detail.

### Products

| Product | Folder | Stack | Build / test | Notes |
|---------|--------|-------|--------------|-------|
| clavity-dotnet (primary) | `clavity-dotnet/` | .NET 10 MCP language server (`Clavity.Ls`) + plugin | `just dotnet::test` (or `cd clavity-dotnet && just test`) | [clavity-dotnet/CLAUDE.md](clavity-dotnet/CLAUDE.md) |
| clavity-classic (failover) | `clavity-classic/` | Rust CLI + Python MCP bridge (`agy-mcp-bridge/`) | `just classic::test` (or `cd clavity-classic && just test`) | [clavity-classic/CLAUDE.md](clavity-classic/CLAUDE.md) |
| agy-autotrain | `agy-autotrain/` | plugin only (skills, hooks, knowledge) | — | — |
| commonmemory | `commonmemory/` | plugin only | — | — |
| review-relay | `review-relay/` | plugin only (+ browser extension) | — | — |

Product-specific notes live in each folder's `CLAUDE.md` / `CONTRIBUTING.md` / `README.md`. The plugin
marketplace manifest is `.claude-plugin/marketplace.json`. See [README.md](README.md) for the product palette.

### Commands and tooling

The repo uses a two-tier [`just`](https://github.com/casey/just) runner: the root `justfile` delegates to
each product's own `justfile` (`mod dotnet`, `mod classic`). `just` lists every recipe. Recipes available at
the root include:

```bash
just build | just test | just lint | just fmt   # all products (fmt mutates)
just dotnet::test                                # one product
just classic::lint
just test-scripts-fast                           # fast Pester gate over scripts/ (inner loop)
```

- `just test-scripts-slow` and `just test-scripts` each take **more than 10 minutes**.
- Repo-level `check-*` recipes (`just --list` shows them all) are **not** part of `just lint`. CI runs the
  same script as `just check-injected-context` only when plugin, seed, skill or gate-script paths change
  (its workflow is path-filtered), not on every push.
- Most tooling is PowerShell 7 (`pwsh`) — scripts under `scripts/` assume it is on PATH.
- `just release-dry` previews a release without publishing; releases themselves are owner-gated (see the rules below).

### Git hooks

Hooks are managed with lefthook ([lefthook.yml](lefthook.yml)).

- **pre-commit:** `ruff` on staged Python under `clavity-classic/agy-mcp-bridge/`; cheatsheet guards
  when the cheatsheet files are staged.
- **pre-push:** fast (seconds-range) consistency gates only. `lint` and `test` are deliberately **not**
  in the hook; CI enforces both.

### Generated and pinned files

- `clavity-classic/src/driver_cheatsheet.rs` and `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` are
  generated from `agy-autotrain/knowledge/driver-cheatsheet.core.md` by `just gen-cheatsheet-literals`.
- `installer/_shared/register-plugin.ps1` is SHA-256 pinned (`just sync-register-hash` refreshes the pin).
- Seed agent artifacts are byte-identical across the two driver plugins (checked by `just seed-sync-check`).
- `docs/USER_GUIDE.html` is generated.

### agy-facing code

`clavity-dotnet`, `clavity-classic` and `agy-autotrain` drive a **live, external, frequently-updated** tool
(`agy`) over `psmux` (`send-keys`/`capture-pane`)/gRPC and the `agentmemory` signal bus. Its behaviour is
empirically derived, not a stable contract, so an agy / psmux / agentmemory update can silently change things
and break it.

The canonical, agy-version-current manual is
[clavity-dotnet/plugin/knowledge/agy-assumptions.md](clavity-dotnet/plugin/knowledge/agy-assumptions.md). It
lists every load-bearing assumption (footer markers, agy's shell (pwsh on Windows, bash on Linux), skill
caching, workspace-scoped writes, headless-print hanging, the bus, keyring auth, …), the versions verified
against, how each was verified, and how to re-verify and fix — most breakages are fixable via an `AGY_*` env
override or the responder skill, not code. LS wire assumptions:
[docs/agy-ls-assumptions.md](docs/agy-ls-assumptions.md).

The maintainer procedure that drains captured `agy-learn` observations into those manuals + the SEED is in
[docs/drain-knowledge-runbook.md](docs/drain-knowledge-runbook.md).

### Further reading

- [docs/README.md](docs/README.md) — documentation portal
- [docs/hosting-a-tool.md](docs/hosting-a-tool.md) — adding a new product to the umbrella (the playbook)
- [docs/release-runbook.md](docs/release-runbook.md) — how releases are cut
- [docs/tracker-format.md](docs/tracker-format.md) — the format ROADMAPs and the backlog follow
- `clavity-dotnet/ROADMAP.md`, each product's `CHANGELOG.md` — current state (prefer these over any
  dated note)

## Rules for every agent

- Never edit the block in `README.md` between `HUMAN ONLY SECTION START` and `HUMAN ONLY SECTION END`.
- Never hand-edit a generated file: `clavity-classic/src/driver_cheatsheet.rs`,
  `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` and `docs/USER_GUIDE.html`.
- Releases are owner-gated: never run `just release` and never push a `clavity-v*` tag unless the owner
  explicitly asks.

## When you are making changes

Skip this section if your session is review-only.

- Run `lefthook install` once per clone.
- Run `just lint` and `just test` yourself before pushing; the pre-push hook does not run them.
- Run `just check-injected-context` by hand if you touch plugin, seed, or skill content.
- Run `just test-scripts-slow` and `just test-scripts` in the background, never in a foreground call with a
  timeout.
- Before changing anything agy-facing, or when it misbehaves, read
  [clavity-dotnet/plugin/knowledge/agy-assumptions.md](clavity-dotnet/plugin/knowledge/agy-assumptions.md)
  first.
- To change a generated cheatsheet file: edit `agy-autotrain/knowledge/driver-cheatsheet.core.md`, run
  `just gen-cheatsheet-literals`, and stage `agy-autotrain/knowledge/driver-cheatsheet.core.md`,
  `clavity-classic/src/driver_cheatsheet.rs` and `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` together.
- After changing `installer/_shared/register-plugin.ps1`, run `just sync-register-hash`.
- Keep seed agent artifacts byte-identical across the two driver plugins (`just seed-sync-check`).
- **Licence header:** every first-party source file carries the text of [header.txt](header.txt)
  (CI: `ci-license-headers.yml`).
- **Commits:** Conventional Commits (`feat(scope): …`, `fix(plugin): …`, `docs: …`); release notes and
  version bumps are computed from them. External contributors also sign off (DCO) — see CONTRIBUTING.md.
- **Windows installer surface** must stay pure ASCII (`just check-installer-ascii`) — it runs on stock
  Windows PowerShell 5.1.
- **README.md:** the `AI SECTION` below the HUMAN ONLY block may be updated.
- **New top-level files:** a new tracked path at the repo root must be classified in
  `scripts/lib/release-lib.ps1` (`$DevOnlyPaths` or a member), or the release computation refuses it.
- **Trackers** (ROADMAPs, backlog) follow [docs/tracker-format.md](docs/tracker-format.md)
  (`just check-tracker-status`).
