# Monorepo Development Workflow — Design

**Date:** 2026-07-09
**Status:** design approved (user); AGY-AFTER panel GREEN (4 rounds, cascade `e350f145`); pending user
spec-review → per-item plans
**Kind:** GOVERNING spec — pins monorepo-native conventions and sequences the remaining sub-projects.
Each sub-project keeps its own spec→plan→execute cycle; this document is the index they hang off.

## Problem

The `clavity` repo reached its current shape by MIGRATION, not by design: it was a set of tool-per-branch
products consolidated into a single-tree monorepo (all five products — clavity-dotnet, clavity-classic,
ghidrust, agy-autotrain, commonmemory — now top-level folders on `main`; per-tool build branches
`clavity-classic` and `ghidrust` retired, `archive/*` tags preserving their history). The migration silently
invalidated assumptions baked into two PENDING specs that were authored beforehand:

- **version-stamp-automation** still says ghidrust's `.iss` lives on branch `ghidrust` and that
  `build-ghidrust.yml` is "not on main"; and classic's `.iss` on branch `clavity-classic`.
- **per-plugin-decoupled-installers** (C4) still resolves builds from `classic@clavity-classic` and
  `ghidrust@ghidrust` — branches that no longer exist.

Verified 2026-07-09: all three `.iss` files (`clavity-dotnet/installer/`, `clavity-classic/installer/`,
`ghidrust/installer/`), all nine workflows, and all five tool folders are on `main`; `origin` has only `main`;
`archive/clavity-classic` and `archive/ghidrust` tags exist.

The conventions (branch model, CI topology, version/deps SoT, dev-tool layout, installer coupling) therefore
need to be re-pinned as monorepo-native BEFORE the sub-projects execute against them.

## Conventions (the constitution)

### K1 — Branch model: single-tree
`main` is the only long-lived branch; every tool builds *from* `main`. Feature work happens on short-lived
branches merged back to `main`. Releases are `clavity-v<N>` tags on `main`, cut by `umbrella-release.yml`.
Per-tool build branches stay **retired and are never reintroduced** (their history is in `archive/*` tags).
Housekeeping: delete the stale local `clavity-dotnet` and `fix-*` branches (no remote counterparts).

### K2 — CI topology: split, path-filtered (one lane per shippable artifact)
Per-tool workflows stay SEPARATE, gated by native GitHub Actions `paths:` filters; `umbrella-release.yml` remains
the sole aggregator. Do NOT consolidate into a single `ci.yml` driven by `dorny/paths-filter` — that trades
zero-maintenance native filtering for YAML bloat, brittle job chains, and noisy "skipped" checks. The convention
is **one path-filtered build lane per shippable artifact**, NOT a frozen count. Today three compiled tools have
`ci-*.yml` + `build-*.yml`, already green on `main`. Item 4 (K5) grows this to FIVE installer-build lanes by
adding ISCC-only build coverage for the two plugin-only tools (agy-autotrain, commonmemory — no compile step),
so `umbrella-release.yml` can harvest all five installer artifacts. K2 ratifies the split *principle* and its
growth rule; it does not fix the workflow count at three.

### K3 — Version + deps: SoT + toolchain unify (bot deferred)
- **Version SoT.** Each tool's version lives at one in-tree source of truth, `/D`-injected into its installer at
  build, and CI output-verified — as designed in the (refreshed) version-stamp-automation spec.
- **Toolchain unification.** A single shared Rust toolchain pin covers both Rust workspaces (classic + ghidrust,
  both already at 1.96.0); a pinned .NET SDK; lockfiles committed. The two Cargo workspaces stay **separate** —
  no root `Cargo.toml` — because they carry different licenses (MIT vs PolyForm-NC) and independent crate graphs.
- **Dependency-update automation** (Renovate/Dependabot across both Cargo workspaces + .NET + Actions pins) is an
  explicit **phase 2**, deferred to avoid a recurring update-PR surface mid-roadmap.

