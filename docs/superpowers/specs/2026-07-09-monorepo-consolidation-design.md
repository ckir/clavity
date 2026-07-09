# Monorepo Consolidation — Design

**Date:** 2026-07-09
**Status:** design approved (topology + tree + migration mechanics); AGY-AFTER panels R1–R6 — **GREEN** (15 findings folded + verified, 4 rejected by measurement; R6 full design panel landed no live challenge); pending user review → plan
**Supersedes/rewires:** the tool-per-branch topology and the `resolve-ref`/SHA-pin umbrella-release wiring. **Resolves** open forks **O4** and **O5** of the per-plugin-decoupled-installers spec (`2026-07-09-per-plugin-decoupled-installers-design.md`), which gets rebased onto this tree.

## Problem

`clavity` is one GitHub repo with **tool-per-branch**, not a monorepo. The branches share an ancient common ancestor but have diverged into effectively separate codebases (verified 2026-07-09):

- `main` — .NET flagship (`src/`, all 5 `plugins/`, `installer/`, ALL orchestration workflows incl. `umbrella-release.yml`); 241 commits ahead of classic's fork point.
- `clavity-classic` — a completely different tree (Rust; `Cargo.toml`, `agy-mcp-bridge`, `agy_skills`; no `plugins/`, no `.claude-plugin/`); toolchain pinned `1.96.0`, MIT.
- `ghidrust` — Rust `crates/` plus a stale copy of main's `plugins/` + `.claude-plugin/`; only 4 commits ahead of its fork point; toolchain `stable`/`1.82`, PolyForm-Noncommercial.

Releases reach each tool via `resolve-ref` jobs that SHA-pin to a branch and build there. This "polyrepo-glued-into-branches" model causes the three pain points the owner raised: (1) build/release friction from the cross-branch wiring; (2) contributor mental model — you cannot see all code at once, no cross-tool diffs, a checkout swaps whole codebases; (3) cross-tool changes cannot land in one commit/PR. The owner explicitly did **not** value independent release cadence.

## Decision (owner-approved)

Convert to a **monorepo**: every product is a **top-level, self-contained folder** on one `main`. One-to-one — *folder = product = installer on the `clavity-v<N>` release page* (the palette).

A poly-repo split (agy's counter-proposal) was **rejected**: it optimizes toolchain isolation (not an owner driver) while *regressing* the two drivers that matter — atomic cross-tool commits become impossible and "see all code at once" becomes three separate clones. Staying on branches leaves all three pain points unaddressed.

## Final tree

```
main/
  clavity-dotnet/     .NET flagship: src/, installer/, tests/, clavity.slnx + plugin/
  clavity-classic/    Rust — own Cargo workspace (rust-toolchain 1.96.0), MIT + plugin/
  ghidrust/           Rust crates/ — own Cargo workspace (stable/1.82), PolyForm-NC + plugin/
  agy-autotrain/      plugin-only product (the folder IS the plugin)
  commonmemory/       plugin-only product (the folder IS the plugin)
  .github/workflows/  umbrella-release + path-filtered per-folder build/test
  .claude-plugin/marketplace.json   remote discovery → the 5 product folders
  docs/  CLAUDE.md  LICENSE  README.md   (shared root surface)
```

### Intra-folder plugin placement
- **Plugin-only products** (`agy-autotrain`, `commonmemory`): the product folder *is* the plugin — it carries `.claude-plugin/plugin.json` + skills/commands at its own root. First-class, not nested under a generic `plugins/` bucket (owner requirement).
- **Tool products** (`clavity-dotnet`, `clavity-classic`, `ghidrust`): the plugin lives in a `plugin/` subdir beside the code (e.g. `clavity-dotnet/plugin/.claude-plugin/plugin.json`), so the folder holds both the binary source and its plugin.
- The repo-root `.claude-plugin/marketplace.json` stays the FULL 5-entry list for remote discovery (`ckir/clavity` marketplace), with each `source` repointed at the new folder path.

## Components

### C1 — Freeze + move migration (no history rewrite)
1. Freeze the two divergent branch histories as archival tags, **then push them to origin BEFORE any branch is deleted**:
   `git tag archive/clavity-classic clavity-classic && git tag archive/ghidrust ghidrust && git push origin archive/clavity-classic archive/ghidrust`.
   `git blame`/archaeology on pre-move code = check out the archival tag. This is the accepted trade: we keep history reachable, we do **not** rewrite it. **A local tag alone does not protect the commits — once the remote branch is deleted, unreferenced commits are garbage-collected on the server. The pushed tag is the only thing keeping the history alive, so the push MUST precede branch retirement (step 3).**
2. On `main`, in ordered commits:
   - move the current .NET root (`src/`, `installer/`, `tests/`, `clavity.slnx`, .NET-scoped configs) into `clavity-dotnet/`;
   - lift each of the 5 plugins out of `plugins/` into its product folder (tools → `<tool>/plugin/`; plugin-only → top-level `<name>/`);
   - vendor the `clavity-classic` tree into `clavity-classic/` (copy current tree state);
   - vendor the `ghidrust` tree into `ghidrust/` (copy current tree state).
3. Retire the `clavity-classic` and `ghidrust` branches (archival tags preserve them). Delete the stale plugin copy that lived on the `ghidrust` branch — the canonical plugin now lives once, in `ghidrust/plugin/`.

**Commit self-consistency (every commit leaves `main` buildable).** The ordered commits are per-tool for reviewability, but each one must be *internally consistent* — a commit that moves a tool's files also updates, in the SAME commit, every reference that points at the old location (that tool's `marketplace.json` `source` path, its `build-*.yml`, its `.iss` paths). Never split "move the files" and "fix the references" across two commits, or the intermediate state is structurally broken (breaks `git bisect` and any CI on that commit). This reconciles the two constraints: many small commits (reviewable) each of which is self-consistent (bisectable). Squashing to one giant commit is NOT required and is rejected — it would make the consolidation PR unreviewable (R1 finding).

