# clavity

[![License: PolyForm Noncommercial 1.0.0](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-blue.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-lightgrey.svg)]()

**clavity** is a host for several tools that pair AI coding agents with live peers. This is the
umbrella repo — a monorepo with one top-level folder per product, each independently built/tested,
plus the shared release machinery that bundles them into one umbrella download. The umbrella
`clavity-v<N>` release is the **canonical** download and bundles every product's installer in one
place.

## Products

| Product | Folder | Build |
|---------|--------|-------|
| clavity-dotnet | clavity-dotnet/ | cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests |
| clavity-classic | clavity-classic/ | cd clavity-classic && cargo test --all --features test-fakes |
| ghidrust | ghidrust/ | cd ghidrust && just test |
| agy-autotrain | agy-autotrain/ | (plugin only) |
| commonmemory | commonmemory/ | (plugin only) |

- **clavity-dotnet** / **clavity-classic** — two **mutually exclusive** variants that pair
  [Claude Code](https://claude.com/claude-code) with [Antigravity (`agy`)](https://antigravity.google);
  install ONE, via its OWN standalone installer (**.NET** Primary or **Classic** Failover — see
  [clavity-dotnet/README.md](clavity-dotnet/README.md)).
- **ghidrust** — drives a persistent headless Ghidra JVM: 19 reverse-engineering tools over MCP
  (attach + decompile + durable edits), via its own standalone installer. See
  [ghidrust/README.md](ghidrust/README.md).
- **agy-autotrain** / **commonmemory** — plugin-only add-ons, each with its OWN standalone installer
  (no binary; no bundling with any other member). `agy-autotrain` needs a clavity driver installed to
  have somewhere to inject its learned header (a non-blocking runtime warning otherwise); `commonmemory`
  needs the `agentmemory` MCP server to be useful.

Every installer is independent — grab exactly the ones you want from the same
[release page](../../releases). There is **no** live remote marketplace; every plugin ships locally
inside its own installer.

## Adding a product

New products follow one repeatable pattern (its own top-level folder; an Inno-Setup installer; its own
release lineage bundled into the umbrella release). See the playbook:
[`docs/hosting-a-tool.md`](docs/hosting-a-tool.md).

## Dev workflow

This monorepo uses a two-tier [`just`](https://github.com/casey/just) task runner. From the repo root:

- `just test` — run every tool's tests · `just lint` — every tool's CI lint gate · `just build` · `just fmt`
- One tool only: `just classic::test`, `just dotnet::lint`, `just ghidrust::build`, …
- **Cut a release:** `just release` (preview with `just release-dry`) — auto-versions + changelogs every member with new conventional commits and publishes one `clavity-vN` umbrella release.
- **Interactive menu:** `pwsh -File DevelopersCockpit.ps1` — a one-stop cockpit over the `just`/scripts/release tasks (delegates, never duplicates; ship actions owner-gated).

Each tool's recipes mirror its CI gate exactly. First-time ghidrust setup (installs `cargo-nextest` +
`cargo-deny` + `cargo-insta`): `just ghidrust::setup`.

Git hooks are managed by [`lefthook`](https://github.com/evilmartians/lefthook) — run `lefthook install`
once per clone. **pre-push** runs five gates: `just lint` (fmt/clippy/compile breaks), `just
seed-sync-check` (seed-artifact drift), `just check-register-hash` (register-plugin hash drift), `just
test-scripts` (the PowerShell script test suite), and `check-versions.ps1` per member (version-source
drift) — all before CI; **pre-commit** runs `ruff` on staged Python (the agy bridge) only.

## License

This project is licensed under the **PolyForm Noncommercial License 1.0.0** — free for non-commercial
use (personal, academic, non-profit). See [LICENSE](LICENSE). All five products (clavity-dotnet,
clavity-classic, ghidrust, agy-autotrain, commonmemory) ship under the same license.

_Trademarks:_ Antigravity is a trademark of Google LLC; Claude and Claude Code are trademarks of
Anthropic; Ghidra is a trademark of the National Security Agency. This is an independent project — not
affiliated with, endorsed by, or sponsored by Google, Anthropic, or the NSA.
