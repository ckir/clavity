# ghidrust Umbrella Onboarding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package the frozen **ghidrust-mcp v1.0.0** binary as a first-class clavity umbrella tool (branch + installer + build/release workflows + marketplace plugin), delivering it two-channel with its own `ghidrust-v<N>` release lineage — **no new ghidrust code**.

**Architecture:** Two-channel delivery (installer = `ghidrust.exe`→PATH only, on branch `ghidrust`; plugin skill + `.mcp.json` via the marketplace on `main`), which dissolves the D7 cross-branch bundling problem. Everything is template instantiation + config; the only "logic" is Inno-Setup Pascal for an optional Ghidra-dir prompt and a non-blocking prereq check.

**Tech Stack:** Rust (cargo, just, cargo-nextest, cargo-deny), Inno Setup 6 (ISCC), GitHub Actions (reusable workflows), Claude Code plugin/marketplace JSON.

**Design source of truth:** `docs/superpowers/specs/2026-07-09-ghidrust-onboarding-design.md` (GREEN after 4 AGY-AFTER panel rounds). Generic mechanics: `docs/hosting-a-tool.md`. Templates: `templates/tool-skeleton/*.template`.

**Token-efficiency contract:** Model tiers marked per task (`[Haiku]`/`[Sonnet]`/`[owner]`). Verification is cheap (JSON/YAML parse, gated local ISCC, `diff`) — no live Ghidra except the explicitly owner-run acceptance task. Paste template fills verbatim; do not re-derive.

**Branch discipline (READ FIRST):** This plan spans **two branches**. Tasks 0–2 are on branch **`ghidrust`**; Tasks 3–6 are on **`main`**; Tasks 7–8 are owner-run at release. Each task states its branch in **Files**. The umbrella already has 8 unpushed commits on local `main` (owner holds push) — **do not push** unless the task says so and the owner has approved.

**Version = `1.0.0`, stamped in 3 files across 2 branches** (bump all in lockstep next release; no auto guard):
`installer/ghidrust.iss` (branch) + `plugins/ghidrust/plugin.json` + `plugins/ghidrust/.claude-plugin/plugin.json` (main).

---

## Task 0: Create branch `ghidrust` + import the v1.0.0 source  `[owner/Sonnet]`

**Files:**
- Branch: create `ghidrust` off `main`.
- Import from: `C:\Users\user\Development\Rust\ghidra-mcp` (the frozen v1.0.0 tree).

**Step 0 — State verification.** Confirm the source repo is at v1.0.0 and green before importing:
- [ ] Run in `C:\Users\user\Development\Rust\ghidra-mcp`: `git rev-parse --abbrev-ref HEAD` (expect `main`), `git status` (expect clean), and confirm the workspace `Cargo.toml` version is `1.0.0`. If any differ, STOP and report `STATE_MISMATCH: <what>`.

**Step 1 — Create the branch (in the clavity repo).**
- [ ] `git -C C:/Users/user/Development/Rust/clavity checkout -b ghidrust`

