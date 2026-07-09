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

Every plugin/tool ships its **own fully-standalone installer**; no installer bundles or references another. There are
**NO opt-ins** (decision 2026-07-09) — no in-installer checkboxes, no runtime download/launch of siblings. Each
installer does exactly one thing. The user composes what they want by choosing which installers to run from the
release page — the **palette IS the release page**. Moving tool code onto per-tool branches is acceptable. All
installers publish to **one** canonical umbrella release (**3a**).

## The five installers

| Installer | Installs | Self-registers its plugin? |
|-----------|----------|----------------------------|
| `clavity-dotnet-setup` | `clavity-ls.exe` (→PATH) + **clavity-dotnet** plugin | yes |
| `clavity-classic-setup` | classic binary (→PATH) + **clavity-classic** plugin | yes |
| `ghidrust-setup` | `ghidrust.exe` (→PATH) + **ghidrust** plugin | yes |
| `agy-autotrain-setup` | **agy-autotrain** plugin (plugin-only) | yes |
| `commonmemory-setup` | **commonmemory** plugin (plugin-only) | yes |

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

### C2 — (REMOVED) No opt-ins
Opt-in download+launch was REMOVED (decision 2026-07-09). No installer fetches, references, or launches any sibling.
This eliminates the entire runtime-download attack surface (TOCTOU, same-release hash-theatre, effective-tag/404) and
drops the `/D` tag+version injection and the idp/curl download mechanism. The clavity tool installers install ONLY
their own binary + own plugin; the user runs whatever other installers they want from the release page.

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

One `clavity-v<N>` release, 10 assets — the palette; the user runs whichever they want:
```
clavity-dotnet-setup-0.1.13.exe (+.sha256)   clavity-ls binary + clavity-dotnet plugin
clavity-classic-setup-0.1.0.exe (+.sha256)   classic binary + clavity-classic plugin
ghidrust-setup-1.0.0.exe        (+.sha256)   ghidrust binary + ghidrust plugin
agy-autotrain-setup-0.1.2.exe   (+.sha256)   plugin only
commonmemory-setup-0.1.0.exe    (+.sha256)   plugin only
```

## Error handling

- **Agent registration fails** (claude/agy) → the installer's OWN plugin registration failing IS fatal for that
  installer (that is its whole job) — report clearly and abort the install cleanly.
- **No agent detected** (neither Claude Code nor agy) → clear message + non-zero exit (as today).
- (No download/opt-in error paths — those were removed with the opt-ins.)

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
- **Uninstall is per-installer (by design, document it).** Opt-in-installed tools register as SEPARATE Add/Remove
  entries; uninstalling `clavity-dotnet` does NOT remove tools you opted into. This is the intended decoupling, not a
  bug — the release notes + each installer's finish page must say "each tool uninstalls independently."

## UX — the release as a palette (user requirement)

The user composes via a **palette = the release page**: the single `clavity-v<N>` page is a menu of standalone
installers, each doing exactly one thing ("pick what you want, run those"). Concretely: (a) release notes lead with a
short table mapping each installer → what it gives you + when you'd want it; (b) each installer's own finish page
states plainly what it installed and what it did NOT (so the user knows to grab siblings from the same page); (c)
nothing is force-installed beyond the installer the user chose to run. The palette feel is the acceptance test for the
UX seat.

## Out of scope (now)

- Signing the installers (still unsigned).
- Moving to a remote-only marketplace model (that was agy's Option D — rejected in favor of decoupled local
  installers per user direction).

## Open items (all → plan)

O1 registration: shared `[Code]` include vs helper exe. O3 scoped manifests: generate vs hand-maintain.
O4 agy-autotrain/commonmemory: branch vs main. O5 dotnet-on-main vs dotnet-branch now that it no longer aggregates.
(O2 download + O6 tag-injection removed with the opt-ins.)
