# Cohesive Distribution Model — Design

**Date:** 2026-07-11
**Status:** design — owner-approved model (2026-07-11); AGY-AFTER adversarial-panel **rounds 1–2 folded** (agy cascade
`0d033d59`). R1: idempotent-upgrade, `-LiteralPath` seeding, install rollback, structural local-only, PATH
false-positive, teardown scope; agy's "malformed marketplace CLI" claim refuted by the `PluginInstaller.cs` oracle.
R2: cross-member `~/.clavity` data-ownership (driver purge must not delete agy-autotrain `growth.md`), decoupled
per-member republish (no blocking sibling gate), manifest path/source contract, rollback exception-safety, upgrade
hygiene, repo-root manifest relocation; agy's ghidrust-seeds-golden-header example refuted (ghidrust has none). Owner
directed "go for green" — running rounds to a no-live-challenge pass.
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
   - **Claude Code:** `claude plugin marketplace add <app> --scope user` → `claude plugin install <plugin>@<unique-mkt> --scope user`;
   - **agy:** `agy plugin install <app>\plugins\<name>`.

**Named oracle for the exact commands (BLOCKING for the plan):** `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs`
(`Install` / `Uninstall`, lines 17–45). The plan MUST copy these argument vectors **verbatim** — do not guess a
signature. Verified there: `marketplace add` takes the **path** as its positional arg (there is **no** marketplace-name
positional — the name is read from the manifest's own top-level `name`); `plugin install` takes `<plugin-name>@<marketplace-name>`;
agy takes the local plugin dir; uninstall is `claude|agy plugin uninstall <plugin-name>`. (An adversarial review claimed the
`marketplace add` signature was malformed and required a name positional — **refuted by this oracle**.)

**Idempotent re-run / upgrade (BLOCKING — folded).** A user re-runs an installer to upgrade in place, so registration
MUST be idempotent: an already-added marketplace or already-installed plugin is a **success**, not a fatal error. The
current `PluginInstaller` treats a non-zero `marketplace add` as fatal (`PluginInstaller.cs:23`) with no
already-registered tolerance — the plan must add that tolerance (detect/ignore "already exists", or remove-then-add),
or an upgrade abort traps the user on the stale version.

**Per-agent semantics (folded).** Detection can find Claude, agy, both, or neither. Register each detected agent
**independently** and report per-agent; treat the install as failed only if **every** detected agent's registration
fails (a genuine no-op install) — a partial success (Claude ok, agy fails) reports the failure but does **not**
silently roll the successful one back without saying so. "No agent detected at all" is a clear message + non-zero exit.

Plugin-only members (agy-autotrain, commonmemory) do exactly this with **no binary step** — their `.exe` is small
(plugin assets + registration logic only).

**Install-time rollback (folded), best-effort and exception-safe (folded R2 — Cascade).** If a step **after** a
successful plugin registration fails (binary unpack, PATH, a second agent), the installer must **deregister** what it
registered (plugin uninstall + `marketplace remove`) before aborting — otherwise a failed *install* leaves the same
dangling-marketplace state C6 guards against on *uninstall*. The rollback MUST track **which** agents actually
registered (deregister only those), and **swallow every teardown error** — an unhandled exception in an Inno `[Code]`
rollback halts mid-cleanup and re-creates the exact dangling state it exists to prevent. Rollback is best-effort:
report if it cannot fully reverse, never throw.

**Scoped-manifest path/source contract (BLOCKING — folded R2, Activation Auditor).** For `plugin install <plugin>@<mkt>`
to resolve, each installer MUST place its scoped manifest at exactly `{app}\.claude-plugin\marketplace.json` and list
the plugin with `source: ./plugins/<name>` matching where it staged the plugin (`{app}\plugins\<name>`). A path/source
mismatch resolves nothing → C1's fatal-abort fires on every install. The scoped-manifest generator (O3) owns this shape.

**Upgrade hygiene (folded R2 — State Corruptor).** Inno `ignoreversion` overwrites but never **deletes** files a newer
plugin version dropped. On a re-run/upgrade the installer must clear `{app}\plugins\<name>` before re-staging (or the
marketplace re-reads orphaned files). Pairs with the idempotent-registration rule above.

**Concurrent installs (folded R2 — State Corruptor).** The five installers share no setup mutex (unlike today's single
`ClavitySetupMutex`), yet each `claude plugin marketplace add` mutates Claude's **global** config. The plan must
confirm the claude/agy CLIs serialize their own config writes; if not, add a shared cross-installer setup mutex so two
simultaneous installs cannot tear Claude's config. **Open (plan) O6.**

**Open (plan) O1** — factor the registration `[Code]` into a shared `.iss` include (DRY across five installers) vs a
tiny shared helper `.exe`. Lean: shared `[Code]` include. This is also the **mitigation for the 1→5 decentralization
cost** (F3): C1 moves the claude/agy CLI contract from one place (`PluginInstaller`) into five installers, so an upstream
CLI drift breaks all five at once — a single shared include keeps the command strings in **one** editable place.

### C2 — Binaries embedded, not downloaded

The three binary members embed their binary in `[Files]` (Inno LZMA2, `SolidCompression`). Unpack to
`{app}`; PATH-append `{app}` (never prepend — PATH hygiene) when the PATH task is selected. There is **no**
download/opt-in/launch mechanism anywhere — that eliminates the whole runtime-download attack surface (TOCTOU,
same-release hash-theatre, effective-tag/404, offline-install breakage). A binary lives once, inside its installer.

### C3 — Local-only: no competing version authority

There is **no** user-facing remote marketplace. `claude plugin marketplace add ckir/clavity` is **not** a supported
install path and is not advertised anywhere (README, release notes, finish pages). The only way to obtain a member is
to download and run its installer from the release page.

**"Local-only" must be STRUCTURAL, not just unadvertised (folded — F1).** `ckir/clavity` is a public repo; if a valid
`marketplace.json` sits at the repo root under `.claude-plugin/`, `claude plugin marketplace add ckir/clavity` **works
for anyone regardless of advertising** — so merely "not documenting it" leaves the exact version-skew door this reset
closes wide open, and an acceptance test that only reviews docs would false-GREEN. Therefore the internal build source
that we slice the per-installer scoped manifests from is **NOT** a Claude-addable `.claude-plugin/marketplace.json` at
the repo root: keep the full five-member list as a plain build data file (e.g. `build/members.json`, or inline in
`umbrella-release.yml`) that is **not** a valid marketplace manifest at an addable path. If a repo-root
`.claude-plugin/marketplace.json` must exist for another reason, the spec must say so and explicitly own the residual
latent remote path rather than claiming skew is impossible. Acceptance #3 is testable accordingly (assert no addable
root marketplace manifest resolves).

