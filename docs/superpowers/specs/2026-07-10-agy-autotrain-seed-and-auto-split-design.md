# agy-autotrain — Seed / Auto Split Architecture — Design

**Status:** design (brainstormed 2026-07-10; four AGY-FIRST consult rounds + one AGY-AFTER panel folded across the
distribution sub-question; owner-confirmed the seed/auto split, the extend model, and the version-agnostic seed).

**One-line:** Split today's agy-autotrain into a **SEED** (curated, version-/driver-agnostic agy knowledge + driving
know-how that ships *inside* the clavity driver installer, so a fresh install drives agy well) and an **AUTO** add-on
(the learning loop that *extends* the seed from everyday use). agy-autotrain becomes the AUTO layer only.

---

## Problem

Today agy-autotrain bundles three different things into one plugin: (1) curated **knowledge** about the `agy` peer
(`agy-assumptions.md`, `agy-capabilities.md`), (2) **know-how** (the golden-header of learned rules; the
`adversarial-panel-review` panel discipline), and (3) the **auto-learning loop** (`agy-learn` capture, `agy-curate`
promote/compile, the `verify/` harness). This causes three problems:

1. **A driver without agy-autotrain drives "blind."** The golden header is purely an agy-autotrain product — installed
   alone, a clavity driver injects an *empty* header. The curated knowledge that would let it drive well (wording,
   panel-forming) is locked in the add-on.
2. **The knowledge is version- and driver-coupled, and it rots.** The files stamp "verified against agy 1.0.8/1.0.10"
   while live agy is 1.0.16; they lean heavily on one driver's transport (psmux/bus vs the gRPC LS). There is **no
   runtime mechanism to detect agy's version.**
3. **Ownership of the golden header is ambiguous** — one file, no clear seed-vs-growth boundary.

## Decision (owner-confirmed)

Split by **lifecycle**, not by topic:

- **SEED — static/curated, ships inside the driver.** Anything a fresh clavity install needs to drive agy competently:
  the agy manual, a golden-header **baseline**, driving/wording know-how, and the **panel-forming discipline** (the
  `adversarial-panel-review` skill + its AGY-AFTER reminder). Written **version-agnostic and driver-agnostic**;
  single-sourced in the monorepo and built into **each** driver variant's package.
- **AUTO — agy-autotrain, the optional add-on.** The learning loop only: `agy-learn` (capture), `agy-curate`
  (**extend** — not own), the `verify/` harness, the agy-learn reminder. Installed from the marketplace on top of a
  driver; it grows the seed from everyday use.

Rule of thumb: **static/curated ⇒ SEED (driver); auto-accumulating ⇒ AUTO (agy-autotrain).**

### Version-agnostic seed (owner principle)

Because there is no way to detect agy's version at runtime, **assume agy's behavior is stable** and write the seed as
**timeless behavioral claims** — no "verified against version X" stamps anywhere in the seed. (This supersedes the
earlier open question about light per-insight version tags: the seed carries none.) Keeping the knowledge current is
the AUTO layer's job, done from **observed** behavior (empirical capture), never from version tracking. Provenance in
the seed is limited to source class (`[corpus]`/`[doc]`/`[verified]`), not a peer-version anchor.

### Driver-agnostic seed

The seed states *what agy does* and *how to work with it* (verifies ≫ discovers; seed-the-invariants; form a panel of
distinct seats; word a review with a REVIEW-ONLY banner) — never *how a particular clavity variant reaches it*
(psmux verbs, bus REST schema, gRPC cascade ids, driver CLI names, driver source paths). Transport mechanics stay in
the respective driver's own docs.

## Components

### 1. Seed extraction (what moves out of agy-autotrain into the driver)

| Moves to the driver SEED | Stays in agy-autotrain (AUTO) |
|---|---|
| `knowledge/agy-assumptions.md`, `agy-capabilities.md` (scrubbed to version-/driver-agnostic) | `knowledge/agy-observations.md` (the raw capture inbox) |
| `knowledge/golden-header.md` **baseline** | `skills/agy-learn`, `skills/agy-curate` |
| the `adversarial-panel-review` skill + the AGY-AFTER reminder hook | `verify/` (assertions + harness) |
| driving/wording know-how | the agy-learn SessionStart/PreCompact reminder |

The seed is single-sourced in the monorepo (one canonical copy) even though two mutually-exclusive drivers each ship it.

