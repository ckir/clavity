# Onboarding `ghidrust` into the clavity umbrella — design (v1.0)

**Date:** 2026-07-09
**Status:** design (awaiting user review gate → writing-plans)
**Scope:** Package the **frozen ghidrust-mcp v1.0.0 binary** as a first-class umbrella tool. This is a
**packaging** effort — it adds **no new ghidrust code**. The generic mechanics live in the onboarding
playbook [`docs/hosting-a-tool.md`](../../hosting-a-tool.md); this spec resolves only the ghidrust-specific
forks the playbook defers.

## Context (facts verified against the ghidrust repo, 2026-07-09)

`ghidrust-mcp` is a pure-Rust single-binary MCP server that attaches a persistent **headless Ghidra JVM**
to an AI agent and exposes reverse-engineering tools over **MCP stdio**. Consumers are AI CLIs (Claude Code
and Antigravity). Platform of record: Windows 11. Verified facts (source: `HANDOFF.md`,
`crates/ghidrust-mcp/src/server.rs`, `.claude/recommended-tools.json`):

- **Binary:** `ghidrust` (crate `ghidrust-mcp`, `[[bin]] name = "ghidrust"`). Version **1.0.0**.
- **Build:** `cargo build --release -p ghidrust-mcp` → `target/release/ghidrust.exe`.
- **Gate:** `just test` (`cargo nextest run --workspace`) + `just lint` (`cargo fmt --check` +
  `cargo clippy -D warnings` + `cargo deny check`).
