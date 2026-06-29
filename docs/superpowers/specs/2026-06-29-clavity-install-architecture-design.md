# clavity install architecture — design spec

> **Authored:** 2026-06-29 · **Status:** draft (brainstorming output, pre-plan) · **Branch:** `clavity-dotnet`
> **Decision owner:** user (Costas). agy consulted on the forks (AGY-FIRST); see *Decisions*.

## Goal

Give clavity a **simple, one-command install with a real uninstall**, while supporting its two distinct
pairing variants — **clavity-classic** (Rust `clavity`; psmux doorbell + agentmemory bus) and
**clavity-dotnet** (.NET `clavity-ls`; agy Language-Server bridge) — without fusing their disjoint setups
into one brittle artifact. Spec covers the whole architecture; **implementation builds the clavity-dotnet
variant first**, with the clavity-classic installer as a defined follow-on into the same entry point.

## Motivation

Today's install is too complex for users. clavity-classic's README is **7 manual steps** (binary +
psmux + agentmemory MCP in *both* CLIs + a `GEMINI.md` doorbell rule + `tmux.conf`). clavity-dotnet, as
first sketched, was a 3-step flow (dotnet tool + `claude plugin install` + `agy plugin install`). The
[`aidesktop`/FlaUI.Mcp](C:\Users\user\Development\c#\aidesktop) project shows the clean alternative: an
**Inno Setup** installer that bundles a published single-file exe, registers PATH, runs a self-config
subcommand (`flaui-mcp install --agent all`), and gets a proper Add/Remove Programs **uninstaller**
(`[UninstallRun]` + PATH cleanup + purge prompt) for free. We adopt that model.

## Decisions (forks resolved)

Each was decided by the user; agy gave a divergent read first (AGY-FIRST). Where agy and the user
diverged, the synthesis and rationale are recorded.

1. **Driver = parity/consistency** — a uniform install story across variants, not urgency.
2. **clavity-dotnet is a true dual-plugin with a *real* agy side** — not a vestigial agy manifest. The
   agy side ships a **tempered orientation/etiquette pairing skill** (see Components). (agy pitched a
   stronger "Subcontractor Protocol" optimizing agy's output for Claude; tempered down to protect the
   human-visible agy tab and because `agy_ask` doesn't decode assistant prose yet.)
3. **Delivery = Inno Setup installer per variant** (aidesktop-exact), fronted by a **thin chooser
   one-liner**. (agy preferred "plugin-as-source-of-truth, no external installer"; overruled by the user
   for install simplicity — but agy's lifecycle concern is honored: see #5.)
4. **Binary rename** — the .NET CLI ships as **`clavity-ls`** (not `clavity`), so it never collides with
   clavity-classic's `clavity` on PATH or in logs.
5. **Inno is the SINGLE master; the plugin is installer-managed** (revised after AGY-AFTER — agy's
   "two-masters / split-brain" challenge accepted). The installer installs the skills *as a plugin* so the
   agents load them natively at runtime, but their **lifecycle is owned by the installer** — install and
   uninstall happen ONLY via the setup / Add/Remove Programs, NOT via the agent's plugin UI. This dissolves
   the split-brain (a native `plugin uninstall` would otherwise orphan the Inno entry + binary + PATH). The
   README/skill docs state plainly: *manage clavity via Add/Remove Programs, not the agent's plugin
   commands.* Uninstall removes the plugin **first** and **aborts file deletion if that fails**, so the
   agent is never left pointing at a deleted exe (closes agy's zombie loophole; see Components B/E).
6. **Pre-built, version-pinned artifacts on GitHub Releases** (incorporates the user's "keep pre-built
   artifacts on GitHub"). CI builds the matched set from ONE commit — `clavity-ls.exe` (single-file) +
   the bundled plugin → `clavity-dotnet-setup.exe` — and publishes them as Release assets under a version
   tag. The chooser downloads a **pinned tag** (default latest); **nothing is built on the user's machine**
   (no dotnet SDK / Inno / cargo). The release tag IS the version-pin, so the binary↔plugin contract can't
   drift (agy's "version skew" risk).
7. **Mutual exclusion** — a user runs **one variant at a time**. Each installer **refuses to continue**
   if the other variant is detected (user must uninstall the other first). Not auto-uninstall.
8. **No unified monolith** — the two variants' setup/teardown logic stays **separate** (agy's strongest
   point: a single wizard surgically reverting `GEMINI.md`/agentmemory/tmux *and* configuring .NET MCP
   is a maintenance chimera). The only shared piece is the ~20-line chooser.

## Architecture

```
 user ──► irm .../install/clavity-install.ps1 | iex        (thin chooser, ~20 lines)
                       │  prompts: classic | dotnet
                       │  pre-checks registry for the OTHER variant (early warn)
                       ▼
        downloads <variant>-setup.exe from GitHub Releases  (version-pinned asset)
                       ▼
        runs the Inno Setup installer for that variant
            ├─ InitializeSetup(): REFUSE if other variant's uninstall key present
            ├─ [Files]   : clavity-ls.exe  +  bundled clavity-dotnet plugin dir
            ├─ [Tasks]   : optional "add to PATH"
            ├─ [Run]     : clavity-ls install --agent all   (native plugin install + MCP verify)
            └─ registers Add/Remove Programs entry
                       ▼
        Uninstall (Add/Remove Programs):
            ├─ [UninstallRun]: clavity-ls uninstall --agent all  (native plugin uninstall)
            ├─ removes binary, cleans PATH (CurUninstallStepChanged)
            └─ InitializeUninstall(): optional data-purge prompt
```

Three layers, each independently maintained:
- **Chooser** (`install/clavity-install.ps1`) — variant menu + download + run. No variant logic.
- **Per-variant Inno installer** — the only place a variant's binary placement, PATH, agent config, and
  uninstall live.
- **Native plugin** — the source of truth for skills + MCP registration, governed by each agent's plugin
  system.

## Components

### A. Thin chooser — `install/clavity-install.ps1`
- One-liner entry (`irm … | iex`). Prompts `classic` / `dotnet`.
- **Pre-check:** reads `HKCU\…\Uninstall\clavity-classic` and `…\clavity-dotnet`; if the *other* variant
  is present, warns and exits before downloading.
- Resolves the latest (or `-Version`-pinned) GitHub Release, downloads `clavity-<variant>-setup.exe` to
  `%TEMP%`, runs it (interactive by default; `-Silent` passes `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`).
- Modeled on aidesktop's `dist/install.ps1`.

### B. clavity-dotnet Inno installer — `installer/clavity-dotnet.iss`
- `AppName=clavity-dotnet`, dedicated `AppId` GUID (its Add/Remove Programs identity).
- `DefaultDirName={localappdata}\Programs\clavity-dotnet`, `PrivilegesRequired=lowest`,
  `ArchitecturesAllowed=x64compatible`, `OutputDir=..\dist`, `OutputBaseFilename=clavity-dotnet-setup`.
- `[Files]`: the published **`clavity-ls.exe`** (single-file) **and the bundled `clavity-dotnet` plugin
  directory** (manifests + `.mcp.json` + skills) under `{app}\plugin\`.
- `[Tasks]`: `addtopath` (checkbox) → `[Registry]` per-user PATH append (aidesktop's `NeedsAddPath`).
- `[Run]`: `clavity-ls install --agent all --plugin "{app}\plugin"` (hidden, wait) — see D.
- **Uninstall — plugin removal must GATE deletion (corrected per AGY-AFTER round 2).** Inno's
  `[UninstallRun]` **cannot abort** an uninstall on a non-zero exit (it logs and deletes `{app}` anyway →
  zombie). So plugin removal runs from `[Code] InitializeUninstall()` via `Exec('clavity-ls','uninstall
  --agent all')`; **if it returns non-zero, return `False` from `InitializeUninstall()` to cancel the
  uninstall before any files are touched.** A `--force`/second-confirm escape removes anyway if plugin
  cleanup is permanently wedged, so the user is never trapped. `--purge-data` when the purge prompt is
  accepted. `[UninstallRun]` is reserved for best-effort, safe-to-fail steps only.
- `[Code]`: `InitializeSetup()` mutual-exclusion refusal (see E) **plus a shared `SetupMutex`** (identical
  name in BOTH variant `.iss` files) so Windows blocks the two installers from running concurrently (closes
  the exclusion-check race). `PrepareToInstall()` guards the live-session case via a **named mutex, not WMI**:
  `clavity-ls --mcp` holds `Global\ClavityMcpRunning` for its lifetime, and if `PrepareToInstall()` finds it
  held it aborts with *"close your active Claude pairing session first"* (no process-arg inspection, no
  taskkill of a live MCP child). `InitializeUninstall()` also hosts the plugin-removal gate above + the purge
  prompt; `CurUninstallStepChanged` PATH removal. (Base patterns from `aidesktop/installer/flaui-mcp.iss`.)

### C. The `clavity-dotnet` plugin (bundled; native source of truth)
- `.claude-plugin/plugin.json` + `plugin.json` — manifests (declare the compatible `clavity-ls` version).
- `.mcp.json` (Claude only) — registers the `clavity-ls --mcp` stdio server.
- `skills/clavity-ls-driving/SKILL.md` (Claude) — when/how to call `agy_look` / `agy_status` / `agy_ask`;
  `agy_ask` is a quota-consuming **write**; handle the `waiting_for_human` and `possible_modal` results.
- `skills/clavity-ls-pairing/SKILL.md` (agy) — tempered orientation/etiquette: you are LS-driven by a
  paired Claude; keep one active conversation; don't leave blocking modals open; prefer precise/parseable
  output (exact paths, error codes) while staying human-readable.
- `README.md`.

### D. New `clavity-ls` CLI surface (.NET, `clavity-dotnet` branch)
- **Rename** `Clavity.Cli` output + command to **`clavity-ls`** (AssemblyName / single-file publish);
  existing commands become `clavity-ls start` / `clavity-ls --mcp`.
- **`clavity-ls install --agent all --plugin <dir>`** — detect installed agents (Claude, agy) and run each
  agent's **native plugin install** of `<dir>`; verify the MCP server registered. Mirrors aidesktop's
  `flaui-mcp install --agent all`, but installs a *plugin* rather than writing a raw MCP JSON entry.
- **`clavity-ls uninstall --agent all [--purge-data]`** — native `plugin uninstall clavity-dotnet` per
  detected agent; **non-zero exit on any agent's removal failure** (the Inno `InitializeUninstall` gate
  depends on this); `--purge-data` also removes the per-session `logs/` retention dir.
- **`clavity-ls --mcp` holds a named mutex `Global\ClavityMcpRunning`** for its lifetime, so the installer
  can detect a live pairing session without WMI process inspection (see Component B).
- Single-file publish config so Inno `[Files]` has one exe.

### E. Mutual-exclusion guard
- Authoritative gate in each installer's `InitializeSetup()`. **Detection MUST cover both install paths**
  (agy caught this gap): (a) the other variant's Add/Remove Programs registry key, AND (b) a
  `cargo install`-era classic that has **no registry key** — detect a `clavity.exe` on PATH (distinct from
  our `clavity-ls`) and/or the classic plugin/skills present in the agent dirs (e.g. `claudavity-responder`).
  If either signal fires, `MsgBox(... 'uninstall it first' ...)` and `Result := False`.
- Friendly early warning in the chooser (same dual detection; B is the real gate, this just avoids a wasted
  download).

## Install / uninstall flow (clavity-dotnet)

**Install:** `irm … | iex` → pick `dotnet` → (no classic present) → download `clavity-dotnet-setup.exe`
→ Inno places `clavity-ls.exe` + plugin, adds PATH, runs `clavity-ls install --agent all` (native plugin
install into Claude + agy, MCP verified) → done. Then `clavity-ls start <project>` launches a pair.

**Uninstall:** Add/Remove Programs → "clavity-dotnet" → `clavity-ls uninstall --agent all` (native plugin
uninstall) → binary removed, PATH cleaned, optional data purge.

## Error handling / failure modes

- **Other variant installed** → hard refuse with a clear instruction (E).
- **Agent not found** (e.g. only Claude, no agy) → `install --agent all` installs into whatever is present;
  reports which agents were configured; never fails the whole install for a missing optional agent.
- **Binary locked** (server running) → `PrepareToInstall` stops `clavity-ls` **only when safe**; it must NOT
  kill a `--mcp` child of an active Claude session (skip-and-warn / ask the user to close the pair first).
- **Uninstall-hook failure** → plugin removal runs FIRST and must succeed before any files are deleted; on
  failure the uninstall surfaces an error and leaves the install intact (no zombie agent config). Re-runnable.
- **Split-brain attempt** (user runs the agent's native `plugin uninstall` instead of Add/Remove Programs) →
  out of the supported path by policy (Decision #5); docs steer users to Add/Remove Programs. (Cannot be fully
  prevented; the harm is limited to a leftover binary/PATH the next install/uninstall reconciles.)
- **Download failure / wrong release asset** → chooser throws with the resolved tag + asset name (aidesktop
  pattern); nothing is installed.
- **Partial install** → `install --agent all` is idempotent and re-runnable; reports per-agent
  success/failure rather than leaving a half state silently.

## Testing strategy

- **`clavity-ls install/uninstall` unit/integration** — against fake/temp agent config dirs: asserts the
  plugin is installed/removed and the MCP server registered/unregistered per agent; idempotent re-run.
- **Inno script** — built in CI (`ISCC.exe`), `/VERYSILENT` install+uninstall smoke on a Windows runner
  asserting: files placed, PATH entry added/removed, Add/Remove Programs entry present then gone,
  mutual-exclusion refusal when a fake "other variant" uninstall key exists.
- **Chooser** — Pester test of the registry pre-check + release-asset resolution (mocked GitHub API).
- **Live smoke (manual, gated)** — `clavity-ls start <project>` launches a working pair (as clavity-classic
  is verified end-to-end today).

## Security (supply-chain & installer) — folded from AGY-AFTER round 3

- **Bootstrap trust (HIGH).** The `irm … | iex` URL MUST pin an **immutable git tag**, never a mutable
  branch; `install.ps1` stays minimal to keep the audit surface small.
- **Release-asset integrity (CRITICAL).** `install.ps1` at the pinned tag **hard-codes the SHA-256** of the
  expected `…-setup.exe`, downloads it, and **verifies the hash — aborting on mismatch before execution**, so
  a compromised GitHub Release asset can't yield silent RCE. (Stricter than aidesktop's bootstrap, which does
  not hash-check.)
- **Code-signing (HIGH, UX) — cost-gated.** CI **Authenticode-signs** both `clavity-ls.exe` and `…-setup.exe`
  IF a cert is provisioned; an unsigned exe gets Mark-of-the-Web → SmartScreen/Defender hard-block. ⚠ Signing
  certs cost money + an HSM/token (EV) — **absent a cert already provisioned in CI (confirm with the owner),
  the documented SmartScreen-bypass is the DEFAULT, not a fallback.** Decide signing-vs-document before the
  release pipeline is built.
- **PATH (MEDIUM).** Inno **APPENDS** `{app}` to HKCU `Path` (never prepend — avoids command/DLL hijack);
  `{app}` holds only `clavity-ls.exe` + the plugin subfolder (minimal DLL-hijack surface).
- **Agent-config writes (MEDIUM).** `clavity-ls install` mutates agent JSON config; it MUST use **atomic
  write (temp-file + rename) + defensive JSON parse**, and enforce it runs as the **logged-in user** (never
  elevated — no SYSTEM-owned files written into the user profile; `PrivilegesRequired=lowest` aids this).
- **.NET single-file extraction (HIGH).** Standard `PublishSingleFile` may extract native libs to a
  hijackable `%TEMP%\.net\…`. **Realistic plan (per round-5 feasibility): true single-file with native-lib
  extraction disabled** (`IncludeNativeLibrariesForSelfExtract` off / no-extract config). NativeAOT is the
  *ideal* but is almost certainly **infeasible** here — `Grpc.Net.Client` + `Google.Protobuf` + the MCP SDK
  rely heavily on runtime reflection and are AOT-hostile. Treat AOT as a stretch goal, the non-extracting
  single-file as the plan (spike it — see Gating spikes).
- **Mutex/registry forgeability (LOW — accepted).** A same-user process can forge the exclusion registry key
  or hold `Global\ClavityMcpRunning` to block installs — local DoS only, no escalation; accepted.

## User experience (naive-user journey) — folded from AGY-AFTER round 4

The goal is "simple for a non-technical Windows user," so these are requirements, not nice-to-haves:

- **Two entry paths (HIGH).** Primary for non-technical users = a **direct `…-setup.exe` download** from the
  GitHub Releases page (double-click). The `irm … | iex` one-liner is the power-user path, and docs MUST say
  "run this in **PowerShell**" (it syntax-errors if pasted into `cmd.exe`).
- **Zero-agent guard (HIGH).** `clavity-ls install` detects agents; if **neither** Claude Code nor agy is
  found it returns non-zero and the installer shows *"No compatible agent (Claude Code / agy) found — install
  one first,"* instead of reporting success over a silent no-op.
- **Next-step prompt (MEDIUM).** On completion the installer shows (Inno `InfoAfterFile` / a final message)
  the exact next command: *"Open a terminal and run `clavity-ls start C:\path\to\project`."*
- **Actionable exclusion message (CRITICAL — the cargo-classic dead-end).** When a legacy `clavity.exe` with
  **no Add/Remove Programs entry** is detected, the refusal MUST print **its exact path** and how to remove it
  (delete the file + its PATH entry) — never a bare "uninstall it first" that sends the user to an empty
  Add/Remove Programs list. May optionally offer to remove it.
- **Visible install-step failure (HIGH).** The installer runs `clavity-ls install` via `Exec` in `[Code]` and
  **checks the exit code**; on failure it shows a visible error + a log path — never "Success" over a broken
  plugin/MCP registration. (Same idiom as the uninstall gate.)
- **Seamless upgrade (MEDIUM).** Re-running the installer upgrades in place; if a pair is live
  (`Global\ClavityMcpRunning` held) it shows a clear *"close any terminal running clavity, then retry"* message,
  not a cryptic file-in-use error.
- **Per-agent skill scoping (MEDIUM — VERIFY).** Prefer Claude loading only `clavity-ls-driving` and agy only
  `clavity-ls-pairing`. Verify whether the dual-plugin format can scope skills per agent (Claude vs agy
  manifest); if not, rely on contextual skill invocation (clavity-classic already ships both skills to both
  CLIs and works in practice) and document the consideration. (Clutter risk, not hard breakage — Claude won't
  *invoke* a pairing skill.)

## Scope / non-goals / sequencing

- **In scope (build now):** the chooser; the clavity-dotnet Inno installer; the bundled clavity-dotnet
  plugin; the `clavity-ls` rename + `install`/`uninstall` subcommands; CI to publish
  `clavity-dotnet-setup.exe` as a Release asset.
- **Follow-on (defined, not built now):** the **clavity-classic** Inno installer (its 7-step setup —
  agentmemory MCP, `GEMINI.md` doorbell rule, `tmux.conf`/escape-time — wrapped into `[Run]` config) and
  publishing `clavity-classic-setup.exe`. Slots into the same chooser.
- **Non-goals:** unified monolithic installer; the exe dropping naked skills; cross-platform installers
  (Windows-first, matching the project's verified surface); the T10 hard-coded-model follow-on; any change
  to the LS bridge's runtime behavior.

## Gating spikes (the plan's first tasks — de-risk before building)

Round-5 feasibility confirmed the Inno `[Code]` mechanisms are buildable (`Exec`+`InitializeUninstall`
abort, `CheckForMutexes`, `SetupMutex`, append-PATH, PATH-split detection). Three unknowns MUST be spiked
first:

1. **Plugin-install invocation + copy-vs-reference** — for BOTH `claude` and `agy`: the exact non-interactive
   command to install a plugin from a local path, and whether it COPIES into the agent store or REFERENCES the
   source dir. Determines `clavity-ls install`'s shape and uninstall ordering. (Existence is established; usage
   is the unknown.)
2. **Non-extracting single-file publish** — prove `clavity-ls.exe` builds as one file that does NOT extract
   native libs to `%TEMP%` (NativeAOT almost certainly ruled out by the gRPC/protobuf/MCP stack).
3. **Agent detection heuristic** — define exactly how `clavity-ls install --agent all` detects Claude / agy
   (config paths like `%USERPROFILE%\.gemini\config`, presence of the CLI on PATH, etc.) — currently
   underspecified.

Also a non-spike decision for the owner: **code-signing cert yes/no** (gates the security/UX story).

## Risks

- **Plugin-install semantics (GATING — see Gating spikes)** — `plugin install` exact usage + copy-vs-reference
  determines uninstall correctness and whether `{app}\plugin` is canonical or a dead staging dir. (Note:
  `claude plugin install` AND `agy plugin install` DO exist — evidenced by this repo's READMEs
  (`claude plugin install ./plugins/clavity-classic`, `agy plugin install …`), the live `agy --help`
  (`plugin … install, uninstall`), and Claude Code's own plugin/marketplace support. AGY-AFTER rounds 1 and 5
  claimed otherwise — **incorrect, disregarded.** The spike verifies *exact invocation*, not *existence*; only
  if a spike proves a command truly absent does the fallback — atomic JSON-config mutation — apply.)
- **Coupling to the .NET branch** — the `clavity-ls` rename lands on `clavity-dotnet`; the installer work
  is gated on that rename existing.
- **Policy vs coexistence** — mutual exclusion deliberately overrides the rename's coexistence capability;
  acceptable as an explicit product choice.
- **Residual split-brain (accepted)** — nothing *prevents* a user from running the agent's own
  `plugin uninstall` instead of Add/Remove Programs; that leaves the binary + PATH behind. Bounded harm,
  reconciled on the next install/uninstall; documented, not engineered away.
- **Agent plugin auto-update skew (VERIFY)** — if Claude/agy ever auto-update a *locally* path-installed
  plugin from a registry/git, the plugin could drift from the version-locked `{app}` exe, re-introducing
  skew. Verify the agents do NOT auto-update local plugins; if they can, mark the plugin local-only /
  pin-version in its manifest. (Inferred risk — confirm against the live plugin systems.)
