# Monorepo Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `clavity` from a tool-per-branch repo into a monorepo where every product (`clavity-dotnet/`, `clavity-classic/`, `ghidrust/`, `agy-autotrain/`, `commonmemory/`) is a top-level, self-contained folder on one `main`.

**Architecture:** Freeze the two divergent branches as pushed archival tags, then move/vendor every product into its own folder on a `monorepo-consolidation` branch. The .NET flagship moves from the repo root into `clavity-dotnet/`; the two Rust tools become two independent Cargo workspaces (each with its own `rust-toolchain.toml`, no root `Cargo.toml`); the five plugins lift out of `plugins/` into their product folders. CI is rewired from `resolve-ref`/`@branch` cross-branch reusable-workflow calls to local-path (`./…`) calls that build every tool from its subfolder on `main`. No history rewrite (archival tags carry pre-move `git blame`).

**Tech Stack:** .NET 10 (`dotnet` CLI, Inno Setup ISCC), Rust (two pinned toolchains: classic `1.96.0`, ghidrust `stable`/`1.82`; `cargo`, `just`, `cargo-nextest`), GitHub Actions (reusable workflows), Claude Code plugin marketplace (`.claude-plugin/marketplace.json`).

**Review status:** AGY-AFTER team-panel R1–R6 — **GREEN** (R6 full panel, no live challenge). 11 findings folded across R1–R5 (incl. 1 FATAL: installed-vs-repo marketplace-source desync → build-generated flat manifest; 1 where agy's remedy was inverted: exclude classic from the flat manifest, don't bundle it into the dotnet installer). 6 rejected by measurement (exec-bit loss, .slnx depth drift, + the 4 spec-level rejections). Against the GREEN spec `4ba7247`.

---

## Reference: verified pre-migration state (checked 2026-07-09 against the repo — do NOT re-derive)

**Branches:** `main` (aggregator: .NET root + all 5 `plugins/` + all orchestration workflows), `clavity-classic` (Rust; 241 ahead of fork), `ghidrust` (Rust `crates/` + a STALE full copy of main). No branch protection on any branch; 0 open PRs.

**`main` root top-level entries:** `.antigravityignore .claude-plugin .claude .clavity .gitattributes .github .gitignore BundleCodeBase.ps1 CLAUDE.md CONTRIBUTING.md GitHub_Actions_Storage_Reset.ps1 LICENSE README-CLAVITY.md README.md ROADMAP.md clavity.slnx docs install installer plugins src templates tests`

**`main` .NET-owned paths (move into `clavity-dotnet/`):** `src/` (`Clavity.Cli Clavity.Ls.Proto Clavity.Ls Clavity.Mcp`), `tests/`, `clavity.slnx`, `installer/` (only `clavity-dotnet.iss`), `install/`, `templates/`, `BundleCodeBase.ps1`, `README-CLAVITY.md`, `ROADMAP.md`. (Root `LICENSE` = **PolyForm Noncommercial 1.0.0**.)

**`main` `plugins/` (5 dirs):** `agy-autotrain clavity-classic clavity-dotnet commonmemory ghidrust`. Root `.claude-plugin/marketplace.json` lists only **4** (agy-autotrain, clavity-dotnet, commonmemory, ghidrust) — `clavity-classic` plugin dir exists (v0.1.0) but is NOT in the manifest.

**`clavity-classic` branch root:** `.antigravityignore .github .gitignore CLAUDE.md CONTRIBUTING.md Cargo.lock Cargo.toml LICENSE README.md ROADMAP.md agy-mcp-bridge agy_skills docs installer lefthook.yml rust-toolchain.toml scripts src tests`. Toolchain **1.96.0**, LICENSE **MIT**. `installer/` = `clavity-classic.iss` + 2 manual-setup `.md`. Build recipe: `scripts/build-classic-release.ps1` → `publish/clavity.exe`; version triangulated across `Cargo.toml` == `installer/clavity-classic.iss` == `agy-mcp-bridge/pyproject.toml`.

**`ghidrust` branch root:** `.antigravityignore .claude-plugin .claude .clavity .gitattributes .github .gitignore BundleCodeBase.ps1 CLAUDE.md CONTRIBUTING.md Cargo.lock Cargo.toml LICENSE README-CLAVITY.md README.md ROADMAP.md crates deny.toml docs install installer justfile plugins rustfmt.toml rust-toolchain.toml skill src templates tests`. Toolchain **stable/1.82**, LICENSE **PolyForm-NC**. **ghidrust-OWNED paths (vendor ONLY these):** `crates/`, `Cargo.toml`, `Cargo.lock`, `deny.toml`, `justfile`, `rustfmt.toml`, `rust-toolchain.toml`, `skill/`, `installer/ghidrust.iss`, `.gitattributes` (if ghidrust-specific). **STALE .NET duplicate on the ghidrust branch (do NOT vendor):** `src/` (= `Clavity.Cli …`), `tests/`, `clavity.slnx`, `install/`, `templates/`, `plugins/`, `.claude-plugin/`, `installer/clavity-dotnet.iss`, `README-CLAVITY.md`, `BundleCodeBase.ps1`. The ghidrust branch's `plugins/ghidrust/.claude-plugin/plugin.json` is **empty** → **canonical ghidrust plugin = `main:plugins/ghidrust/` (v0.1.0)**.

**Workflows on `main` `.github/workflows/`:** `build-dotnet.yml` (reusable; `dotnet publish src/Clavity.Cli`, ISCC `installer/clavity-dotnet.iss`), `ci.yml` (classic Rust CI; triggers only on `push/PR branches: [clavity-classic]` — dormant on main), `e2e-ghidrust.yml` (reusable live gate; `clang -g crates/ghidrust-mcp/tests/fixtures/fixture.c` at **line 84**, `analyzeHeadless.bat` at line 89, `clang --version` at line 81), `release-ghidrust.yml` (dispatch escape-hatch; `resolve-ref` job lines 25–37 + `uses: …/build-ghidrust.yml@ghidrust` line 44), `umbrella-release.yml` (see below).

**`umbrella-release.yml` (main) exact citations:** `resolve-classic` job lines 34–50; `dotnet: uses: ./.github/workflows/build-dotnet.yml` line 53 (already local-path); `classic: uses: ckir/clavity/.github/workflows/build-classic.yml@clavity-classic` line 59; `resolve-ghidrust` job lines 63–75; `ghidrust: uses: ckir/clavity/.github/workflows/build-ghidrust.yml@ghidrust` line 80; `e2e-ghidrust: uses: ./.github/workflows/e2e-ghidrust.yml` line 89 (already local-path); `publish.needs` line 95; notes table `main@sha` / `clavity-classic@sha` / `ghidrust@sha` lines 137–139.

**Branch-only build workflows (re-author on main):** `clavity-classic:.github/workflows/build-classic.yml`, `ghidrust:.github/workflows/build-ghidrust.yml` (both SHA-pin-checkout the tool branch and build from branch-ROOT-relative paths).

**`installer/clavity-dotnet.iss` (main) exact citations:** `LicenseFile=..\LICENSE` line 22; `Source:` directives lines 38–46 — line 38 `..\publish\{#ExeName}`, line 39 `..\.claude-plugin\marketplace.json`, line 40 `..\plugins\clavity-dotnet\*`, line 42 `..\plugins\agy-autotrain\*`, line 43 `..\plugins\commonmemory\*`, line 46 `..\plugins\ghidrust\*`; `OutputDir=..\dist` line 28. NO `ReadmeFile`/`InfoBefore` directive.

**`.gitignore` (main) — ANCHORED rules:** `/target`, `/dist`, `/clavity.txt` (leading-slash → root-only; will NOT ignore `<tool>/target`).

**`CLAUDE.md` (main) root commands:** `cargo test --all --features test-fakes`; `.NET … dotnet build / dotnet test tests/Clavity.Ls.Tests`.

---

## File Structure — final tree

