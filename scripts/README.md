# scripts/ — index

Dev/CI tooling for the monorepo: release engineering, pre-push/CI gates, the agy-learn knowledge
drain, and golden-header (SEED) integrity. Grouped by function below; every file in this folder is
listed exactly once. Most are run via a `just` recipe (see the root `justfile`) rather than
directly.

## Release & versioning

| Script | Purpose | Run via |
|---|---|---|
| `release.ps1` | Prepare + gate + push a live umbrella release (auto semver + CHANGELOG from conventional commits) | `just release` / `just release-dry` (`-WhatIf`) |
| `compute-release.ps1` | Compute the next release: baseline SHA, next serial, per-member/shared version bumps from conventional commits | invoked by `release.ps1` |
| `bump-version.ps1` | Write every version source for one member (or one ghidrust channel) to `<Version>`, then self-verify via `check-versions.ps1` | `just bump <member> <version>` / `just bump-ghidrust <channel> <version>` |
| `check-versions.ps1` | Assert every version source for one member agrees (or, with `-Coverage`, that no tracked version-bearing file is unregistered) | `just check-versions <member>` |
| `check-versions-all.ps1` | Run `check-versions.ps1` for every member in one pwsh process (avoids 5 cold starts) | lefthook pre-push (`check-versions`); run directly, no `just` recipe |
| `check-roster.ps1` | Assert the release-tooling roster (`lib/release-lib.ps1`) matches `build/members.json`'s member set, and the shared-path map matches the installers | CI (`umbrella-release.yml`); run directly, no `just` recipe |
| `generate-scoped-manifest.ps1` | Generate one member's single-plugin scoped `marketplace.json` from `build/members.json` | CI (`build-<member>.yml`); run directly, no `just` recipe |
| `validate-members-manifest.ps1` | CI guard: `build/members.json` has exactly 5 members, each with `name`/`source`/`marketplaceName`, all `marketplaceName` values distinct | CI (`validate-members.yml`); run directly, no `just` recipe |

## Pre-push / CI gates

| Script | Purpose | Run via |
|---|---|---|
| `check-doc-stubs.ps1` | Fail if a doc deliberately reduced to a pointer stub has been re-fattened into a duplicate copy | `just check-doc-stubs` |
| `check-member-docs.ps1` | Fail if any member is missing a required user-facing doc, or ships a CHANGELOG the release machinery can't inject into | `just check-member-docs` |
| `check-user-facing-docs.ps1` | Fail if `docs/user-facing-docs.txt` lists a nonexistent or do-not-touch doc; warn if a user-facing-shaped doc is missing from the list | `just check-user-facing-docs` |
| `check-installer-ascii.ps1` | Assert every `.ps1` in the Windows PowerShell 5.1 (end-user installer) domain is pure ASCII | `just check-installer-ascii` |
| `check-register-hash-synced.ps1` | Fail if `register-plugin-hash.iss` is stale vs the current `register-plugin.ps1` (uninstaller tamper-check drift guard) | `just check-register-hash` |
| `sync-register-hash.ps1` | Regenerate `register-plugin-hash.iss` with the current SHA-256 of `register-plugin.ps1` | `just sync-register-hash` |
| `check-agy-discipline-skills.ps1` | Lints shipped agy-driving discipline skills (frontmatter, ASCII-only [VERDICT] grammar, transports, marker constant) | `just check-agy-skills` (pre-push) |
| `check-plugin-namespace.ps1` | SP-0 namespace-rename completeness gate: fails if the mass rename left any stray old plugin-namespace, skill-dir, or plugin-identity reference | lefthook pre-push (`check-plugin-namespace`); run directly, no `just` recipe |

## Seed / golden-header integrity