**Step 2 — Import a clean snapshot of the shippable crate.** Copy from the ghidra-mcp tree into the clavity worktree root: `Cargo.toml`, `Cargo.lock`, `crates/`, `skill/`, `worker/` (if a top-level dir; else it lives under the crate — verify), `justfile`, `deny.toml`, `rust-toolchain.toml`, `.claude/recommended-tools.json`. **Exclude** `target/`, `.git/`, `docs/superpowers/`, `.clavity/`, `CHANGELOG.md`, `ROADMAP.md`, `HANDOFF.md`, `README.md` (the umbrella owns docs; the tool's dev history stays in the origin repo).
- [ ] Copy the included paths (PowerShell `Copy-Item -Recurse` or `robocopy`, honoring the exclude list). Then confirm the crate builds from the new location:
- [ ] Run: `cargo build --release -p ghidrust-mcp` → expect `target/release/ghidrust.exe` produced. If the `worker/` path or `skill/` `include_str!` fails to resolve, STOP and report — the relative crate↔`skill/`↔`worker/` layout must travel intact.

**Step 3 — Commit.**
- [ ] `git add -A && git commit -m "feat(ghidrust): import ghidrust-mcp v1.0.0 source onto branch"`

> **Note:** `templates/tool-skeleton/` and the specs/plans live on `main` and are inherited by this branch (it was cut from `main`), so Tasks 1–2 can read them here.

---

## Task 1: `installer/ghidrust.iss`  `[Sonnet]`  (branch `ghidrust`)

**Files:**
- Create: `installer/ghidrust.iss` (from `templates/tool-skeleton/installer.iss.template`).

**Step 0 — State verification.** Open `templates/tool-skeleton/installer.iss.template` and confirm it contains `#define ExeName "<BINARY>"`, `Source: "..\publish\{#ExeName}"`, and a `[Code]` block with `NeedsAddPath`/`RemoveFromUserPath`/`CurUninstallStepChanged`. If the shape differs, STOP and report `STATE_MISMATCH`.

**Step 1 — Instantiate the template with these exact substitutions.** Copy the template to `installer/ghidrust.iss` and apply:
- `<TOOL-ID>` → `ghidrust` (every occurrence: `AppName`, `DefaultDirName`, `OutputBaseFilename`, `[Tasks]` description).
- `#define AppVersion "<VERSION>"` → `#define AppVersion "1.0.0"`.
- `#define ExeName "<BINARY>"` → `#define ExeName "ghidrust.exe"` (**with `.exe`** — this feeds `Source: "..\publish\{#ExeName}"`, a literal staged filename).
- `AppId={{REPLACE-WITH-A-FRESH-GUID}` → generate a fresh GUID (PowerShell `[guid]::NewGuid()`), e.g. `AppId={{A1B2C3D4-...}` (keep the leading `{{`). **Never reuse another tool's GUID.**

**Step 2 — Add the header comment (replace the D7 template note).** The template's lines 4–5 mention the D7 open question. Replace them with:
```
; Two-channel delivery (see docs/superpowers/specs/2026-07-09-ghidrust-onboarding-design.md): this installer
; ships ONLY the binary. The plugin (skill + .mcp.json) is delivered via the marketplace on main — the
; installer never stages plugins/, so there is no cross-branch bundling.
```

**Step 3 — Add an optional Ghidra-dir page + non-blocking prereq check + env-var set.** Extend the `[Code]` block (keep the existing functions). Add at the top of `[Code]`:
```pascal
var
  GhidraPage: TInputDirWizardPage;

procedure InitializeWizard;
var
  Existing: string;
begin
  GhidraPage := CreateInputDirPage(wpSelectTasks,
    'Ghidra install location (optional)',
    'ghidrust needs Ghidra 12.1.2 and a JDK 21 at run time.',
    'Point to your Ghidra install root (the folder containing support\analyzeHeadless.bat). ' +
    'Leave blank to skip — you can set GHIDRA_INSTALL_DIR yourself later.',
    False, '');
  GhidraPage.Add('');
  Existing := GetEnv('GHIDRA_INSTALL_DIR');
  if Existing <> '' then
    GhidraPage.Values[0] := Existing;
end;
```
And add a post-install handler (the template already has `CurUninstallStepChanged`; add `CurStepChanged`):
```pascal
procedure CurStepChanged(CurStep: TSetupStep);
var
  Dir: string;
begin
  if CurStep = ssPostInstall then
  begin
    Dir := Trim(GhidraPage.Values[0]);
    if Dir <> '' then
    begin
      RegWriteExpandStringValue(HKCU, 'Environment', 'GHIDRA_INSTALL_DIR', Dir);
      if not FileExists(Dir + '\support\analyzeHeadless.bat') then
        MsgBox('Warning: support\analyzeHeadless.bat was not found under the Ghidra folder you gave. ' +
               'Install Ghidra 12.1.2 before using ghidrust. (Install continues.)', mbInformation, MB_OK);
    end;
  end;
end;
```
> Uninstall is unchanged: it removes ONLY the PATH entry (existing `RemoveFromUserPath`). It deliberately does **not** delete `GHIDRA_INSTALL_DIR` (shared user config) or `%USERPROFILE%\.ghidrust` (user data). Do not add such removal.

**Step 4 — Local verification (gated on ISCC).**
- [ ] If Inno Setup is installed, dry-run compile (**PowerShell**): create a throwaway `publish/ghidrust.exe` (empty file) so `[Files]` resolves, then
  ```powershell
  $iscc = "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe"
  if (Test-Path $iscc) { & $iscc installer/ghidrust.iss } else { "ISCC not local — CI covers it" }
  ```
  Expect exit 0 and `dist/ghidrust-setup-1.0.0.exe`. Delete the throwaway `publish/ghidrust.exe` + `dist/` output after. If ISCC is absent, skip (CI covers it).

**Step 5 — Commit.**
- [ ] `git add installer/ghidrust.iss && git commit -m "feat(ghidrust): Inno installer (binary→PATH, optional Ghidra-dir prompt, non-blocking prereq check)"`

---

## Task 2: `.github/workflows/build-ghidrust.yml`  `[Sonnet]`  (branch `ghidrust`)

**Files:**
- Create: `.github/workflows/build-ghidrust.yml` (from `templates/tool-skeleton/build-tool.yml.template`).

**Step 0 — State verification.** Open `templates/tool-skeleton/build-tool.yml.template` and confirm it has: `workflow_call` with `outputs.version/sha/artifact-name`; a SHA-pinned `actions/checkout@v4` using `${{ inputs.ref }}`; a `FILL(per-tool): install the tool's build toolchain` comment; an `Extract version from .iss` step reading `installer/<TOOL-ID>.iss`; a `FILL(per-tool): build the binary into publish/<BINARY>` comment; an `OPEN QUESTION (D7 ...)` comment about staging `plugins/<TOOL-ID>/`; and Inno-install + ISCC + sha256 + upload steps. If the shape differs, STOP and report `STATE_MISMATCH`.

**Step 1 — Instantiate.** Copy the template to `.github/workflows/build-ghidrust.yml`; replace every `<TOOL-ID>` → `ghidrust` and `<BINARY>` → `ghidrust.exe` (in the `publish/<BINARY>` FILL comment only; the ISCC/sha256 steps already use `<TOOL-ID>-setup-*`).

**Step 2 — Fill the toolchain-install step** (replace the `# FILL(per-tool): install the tool's build toolchain` comment). `windows-latest` ships `rustup`/`cargo`; `rust-toolchain.toml` auto-installs the pinned toolchain. Add `just`, `cargo-nextest`, `cargo-deny` via **prebuilt binaries** (NOT `cargo install`, which compiles them from source — ~15–20 min on a Windows runner):
```yaml
      - name: Install build tools (just, nextest, cargo-deny)
        uses: taiki-e/install-action@v2
        with:
          tool: just,cargo-nextest,cargo-deny
```

**Step 3 — Fill the build + gate step** (replace the `# FILL(per-tool): build the binary into publish/<BINARY>` comment). Build, run the CI-safe gate (live tests self-skip without `GHIDRUST_E2E`), then stage the binary:
```yaml
      - name: Lint gate
        shell: bash
        run: just lint

      - name: Test gate (live-worker tests self-skip without GHIDRUST_E2E)
        shell: bash
        run: just test

      - name: Build release binary
        shell: bash
        run: cargo build --release -p ghidrust-mcp

      - name: Stage binary into publish/
        shell: bash
        run: |
          mkdir -p publish
          cp target/release/ghidrust.exe publish/ghidrust.exe
```

**Step 4 — Resolve the D7 OPEN QUESTION comment.** DELETE the template's `# OPEN QUESTION (D7 ...)` comment block (the 3 lines about staging `plugins/<TOOL-ID>/`) and replace with a one-line resolution:
```yaml
      # Two-channel delivery: the installer ships ONLY the binary; the plugin is marketplace-delivered on
      # main. No plugins/ staging here — D7 cross-branch bundling does not apply (see the onboarding spec).
```

**Step 5 — Verification.**
- [ ] YAML parses: `yq '.jobs.build.steps | length' .github/workflows/build-ghidrust.yml` → a number ≥ 8; `yq '.on.workflow_call.outputs' ...` non-null. Confirm no literal `<TOOL-ID>` / `<BINARY>` remains: `grep -n '<TOOL-ID>\|<BINARY>' .github/workflows/build-ghidrust.yml` → no matches.

**Step 6 — Commit.**
- [ ] `git add .github/workflows/build-ghidrust.yml && git commit -m "ci(ghidrust): reusable build+package workflow (rust gate self-skips live tests; two-channel, no plugin staging)"`

> **After Task 2:** the branch `ghidrust` is complete. `git checkout main` for Tasks 3–6.

---

## Task 3: `plugins/ghidrust/`  `[Sonnet]`  (branch `main`)

**Files (all under `plugins/ghidrust/`):**
- Create: `plugin.json`, `.claude-plugin/plugin.json`, `.mcp.json`, `skills/ghidra-re-driver/SKILL.md`, `README.md`.

**Step 0 — State verification.** Confirm the layout to mirror: `ls plugins/clavity-dotnet/` shows both `plugin.json` and `.claude-plugin/plugin.json` and a `.mcp.json`. If not, STOP and report `STATE_MISMATCH`.

**Step 1 — Both plugin manifests (identical content).** Write the SAME JSON to `plugins/ghidrust/plugin.json` AND `plugins/ghidrust/.claude-plugin/plugin.json`:
```json
{
  "name": "ghidrust",
  "version": "1.0.0",
  "description": "Drive a persistent headless Ghidra JVM from your agent: 19 reverse-engineering tools (decompile, navigate, and durable rename/comment/set-datatype/set-prototype/set-local writes) over MCP."
}
```

**Step 2 — Bundled env-driven `.mcp.json`.** Write `plugins/ghidrust/.mcp.json` (no hardcoded paths; bare PATH `command`):
```json
{
  "mcpServers": {
    "ghidrust": { "command": "ghidrust", "args": ["serve"] }
  }
}
```

**Step 3 — Skill file, emitted from the branch binary (NOT generated on `main`).** The `ghidrust` crate is not on `main`, so obtain `SKILL.md` from the branch build (Task 0 built `target/release/ghidrust.exe` on branch `ghidrust`). **Run these in Git Bash** (the `mkdir -p`/`mv`/forward-slash exe path all work there; do NOT run in PowerShell). You are on `main` at the start of Task 3 — switch to the branch FIRST:
- [ ] `git checkout ghidrust`
- [ ] `./target/release/ghidrust.exe skill --emit > ghidra-re-driver.SKILL.md.tmp`   (untracked repo-root file; if `target/` was cleaned, re-run `cargo build --release -p ghidrust-mcp` first)
- [ ] `git checkout main`   (the untracked `.tmp` survives the switch)
- [ ] `mkdir -p plugins/ghidrust/skills/ghidra-re-driver && mv ghidra-re-driver.SKILL.md.tmp plugins/ghidrust/skills/ghidra-re-driver/SKILL.md`
- [ ] Sanity: `grep -c 'name: ghidra-re-driver' plugins/ghidrust/skills/ghidra-re-driver/SKILL.md` → 1; file size > 8 KB.

**Step 4 — `README.md`** (from `templates/tool-skeleton/README.md.template`, all `<…>` filled). Write `plugins/ghidrust/README.md`:
````markdown
# ghidrust

Drive a persistent headless Ghidra JVM from your AI agent — 19 reverse-engineering tools over MCP.

## Install
Ships in the `clavity` umbrella. Install the binary via the `ghidrust-v<N>` GitHub Release installer
(`ghidrust-setup-<VERSION>.exe`), and add the plugin from this repo's marketplace.

**Runtime prerequisites (you must install these yourself):**
- **Ghidra 12.1.2** — set `GHIDRA_INSTALL_DIR` to its root (the installer offers to set it).
- **JDK 21** — Ghidra 12.1.2 requires `application.java.min=21`.
- A Ghidra **project you have already created and fully analyzed in the Ghidra GUI, then CLOSED**
  (v1.0 ATTACHES to an analyzed project; it cannot import/analyze — a GUI-locked project can't be attached).

## What it provides
Binary `ghidrust` on your PATH; the plugin runs `ghidrust serve` as an MCP server exposing **19 tools**:
- **Read / navigate (14):** `list_project_programs`, `attach_program`, `inspect_function`, `find_functions`,
  `list_symbols`, `list_strings`, `list_data_items`, `list_segments`, `resolve_symbol`, `describe_address`,
  `get_xrefs`, `get_disassembly`, `read_bytes`, `get_datatype`.
- **Write (durable, saved to disk, 5):** `rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`.

Plus the `ghidra-re-driver` skill (embedded in the binary; this copy is emitted from it).

## Configuration
The 4 required values are non-secret env vars (each has a `--kebab` CLI flag; precedence flag > env):
- `GHIDRA_INSTALL_DIR` — Ghidra install root (machine-stable; set once, e.g. via the installer).
- `GHIDRUST_PROJECT_DIR` — dir holding the `<name>.gpr`/`.rep`.
- `GHIDRUST_PROJECT_NAME` — the Ghidra project name.
- `GHIDRUST_BOOTSTRAP_PROGRAM` — a **bare** program filename already in the project (e.g. `add.exe`).

Optional: `GHIDRUST_MAX_HEAP` (JVM `-Xmx`, e.g. `4G`, for large binaries), `GHIDRUST_HOME` (relocate the
`.ghidrust` data dir), `GHIDRUST_BOOTSTRAP_PROGRAM_PATH` (VFS path if the bootstrap program is in a subfolder).

**One server = one Ghidra project.** For per-project config or multiple projects, register the server per
workspace with a project-scoped `.mcp.json` (this overrides the bundled env-only registration):
```json
{
  "mcpServers": {
    "ghidrust": {
      "command": "ghidrust",
      "args": ["serve"],
      "env": {
        "GHIDRUST_PROJECT_DIR": "<absolute path to the dir holding your .gpr/.rep>",
        "GHIDRUST_PROJECT_NAME": "<your Ghidra project name>",
        "GHIDRUST_BOOTSTRAP_PROGRAM": "<bare program filename, e.g. add.exe>"
      }
    }
  }
}
```
> **Project-lock:** one Ghidra project ↔ at most ONE live `ghidrust serve`, and the Ghidra GUI CLOSED. Two
> servers on the same project collide on Ghidra's `project.lock`. Different workspaces must target different projects.

## Logs & quirks
- Logs: `<data>/logs/worker-<pid>.log`, rotated daily (5 kept), owner-only. `<data>` = `GHIDRUST_HOME` or
  `%USERPROFILE%\.ghidrust`. **Log verbosity is fixed in v1.0 — there is no `RUST_LOG`.**
- First call after a cold start returns `WORKER_WARMING` (JVM warm-up) — wait a few seconds, don't hammer.
- Run live e2e from **PowerShell** (Git Bash mangles the `/`-prefixed `-process` arg).
- Keep the installer and this plugin at the same version (they update on separate channels).

## Uninstall
Windows Add/Remove Programs removes the binary + its PATH entry. It intentionally leaves
`GHIDRA_INSTALL_DIR` (shared) and `%USERPROFILE%\.ghidrust` (your data).
````

**Step 5 — Verification.**
- [ ] Both `plugin.json` parse and are byte-identical: `diff plugins/ghidrust/plugin.json plugins/ghidrust/.claude-plugin/plugin.json` → no diff; each `yq -e . <file>` exits 0.
- [ ] `.mcp.json` parses: `yq -e '.mcpServers.ghidrust.command' plugins/ghidrust/.mcp.json` → `ghidrust`.
- [ ] No `<…>` placeholders remain: `grep -rn '<TOOL-ID>\|<BINARY>\|<DESCRIPTION>\|<VERSION>\|<SKILL-NAME>' plugins/ghidrust/` → no matches.

**Step 6 — Commit.**
- [ ] `git add plugins/ghidrust && git commit -m "feat(ghidrust): plugin (dual manifest, env-driven .mcp.json, emitted skill, README runbook)"`

---

## Task 4: Marketplace entry  `[Haiku]`  (branch `main`)

**Files:**
- Modify: `.claude-plugin/marketplace.json` (append one entry to `plugins[]`).

**Step 0 — State verification.** Open `.claude-plugin/marketplace.json`; confirm `plugins` is an array of 3 objects (`agy-autotrain`, `clavity-dotnet`, `commonmemory`). If the count differs, STOP and report `STATE_MISMATCH`.

**Step 1 — Append the ghidrust object** as the 4th element of `plugins[]`. Do this as a single exact-string edit so the JSON stays valid — the `commonmemory` entry's closing `}` MUST gain a trailing comma. Replace:
```json
    {
      "name": "commonmemory",
      "source": "./plugins/commonmemory",
      "description": "Optional add-on: a shared notebook so Claude and agy share facts across the pairing."
    }
  ]
```
with:
```json
    {
      "name": "commonmemory",
      "source": "./plugins/commonmemory",
      "description": "Optional add-on: a shared notebook so Claude and agy share facts across the pairing."
    },
    {
      "name": "ghidrust",
      "source": "./plugins/ghidrust",
      "description": "Drive a persistent headless Ghidra JVM from your agent: 19 reverse-engineering tools (decompile, navigate, durable rename/type/prototype writes) over MCP."
    }
  ]
```

**Step 2 — Verification.**
- [ ] `yq -e '.plugins | length' .claude-plugin/marketplace.json` → `4`; `yq -e '.plugins[3].source' ...` → `./plugins/ghidrust`.

**Step 3 — Commit.**
- [ ] `git add .claude-plugin/marketplace.json && git commit -m "feat(ghidrust): list plugin in the umbrella marketplace"`

---

## Task 5: `.github/workflows/release-ghidrust.yml`  `[Sonnet]`  (branch `main`)

**Files:**
- Create: `.github/workflows/release-ghidrust.yml` (from `templates/tool-skeleton/release-tool.yml.template`).

**Step 0 — State verification.** Open `templates/tool-skeleton/release-tool.yml.template`; confirm it has: tag trigger `<TOOL-ID>-v*`; a `resolve-ref` job (`git ls-remote ... refs/heads/<BRANCH-REF>`); a `build` job `uses: ckir/clavity/.github/workflows/build-<TOOL-ID>.yml@<BRANCH-REF>` with `ref: ${{ needs.resolve-ref.outputs.sha }}`; a `publish` job with `make_latest: false` and `files: dist/<TOOL-ID>-setup-*.exe(.sha256)`. If not, STOP and report `STATE_MISMATCH`.

**Step 1 — Instantiate.** Copy to `.github/workflows/release-ghidrust.yml`; replace every `<TOOL-ID>` → `ghidrust` and every `<BRANCH-REF>` → `ghidrust` (recommended `<branch-ref>` == `<tool-id>`). The `owner/repo` `ckir/clavity` in `uses:` stays hardcoded (Actions forbids expressions there — documented limitation).

**Step 2 — Verification.**
- [ ] `grep -n '<TOOL-ID>\|<BRANCH-REF>' .github/workflows/release-ghidrust.yml` → no matches.
- [ ] `yq -e '.on.push.tags[0]' ...` → `ghidrust-v*`; `yq -e '.jobs.build.uses' ...` → `ckir/clavity/.github/workflows/build-ghidrust.yml@ghidrust`; `yq -e '.jobs.publish.steps[] | select(.uses == "softprops/action-gh-release@v2") | .with.make_latest' ...` → `false`.

**Step 3 — Commit.**
- [ ] `git add .github/workflows/release-ghidrust.yml && git commit -m "ci(ghidrust): release orchestration (ghidrust-v* tag → build@ghidrust + publish, make_latest false)"`

---

## Task 6: ROADMAP + root README rows  `[Sonnet]`  (branch `main`)

**Files:**
- Modify: `ROADMAP.md` (add a "Hosted tools" row + a `# ghidrust` section).
- Modify: `README.md` (add a "Tools hosted here" row).

**Step 0 — State verification.** In `ROADMAP.md` confirm the "## Hosted tools" table has a header row + one `clavity` row, and the first tool section is `# clavity`. In `README.md` confirm the "## Tools hosted here" table has one `clavity` row. If not, STOP and report `STATE_MISMATCH`.

**Step 1 — ROADMAP "Hosted tools" row.** In `ROADMAP.md`, add after the `clavity` row in the `## Hosted tools` table:
```
| [`ghidrust`](#ghidrust) | Drives a persistent headless Ghidra JVM — 19 reverse-engineering tools over MCP (v1.0 attaches to an analyzed project). | `ghidrust-v<N>` |
```

**Step 2 — ROADMAP `# ghidrust` section.** Append at the end of `ROADMAP.md`:
```markdown
---

# ghidrust

> Reverse-engineering MCP server: attaches a persistent **headless Ghidra JVM** to an AI agent and exposes
> **19 tools** (14 read/nav + 5 durable writes) over MCP stdio. Pure-Rust single binary `ghidrust`.

## What ghidrust is now
**SHIPPED — v1.0.0.** `ghidrust serve` attaches to a **pre-analyzed, GUI-closed** Ghidra project and drives
it: decompile/navigate (`inspect_function`, `get_disassembly`, `get_xrefs`, …) plus durable, CAS-guarded
writes saved to disk (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`). Delivered
two-channel: `ghidrust-setup-<VERSION>.exe` installs the binary→PATH; the plugin (skill + `.mcp.json`) ships
via the marketplace. Runtime prereqs: Ghidra 12.1.2 + JDK 21.

## ▶ Forward backlog (v1.1)
- **`import_binary`** — create a project + import/analyze a binary (removes the "pre-analyze in the GUI"
  constraint) — the headline v1.1 feature.
- **Smart-server onboarding** — self-registering binary (`ghidrust register`), agent-driven lazy config (a
  `configure_ghidrust` MCP tool), and JIT MCP diagnostics (`ghidrust doctor` in the boot path turning bad
  config / open-GUI into actionable agent prompts). Requires new binary code (out of the v1.0 packaging).
- **Lazy-boot worker** re-architecture (paired with `import_binary`).
```

**Step 3 — README "Tools hosted here" row.** In `README.md`, add after the `clavity` row:
```
| **ghidrust** | Drives a persistent headless Ghidra JVM — 19 reverse-engineering tools over MCP (attach + decompile + durable edits). | [plugins/ghidrust/README.md](plugins/ghidrust/README.md) | `ghidrust-v<N>` |
```

**Step 4 — Verification.**
- [ ] `grep -c '^# ghidrust' ROADMAP.md` → 1; `grep -c 'plugins/ghidrust/README.md' README.md` → 1. Both tables still render (pipe counts consistent per row).

**Step 5 — Commit.**
- [ ] `git add ROADMAP.md README.md && git commit -m "docs(ghidrust): ROADMAP section + hosted-tools index rows"`

---

## Task 7: Local live-acceptance  `[owner]`  (needs live Ghidra — manual, PowerShell)

**Files:** none (verification only). **Precondition:** run from **Windows PowerShell**.

- [ ] Build on branch `ghidrust`: `cargo build --release -p ghidrust-mcp`.
- [ ] Install `dist/ghidrust-setup-1.0.0.exe` (built locally via ISCC, or from the branch); confirm `ghidrust`
      resolves on PATH in a NEW shell (`Get-Command ghidrust`).
- [ ] Ensure a pre-analyzed, **GUI-closed** Ghidra project exists (create + analyze one in the Ghidra GUI
      first if needed). Note its `PROJECT_DIR`, `PROJECT_NAME`, and a bootstrap program (bare filename).
- [ ] Set env for the session: `GHIDRA_INSTALL_DIR = C:\Users\user\Development\Java\ghidra_12.1.2_PUBLIC`
      (local machine value — never committed), plus `GHIDRUST_PROJECT_DIR`/`_NAME`/`_BOOTSTRAP_PROGRAM`.
- [ ] Register the server (project-scoped `.mcp.json` in a scratch workspace) and, in Claude Code, exercise
      **one read** (`list_project_programs` then `inspect_function`) and **one write** (`rename` or `comment`;
      confirm the change persists on re-read). Expect a first-call `WORKER_WARMING` — wait, retry.
- [ ] Skill-drift guard: `target/release/ghidrust.exe skill --emit` diffs clean against
      `plugins/ghidrust/skills/ghidra-re-driver/SKILL.md` (compare the branch emit to the `main` copy).
- [ ] Record PASS/FAIL in the execution memory. (No commit.)

---

## Task 8: Cut the release  `[owner]`  (branch `main`, outward-facing — explicit owner OK required)

**Files:** none (tag push + release verification). **Gate:** the owner must approve the push (8 prior local
commits + these are unpushed). Do NOT push without explicit approval.

- [ ] Push the branch + main: `git push origin ghidrust` and `git push origin main` (owner-approved).
- [ ] Push the tag on `main`: `git tag ghidrust-v1 && git push origin ghidrust-v1`.
- [ ] Watch `release-ghidrust.yml`: `resolve-ref` pins the `ghidrust` branch SHA → `build` (gate + ISCC +
      sha256) → `publish`. **Do not advance the `ghidrust` branch between tagging and any re-run** (a re-run
      re-resolves the tip).
- [ ] Verify the GitHub Release `ghidrust-v1`: assets `ghidrust-setup-1.0.0.exe` + `.exe.sha256`;
      `make_latest` did NOT steal the "Latest" badge from clavity; the plugin resolves in the marketplace.
- [ ] Update the execution memory: release SHIPPED + live.

> Tag-namespace ruleset stays the documented Enterprise no-op (Layer 2 per-workflow tag filter is the
> free-plan floor — same as clavity; see `docs/hosting-a-tool.md`).

---

## Self-review (author's audit)

**Spec coverage:** Delivery (two-channel) → Tasks 1–5; config injection (bundled + project-scoped `.mcp.json`,
`GHIDRA_INSTALL_DIR` env) → Tasks 1, 3; prereq doc + non-blocking check → Tasks 1, 3; skill sync (emit from
branch) → Task 3; release lineage `ghidrust-v<N>` → Tasks 5, 8; version-stamp sites → Tasks 1, 3 (+ header);
CI toolchain + self-skip split → Task 2; 19-tool surface → Task 3; lifecycle notes (uninstall, project-lock,
version skew) → Tasks 1, 3; local accept → Task 7. All spec sections map to a task.

**Placeholder scan:** No TBD/TODO. Template `<…>` tokens appear only inside "replace X with Y" instructions,
not as final content; each file task ends with a `grep` proving no token survives.

**Type/name consistency:** `ghidrust` (tool-id/binary/marketplace/tag) and `ghidrust.exe` (installer staged
filename + build `cp` target) used consistently; MCP `command` is bare `ghidrust` everywhere; skill name
`ghidra-re-driver` consistent across `.mcp.json` path, README, and the emit target; version `1.0.0` in the 3
enumerated stamp sites.

**Deferred to execution (not gaps):** the fresh `AppId` GUID (generated in Task 1); the exact `PROJECT_*`
values for Task 7 (owner's live project). Both are correctly owner/runtime-supplied, not spec omissions.
