# Universal Dual-Plugin Restructure — Design

**Date:** 2026-06-17
**Status:** Approved (design); implementation plan pending.
**Author:** Costas Kirgoussios (with Claude + agy consult)

---

## 1. Context & charter

Today the repo is a single Rust binary — `clavity` — that lets Claude Code (master)
drive a live `agy` (Antigravity CLI) peer over a psmux doorbell + the agentmemory
signal bus. It is **one tool, one direction**.

The repo's charter is being reframed: it is **dedicated to tools (plural) that
facilitate collaboration between `claude-cli` and `antigravity-cli`**. The first
change is **packaging**: produce **"universal" plugins** — a single directory
installable by *both* CLIs:

```
claude plugin install /path/to/<plugin>
agy    plugin install /path/to/<plugin>
```

The current `clavity` code is **preserved on a `v1` branch for reference only** and is
not carried forward; `main` is rebuilt fresh around the universal-plugin model. We stay
in **Rust**.

### What a "plugin" is (the user's model)

A plugin is a **package envelope** bundling up to four component types, installed as a
unit:

| Component | Role | Across the two hosts |
|---|---|---|
| **Skills** | behavioral playbook (e.g. `/deploy-stack`) | `skills/<name>/SKILL.md` — **same path, 100% shared** |
| **MCP servers** | active API tools (JSON-RPC) | shared **binary**; config forks (Claude `.mcp.json` / agy `mcp_config.json`) |
| **Rules** | style / constraints | agy reads `rules/`; **Claude has no plugin `rules/`** → mirrored into a skill |
| **Hooks** | lifecycle triggers | shared **scripts**; config forks (Claude `hooks/hooks.json` / agy `hooks.json`) |

Skills *use* MCP tools: the skill is the structured playbook, the MCP server is the API
bridge.

---

## 2. Goals & non-goals

**Goals (this spec):**

1. Define the fresh `main` repo structure: a Cargo **workspace** that produces a **suite**
   of universal, dual-installable plugins.
2. Specify the **dual-compatibility mechanism** (how one source produces artifacts both
   CLIs accept) and the **`xtask` packager**.
3. Deliver a minimal **dual-compat scaffold plugin** that installs cleanly in *both* CLIs,
   proving the packaging before real capability is built on it.
4. Preserve v1.

**Non-goals (deferred to their own spec → plan cycles):**

- Full design/implementation of `clavity` v2 (bidirectional collaboration).
- Full design/implementation of `commonmemory`.
- Cross-platform (Linux/macOS) plugin distribution — Windows `.exe` first (matches v1's
  verified platform).

---

## 3. Verified facts (provenance-tagged)

Per this repo's discipline (`docs/agy-assumptions.md`): behaviors of the external CLIs are
**empirically derived, not a stable contract** — re-verify after a CLI update.

### Claude Code plugin format
*(Source: code.claude.com/docs/en/plugins-reference, fetched 2026-06-17)*
- Manifest: `.claude-plugin/plugin.json`.
- MCP servers: `.mcp.json` at plugin root (standard `mcpServers`: `command`, `args`,
  `env`, `cwd`), or inline in `plugin.json`.
- **`${CLAUDE_PLUGIN_ROOT}`** path variable is supported in mcp/hook commands — a bundled
  binary is referenced as `"${CLAUDE_PLUGIN_ROOT}/bin/<n>.exe"`.
- Hooks: `hooks/hooks.json` (or inline), event matchers; commands may use
  `${CLAUDE_PLUGIN_ROOT}`.
- Skills: `skills/<name>/SKILL.md`, auto-discovered.
- No plugin-level `rules/` directory (components are skills/agents/hooks/MCP/LSP/monitors).

### Antigravity (agy) plugin format
*(Source: agy peer consult [req-djbdx6998nv0] + [req-djbeby5zp30k], 2026-06-17; agy docs page is JS-rendered/unreadable — re-verify against live agy)*
- Staged under `~/.gemini/antigravity-cli/plugins/<name>/`.
- Manifest: root **`plugin.json`**; **required fields: `name`, `version`, `description`.**
- MCP servers: `mcp_config.json` (`mcpServers`; supports `command`/`args` and `serverUrl`).
- **No `${...}` path variable.** agy sets **CWD = plugin root** when launching the MCP
  server, so reference a bundled binary by **relative path**: `"./bin/<n>.exe"`.
- Hooks: `hooks.json` at root. Optional `skills/`, `agents/`, `rules/`.
- **`agy plugin install <path>` only copies/stages files — no build step.** Binaries must
  be **pre-compiled**.

### agy's hard constraints for a shipped Rust MCP server
*(Source: agy consult, 2026-06-17)*
- Windows: the `command` **must include the `.exe` suffix**.
- The server **must write all logs/panics to `stderr`** — any non-JSON-RPC byte on
  **stdout breaks the MCP transport.**

### The "universal" mechanism
The two CLIs read **disjoint filenames**, so both manifest sets coexist in one directory
without collision:

| Concern | Claude reads | agy reads |
|---|---|---|
| Manifest | `.claude-plugin/plugin.json` | `plugin.json` |
| MCP config | `.mcp.json` | `mcp_config.json` |
| Hooks config | `hooks/hooks.json` | `hooks.json` |

