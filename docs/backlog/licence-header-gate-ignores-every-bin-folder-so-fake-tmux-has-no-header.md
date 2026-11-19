# Backlog stub - the licence-header checks ignore every `bin/` folder, so `clavity-classic/src/bin/fake_tmux.rs` has no header

**Status:** OPEN 2026-11-19 - promoted from `.clavity/local-anomalies.md`; not yet scheduled

**Raised:** 2026-11-19, found by the whole-branch review of the three-licences work.
**Scope:** `.github/workflows/ci-license-headers.yml` (the `addlicense` ignore list) and `scripts/check-licensing-consistent.ps1`
(`Test-IgnoredPath`, which copies that list).

## The defect

Both the CI header check and the licensing gate ignore any path with a `bin` segment, a rule meant for build output
(`bin/Debug`). `clavity-classic/src/bin/fake_tmux.rs` is a tracked first-party Rust source file (a fake `tmux` for
integration tests, built only with `--features test-fakes`) and lives under `src/bin/`, so it is skipped. Its first line is
a `//!` doc comment with no `Copyright (c)` header, unlike every other first-party source file.

## What a fix has to establish

Either give the file the five-line header and narrow the ignore so a `bin` folder is ignored only where it is build output
(for example `**/bin/Debug/**`, `**/bin/Release/**`, or only outside `src/`), in the workflow and in `Test-IgnoredPath` together
(the gate's own header says it mirrors the workflow), or record that the file is deliberately exempt. Re-run
`go run github.com/google/addlicense@v1.1.1 -f header.txt -check ...` and `just check-licensing` afterwards.
