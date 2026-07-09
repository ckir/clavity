# Version-Stamp Automation — Design

**Date:** 2026-07-09
**Status:** approved (design); pending AGY-AFTER + spec review → implementation plan

## Problem

Every release hand-edits a tool's version across multiple checked-in files that MUST agree, and drift causes
same-version/different-content installer collisions (hit twice while cutting clavity-v4 / v5). Current stamp
topology:

| Tool | Stamps that must agree | Channel |
|------|------------------------|---------|
| clavity-dotnet | `installer/clavity-dotnet.iss` `#define AppVersion` + `plugins/clavity-dotnet/plugin.json` + `plugins/clavity-dotnet/.claude-plugin/plugin.json` | installer ver **==** plugin ver |
| ghidrust | `installer/ghidrust.iss` (branch `ghidrust`) **vs** `plugins/ghidrust/plugin.json` ×2 (main) | installer=**binary** ver (1.0.0) **decoupled** from plugin ver (0.1.0) |
| clavity-classic | `installer/clavity-classic.iss` (branch `clavity-classic`) + `plugins/clavity-classic/plugin.json` ×2 (main) | installer=binary ver, decoupled from plugin ver |
| agy-autotrain / commonmemory | `plugin.json` ×2 each (no installer) | plugin only |

Build workflows (`build-dotnet.yml`, `build-ghidrust.yml`) currently EXTRACT the version by regex/`Select-String`
from the `.iss` at build time.

## Goal

A maintainer changes **one** number per tool per release; derived stamps follow automatically or CI fails the
release. No bespoke templating engine (per divergent review): prefer *deleting* stamps and injecting at build
over generating files.

## Principle

Each version lives at its ONE natural source; every other representation is either (i) removed, (ii) injected at
build time, or (iii) CI-verified equal. Cross-branch **binary** and **plugin** versions are DECOUPLED — they
evolve independently and are never force-synced.

## Canonical sources of truth

- **Plugin channel** (each plugin, on `main`): `plugins/<name>/.claude-plugin/plugin.json` `version`. This is the
  manifest Claude Code actually consumes (the marketplace `source` points at the plugin *dir*; neither `clavity-ls`
  nor `marketplace.json` reference the root `plugin.json` — verified 2026-07-09).
- **Installer / binary channel**:
  - **clavity-dotnet**: installer version == plugin version, so `plugins/clavity-dotnet/.claude-plugin/plugin.json`
    is the SoT for BOTH the plugin and the `.iss`.
  - **ghidrust**: `crates/ghidrust-mcp/Cargo.toml` `[package] version` (on branch `ghidrust`; currently 1.0.0) is
    the SoT for `ghidrust.iss`. The ghidrust *plugin* version is independent.
  - **clavity-classic**: the classic binary's canonical version on branch `clavity-classic` is the SoT for
    `clavity-classic.iss`. (Exact source file confirmed in the plan — classic build internals not re-verified here.)

## Components

### C1 — `.iss` stops carrying a real version (build-time `/D` injection)
Each `.iss` replaces its hardcoded `#define AppVersion "x.y.z"` with a guarded placeholder:

```
#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
```

The build workflow reads the real version from that tool's SoT and passes it to ISCC:
`ISCC /DAppVersion=<resolved> installer/<tool>.iss`. Everything downstream (`OutputBaseFilename`,
`clavity-<tool>-setup-{#AppVersion}.exe`, the `.sha256` name, release notes) already flows from `{#AppVersion}`,
so no other `.iss` change is needed. The in-repo `.iss` therefore has NO drift-able version.

Version resolution per tool (replaces the current `Select-String` on the `.iss`):
- **build-dotnet.yml**: `jq -r .version plugins/clavity-dotnet/.claude-plugin/plugin.json`.
- **build-ghidrust.yml**: the `[package] version` from `crates/ghidrust-mcp/Cargo.toml`
  (`cargo metadata --format-version 1 --no-deps` → the `ghidrust-mcp` package `version`; a `cargo`-native read,
  not a brittle grep).
- **build-classic.yml**: the classic binary's canonical version (source confirmed in the plan).

### C2 — Resolve the duplicate `plugin.json`
`.claude-plugin/plugin.json` is canonical. The root `plugins/<name>/plugin.json` is an unreferenced mirror.
Resolution, in priority order:
1. **Preferred — remove the root mirror** if the plan confirms no consumer needs it (test: with the root
   `plugin.json` absent, Claude Code installs the plugin from the marketplace dir AND an agy `install <dir>` still
   loads it). If both pass, delete every `plugins/<name>/plugin.json`, leaving only `.claude-plugin/plugin.json`.
2. **Fallback — keep + CI-verify** if any consumer needs the root file: a CI check asserts
   `root.version == .claude-plugin.version` for every plugin dir, failing the build on mismatch. (No generator; the
   maintainer edits the canonical file and CI catches a forgotten mirror.)

### C3 — CI consistency guard (OUTPUT-verified, not input-trusted)
A check in the build workflows (and/or `ci.yml`). The guard must verify what actually got BUILT, not just the
upstream variable — trusting the resolved variable lets a broken injection ship silently (AGY-AFTER R1).

