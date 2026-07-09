# clavity — notes for Claude

clavity drives a **live, external, frequently-updated** tool — Antigravity (`agy`) — over `psmux`
(`send-keys`/`capture-pane`) and the `agentmemory` signal bus. Its behavior is **empirically derived,
not a stable contract**, so an agy / psmux / agentmemory update can silently change things and break it.

**If clavity misbehaves, or before you change anything agy-facing, read
[`plugins/agy-autotrain/knowledge/agy-assumptions.md`](plugins/agy-autotrain/knowledge/agy-assumptions.md)
first** (the canonical, agy-version-current manual; `docs/agy-assumptions.md` is now just a pointer to it).
It lists every load-bearing assumption
(footer markers, agy's pwsh shell, skill caching, workspace-scoped writes, headless-print hanging,
the bus, keyring auth, …), the versions verified against, **how each was verified**, and **how to
re-verify and fix** — most breakages are fixable via an `AGY_*` env override or the responder skill,
not Rust code.

Quick re-verify: `clavity doctor`; `clavity capture --viewport` (idle vs busy footer); a bus `[ping]`
round-trip. agy's own logs live at `~/.gemini/antigravity-cli/` (`cli.log` + `log/`).

Dev: `cargo test --all --features test-fakes`, `cargo clippy --all-targets --features test-fakes -- -D warnings`,
`cargo fmt --all`. See `CONTRIBUTING.md` for the live acceptance runbook and the Linux/macOS porting guide.
(The .NET `clavity-dotnet` variant — the `Clavity.Ls` MCP LS behind `agy_ask`/`agy_status`/`agy_look` — builds/tests with `dotnet build` / `dotnet test tests/Clavity.Ls.Tests`.)

## Recent session notes
- [2026-07-04 — `Clavity.Ls` ask-Answer fix + `clavity-v2` release](docs/session-notes/2026-07-04-ls-ask-answer-fix-and-clavity-v2.md)
  — fixed null `Answer` on a tool-terminated agy turn (`BoundedView.ProjectAskReply` now rescues the last
  assistant run's full prose into `Activity` instead of clipping to 200); released as dotnet **0.1.10** / umbrella
  tag **`clavity-v2`**. Includes the release runbook (serial `clavity-v<N>` tag; bump `installer/clavity-dotnet.iss`).