Shared (compatible across both): `skills/`, `rules/` (agy; Claude via mirror), `hooks/`
scripts, `bin/`.

**Load-bearing assumption (state explicitly; re-verify — agy consult):** each CLI
**silently ignores the other's host-specific files** in a shared dir — agy ignores
`.claude-plugin/` + `.mcp.json` + `hooks/hooks.json`; Claude ignores root `plugin.json` +
`mcp_config.json` + `hooks.json`. The entire universal-dir model rests on this mutual
tolerance; if either CLI starts erroring on unrecognized sibling files, `split` mode
(§4.3) becomes mandatory.

---

## 4. Architecture — repo structure

```
clavity/                          # repo (fresh main; old code on the v1 branch)
├── Cargo.toml                    # [workspace] members = crates/*, plugins/*, xtask
├── crates/
│   └── mcp-core/                 # SHARED lib: stdio JSON-RPC loop, protocol types,
│                                 #   stderr-only logging helpers
├── plugins/                      # each subdir is one plugin (a workspace member)
│   ├── scaffold/                 # first deliverable — proves dual-compat (shown expanded below)
│   │   ├── plugin.toml           # SOURCE OF TRUTH: name, version, description,
│   │   │                         #   mcp server defs, hook defs
│   │   ├── Cargo.toml            # bin crate → the plugin's MCP server (deps mcp-core)
│   │   ├── src/main.rs
│   │   ├── skills/<skill>/SKILL.md   # shared payload, copied verbatim
│   │   ├── rules/<rule>.md           # shared payload (agy native; mirrored to Claude skill)
│   │   └── hooks/<script>.ps1        # shared hook scripts
│   ├── clavity/                  # v2 (bidirectional) — own spec, later
│   └── commonmemory/             # config-only (NO Cargo.toml/src bin crate) — own spec, later
├── xtask/                        # `cargo xtask package <plugin> [--mode ...]`
└── dist/                         # GENERATED, gitignored — the installable payload
    └── <plugin>/                 # (universal mode) installable by BOTH CLIs
        ├── .claude-plugin/plugin.json    plugin.json       # Claude / agy manifests (generated)
        ├── .mcp.json                     mcp_config.json   # Claude / agy mcp config (generated)
        ├── hooks/hooks.json              hooks.json        # Claude / agy hooks (generated)
        ├── skills/  rules/  hooks/<scripts>                # copied shared payload
        └── bin/<n>.exe                                     # pre-built (agy can't build on install)
```

### 4.1 `crates/mcp-core` (shared library)
- A reusable stdio JSON-RPC (MCP) server loop, protocol/request-response types, and
  **logging helpers that write only to stderr**.
- Every plugin's bin crate depends on it, so the stdout-purity invariant is enforced in
  one place.

### 4.2 `plugins/<name>/plugin.toml` (single source of truth)
- Holds `name`, `version`, `description` (the fields both manifests need), plus the
  plugin's MCP server definition(s) and hook definition(s) in a host-neutral form.
- The xtask renders this into **both** hosts' concrete files, injecting the correct
  per-host binary-path convention. One edit, both hosts stay in sync — no drift.

