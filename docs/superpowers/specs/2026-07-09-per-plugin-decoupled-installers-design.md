# Per-Plugin Decoupled Installers (3a) — Design

**Date:** 2026-07-09
**Status:** design approved (file layout + 3a); pending spec self-review + AGY-AFTER + user review → plan
**Supersedes/rewires:** the v6 "fold ghidrust into the umbrella" bundling (`4083058`) — the dotnet installer
STOPS bundling other tools' plugins; interacts with the version-stamp-automation spec (plugin.json SoT).

## Problem

The `clavity-dotnet` installer bundles a local `marketplace.json` + ALL plugin dirs (clavity-dotnet,
agy-autotrain, commonmemory, ghidrust) and `clavity-ls install` registers them into the detected agent from
that local bundle. Baking autonomous tools' plugins into the flagship installer couples them — adding/updating
ghidrust forced dotnet version bumps (0.1.11→0.1.13). (Verified 2026-07-09 via innounp: the v6 dotnet installer
contains `{app}\plugins\{clavity-dotnet,agy-autotrain,commonmemory,ghidrust}`.)

## Goal (user-approved)

Every plugin/tool ships its **own decoupled installer**; no installer bundles another's plugin. The two clavity
tool installers **offer** the other plugins as **opt-in** checkboxes that **download + launch the standalone
installer at runtime**. Internet-at-install is acceptable. Moving tool code onto per-tool branches is acceptable.
All installers publish to **one** canonical umbrella release (**3a**).

## The five installers

| Installer | Installs | Self-registers plugin? | Offers opt-ins |
|-----------|----------|------------------------|----------------|
| `clavity-dotnet-setup` | `clavity-ls.exe` (→PATH) + **clavity-dotnet** plugin | yes | agy-autotrain, commonmemory, ghidrust |
| `clavity-classic-setup` | classic binary (→PATH) + **clavity-classic** plugin | yes | agy-autotrain, commonmemory, ghidrust |
| `ghidrust-setup` | `ghidrust.exe` (→PATH) + **ghidrust** plugin | yes | — |
| `agy-autotrain-setup` | **agy-autotrain** plugin (plugin-only) | yes | — |
| `commonmemory-setup` | **commonmemory** plugin (plugin-only) | yes | — |

## Components

### C1 — Each installer SELF-REGISTERS its own plugin (no clavity-ls dependency)
Today `clavity-ls install` runs the registration. That couples every plugin to the dotnet binary. Decouple it:
each installer's Inno `[Code]` performs the registration itself against detected agents, mirroring the existing
`PluginInstaller` calls but inline and per-installer:
- stage the plugin dir + a **scoped** 1-entry `marketplace.json` (listing ONLY this plugin) under `{app}`;
- Claude: `claude plugin marketplace add {app} --scope user` → `claude plugin install <name>@<scoped-mkt> --scope user`;
- agy: `agy plugin install {app}\plugins\<name>`;
- uninstall reverses (`claude plugin uninstall` / `agy` removal + `marketplace remove`).

Plugin-only installers (`agy-autotrain`, `commonmemory`) do exactly this with no binary in `[Files]`.
**Open (plan): O1** — factor the registration `[Code]` into a shared `.iss` include (DRY across 5 installers)
vs a tiny shared `plugin-register.exe` helper. Lean: shared `[Code]` include (no new binary, no coupling).

### C2 — Opt-in download+launch (clavity-dotnet / clavity-classic)
Each opt-in is an Inno `[Tasks]` checkbox (unchecked by default). When ticked, `[Code]` at `ssPostInstall`:
1. downloads the sibling installer from **this release** —
   `https://github.com/ckir/clavity/releases/download/<TAG>/<sibling>-setup-<VER>.exe`;
2. runs it silently (`/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`), which self-registers per C1;
3. ghidrust opt-in = the FULL `ghidrust-setup` (binary + plugin), per user decision.