**Ignore-rule re-anchoring (verified hazard).** The root `.gitignore` uses **anchored** rules (`/target`, `/dist`) — verified. `/target` ignores only `./target`, NOT `clavity-classic/target` or `ghidrust/target`, so after the move the Rust build outputs become untracked and committable. Each branch shipped its own `.gitignore`; vendor it into the tool's subfolder so its rules re-anchor at the new depth, and/or de-anchor the root rules. Confirm post-move that `target/`, `bin/`, `obj/`, `dist/`, `publish/`, `TestResults/` under every tool folder are ignored.

**`.github/` does NOT vendor into subfolders (verified).** All three branches carry `.github/ISSUE_TEMPLATE/`, `pull_request_template.md`, and workflows; GitHub reads these operational files **only** from the repo-root `.github/`. Vendoring a tool tree verbatim would bury them in `clavity-classic/.github/` etc. where GitHub silently ignores them. So the move MUST **exclude** each tool's `.github/` from the subfolder vendor: hoist the still-needed build workflow (`build-classic.yml`, `build-ghidrust.yml`) to root `.github/workflows/` (per C4), and drop the rest — the ISSUE/PR templates already exist at root, and the `ghidrust` branch's stale duplicate `build-dotnet.yml`/`ci.yml`/`umbrella-release.yml` are discarded. (No `dependabot.yml`/`CODEOWNERS` exist on any branch — verified — so none to merge; the principle is templates + workflows.)

**Rejected alternative:** `git filter-repo --to-subdirectory-filter` per branch to preserve `git blame` across the move. Higher effort/risk (SHA rewrite, fiddly merges) for archaeology the owner does not need; agy concurred it was a "nightmare."

### C2 — Two independent Cargo workspaces (do NOT merge)
The two Rust tools have independent build settings (verified): classic is toolchain-pinned `1.96.0` / MIT / single-package; ghidrust is a 3-crate workspace / PolyForm-Noncommercial, vendored at migration time on `stable` (+ `rust-version 1.82` MSRV) and **hard-pinned to `1.96.0` in a post-migration follow-on** so both Rust tools now share the same toolchain. Even with matching toolchains the decision stands: a single root workspace would force one **license** and one **`Cargo.lock`/crate-graph** across both (MIT vs PolyForm-NC; single-package vs 3-crate) — wrong. Keep **two** workspaces, each rooted in its folder with its own `rust-toolchain.toml` + `Cargo.lock`. This is what makes the monorepo safe; it is NOT a reason to avoid the monorepo.

### C3 — IDE / toolchain coexistence
- `.vscode/settings.json`: `rust-analyzer.linkedProjects = ["clavity-classic/Cargo.toml", "ghidrust/Cargo.toml"]` so both Rust workspaces resolve without thrash.
- The .NET solution (`clavity-dotnet/clavity.slnx`) is scoped to its folder.
- Contributors get one clone with everything visible; per-language tooling is folder-scoped.

