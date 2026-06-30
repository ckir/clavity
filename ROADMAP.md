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
  (`clavity-dotnet-setup.exe`), Add/Remove-Programs uninstall, release CI. Current release **v0.1.8**.
- **clavity-classic** — Rust, binary **`clavity`**, drives agy over **psmux** + the **agentmemory signal bus**
  (`clavity ask` / `await-reply` / `ping`, `delegate_to_antigravity`). Source lives on the **`clavity-classic`
  branch**. Today it installs via `cargo install --git … --branch clavity-classic` (needs the Rust toolchain).
  **An installer for it is the #1 forward item** (design + plan complete — see § 1).

Optional opt-in add-ons (installer checkboxes, **clavity-dotnet only**): **agy-autotrain** (the
agy-driving-perfection learning loop) and **commonmemory** (shared Claude⇄agy notebook over agentmemory). These
are dotnet **plugins**; classic has no plugin tree, so its installer (Option A) ships **only** the opt-in
`agy-mcp-bridge` add-on, not these.

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
- **v0.1.8** — agy always launches with `--dangerously-skip-permissions` (the paired agy is driven headless, so
  its interactive permission prompts would otherwise stall the bus round-trip).

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

### 1. clavity-classic installer — **#1 PRIORITY** (Option A: minimal/honest, matches classic's architecture)

Ship `clavity-classic-setup.exe` so a user installs classic with **no Rust toolchain**. **Scope redecided
2026-06-30 (Option A — minimal/honest):** plan-grounding against the real `clavity-classic` source showed classic
**deliberately uses manual wiring** and lacks dotnet-style install machinery (no `install` verb; agentmemory over
**REST** not MCP; GEMINI.md pointer **manual by design**; no plugin tree/add-ons; no `tmux.conf`). So the installer
ships what exists and surfaces the rest as **guided-manual** — it does NOT mirror dotnet's zero-touch registration
(building those new Rust verbs = "Option B" packaging-driven scope creep, **rejected**; agy-consulted +
user-approved). Build order **7.3 ✅ → 7.8 ✅ → 7.1 → 7.2**.

Design = `docs/superpowers/specs/2026-06-30-clavity-classic-packaging-design.md` (Option A reconciliation block);
implementation plan = `docs/superpowers/plans/2026-06-30-clavity-classic-packaging-plan.md` (Tasks 0–6,
AGY-AFTER round-1 reviewed; release/ops round pending agy availability).

- **7.3 — Rust golden-header injection. ✅ DONE — merged to `clavity-classic` (`dea8f87`), rust-reviewed APPROVE.**
  Mirrors dotnet `GoldenHeader` (`src/golden_header.rs`): resolves `%USERPROFILE%\.clavity\golden-header.md` via
  **`std::env::var_os("USERPROFILE")→HOME`** (NOT the `dirs` crate — no dep added), read+cap+prepend per
  `clavity ask`, `clavity curate-commit` writes the header + atomic `.sha256` sidecar; `clavity doctor` reports
  golden-hdr status. *(dotnet-parity follow-ups noted in § 6.)*
- **7.8 — prebuild + stage the Rust `clavity.exe`. ✅ DONE — `scripts/build-classic-release.ps1`** (the shared
  recipe, run locally AND in 7.2 CI): `cargo build --release --locked` → stages `clavity.exe` + the bridge
  **runtime whitelist** (incl. `SKILL.md`) into `publish/`, with a hard `.env`-leak assertion. No cross-repo
  fetch — the bridge is vendored in-branch at `agy-mcp-bridge/` (canonical home).
- **7.1 — the Inno installer (`installer/clavity-classic.iss`, greenfield, Option A).** Real jobs: `clavity.exe`
  →PATH; **SET `HKCU\Software\clavity\classic`** so the shipped dotnet installer's existing `ClassicRegistered`
  detection fires (no dotnet-side patch); **refuse** if `clavity-ls` is on PATH or dotnet's ARP key is present
  (live-test BOTH directions); the **opt-in `agy-mcp-bridge`** add-on (Python/uv prereq, default OFF, `uv sync
  --frozen` warmup, `.env` hard-excluded); responder-skill teardown on uninstall; golden-header zombie rename;
  **informed `.env` keep/purge**. **Guided-manual (NOT installer-automated):** the agentmemory MCP, the GEMINI.md
  doorbell pointer, and the bridge MCP registration — surfaced via shipped docs + a loud final-wizard summary
  (editing user-owned agent config from an installer is too brittle — agy security/contract round). Full task
  breakdown + the complete `.iss` in the packaging plan.
- **7.2 — `clavity-classic-setup.exe` release CI** (`release-clavity-classic.yml`, greenfield; mirrors
  `release-clavity-dotnet.yml`): tag `clavity-classic-v*`, single checkout, 4-way version triangulation,
  tag-lineage guard, pinned toolchain + Inno + `windows-2022`, **blocking** timeout-bounded smokes
  (install/uninstall, mutual-exclusion, `.env`-exclusion), `concurrency` guard, upload-artifact then atomic
  gh-release. Authored in the plan; awaits the local ISCC gate before the first tag.

- **✅ BRIDGE FORK RESOLVED (user 2026-06-30): (d) Python/uv prerequisite.** Ship `agy-mcp-bridge` as an **opt-in,
  default-OFF** add-on declaring a Python ≥3.10 + uv prereq (no PyInstaller, no Rust port — the `google-antigravity`
  SDK is Python-only). Source is vendored in-branch at `agy-mcp-bridge/` (no upstream, no drift). **Security
  hardening landed @`bd8ec8f`:** `server.py` scrubs host AI-platform keys (`GEMINI_API_KEY` et al.) from the env
  before spawning the delegated sub-agent (confused-deputy fix) and passes the key explicitly to the SDK. *(One
  residual: whether the closed `localharness` binary re-exports the key into its shells needs a live delegation to
  confirm — tracked.)*

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

### 6. dotnet golden-header parity follow-ups
The classic 7.3 implementation (`src/golden_header.rs`) is now the canonical golden-header behavior; two dotnet
divergences were found during the Spec A capstone and are tracked as **dotnet-side code fixes** (they do not
affect the packaging `.iss`/CI contracts):
- **`GoldenHeader.Apply` trim charset** — dotnet uses full-Unicode `TrimEnd()`; classic (canonical) trims an
  **ASCII-only** whitespace set. Align dotnet to ASCII-only.
- **Sidecar write order/atomicity** — dotnet writes the `.sha256` sidecar **before** the target rename and
  non-atomically; classic writes it **after** the rename, atomically. Align dotnet to after-move/atomic.

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
- **No continuous .NET build/test CI** on `main` — the .NET release gate stays local (`dotnet build -c Release` +
  `dotnet test --filter "Category!=LiveAgy"`); dotnet packaging ships via the release-only
  `release-clavity-dotnet.yml`. The continuous `ci.yml` (cargo fmt/clippy/test/build) now **targets the
  `clavity-classic` branch** (where the Rust crate lives) on both branches — it was retargeted off `main` (which
  has no `Cargo.toml`) so it stops false-failing and actually gates the Rust crate.

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