**De-duplicate the per-variant driving skills (owner-approved).** Today both `clavity-ls-driving` (dotnet, MCP) and
`clavity-driving` (classic, CLI/psmux) embed agnostic protocol/panel know-how — both descriptions already say
"convening multi-lens review panels." That agnostic content is really seed. After the split, each driving skill keeps
**only its transport** ("how to mechanically reach agy" — `agy_ask` vs the CLI/psmux verbs) and **points at** the seed's
agnostic protocol + the `adversarial-panel-review` discipline, rather than re-embedding it. The agnostic protocol lives
once, in the seed; the two driving skills stop duplicating it.

**Delivery channel — split the seed by artifact TYPE (do not ship agent artifacts via the binary installer):**
- **Binary-consumed data** — the golden-header **baseline** and the agy manual (`agy-assumptions.md`/`agy-capabilities.md`
  as reference). The driver *binary* reads these; the Inno installer ships them as data files. Their lifecycle is
  managed by the SEED/GROWTH regions (below), not the plugin system.
- **Agent plugin artifacts** — the `adversarial-panel-review` **skill** and the AGY-AFTER **hook** are discovered by the
  agent's plugin ecosystem, NOT read by the binary. Shipping them through the .exe installer would recreate the exact
  installer-ships-a-plugin **downgrade trap this design bans** (Component 3). They therefore ship in the **driver's
  marketplace plugin** (the `clavity-dotnet` / `clavity-classic` plugin — where the driving-protocol skills already
  live), which has a clean marketplace lifecycle. "Ships with the driver" = with the driver's *plugin*, not its .exe.

### 2. `agy-curate` becomes EXTEND, not OWNER — the merge-without-clobber

The injected golden header lives at the shared path (`%USERPROFILE%\.clavity\golden-header.md`) and has **two
delimited regions**, each with a single owner:

```
<!-- <<< SEED (managed by the clavity driver — replaced on driver update; do not edit) >>> -->
   ...baseline agy rules shipped with the driver...
<!-- <<< END SEED >>> -->
<!-- <<< GROWTH (managed by agy-curate — appended from learning; do not edit) >>> -->
   ...rules promoted from everyday use...
<!-- <<< END GROWTH >>> -->
```

The markers are **HTML comments**, not `#` Markdown headings: the whole file is injected into every agy request, so a
`#`-prefixed marker would become a loud H1 ("do not edit") that pollutes the peer's context and wastes tokens. HTML
comments carry the delimiter for the two writers while staying low-signal in the injected prompt.

- **Driver install/update** writes/replaces **only the SEED region** (from its bundled baseline). It never touches
  GROWTH — so re-running the driver installer cannot clobber accumulated learning (this is the fix for the
  reinstall-downgrade trap identified earlier).
- **`agy-curate`** reads the SEED region as the floor, promotes rules from the inbox, and writes **only the GROWTH
  region** (deduped against SEED — a promoted rule already stated in SEED is dropped; a genuinely new/updated
  observation is appended with provenance).
- **The driver injects the whole file.** With no agy-autotrain, GROWTH is absent/empty and the driver injects SEED
  alone — still competent.

On driver install the installer **seeds the shared path** (writes the SEED region if absent, or replaces the existing
SEED region if the bundled baseline is newer), leaving any GROWTH region intact.

**Merge requirements & risks (the load-bearing, riskiest part — surfaced by the panel):**
- **Region-aware read-modify-write, not overwrite.** The installer must parse the existing shared file, replace *only*
  the SEED region, and re-emit GROWTH untouched. A naive whole-file overwrite reintroduces the very clobber this design
  exists to prevent. In Inno-Setup this is Pascal-script region editing — non-trivial; its complexity/feasibility is a
  first-class implementation risk to prototype early.
- **Atomic writes + single-writer discipline.** Two owners write one file (installer SEED, `agy-curate` GROWTH). Each
  write must be atomic (temp-file → rename) and should treat the file as single-writer at a time, so a driver install
  running concurrently with a curate cannot tear the file or drop a region.
- **GROWTH is regenerated wholesale, never appended incrementally** — so re-running `agy-curate` is idempotent (no
  duplicate rules accreting across runs); dedup runs against both SEED and the freshly-regenerated GROWTH.
- **Migration from today's flat header.** Existing installs have a single flat golden-header with no region markers.
  The first driver version that adopts this must migrate: treat a marker-less existing file as legacy GROWTH (preserve
  it) and write the SEED region around it, OR define a one-time conversion. A region-unaware *old* driver injecting a
  new regioned file still works (it injects the whole file), so the risk is one-directional (new writers must tolerate
  a legacy flat file); make that explicit.
- **Orphaned GROWTH / absent SEED.** `agy-curate` may run before any driver is installed (capture works standalone), so
  the shared file can hold a GROWTH region with **no SEED**. Both writers must tolerate this: `agy-curate` treats an
  absent SEED as an empty floor and emits a GROWTH-only file; a later driver install must inject its SEED region into a
  file that already has GROWTH-but-no-SEED. (This is the same read-modify-write robustness as migration.)
