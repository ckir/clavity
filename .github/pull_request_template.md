<!-- Thanks for contributing to clavity! -->

## What & why

<!-- What does this PR change, and why? -->

## How verified

<!-- Monorepo: the cargo commands below are for clavity-classic (the Rust product) and must be run from
     `clavity-classic/` — there is no root Cargo.toml, so they fail from the repo root. Other products
     build per their own CLAUDE.md (e.g. `dotnet test tests/Clavity.Ls.Tests`, `just test`). -->

- [ ] `cargo test --all --features test-fakes` passes *(from `clavity-classic/`)*
- [ ] `cargo clippy --all-targets --features test-fakes -- -D warnings` is clean *(from `clavity-classic/`)*
- [ ] `cargo fmt --all --check` is clean *(from `clavity-classic/`)*
- [ ] **Live acceptance runbook** (see `CONTRIBUTING.md`) — OS: `____`
      <!-- Required when touching the doorbell, the checkpoint, or a platform port. -->

## Notes

<!-- Platform(s) tested, follow-ups, anything reviewers should know. -->