```
main/
  clavity-dotnet/
    src/{Clavity.Cli,Clavity.Ls,Clavity.Ls.Proto,Clavity.Mcp}/   (moved from root src/)
    tests/                                                        (moved from root tests/)
    installer/clavity-dotnet.iss                                 (moved; Source:/LicenseFile rewritten)
    install/  templates/  clavity.slnx  BundleCodeBase.ps1        (moved from root)
    plugin/.claude-plugin/plugin.json + skills/…                 (moved from plugins/clavity-dotnet/)
    LICENSE  (PolyForm-NC)   README.md  CLAUDE.md  ROADMAP.md     (detailed .NET docs)
    .gitignore                                                    (folder-scoped ignore rules)
  clavity-classic/
    src/ Cargo.toml Cargo.lock rust-toolchain.toml (1.96.0)       (vendored from clavity-classic branch)
    agy-mcp-bridge/ agy_skills/ scripts/ tests/ installer/ docs/  (vendored)
    lefthook.yml  LICENSE (MIT)  README.md  CLAUDE.md             (vendored)
    plugin/.claude-plugin/plugin.json + skills/…                 (moved from plugins/clavity-classic/)
    .gitignore                                                    (vendored classic .gitignore)
  ghidrust/
    crates/ Cargo.toml Cargo.lock rust-toolchain.toml (1.82)      (vendored SELECTIVELY from ghidrust branch)
    justfile deny.toml rustfmt.toml skill/ installer/ghidrust.iss (vendored)
    LICENSE (PolyForm-NC)  README.md  CLAUDE.md                   (ghidrust-specific docs)
    plugin/.claude-plugin/plugin.json + …                        (moved from main:plugins/ghidrust/ — canonical)
    .gitignore                                                    (folder-scoped)
  agy-autotrain/       (folder IS the plugin — moved from plugins/agy-autotrain/)
  commonmemory/        (folder IS the plugin — moved from plugins/commonmemory/)
  .github/workflows/   umbrella-release.yml + build-dotnet/classic/ghidrust.yml + e2e-ghidrust.yml
                       + release-ghidrust.yml + per-tool path-filtered CI
  .claude-plugin/marketplace.json   (5 entries, sources repointed to folders)
  docs/  CLAUDE.md  LICENSE (PolyForm-NC)  README.md   (umbrella-level)
```

---

## Task 0: Create the branch and push archival tags (safety net FIRST)

**Files:** none (git operations only).

- [ ] **Step 1: Confirm clean starting state**

Run:
```bash
git status --porcelain --untracked-files=no
git rev-parse --abbrev-ref HEAD
```
Expected: empty output (clean tree); current branch `main`. If not clean, STOP and report `STATE_MISMATCH: working tree dirty`.

- [ ] **Step 2: Create the migration branch off main**

Run:
```bash
git checkout -b monorepo-consolidation
```
Expected: `Switched to a new branch 'monorepo-consolidation'`.

- [ ] **Step 3: Freeze the two divergent branches as archival tags AND PUSH THEM (this precedes any branch delete — a local tag alone does not protect commits from server GC)**

Run:
```bash
git tag archive/clavity-classic clavity-classic
git tag archive/ghidrust ghidrust
git push origin archive/clavity-classic archive/ghidrust
```
Expected: two `* [new tag]` lines confirming both tags reached `origin`.

- [ ] **Step 4: Verify the tags are on the remote (the safety net is real before we touch anything)**

Run:
```bash
git ls-remote --tags origin | grep -E 'archive/(clavity-classic|ghidrust)$'
```
Expected: two lines, one per archival tag. If either is missing, STOP — do NOT proceed to any file move.

- [ ] **Step 5: Commit marker (empty commit to anchor the branch point)**

No commit needed yet — Task 0 is git-metadata only. Proceed to Task 1.

---

## Task 1: Move the .NET flagship into `clavity-dotnet/`

**Files:**
- Move: `src/`, `tests/`, `clavity.slnx`, `installer/clavity-dotnet.iss`, `install/`, `templates/`, `BundleCodeBase.ps1` → `clavity-dotnet/…`
- Create: `clavity-dotnet/LICENSE`, `clavity-dotnet/.gitignore`
- Modify: `clavity-dotnet/installer/clavity-dotnet.iss` (Source:/LicenseFile/OutputDir paths)

- [ ] **Step 1: Step-0 state verification**

Run:
```bash
git ls-tree --name-only HEAD | tr '\n' ' '
git ls-tree --name-only HEAD:src
```
Expected: top-level list includes `src installer tests clavity.slnx`; `src` contains `Clavity.Cli Clavity.Ls Clavity.Ls.Proto Clavity.Mcp`. If `src` is absent or its children differ, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Create the folder and move the .NET code + solution with `git mv`**

Run:
```bash
mkdir -p clavity-dotnet/installer
git mv src clavity-dotnet/src
git mv tests clavity-dotnet/tests
git mv clavity.slnx clavity-dotnet/clavity.slnx
git mv install clavity-dotnet/install
git mv templates clavity-dotnet/templates
git mv BundleCodeBase.ps1 clavity-dotnet/BundleCodeBase.ps1
git mv README-CLAVITY.md clavity-dotnet/README.md   # the .NET-detailed readme becomes the folder's README
git mv ROADMAP.md clavity-dotnet/ROADMAP.md          # .NET roadmap → folder
git mv installer/clavity-dotnet.iss clavity-dotnet/installer/clavity-dotnet.iss
```
Expected: no errors. (`installer/` on main holds ONLY `clavity-dotnet.iss`, so it is now empty — git drops empty dirs automatically.) NOTE: root `README.md` + `CLAUDE.md` STAY at the root — they are rewritten as the umbrella surface in Task 8 (do NOT move them here). `clavity-dotnet/README.md` (from `README-CLAVITY.md`) is the moved .NET detail Task 8 edits.

- [ ] **Step 3: Give the folder its own LICENSE (PolyForm-NC, matching what .NET currently inherits from root)**

Run:
```bash
cp LICENSE clavity-dotnet/LICENSE
git add clavity-dotnet/LICENSE
```
Expected: staged. (Root `LICENSE` stays too — it becomes the umbrella license in Task 8.)

- [ ] **Step 4: Add a folder-scoped `.gitignore` so build outputs re-anchor at the new depth**

Create `clavity-dotnet/.gitignore`:
```gitignore
# .NET build output (re-anchored at clavity-dotnet/ depth)
/publish
/dist
[Bb]in/
[Oo]bj/
artifacts/
*.user
TestResults/
# build-generated flat install manifest (Task 5/Step 2b) — never committed
/installer/marketplace.install.json
```
Run: `git add clavity-dotnet/.gitignore`

- [ ] **Step 5: In THIS commit, edit ONLY the `.iss` LicenseFile + OutputDir (the plugin `[Files]` Source rewrite is DEFERRED to Task 2 for bisectability)**

