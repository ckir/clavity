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

# Bump every version source for a member to <version>, then self-verify (dotnet/classic/agy-autotrain/commonmemory).
bump member version:
    pwsh -File scripts/bump-version.ps1 {{member}} {{version}}

# Bump ghidrust independently per channel (binary = crates+iss, plugin = plugin.json ×2).
bump-ghidrust channel version:
    pwsh -File scripts/bump-version.ps1 ghidrust {{version}} -Channel {{channel}}

# Check a member's version sources agree (dev-time gate mirror of CI).
check-versions member:
    pwsh -File scripts/check-versions.ps1 {{member}}