| Script | Purpose | Run via |
|---|---|---|
| `check-seed-artifacts-synced.sh` | Fail if the seed agent artifacts (adversarial-panel-review skill, the AGY-AFTER, auto-fire seam-inject, and SessionStart liveness hooks, the two driver knowledge manuals, `hooks.json`'s shared PostToolUse + PreToolUse blocks + the shared SessionStart liveness entry) drift between the two driver plugins | `just seed-sync-check` |
| `check-seed-budget.ps1` | Assert the injected golden-header SEED alone is within its committed byte budget (default 7992 B) | CI (`build-dotnet.yml`, `build-classic.yml`); run directly, no `just` recipe |
| `check-core-integrity.ps1` | Assert every protected driver-owned file (the SEED, the four driver manuals, `driver-cheatsheet.core.md`) is byte-identical to its committed HEAD version after a drain | invoked by `drain-knowledge.ps1` |
| `check-growth-budget.ps1` | Warn-only gate: assert SEED+GROWTH combined size fits the binary's 16 KiB injection cap | invoked by `drain-knowledge.ps1` (warn-only) |

## Knowledge drain & docs-audit tooling

| Script | Purpose | Run via |
|---|---|---|
| `drain-knowledge.ps1` | Drain machine-local agy-learn captures into a reviewable GROWTH proposal via a headless `claude -p` curator, then run the SEED/core/budget gates. No commit. | `just drain-knowledge` |
| `drain-knowledge-prompt.md` | The prompt fed verbatim to the headless curator `claude -p` call inside `drain-knowledge.ps1` | input to `drain-knowledge.ps1`, not executable |
| `drain-lib.ps1` | Shared, parameter-less drain primitives (inbox-path resolution, pending-bullet counting, the protected-path list) | dot-sourced by `abort-drain.ps1`, `accept-drain.ps1`, `drain-knowledge.ps1`, `check-core-integrity.ps1`; no recipe |
| `abort-drain.ps1` | Reject a pending drain: git-restore every tracked drain output and restore the staged observations into the inbox's Pending section | `just abort-drain` |
| `accept-drain.ps1` | Accept a committed drain: verify the run-ID is committed and the tree is clean, publish the reviewed GROWTH proposal via curate-commit, delete the staging snapshot | `just accept-drain` |
| `docs-audit.ps1` | Stage-1 docs-rationalize audit: read-only `claude -p` doc-vs-code accuracy audit over `docs/user-facing-docs.txt`, emitting a per-doc punch-list + append-only log. No doc edits, no commit. | `just docs-audit` |
| `docs-audit-prompt.md` | The prompt fed to the per-doc `claude -p` auditor call inside `docs-audit.ps1` | input to `docs-audit.ps1`, not executable |
| `docs-audit-lib.ps1` | Shared, parameter-less docs-audit primitives (doc-list parsing, in-scope resolution) | dot-sourced by `docs-audit.ps1`; no recipe |
| `discipline-reaching-report.ps1` | Read-only reader for `.clavity/discipline-reaching.jsonl`: reports whether the AGY-ANOMALIES dispatch relay is reaching a driver. Never folds a `null` count into a zero, never prints a ratio, reports sessions RECORDED (distinct sessions, not runs), and quarantines still-running sessions in a `PROVISIONAL` bucket — each refusal blocks a measured false conclusion | `just discipline-report [--Last N]` |

## Subdirectories

- `lib/` — shared PowerShell helpers (`release-lib.ps1`), dot-sourced by the release/versioning
  scripts above.
- `tests/` — Pester suites covering the scripts in this folder (count via `ls scripts/tests/*.Tests.ps1`), run via `just test-scripts`.
- `ci/fake-claude/` — a stub `claude` CLI (`claude.cmd` + `fake-claude.ps1`) simulating `plugin
  marketplace add/remove`, `plugin install/uninstall`, and `plugin list`; used by the ghidrust
  installer CI smokes (`build-ghidrust.yml`, `ci-installer-ghidrust.yml`) so those workflows need
  no real `claude` CLI.

## Anomalies

- `GitHub_Actions_Storage_Reset.ps1` — a manual, interactive `gh`-CLI utility to list/delete
  GitHub Actions caches and logs (`-NonInteractive` skips the prompts). Not referenced by the
  justfile, lefthook, or any CI workflow — run it by hand.
- `release-abandoned.txt` — data, not a script: one `clavity-vN` per line, the release serials the
  maintainer retracted (tag + GitHub Release deleted) after a completed release.
  `lib/release-lib.ps1` (`Get-AbandonedSerials` / `Get-NextSerial`) unions it with git tags so a
  burned serial is never reused, and `release.ps1` treats a listed serial's missing remote tag as a
  deliberate retraction rather than a stuck release.