**Bisectability (SEAT-3 fold):** the `[Files]` plugin `Source:` lines point at sibling folders (`..\plugin\*`, `..\..\agy-autotrain\*`, …) that do NOT exist until Task 2 moves the plugins. Rewriting them in THIS commit would make ISCC fail ("Source file does not exist") at the Task-1 commit, breaking `git bisect`. So Task 1 edits ONLY the two directives that are already valid at this commit (LicenseFile → folder-local `LICENSE` created in Step 3; OutputDir unchanged). The `[Files]` block below is the TARGET spec — it is applied and committed in **Task 2/Step 5b**, the SAME commit that creates the plugin dirs (per the spec's same-commit reference-update rule).

The `.iss` now sits at `clavity-dotnet/installer/`. Apply these exact edits to `clavity-dotnet/installer/clavity-dotnet.iss`:

Line 22 — LicenseFile must resolve to the FOLDER's license, not the repo root:
```
LicenseFile=..\LICENSE
```
Stays `..\LICENSE` textually, but now resolves to `clavity-dotnet/LICENSE` (created in Step 3) — verify in Step 6.

Line 28 — OutputDir: **leave as `..\dist`** (do NOT change). It was repo-root `dist/` when `installer/` was at root; now that `installer/` sits at `clavity-dotnet/installer/`, `..\dist` resolves to the **folder-local** `clavity-dotnet/dist`. All three tools' `.iss` files use `..\dist` (verified: classic:24, ghidrust:23, dotnet:28), so keeping them uniform means each writes to its own `<tool>/dist` and CI uploads with a workspace-relative `<tool>/dist/...` glob (Task 5). Do NOT rewrite this to `..\..\dist`.
```
OutputDir=..\dist
```

Lines 38–46 — `[Files]` Source directives. `..\publish` stays one level up from `installer/` (= `clavity-dotnet/publish`); the four plugin sources repoint to the scattered folders. **The bundled `marketplace.json` is NOT the repo-root one** — see the CRITICAL note below:
```
Source: "..\publish\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity-dotnet"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\agy-autotrain\*"; DestDir: "{app}\plugins\agy-autotrain"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\commonmemory\*"; DestDir: "{app}\plugins\commonmemory"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\ghidrust\plugin\*"; DestDir: "{app}\plugins\ghidrust"; Flags: ignoreversion recursesubdirs createallsubdirs
```
Note: `..\publish` stays `..\publish` because `build-dotnet.yml` publishes into `clavity-dotnet/publish` (Task 5). The clavity-dotnet plugin becomes `..\plugin\*` (sibling `plugin/` folder, populated in Task 2); agy-autotrain/commonmemory/ghidrust become `..\..\<folder>` (Task 2).

**CRITICAL — the installed marketplace.json must carry FLAT `./plugins/<name>` sources, NOT the repo's nested tree paths.** Verified (`.iss` lines 8–10): clavity-ls resolves `marketplaceRoot = {app}` and each plugin at `{app}\plugins\<name>`, so the installed manifest's `source` fields MUST be `./plugins/<name>` (flat), matching the `DestDir: {app}\plugins\<name>` layout above. But Task 2 rewrites the REPO-ROOT `.claude-plugin/marketplace.json` to NESTED sources (`./clavity-dotnet/plugin`, `./agy-autotrain`, …) for repo-local discovery. Bundling that nested-path file into `{app}` would make the loader look for `{app}\clavity-dotnet\plugin` — which does not exist — and ALL plugins fail to load at runtime. So the installer bundles a **build-generated FLAT manifest** (`marketplace.install.json`), derived from the repo-root manifest by rewriting every `source` to `./plugins/<name>` (see Task 5/Step 2b). **SHAPE-DIVERGENCE STOP:** the `DestDir: {app}\plugins\<name>` layout AND the flat `./plugins/<name>` source form are the installed-tree contract clavity-ls resolves against — neither may change; if the generated manifest cannot produce flat sources, STOP and report.

- [ ] **Step 6: Verify the LicenseFile now resolves folder-local and no root plugin bleed**

Run:
```bash
test -f clavity-dotnet/LICENSE && head -1 clavity-dotnet/LICENSE
grep -n 'LicenseFile' clavity-dotnet/installer/clavity-dotnet.iss
```
Expected: `# PolyForm Noncommercial License 1.0.0`; `LicenseFile=..\LICENSE` present (resolves to `clavity-dotnet/LICENSE`).

- [ ] **Step 7: Commit (self-consistent — this commit does NOT yet fix marketplace.json sources; those move in Task 2 with the plugins, so main is intentionally mid-migration on this branch only)**

Run:
```bash
git add -A
git commit -m "refactor(monorepo): move .NET flagship into clavity-dotnet/

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Lift the 5 plugins into their product folders + repoint marketplace.json

**Files:**
- Move: `plugins/clavity-dotnet/` → `clavity-dotnet/plugin/`; `plugins/clavity-classic/` → `clavity-classic/plugin/`; `plugins/ghidrust/` → `ghidrust/plugin/`; `plugins/agy-autotrain/` → `agy-autotrain/`; `plugins/commonmemory/` → `commonmemory/`
- Modify: `.claude-plugin/marketplace.json` (repoint 4 sources + add clavity-classic 5th entry = 5 total)

- [ ] **Step 1: Step-0 state verification**

Run:
```bash
git ls-tree --name-only HEAD:plugins
```
Expected: `agy-autotrain clavity-classic clavity-dotnet commonmemory ghidrust`. If the set differs, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Move the three tool plugins into `<tool>/plugin/`**

Run:
```bash
mkdir -p clavity-dotnet clavity-classic ghidrust
git mv plugins/clavity-dotnet clavity-dotnet/plugin
git mv plugins/clavity-classic clavity-classic/plugin
git mv plugins/ghidrust ghidrust/plugin
```
Expected: no errors. (`clavity-classic/` and `ghidrust/` are placeholder dirs here; the CODE gets vendored in Tasks 3–4. The plugin arrives first, which is fine — the folder just accrues content.)

- [ ] **Step 3: Move the two plugin-only products to top-level (folder IS the plugin)**

Run:
```bash
git mv plugins/agy-autotrain agy-autotrain
git mv plugins/commonmemory commonmemory
```
Expected: no errors. `plugins/` is now empty and git drops it.

- [ ] **Step 4: Verify plugin.json is present at each new location**

Run:
```bash
for p in clavity-dotnet/plugin clavity-classic/plugin ghidrust/plugin agy-autotrain commonmemory; do
  test -f "$p/.claude-plugin/plugin.json" && echo "OK $p" || echo "MISSING $p"
done
```
Expected: five `OK` lines. If `ghidrust/plugin/.claude-plugin/plugin.json` is MISSING, STOP — the canonical ghidrust plugin is main's copy (v0.1.0) and must have moved.

- [ ] **Step 5: Repoint marketplace.json sources and add the missing clavity-classic entry (5 total)**

Replace the entire `plugins` array in `.claude-plugin/marketplace.json` so each `source` targets the new folder path, and add the previously-absent `clavity-classic` entry:
```json
  "plugins": [
    {
      "name": "agy-autotrain",
      "source": "./agy-autotrain",
      "description": "Drive the agy peer like a model and auto-train clavity's agy knowledge from everyday usage (capture -> curate -> verify -> golden-header)."
    },
    {
      "name": "clavity-dotnet",
      "source": "./clavity-dotnet/plugin",
      "description": "Pair Claude with a live agy peer via the clavity-ls Language-Server bridge (agy_look / agy_status / agy_ask)."
    },
    {
      "name": "clavity-classic",
      "source": "./clavity-classic/plugin",
      "description": "clavity-classic: Claude drives a live agy peer via a psmux doorbell + the agentmemory bus."
    },
    {
      "name": "commonmemory",
      "source": "./commonmemory",
      "description": "Optional add-on: a shared notebook so Claude and agy share facts across the pairing."
    },
    {
      "name": "ghidrust",
      "source": "./ghidrust/plugin",
      "description": "Drive a persistent headless Ghidra JVM from your agent: 19 reverse-engineering tools (decompile, navigate, durable rename/type/prototype writes) over MCP."
    }
  ]
```
(The `clavity-classic` description is copied verbatim from `clavity-classic/plugin/.claude-plugin/plugin.json`.)

- [ ] **Step 5b: Apply the deferred `clavity-dotnet.iss` `[Files]` plugin-Source rewrite (SAME commit as the plugin move — SEAT-3 bisectability)**

Now that the plugin dirs exist at their sibling locations, apply the `[Files]` block deferred from Task 1/Step 5 to `clavity-dotnet/installer/clavity-dotnet.iss` (lines 38–46):
```
Source: "..\publish\{#ExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "marketplace.install.json"; DestDir: "{app}\.claude-plugin"; DestName: "marketplace.json"; Flags: ignoreversion
Source: "..\plugin\*"; DestDir: "{app}\plugins\clavity-dotnet"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\agy-autotrain\*"; DestDir: "{app}\plugins\agy-autotrain"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\commonmemory\*"; DestDir: "{app}\plugins\commonmemory"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\ghidrust\plugin\*"; DestDir: "{app}\plugins\ghidrust"; Flags: ignoreversion recursesubdirs createallsubdirs
```
This lands in the SAME commit (Step 6) that moved the plugins, so every `Source:` path resolves at this commit (bisectable). Verify `..\plugin`, `..\..\agy-autotrain`, `..\..\commonmemory`, `..\..\ghidrust\plugin` all now exist relative to `clavity-dotnet/installer/`.

- [ ] **Step 6: Verify every marketplace source resolves on disk (the C4 drift guard, run manually now — uses `jq`, on the portable toolchain PATH)**

Run:
```bash
missing=0
for s in $(jq -r '.plugins[].source' .claude-plugin/marketplace.json); do
  [ -d "$s" ] || { echo "MISSING $s"; missing=1; }
done
[ "$missing" -eq 0 ] && echo "all 5 sources resolve"
```
Expected: `all 5 sources resolve` (no `MISSING` lines).

- [ ] **Step 7: Commit**

Run:
```bash
git add -A
git commit -m "refactor(monorepo): lift plugins into product folders + repoint marketplace.json (5 entries)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Vendor the `clavity-classic` tree into `clavity-classic/`

**Files:**
- Create (vendored from `clavity-classic` branch, EXCLUDING `.github/`): `clavity-classic/{src,agy-mcp-bridge,agy_skills,scripts,tests,installer,docs,Cargo.toml,Cargo.lock,rust-toolchain.toml,lefthook.yml,LICENSE,README.md,CLAUDE.md,CONTRIBUTING.md,ROADMAP.md,.gitignore,.antigravityignore}`

- [ ] **Step 1: Step-0 verification — the archival tag is the source of truth**

Run:
```bash
git ls-tree --name-only archive/clavity-classic | tr '\n' ' '
```
Expected: matches the documented clavity-classic root (`Cargo.toml Cargo.lock rust-toolchain.toml agy-mcp-bridge agy_skills scripts src tests installer docs lefthook.yml LICENSE …`). If it differs, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Extract the branch tree into the folder via `git archive` (no history — freeze+move)**

Run (git-bash):
```bash
git archive archive/clavity-classic | tar -x -C clavity-classic/
```
Expected: no errors. `clavity-classic/` now contains the full classic tree (including its `.github/` and `plugin/` from Task 2 — both handled next).

- [ ] **Step 3: Remove the vendored `.github/` (GitHub reads operational files ONLY from repo-root `.github/`) and the placeholder collision**

Run:
```bash
rm -rf clavity-classic/.github
```
Expected: no errors. (The still-needed `build-classic.yml` is re-authored at repo root in Task 5; ISSUE/PR templates already exist at root.)

- [ ] **Step 4: Confirm the classic `.gitignore` re-anchored the Rust build outputs**

The archive brought classic's own `.gitignore` (`/target`, `/publish`, `/dist`). Verify it landed and now anchors at `clavity-classic/` depth:
```bash
head -20 clavity-classic/.gitignore
```
Expected: contains `/target`, `/publish`, `/dist` (these now ignore `clavity-classic/target` etc.).

- [ ] **Step 5: Lossless-move proof — tree diff between the archival tag and the vendored folder (NON-NEGOTIABLE gate)**

Run (git-bash). The gate is **anchored** — do NOT use `diff --exclude=plugin` (that would mask ANY dir named `plugin` at any depth). Instead assert the ONLY difference is the root-level `plugin/` (added in Task 2 from main):
```bash
TMP=$(mktemp -d)
git archive archive/clavity-classic | tar -x -C "$TMP"
rm -rf "$TMP/.github"                      # we deliberately dropped .github from the vendor (symmetric)
OUT=$(diff -rq "$TMP" clavity-classic)
echo "$OUT"
EXTRA=$(printf '%s\n' "$OUT" | grep -vE '^Only in clavity-classic: plugin$' | grep -vE '^$')
[ -z "$EXTRA" ] && echo "GATE PASS: only root plugin/ differs" || { echo "GATE FAIL — unexpected diff above"; false; }
```
Expected: `GATE PASS: only root plugin/ differs`. Any line other than `Only in clavity-classic: plugin` = a dropped/extra asset → STOP and investigate before continuing.

- [ ] **Step 6: Verify the classic Cargo workspace builds under its pinned toolchain, from inside the folder**

Run (git-bash). Use a **subshell** so a build failure cannot strand the shell inside the subfolder (a trailing `&& cd ..` would be skipped on failure):
```bash
(cd clavity-classic && cargo build --release)
```
Expected: `Finished release [optimized]`. `rustup` picks `1.96.0` from `clavity-classic/rust-toolchain.toml` because the CWD is the folder. If it resolves a different toolchain, STOP — the `working-directory` contract (C4) is violated.

- [ ] **Step 7: Commit**

Run:
```bash
git add -A
git commit -m "refactor(monorepo): vendor clavity-classic tree into clavity-classic/ (freeze+move, .github excluded)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Vendor the `ghidrust` tree into `ghidrust/` (SELECTIVE — exclude the stale .NET dup)

**Files:**
- Create (vendored SELECTIVELY from `ghidrust` branch): `ghidrust/{crates,Cargo.toml,Cargo.lock,deny.toml,justfile,rustfmt.toml,rust-toolchain.toml,skill,installer/ghidrust.iss,LICENSE,README.md,CLAUDE.md,CONTRIBUTING.md,.gitignore,.antigravityignore}`

- [ ] **Step 1: Step-0 verification — enumerate what the archival tag actually contains**

Run:
```bash
git ls-tree --name-only archive/ghidrust | tr '\n' ' '
git ls-tree --name-only archive/ghidrust:installer
git ls-tree --name-only archive/ghidrust:src
```
Expected: root includes BOTH ghidrust-owned (`crates justfile deny.toml rustfmt.toml Cargo.toml skill`) AND the stale .NET dup (`src clavity.slnx tests plugins .claude-plugin install templates`); `installer/` = `clavity-dotnet.iss ghidrust.iss`; `src/` = `Clavity.Cli Clavity.Ls …` (confirms `src/` is the stale .NET dup, NOT ghidrust code). If `crates/` is absent or `src/` is NOT the .NET projects, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Extract ONLY the ghidrust-owned paths via `git archive` with an explicit pathspec**

Run (git-bash):
```bash
git archive archive/ghidrust \
  crates Cargo.toml Cargo.lock deny.toml justfile rustfmt.toml rust-toolchain.toml \
  skill installer/ghidrust.iss LICENSE README.md CLAUDE.md CONTRIBUTING.md \
  .gitignore .antigravityignore \
  | tar -x -C ghidrust/
```
Expected: no errors. `ghidrust/` now holds the Rust workspace + `installer/ghidrust.iss` (only), plus the `plugin/` from Task 2. The stale `src/`, `clavity.slnx`, `tests/`, `plugins/`, `.claude-plugin/`, `install/`, `templates/`, `installer/clavity-dotnet.iss` are NOT extracted.

**Deliberately-NOT-vendored, classified (not silently dropped):** `.gitattributes` — verified **identical to `main`'s** root `.gitattributes`, so the root copy already covers `ghidrust/`; no folder copy needed. `.claude/` — the ghidrust branch's `.claude/` holds ONLY `recommended-tools.json` (ghidrust-specific: declares `cargo-nextest`, `cargo-deny`, `just`, `lefthook`); a monorepo has ONE root `.claude/recommended-tools.json`, so this is NOT vendored into `ghidrust/.claude/` — its entries are **merged into the root** file in Task 8/Step 4a. `.clavity/` — agent-runtime/seams dir, a stale `main` copy (would collide with root `.clavity/`); dropped.

- [ ] **Step 3: Verify the ghidrust folder has the Rust workspace and NOT the .NET dup**

Run:
```bash
test -d ghidrust/crates && echo "OK crates"
test -f ghidrust/installer/ghidrust.iss && echo "OK ghidrust.iss"
test ! -e ghidrust/clavity.slnx && echo "OK no stale slnx"
test ! -e ghidrust/installer/clavity-dotnet.iss && echo "OK no stale dotnet.iss"
test ! -d ghidrust/src && echo "OK no stale .NET src"
```
Expected: five `OK` lines. Any failure → the pathspec extracted too much/little; STOP.

- [ ] **Step 4: Confirm `.gitignore` re-anchored ghidrust build output**

Run:
```bash
head -5 ghidrust/.gitignore
```
Expected: contains `/target`, `/dist` (now anchored at `ghidrust/` depth).

- [ ] **Step 5: Lossless-move proof for the SELECTIVE vendor (diff the OWNED subset only)**

Run (git-bash). Anchored gate (same as Task 3 — assert the ONLY difference is the root `plugin/`):
```bash
TMP=$(mktemp -d)
git archive archive/ghidrust \
  crates Cargo.toml Cargo.lock deny.toml justfile rustfmt.toml rust-toolchain.toml \
  skill installer/ghidrust.iss LICENSE README.md CLAUDE.md CONTRIBUTING.md \
  .gitignore .antigravityignore | tar -x -C "$TMP"
OUT=$(diff -rq "$TMP" ghidrust)
echo "$OUT"
EXTRA=$(printf '%s\n' "$OUT" | grep -vE '^Only in ghidrust: plugin$' | grep -vE '^$')
[ -z "$EXTRA" ] && echo "GATE PASS: only root plugin/ differs" || { echo "GATE FAIL — unexpected diff above"; false; }
```
Expected: `GATE PASS: only root plugin/ differs`. (The stale .NET dup is out of the pathspec, so it appears on NEITHER side — the "deliberately-deleted" exclusion the spec allows. The pathspec IS the vendor's source of truth, so this diff proves the extract == the pathspec, not that the pathspec == everything ghidrust-owned; Step 1's enumeration is what guards the pathspec's completeness.)

- [ ] **Step 6: Verify the ghidrust workspace builds under its pinned toolchain, from inside the folder**

Run (git-bash; requires `just`, `cargo-nextest` per `.claude/recommended-tools.json`). Subshell (build failure must not strand the shell in the subfolder):
```bash
(cd ghidrust && cargo build --release -p ghidrust-mcp)
```
Expected: `Finished release`. `rustup` picks `stable`/`1.82` from `ghidrust/rust-toolchain.toml` (CWD-scoped). If a different toolchain resolves, STOP.

- [ ] **Step 7: Commit**

Run:
```bash
git add -A
git commit -m "refactor(monorepo): vendor ghidrust Rust workspace into ghidrust/ (selective; stale .NET dup excluded)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Re-author the per-tool build workflows ON `main` (build from subfolders)

**Files:**
- Modify: `.github/workflows/build-dotnet.yml` (add `working-directory: clavity-dotnet` scoping)
- Create: `.github/workflows/build-classic.yml` (from `clavity-classic:…/build-classic.yml`, folder-scoped, checkout-of-main not branch)
- Create: `.github/workflows/build-ghidrust.yml` (from `ghidrust:…/build-ghidrust.yml`, folder-scoped)

- [ ] **Step 1: Step-0 verification**

Run:
```bash
ls .github/workflows/
```
Expected: `build-dotnet.yml ci.yml e2e-ghidrust.yml release-ghidrust.yml umbrella-release.yml` (no build-classic/build-ghidrust yet). If they already exist, STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Folder-scope `build-dotnet.yml` to `clavity-dotnet/`**

Every `pwsh` step in `build-dotnet.yml` uses root-relative paths (`installer/clavity-dotnet.iss`, `src/Clavity.Cli`, `publish/`, `dist/`). Add a job-level default so all `run:` steps execute inside the folder. Insert under `jobs.build:` (after `runs-on`):
```yaml
    defaults:
      run:
        working-directory: clavity-dotnet
```
The `dotnet publish … -o publish` now writes `clavity-dotnet/publish` matching the `.iss` `..\publish` Source; ISCC `OutputDir=..\dist` (unchanged, Task 1) writes to the folder-local `clavity-dotnet/dist`; the `Extract version` step's `installer/clavity-dotnet.iss` path is now correct relative to `clavity-dotnet/`. **Artifact-upload path — do NOT use `working-directory`.** `actions/upload-artifact` is a `uses:` step; `working-directory:` is invalid on `uses:` steps (only valid on `run:`), and its `path:` input is always relative to `GITHUB_WORKSPACE` (repo root) regardless of the job's `defaults.run.working-directory`. So set the upload glob to the workspace-relative folder path:
```yaml
      - uses: actions/upload-artifact@v4
        with:
          name: dotnet-installer   # umbrella-release depends on this exact name — do NOT change
          path: |
            clavity-dotnet/dist/clavity-dotnet-setup-*.exe
            clavity-dotnet/dist/clavity-dotnet-setup-*.exe.sha256
```
**SHAPE-DIVERGENCE STOP:** the artifact name `dotnet-installer` is the wire contract umbrella-release's `publish` job downloads by — it must not change.

- [ ] **Step 2b: Generate the FLAT install manifest before ISCC (fixes the installed-vs-repo marketplace desync — Task 1's CRITICAL note)**

Insert a step in `build-dotnet.yml` AFTER checkout and BEFORE `Build installer (ISCC)`, running from `working-directory: clavity-dotnet`. It derives a flat-source manifest, **excluding `clavity-classic`** (the clavity-dotnet installer must NOT ship the classic plugin — the two are mutually-exclusive variants, and the `.iss` refuses to install over a classic presence), so the generated manifest lists EXACTLY the 4 plugins the `.iss` `[Files]` block lays down (`clavity-dotnet`, `agy-autotrain`, `commonmemory`, `ghidrust`):
```yaml
      - name: Generate flat install manifest (4 bundled plugins; EXCLUDE mutually-exclusive classic)
        shell: pwsh
        run: |
          $root = Get-Content ../.claude-plugin/marketplace.json -Raw | ConvertFrom-Json
          $bundled = $root.plugins | Where-Object { $_.name -ne 'clavity-classic' }
          foreach ($p in $bundled) { $p.source = "./plugins/$($p.name)" }
          $root.plugins = $bundled
          $root | ConvertTo-Json -Depth 10 | Set-Content installer/marketplace.install.json -Encoding utf8
          if ($bundled.Count -ne 4) { throw "expected 4 bundled plugins, got $($bundled.Count)" }
          if (($bundled | Where-Object { $_.source -notmatch '^\./plugins/' }).Count -ne 0) { throw "flat manifest has a non-flat source" }
          Write-Host "generated installer/marketplace.install.json with 4 flat sources (classic excluded)"
```
The `.iss` `Source: "marketplace.install.json"; DestName: "marketplace.json"` (Task 1/Step 5) installs it as `{app}\.claude-plugin\marketplace.json` — its 4 entries match the 4 `DestDir: {app}\plugins\<name>` payloads exactly, so no `./plugins/<name>` source dangles at runtime. (Do NOT instead add a `clavity-classic` Source to the dotnet `.iss` — that would ship the classic plugin from the dotnet installer and break mutual exclusion.) The build-dotnet smoke step's existing assertion `Test-Path "$app\.claude-plugin\marketplace.json"` still passes; ADD an assertion that the installed manifest has 4 entries all with `source` starting `./plugins/`. `marketplace.install.json` is gitignored (Task 1/Step 4) — a build artifact, never committed.

- [ ] **Step 3: Create `build-classic.yml` on main from the branch version, folder-scoped**

Base it on `clavity-classic:.github/workflows/build-classic.yml` (captured below), with two structural changes: (a) drop the SHA-pinned tool-branch checkout — a naked `actions/checkout@v4` on main is correct now the code lives in `clavity-classic/`; (b) add `defaults.run.working-directory: clavity-classic` so `scripts/build-classic-release.ps1`, `Cargo.toml`, `installer/clavity-classic.iss`, `agy-mcp-bridge/pyproject.toml`, `cargo test` all resolve. Keep the `workflow_call` outputs (`version`, `sha`, `artifact-name: classic-installer`) — umbrella-release consumes them. The `ref` input becomes unused; remove it and update the umbrella caller in Task 6. classic's `.iss` `OutputDir=..\dist` (verified line 24, unchanged) now writes to the folder-local `clavity-classic/dist`; the artifact-upload step is a `uses:` step (NO `working-directory`), so set its workspace-relative glob:
```yaml
      - uses: actions/upload-artifact@v4
        with:
          name: classic-installer
          path: |
            clavity-classic/dist/clavity-classic-setup-*.exe
            clavity-classic/dist/clavity-classic-setup-*.exe.sha256
```
The `sha` output uses `git rev-parse HEAD` — now returns the main commit (correct, since the tag points at main).

- [ ] **Step 4: Create `build-ghidrust.yml` on main from the branch version, folder-scoped**

Base it on `ghidrust:.github/workflows/build-ghidrust.yml` (captured below): (a) naked `actions/checkout@v4` (no SHA-pin — code is in `ghidrust/`); (b) `defaults.run.working-directory: ghidrust` so `just lint`, `just test`, `cargo build --release -p ghidrust-mcp`, `installer/ghidrust.iss`, `target/release/ghidrust.exe` resolve; (c) keep `taiki-e/install-action` for `just,cargo-nextest,cargo-deny`. Preserve outputs (`version`, `sha`, `artifact-name: ghidrust-installer`). ghidrust's `.iss` `OutputDir=..\dist` (verified line 23, unchanged) now writes the folder-local `ghidrust/dist`; the upload is a `uses:` step (NO `working-directory`) with a workspace-relative glob:
```yaml
      - uses: actions/upload-artifact@v4
        with:
          name: ghidrust-installer
          path: |
            ghidrust/dist/ghidrust-setup-*.exe
            ghidrust/dist/ghidrust-setup-*.exe.sha256
```
Remove the now-unused `ref` input (update the two callers — umbrella + release-ghidrust — in Task 6).

- [ ] **Step 5: Add per-workspace Rust cache scoping (C4 — default root-lockfile hashing yields permanent cache misses)**

In `build-classic.yml`, if it uses `Swatinem/rust-cache`, set `with: { workspaces: "clavity-classic" }`. In `build-ghidrust.yml`, set `with: { workspaces: "ghidrust" }`. (The branch `build-classic.yml` uses `dtolnay/rust-toolchain` without an explicit cache action; if none is present, add `Swatinem/rust-cache@v2` with the `workspaces:` scope for CI speed.)

- [ ] **Step 6: Lint all three workflows**

Run (git-bash — validate YAML parses with `yq`, which is on the portable toolchain PATH; do NOT use `python -c "import yaml"` — PyYAML is a third-party module, not stdlib, and would `ModuleNotFoundError`):
```bash
for f in build-dotnet build-classic build-ghidrust; do
  yq '.' ".github/workflows/$f.yml" > /dev/null && echo "OK $f" || echo "BAD $f"
done
```
Expected: three `OK` lines. If any prints `BAD`, fix the YAML before committing.

- [ ] **Step 7: Commit**

Run:
```bash
git add -A
git commit -m "ci(monorepo): re-author build-classic/build-ghidrust on main + folder-scope build-dotnet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Rewire `umbrella-release.yml` + `release-ghidrust.yml` + `e2e-ghidrust.yml` (drop resolve-ref, local-path callers, folder-scope shells)

**Files:**
- Modify: `.github/workflows/umbrella-release.yml` (delete resolve-classic 34–50 + resolve-ghidrust 63–75; rewrite callers 59, 80 to local-path; fix notes table 137–139)
- Modify: `.github/workflows/release-ghidrust.yml` (delete resolve-ref 25–37; local-path caller 44; drop `ref` input)
- Modify: `.github/workflows/e2e-ghidrust.yml` (folder-scope the clang/analyzeHeadless step; drop SHA-pin checkout)

- [ ] **Step 1: Step-0 verification of the exact citations**

Run:
```bash
grep -n 'resolve-classic\|resolve-ghidrust\|build-classic.yml@\|build-ghidrust.yml@\|working-directory' .github/workflows/umbrella-release.yml
grep -n 'resolve-ref\|build-ghidrust.yml@' .github/workflows/release-ghidrust.yml
grep -n 'crates/ghidrust-mcp/tests/fixtures/fixture.c' .github/workflows/e2e-ghidrust.yml
```
Expected: umbrella shows `resolve-classic` (34), `resolve-ghidrust` (63), `@clavity-classic` (59), `@ghidrust` (80); release-ghidrust shows `resolve-ref` (25) + `@ghidrust` (44); e2e shows the fixture path at line 84. If line numbers drifted (e.g. an earlier task edited these), re-locate by string, not line, and note the drift.

- [ ] **Step 2: `umbrella-release.yml` — delete both `resolve-*` jobs and rewrite the two `@branch` callers to local-path**

Delete the `resolve-classic:` job (lines 34–50) and the `resolve-ghidrust:` job (lines 63–75). Rewrite the `classic` job (was lines 55–61):
```yaml
  classic:
    uses: ./.github/workflows/build-classic.yml
```
Rewrite the `ghidrust` job (was lines 77–82):
```yaml
  ghidrust:
    uses: ./.github/workflows/build-ghidrust.yml
```
Update the `e2e-ghidrust` job (was 84–91): it no longer needs `resolve-ghidrust`; it needs only `ghidrust`, and passes no `ref` (checkout is main):
```yaml
  e2e-ghidrust:
    needs: [ghidrust]
    uses: ./.github/workflows/e2e-ghidrust.yml
```
Remove the now-dangling `with: { ref: … }` blocks and `needs: resolve-*` from `classic`/`ghidrust`/`e2e-ghidrust`. Also delete the `classic_ref` dispatch input (lines 18–22) — there is no branch to pin anymore. **SHAPE-DIVERGENCE STOP:** `e2e-ghidrust.yml` still declares a REQUIRED `ref` input; either make it optional (Step 4) or keep passing a value. Reconcile in Step 4 before committing.

- [ ] **Step 3: `umbrella-release.yml` — fix the release-notes source table (lines 137–139) to all-main**

All three tools now build from `main`, so the `source` column is uniform:
```
          | clavity-dotnet  | ${{ needs.dotnet.outputs.version }}  | main@${{ needs.dotnet.outputs.sha }} |
          | clavity-classic | ${{ needs.classic.outputs.version }} | main@${{ needs.classic.outputs.sha }} |
          | ghidrust        | ${{ needs.ghidrust.outputs.version }} | main@${{ needs.ghidrust.outputs.sha }} |
```
Leave `publish.needs: [dotnet, classic, ghidrust, e2e-ghidrust]` (line 95) unchanged — still atomic.

- [ ] **Step 4: `e2e-ghidrust.yml` — make `ref` optional + folder-scope every shell step**

Change the `workflow_call` input `ref` to `required: false, default: ''`. Change the checkout to use the caller ref only when provided (blank = main): `ref: ${{ inputs.ref }}` already falls back to the default checkout when blank — verify. Folder-scope the two build steps that use `crates/…` and `$GHIDRA_INSTALL_DIR`: add `working-directory: ghidrust` to the "Build fixture + analyze headless" step (so `clang -g crates/ghidrust-mcp/tests/fixtures/fixture.c` at line 84 resolves as `ghidrust/crates/…`) and to the "Live E2E smoke" step (so `cargo nextest -p ghidrust-mcp` resolves the workspace + picks the pinned toolchain). Leave the Ghidra download/cache steps (which use `$RUNNER_TEMP`) unscoped — they are path-independent.

- [ ] **Step 5: `release-ghidrust.yml` — delete `resolve-ref`, local-path caller, drop `ref`**

Delete the `resolve-ref:` job (lines 25–37). Rewrite `build` (was 39–46):
```yaml
  build:
    uses: ./.github/workflows/build-ghidrust.yml
```
Rewrite `e2e` (was 48–55) to drop `resolve-ref` and the `ref` pass:
```yaml
  e2e:
    needs: [build]
    uses: ./.github/workflows/e2e-ghidrust.yml
```
`publish.needs: [build, e2e]` (line 58) unchanged.

- [ ] **Step 6: Lint the three rewired workflows**

Run:
```bash
for f in umbrella-release release-ghidrust e2e-ghidrust; do
  yq '.' ".github/workflows/$f.yml" > /dev/null && echo "OK $f" || echo "BAD $f"
done
grep -c 'resolve-classic\|resolve-ghidrust\|resolve-ref\|@clavity-classic\|@ghidrust' .github/workflows/umbrella-release.yml .github/workflows/release-ghidrust.yml
```
Expected: three `OK` lines; the grep count is `0` for both files (every branch pin removed).

- [ ] **Step 7: Commit**

Run:
```bash
git add -A
git commit -m "ci(monorepo): drop resolve-ref/branch-pins, local-path reusable callers, folder-scope e2e shells

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Per-tool path-filtered daily CI + shared-surface fan-out guard

**Files:**
- Modify/replace: `.github/workflows/ci.yml` (currently classic-only, triggers on `clavity-classic` branch — repoint to path-filtered classic CI on main)
- Create: `.github/workflows/ci-dotnet.yml`, `.github/workflows/ci-ghidrust.yml` (path-filtered daily push/PR CI)

- [ ] **Step 1: Step-0 verification**

Run:
```bash
grep -n 'branches:\|paths:' .github/workflows/ci.yml
```
Expected: `ci.yml` triggers `push/pull_request branches: [clavity-classic]` (lines 4–7), NO `paths:` filter. If it already has path filters (or is already renamed to `ci-classic.yml`), STOP and report `STATE_MISMATCH`.

- [ ] **Step 2: Rename `ci.yml` → `ci-classic.yml` and convert it into the path-filtered classic CI on `main`**

First rename for symmetry with `ci-dotnet.yml`/`ci-ghidrust.yml` (verified: nothing references `ci.yml` by name, so the rename is safe):
```bash
git mv .github/workflows/ci.yml .github/workflows/ci-classic.yml
```
Then change the trigger from branch-scoped to `main` with a path filter that watches the classic folder PLUS the shared CI surface (the fan-out guard — a shared edit must trigger classic too):
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'clavity-classic/**'
      - '.github/workflows/ci-classic.yml'
      - '.github/workflows/build-classic.yml'
  pull_request:
    paths:
      - 'clavity-classic/**'
      - '.github/workflows/ci-classic.yml'
      - '.github/workflows/build-classic.yml'
```
Add `defaults.run.working-directory: clavity-classic` to each job (`check`, `linux-binary`) so `cargo fmt/clippy/test/build` resolve the folder + pick the `1.96.0` toolchain. The `linux-binary` artifact upload is a `uses:` step (NO `working-directory`), so set its `path:` to the workspace-relative `clavity-classic/target/release/clavity`. Add `Swatinem/rust-cache@v2` `with: { workspaces: "clavity-classic" }`.

- [ ] **Step 3: Create `ci-dotnet.yml` — path-filtered .NET daily CI**

```yaml
name: ci-dotnet
on:
  push:
    branches: [main]
    paths:
      - 'clavity-dotnet/**'
      - '.github/workflows/ci-dotnet.yml'
      - '.github/workflows/build-dotnet.yml'
  pull_request:
    paths:
      - 'clavity-dotnet/**'
      - '.github/workflows/ci-dotnet.yml'
      - '.github/workflows/build-dotnet.yml'
jobs:
  test:
    runs-on: windows-latest
    defaults:
      run:
        working-directory: clavity-dotnet
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with:
          dotnet-version: '10.0.x'
      - run: dotnet build
      - run: dotnet test tests/Clavity.Ls.Tests
```
(Paths mirror the `CLAUDE.md` .NET commands; `tests/Clavity.Ls.Tests` resolves under `clavity-dotnet/`.)

- [ ] **Step 4: Create `ci-ghidrust.yml` — path-filtered ghidrust daily CI (lint+test, NOT the ~5-min Ghidra E2E)**

```yaml
name: ci-ghidrust
on:
  push:
    branches: [main]
    paths:
      - 'ghidrust/**'
      - '.github/workflows/ci-ghidrust.yml'
      - '.github/workflows/build-ghidrust.yml'
      - '.github/workflows/e2e-ghidrust.yml'
  pull_request:
    paths:
      - 'ghidrust/**'
      - '.github/workflows/ci-ghidrust.yml'
      - '.github/workflows/build-ghidrust.yml'
      - '.github/workflows/e2e-ghidrust.yml'
jobs:
  check:
    runs-on: windows-latest
    defaults:
      run:
        working-directory: ghidrust
    steps:
      - uses: actions/checkout@v4
      - uses: taiki-e/install-action@v2
        with:
          tool: just,cargo-nextest,cargo-deny
      - uses: Swatinem/rust-cache@v2
        with:
          workspaces: ghidrust
      - run: just lint
      - run: just test   # live-worker tests self-skip without GHIDRUST_E2E
```

- [ ] **Step 5: Lint the three CI workflows**

Run:
```bash
for f in ci-classic ci-dotnet ci-ghidrust; do
  yq '.' ".github/workflows/$f.yml" > /dev/null && echo "OK $f" || echo "BAD $f"
done
```
Expected: three `OK` lines.

- [ ] **Step 6: Commit**

Run:
```bash
git add -A
git commit -m "ci(monorepo): path-filtered per-tool daily CI + shared-surface fan-out guards

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Licenses, docs sweep, umbrella README/CLAUDE.md, IDE coexistence

**Files:**
- Create: `clavity-classic/LICENSE` (MIT — verify vendored), `ghidrust/LICENSE` (PolyForm — verify vendored), `agy-autotrain/LICENSE` (PolyForm), `commonmemory/LICENSE` (PolyForm)
- Modify: root `CLAUDE.md`, `README.md`, `README-CLAVITY.md`, `ROADMAP.md`, `CONTRIBUTING.md`, `.claude/recommended-tools.json`
- Create: `.vscode/settings.json` (rust-analyzer linkedProjects)
- Audit: every `.iss` `LicenseFile`

- [ ] **Step 1: Verify/create the CORRECT license in EVERY product folder (installer license-file bleed guard — C6; every folder = a product the decoupled-installers plan packages independently, so each must be legally self-contained)**

The two plugin-only products have NO license today (verified: `plugins/agy-autotrain` and `plugins/commonmemory` carry none) — give each the umbrella PolyForm-NC (clavity-owned):
```bash
cp LICENSE agy-autotrain/LICENSE
cp LICENSE commonmemory/LICENSE
git add agy-autotrain/LICENSE commonmemory/LICENSE
```
Then verify all five product folders:
```bash
head -1 clavity-dotnet/LICENSE clavity-classic/LICENSE ghidrust/LICENSE agy-autotrain/LICENSE commonmemory/LICENSE
grep -n 'LicenseFile' clavity-dotnet/installer/clavity-dotnet.iss ghidrust/installer/ghidrust.iss clavity-classic/installer/clavity-classic.iss
```
Expected: `clavity-dotnet/LICENSE` = PolyForm, `clavity-classic/LICENSE` = MIT, `ghidrust/LICENSE` = PolyForm, `agy-autotrain/LICENSE` = PolyForm, `commonmemory/LICENSE` = PolyForm (classic + ghidrust licenses arrived via the Task 3/4 vendors). Each `.iss` `LicenseFile=..\LICENSE` now resolves to its OWN folder's LICENSE. If `clavity-classic/installer/clavity-classic.iss` `LicenseFile` resolves anywhere but `clavity-classic/LICENSE` (MIT), STOP — shipping PolyForm on the MIT tool is a legal misstatement.

- [ ] **Step 2: Author the umbrella root `README.md` + `CLAUDE.md` (palette-level); relocate .NET detail into `clavity-dotnet/`**

The root `README.md`/`README-CLAVITY.md`/`CLAUDE.md` currently describe the .NET flagship. Task 1 already moved `README-CLAVITY.md → clavity-dotnet/README.md` and `ROADMAP.md → clavity-dotnet/ROADMAP.md` (verify they exist). Here: copy the root `CLAUDE.md`'s .NET-specific detail into `clavity-dotnet/CLAUDE.md` (create it), then rewrite the ROOT `README.md` + `CLAUDE.md` (which were NOT moved) as a lightweight umbrella: what the repo is, the 5-product palette table, and per-folder build commands:
```
| Product | Folder | Build |
|---------|--------|-------|
| clavity-dotnet | clavity-dotnet/ | cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests |
| clavity-classic | clavity-classic/ | cd clavity-classic && cargo test --all --features test-fakes |
| ghidrust | ghidrust/ | cd ghidrust && just test |
| agy-autotrain | agy-autotrain/ | (plugin only) |
| commonmemory | commonmemory/ | (plugin only) |
```
Keep the root `CLAUDE.md`'s agy-facing guidance (the `plugins/agy-autotrain/knowledge/agy-assumptions.md` pointer) but repoint it to `agy-autotrain/knowledge/agy-assumptions.md` (new folder path — verify the file moved with the plugin in Task 3/Step-nothing; it lived under `plugins/agy-autotrain/`).

- [ ] **Step 3: Folder-scope every stale root-relative command in the docs (C7)**

Grep for the commands that break once .NET leaves the root, and prepend `cd <tool>/`:
```bash
grep -rn 'dotnet test tests/Clavity.Ls.Tests\|cargo test --all --features test-fakes\|dotnet build' CLAUDE.md README.md README-CLAVITY.md CONTRIBUTING.md ROADMAP.md docs/ 2>/dev/null
```
For each hit in a root/umbrella doc, repoint to `cd clavity-dotnet && dotnet …` or `cd clavity-classic && cargo …`. (Docs that now live INSIDE a tool folder keep folder-relative commands.)

- [ ] **Step 4a: Merge each tool branch's `.claude/recommended-tools.json` into the ROOT (monorepo has ONE root file — the SessionStart hook reads only `<repo>/.claude/recommended-tools.json`)**

The Rust tools declared their own recommended tools on their branches (verified: `ghidrust:.claude/recommended-tools.json` declares `cargo-nextest`, `cargo-deny`, `just`, `lefthook`; the classic branch declares its own — check `clavity-classic:.claude/recommended-tools.json`). Those were dropped by the Tasks 3–4 selective/`.github`-excluding vendors and would otherwise vanish, so a fresh session in the monorepo would not be told to install `just`/`nextest`/`deny`. Merge the UNION of all three branches' entries (dedup by `name`) into the root `.claude/recommended-tools.json`:
```bash
git show ghidrust:.claude/recommended-tools.json
git show clavity-classic:.claude/recommended-tools.json 2>/dev/null || echo "(none on classic)"
git show main:.claude/recommended-tools.json 2>/dev/null || echo "(none on main)"
```
Hand-merge the union into `.claude/recommended-tools.json` (one entry per distinct tool `name`: `cargo`, `cargo-nextest`, `cargo-deny`, `just`, `lefthook`, plus any .NET/dotnet entry). These are declarative presence checks (`in_path`), tool-name-keyed — no folder path to repoint.

- [ ] **Step 4b: Confirm no stale moved-tree path lingers in the merged root file**

Run:
```bash
grep -n 'src/\|plugins/\|tests/\|installer/\|clavity.slnx' .claude/recommended-tools.json 2>/dev/null || echo "no tree-path references"
```
Expected: `no tree-path references` (entries declare tools by name, e.g. `just`, `cargo-nextest`). If any moved tree path appears, repoint it to the new folder.

- [ ] **Step 5: IDE coexistence — rust-analyzer linkedProjects (C3)**

Create/modify `.vscode/settings.json`:
```json
{
  "rust-analyzer.linkedProjects": [
    "clavity-classic/Cargo.toml",
    "ghidrust/Cargo.toml"
  ]
}
```

- [ ] **Step 6: Verify no stale root-relative build path survives in umbrella docs**

Run:
```bash
grep -rn 'dotnet test tests/Clavity.Ls.Tests' CLAUDE.md README.md 2>/dev/null && echo "STALE FOUND — fix" || echo "clean"
```
Expected: `clean` (root docs no longer carry the un-prefixed command).

- [ ] **Step 7: Commit**

Run:
```bash
git add -A
git commit -m "docs(monorepo): umbrella README/CLAUDE.md, folder-scoped commands, per-tool licenses, rust-analyzer linkedProjects

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Full acceptance gate + retire branches

**Files:** none new — verification + git branch retirement.

- [ ] **Step 1: `.gitignore` re-anchoring proof — no build output is now committable**

Run each tool build, then confirm nothing under `<tool>/{target,bin,obj,publish,dist,TestResults}` shows as untracked:
```bash
(cd clavity-dotnet && dotnet build) && (cd clavity-classic && cargo build) && (cd ghidrust && cargo build -p ghidrust-mcp)
git status --porcelain | grep -E '(target|bin|obj|publish|dist|TestResults)/' && echo "LEAK — fix ignore rules" || echo "ignore rules OK"
```
Expected: `ignore rules OK`. If leaks appear, add the missing anchored rule to that folder's `.gitignore` and re-commit under Task 8.

- [ ] **Step 2: Build ALL tools green in their new homes (acceptance)**

Run:
```bash
(cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests)
(cd clavity-classic && cargo test --all --features test-fakes && cargo clippy --all-targets --features test-fakes -- -D warnings)
(cd ghidrust && just lint && just test)
```
Expected: all green under each pinned toolchain. This is the "build ALL tools once, ignoring path filters" proof the spec's risk section mandates.

- [ ] **Step 3: Marketplace source-resolution guard (final)**

Run the Task-2/Step-6 `jq` check again:
```bash
missing=0
for s in $(jq -r '.plugins[].source' .claude-plugin/marketplace.json); do
  [ -d "$s" ] || { echo "MISSING $s"; missing=1; }
done
[ "$missing" -eq 0 ] && echo "all 5 sources resolve"
```
Expected: `all 5 sources resolve`.

- [ ] **Step 4: Archival-tag spot-check (pre-move tool still builds from the tag)**

Run (git-bash — worktree checkout so we don't disturb the branch):
```bash
git worktree add ../clavity-archive-check archive/ghidrust
(cd ../clavity-archive-check && cargo build -p ghidrust-mcp && echo "archive builds")
git worktree remove ../clavity-archive-check
```
Expected: `archive builds`. Confirms the frozen history is checkout-able and buildable.

- [ ] **Step 5: Push the branch and open the consolidation PR (owner-gated — do NOT merge without owner)**

This is a large structural PR. Push and open it for owner review:
```bash
git push -u origin monorepo-consolidation
gh pr create --title "Monorepo consolidation: tool-per-branch -> single-tree" --body "$(cat <<'EOF'
## Summary
- Move .NET flagship into clavity-dotnet/; vendor clavity-classic + ghidrust into their folders (freeze+move, archival tags pushed).
- Two independent Cargo workspaces (classic 1.96.0 / ghidrust stable-1.82); no root Cargo.toml.
- Lift 5 plugins into product folders; marketplace.json repointed (5 entries).
- CI: drop resolve-ref/branch-pins; local-path reusable callers; folder-scoped shells; per-tool path-filtered CI + shared-surface fan-out guards.
- Per-tool licenses; umbrella README/CLAUDE.md; rust-analyzer linkedProjects.

## Test Plan
- [ ] dotnet build + test green in clavity-dotnet/
- [ ] cargo test + clippy green in clavity-classic/ (1.96.0) and ghidrust/ (stable-1.82)
- [ ] Lossless-move diff vs archive/clavity-classic and archive/ghidrust = 0 unexpected differences
- [ ] workflow_dispatch umbrella-release produces all installers + ghidrust E2E gate passes
- [ ] archive/* tags remain checkout-able and build the pre-move tool
- [ ] Branch retirement (clavity-classic, ghidrust) — owner performs AFTER merge

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```
Expected: PR URL printed. **STOP here** — branch retirement (Step 6) and the live `workflow_dispatch` umbrella-release run are owner actions AFTER merge.

- [ ] **Step 6: (OWNER, post-merge) Retire the divergent branches — archival tags preserve them**

After the PR merges to `main`, the owner runs:
```bash
git push origin --delete clavity-classic ghidrust
```
The `archive/clavity-classic` + `archive/ghidrust` tags (pushed in Task 0) keep the history reachable. A `workflow_dispatch` of `umbrella-release` on `main` then proves all installers still build with no branch pins.

---

## Sequencing note

This plan lands the **monorepo tree + CI rewiring** ONLY. The **decoupled-installers** plan (5 standalone installers, removing the interim cross-plugin `.iss` bundling) is authored SEPARATELY against this final tree — its O4 (agy-autotrain/commonmemory placement) and O5 (dotnet on main) forks are already resolved here (all products are folders on `main`). Do not interleave the two.
