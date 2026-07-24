# clavity monorepo — top-level dev tasks. Run `just` to list.
# Two-tier: this root delegates to each tool's own justfile via `mod`. Submodule recipes run with the
# working directory set to the tool folder, so `cargo`/`dotnet` resolve correctly.
# One tool: `just classic::test`. All tools: `just test`.

mod dotnet 'clavity-dotnet/justfile'
mod classic 'clavity-classic/justfile'
mod ghidrust 'ghidrust/justfile'

default:
    @just --list

# Aggregate lint across every tool (each recipe mirrors that tool's CI gate).
lint: dotnet::lint classic::lint ghidrust::lint

# Aggregate tests across every tool.
test: dotnet::test classic::test ghidrust::test

# Aggregate build across every tool.
build: dotnet::build classic::build ghidrust::build

# Aggregate format across every tool (mutating).
fmt: dotnet::fmt classic::fmt ghidrust::fmt

# Verify the seed agent artifacts are byte-identical across the two driver plugins
seed-sync-check:
    bash scripts/check-seed-artifacts-synced.sh

# Lint the shipped agy-driving discipline skills (frontmatter, [VERDICT] grammar, transports, marker)
check-agy-skills:
    pwsh -NoProfile -Command "./scripts/check-agy-discipline-skills.ps1"

# Verify docs reduced to pointer stubs have not been re-fattened into duplicate content
check-doc-stubs:
    pwsh -File scripts/check-doc-stubs.ps1

# Verify every member has its required user-facing docs and a release-injectable CHANGELOG
check-member-docs:
    pwsh -File scripts/check-member-docs.ps1

# Verify docs/user-facing-docs.txt lists only existing, non-do-not-touch, voiced docs (docs-rationalize target).
check-user-facing-docs:
    pwsh -File scripts/check-user-facing-docs.ps1

# Verify every relative link in the product docs resolves (becheran/mlc; config in .mlc.toml).
# Not wired into lefthook: it reports 2 KNOWN errors -- the GitHub-relative release links in
# README.md and ghidrust/README.md, which are correct under GitHub rendering but unresolvable to an
# offline filesystem check. Anything beyond those two is a real defect. Read .mlc.toml first.
check-links:
    mlc

# Bump every version source for a member to <version>, then self-verify (dotnet/classic/agy-autotrain/commonmemory).
bump member version:
    pwsh -File scripts/bump-version.ps1 {{member}} {{version}}

# Bump ghidrust independently per channel (binary = crates+iss, plugin = plugin.json ×2).
bump-ghidrust channel version:
    pwsh -File scripts/bump-version.ps1 ghidrust {{version}} -Channel {{channel}}

# Check a member's version sources agree (dev-time gate mirror of CI).
check-versions member:
    pwsh -File scripts/check-versions.ps1 {{member}}

# Drain machine-local agy-learn captures into a REVIEWABLE GROWTH proposal (docs/agy-golden-header.growth.md) +
# docs side-artifacts via a headless claude curator (EXTEND model — the runtime golden-header is published later by
# `just accept-drain`; the drain never edits the SEED, the 4 manuals, or driver-cheatsheet.core.md). NO commit and
# NO runtime write — review `git status`/`git diff` then `just accept-drain` or `just abort-drain`. `*args` forwards
# flags such as `-WhatIf` (dry-run) and `-InboxPath <path>` (AB1: without `*args`, `just` rejects extra args).
drain-knowledge *args:
    pwsh -File scripts/drain-knowledge.ps1 {{args}}

# Reject a pending drain: restore all outputs and re-queue the staged observations into the inbox.
abort-drain *args:
    pwsh -File scripts/abort-drain.ps1 {{args}}

# Accept a committed drain: prove the run-ID is committed + the tree is clean, publish the reviewed GROWTH proposal
# to the runtime header via curate-commit, then delete the staging snapshot.
accept-drain *args:
    pwsh -File scripts/accept-drain.ps1 {{args}}

# Stage-1 docs-rationalize AUDIT: read-only `claude -p` doc-vs-code accuracy audit over docs/user-facing-docs.txt,
# emitting a per-doc punch-list (docs/docs-audit-findings.md) + append-only log (docs/docs-audit-log.md). Makes NO
# doc edits and NO commit. RUN ON DEMAND / BACKGROUNDED ONLY — never a gate, never in lefthook. `*args` forwards
# flags: `-Only a.md,b.md` (narrow to a subset, skips the link-check — COMMAS, NO SPACES: under `pwsh -File` a
# space-separated 2nd value silently binds to the next positional parameter), `-WhatIf` (dry-run preview — no
# lock, no claude -p, no writes), `-RepoRoot <path>`. Main thread picks up the punch-list for Stage 2.
docs-audit *args:
    pwsh -File scripts/docs-audit.ps1 {{args}}

# Run the pwsh unit tests for the release engine (pure-logic seam).
test-scripts:
    pwsh -c "Invoke-Pester scripts/tests -Output Detailed -CI"

# Gate the Windows PowerShell 5.1 domain (the end-user installer surface) to pure ASCII.
# ~6s, and the ONLY local check that can catch a CP1252 mangling: pwsh 7 defaults to UTF-8, so a
# BOM-less non-ASCII .ps1 looks fine locally and only breaks on a stock 5.1 box.
check-installer-ascii:
    pwsh -File scripts/check-installer-ascii.ps1

# Prepare + gate + push a live umbrella release (auto semver + CHANGELOG from conventional commits).
release:
    pwsh -File scripts/release.ps1

# Preview what `just release` would do — compute + notes, NO writes/tag.
release-dry:
    pwsh -File scripts/release.ps1 -WhatIf

# Regenerate the pinned SHA-256 of register-plugin.ps1 (uninstaller tamper check).
sync-register-hash:
    pwsh -File scripts/sync-register-hash.ps1

# Fail if register-plugin-hash.iss drifted from register-plugin.ps1 (pre-push gate).
check-register-hash:
    pwsh -File scripts/check-register-hash-synced.ps1