- **Resolved-version sanity (pre-ISCC)**: after reading the SoT, fail unless the value matches `^\d+\.\d+\.\d+`.
  This explicitly rejects the empty string (swallowed `cargo metadata`), the literal `null` (a `plugin.json` missing
  its `version` key — `jq -r .version` emits `null`), whitespace, AND the `0.0.0-dev` placeholder. Checking only
  `== 0.0.0-dev` is insufficient — `null`/`""` pass it and produce `setup-null.exe` (AGY-AFTER R2).
- **Built-artifact guard (post-ISCC)**: after ISCC, assert `dist/<tool>-setup-<resolved>.exe` EXISTS — i.e. the
  compiled installer's version equals the resolved SoT version. If the `/D` injection silently failed to override,
  the expected-named file is absent and the build fails here (this is the real guarantee; the pre-ISCC check alone
  does not prove ISCC honored `/D`). The existing `Test-Path $setup` steps already do this shape — they just must
  compute `<resolved>` from the SoT, not from the (now placeholder) `.iss`.
- **Duplicate guard** (only if C2 fallback is taken): the two `plugin.json` versions match for every plugin.
- **Marketplace sanity** (carried from the ghidrust work): every `marketplace.json` plugin `source` dir exists.

### C4 — Maintainer flow (the payoff)
- Release **clavity-dotnet 0.1.14**: edit ONE number in `plugins/clavity-dotnet/.claude-plugin/plugin.json`
  (if C2 fallback: the CI guard reminds you of the mirror), commit, bump the umbrella tag, done. Installer version
  follows at build.
- Release **ghidrust** binary: bump `crates/ghidrust-mcp/Cargo.toml` on the `ghidrust` branch; installer follows.
  The ghidrust *plugin* version moves independently in its `plugin.json`.

## Error handling

- **SoT not found / path typo** → `jq`/`cargo` yields `null`, `""`, or nothing → C3 resolved-version sanity
  (`^\d+\.\d+\.\d+`) fails the build, loud and early (NOT just an `== 0.0.0-dev` check — `null`/`""` would pass that).
- **`#ifndef` guard omitted in the `.iss`** → ISCC sees a `/D` define AND an in-file `#define` of the same symbol →
  ISCC **errors on redefinition** and the build fails (loud, not silent). The `#ifndef` guard is what makes `/D`
  win cleanly.
- **`/D` injection silently not honored** (any reason) → the built installer carries `0.0.0-dev` → C3
  built-artifact guard fails because `dist/<tool>-setup-<resolved>.exe` is absent. This is why the guard is
  OUTPUT-verified, not input-trusted.
- **ISCC macro-quote typing** → the quoted fallback `#define AppVersion "0.0.0-dev"` and an unquoted
  `/DAppVersion=0.1.12` could expand differently under `{#AppVersion}`. The plan MUST verify both emit an identical
  bare version string (they do for filename/`AppVersion` usage); if any `[Code]` string op needs a String type,
  inject with explicit quotes instead. (AGY-AFTER R3.)
- **Duplicate drift** (C2 fallback) → C3 duplicate guard fails.

## Testing

- **Unit-ish**: a script/test asserts version resolution returns the expected semver for each tool from a fixture
  SoT; asserts placeholder-guard fires on a missing/renamed SoT.
- **Workflow**: a `workflow_dispatch` build run per tool produces `…-setup-<real-semver>.exe` (not `0.0.0-dev`),
  proving `/D` injection end-to-end. (clavity-dotnet already re-buildable via dispatch.)
- **C2 removal test** (if taken): install the marketplace plugin in Claude Code + `agy install <dir>` with the root
  `plugin.json` deleted; both load.

## Migration / rollout

Each tool's `.iss` and its `build-<tool>.yml` are CO-LOCATED on the same branch (verified 2026-07-09:
clavity-dotnet both on `main`; ghidrust both on branch `ghidrust`; classic both on branch `clavity-classic` —
`build-ghidrust.yml` is NOT on `main`). Therefore the cutover for each tool is a **single atomic commit** on that
tool's branch that BOTH (a) replaces the `.iss` `#define` with the `#ifndef … 0.0.0-dev` placeholder AND (b) flips
that tool's build workflow to read the version from the new SoT + pass `/D` + apply the C3 guard. Never split (a)
and (b) across commits — a lone (a) would let the old workflow regex-extract `0.0.0-dev`; a lone (b) would hit an
ISCC redefinition error. (The migration-deadlock concern assumed workflow-on-main / iss-on-branch; measured false —
they are co-located, so no non-atomic window exists as long as (a)+(b) ship together.)

Order the tools: **clavity-dotnet first** (both files on `main`, easiest to validate via `workflow_dispatch`), then
ghidrust, then classic. Each is independently shippable.

## Out of scope (now)

- `release-please` or commit-history-driven auto-bump (future full automation; heavier dependency + conventional
  commits). Revisit as a phase 2.
- Changing the umbrella serial tag scheme (`clavity-v<N>`) — orthogonal; tags stay serial, semvers stay in the SoT.

## Open items (resolved where noted)

- **O1 (plan)**: confirm whether the root `plugin.json` is removable (C2 step 1) vs must be kept (C2 step 2). Gates
  whether ANY sync/CI-equality logic is needed at all.
- **O2 (plan)**: confirm `build-classic.yml`'s current version source + the classic binary's canonical version file
  (classic build internals not re-verified in this spec — frozen variant).
- **O3 (plan)**: where the CI guard lives (each `build-*.yml` vs a shared `ci.yml` step) — pick per least
  duplication.