The clavity installer must know `<TAG>` + each sibling `<VER>` at build time → the umbrella build injects them via
ISCC `/D` (the release tag + sibling versions resolved at cut time). Download mechanism: Inno's
`InnoDownloadPlugin` (idp) or an `Exec` of `curl.exe`/`Invoke-WebRequest`. **Open (plan): O2** — pick idp vs
Exec-curl; handle offline gracefully (skip with a clear message, since internet is "OK" not "required-hard").

### C3 — No cross-plugin bundling; marketplace split
- `clavity-dotnet.iss` `[Files]` drops `agy-autotrain`, `commonmemory`, `ghidrust` staging — keeps ONLY
  `plugins/clavity-dotnet` + a clavity-dotnet-scoped `marketplace.json`.
- The **repo-root** `.claude-plugin/marketplace.json` stays the FULL list (all 5) for REMOTE discovery
  (`ckir/clavity` marketplace) — unchanged.
- Each installer bundles its OWN scoped `marketplace.json` (1 entry). **Open (plan): O3** — generate the scoped
  manifests from the repo-root full manifest (a small build step) vs hand-maintain; prefer generate to avoid drift.

### C4 — Build + release wiring (umbrella, 3a)
`umbrella-release.yml` builds all 5 installers and publishes them to ONE `clavity-v<N>` release:
- resolve-ref + build jobs per tool (dotnet@main, classic@clavity-classic, ghidrust@ghidrust,
  agy-autotrain@<branch>, commonmemory@<branch>);