### K4 — Dev-tools: two-tier `just` + pre-push lint
A root `justfile` delegates (via `just`'s `mod` feature) to per-tool justfiles, so `just test` / `just build`
work from the repo root while tool-specific build logic stays encapsulated per-tool. Create per-tool justfiles
for clavity-dotnet and clavity-classic; ghidrust already has one. A root `lefthook.yml` runs each tool's
`just lint` (fmt/clippy and the .NET equivalent) on **pre-push only** — catching malformed pushes locally before
they burn a CI bounce, which matters in an agent-driven repo where an agent may push unformatted code.
Pre-*push* (not pre-commit) keeps commit-time friction at zero. **No pre-commit hooks.** (Decided via the
AGY-AFTER panel on 2026-07-09: the initial "no git hooks at all" call was revised to add pre-push lint after the
UX/operator seat flagged the agent-push-loop cost; cascade `e350f145`.)

### K5 — Installers: fully decoupled + uninstall parity
Each tool ships its OWN standalone installer that self-registers only its own plugin (per the refreshed
decoupled-installers spec); no installer bundles or references another. All **four non-dotnet installers**
(clavity-classic, ghidrust, agy-autotrain, commonmemory) gain "Remove configuration files" uninstall parity so
every tool cleans up after itself symmetrically.

## Sequenced roadmap

Dependency reasoning: **3 must precede 4** (automate version stamps before five installers exist, else each
release hand-bumps five `.iss` files); **2 must precede 3 and 4** (a plan built on specs that assume retired
branches is unsafe); **1 is independent** and goes first as a cheap ergonomic win that every later task benefits from.

| # | Item | Gates | Rationale |
|---|------|-------|-----------|
| 0 | This governing spec | — | Pins K1–K5 + the order |
| 1 | **Dev-tools** — `just` two-tier + lefthook pre-push lint (K4) | independent | Quick win, first; improves every later task's ergonomics and guards pushes |
| 2 | **Refresh the two stale specs** → main-only | blocks 3, 4 | Remove retired-branch assumptions before building on them |
| 3 | **Version-stamp + toolchain unify** (K3) | needs 2; **blocks 4** | Version SoT + `/D` injection + CI guard + shared toolchain pin |
| 4 | **Decoupled-installers + uninstaller parity** (K5) | needs 2, 3 | Five standalone installers built from `main`; fold config-removal parity into the four non-dotnet installers (near-free — their `[Code]` is already being rewritten for self-registration) |
| P2 | *(deferred)* dependency-update bot | after 4 | Recurring surface; phase 2 |

## Refresh deltas (item 2 — what is stale)

- **version-stamp-automation spec:** drop "ghidrust `.iss` on branch `ghidrust`", "`build-ghidrust.yml` is NOT on
  main", and "classic `.iss` on branch `clavity-classic`" → all `.iss` + `build-*.yml` are co-located on `main`.
  The migration/rollout section simplifies: there is no cross-branch non-atomic window to worry about (the
  original atomic-commit hazard assumed workflow-on-main / iss-on-branch, which is no longer the case), though the
  `(a) placeholder + (b) workflow flip` still ship in one commit per tool for cleanliness.
- **decoupled-installers spec:** C4 resolve-ref "`classic@clavity-classic`, `ghidrust@ghidrust`" → all `@main`,
  path-scoped. Open items **O4** (agy-autotrain/commonmemory branch-vs-main) and **O5** (dotnet branch-vs-main)
  resolve to **main** for every tool — single-tree removes the question.

## Phase-2 seams (recorded now to preempt rework)

- **The serial umbrella tag stays orthogonal to per-tool semvers.** K1's `clavity-v<N>` is a serial release-*train*
  marker cut by `umbrella-release.yml`; it does NOT encode any tool's version. K3's per-tool semvers live in each
  tool's in-tree SoT and surface only in artifact filenames. They compose and do not conflict (standard
  release-train mechanics). When phase 2 adds auto-bump (`release-please` or equivalent), it MUST own only the
  in-tree SoT version bumps (via PRs) and MUST NOT be wired to own or replace the `clavity-v<N>` train tag. If a
  future tool insists on per-path release tags, those are ADDITIVE (`<tool>-v<x.y.z>`) alongside the serial train
  tag — never a forced global-version unification. (Defuses the only phase-2 landmine surfaced in AGY-AFTER review:
  there is no requirement to unify the five decoupled versions or abandon the umbrella tag; cascade `e350f145`.)

## Acceptance

- Each sub-project (1, 3, 4) runs its own spec→plan→execute cycle; this governing spec is their index.
- **Item 1:** `just test` and `just build` from the repo root exercise every tool via delegation; per-tool
  justfiles exist for all three compiled tools; a root `lefthook.yml` runs each tool's `just lint` on pre-push
  (verified by an intentionally-malformed push being rejected locally before reaching CI).
- **Item 3:** classic + ghidrust both build under the single pinned Rust toolchain with CI green; a
  `workflow_dispatch` build per tool produces `…-setup-<real-semver>.exe` (not `0.0.0-dev`), proving `/D`
  injection end-to-end.
- **Item 4:** the release palette is one `clavity-v<N>` page carrying the standalone installers, each
  self-contained (installs only its own binary + plugin) and each removing its configuration on uninstall.

## Out of scope

- Renovate/Dependabot dependency-update bot (phase 2).
- Merging the two Cargo workspaces into a single root workspace.
- Signing the installers (still unsigned).
- `release-please` / commit-history-driven auto-bump (a later version-stamp phase 2).

## Open items

None at the governing level — the three genuine forks (deps scope, dev-tools git-hooks, dev-tools sequence
position) were decided with the user on 2026-07-09 (AGY-FIRST consult, cascade `e350f145`). Item-level open
questions (e.g. decoupled-installers O1/O3, version-stamp O1/O2/O3) live in each sub-project's own spec and are
resolved in that sub-project's plan.