### C4 — CI rewiring
- **Re-author the per-tool build workflows ON `main` (they currently live on the branches).** Verified: only `build-dotnet.yml` is on `main`; `umbrella-release.yml` calls `build-classic.yml@clavity-classic` and the ghidrust build `@ghidrust`, and `release-ghidrust.yml` + `umbrella-release.yml` carry `resolve-ref`/SHA-pin jobs. When the branches retire, all of that breaks. Migration MUST: (a) create `build-classic.yml` + `build-ghidrust.yml` on `main` that build from `clavity-classic/` + `ghidrust/`; (b) rewire `release-ghidrust.yml` to target the subfolder on `main` (or retire it — see P3); (c) delete every `resolve-ref` job and rewrite the `@clavity-classic`/`@ghidrust` callers in `umbrella-release.yml` to **local-path** reusable-workflow syntax (`uses: ./.github/workflows/build-classic.yml`), NOT `@main`. Verified: the file already mixes styles — dotnet (line 53) + e2e (line 89) use tag-immutable `./…`, while classic (59) + ghidrust (80) use `@<branch>`. Local-path resolves the reusable workflow at the SAME commit the `clavity-v<N>` tag points to (release reproducibility); `@main` would run main's tip regardless of the tag. Converge all four on the local-path style.
- `umbrella-release.yml`: **drop** every `resolve-ref`/SHA-pin job. Build each tool from its subfolder on `main`. ghidrust keeps its **BLOCKING** live-E2E gate (boots real Ghidra 12.1.2 + JDK21 + 2-test smoke). `publish` needs all build+gate jobs → one atomic `clavity-v<N>` release with all installers + a per-product notes table.
- **Release builds are UNCONDITIONAL — no path filter on the release path.** `paths:` filters apply only to `push`/`pull_request` triggers, NOT to `workflow_call` or `workflow_dispatch` (correcting the panel's stated mechanism: a reusable build called by the release does not *inherit* a caller's path filter). Regardless, encode the release build jobs so they run for every tool on a `clavity-v<N>` tag, so `publish` never waits on an artifact a self-skipped job never produced.
- Per-tool **path-filtered** build/test workflows (the DAILY `push`/PR CI, separate from the release path): `paths: ['clavity-dotnet/**']`, `['clavity-classic/**']`, `['ghidrust/**']`, etc. — so a .NET patch does not fire ghidrust's ~5-min Ghidra E2E, and vice-versa.
- **Shared-surface guard:** a change to a shared root path (`.github/workflows/**`, root configs, cross-cutting `docs/**`) must trigger **all** tool builds, not silently skip them. Encode this as an explicit `paths` entry on every per-tool workflow (each tool watches its own folder **plus** the shared CI paths), so shared edits fan out. This is the known path-filter footgun agy flagged — closed by construction, not by memory.
- **Folder-scope EVERY shell step in a moved workflow, not just `cargo`.** Verified: `e2e-ghidrust.yml` has a raw pwsh step `clang -g crates/ghidrust-mcp/tests/fixtures/fixture.c …` (line 84) — a non-cargo step with a root-relative path. After the move that path is `ghidrust/crates/…`, so a `working-directory` fix applied only to `cargo` steps would leave the `clang`/`analyzeHeadless` steps crashing with "file not found." Apply `working-directory: ghidrust` (or path-correct the reference) to **every** shell step of each relocated workflow.
- **CI Rust cache keys must target the subfolder lockfiles.** `Swatinem/rust-cache` / `actions/cache` default to hashing a **root** `Cargo.lock` to key the cache. With no root `Cargo.toml`/`Cargo.lock` (P2) and each `Cargo.lock` under its tool folder, the default key resolves to nothing → silent permanent cache misses → slow CI. The re-authored on-main Rust workflows MUST set the cache scope explicitly per workspace (e.g. `Swatinem/rust-cache` `workspaces: "ghidrust"` / `"clavity-classic"`), not rely on root-lockfile hashing.
- **Two Rust workspaces → two separate invocations that `cd` into the folder** (`working-directory: clavity-classic` / `working-directory: ghidrust`), NOT `cargo --manifest-path ../<folder>/Cargo.toml` from the root. Verified hazard: `rustup` resolves `rust-toolchain.toml` from the **current working directory**, not from the manifest path — building via `--manifest-path` from root would silently use the default toolchain instead of the folder's pinned one (classic `1.96.0`, ghidrust `stable`/`1.82`), defeating the whole two-workspace isolation. `cargo build`/`test`/`clippy` each run inside the tool folder.

