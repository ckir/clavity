# clavity-classic packaging — installer + prebuild + release CI (7.8 / 7.1 / 7.2) — design

> **Spec B of the clavity-classic installer epic** (see ROADMAP.md §1; Spec A is the golden-header
> **injection** prerequisite, `2026-06-30-clavity-classic-injection-design.md`). Forward-writable SPEC — the
> Rust source lives on the `clavity-classic` branch and the prebuilt `clavity.exe` does not exist yet, so
> line-level `.iss`/workflow detail lands in the implementation plan authored against the **real** CI
> artifacts. This spec defines intent + contracts, mirroring the **proven, shipped** dotnet packaging
> (`installer/clavity-dotnet.iss` + `.github/workflows/release-clavity-dotnet.yml` on `main`) as the oracle.

> **STATUS — reconciled 2026-06-30 (Spec A landed).** The 7.3 prerequisite is **DONE**: golden-header
> injection is **merged to `clavity-classic` (`dea8f87`)**, rust-reviewed (APPROVE). The build order's first
> item is complete and **Spec B is now the active epic**; next actionable = **7.8 (prebuild)**.
> **BRIDGE SOURCE = VENDORED IN-BRANCH (user re-decision 2026-06-30, (iii)→(i)).** The claudavity bridge
> source now lives **canonically in-branch at `agy-mcp-bridge/` on `clavity-classic`** (commit `b795c4b`; it
> originated from the **now-frozen claudavity prototype** @`fae54fa`, kept only for reference — there is **no
> upstream, no re-sync, no drift**; see `agy-mcp-bridge/VENDORED-FROM.md`). This **removes task 7.0** (publish claudavity) and the
> multi-repo CI fetch / `CLAUDAVITY_RO_PAT` — CI is now a **single checkout**. Build order is **7.3 ✅ → 7.8 →
> 7.1 → 7.2**. The `.env` secret boundary is *stronger* under vendoring: the live key is never copied (only
> `.env.example`), and an `agy-mcp-bridge/.gitignore` guards a future `uv sync` from committing it.
> **Concrete symbols the plan may now reference (no longer speculative):**
> - **`clavity curate-commit`** — the stdin write verb (atomic header + `.sha256` sidecar). Exists on the branch.
> - **Header path** resolved via **`std::env::var_os("USERPROFILE")` → `HOME`** (NOT the `dirs` crate — the
>   roadmap's earlier "`dirs::home_dir`" wording is superseded; no `dirs` dep was added), default
>   `%USERPROFILE%\.clavity\golden-header.md`, overridable via `CLAVITY_GOLDEN_HEADER`.
> - **`clavity doctor`** already prints a **`golden-hdr`** status line (path + Active/none/disabled + sidecar
>   present/MISSING); 7.1's `doctor` bridge-readiness lines extend the SAME verb (below).
> - **Sidecar** = `<path>.sha256`, 64 lowercase-hex, no trailing newline; classic reads `golden-header.md` per ask.
> - **Separate dotnet-side follow-ups (NOT Spec B scope):** the capstone confirmed dotnet `GoldenHeader.Apply`
>   uses full-Unicode `TrimEnd()` vs classic's canonical ASCII-only set, and dotnet writes the sidecar
>   before-move/non-atomic vs classic's after-move/atomic — both are dotnet *code* parity fixes, tracked apart
>   from packaging (they do not affect the `.iss`/CI contracts here).

> **⚠️ OPTION A RECONCILIATION — SCOPE CORRECTED 2026-06-30 (plan-grounding, agy-consulted, user-approved).**
> Authoring the implementation plan against the **real** `clavity-classic` source revealed that 7.1 below was
> written assuming **dotnet-parity install machinery the classic binary DOES NOT HAVE.** Verified facts:
> classic has **no `install`/`uninstall` CLI verb**; it does **not register an MCP** (it speaks to the
> agentmemory daemon directly over **REST**, and registering the agentmemory MCP is a **manual both-agents**
> step — see `README.md` §1, and note even **dotnet** treats agentmemory as a *separate manual prerequisite*,
> `clavity-dotnet.iss:202`); the **GEMINI.md** pointer is **manual by design** (`src/main.rs:638`); there is
> **no `tmux.conf`** and **no plugin tree / `marketplace.json` / agy-autotrain+commonmemory plugins** for
> classic; the only auto-registration is the **responder skill** that `clavity start` writes to
> `~/.gemini/antigravity-cli/skills/claudavity-responder/` (`install_skill()`, `src/main.rs:639`) — a side
> effect of `start`, not a verb. **DECISION (user 2026-06-30): Option A — minimal/honest installer matching
> classic's actual architecture.** What this CHANGES below (these amendments are AUTHORITATIVE; the original
> 7.1/bridge prose is kept for history but superseded where it conflicts):
> - **No new Rust verbs** (Option B rejected as packaging-driven scope creep — agy + LEAD concur).
> - **The installer does NOT edit the user's agent config files.** agentmemory-MCP registration, the GEMINI.md
>   doorbell pointer, **AND the bridge MCP registration** are all **guided-manual**, surfaced via a loud
>   `README-FIRST.md` + a final-wizard summary page with the exact copy-paste commands/snippets (incl. the
>   directory-anchored `uv --directory "{app}\agy-mcp-bridge" run "…\server.py"` for the bridge). Rationale
>   (agy security/contract round): installer-side PowerShell `ConvertFrom/ConvertTo-Json` round-trips reformat
>   and can corrupt user-owned JSONC config, and surgical uninstall reversal is brittle — too high-risk for an
>   installer. **This DEMOTES the bridge-packaging "installer auto-registers the bridge MCP (directory-anchored,
>   BLOCKER)" requirement to guided-manual** (the one material spec change Option A forces).
> - **DROP** the plugin tree + `marketplace.json` + agy-autotrain/commonmemory `[Tasks]` add-ons (do not exist
>   for classic) and the `tmux.conf` placement (none exists).
> - **The installer's grounded jobs:** `clavity.exe`→`{app}` + HKCU PATH append; set `HKCU\Software\clavity\classic`
>   marker; bidirectional mutual-exclusion refuse; ship the opt-in **bridge add-on**; a loud manual-wiring
>   summary. **Uninstall:** reverse PATH/marker, **tear down the responder skill** at the `~/.gemini/…` path
>   (`[UninstallDelete]` — it is clavity's artifact even though `start` wrote it), the golden-header zombie
>   rename-on-keep, and the bridge `.env` keep/purge prompt. `clavity doctor` extension for install/bridge
>   readiness is **optional Rust polish, not required for 7.1**.
> - **UX:** classic is "bring your own wiring," NOT dotnet's zero-touch — the wizard MUST be loud about the
>   remaining manual steps or dotnet-crossover users will think it failed.

**Goal:** Ship `clavity-classic-setup.exe` so a user installs the Rust **clavity** (classic) variant with **no
Rust toolchain**: the prebuilt binary on PATH, the responder skill auto-placed by `clavity start`, the optional
`delegate_to_antigravity` bridge as a **Python/uv** add-on, and **guided-manual** wiring (agentmemory MCP +
GEMINI.md pointer + bridge MCP) surfaced honestly — matching classic's deliberate manual-wiring architecture
(Option A, user-decided 2026-06-30). Mutually exclusive with the dotnet install in both directions. *(Earlier
"feature parity with dotnet … MCP + GEMINI.md + tmux.conf registered, optional add-ons" framing is superseded by
the Option A reconciliation above.)*

**Why after Spec A:** classic had **no golden-header injection** until 7.3 landed (the `driving-agy` skill that
carried it was deleted). Shipping packaging first would have deployed a product regressed vs. its own past and
vs. dotnet. **7.3 is now DONE** (merged `dea8f87`). Build order is **7.3 ✅ (Spec A) → 7.8 → 7.1 → 7.2**: feature
parity first (locally testable); then the prebuilt artifact (7.8, which stages the **in-branch vendored** bridge
at `agy-mcp-bridge/` — no cross-repo fetch), then the installer authored against the *real* artifacts (7.1), then
release CI only once the installer is proven locally (7.2 — RIGHT-TOOL: ISCC local verify before any remote tag).

**Tech:** Inno Setup 6 (ISCC), GitHub Actions (`windows-latest`), `cargo build --release` (the `clavity` crate
on `clavity-classic`), `uv` (bridge runtime prereq), PowerShell (CI glue). Local gate = ISCC + a silent
install/uninstall smoke, exactly as dotnet.

---

## Component 7.8 — prebuild + stage the Rust `clavity.exe` (build recipe, run locally AND in CI)

The **build recipe** that produces the classic binary + staged bridge so the user never needs `cargo`. It is
**not CI-only**: the SAME recipe runs **locally** to populate `publish/` so 7.1's `clavity-classic.iss` can be
authored and ISCC-verified on this machine (RIGHT-TOOL gate, before any tag), **and** runs inside 7.2's release
workflow to produce the shipped artifact. The `.iss` `[Files]` packs *this* recipe's output (`publish/`). Authoring
7.1 locally therefore requires running 7.8 locally first — but the **vendored `agy-mcp-bridge/` is already in
the checkout**, so staging it is a plain copy into `publish/agy-mcp-bridge/` (no `git clone`, identical locally
and in CI), present before ISCC compiles. (This mirrors dotnet, where `dotnet publish` → ISCC runs locally before the tag
triggers the identical CI build — no circular dependency: the recipe is the shared unit, not a CI-only job.)

- **Source:** the `clavity` crate on the **`clavity-classic` branch** (NOT `main`). The release workflow checks
  out that branch's tag (see 7.2).
- **Build:** `cargo build --release` on `windows-latest` → `target/release/clavity.exe`. Assert the exe exists
  (mirror the dotnet `if (-not (Test-Path …)) { throw }` guard). Strip/verify it is a single self-contained exe
  (Rust statically links the CRT by default with the MSVC toolchain; confirm no extra runtime DLLs are needed —
  if any are, they ship alongside in `[Files]`).
- **Stage for ISCC** at a path the `.iss` resolves relative to `installer/` — mirror dotnet's `..\publish\`
  convention (e.g. stage to `publish/clavity.exe`) so both installers share one layout idiom.
- **Stage the bridge (in-branch source — NO fetch):** the bridge source lives in-branch on
  `clavity-classic` at **`agy-mcp-bridge/`** (the canonical home; `agy-mcp-bridge/VENDORED-FROM.md` records its
  provenance — originated from the now-frozen claudavity prototype @`fae54fa`). Staging is a plain copy of that
  in-branch dir into the ISCC source layout
  (`publish/agy-mcp-bridge/`) — **no second `actions/checkout`, no `git clone`, no cross-repo auth** (the appeal
  of the in-branch source). The staged runtime whitelist (`scripts/build-classic-release.ps1`) is `server.py`,
  `agy_bus.py`, `agy_tmux.py`, `isolation.py`, `telemetry.py`, `SKILL.md` (runtime — injected by `server.py`),
  `pyproject.toml`, `uv.lock`, `start-claudavity.ps1`, `.env.example`, `LICENSE` (the dir also holds dev-only
  tests + `lefthook.yml`, which the recipe does NOT stage)
  and **never the dev `.env`** (not vendored; `agy-mcp-bridge/.gitignore` also blocks a future `uv sync` from
  committing it), so staging cannot leak the secret. The responder skill is NOT under `agy-mcp-bridge/` — it
  already lives at `agy_skills/claudavity-responder/SKILL.md` (embedded in the binary).
- **Cross-platform:** Windows is the shipping target now; Linux/macOS prebuild follows the porting guide
  (`CONTRIBUTING.md`) as a later increment — **out of scope here** (Windows installer only).

> **PLAN-vs-SPEC:** the exact `cargo` invocation, the crate's bin name, and any required side-by-side DLLs are
> verified against the `clavity-classic` branch when the plan is authored — not fabricated here.

---

## Component 7.1 — the Inno installer (`installer/clavity-classic.iss`)

Mirror `clavity-dotnet.iss` structure; the deltas below are what makes it the *classic* installer. Reuse every
proven hardening (in-process PATH scan, no `where` subprocess, suppressible msgboxes, fail-open uninstall).

### Identity & layout
- **New, distinct `AppId` GUID** — MUST differ from the dotnet `{B7E4B2A1-…}` so the two never share an
  uninstall identity. Generate one fresh; freeze it (never change across releases).
- `AppName=clavity-classic`, `#define ExeName "clavity.exe"`, `OutputBaseFilename=clavity-classic-setup`,
  `OutputDir=..\dist`.
- `DefaultDirName={localappdata}\Programs\clavity-classic`, `PrivilegesRequired=lowest`, `x64compatible`,
  `ChangesEnvironment=yes`.
- **`SetupMutex=ClavitySetupMutex`** — reuse the **same** shared mutex name as dotnet (`.iss:34`). This is the
  cross-installer guard that blocks a concurrent classic+dotnet setup race; it only works if both installers
  name it identically.

### Files
- `Source: "..\publish\clavity.exe"; DestDir: "{app}"` (+ any required side-by-side DLLs from 7.8).
- The agy-driving plugin tree + marketplace manifest for the **classic** variant (the `clavity-classic`
  driving/pairing skills), shipped under `{app}` the same way dotnet ships its plugin — exact plugin names
  resolved against the `clavity-classic` branch in the plan.
- Optional add-ons **agy-autotrain** + **commonmemory** shipped (gated by `[Tasks]`), identical to dotnet.
- **The bridge tree** (`Source: "..\publish\agy-mcp-bridge\*"` with `recursesubdirs`) — see *Bridge packaging*
  below; shipped under `{app}\agy-mcp-bridge`, gated by its own `[Tasks]` checkbox, with `.env` / `.venv` /
  caches **excluded**. **This tree MUST include `SKILL.md`** — the sub-agent execution protocol `server.py`
  injects at runtime (`CANONICAL_SKILL`, loaded from its own dir). It is runtime-critical, NOT docs: the bridge
  silently misbehaves without it. The 7.8 recipe already stages it into `publish\agy-mcp-bridge\`; pack that
  staged dir **recursively** so `SKILL.md` (and any future runtime file) cannot be omitted from the installer.

### Tasks / Registry / runtime registration
- `addtopath` (checkedonce) — append `{app}` to HKCU `Path` (the in-place `NeedsAddPath` append-never-prepend
  logic, verbatim from dotnet).
- **Set the mutual-exclusion marker:** write `HKCU\Software\clavity\classic` (a `[Registry]` key) so the
  **already-shipped dotnet installer refuses**. **Exact contract (verified against the oracle):**
  `clavity-dotnet.iss:135` is `Result := RegKeyExists(HKCU, 'Software\clavity\classic')` — it checks **KEY
  EXISTENCE, not a value**. So the classic `[Registry]` entry only has to MATERIALIZE the key (`Root: HKCU;
  Subkey: "Software\clavity\classic"`; a `ValueType: none` entry, or any value, creates it) — no specific
  `ValueName`/`ValueData` is required by the oracle. (An API-contract round flagged a missing value shape; that
  was a false alarm — `RegKeyExists` is satisfied by an empty key. Still, pin it explicitly so the `.iss` author
  knows the contract is key-existence.) Create it with `Flags: uninsdeletekey` so it is removed on uninstall. No
  dotnet-side patch is needed — this is the classic side honoring the existing contract.
- **Register the classic runtime** at `ssPostInstall` (mirror dotnet's `CurStepChanged`): register the
  **agentmemory MCP** with the agent(s), install the GEMINI.md **doorbell** rule, and place **`tmux.conf`**.
  **The doorbell line is a strict wire contract** (API-contract round): it MUST be byte-identical to the literal
  the Rust crate's `ring`/parser listens for — pin it to the crate's **canonical doorbell constant** (the same
  one `clavity ring`'s `$AGY_DOORBELL` default uses), NOT a re-typed string that could drift a character and make
  agy's signal silently ignored. The plan resolves the exact literal from the `clavity-classic` source.
  Surface any failure with a suppressible msgbox + the manual re-run command (no false "Success") — same UX
  contract as dotnet's plugin registration.
  - **MERGE, never blind-overwrite the user's global config (agy security round, 2026-06-30).** `GEMINI.md`
    (the user's global agy instructions) and `tmux.conf` are user-owned files that often already exist with
    bespoke content. The doorbell rule MUST be added as a **marked, idempotent block** (append/merge — re-running
    is a no-op, not a duplicate) — NOT a wholesale file overwrite, which would destroy the user's own agy
    instructions/config. On uninstall, remove **only** clavity's marked block, leaving the rest intact. (Verify
    dotnet does the same; if it blind-overwrites, that's a dotnet parity bug to fix, not a pattern to mirror.)

### Mutual exclusion (classic refuses dotnet) — `[Code]`
Mirror dotnet's `InitializeSetup`, inverted:
- Refuse if **`clavity-ls`** is on PATH (in-process PATHEXT scan for the `clavity-ls` stem — reuse dotnet's
  `ClassicClavityOnPath` scanner, retargeted; **NOT** the bare `clavity` stem, which is *our own* binary).
- Refuse if **dotnet's ARP key** is present (its Inno uninstall key / `DisplayName like "clavity-dotnet*"`),
  i.e. dotnet is installed. Use the same registry-scan shape dotnet uses to find the classic ARP key.
- Each refusal → a `SuppressibleMsgBox(mbCriticalError)` naming how to remove the other variant, then
  `Result := False`. **Live-test BOTH directions before merge** (install classic→dotnet refuses; install
  dotnet→classic refuses).
- `PrepareToInstall` / `InitializeUninstall`: if classic holds a live-session mutex analogous to dotnet's
  `Local\ClavityMcpRunning`, gate on it the same way; otherwise omit (classic's psmux/bus model may have no
  equivalent single-process lock — resolved in the plan against the branch).

### Uninstall
Mirror dotnet: unregister the MCP/doorbell/add-ons (best-effort, fail-open if the exe is gone — dotnet F15),
remove the PATH entry (`RemoveFromUserPath`), delete `HKCU\Software\clavity\classic`, and honor the
keep-vs-purge data prompt (default KEEP). Classic **now reads**
the shared `%USERPROFILE%\.clavity\golden-header.md` (post-7.3, `dea8f87`), so apply the **same zombie-header
rename-to-`.backup` on keep** that dotnet does (`clavity-dotnet.iss:280-293`) so a reinstall doesn't auto-inject
frozen wisdom.

- **Clean up the bridge's post-install artifacts (`[UninstallDelete]`) — informed, split by sensitivity.** Inno's
  uninstaller only removes files it *installed*; the bridge's **`.env` (live `GEMINI_API_KEY`)**, `.venv/`,
  `__pycache__/`, and `.agent/` are all generated *after* install (by the user copying `.env.example` and by
  `uv sync`), so a plain uninstall **strands `{app}\agy-mcp-bridge` as a zombie directory** — including, if left,
  the user's live API key. Handle the two classes differently (user decision 2026-06-30):
  - **`.venv/`, `__pycache__/`, `.agent/` (regenerable, no secret):** `[UninstallDelete]` removes them
    **unconditionally** — they carry no user intent and are trivially rebuilt by `uv sync`.
  - **`.env` (live secret + user-intent-bearing):** deletion is **gated on the existing keep-vs-purge data
    prompt**, default **KEEP**. To avoid keep-vs-purge *dissonance* (a user ticking "keep my data" but the key
    vanishing — the failure mode if `.env` were force-purged), the **prompt enumerates the data classes it
    actually governs** — **always** the **golden-header wisdom**, and — **ONLY when the bridge was installed** —
    the **bridge API key (`.env`)**. **The API-key line MUST be conditional** (gate on
    `WizardIsTaskSelected('install_bridge')` at install time / on `.env` existing at uninstall time): the bridge
    is opt-in default-OFF, so a user who never enabled it must NOT see a prompt threatening to delete an API key
    they never provided (a false alarm). When the bridge IS present, naming "your stored API key" makes the
    choice *informed* (this is what resolves the original zombie concern — *surfacing* the key, not
    force-deleting it). On *purge*, the `.env` and the now-empty `{app}\agy-mcp-bridge` dir are removed; on
    *keep*, the `.env` stays and the uninstall summary states the key was retained. (Note: a normal same-AppId
    in-place **upgrade** does not run the uninstaller, so this prompt only fires on a real uninstall — no
    mid-upgrade key loss.)
  Verify both branches (purge-removes-key, keep-retains-key) in the local uninstall smoke.
- **Remove the responder skill — directive MUST match the install mechanism (no orphan).** B1 places
  `claudavity-responder` in an agy discovery root under `~/.gemini/…`. *If* it is installed via Inno `[Files]`
  (static dest), the uninstaller auto-removes it. *But if* it is placed by `[Code]`/PowerShell at
  `ssPostInstall` (likely, since the exact per-agent discovery path is resolved at runtime), **Inno has no record
  of it and the uninstaller will orphan it.** The plan MUST therefore pair any dynamic skill-copy with an
  explicit teardown — a `[UninstallDelete]` entry (or `[Code]` `usUninstall` cleanup) targeting the **same
  resolved `~/.gemini/…` path** — and the local uninstall smoke asserts the skill dir is gone. (Same rule applies
  to any other artifact placed dynamically outside `{app}`.)

---

## Bridge packaging (the `delegate_to_antigravity` runtime) — Python/uv prerequisite

**Decision (user, 2026-06-30):** ship the bridge as an **opt-in add-on** that **declares a Python/uv
prerequisite** — do NOT bundle a Python runtime, do NOT PyInstaller, do NOT rewrite in Rust. Rationale (survey
+ web-verified 2026-06-30): the bridge (`claudavity`) depends on the **`google-antigravity` SDK**, which is
**Python-only** (no Go/C# drop-in exists) and drives a **bundled Go harness over a protobuf WebSocket**, so a
native port is real rewrite work out of scope for shipping. uv is the fastest, least-leaky path.

> **agy on record (2026-06-29):** recommended PyInstaller over uv-prereq, calling uv-prereq a "leaky
> abstraction that will lead to user friction." **User overrode** to uv-prereq (their call). agy's *valid*
> sub-findings from that review are folded in below: the `.env` secret-leak (→ hard exclusion + CI assertion),
> the responder-skill omission (→ shipped), and the elevation/profile hazard (→ mitigated by
> `PrivilegesRequired=lowest` + HKCU-only registration; the installer never runs elevated, so the per-user
> `~/.claude.json` / agent config is written to the *executing* user's profile, not an Administrator profile).

- **Source location — the bridge source lives CANONICALLY in-branch at `agy-mcp-bridge/` on `clavity-classic`
  (user decision 2026-06-30).** `agy-mcp-bridge/` (committed `b795c4b`) **IS** the bridge source and its active
  development home. It originated as a snapshot of the **claudavity prototype** (`~/Development/Rust/claudavity`
  @ `fae54fa`), which is now **frozen/deprecated and kept only for reference** — it is NOT an upstream to track.
  Provenance is recorded in `agy-mcp-bridge/VENDORED-FROM.md`. CI/ISCC stage straight from this in-branch dir —
  **single `actions/checkout`, no cross-repo fetch, no auth, no `BRIDGE_VERSION` / `actions/checkout
  repository:`**. **There is no upstream, therefore no drift and no re-sync:** bridge bugs are fixed **here**, in
  `agy-mcp-bridge/`, like any other in-repo code, and deps are managed here (`uv lock` updates `uv.lock` normally
  when `pyproject.toml` changes). Bridge changes ride a `clavity-classic-v*` release with the rest of the crate.
  **Secret boundary:** the dev `.env` was never copied (only `.env.example`), and `agy-mcp-bridge/.gitignore`
  blocks `uv sync` / local bridge runs from ever committing the secret OR the regenerable runtime artifacts —
  it lists `.env`, `.venv/`, `__pycache__/`, `*.pyc`, `.agent/`, `.pytest_cache/`, `.ruff_cache/`,
  `.playwright-cli/`, `.serena/`, `server.log` (already committed) — so neither the bridge `.env` nor dev cruft
  can land in the Rust repo.
  - **No task 7.0.** With the source in-branch there is **no "publish claudavity" precondition** — the earlier
    (iii) plan's outward-facing 7.0 (push claudavity to GitHub + pinned tag + read access) is **dropped**. Build
    order is **7.3 ✅ → 7.8 → 7.1 → 7.2**.
  - History (superseded): an interim plan (iii) kept claudavity as a separate published repo with CI fetching a
    pinned SHA; a brief intermediate framing kept claudavity as the *upstream* single-source-of-truth with the
    in-branch dir a re-synced copy. Both are **superseded** — `agy-mcp-bridge/` is simply the canonical home now,
    which removes the drift concern entirely (there is no second tree to diverge). The earlier alternatives
    (git-submodule; the separate-repo fetch) were set aside for CI/auth friction with no remaining upside.

- **What ships** (under `{app}\agy-mcp-bridge`, gated by an `install_bridge` `[Tasks]` checkbox, default OFF):
  the bridge sources (`server.py`, `agy_tmux.py`, `agy_bus.py`, `isolation.py`, `telemetry.py`,
  `pyproject.toml`, `uv.lock`), **`SKILL.md`** (a RUNTIME file — `server.py` loads it as `CANONICAL_SKILL` and
  injects it into every spawned sub-agent; it MUST ship beside `server.py`), `start-claudavity.ps1`, and
  **`.env.example`**. (The dev test suite + `lefthook.yml` live in `agy-mcp-bridge/` but are NOT shipped.)
- **The agy-side responder skill — installed into a REAL agy skill-discovery root, NOT under `{app}`.** The
  responder (`claudavity-responder`) is required for the bridge round-trip (the agy peer runs it), but agy does
  **not** auto-discover skills under an arbitrary `{app}\…\agy_skills\` directory. **Verified on this machine
  (2026-06-30):** agy's live skill roots are `~/.gemini/config/plugins/<plugin>/skills/`, `~/.gemini/skills/`,
  `~/.gemini/antigravity-cli/skills/`, and `~/.gemini/extensions/…/skills/` — and the *non-existent* paths agy's
  bus review named (`~/.gemini/config/skills`, `skills.json`) are NOT roots. The installer MUST place the
  responder where agy will load it, mirroring how the **clavity-dotnet** agy-facing skill ships today (verified
  at `~/.gemini/config/plugins/clavity-dotnet/skills/`): deliver `claudavity-responder` as/into a plugin under
  `~/.gemini/config/plugins/<classic-plugin>/skills/` (or `~/.gemini/skills/claudavity-responder/`). Exact
  mechanism (which agent profile, copy vs. plugin-manifest registration) is resolved in the plan against the
  classic branch's existing plugin-delivery code — but the **placement contract is fixed: a real discovery
  root, not `{app}`.** Remove it on uninstall.
- **What MUST NOT ship (secret boundary):** the dev **`.env`** (holds `GEMINI_API_KEY`), `.venv/`,
  `__pycache__/`, `.agent/` (telemetry.db, worktrees, server.log), `.ruff_cache`, `.serena`, `.playwright-cli`.
  Enforce with explicit Inno `[Files]` `Excludes: ".env,.venv,__pycache__,.agent,*.pyc"` AND a stage-time copy
  filter in 7.8 that whitelists only the files above. The `.env` leak is the highest-severity packaging risk —
  the spec freezes it as a hard exclusion + a CI assertion (see 7.2 smoke).
- **Task label states the VALUE, not just the cost (UX round):** the `install_bridge` `[Tasks]` label/description
  must first say **what the bridge gives you** — *autonomous code-delegation: let Claude hand off a coding task
  for Antigravity to do in an isolated worktree (`delegate_to_antigravity`)* — THEN the prerequisite. A label that
  states only "needs Python/uv" with no value proposition makes operators skip a major capability out of
  confusion (they can't tell what they'd be enabling). Default-OFF is right, but the choice must be *informed*.
- **Prerequisite handling:** the bridge `[Tasks]` checkbox label states plainly it needs **Python ≥3.10 + uv**;
  at `ssPostInstall`, if `install_bridge` is ticked, detect `uv` on PATH (in-process, no subprocess hang risk)
  and:
  - present, → run **`uv sync --frozen`** in `{app}\agy-mcp-bridge` to materialize `.venv` from `uv.lock`
    (best-effort; surface failure with the manual command, never block the install). **`--frozen` is required:**
    a bare `uv sync` may silently *re-resolve* and fetch newer PyPI packages if `uv.lock` is out of sync with
    `pyproject.toml`, defeating the release-vetted pinning and opening a supply-chain hole at install time;
    `--frozen` uses the lockfile exactly and errors instead of drifting (the same flag applies to the deferred
    warmup case below);
  - absent, → a suppressible msgbox: the bridge is installed but **inactive** until the user installs uv
    (`https://docs.astral.sh/uv/`) **and runs `uv sync` in `{app}\agy-mcp-bridge` BEFORE first use** — be
    honest, mirror dotnet's commonmemory "registered but needs agentmemory" honesty pattern
    (`clavity-dotnet.iss:200-204`). **Why the explicit `uv sync` step matters (cold-start timeout):** the MCP
    server is registered as `uv run … server.py`. If uv arrives *after* install and the user never runs
    `uv sync`, the **first** MCP tool call triggers an implicit cold sync — downloading the Python toolchain +
    all deps — which routinely **exceeds the MCP startup/timeout window** and fails cryptically (the agent sees
    a dead tool, not a "still downloading" signal). So the warmup is a required step, not a nicety: the msgbox
    states it, `.env.example`/README repeat it, and the install-time `uv sync` (the *present* branch above) is
    what spares the on-time installer from ever hitting this. (A future hardening option — wrap the MCP launch
    in a `uv sync && uv run` warmup script so the first call self-heals — is noted for the plan, not required
    for 7.1.)
- **First-run secret setup:** the user copies `.env.example` → `.env` and pastes their `GEMINI_API_KEY`
  (the SDK does NOT reuse agy's OAuth — documented in `.env.example`). The installer does NOT prompt for or
  store the key (no secret in the installer or registry).
- **Upgrade-with-deselection cleanup (UX round — zombie-state).** Inno does NOT delete previously-installed
  files when a task is **unchecked on an in-place upgrade** — it just skips updating them. So an operator who
  upgrades and unticks `install_bridge` (mental model: "I unchecked it, so it's gone") is left with a **zombie
  `{app}\agy-mcp-bridge` tree + an orphaned bridge MCP registration** that now points at maybe-stale files. The
  `[Code]` MUST detect bridge **deselection on upgrade** (task previously installed, now unchecked) and actively
  tear it down — remove the bridge dir (honoring the same `.env` keep/purge prompt) and **unregister the bridge
  MCP** — so the unchecked state actually means uninstalled. (The regenerable `.venv`/caches go unconditionally.)
- **First-run DISCOVERABILITY (don't strand the operator at a closed wizard).** The bridge add-on is inert until
  the user does an ordered set of manual steps (install uv → `uv sync --frozen` → copy `.env.example`→`.env` →
  paste `GEMINI_API_KEY`), and after the wizard closes they would otherwise have to *hunt* for
  `{app}\agy-mcp-bridge`. So: (1) the final wizard page offers an **"Open the bridge configuration folder"**
  checkbox (Inno `[Run]` `Flags: postinstall shellexec skipifsilent` → `explorer.exe {app}\agy-mcp-bridge`)
  — **gated `Tasks: install_bridge`** (UX round): a user who left the bridge OFF must NOT see this checkbox; if
  shown+checked it opens a non-existent/empty folder; (2) the bridge `[Tasks]`/inactive msgboxes print the
  **absolute `{app}\agy-mcp-bridge` path** and the **ordered step list**; (3) a short **`README-FIRST.md`** ships
  in the bridge dir with the same steps. **The steps must include HOW to open a terminal in that folder** (the
  `[Run]` checkbox opens it in Explorer — a GUI window, not a shell — so "run `uv sync`" is a dead end without
  it; e.g. "type `cmd` in the Explorer address bar and press Enter", or Shift+right-click → *Open in Terminal*).
  **README-FIRST must also (UX round):** (a) give the exact `.env` setup as a copy command —
  `Copy-Item .env.example .env` — NOT "rename in Explorer" (Explorer blocks creating dot-leading filenames); and
  (b) **warn NOT to run `start-claudavity.ps1` manually** — the MCP server is launched in the background by the
  host agent (`uv … run server.py`); running the script by hand is a false affordance that just hangs the
  terminal. *(If `start-claudavity.ps1` has no operator-facing purpose, the plan may instead drop it from the
  shipped `[Files]` whitelist — resolve its role against the bridge code.)* The goal: the operator never meets a
  silently-dead MCP tool later because they didn't know a setup step existed.
- **MCP registration (MUST be gated on `install_bridge`):** register the bridge as an MCP server with the
  agent(s) the same mechanism the runtime registration uses, pointing at `uv run … server.py` in
  `{app}\agy-mcp-bridge`. **DIRECTORY-ANCHOR the launch command (API-contract round, BLOCKER):** an MCP client
  does NOT guarantee the server's `cwd` — it typically launches in the user's active workspace. A bare
  `uv run … server.py` would then look for `pyproject.toml`/`.venv` in the WRONG dir (wrong/no Python env) and
  miss `{app}\agy-mcp-bridge\.env` (no `GEMINI_API_KEY` loaded) — a silent runtime failure. So register it with
  an **absolute** working dir + script path, e.g. `uv --directory "{app}\agy-mcp-bridge" run "{app}\agy-mcp-bridge\server.py"`,
  and `server.py` MUST load `.env` (and `SKILL.md`) **relative to `__file__`, never `cwd`** (SKILL.md already is;
  confirm `.env`/`load_dotenv` is too — a bridge-code check). **This registration fires ONLY when the `install_bridge` task is selected** — the
  bridge is opt-in default-OFF, so registering it unconditionally would inject a `delegate_to_antigravity` tool
  whose `server.py` was never installed, giving opted-out users a dead/cryptically-failing MCP tool. Gate it
  (and remove the registration on uninstall). Exact command resolved in the plan against `server.py`'s entry
  contract.
- **State discoverability via `clavity doctor` (extend the existing verb).** So the operator can confirm "did it
  work?" without launching an agent and waiting for a downstream failure, `clavity doctor` (Spec A extends it for
  golden-header status) ALSO reports the **install/runtime state**: which variant owns `HKCU\Software\clavity\classic`
  (and whether dotnet's marker/ARP is present), and **bridge readiness** — `uv` on PATH, `.venv` present/synced,
  `.env` present (key set, **never printed**), and the MCP registration in place. Each line is a clear OK / NEEDS-X
  with the remediation. This is the single "is my install healthy?" surface; failure is reported, not silent.

> Migrating classic→dotnet still regresses `delegate_to_antigravity` (dotnet has no autonomous code-delegation,
> only `agy_ask` consults) — a documented Non-goal (ROADMAP). The bridge add-on keeps it available for classic.

---

## Component 7.2 — `release-clavity-classic.yml` (mirror `release-clavity-dotnet.yml`)

Release-only CI (no continuous build on `main`; the classic gate is `cargo test` local + this tag job).

- **Trigger:** `push: tags: ['clavity-classic-v*']` (distinct from dotnet's `clavity-dotnet-v*`/`v*` — do NOT
  reuse the bare `v*` glob, which dotnet already claims). `permissions: contents: write`.
- **Checkout (single repo):** one `actions/checkout` of the **`clavity-classic`** tag — the Rust crate **and**
  the vendored bridge at `agy-mcp-bridge/` arrive together (the whole point of the vendor choice). **No second
  checkout, no cross-repo auth, no PAT** — the default `GITHUB_TOKEN` suffices. The workflow file lives on
  whatever branch CI reads it from (resolved in the plan); the sources it builds are the classic-branch crate +
  its in-tree `agy-mcp-bridge/`.
- **Version triangulation (assert BEFORE building):** the classic version lives in four places — the triggering
  git tag `clavity-classic-vX.Y.Z`, `Cargo.toml`, the `.iss` `AppVersion`, and `plugin.json`. A first CI step
  **parses the tag and asserts all four match** (hard-fail the job on mismatch). Without this, CI could publish a
  `v0.2.0` release carrying a `v0.1.0` binary/installer — downgrade-guard and cache-poisoning hazard. (dotnet
  bumps these by hand today; this assertion is a classic improvement worth backporting.)
  - **Also fold in the vendored bridge:** `agy-mcp-bridge/pyproject.toml`'s `version` is now a co-released
    in-branch component, so add it to the same parity assert (a 5th place) so the bridge can't silently drift
    from the release. *Severity note (LEAD vs agy):* agy rated this MAJOR; I rate it **consistency-hygiene, not
    correctness** — nothing consumes that version (the bridge isn't published to PyPI, it runs via `uv run
    server.py`), so a mismatch breaks nothing functionally. It's cheap and matches the spec's own triangulation
    rigor, so include it; just bump `pyproject.toml` with the others each release.
- **Pinned, reproducible toolchains (local↔CI parity):** do NOT float toolchains. Pin the Rust toolchain
  (`rust-toolchain.toml` on the classic branch), build with **`cargo build --release --locked`** (enforce
  `Cargo.lock`, no silent dep bump), and **pin the Inno Setup version** (`choco install innosetup --version=<X>`,
  not latest). This keeps the local ISCC gate and CI building the *same* installer and makes a tag rebuildable
  later (functionally reproducible — not claiming bit-identical, which needs deeper determinism work). **Pin the
  runner to a STATIC OS image (`runs-on: windows-2022`), NOT `windows-latest`** (agy release-eng round): the
  rolling image silently updates MSVC / linker / Windows SDK, so rebuilding a historic tag months later would use
  a different build environment and break the reproducibility claim. Match the local Windows dev box's class.
- **Build + package steps:** 7.8 recipe (`cargo build --release --locked` + stage the in-branch vendored
  `agy-mcp-bridge/` → `publish/`) → `cargo test` gate → pinned ISCC compiles `installer\clavity-classic.iss`
  (assert `dist\clavity-classic-setup.exe`) → SHA-256 companion in the **exact** `"<hash>  clavity-classic-setup.exe"`
  format.
- **Smokes are BLOCKING gates, not `continue-on-error` (regression must NOT ship):** the earlier draft marked the
  smokes `continue-on-error: true` to dodge runner hangs — that is wrong: it would let a catastrophic installer
  regression (crash, broken PATH, **or a `.env`/secret leak**) be treated as success and published. Instead each
  smoke is a **hard gate** bounded by `timeout-minutes` (so a *hang* fails fast rather than blocking forever):
  - **install/uninstall lifecycle** (silent) — install succeeds, files/PATH/marker land, uninstall reverses them. **BLOCKING.**
  - **mutual-exclusion** — seed a fake `clavity-ls` on PATH or the dotnet ARP key; assert the installer **refuses**. **BLOCKING.**
  - **`.env`-exclusion** — after a silent install with the bridge task ticked, assert `{app}\agy-mcp-bridge\.env`
    does **NOT** exist. **BLOCKING** — the secret-boundary regression guard is the *last* thing that should be advisory.
  - Only genuinely **agent-dependent** steps (MCP/doorbell registration, which no-op on an agent-less runner) are
    tolerant/skipped — and they assert "skipped because no agent," not silent success.
  - **Coverage gap (documented):** a silent CI install exercises only the **default** keep-vs-purge `.env` branch
    (KEEP) and cannot drive the interactive dialog. The **local manual uninstall gate (RIGHT-TOOL, pre-tag) MUST
    exercise BOTH `.env` branches (keep-retains-key, purge-removes-key)** and PATH-append idempotency on reinstall
    — these are not CI-coverable and are the local gate's responsibility.
- **Publish:** first **`actions/upload-artifact`** the `setup.exe` + `.sha256` (so a transient GitHub Release
  API failure doesn't lose the built assets with the ephemeral runner — operators can recover/inspect without a
  non-deterministic rebuild), THEN `softprops/action-gh-release@v2` attaches both to one release entity
  (multi-asset publish is atomic — no exe-without-hash window).
- **Pipeline resilience (agy release-eng round, 2026-06-30):**
  - **`concurrency` guard:** set `concurrency: { group: release-${{ github.ref }}, cancel-in-progress: true }`.
    A deleted-and-force-pushed tag (common, to fix a late typo) otherwise spawns two jobs racing on the publish
    step — the `.exe` from one runner and the `.sha256` from another — silently breaking the atomic-publish claim.
  - **Tag-lineage guard (wrong-branch):** version triangulation catches a version mismatch but NOT a
    `clavity-classic-v*` tag accidentally pushed onto **`main`** (the dotnet branch) with a coinciding version —
    CI would then build the wrong code. A fast pre-flight step MUST assert the tag's commit is on / an ancestor
    of **`clavity-classic`** (`git merge-base --is-ancestor <tag> clavity-classic`); hard-fail otherwise.
  - **Yank / rollback procedure (how to UN-ship):** there is no `cargo yank` for a standalone GitHub binary
    release, so define the manual rollback for a catastrophic-bad installer: mark the GitHub Release as
    **deleted/draft**, destroy the tag, and **roll FORWARD** with a patched `clavity-classic-vX.Y.(Z+1)` — never
    silently leave a known-bad `setup.exe` downloadable while a fix is authored. (dotnet likely has the same gap;
    backport.)
- **Unsigned** (owner decision; SmartScreen documented), same as dotnet.

---

## Security / threat model

- **Secret boundary (bridge `.env`)** — the only new high-severity surface, guarded at **three** points: (1) it
  is gitignored upstream and **was never vendored** into `agy-mcp-bridge/` (only `.env.example` was copied;
  `agy-mcp-bridge/.gitignore` also blocks a future `uv sync` from committing it); (2) **hard-excluded** from
  `[Files]` + the stage-time whitelist, with a CI smoke asserting its absence in the installed tree; (3) on
  uninstall, any post-install `.env` the *user* created is surfaced by an **informed keep-vs-purge prompt** (the
  prompt names the stored API key; default KEEP) so it is never *silently* stranded — the user knowingly keeps or
  purges it (see Uninstall). Only `.env.example` ships. The installer never reads/stores the key.
- **Runtime secret hygiene (bridge key never logged)** — the bridge runs with the live `GEMINI_API_KEY` in
  memory; standard Python tracebacks, a `server.log`, telemetry payloads, or the agent transcript can casually
  capture environment variables and write the key to disk. The bridge MUST **mask/scrub `GEMINI_API_KEY` from
  all logs, crash dumps, exception output, and telemetry**.
  - **Sub-agent environment inheritance (HIGH — agy security round, 2026-06-30):** `delegate_to_antigravity`
    spawns a headless sub-agent in a worktree, and that child process (plus every shell command IT runs)
    **inherits `server.py`'s environment**, which holds the live `GEMINI_API_KEY`. A delegated task on a
    malicious repo (a poisoned build step) or a prompt-injected master could exfiltrate the key, or simply have
    the sub-agent `cat` the `.env` — masking *logs* does not protect the live execution shell (a confused-deputy
    escalation). **The bridge MUST strip `GEMINI_API_KEY` (and any other host secret) from the environment it
    passes to the spawned sub-agent** — the sub-agent uses its own agy auth and has no need for the bridge's
    key. This is a **bridge-code hardening** in `agy-mcp-bridge/server.py` (the spawn-env construction);
    surfaced here because the installer ships the capability. The fix lives in the bridge source — now
    maintained in-tree at `agy-mcp-bridge/` — so it is an ordinary in-repo code requirement verified there (no
    separate upstream). It is restated here as the packaging-side secret-boundary requirement: the
  installer ships the bridge, so it owns surfacing the requirement.
- **Mutual exclusion** — bidirectional and contract-bound: classic SETS `HKCU\Software\clavity\classic` (dotnet
  reads it) and REFUSES on `clavity-ls`/dotnet-ARP; shared `SetupMutex` blocks the concurrent-setup race.
  **Residual (deliberate-bypass, accepted):** the guard is *install-time* (PATH/ARP scan). A user who actively
  circumvents (rename the dotnet dir → install classic → restore dotnet) could co-install both and race the same
  bus. The accidental case is covered; the deliberate case is out of the primary threat model. **Optional
  defense-in-depth follow-up (both variants):** have the runtime binary re-check the opposing variant's HKCU
  marker at startup and refuse — noted, not required for 7.1 (dotnet has no such cross-variant runtime check
  today either; parity, not regression).
- **PATH hygiene** — append-never-prepend (verbatim dotnet `NeedsAddPath`), removed on uninstall.
- **Same-user boundary** — `%USERPROFILE%`/`{localappdata}`-scoped, per-user (HKCU), unsigned; same-user TOCTOU
  accepted (inherited from the dotnet threat model, unchanged).
- **uv prerequisite** — the bridge runs user-supplied Python in the user's own profile; no elevation, no
  system-wide install. `uv sync` resolves from the pinned `uv.lock` (no floating deps at install time).

---

## Testing

- **Local (the gate — RIGHT-TOOL):** ISCC compiles `clavity-classic.iss`; a manual silent install/uninstall on
  this machine asserts the full file/PATH/marker/ARP lifecycle AND both mutual-exclusion directions AND the
  `.env` absence — BEFORE any tag is pushed. No remote-CI iteration to find installer bugs (remote-iteration
  breaker).
- **CI smokes** (7.2 above): install/uninstall lifecycle, mutual-exclusion refusal, `.env`-exclusion — **BLOCKING
  gates** (a real regression fails the job and BLOCKS publish), each bounded by `timeout-minutes` so a runner
  *hang* fails fast instead of blocking forever. Only the agent-dependent MCP/doorbell registration steps are
  tolerant (and assert "skipped — no agent," not silent success). CI's silent install covers only the default
  (KEEP) `.env` branch — the interactive keep/purge branches + PATH-append idempotency are the **local** gate's job.
- **Classic unit/integration:** `cargo test --all --features test-fakes` (the crate's existing gate) stays green
  on the `clavity-classic` branch — unchanged by packaging.

---

## Out of scope (this spec)

- The Rust golden-header **injection** (`clavity curate-commit` + per-ask prepend) — that is **Spec A** (7.3),
  **DONE** (merged `dea8f87`); it landed before this and is the prerequisite Spec B builds on.
- Linux/macOS installers / prebuild — Windows only here; cross-platform follows the porting guide later.
- A native (Rust/Go) bridge port — explicitly rejected (Python-only SDK); uv-prereq is the decided runtime.
- Golden-header tamper-detection (7.4), `--restart-agy` (7.7), dynamic model resolution — separate backlog items.
- Any change to the dotnet installer — it is the frozen oracle; the marker/mutex/sha256 contracts conform to it.
