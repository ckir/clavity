# clavity ROADMAP

> **Live roadmap — reconciled 2026-06-30.** This file is the single forward-looking source of truth.
> It supersedes the original 2026-06-16 driving-session roadmap (now folded into **§ Shipped — history**
> below). Detail for each item lives in `docs/superpowers/specs/` + `docs/superpowers/plans/`; this file
> tracks **what is done** and **what is next, in order**.

---

## What clavity is now

clavity pairs **Claude** with a live **Antigravity (`agy`)** peer. It ships in **two variants**:

- **clavity-dotnet** — .NET 10, binary **`clavity-ls`**, drives agy over its **Language Server** (gRPC/h2c)
  via the `agy_look` / `agy_status` / `agy_ask` MCP tools. **SHIPPED**: one-command Windows installer
  (`clavity-dotnet-setup.exe`), Add/Remove-Programs uninstall, release CI. Current release **v0.1.7**.
- **clavity-classic** — Rust, binary **`clavity`**, drives agy over **psmux** + the **agentmemory signal bus**
  (`clavity ask` / `await-reply` / `ping`, `delegate_to_antigravity`). Source lives on the **`clavity-classic`
  branch**. Today it installs via `cargo install --git … --branch clavity-classic` (needs the Rust toolchain).
  **An installer for it is the #1 forward item.**

Optional opt-in add-ons (installer checkboxes): **agy-autotrain** (the agy-driving-perfection learning loop) and
**commonmemory** (shared Claude⇄agy notebook over agentmemory).

The two variants are **mutually exclusive** on a machine (the installers refuse to co-install).

---

## ✅ Shipped

### clavity-dotnet — releases
- **v0.1.0–v0.1.4** — packaging: Inno installer + PowerShell chooser + release CI + silent install/uninstall
  CI smoke; mutual-exclusion guard; per-user (`%LOCALAPPDATA%` + HKCU), unsigned. (v0.1.1–v0.1.4 were
  installer-hang fixes culminating in a fully CI-green silent lifecycle — the lesson that birthed local-ISCC
  verification, now standard.)
- **v0.1.5** — agy-tab launch fix: `wt` split `;` in the inline pwsh script → base64 `pwsh -EncodedCommand`.
- **v0.1.6** — `agy_ask`/`agy_look` decode agy's **reply prose** (modeled `CascadeAssistantOutput`, trajectory
  field 20.1; `BoundedView` reads assistant text, not just user input).
- **v0.1.7** — `agy_ask` returns agy's **full reply**: differentiated view caps (LOOK keeps the 8 KB/1 KB glance;
  ASK uses 32 KB total / 16 KB per-step) + **newest-first fill** so a noisy delta can't re-truncate the answer.
  (Closed the 1 000-char/step `BoundedView` cap that truncated long design consults.)

### clavity-dotnet — engineering increments (all merged to `main`)
- **.NET port, increment 1 (T1–T10)** — LS discovery, h2c framing (live-proven + CI-pinned), `LsClient`,
  the `agy_look`/`agy_status`/`agy_ask` MCP surface, live write path (model-id reverse-engineered).
- **Multi-session pairing** — N independent Claude⇄agy pairs in a shared agy tree; per-session `--log-file`→port
  discovery, identity via `CLAVITY_AGY_LOG`/`CLAVITY_SESSION_ID`, convId from the LS (ConversationLocator retired),
  log retention, ModalGuard. Live-proven with two concurrent agy instances.
- **Product-structure refactors** — golden-header injection moved skill→binary (`clavity-ls curate-commit` writes,
  the binary reads+prepends per ask); anti-misfire driving protocol merged into the core driving skills;
  `driving-agy` deleted; bundled `clavity-dotnet` plugin + marketplace entry.
- **RIGHT-TOOL tooling discipline** — declarative `.claude/recommended-tools.json` + SessionStart presence-check
  hook + remote-iteration circuit-breaker (ISCC declared; local installer verification is now standard).

---

## ▶ Forward backlog (in priority order)

### 1. clavity-classic installer — **#1 PRIORITY** (Option A: full shippable, dotnet parity)

Ship `clavity-classic-setup.exe` so a user installs classic with **no Rust toolchain**, with feature parity to
dotnet. Decided scope: **Option A (full shippable artifact)**; build order **7.3 → 7.8 → 7.1 → 7.2** (feature
parity first, locally testable; then the prebuilt artifact; then the installer authored against the *real* CI
artifacts; then release CI only after the installer is proven locally). agy-consulted + user-approved 2026-06-30.

- **7.3 — Rust golden-header injection.** Mirror the dotnet `GoldenHeader` in the Rust crate (resolve
  `%USERPROFILE%\.clavity\golden-header.md` via `dirs::home_dir`, read+cap+prepend in `clavity ask`; add
  `clavity curate-commit`). **Ship-blocker:** `driving-agy` was deleted, so classic has *no* injection until this
  lands. The Rust source is on the `clavity-classic` branch → author against that branch (PLAN-vs-SPEC: line-level
  plan only against code you can read there).
- **7.8 — prebuild the Rust `clavity.exe` on CI.** A release-CI job `cargo build --release` on a Windows runner
  (then Linux/macOS per the porting guide), published as a Release asset — removes the user-side Rust requirement
  and is the build prerequisite for 7.1/7.2.
