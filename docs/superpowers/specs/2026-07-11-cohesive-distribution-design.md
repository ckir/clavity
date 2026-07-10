# Cohesive Distribution Model — Design

**Date:** 2026-07-11
**Status:** design — owner-approved model (2026-07-11); pending spec self-review + AGY-AFTER panel + user review → plan.
**Supersedes / resets:** all prior distribution decisions for the umbrella repo, including
`2026-07-09-per-plugin-decoupled-installers-design.md` (whose download/opt-in mechanics and marketplace-split
details are re-derived from scratch here) and the *Distribution* phase (Component 3 / Acceptance #6) of
`2026-07-10-agy-autotrain-seed-and-auto-split-design.md`. Where this document and those disagree, **this document
wins** for how members are packaged and shipped. This was brainstormed fresh with the owner ("forget previous stale
notes and decisions; start from scratch"), with one AGY-FIRST design consult folded (agy endorsed the model as the
most structurally sound realization of the constraints, and surfaced the four requirements folded into C6/C7/C9/D).

## Problem

The repo is now a monorepo hosting five first-class members. They currently ship through an **incoherent** mix:
the `clavity-dotnet` installer bundles a local `marketplace.json` **plus every other member's plugin dir**
(clavity-dotnet, agy-autotrain, commonmemory, ghidrust) and opt-in-registers agy-autotrain / commonmemory from that
bundle; `ghidrust`'s installer ships only its binary and leaves its plugin to a remote marketplace; agy-autotrain and
commonmemory have **no installer of their own**. This couples members that should be independent (adding/updating
ghidrust forced dotnet version bumps), creates competing version authorities (a plugin reachable both from the
bundled local marketplace and the remote `ckir/clavity` marketplace → silent-downgrade skew), and gives no single,
predictable answer to "how does a user get member X."

## Goal (owner-approved)

**One coherent, offline-capable, per-member distribution with no competing version authorities.** Every member is
packaged and delivered the same way; the user composes what they want from a single release page.

## The model (locked)

The repo's five first-class members ("senior citizens"):

| Member | Binary | Plugin | Kind |
|---|---|---|---|
| clavity-dotnet | `clavity-ls.exe` | clavity-dotnet | binary + plugin |
| clavity-classic | classic `clavity.exe` | clavity-classic | binary + plugin |
| ghidrust | `ghidrust.exe` | ghidrust | binary + plugin |
| agy-autotrain | — | agy-autotrain | plugin-only |
| commonmemory | — | commonmemory | plugin-only |

Six settled rules:

1. **Monorepo; one umbrella release is the catalog.** A single `clavity-v<N>` GitHub release is the user-facing
   palette — a menu of standalone installers. The release page *is* the "marketplace" in the human/shopping sense.
2. **One standalone installer per member** (five installers), each published on that release. Each installer does
   **exactly one** member and never bundles, references, downloads, or launches another.
3. **The plugin is the universal packaging unit for a member's AI assets** (skills, hooks, knowledge, `.mcp.json`).
   Every member ships exactly one plugin; the member's installer **installs and uninstalls** that plugin.
4. **Plugin registration is installer-local** (chosen over a live remote marketplace). Each installer embeds its own
   plugin folder, lays it down under `{app}`, writes a **scoped 1-entry `marketplace.json`** beside it under a
   **unique marketplace name**, then registers it against the detected agents. No live-remote dependency; works
   offline.
5. **Binaries are embedded (compressed) in the installer `.exe`** (chosen over download-at-install). At install the
   binary is unpacked to `{app}` and added to PATH. No network, no version-pinning, no TOCTOU. The binary is **never**
   placed inside the plugin (plugins carry only AI assets).
6. **Uninstall reverses everything** the installer did (deregister plugin + remove marketplace + delete `{app}` +
   strip PATH). **dotnet and classic are mutually exclusive** — each installer refuses if the other variant is
   present.

## Components

### C1 — Plugin as the universal packaging unit; installer-local registration

Each member's AI assets are a plugin folder embedded in its installer. On install, the installer's Inno `[Code]`:

1. stages the plugin folder → `{app}\plugins\<name>`;
2. writes a scoped `marketplace.json` (see C9) listing **only** `<name>`, under a **unique** marketplace name;
3. registers against each detected agent, mirroring today's `PluginInstaller` behavior but inline and per-installer:
   - **Claude Code:** `claude plugin marketplace add {app} --scope user` → `claude plugin install <name>@<unique-mkt> --scope user`;
   - **agy:** `agy plugin install {app}\plugins\<name>`.

Plugin-only members (agy-autotrain, commonmemory) do exactly this with **no binary step** — their `.exe` is small
(plugin assets + registration logic only). Registration failure is **fatal for that installer** (registering its own
plugin is the installer's whole job): report clearly and abort cleanly.

**Open (plan) O1** — factor the registration `[Code]` into a shared `.iss` include (DRY across five installers) vs a
tiny shared helper `.exe`. Lean: shared `[Code]` include (no new binary, no runtime coupling).

### C2 — Binaries embedded, not downloaded

The three binary members embed their binary in `[Files]` (Inno LZMA2, `SolidCompression`). Unpack to
`{app}`; PATH-append `{app}` (never prepend — PATH hygiene) when the PATH task is selected. There is **no**
download/opt-in/launch mechanism anywhere — that eliminates the whole runtime-download attack surface (TOCTOU,
same-release hash-theatre, effective-tag/404, offline-install breakage). A binary lives once, inside its installer.

### C3 — Local-only: no competing version authority

There is **no** user-facing remote marketplace. `claude plugin marketplace add ckir/clavity` is **not** a supported
install path and is not advertised anywhere (README, release notes, finish pages). The only way to obtain a member is
to download and run its installer from the release page.

The repo-root `.claude-plugin/marketplace.json` (the full five-member list) is retained **only as an internal build
artifact** — the single source we slice the per-installer scoped manifests from (C9). It is not a user channel.

**Why local-only (agy's call, owner-ratified):** a member's binary and its companion plugin always arrive together,
from one `.exe`, at one version, so the binary↔plugin execution contract can never skew. Offering a remote backdoor
would reintroduce exactly the silent-downgrade loop this reset eliminates (update the plugin remotely while the binary
stays stale). Trade-off accepted: a plugin-only member is obtained by running a small `.exe` rather than by remote
zero-install discovery — acceptable in exchange for ironclad version parity and offline capability.

### C4 — Golden-header baseline seed → installer payload (not the plugin)

A binary member carries a small **data** file its binary reads at runtime — the golden-header baseline
(`seed/golden-header.md`). It is neither an agent plugin asset nor the binary. It ships in the **installer's file
payload** and is seeded to a stable user-profile path (`%USERPROFILE%\.clavity\golden-header.seed.md`) via standard
PowerShell post-install (as today; unconditional — the SEED ships even without the agy-autotrain add-on).

**Why the installer, not the plugin (agy point D):** the seed is configuration consumed by the *host driver binary*.
Putting it inside a plugin would couple the binary's runtime to the agent's opaque plugin-extraction paths. Seeding it
to the user profile gives the binary a stable, OS-native path fully decoupled from the agent's plugin lifecycle. This
matches the split-file SEED/GROWTH design already implemented (`golden-header.seed.md` written by the installer;
`golden-header.growth.md` written by agy-curate; binary assembles SEED-then-GROWTH at read).

### C5 — Mutual exclusion (dotnet XOR classic)

The dotnet and classic installers keep the existing mutual-exclusion refusal: each aborts at `InitializeSetup` if the
other variant is detected (in-process PATH scan for the `clavity` stem; the `Software\clavity\classic` registry
marker). This is another reason the model is **five standalone installers, not one master installer with checkboxes**:
a single installer would have to enforce radio-button exclusivity between two of its own driver checkboxes, which is
clumsier than two installers that refuse each other.

### C6 — Uninstall robustness; no dangling marketplaces (agy failure-mode A1)

A failed uninstall or a manually-deleted `{app}` leaves a dead local marketplace path in Claude's registry that then
errors on every future plugin operation. Each installer's uninstall therefore:

- deregisters the plugin from each agent (`claude plugin uninstall <name>@<unique-mkt>` / agy removal) **and**
  `claude plugin marketplace remove <unique-mkt>` — so no registry entry outlives the files;
- tolerates a missing exe/dir (fail-open so Add/Remove Programs can still complete);
- (dotnet/classic) preserves the existing zombie-header backup of `~/.clavity` files when keeping user data.

### C7 — Dependency blindness is a runtime concern, not an install-time one (agy failure-mode A3)

A standalone `agy-autotrain` cannot verify at install time that a driver (dotnet or classic) is present. It does
**not** try to. The existing **runtime loud-guide** covers it: `agy-curate` still writes `golden-header.growth.md` and
emits a **non-blocking** warning ("no clavity driver detected; the learned header won't be injected until a driver is
installed"). Install-time never blocks on a sibling.

### C8 — Umbrella release wiring

`umbrella-release.yml` builds all five installers and publishes them to **one** `clavity-v<N>` release — 10 assets
(5 `.exe` + 5 `.sha256`) plus a **palette** notes table mapping each installer → what it gives you + when you'd want
it. Each installer's finish page states plainly what it installed and what it did **not** (so the user knows to grab
siblings from the same page). Nothing is force-installed beyond the installer the user chose to run.

- Binary members build their binary, embed it, ISCC the installer, run a per-installer install/uninstall smoke.
- Plugin-only members have no compile step; their installer just packages the plugin + registration `[Code]`.
- ghidrust keeps its BLOCKING `e2e-ghidrust` live gate.
- `publish` needs all build+gate jobs → an atomic 10-asset release.

**Open (plan) O4** — agy-autotrain / commonmemory currently live on `main` as plugin dirs. Keep building them from
`main` (pure plugin content, no binary → a branch is optional) unless a reason emerges. **O5** — with the dotnet
installer no longer aggregating umbrella content, revisit whether `dotnet` stays on `main` or moves to a `dotnet`
branch for symmetry; flag for an explicit call in the plan, not decided here.

### C9 — Unique marketplace name per installer (BLOCKING correctness — agy failure-mode B)

`PluginInstaller` today uses a single const `MarketplaceName = "clavity"`. If all five installers register a local
marketplace under the **same** name, the last install **steals the namespace** and silently breaks every previously
installed member's plugin resolution. Therefore each installer's scoped manifest and its `plugin marketplace
add`/`install <name>@<mkt>` MUST use a **unique** marketplace name — e.g. `clavity-dotnet`, `clavity-classic`,
`clavity-ghidrust`, `clavity-agy-autotrain`, `clavity-commonmemory`. Each installer also keeps a **distinct**
`DefaultDirName` (`…\Programs\<member>`) so their `{app}\.claude-plugin\marketplace.json` + `{app}\plugins` never
clobber each other.

**Open (plan) O3** — generate the scoped 1-entry manifests (with the rewritten unique `name`) from the repo-root full
manifest via a small build step, vs hand-maintain five files. Prefer **generate** to avoid drift.

## Failure modes (agy consult) and disposition

| # | Failure mode | Disposition |
|---|---|---|
| A1 | Dangling local marketplace after failed uninstall / manual delete | Mitigated — C6 (deregister marketplace on uninstall; fail-open) |
| A2 | Cross-member update drift (dotnet v2 + agy-autotrain v1) | Accepted — low-stakes by design: plugins are variant-agnostic; the binary↔*own*-plugin contract can't skew (C3). Not the master-installer's problem to solve here. |
| A3 | Dependency blindness (agy-autotrain needs a driver) | Handled at runtime — C7 loud-guide warning |
| B | Marketplace-name collision steals the namespace | Blocking requirement — C9 unique name per installer |

## Error handling

- **Plugin registration fails** (claude/agy) → fatal for that installer; report clearly, abort cleanly (that
  registration is the installer's whole job).
- **No agent detected** (neither Claude Code nor agy) → clear message + non-zero exit.
- **Binary/PATH step fails** → surface, do not report a false success.
- (No download / opt-in error paths — those mechanisms do not exist in this model.)

## Testing

- **Per-installer install/uninstall smoke** (like today's dotnet smoke) for all five: install → assert the plugin is
  registered into a fake/real agent under the **unique** marketplace name → assert binary on PATH (binary members) →
  seed present at `~/.clavity/golden-header.seed.md` (dotnet/classic) → uninstall → assert plugin **and** marketplace
  entry removed, PATH stripped, no dangling registry path.
- **Namespace-collision guard:** a CI assertion that the five scoped manifests carry five **distinct** marketplace
  names.
- **Mutual exclusion:** dotnet-over-classic (and vice-versa) refusal smoke retained.
- **E2E:** the ghidrust live gate stays; a dispatch build produces all 10 assets at real versions.

## Out of scope (now)

- Signing the installers (still unsigned).
- Any live remote marketplace channel (explicitly rejected — C3).
- A unified master installer with per-component checkboxes (considered and rejected in favor of five standalone
  installers — see C5; the palette is the composition surface).
- Marketplace-level cross-plugin dependency enforcement (does not exist; not building it).

## Acceptance

1. The `clavity-v<N>` release page presents five standalone installers (10 assets) with a palette notes table; each
   installer installs exactly one member and references no other.
2. Running any member's installer registers that member's plugin from a **local** scoped marketplace under a
   **unique** name, with no network access required; binary members also place their binary on PATH, all from the
   embedded payload.
3. No installer bundles, downloads, or launches another member; there is no user-facing remote marketplace path.
4. Uninstalling a member deregisters its plugin, removes its marketplace entry (no dangling path), strips its PATH
   entry, and leaves other members untouched.
5. dotnet and classic still refuse to co-install.
6. The golden-header seed is installer-seeded to `~/.clavity/golden-header.seed.md`; agy-autotrain with no driver
   present still installs and captures, warning (non-blocking) that the header won't inject until a driver exists.
7. The five scoped marketplace manifests carry five distinct marketplace names (CI-asserted).

## Open items (all → plan)

- **O1** registration `[Code]`: shared `.iss` include vs helper `.exe` (lean: include).
- **O3** scoped manifests: generate from repo-root full manifest vs hand-maintain (lean: generate).
- **O4** agy-autotrain / commonmemory build source: `main` vs own branch (lean: `main`).
- **O5** dotnet on `main` vs a `dotnet` branch now that it no longer aggregates (explicit call in the plan).