### C5 — Marketplace + installer wiring
- Root `.claude-plugin/marketplace.json` `source` fields repoint from `./plugins/<name>` to the new folder locations.
- The decoupled-installers spec is **rebased** onto this tree: each installer stages its plugin from the new folder path; the umbrella build no longer resolves branches. That spec's O4 (agy-autotrain/commonmemory placement) and O5 (dotnet on main vs branch) are **resolved here** — all products are folders on `main`.
- **Interim flagship-installer `Source:` rewrite (verified — sequencing consequence).** Because monorepo lands BEFORE decoupled-installers, `clavity-dotnet.iss` still bundles all 5 plugins in the interim. Verified today it pulls `..\.claude-plugin\marketplace.json` + `..\plugins\{clavity-dotnet,agy-autotrain,commonmemory,ghidrust}\*` (lines 39–46). After the move the `.iss` sits at `clavity-dotnet/installer/` and those plugins scatter to `../../agy-autotrain/`, `../../commonmemory/`, `../../ghidrust/plugin/`, `../plugin/` — every `..\plugins\*` path is wrong and ISCC will fail "File not found" on the first monorepo umbrella release. The move MUST rewrite every `Source:` directive in `clavity-dotnet.iss` to the scattered new paths (interim behavior preserved); the later decoupled-installers step then removes the cross-plugin bundling entirely.
- **version-stamp-automation cross-spec reconciliation (verified conflict).** That spec's CI hardcodes plugin.json extraction paths under the OLD topology, e.g. `build-dotnet.yml: jq -r .version plugins/clavity-dotnet/.claude-plugin/plugin.json` (line 64) and its whole table uses `plugins/<name>/…`. The monorepo move relocates each plugin to `<tool>/plugin/.claude-plugin/plugin.json` (or top-level for the two plugin-only products), so every such `jq` path must be updated in lockstep with the move — otherwise the version-stamp guard extracts `null` and loudly fails the release. Whichever spec lands relative to the move, the extraction paths MUST track the final topology; the migration commit that moves a plugin also updates that plugin's version-extraction path.

### C6 — Licenses (and installer license-file bleed)
Root `LICENSE` (verified = **PolyForm Noncommercial 1.0.0**) + umbrella `NOTICE` stay. Each product folder keeps its own `LICENSE` — `clavity-classic/LICENSE` (**MIT**, verified), `ghidrust/LICENSE` (PolyForm-NC), `clavity-dotnet/LICENSE` (PolyForm-NC, matching today's root that it currently inherits) — so per-tool licensing is unambiguous after the move.

**Installer license-file bleed (BLOCKING audit).** Verified: `installer/clavity-dotnet.iss` uses `LicenseFile=..\LICENSE`, i.e. relative to the `.iss` file's dir. Today that resolves to the repo-root PolyForm license. After the move, an `.iss` at `<tool>/installer/…` with `..\LICENSE` resolves one level up — which must land on the **folder-scoped** `LICENSE`, not the repo root. If any `.iss` `LicenseFile` (or a bundled `Source:` LICENSE) still resolves to the root, the MIT `clavity-classic` installer would ship and display the restrictive **PolyForm** license — a legal misstatement. Migration MUST audit every `.iss` `LicenseFile`/`Source:*LICENSE*` directive to resolve to its own folder's `LICENSE`, and verify each tool folder contains the correct license file before the first release build.

## C7 — Docs / onboarding path audit
Root-relative commands and paths in onboarding docs go stale the moment the .NET code leaves the root, silently breaking a new contributor's (or new agent's) first build. Verified: root `CLAUDE.md` carries `cargo test --all --features test-fakes` and `.NET … dotnet build / dotnet test tests/Clavity.Ls.Tests` as root commands. Migration MUST audit and folder-scope every such reference: `CLAUDE.md` (root + any per-tool), `README.md`, `README-CLAVITY.md`, `ROADMAP.md`, `CONTRIBUTING.md`, session-notes, and `.claude/recommended-tools.json` — prepend `cd <tool>/` (e.g. `cd clavity-dotnet && dotnet test …`) or repoint file paths to the new folders.

