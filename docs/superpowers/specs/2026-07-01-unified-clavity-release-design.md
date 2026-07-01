# Unified `clavity` release (umbrella of both variants) — design

## Goal

Replace the two independent per-variant GitHub Releases (`clavity-dotnet-v*`, `clavity-classic-v*`) with a **single
umbrella release named `clavity`** that bundles **both** installers. Each variant keeps its **own independent
version** (in the artifact filename); umbrella releases are **point-in-time snapshots with history**, cut on a
serial `clavity-v<N>` tag. Going forward, **only `clavity` releases are produced**; the existing per-variant
releases are frozen as history.

**Decided (owner):**
- Versioning model: **independent per-variant versions, umbrella release** (not lockstep, not rolling).
- Build/trigger: **Option D — orchestrator + reusable workflows** (agy-consulted, owner-approved).
- Umbrella tag scheme: **serial** `clavity-v1`, `clavity-v2`, … (a bundle counter; deliberately NOT a semver, to
  avoid confusion with the variants' own `0.1.x`).
- Existing per-variant releases (11) + their tags: **kept as frozen history**; their tag-triggered release
  workflows are **retired** (no new per-variant releases).

## Current state (verified 2026-07-01)

- **dotnet** — `.github/workflows/release-clavity-dotnet.yml` on `main`, triggers on tags `clavity-dotnet-v*` **and
  bare `v*`**. Builds a self-contained single-file `clavity-ls.exe` → Inno Setup `dist/clavity-dotnet-setup.exe`
  (+`.sha256`) → install/uninstall + mutual-exclusion smoke → publishes a per-variant Release. Version hardcoded in
  `installer/clavity-dotnet.iss` (`#define AppVersion`, now `0.1.9`). Runner `windows-latest`.
- **classic** — `.github/workflows/release-clavity-classic.yml` on the `clavity-classic` branch, triggers on
  `clavity-classic-v*`. Rust build → Inno `clavity-classic-setup.exe` (+`.sha256`) → per-variant Release. Version in
  `installer/clavity-classic.iss`. Runner `windows-2022` (pinned for a stable toolchain), `concurrency` guard.
- Installer filenames are currently **un-versioned** (`clavity-<variant>-setup.exe`); the version lives only in the
  release tag and inside the installer.

## Architecture — Option D

Three workflows replace the two per-variant release workflows:

### 1. `build-dotnet.yml` — reusable (`on: [workflow_call, workflow_dispatch]`), on `main`
`workflow_dispatch` is included so a dotnet installer change can still be built/tested in isolation without cutting
an umbrella (audit round 1, DevEx). The build+smoke half of today's `release-clavity-dotnet.yml`, minus the release step:
- publish single-file `clavity-ls.exe`; build the Inno installer; run the install/uninstall + mutual-exclusion
  smoke steps unchanged (still gate: a broken installer must not proceed).
- **Version filename at build time** (see §Version + filename).
- Upload `clavity-dotnet-setup-<ver>.exe` + `.sha256` as an **Actions Artifact** (`actions/upload-artifact`) —
  **not** a Release.
- Expose `outputs`: `version`, `sha` (`${{ github.sha }}` of the building ref), `artifact-name`.

### 2. `build-classic.yml` — reusable (`on: [workflow_call, workflow_dispatch]`), on the `clavity-classic` branch
Identical treatment for the Rust build; keeps `runs-on: windows-2022`. Uploads
`clavity-classic-setup-<ver>.exe` + `.sha256` as an Actions Artifact; outputs `version`, `sha`, `artifact-name`.
**Must be committed on the `clavity-classic` branch** so the orchestrator can call it cross-branch.
**Takes a `ref` input** (a classic-branch commit SHA) and does `actions/checkout` with `ref: ${{ inputs.ref }}`
so the built code is PINNED, not the floating branch HEAD (audit round 1 — see Reproducibility below).
`workflow_dispatch` defaults `ref` to the branch tip for isolated manual test builds.

### 3. `umbrella-release.yml` — orchestrator, on `main`, `on: push: tags: ['clavity-v*']`
```
jobs:
  resolve-classic:                      # pin the classic commit ONCE, at cut time (see Reproducibility)
    outputs: { sha: <resolved classic-branch tip SHA> }
    - sha=$(git ls-remote <repo> refs/heads/clavity-classic | cut -f1)   # or an operator-supplied SHA
  dotnet:  { uses: ./.github/workflows/build-dotnet.yml }                 # builds this tag's main commit
  classic:
    needs: resolve-classic
    uses: <owner>/<repo>/.github/workflows/build-classic.yml@clavity-classic   # FILE ref (stable)
    with: { ref: ${{ needs.resolve-classic.outputs.sha }} }              # CODE checkout is PINNED
  publish:
    needs: [dotnet, classic]
    permissions: { contents: write }
    - download both artifacts
    - create ONE GitHub Release named "clavity <tag>" for the clavity-v<N> tag, attaching:
        clavity-dotnet-setup-<dv>.exe (+ .sha256)
        clavity-classic-setup-<cv>.exe (+ .sha256)
    - auto-generate the release body from the build outputs (see §Traceability), incl. the pinned classic SHA
```
- **`concurrency: group: release-clavity, cancel-in-progress: FALSE`** — a publish pipeline creates a release object
  then uploads 4 assets sequentially (not atomic); `cancel-in-progress: true` (as classic uses) could assassinate a
  run mid-upload and leave a PARTIAL public release (audit round 1). Queue, never cancel.
- The old dotnet workflow's bare `v*` and `clavity-dotnet-v*` triggers are removed with its retirement (see
  Migration — tag deprecation).

