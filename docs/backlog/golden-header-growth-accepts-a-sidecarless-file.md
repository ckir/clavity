# Backlog stub - the golden-header GROWTH reader accepts a sidecar-less file, so a direct write bypasses the human gate

**Status:** OPEN 2026-10-10 - raised by the Branch G plan panel (round 1, BS-1); the owner ruled it a follow-up item, not part of Branch G
**Raised:** 2026-10-10, AGY panel round 1 over `docs/superpowers/plans/2026-10-10-sweep-branch-g-human-gate.md`.
**Scope:** `clavity-classic/src/golden_header.rs` `try_read_file` and `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs` `TryReadFile` (the `SidecarVerdict.Absent` arm), plus `agy-autotrain/skills/agy-curate/SKILL.md`.

## The defect

Branch G makes both drivers refuse `driver-cheatsheet.growth.md` unless the `.sha256` sidecar written by `curate-commit --cheatsheet` matches, so only a publish through the verb (after the agy-curate human gate) is ever delivered. The golden header is the opposite: both readers ACCEPT a region file with no sidecar, because the installer seeds `golden-header.seed.md` without one. `golden-header.growth.md` is not installer-seeded, so the same "absent = accept" rule lets any writer put content on that live path with no verb and no approval.

## Why it was not folded into Branch G

- Branch G fixes a MEASURED defect: `SKILL.md` instructed a write of the cheatsheet to its live name 147 lines before the human gate, and a sentinel written that way was delivered on the next ask. `golden-header.growth.md` has no such pre-gate write; `curate-commit` is its only instructed writer and runs after the gate.
- Requiring the sidecar on GROWTH changes the legacy flat-file migration (`golden-header.md` is read ALONE as GROWTH) and degrades any hand-edited install. That needs its own design and its own failing control.
- The sidecar is documented as an integrity check, not a security control (anyone who can write the file can write the sidecar); here its value is stopping a writer that does not know to compute it.

## Fix direction (not chosen)

A per-region rule in the shared `verify_sidecar` / `VerifySidecar` verdict consumer: SEED keeps `Absent = accept`; GROWTH (and the legacy flat file read as GROWTH) degrade on `Absent` with the same visible warning. Needs: a decision on the legacy flat file; a migration note for installs whose GROWTH was written before `curate-commit` wrote sidecars; failing controls in both variants; a one-time republish for any sidecar-less live file.

**Reopen if:** not applicable while OPEN. The sweep's "nothing open" bar means this must be fixed or closed by ruling before the release.