**Root docs become umbrella-level; tool-specific detail moves into the tool folder.** The root `README.md`/`README-CLAVITY.md`/`CLAUDE.md` today describe the .NET flagship. After the move, author a lightweight **umbrella** `README.md`/`CLAUDE.md` at the root (what the repo is, the palette of tools, how to build each) and relocate the detailed .NET-specific content into `clavity-dotnet/`. (Checked: `clavity-dotnet.iss` has **no** `ReadmeFile`/`InfoBefore` directive, so leaving/moving the README does not crash ISCC — the concern is documentation authority, not an installer dependency.)

**Considered and REJECTED — "agent decapitation" (measured false).** A panel seat argued the driving agent loads its tools from the repo tree (`./plugins/clavity-dotnet`), so the move would strip the agent's capabilities mid-session. Measurement refutes it: `git grep` across `.claude/` + `.clavity/` for `plugins/clavity-*`, `./src/`, `clavity.slnx`, `manifest-path` returns **zero** hits, and the active agent's MCP tools come from the *installed* `clavity-ls` (`%LOCALAPPDATA%\Programs\clavity-dotnet`), not the working tree. The migration also happens on a branch. So no decapitation risk. (`.claude/recommended-tools.json` is still audited under the docs sweep above, out of caution — but it references tool binaries, not moved tree paths.)

## Sequencing

1. **Monorepo consolidation (this spec) FIRST** — land the tree + CI rewiring; verify a dispatch umbrella release still produces all installers.
2. **Then** the decoupled-installers plan, authored against the final tree (no branch pins, no O4/O5 forks).

Doing both simultaneously is a scope trap (agy's one valid sequencing point, adapted): the tree move and the 5-installer rewrite must not interleave.

## Error handling / risks

- **A build path is missed after the move** → the per-tool workflow's `paths` filter silently skips → `main` goes green while a tool is actually broken. Mitigation: the C4 shared-surface guard + a one-time "build ALL tools" run on the consolidation merge commit (ignore path filters once) to prove every tool still builds in its new home.
- **marketplace.json `source` drift** → a plugin fails to resolve remotely. Mitigation: a CI check that every `source` path in the root manifest exists on disk.
- **ghidrust stale-plugin divergence** → the copy on the `ghidrust` branch and the copy under main's `plugins/` may differ; pick the canonical one deliberately during the move and delete the other (do not blind-merge).

## Testing / acceptance

- **Lossless-move proof (non-negotiable acceptance gate).** "It builds" does NOT prove the freeze+move dropped no non-compiled assets (test fixtures, shell scripts, localized docs). For each vendored tool, a programmatic tree diff between the archival tag and the new subfolder must yield zero *unexpected* differences: e.g. `git diff --stat archive/ghidrust -- . ':(exclude).git'` compared against `ghidrust/`, or `diff -rq <checkout of archive/ghidrust> ghidrust/` excluding `.git` and the deliberately-deleted stale plugin dir. Same for `clavity-classic`. This runs before the branches are retired.
- Post-migration, on `main`: `dotnet build` + `dotnet test` green in `clavity-dotnet/`; `cargo test` + `clippy -D warnings` green in **each** Rust workspace under its pinned toolchain.
- A `workflow_dispatch` `umbrella-release` produces all installers named at their real versions and the ghidrust E2E gate passes.
- Each `archive/*` tag remains checkout-able and builds the pre-move tool (spot-check one).
- rust-analyzer resolves both workspaces in one open editor (no root-context thrash).

## Out of scope (now)

- The decoupled-installers implementation itself (separate spec/plan; rebased onto this tree).
- Signing installers (still unsigned).
- Any change to how installers register plugins into agents (unchanged behavior; only source paths move).
- Deep `git blame` preservation across the move (accepted trade — archival tags instead).

## Open items (→ plan)

- **P1** — exact intra-folder layout for tool plugins: `<tool>/plugin/` vs `<tool>/.claude-plugin/` at the tool-folder root (lean: `<tool>/plugin/` to keep code and plugin visually separated).
- **P2** — whether the two Rust workspaces also get a thin root `Cargo.toml` `[workspace] exclude`-list to stop `cargo` at root from trying to unify them (lean: no root Cargo.toml; rely on folder-scoped invocations).
- **P3** — retire vs keep the per-branch legacy build workflows that currently live on `clavity-classic`/`ghidrust` branches (they vanish when branches are retired, but confirm nothing on `main` references them).