### Reproducibility — pinning the classic commit (audit round 1)
`uses: …/build-classic.yml@clavity-classic` resolves the workflow FILE from the branch (stable — the file rarely
changes), but a reusable workflow's `actions/checkout` defaults to that same floating ref, so a **re-run of
`clavity-v1` weeks later would rebuild whatever `clavity-classic` HEAD is then** — silently changing a historical
snapshot. The orchestrator therefore **resolves the classic tip SHA once at cut time** and passes it as the `ref`
input that `build-classic.yml` checks out; the resolved SHA is **recorded in the release body**. For a guaranteed
byte-identical re-cut, an operator can supply the exact SHA (via `workflow_dispatch`) instead of the auto-resolved
tip. (The dotnet side is already pinned: the `clavity-v*` tag IS a main commit.)

## Version + filename

- Each variant's **shipped version = its installer `.iss` `AppVersion`** (the authoritative version already used to
  stamp the installer + Add/Remove-Programs). Extract it in the reusable workflow (read `#define AppVersion "X.Y.Z"`
  from the variant's `.iss`) and surface as the job `version` output.
- Emit the **versioned filename directly from Inno** by setting `OutputBaseFilename=clavity-<variant>-setup-{#AppVersion}`
  in each `.iss` (small, local change; keeps ISCC as the single place that names the artifact). The `.sha256`
  companion is computed over the final versioned file (`"<hash>  <filename>"`, unchanged format —
  `install/clavity-install.ps1` parses the first token).

## Traceability (release body, auto-generated)

The `publish` job writes the release notes from the two build jobs' outputs:
```markdown
# clavity <clavity-vN>
| variant | version | source |
|---------|---------|--------|
| dotnet  | 0.1.9   | main@<sha>            |
| classic | 0.1.0   | clavity-classic@<sha> |

The two variants are **mutually exclusive** on a machine — install ONE. See each installer's SmartScreen note
(unsigned).
```
This records exactly which source commit each bundled installer was built from — the umbrella is a snapshot of two
branches at arbitrary points, so the SHAs are the proof of what shipped.

## Migration

- First umbrella: push tag **`clavity-v1`** → bundles dotnet `0.1.9` + classic `0.1.0` (current versions).
- **Retire** `release-clavity-dotnet.yml` and `release-clavity-classic.yml` (delete, after their build bodies move
  into the reusable `build-*.yml`). The 11 existing per-variant releases + their tags are **left untouched** as
  frozen history (not deleted, not hidden).
- **Tag deprecation (audit round 1):** after retirement, the ONLY tag that produces a release is `clavity-v*`.
  Bare `v*`, `clavity-dotnet-v*`, and `clavity-classic-v*` tags will trigger NOTHING (silent "ghost" tags). This
  must be stated in `CONTRIBUTING.md`/release runbook; the old tags are NOT remapped to the orchestrator (they carry
  variant semvers, not the umbrella serial — remapping would reintroduce the confusion this design removes).
- `install/clavity-install.ps1` (the PowerShell chooser that fetches "the latest release") must be made
  **backward-compatible (audit round 1 — deployment-order race):** it is live code users fetch from `main`, so
  whichever ships first (the script update or `clavity-v1`) must not break the other. It MUST try the umbrella
  release + versioned, variant-prefixed asset names AND fall back to the legacy per-variant releases + un-versioned
  `clavity-<variant>-setup.exe`. (Verify its current asset-match + latest-release logic at plan time.)
- **`README.md` update (final deliverable — owner-requested):** the README's `## Install (one command)` section
  (and the `## clavity-dotnet` section) describe the release/asset model, so they must be updated to the umbrella
  model — the single `clavity` release, both variants' versioned installers, and the (now variant-aware) install
  one-liner. **Also fix the STALE note** at README ~L45-47 that claims the classic variant is "a planned follow-on"
  installed via `cargo` — classic already ships a packaged `clavity-classic-setup.exe` (v0.1.0), and the umbrella
  release makes both installers first-class. This is the LAST plan task (do it after the workflows + `install.ps1`
  land, so the docs match shipped behavior).

## Testing

- Each reusable workflow **retains its own smoke test** (install/uninstall lifecycle + mutual-exclusion refusal),
  so a broken installer fails its build job before the umbrella can publish.
- `publish` `needs: [dotnet, classic]` — either build/smoke failing means **no umbrella release** is created.
- Manual acceptance for the first cut: push `clavity-v1`, confirm the single `clavity` release appears with all four
  assets (2 exe + 2 sha256), correct versioned names, and an accurate traceability table; confirm each `.sha256`
  verifies against its exe.

## Out of scope

- No change to installer **behavior**, the mutual-exclusion guard, or either variant's version **cadence**.
- No change to the classic source (only its release plumbing moves to a reusable workflow + its `.iss`
  `OutputBaseFilename`).
- Signing / SmartScreen (installers remain unsigned — owner decision, inherited).
- Deleting or hiding the historical per-variant releases (explicitly kept).

## Accepted limitations / risks

- **Cross-branch `workflow_call`** requires `build-classic.yml` to live on the `clavity-classic` branch with
  `on: workflow_call`; changes to the classic build must be committed there. Coordination cost, accepted.
- The umbrella **rebuilds both variants from source** on each `clavity-v*` (it does not reuse a prior per-variant
  release's binary). Accepted — it gives from-source reproducibility, and each build re-runs its smoke gate.
- The umbrella version (`clavity-vN`) is a **third** version line to advance manually; the release title/body carry
  the meaningful per-variant versions so the serial number needs no semantic meaning.
- **Fork `uses:` limitation (audit round 1):** the orchestrator hardcodes `<owner>/<repo>/…/build-classic.yml@clavity-classic`
  (GitHub Actions forbids expressions like `${{ github.repository }}` in `uses:`). A fork therefore references the
  UPSTREAM reusable workflow, so a fork cannot test its own umbrella pipeline unchanged. Low impact for a
  single-owner repo; documented, not worked around. (This is a "can't self-test in a fork" nuisance, not the
  fork-runs-untrusted-code hazard — the direction is the reverse.)
