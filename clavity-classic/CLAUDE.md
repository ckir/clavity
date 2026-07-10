# clavity — notes for Claude

clavity drives a **live, external, frequently-updated** tool — Antigravity (`agy`) — over `psmux`
(`send-keys`/`capture-pane`) and the `agentmemory` signal bus. Its behavior is **empirically derived,
not a stable contract**, so an agy / psmux / agentmemory update can silently change things and break it.

**If clavity misbehaves, or before you change anything agy-facing, read
[`plugin/knowledge/agy-assumptions.md`](plugin/knowledge/agy-assumptions.md) first.** It lists every load-bearing assumption
(footer markers, agy's pwsh shell, skill caching, workspace-scoped writes, headless-print hanging,
the bus, keyring auth, …), the versions verified against, **how each was verified**, and **how to
re-verify and fix** — most breakages are fixable via an `AGY_*` env override or the responder skill,
not Rust code.

Quick re-verify: `clavity doctor`; `clavity capture --viewport` (idle vs busy footer); a bus `[ping]`
round-trip. agy's own logs live at `~/.gemini/antigravity-cli/` (`cli.log` + `log/`).

Dev: `cargo test --all --features test-fakes`, `cargo clippy --all-targets --features test-fakes -- -D warnings`,
`cargo fmt --all`. See `CONTRIBUTING.md` for the live acceptance runbook and the Linux/macOS porting guide.