- **Installer file ownership/ACLs.** The installer seeds a file under `%USERPROFILE%\.clavity\` that `agy-curate` later
  rewrites as a **standard user**. Verify the driver installer runs **per-user / non-elevated** (its target is
  `AppData\Local\Programs`, which normally does *not* require elevation) — in which case ownership is correct by
  construction. If any install path runs **elevated**, it must seed the shared file with the interactive user's
  ownership/ACLs, or a later standard-user `agy-curate` write fails with Access-Denied and silently breaks learning.

### 3. Distribution & discovery (folds in the earlier distribution decision)

- **agy-autotrain stays a single first-class marketplace plugin** (one owner of the AUTO layer; one version-of-record;
  no bundling into the driver installer — bundling a plugin via a binary installer creates a competing version
  authority and a silent-downgrade loop, already witnessed this session as a repo/Programs/cache version skew).
- **Discovery is driver-side, guidance only:** each driver's README + installer post-install message advertise the
  add-on. The message is phrased conditionally (*"If you haven't already, add auto-learning: `<the correct
  agy-autotrain install command>`"*) so repeated driver updates don't train users to blindly re-install.
  - **Open item:** the exact install command must be the verified one for how agy-autotrain is actually installed on
    this setup (marketplace `claude plugin install …` vs the umbrella install script) — confirm before writing it into
    a shipped message. (An earlier draft asserted an unverified command; do not repeat that.)

### 4. Loud-guide degradation (agy-autotrain without a driver)

- `agy-learn` (capture → append to the inbox) needs no driver and always works.
- `agy-curate` needs the driver's SEED to extend and the driver to inject the result. With **no driver detected**
  (checkable signal: the clavity binary on `PATH`), it does **not** hard-fail and is **not** a hard block: it still
  writes the GROWTH region if it can, and emits a **non-blocking warning** — *"no clavity driver detected; the learned
  header won't be injected until a driver is installed."* (Non-blocking, per the AGY-AFTER panel finding: a `PATH`
  false-negative must not lock the user out of a file write that is otherwise harmless.)
- The panel discipline no longer lives here (it moved to the SEED), so agy-autotrain-without-a-driver has no panel
  responsibilities.

## Out of scope

- A marketplace-level dependency mechanism (does not exist; not building one).
- Making the panel escalation / `agy-curate` work over the **classic** driver's transport — gated on the unresolved
  "is clavity-classic still a live target, or frozen/legacy?" question; its own spec if pursued.
- Rewriting the driving-protocol skills (`clavity-driving`/`clavity-ls-driving`) — they already ship with the driver.

## Implementation phasing (for the plan)

1. **Agnostic scrub** — rewrite `agy-assumptions.md` + `agy-capabilities.md` to version-/driver-agnostic (relocate the
   driver-specific transport mechanics to each driver's own docs; drop version stamps).
2. **Seed extraction** — move the scrubbed knowledge + golden-header baseline + `adversarial-panel-review` + AGY-AFTER
   hook into a single-sourced seed built into each driver package; **thin `clavity-ls-driving` + `clavity-driving` to
   transport-only + a pointer to the seed** (remove the duplicated agnostic protocol/panel know-how).
3. **Curate-extend** — implement the SEED/GROWTH delimited regions; make the driver install seed the SEED region and
   `agy-curate` own only GROWTH; dedupe growth against seed.
4. **Distribution** — driver README + installer post-install advertisement (verified install command); agy-autotrain's
   loud-guide warning; confirm agy-autotrain's marketplace listing/description as the AUTO add-on.

## Acceptance

1. A fresh clavity driver install (no agy-autotrain) drives agy competently: it has the manual, injects the SEED golden
   header, and can form review panels — all from the seed.
2. The seed contains no agy-version stamp and no driver-transport mechanics (grep-checkable).
3. Installing agy-autotrain and running `agy-curate` appends a GROWTH region without altering SEED; the driver injects
   SEED+GROWTH.
4. Re-running the driver installer replaces SEED and leaves GROWTH intact (no learning lost); re-running `agy-curate`
   is idempotent (GROWTH regenerated wholesale, no duplicate rules). A pre-existing *flat* (marker-less) header is
   migrated without data loss (its content preserved as GROWTH under a fresh SEED region).
5. agy-autotrain with no driver present: `agy-learn` captures; `agy-curate` emits the non-blocking warning (no crash,
   no hard block).
6. The driver installers advertise agy-autotrain (conditional wording) but do not ship the plugin; the marketplace is
   its sole installer.