- ghidrust keeps its BLOCKING `e2e-ghidrust` gate (shared reusable workflow, already built);
- `publish` needs ALL build+gate jobs → atomic 10-asset release (5 `.exe` + 5 `.sha256`) + notes table.
- clavity-dotnet/classic builds receive the `/D<TAG>`/sibling-versions for C2.
- **Open (plan): O4** — agy-autotrain/commonmemory currently live on `main` as plugin dirs. Move each to its own
  branch (user OK'd) for symmetry, or keep on main and build from there? Plugin-only tools have no compile step,
  so a branch is optional. Lean: keep on `main` (they're pure plugin content, no binary) unless a reason emerges.
- **Open (plan): O5** — with the dotnet installer no longer aggregating umbrella content, the earlier
  "keep dotnet on main" rationale (it bundled shared marketplace+plugins) weakens. Reconsider whether `dotnet`
  moves to a `dotnet` branch for full symmetry. NOT decided here — flag for an explicit call in the plan.

### C5 — Version stamps
Each installer's version = its plugin/binary SoT (per the version-stamp-automation spec): clavity-dotnet 0.1.13,
classic 0.1.0, ghidrust binary 1.0.0, agy-autotrain 0.1.2, commonmemory 0.1.0. The two specs compose cleanly —
this one adds installers; the other governs where each version lives.

## Release artifact layout (approved)

One `clavity-v<N>` release, 10 assets:
```
clavity-dotnet-setup-0.1.13.exe (+.sha256)   ce+ opt-ins: agy-autotrain, commonmemory, ghidrust
clavity-classic-setup-0.1.0.exe (+.sha256)   + same opt-ins
ghidrust-setup-1.0.0.exe        (+.sha256)   binary + plugin
agy-autotrain-setup-0.1.2.exe   (+.sha256)   plugin only
commonmemory-setup-0.1.0.exe    (+.sha256)   plugin only
```

## Error handling

- **Opt-in download fails / offline** → skip that opt-in with a clear logged message; the primary tool install
  still succeeds (internet is "OK", not a hard requirement) — never fail the whole install on an opt-in fetch.
- **Sibling installer silent-run fails** → surface a non-fatal warning; the user can run the standalone later.
- **Agent registration fails** (claude/agy) → the installer's own plugin registration failing IS fatal for that
  installer (its job); an OPT-IN's registration failing is non-fatal (it's a convenience).
- **Checksum** of a downloaded sibling → verify the `.sha256` before launching. NOTE (AGY-AFTER R1): the sibling's
  `.sha256` lives in the SAME release, so this only catches a CORRUPTED download (transport integrity) — it is NOT
  supply-chain protection (an attacker who can overwrite the release overwrites both). Real integrity would need
  Authenticode signing (out of scope — installers are unsigned). Frame it as transport-integrity only.

## Testing

- Per-installer CI install/uninstall smoke (like the current dotnet smoke): install → assert plugin registered
  into a fake/real agent → uninstall → assert removed. Plugin-only installers too.
- Opt-in path: a CI test that ticks an opt-in, mocks the download to a local file, asserts the sibling runs.
- E2E: the ghidrust live gate stays; a dispatch build produces all 10 assets named at real versions.

## C6 — Correctness & security (AGY-AFTER R1 folded)

- **UNIQUE marketplace name per tool (BLOCKING).** `PluginInstaller` today uses one const `MarketplaceName =
  "clavity"` (verified). If all 5 installers register a local marketplace named `"clavity"`, Claude Code collides
  the registrations. Each installer's scoped manifest + `plugin marketplace add`/`install <name>@<mkt>` MUST use a
  UNIQUE marketplace name (e.g. `clavity-dotnet`, `clavity-ghidrust`, `clavity-agy-autotrain`, …). The scoped-manifest
  generator (O3) rewrites the `name` field per tool.
- **DISTINCT install dir per installer.** Each installer keeps its own `DefaultDirName` so their `{app}\.claude-plugin\
  marketplace.json` + `{app}\plugins` never clobber each other. The three tool installers are ALREADY distinct
  (`{localappdata}\Programs\{clavity-dotnet,ghidrust,clavity-classic}` — verified); the two new plugin-only installers
  MUST get their own (`…\Programs\agy-autotrain`, `…\commonmemory`).
- **Sibling download → secured per-user temp, not `%TEMP%`.** Download the opt-in sibling into an installer-created,
  ACL-restricted dir, then verify+launch. NOTE: agy flagged this as an LPE via a TOCTOU swap, but all installers are
  `PrivilegesRequired=lowest` (verified) — NOT elevated — so a swapped payload runs at the SAME user level (no
  privilege escalation). Severity is "same-user integrity," not LPE; the secured-temp + verify is still correct hygiene.
- **Opt-in `<TAG>` = the EFFECTIVE release tag, with a guard.** The `/D`-injected tag must be the release tag
  (`inputs.tag` on dispatch, the pushed tag otherwise) — NOT `github.ref_name` (which is `main` on dispatch → the
  opt-in URL `…/releases/download/main/…` 404s at runtime). If the effective tag isn't `clavity-v*`, the installer
  DISABLES the opt-ins (a non-release/test build yields a working primary install with opt-ins greyed out, never a
  broken download). The tag IS known at build time (it triggered the run) even though the release publishes after
  the build — the URL resolves at INSTALL time, which is post-publish.
- **Uninstall is per-installer (by design, document it).** Opt-in-installed tools register as SEPARATE Add/Remove
  entries; uninstalling `clavity-dotnet` does NOT remove tools you opted into. This is the intended decoupling, not a
  bug — the release notes + each installer's finish page must say "each tool uninstalls independently."

## UX — the release as a palette (user requirement)

The user picks components like a **palette**: the single `clavity-v<N>` release page is a menu of standalone
installers ("choose your tool(s)"), and each clavity tool installer presents the add-ons as a clear opt-in palette
("choose your plugins") rather than a hidden default. Concretely: (a) release notes lead with a short "pick what you
want" table mapping each installer → what it gives you; (b) the `[Tasks]` page groups the opt-ins under a labelled
"Optional plugins" heading with one-line value descriptions (already the style of the current add-on tasks); (c) no
component is force-installed beyond the tool the user chose to run. The palette feel is the acceptance test for the
UX seat.

## Out of scope (now)

- Signing the installers (still unsigned).
- Moving to a remote-only marketplace model (that was agy's Option D — rejected in favor of decoupled local
  installers per user direction).

## Open items (all → plan)

O1 registration: shared `[Code]` include vs helper exe. O2 download: idp vs Exec-curl + offline handling.
O3 scoped manifests: generate vs hand-maintain. O4 agy-autotrain/commonmemory: branch vs main. O5 dotnet-on-main
vs dotnet-branch now that it no longer aggregates. O6 the `<TAG>`/sibling-version `/D` injection mechanics for C2.