- **MCP:** `ghidrust serve` speaks MCP over stdio; **stdout is reserved for JSON-RPC** (logs go to a file).
- **Tool surface: 19 tools** — 14 read/nav (`list_project_programs`, `attach_program`, `inspect_function`,
  `find_functions`, `list_symbols`, `list_strings`, `list_data_items`, `list_segments`, `resolve_symbol`,
  `describe_address`, `get_xrefs`, `get_disassembly`, `read_bytes`, `get_datatype`) + 5 write
  (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`). *(Counted from the `_tool_attr()`
  registry in `server.rs`; the ghidrust M3-prep spec's "18" is a stale typo — not corrected here, that's
  the other repo.)*
- **Config: 4 required, machine-specific, non-secret env values** (each has a `--kebab` CLI-flag
  equivalent; precedence CLI flag > env var; there is **no config file** and **nothing secret** — the
  loopback auth token is ephemeral per boot):
  - `GHIDRA_INSTALL_DIR` — Ghidra install root (machine-stable).
  - `GHIDRUST_PROJECT_DIR` — dir holding the `<name>.gpr`/`.rep` (per RE project).
  - `GHIDRUST_PROJECT_NAME` — the Ghidra project name (per RE project).
  - `GHIDRUST_BOOTSTRAP_PROGRAM` — a **bare** program filename already in the project (per RE project).
  - Optional: `GHIDRUST_BOOTSTRAP_PROGRAM_PATH`, `GHIDRUST_MAX_HEAP`, `GHIDRUST_HOME`.
- **Runtime prerequisites (end user):** **JDK 21** and **Ghidra 12.1.2** (Ghidra 12.1.2 requires
  `application.java.min=21`). `cargo`/`nextest`/`deny`/`just`/`lefthook` are **build-only** prereqs.
- **Skill:** `ghidra-re-driver`, authored at `skill/SKILL.md`, **embedded in the binary**; the binary is
  the single source of truth via `ghidrust skill --emit`.
- **One server = one Ghidra project** (fixed at boot); `attach_program` switches programs *within* it.
- **v1.0 only ATTACHES** to a pre-existing, fully-analyzed project with the **Ghidra GUI CLOSED**
  (`import_binary` is v1.1). The operator must create + analyze the project in the GUI first, then close it.

**ghidrust is the FIRST umbrella tool that is BOTH code-on-branch AND ships a plugin** — clavity-dotnet is
all-on-`main`; clavity-classic ships no plugin. It is therefore the first to hit the playbook's deferred
cross-branch plugin-bundling question. The delivery decision below **dissolves** that question rather than
solving it.

## Settled umbrella conventions applied (not re-opened)

- **D2 — per-tool release lineage:** ghidrust releases under its **own** serial `ghidrust-v<N>` tag with its
  own `release-ghidrust.yml`. *(This overrides `HANDOFF.md`'s stale "release under `clavity-v<N>`" line,
  which predates D2.)*
- **D7 — branch/main split:** code + `installer/ghidrust.iss` + reusable `build-ghidrust.yml` on the
  `ghidrust` **branch**; `plugins/ghidrust/` + its `marketplace.json` entry + ROADMAP section +
  `release-ghidrust.yml` on **`main`**.
- **D8 — slug:** `ghidrust` (flat kebab == binary name), used identically for plugin dir, marketplace name,
  tag prefix, installer basename.

## Decision 1 — Delivery model: TWO-CHANNEL (dissolves cross-branch bundling)

The native binary and the Claude Code plugin travel **separate, natural channels**:

- **Native binary → Inno installer** (on the `ghidrust` branch): installs `ghidrust.exe` to PATH only.
- **Plugin (skill + registration) → Claude Code marketplace** (on `main`, via `marketplace.json`).

Because the installer never packages `plugins/`, **the branch-side build never needs `main`'s plugin
tree** — the cross-branch coupling problem does not arise. This is also the most umbrella-idiomatic shape
(mirrors clavity-classic's "Option A" binary-to-PATH installer; the umbrella already serves plugins via the
marketplace).

Rejected alternatives: *installer-bundles-plugin* (would force a cross-branch sparse-checkout of `main` into
the branch build — needless coupling); *marketplace-only, no installer* (hostile to non-Rust Windows users —
loses the one-command binary install).

## Decision 2 — Config injection: project-scoped `.mcp.json` + one machine env var

Reflecting the **one-server-per-project** reality and the "env IS the config" model:

- `GHIDRA_INSTALL_DIR` (machine-stable) → a **user-level environment variable**; the installer offers to set
  it (from a value the user supplies), so every project inherits it.
- `GHIDRUST_PROJECT_DIR` / `GHIDRUST_PROJECT_NAME` / `GHIDRUST_BOOTSTRAP_PROGRAM` (per RE project) → carried
  in a **project-scoped `.mcp.json`** the operator drops into their RE workspace, from a documented template
  (below). This survives plugin updates (nothing to hand-edit inside the plugin cache) and lets one machine
  drive many projects (one `.mcp.json` per workspace).

**The plugin bundles a convention-consistent, env-driven `.mcp.json`** — every existing umbrella plugin
bundles one (verified against `plugins/clavity-dotnet/.mcp.json`, which serves *both* Claude and agy, so
`.mcp.json` — **not** `mcp_config.json` — is the umbrella convention for both CLIs). The bundled file
registers the server with **no hardcoded paths**; it runs `ghidrust serve` and reads all config from the
environment:

```json
{ "mcpServers": { "ghidrust": { "command": "ghidrust", "args": ["serve"] } } }
```

A **single-project** user who sets the 4 values as machine/user env vars gets a working server on plugin
install, nothing to edit. A **multi-project** user overrides per workspace with the project-scoped
`.mcp.json` template below (adding the three per-project values to the `env` block). This keeps ghidrust
consistent with the other plugins *and* honors the one-server-per-project model. The `command` is the
**bare `ghidrust`** (PATH-resolved), never `ghidrust.exe`.

Documented `.mcp.json` template (goes in `plugins/ghidrust/README.md`):

```json
{
  "mcpServers": {
    "ghidrust": {
      "command": "ghidrust",
      "args": ["serve"],
      "env": {
        "GHIDRUST_PROJECT_DIR": "<absolute path to the dir holding your .gpr/.rep>",
        "GHIDRUST_PROJECT_NAME": "<your Ghidra project name>",
        "GHIDRUST_BOOTSTRAP_PROGRAM": "<bare program filename already in the project, e.g. add.exe>"
      }
    }
  }
}
```

`GHIDRA_INSTALL_DIR` is inherited from the machine env var; a user who prefers self-contained config may add
it to the `env` block too (CLI flag > env var precedence makes either work).

## Decision 3 — Prerequisite handling: doc-first + non-blocking installer check

The end-user prereqs (JDK 21, Ghidra 12.1.2, a pre-analyzed GUI-closed project) are heavyweight and
external. The installer:

- **States** the JDK 21 + Ghidra 12.1.2 requirement and the "analyze-in-GUI-then-close" onboarding flow in
  its wizard text + the plugin README.
- Performs a **non-blocking** check: if `GHIDRA_INSTALL_DIR` (env) / `support\analyzeHeadless.bat` does not
  resolve, it **warns but does not refuse** (the user may install Ghidra afterwards).

This is a deliberate step up from clavity-classic's doc-only `uv` precedent, justified by the heavier prereq,
while staying non-hostile. Runtime footguns (GUI still open, bad bootstrap program) surface as ghidrust's own
boot/first-call errors (existing behavior — e.g. `WORKER_WARMING` on cold start); the packaging session adds
no new diagnostics.

## Decision 4 — Skill sync: regenerate from the binary (zero drift)

The binary embeds the authored skill (`include_str!`) and emits it via `ghidrust skill --emit`, so the
plugin copy can never drift from the binary's version. *(This is the one in-scope kernel of agy's "binary is
source of truth" instinct.)*

**Where it runs matters — the ghidrust crate does NOT exist on `main`** (code is on the `ghidrust` branch),
so the skill **cannot** be emitted by a binary on `main` during Phase B, and `ghidrust` is not yet on PATH
(the installer runs in Phase C). The skill file is therefore emitted **on the `ghidrust` branch**, from the
release binary the branch build produces, and the resulting `SKILL.md` is **committed on `main`**:

The redirect target `plugins/ghidrust/skills/…` exists **only on `main`**, so emit to a **temp file** on the
branch first, then `git checkout main` and move it into the plugin tree:

```
# on the ghidrust branch, after `cargo build --release -p ghidrust-mcp`:
target/release/ghidrust skill --emit > ghidra-re-driver.SKILL.md.tmp   # untracked file at repo ROOT
git checkout main                                                       # the untracked temp file survives the switch
mkdir -p plugins/ghidrust/skills/ghidra-re-driver
mv ghidra-re-driver.SKILL.md.tmp plugins/ghidrust/skills/ghidra-re-driver/SKILL.md   # then commit on main
```

The temp file is a **repo-root relative path** (no `$TEMP`/`$env:TEMP` — that variable differs between bash
and PowerShell and would misfire); an untracked root file survives `git checkout main`.

A drift-guard in CI/plan re-emits and diffs (see Testing). No step assumes `ghidrust` on PATH before the
installer exists, and no redirect targets a path that is absent on the current branch.

## Deliverables by phase (maps onto `docs/hosting-a-tool.md`)

### Phase A — branch `ghidrust`
1. **Import the v1.0.0 source** onto branch `ghidrust`. Recommended: a **clean snapshot** of the shippable
   crate (workspace `Cargo.toml`, `crates/`, `skill/`, `worker/`, `justfile`, `deny.toml`,
   `rust-toolchain.toml`, `.claude/recommended-tools.json`), **excluding** `target/`, the origin `.git`, and
   the tool's internal `docs/superpowers/` dev history (which stays in the original repo as provenance). The
   branch must also contain `templates/tool-skeleton/` (merge `main` if the branch is cut before that
   exists). *(Open point for the plan: clean snapshot vs `git subtree` history preservation — recommend
   snapshot; the original repo is the history of record.)*
2. `installer/ghidrust.iss` from `templates/tool-skeleton/installer.iss.template`: fill
   `<TOOL-ID>`=`ghidrust`, `<VERSION>`=`1.0.0`, `<BINARY>`=**`ghidrust.exe`** (the template's `ExeName`
   feeds `Source: "..\publish\{#ExeName}"`, a literal staged filename — the `.exe` is required or ISCC can't
   find the file; the MCP `command` separately uses the bare `ghidrust`); **fresh `AppId` GUID**; per-user
   (`%LOCALAPPDATA%` + HKCU); binary→PATH; wizard text states JDK 21 + Ghidra 12.1.2 + the GUI-closed flow;
   offers to set `GHIDRA_INSTALL_DIR` user env var; **non-blocking** Ghidra-presence check; **no plugin
   packaged**.
3. `.github/workflows/build-ghidrust.yml` from `build-tool.yml.template` (**not** copied from
   `build-dotnet.yml` — its naked `actions/checkout` would build `main`): checkout `ref`-pinned to branch
   `ghidrust`; **install the toolchain the stock runner lacks — `just`, `cargo-nextest`, `cargo-deny`** (a
   `FILL`-marked step); `cargo build --release -p ghidrust-mcp`; run the **CI-safe gate** `just lint`
   (fmt/clippy/deny — no Ghidra) + `just test` (the live-worker tests **self-skip without `GHIDRUST_E2E=1`**
   — verified via `tests/common::enabled()` — so no Ghidra/JDK is needed on the runner; only unit/structural
   tests execute); stage `target/release/ghidrust.exe` → `publish/`; produce the installer via ISCC.
   > The **full live suite** (`GHIDRUST_E2E=1`, needs Ghidra + an analyzed project — 177 tests locally)
   > stays a **local pre-release gate**, mirroring clavity-dotnet's local-gate precedent (no live JVM in CI).

### Phase B — `main`
4. `plugins/ghidrust/` — mirror the existing plugins' layout exactly (verified against `plugins/clavity-dotnet/`):
   - **BOTH** `plugin.json` (dir root) **and** `.claude-plugin/plugin.json` — every existing umbrella plugin
     ships both manifests; naming only the `.claude-plugin/` one leaves the plugin undiscoverable. Fill all
     `<…>` from the template.
   - `.mcp.json` (dir root) — the bundled, env-driven registration `{ "mcpServers": { "ghidrust": {
     "command": "ghidrust", "args": ["serve"] } } }` (no hardcoded paths; see Decision 2).
   - `skills/ghidra-re-driver/SKILL.md` — **committed here, emitted from the branch build** (see Decision 4;
     NOT generated by an on-PATH binary during Phase B — the crate isn't on `main`).
   - `README.md` = operator **runbook** (create+analyze project → close GUI → set the 4 values) + the
     **19-tool surface** + the project-scoped **`.mcp.json` override template** + the **optional env vars**
     (`GHIDRUST_MAX_HEAP` for large-binary JVM heap tuning; `GHIDRUST_HOME` to relocate the data dir;
     `GHIDRUST_BOOTSTRAP_PROGRAM_PATH` when the bootstrap program lives in a project subfolder) + a
     **project-lock warning** (one Ghidra project ↔ **at most one** live `ghidrust serve` **and** the GUI
     closed; two servers pointed at the *same* project collide on Ghidra's `project.lock` — different
     workspaces must target different projects) + logs/quirks (logs at `<data>/logs/worker-<pid>.log`,
     daily-rotated, owner-only; **no `RUST_LOG` — do not claim it**; run live e2e from PowerShell).
5. `.claude-plugin/marketplace.json`: one entry from `marketplace-entry.json.template`,
   `source: ./plugins/ghidrust`.
6. `.github/workflows/release-ghidrust.yml` from `release-tool.yml.template`: tag-filtered `ghidrust-v*`,
   `uses: …@ghidrust`, `make_latest: false`.
7. ROADMAP `# ghidrust` section + a "Hosted tools" index row; root `README.md` "Tools hosted here" row
   linking `plugins/ghidrust/README.md`.

### Phase C — release
8. Push tag **`ghidrust-v1` on `main`** (matching the `clavity-v<N>` precedent — the tag must land where
   `release-ghidrust.yml` lives). Verify: GitHub Release + `ghidrust-setup-*.exe` + `.sha256`; the plugin
   resolves in the marketplace. Tag-namespace ruleset stays the documented Enterprise no-op (Layer 2
   per-workflow filter is the free-plan floor — same as clavity; see the playbook).

## Testing / verification

**CI (build-ghidrust.yml, after installing `just`/`cargo-nextest`/`cargo-deny`):** `cargo build --release`
green; `just lint` green; `just test` green with the live-worker tests **self-skipped** (`GHIDRUST_E2E`
unset — no Ghidra/JDK on the runner); ISCC compiles the installer; `.sha256` emitted.

**Local pre-release gate (manual):** the **full** `just test` (`GHIDRUST_E2E=1`, 177 tests, real Ghidra) +
`just lint` green before cutting the tag — the live JVM path is exercised locally, not in CI.

**Skill-drift guard (manual, documented in the plan):** re-emit from the branch binary and diff against the
committed copy — `target/release/ghidrust skill --emit | diff - plugins/ghidrust/skills/ghidra-re-driver/SKILL.md`
→ no diff. *(Run on the `ghidrust` branch with the plugin file fetched, or compare the emitted temp file to
the `main` copy — the binary isn't on `main`.)*

**Local live-acceptance runbook (manual, Windows PowerShell — Git Bash mangles the `/`-prefixed `-process`
arg):**
- `GHIDRA_INSTALL_DIR = C:\Users\user\Development\Java\ghidra_12.1.2_PUBLIC` (local machine value — **never**
  hardcoded into any shipped artifact).
- Requires a pre-analyzed, **GUI-closed** Ghidra project + a bootstrap program (`PROJECT_DIR`/`PROJECT_NAME`/
  `BOOTSTRAP_PROGRAM`); if none exists, create + analyze one in the GUI first.
- Register the server from the project-scoped `.mcp.json` template; exercise **one read tool**
  (`list_project_programs` / `inspect_function`) and **one write tool** (`rename` or `comment`, confirming
  the edit persists). Expect a first-call `WORKER_WARMING` on cold start — wait, don't hammer.

**Acceptance:** installer installs `ghidrust.exe` to PATH and sets the env var; marketplace serves the
plugin; the skill loads and its tool references resolve once the server is registered.

## Release & lifecycle notes

- **Version-stamp sites (bump in lockstep every release).** `1.0.0` lives in **3 files across 2 branches**:
  `installer/ghidrust.iss` `AppVersion` (branch `ghidrust`); `plugins/ghidrust/plugin.json` **and**
  `plugins/ghidrust/.claude-plugin/plugin.json` (`main`). The workspace `Cargo.toml` version is the source
  of truth on the branch. There is **no automated cross-branch parity guard** — the release checklist (in the
  plan) must enumerate and bump all sites together (mirrors the clavity-dotnet lesson: bump `.iss` + both
  `plugin.json` + ROADMAP). *(marketplace.json carries no version — it points at the plugin dir.)*
- **Build reproducibility.** `release-ghidrust.yml`'s `resolve-ref` job SHA-pins the `ghidrust` branch tip
  **once at cut time**, so a single run rebuilds one snapshot. Accepted, umbrella-wide caveat (inherited from
  the template, not ghidrust-specific): a **re-run** days later re-resolves the *current* branch tip, and
  `uses: …@ghidrust` loads the build file from branch tip — so **do not advance the `ghidrust` branch between
  tagging and a release re-run** (or the plan may add a SHA/`ref` dispatch input like `umbrella-release.yml`'s
  `classic_ref`). See the playbook's @ref discipline.
- **Uninstall scope.** The uninstaller removes only the **PATH** entry. It intentionally leaves
  (a) `GHIDRA_INSTALL_DIR` — shared user config that other tools may rely on, **not ghidrust's to delete** —
  and (b) the `%USERPROFILE%\.ghidrust` data dir (logs/worker scripts; user data, same-user trust boundary).
  Documented in the installer/README so it is a choice, not a surprise.
- **Two-channel version skew (accepted limitation).** Because the binary (installer) and the plugin
  (marketplace) update on separate channels, a user can run a v2 plugin against a v1 binary (or vice-versa)
  until they update both. This is tolerable by construction: the **binary's advertised MCP tool surface is
  authoritative** (the skill is version-tolerant driving *guidance*, not a version-locked wire contract; the
  host↔worker IPC version `0.7.0` is internal to the binary). The README states "update the installer and the
  plugin together." Not a blocker; the price of the two-channel model the user chose.

## Out of scope / future (v1.1 north star)

Recorded from the AGY-FIRST divergent consult (cascade `e350f145`) — **deferred, needs new ghidrust binary
code, precluded by the frozen v1.0.0 + the M3-prep scope boundary**:

- **Self-registering binary** (`ghidrust register` writes `.mcp.json`/skill into `~/.claude` & `~/.gemini`).
- **Agent-driven lazy config** (boot unconfigured; a `configure_ghidrust` MCP tool persists the 4 values;
  first-call error coaches the agent to collect them).
- **JIT MCP diagnostics** (a `ghidrust doctor` preflight inside the boot sequence turning "GUI is open" /
  "bad Ghidra dir" into actionable agent prompts).
- **`import_binary`** (create/import/analyze a project — removes the "pre-analyze in GUI" constraint) and the
  **lazy-boot worker** re-architecture.

These are the strongest v1.1 directions but are explicitly not part of this packaging effort.