**Why local-only (agy's call, owner-ratified):** a member's binary and its companion plugin always arrive together,
from one `.exe`, at one version, so the binary↔plugin execution contract can never skew. Offering a remote backdoor
would reintroduce exactly the silent-downgrade loop this reset eliminates (update the plugin remotely while the binary
stays stale). Trade-off accepted: a plugin-only member is obtained by running a small `.exe` rather than by remote
zero-install discovery — acceptable in exchange for ironclad version parity and offline capability.

### C4 — Golden-header baseline seed → installer payload (not the plugin)

The two **agy-driver** binary members — clavity-dotnet and clavity-classic **only** (ghidrust has **no** golden-header;
it is a Ghidra RE tool) — carry a small **data** file their binary reads at runtime: the golden-header baseline
(`seed/golden-header.md`). It is neither an agent plugin asset nor the binary. It ships in the **installer's file
payload** and is seeded to a stable user-profile path (`%USERPROFILE%\.clavity\golden-header.seed.md`) via standard
PowerShell post-install (as today; unconditional — the SEED ships even without the agy-autotrain add-on).

**Why the installer, not the plugin (agy point D):** the seed is configuration consumed by the *host driver binary*.
Putting it inside a plugin would couple the binary's runtime to the agent's opaque plugin-extraction paths. Seeding it
to the user profile gives the binary a stable, OS-native path fully decoupled from the agent's plugin lifecycle. This
matches the split-file SEED/GROWTH design already implemented (`golden-header.seed.md` written by the installer;
`golden-header.growth.md` written by agy-curate; binary assembles SEED-then-GROWTH at read).

**Bracket-/quote-safe path handling (BLOCKING — folded, Boundary Smuggler).** All path-bound PowerShell in the seeding
step MUST treat the profile path literally: use `-LiteralPath` on **every** path cmdlet (`New-Item`, `Test-Path`,
`Copy-Item` source **and** any destination resolution), plus the existing single-quote doubling. A profile such as
`C:\Users\J[x]` makes `[` a globbing wildcard for non-literal cmdlets, so a bare `New-Item -Path` silently fails to
create `~/.clavity` and the seed is dropped. (The shipped code already uses `-LiteralPath` on the `Copy-Item` source
but **not** on `New-Item -Path` — the plan must close that gap for all five path uses.)

### C5 — Mutual exclusion (dotnet XOR classic)

The dotnet and classic installers keep the existing mutual-exclusion refusal: each aborts at `InitializeSetup` if the
other variant is detected (in-process PATH scan for the `clavity` stem; the `Software\clavity\classic` registry
marker). This is another reason the model is **five standalone installers, not one master installer with checkboxes**:
a single installer would have to enforce radio-button exclusivity between two of its own driver checkboxes, which is
clumsier than two installers that refuse each other.

**Known limitation (folded — low severity, Cascade).** The PATH-scan can false-positive on a `clavity` entry the
current user cannot remove (another user's profile on the machine PATH, or a stray manual entry) → a per-user install
of the other variant refuses and the standard user may lack rights to clear the blocker. The per-user
`HKCU\Software\clavity\<variant>` registry marker is the sounder, self-scoped signal; the plan should prefer it and
treat a PATH-only hit as advisory. Documented as an accepted edge, not blocking.

### C6 — Uninstall robustness; no dangling marketplaces (agy failure-mode A1)

A failed uninstall or a manually-deleted `{app}` leaves a dead local marketplace path in Claude's registry that then
errors on every future plugin operation. Each installer's uninstall therefore:

- deregisters the plugin from each agent (`claude plugin uninstall <name>@<unique-mkt>` / agy removal) **and**
  `claude plugin marketplace remove <unique-mkt>` — so no registry entry outlives the files;
- tolerates a missing exe/dir (fail-open so Add/Remove Programs can still complete);
- (dotnet/classic) preserves the existing zombie-header backup of `~/.clavity` files when keeping user data.

**Shared `~/.clavity` state is owned per-file, never blind-deleted (folded R2 — Axiom Breaker).** `~/.clavity` is
shared state written by more than one member: a driver seeds `golden-header.seed.md`; agy-autotrain writes
`golden-header.growth.md`. Because the installers are standalone and disjoint, teardown must respect ownership rather
than wipe the shared dir: a **driver** uninstall/purge removes only **driver-owned** files (`seed.md`, its `.sha256`,
the legacy flat file) — it must **not** delete agy-autotrain-owned `golden-header.growth.md`; `growth.md` is removed
only when **agy-autotrain** is uninstalled. This is the split-file ownership already defined in the seed/auto-split
spec; the cohesion model must not regress it into a blind `~/.clavity` delete that rips out a sibling's data. The seed
file itself is teardown-managed **by the binary** (`clavity-ls uninstall --purge-data` / the zombie-header backup),
**not** by Inno's `[Files]` uninstall tracking (it was written out-of-band to the profile, so `[Files]` never sees it).

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
- **Release coupling — decoupled by design (folded R2 — Activation Auditor).** A *full* umbrella build publishes all
  10 assets together, but a single member MUST be independently re-buildable and re-publishable onto the **existing**
  `clavity-v<N>` release via a per-member `workflow_dispatch`, so one member's blocking gate (e.g. a flaky
  `e2e-ghidrust` network fetch) cannot freeze an unrelated `clavity-dotnet` / `agy-autotrain` hotfix. The umbrella
  release is the stable *catalog* (one page, cohesive), **not** an all-or-nothing publish barrier — otherwise the
  atomic-publish requirement re-couples exactly the members this design decouples. (Owner-delegated call, 2026-07-11:
  "go for green" — resolved toward per-member republish rather than a blocking all-5 gate.)

**Open (plan) O4** — agy-autotrain / commonmemory currently live on `main` as plugin dirs. Keep building them from
`main` (pure plugin content, no binary → a branch is optional) unless a reason emerges. **O5** — with the dotnet
installer no longer aggregating umbrella content, revisit whether `dotnet` stays on `main` or moves to a `dotnet`
branch for symmetry; flag for an explicit call in the plan, not decided here.

### C9 — Unique marketplace name per installer (BLOCKING correctness — agy failure-mode B)

`PluginInstaller` today uses a single const `MarketplaceName = "clavity"`. If all five installers register a local
marketplace under the **same** name, the last install **steals the namespace** and silently breaks every previously
installed member's plugin resolution. The **unique thing is the scoped `marketplace.json`'s top-level `name` field**
(verified oracle: `claude plugin install <plugin>@<name>` resolves the manifest's `name`, `PluginInstaller.cs:25`) —
**not** the plugin name, which stays the member's real name. Each installer's scoped manifest MUST carry a **unique**
top-level `name` — e.g. `clavity-dotnet`, `clavity-classic`, `clavity-ghidrust`, `clavity-agy-autotrain`,
`clavity-commonmemory` — and its `plugin install <plugin>@<that-name>` must match. Each installer also keeps a
**distinct** `DefaultDirName` (`…\Programs\<member>`) so their `{app}\.claude-plugin\marketplace.json` + `{app}\plugins`
never clobber each other.

**Open (plan) O3** — generate the scoped 1-entry manifests (with the rewritten unique `name`) from the repo-root full
manifest via a small build step, vs hand-maintain five files. Prefer **generate** to avoid drift.

### C10 — Migration / teardown of the current bundled model (IN SCOPE — folded, F4)

This design does not just *add* five installers — it **removes** the current bundled machinery, and the plan must
enumerate that teardown so the new and old cannot coexist and contradict:

- **`clavity-dotnet.iss`:** delete the opt-in add-on `[Tasks]` (`install_agy_autotrain`, `install_commonmemory`),
  the `InstallAddon` calls + the uninstall `--plugin agy-autotrain|commonmemory` deregistration, and the cross-plugin
  `[Files]` staging of `agy-autotrain` / `commonmemory` / `ghidrust` under `{app}\plugins`. It keeps only its **own**
  plugin + binary + seed.
- **`build-dotnet.yml`:** remove the flat 4-plugin `marketplace.install.json` generation and the smoke assertions that
  the sibling plugins are bundled under `{app}\plugins` (`agy-autotrain`, `commonmemory`, `ghidrust`); replace with the
  single-member assertion + the C9 unique-name / C6 no-dangling checks.
- **New installers:** `agy-autotrain` and `commonmemory` gain their own plugin-only installers (they have none today);
  `ghidrust`'s installer gains local plugin self-registration (today it ships binary-only, plugin via remote marketplace).
- **Relocate the repo-root marketplace manifest (folded R2 — required by C3/E).** The existing
  `.claude-plugin/marketplace.json` at the repo root is publicly `marketplace add`-able and so defeats local-only;
  move the full member list to the non-addable build source (`build/members.json`) and re-point `build-dotnet.yml`'s
  scoped-manifest generation at it. Leaving the root manifest in place silently re-opens the version-skew path.

## Failure modes (agy consult) and disposition

| # | Failure mode | Disposition |
|---|---|---|
| A1 | Dangling local marketplace after failed **uninstall** / manual delete | Mitigated — C6 (deregister marketplace on uninstall; fail-open) |
| A1′ | Dangling marketplace after a failed **install** (register-then-fail, no rollback) | Mitigated — C1 install-time rollback (deregister before abort) |
| A2 | Cross-member update drift (dotnet v2 + agy-autotrain v1) | Accepted — low-stakes by design: plugins are variant-agnostic; the binary↔*own*-plugin contract can't skew (C3). Not the master-installer's problem to solve here. |
| A3 | Dependency blindness (agy-autotrain needs a driver) | Handled at runtime — C7 loud-guide warning |
| B | Marketplace-name collision steals the namespace | Blocking requirement — C9 unique top-level manifest `name` per installer |
| C | Re-run/upgrade abort on idempotent "already registered" | Blocking requirement — C1 idempotent registration |
| D | `[`/`'` in profile path breaks PowerShell seeding (globbing) | Blocking requirement — C4 `-LiteralPath` on all path cmdlets |
| E | Local-only defeated by a public repo-root addable manifest | Mitigated — C3 keeps the build source non-addable (not a root `.claude-plugin/marketplace.json`) |
| F | claude/agy plugin CLI drift breaks all five installers at once | Accepted + mitigated — C1/O1 shared include keeps the contract in one editable place; PluginInstaller.cs is the named oracle |
| G | Mutual-exclusion PATH false-positive traps a per-user install | Accepted (low) — C5 prefers the per-user registry marker; PATH hit advisory |
| H | Driver purge blind-deletes agy-autotrain's `growth.md` (sibling data) | Blocking requirement — C6 per-file ownership (driver removes `seed.md` only) |
| I | Blocking sibling gate freezes an unrelated member's hotfix | Mitigated — C8 per-member republish onto the rolling umbrella release |
| J | Scoped manifest path/source mismatch → every install fatally aborts | Blocking requirement — C1 manifest path/source contract |
| K | Rollback throws mid-cleanup → dangling state it meant to prevent | Mitigated — C1 rollback is per-agent-tracked + exception-swallowing |
| L | Upgrade orphans stale plugin files / concurrent installs tear Claude config | Mitigated — C1 upgrade-clean + O6 concurrent-install serialization |

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
3. No installer bundles, downloads, or launches another member; **no addable Claude marketplace manifest resolves at
   the repo root** (`marketplace add ckir/clavity` finds nothing) — local-only is structural, not documentation.
4. Uninstalling a member deregisters its plugin, removes its marketplace entry (no dangling path), strips its PATH
   entry, and leaves other members untouched. A **failed install** likewise leaves no dangling marketplace (rollback).
5. dotnet and classic still refuse to co-install.
6. The golden-header seed is installer-seeded to `~/.clavity/golden-header.seed.md` (surviving a profile path
   containing `[` `]` or `'`); agy-autotrain with no driver present still installs and captures, warning
   (non-blocking) that the header won't inject until a driver exists.
7. The five scoped marketplace manifests carry five distinct top-level `name`s (CI-asserted).
8. **Re-running an installer over an existing install upgrades in place** — idempotent registration does not abort on
   an already-added marketplace / already-installed plugin.
9. Registration runs per detected agent independently; a partial (one-agent) failure is reported, not silently
   dropped, and does not leave a half-registered install without rollback (rollback is per-agent-scoped and cannot
   itself throw the installer into a dangling state).
10. Uninstalling a driver removes only driver-owned `~/.clavity` files (`seed.md` + sidecar + legacy flat); a
    co-installed agy-autotrain's `golden-header.growth.md` survives (removed only by agy-autotrain's own uninstall).
11. A single member can be rebuilt and republished onto the existing `clavity-v<N>` release without any sibling's
    build/gate passing (no blocking sibling freezes an unrelated hotfix).

## Open items (all → plan)

- **O1** registration `[Code]`: shared `.iss` include vs helper `.exe` (lean: include).
- **O3** scoped manifests: generate from repo-root full manifest vs hand-maintain (lean: generate).
- **O4** agy-autotrain / commonmemory build source: `main` vs own branch (lean: `main`).
- **O5** dotnet on `main` vs a `dotnet` branch now that it no longer aggregates (explicit call in the plan).
- **O6** concurrent-install serialization: confirm the claude/agy CLIs lock their own global config, else add a shared
  cross-installer setup mutex.