- **7.1 — the Inno installer.** Ship the prebuilt binary + register the agentmemory MCP, the GEMINI.md doorbell
  rule, and `tmux.conf` (+ the **agy-mcp-bridge** *only if* the bridge fork below resolves to include it — it is
  NOT a fixed 7.1 requirement); slot into the existing chooser. **Mutual exclusion:** the released dotnet installer
  (v0.1.7) ALREADY detects classic — `InitializeSetup` refuses if the `clavity` stem is on PATH (`ClassicClavityOnPath`)
  or `HKCU\Software\clavity\classic` is set (`ClassicRegistered`) — so 7.1 needs **no dotnet-side patch**: it must
  (a) put `clavity.exe` on PATH and (b) SET `HKCU\Software\clavity\classic` so that existing detection fires, and
  itself refuse if dotnet's ARP key / `clavity-ls` is present. Live-test BOTH directions before merge.
  AGY-AFTER-audited constraints (packaging plan Task 7.1).
- **7.2 — `clavity-classic-setup.exe` release CI** (mirror `release-clavity-dotnet.yml`).

- **OPEN FORK — agy-mcp-bridge runtime (`delegate_to_antigravity`).** The bridge is `claudavity/server.py` (uv/
  Python), so a clean install needs a runtime. Options surfaced (agy-consulted 2026-06-30): **(a) defer the bridge**
  and ship the core installer without it (treat it as a later opt-in add-on — post-migration it's the legacy/
  optional feature); **(b) port the bridge to a small Rust binary** (native parity, no Python/PyInstaller — agy's
  idea; real porting work); **(c) PyInstaller standalone exe** (no rewrite; PyInstaller flakiness risk);
  **(d) declare a Python/uv prerequisite** (leaky, fastest). **Decision deferred** to the classic-installer design
  session, but **MUST be resolved BEFORE 7.1 is authored** — Inno can only pack what the fork settles (the bridge's
  presence in 7.1 is contingent on it). Also required if the bridge ships: the agy-side `claudavity-responder`
  skill + the psmux/bus substrate, and NO dev-`.env` leak.

### 2. `clavity --restart-agy` (classic) — 7.7
Agy-only restart: tear down + relaunch ONLY the agy psmux session under the same `--session`, WITHOUT co-launching
a new Claude (today only `clavity start` relaunches, which orphans the driving session). Re-run agy's exact launch
+ confirm readiness via a `ping`. Surfaced 2026-06-29 when an agy MCP hang forced a full teardown mid-session.

### 3. Golden-header tamper-detection — 7.4
Compare `golden-header.md` to its `.sha256` sidecar at read-time; LOUD plain-English warning on external change,
subtle active-marker otherwise. Honest threat model: the sidecar defends accidental corruption / naive hand-edits
only (same-user adversary rewrites both — the accepted same-user boundary). Staged after the injection MVP.

### 4. Dynamic send-model resolution (dotnet) — T10 follow-up
`AgyView` hard-codes the send model id (`MODEL_GEMINI_3_1_PRO_HIGH = 1037`); the enum ints are version-specific to
the running agy. Resolve dynamically (`GetAvailableModels` `default_agent_model_id`, or the conversation's own
model) so a model/version change can't break the live write. User-accepted as deferred (pre-1.0 scope; the paired
agy uses its default model).

### 5. Packaging verifications — 7.5 / 7.6
- **7.5** — confirm the dual-plugin format scopes `clavity-ls-driving` to Claude and `clavity-ls-pairing` to agy
  (else rely on contextual invocation + document).
- **7.6** — confirm Claude/agy don't auto-update a locally path-installed plugin away from the version-pinned
  `{app}` binary.

### Stretch (not planned)
- **NativeAOT** — ruled infeasible with the current gRPC/protobuf/MCP-reflection stack; revisit only if that stack
  changes.

---

## Non-goals / accepted limitations

- **True mid-turn push to Claude Code** — none exists; long-poll `await-reply` / a bounded idle-wait is the
  pragmatic equivalent. Don't chase push.
- **Signed installers** — shipped unsigned (owner decision); SmartScreen warning documented.
- **Release-asset integrity** — companion `.sha256` + immutable pinned tag + GitHub/TLS trust; a fully compromised
  Release rewrites both (documented, accepted).
- **Same-user trust boundary** — `%USERPROFILE%`-scoped data; same-user TOCTOU accepted (cross-user/elevation
  mitigated). DPAPI/signing out of scope for this threat model.
- **Migrating classic → dotnet regresses `delegate_to_antigravity`** — dotnet provides `agy_ask` (consults), not
  autonomous code-delegation. Valid only while clavity-classic stays a maintained variant (which item 1 assumes).
- **No continuous .NET build/test CI** on `main` — CI here is **release-only**; the .NET gate stays local
  (`dotnet build -c Release` + `dotnet test --filter "Category!=LiveAgy"`). `ci.yml` remains Rust/`main`-only.

---

## Shipped — history (original 2026-06-16 roadmap)

> Provenance: authored from a real driving session (Claude driving `agy` through clavity, 2026-06-16) — 6
> review/red-team round-trips. It defined **Theme 1 (first-class blocking round-trips)** and **Theme 2 (protocol &
> docs hygiene)**, both **COMPLETE 2026-06-17** on `ckir/clavity`: `ask` (+ `--review-only`/`--no-ring`),
> `await-reply` (resolved to thread-scoped Option D), `ping`, the `membus`/agentmemory daemon client, the
> hermetic fake-endpoint harness, the deprecation of pane-scraping, and the codified REVIEW-ONLY banner. That
> effort also produced the agy capability profile + capability-aware wording protocol + the re-runnable acceptance
> suite (`docs/agy-capabilities.md`, `docs/agy-remote-control-protocol.md`, `docs/agy-test-suite.md`). Everything
> in this section is shipped; it is kept for provenance only.
