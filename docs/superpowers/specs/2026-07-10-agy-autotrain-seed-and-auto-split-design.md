# agy-autotrain — Seed / Auto Split Architecture — Design

**Status:** design (brainstormed 2026-07-10; four AGY-FIRST consult rounds + one AGY-AFTER panel folded across the
distribution sub-question; owner-confirmed the seed/auto split, the extend model, and the version-agnostic seed).
Component 2 **revised 2026-07-10** to the **split-file** golden-header model (a further AGY-FIRST consult; owner-ratified)
— superseding the earlier single-file two-region design and dissolving the region-aware read-modify-write risk.

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
  managed by the SEED/GROWTH split files (below), not the plugin system.
- **Agent plugin artifacts** — the `adversarial-panel-review` **skill** and the AGY-AFTER **hook** are discovered by the
  agent's plugin ecosystem, NOT read by the binary. Shipping them through the .exe installer would recreate the exact
  installer-ships-a-plugin **downgrade trap this design bans** (Component 3). They therefore ship in the **driver's
  marketplace plugin** (the `clavity-dotnet` / `clavity-classic` plugin — where the driving-protocol skills already
  live), which has a clean marketplace lifecycle. "Ships with the driver" = with the driver's *plugin*, not its .exe.

### 2. `agy-curate` becomes EXTEND, not OWNER — split files, assemble-at-read

**Two separate files, each with exactly one writer** (an AGY-FIRST consult surfaced this and the owner ratified it,
superseding the earlier single-file two-region design). Under the shared path `%USERPROFILE%\.clavity\`:

```
golden-header.seed.md     ← written ONLY by the driver install/update (from its bundled baseline)
golden-header.growth.md   ← written ONLY by agy-curate (rules promoted from learning)
```

The driver binary, on every ask, **reads both files and concatenates them SEED-then-GROWTH** (blank-line separated),
then injects the result. Each writer does a whole-file **atomic** write (temp → rename) of **its own file only**.

**Why split, not one file with regions:** two uncoordinated lifecycle actors (an OS installer and an async curator
skill) sharing one mutable file forces a region-aware read-modify-write, whose correctness is the whole game — a naive
overwrite clobbers the other owner's region, and two writers racing on one file can lose an update even with atomic
renames. Splitting the storage makes the clobber **structurally impossible** rather than correctness-dependent: there
is no shared mutable file, so there is no region parser, no read-modify-write, and no cross-writer lock to get right.
The injected bytes are identical to the single-file design (concatenation reproduces SEED-then-GROWTH).

- **No region markers.** The file boundary *is* the delimiter — no HTML-comment (or `#`-heading) SEED/GROWTH markers are
  needed inside the content, so nothing marker-shaped pollutes the injected prompt. (A file may optionally carry a
  one-line human-facing top comment naming its owner; it is not load-bearing and is subject to the size cap like any
  other content.)
- **Assemble at read.** The binary reads `golden-header.seed.md` (or empty if absent) and `golden-header.growth.md` (or
  empty if absent), concatenates SEED-then-GROWTH, applies the existing 16 KB cap to the **combined** result, and
  prepends. Neither file present ⇒ no header (the existing clean no-op; the add-on is simply not installed).
- **Driver install/update** writes only `golden-header.seed.md`. It never touches `growth.md`, so re-running the
  installer cannot clobber accumulated learning (this is the fix for the reinstall-downgrade trap identified earlier).
- **`agy-curate`** reads `seed.md` as the floor for dedup, promotes rules from the inbox, and writes only
  `golden-header.growth.md` — **regenerated wholesale** each run (idempotent; no duplicate rules accreting), deduped
  against SEED so a promoted rule already stated in SEED is dropped. It never touches `seed.md`.
- **Degradation.** With no driver, `seed.md` is absent and `agy-curate` still writes `growth.md` alone. With no
  agy-autotrain, `growth.md` is absent and the driver injects SEED alone — still competent.

**Residual robustness requirements (much smaller than the single-file design — most risks are now structural):**
- **Atomic per-file write.** Each writer's single-file write is still atomic (temp → rename) so a reader never sees a
  torn file. No cross-writer lock is needed — the two writers target different files and cannot race.
- **Migration from today's flat header (one-directional).** Existing installs have a single flat `golden-header.md`.
  The binary tolerates it on read: if `golden-header.seed.md`/`golden-header.growth.md` are both absent but a legacy
  flat `golden-header.md` exists, inject the legacy file (treat its content as GROWTH). `agy-curate` migrates it
  **automatically** on its next run — reads the legacy flat file as the GROWTH floor and writes `golden-header.growth.md`
  — with **no user action** (not "rename it yourself"). A new installer writing `seed.md` next to a legacy flat file is
  safe (the binary prefers `seed.md`+`growth.md` when present; the flat file is a fallback only). The one-directional
  risk to make explicit: an *old* driver binary reads only the flat `golden-header.md` and will not see the new split
  files — acceptable because the binary and its installer ship together in one release, so this skew only arises if the
  data is updated without the binary.
- **`.sha256` sidecar becomes per-file.** Each writer sidecars its own file (`golden-header.seed.md.sha256`,
  `golden-header.growth.md.sha256`). Active validation remains the deferred follow-on (today sidecars are written, not
  read).
- **`CLAVITY_GOLDEN_HEADER` override.** Today it names one file; under split it should resolve a **directory** (default
  `%USERPROFILE%\.clavity\`) so a test/CI can redirect both files together. Exact override shape is a plan detail.
- **Installer file ownership/ACLs.** The installer writes `seed.md` under `%USERPROFILE%\.clavity\` that `agy-curate`
  later writes alongside as a **standard user**. Verify the driver installer runs **per-user / non-elevated** (its
  target is `AppData\Local\Programs`, which normally does *not* require elevation) — in which case ownership is correct
  by construction. If any install path runs **elevated**, it must create the directory / `seed.md` with the interactive
  user's ownership, or a later standard-user `agy-curate` write fails with Access-Denied and silently breaks learning.

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
  writes `golden-header.growth.md` if it can, and emits a **non-blocking warning** — *"no clavity driver detected; the learned
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
3. **Curate-extend** — implement the split files: the driver install writes `golden-header.seed.md`, `agy-curate` owns
   only `golden-header.growth.md`, the binary assembles SEED-then-GROWTH at read; dedupe growth against seed; auto-migrate
   a legacy flat `golden-header.md` as GROWTH.
4. **Distribution** — driver README + installer post-install advertisement (verified install command); agy-autotrain's
   loud-guide warning; confirm agy-autotrain's marketplace listing/description as the AUTO add-on.

## Acceptance

1. A fresh clavity driver install (no agy-autotrain) drives agy competently: it has the manual, injects the
   `golden-header.seed.md` header, and can form review panels — all from the seed.
2. The seed contains no agy-version stamp and no driver-transport mechanics (grep-checkable).
3. Installing agy-autotrain and running `agy-curate` writes `golden-header.growth.md` without altering
   `golden-header.seed.md`; the driver injects SEED-then-GROWTH concatenated.
4. Re-running the driver installer rewrites `seed.md` and leaves `growth.md` intact (no learning lost); re-running
   `agy-curate` is idempotent (`growth.md` regenerated wholesale, no duplicate rules). A pre-existing *flat*
   `golden-header.md` is migrated without data loss (its content preserved as GROWTH), with no user action required.
5. agy-autotrain with no driver present: `agy-learn` captures; `agy-curate` emits the non-blocking warning (no crash,
   no hard block).
6. The driver installers advertise agy-autotrain (conditional wording) but do not ship the plugin; the marketplace is
   its sole installer.