### 4.3 `xtask` (the packager)
`cargo xtask package <plugin> [--mode universal|split]`:
1. `cargo build --release` the plugin's bin crate (if any).
2. Generate from `plugin.toml`: `.claude-plugin/plugin.json` + root `plugin.json`;
   `.mcp.json` (binary as `${CLAUDE_PLUGIN_ROOT}/bin/<n>.exe`) + `mcp_config.json`
   (binary as `./bin/<n>.exe`, relying on agy's CWD=plugin-root); `hooks/hooks.json` +
   `hooks.json`.
3. Mirror `rules/*.md` into a Claude-side skill (Claude has no plugin `rules/`).
4. Copy shared payload (`skills/`, `rules/`, `hooks/` scripts) and the built `bin/<n>.exe`.
5. Emit into `dist/`.

**Packaging modes (both supported; default deferred):**
- **universal** — one `dist/<plugin>/` with both manifest sets coexisting (disjoint
  filenames). Matches the bidirectional/symmetric model; the original vision.
- **split** — per-host `dist/<plugin>-claude/` and `dist/<plugin>-agy/` (agy's suggestion;
  eliminates any cross-host skill noise for asymmetric plugins).

The default mode is **chosen after the scaffold is installed and tested in both CLIs**,
not now.

---

## 5. Rules parity
*(Decision: mirror rules → Claude skill.)* Claude plugins have no native `rules/` for
automatic context injection. At package time the xtask emits each `rules/*.md` as a
Claude-side skill so both hosts honor the constraints. agy consumes `rules/` natively.

**Double-load hazard (agy spec review):** in a single universal dir, agy would load **both**
the native `rules/` *and* the mirrored skill in `skills/` — duplicating that context.
Resolution depends on packaging mode:
- **split mode** — clean: the agy dist ships native `rules/` (always-on injection) and
  **not** the mirrored skill; the Claude dist ships the mirrored skill and no `rules/`.
- **universal mode** — to avoid the agy double-load, ship **only the mirrored skill** (both
  hosts use it on-demand) and **omit native `rules/`** from the universal dir — accepting
  that agy loses always-on injection for on-demand skill invocation. (Alternative: keep
  `rules/` and exclude the mirror for agy *iff* agy supports per-host skill exclusion —
  re-verify; see §10.)

Because this interacts with the packaging-mode default (deferred), the rules-handling
choice is finalized alongside that default after the scaffold is live-tested.

---

## 6. First deliverable — the dual-compat scaffold plugin
`plugins/scaffold/`: a minimal plugin that exercises **all four component types** so the
acceptance proves the *whole* packaging contract, not just MCP+skills *(agy spec review)*.
- A trivial **MCP server** (built on `mcp-core`) exposing one "hello" tool; logs to stderr
  only.
- One shared **`SKILL.md`** (skill).
- One trivial **hook** (e.g. a `SessionStart`/lifecycle hook that emits a marker).
- One trivial **rule** (constraint markdown) → mirrored to a Claude skill per §5.
- A `plugin.toml` from which the xtask generates **both** hosts' manifests/mcp/hooks.

**Acceptance:** `cargo xtask package scaffold` produces an installable `dist/scaffold/`
where, in **both** CLIs:
1. Install is accepted (`claude plugin install dist/scaffold`; `agy plugin install
   dist/scaffold`).
2. **MCP** — the server + skill are listed and the hello tool responds.
3. **Hook** — the lifecycle hook fires (its marker is observed).
4. **Rule** — the rule is actively injected into context (agy native `rules/` and/or the
   Claude-mirrored skill, per the §5 mode decision).
5. No stdout-pollution transport failure on either host.

This proves all four component types and the packaging before `clavity` v2 and
`commonmemory` build on it.

---

## 7. Suite members (structure drivers; designed later)

- **`clavity` (v2)** — **bidirectional** Claude↔agy collaboration over the psmux doorbell +
  agentmemory bus. Not master→peer: *either* agent can drive and *either* can respond;
  the role is **assigned per project** (config), not baked into the package. Because both
  hosts want the same capability, the shared `skills/` (driver + responder playbooks) is
  genuinely shared — which is why the **universal single-dir** model fits. Mechanics
  (symmetric doorbell so each agent is wakeable by the other, per-project role config) are
  this plugin's own spec.
- **`commonmemory`** — **config-only plugin (no binary).** It reuses the **existing
  agentmemory daemon** both agents already connect to. Minimal sound shape *(agy consult)*:
  (a) shared skills encoding shared-memory conventions, (b) manifest configuration wiring
  both agents to the same agentmemory store. Confirms the structure must support a plugin
  with **no bin crate**.

---

## 8. v1 preservation
Branch `v1` off the current `main` (preserving full history + current code), push it, then
rebuild `main` fresh. Both branches retain history; v1 is reference-only.

---

## 9. Testing strategy
- **mcp-core / xtask:** unit tests (manifest generation from `plugin.toml` produces the
  exact expected files for both hosts; stdout-purity guard).
- **Scaffold install:** the live acceptance in §6 — a runbook re-run after a `claude`/`agy`
  update (consistent with the existing `docs/agy-test-suite.md` discipline).
- Keep `cargo test --all`, `cargo clippy --all-targets -- -D warnings`, `cargo fmt --all`
  green across the workspace.

---

## 10. Open items — re-verify against the live CLIs
These rest on the agy peer consult and may shift on a CLI update; confirm during scaffold
implementation:
1. agy `plugin.json` required fields — `name`/`version`/`description` confirmed; **also
   check whether `author` (or any other field) is strictly required** *(agy flagged it
   might be)*.
2. agy launches the MCP server with **CWD = plugin root** (so `./bin/<n>.exe` resolves).
3. agy hooks file is exactly `hooks.json` at root with the expected schema.
4. `claude plugin install <local path>` accepts a local dir (vs marketplace-only) and
   discovers `.mcp.json` + `skills/` + `hooks/hooks.json` without manifest registration.
5. **Mutual file-tolerance** (§3): each CLI silently ignores the other's host-specific
   sibling files in a shared dir. If violated, `split` mode is mandatory.
6. **rules double-load** (§5): in a universal dir agy loads *both* `rules/` and the
   mirrored skill. Confirm whether agy can exclude a skill per-host; if not, the
   universal-mode rules approach (skill-only, drop `rules/`) stands.

---

## 11. Risks
- **External-contract drift** — the whole repo's standing risk; mitigated by the SSOT +
  generation (one place to fix) and the re-verification runbook.
- **stdout pollution** — a stray `println!`/panic-to-stdout breaks MCP transport silently;
  mitigated by routing all output through `mcp-core` stderr helpers + a test guard.
- **Platform** — `dist/` ships a Windows `.exe`; non-Windows hosts need a per-platform
  build (deferred). Note *(agy spec review)*: agy's install does **not** `chmod +x`
  pre-built binaries on Unix, so the Unix port must set the exec bit in the xtask (or
  document a post-install step) — tracked for the cross-platform work.
