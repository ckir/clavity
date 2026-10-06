# clavity — notes for Claude

agy-facing guidance lives in the root `CLAUDE.md` (read
[`plugin/knowledge/agy-assumptions.md`](plugin/knowledge/agy-assumptions.md) first).

Quick re-verify: `clavity doctor`; `clavity capture --viewport` (idle vs busy footer); a bus `[ping]`
round-trip. agy's own logs live at `~/.gemini/antigravity-cli/` (`cli.log` + `log/`).

Dev: `cargo test --all --features test-fakes`, `cargo clippy --all-targets --features test-fakes -- -D warnings`,
`cargo fmt --all`. See `CONTRIBUTING.md` for the live acceptance runbook and the Linux/macOS porting guide.
