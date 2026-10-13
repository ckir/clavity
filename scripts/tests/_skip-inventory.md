# Pester skip inventory

This file is GENERATED, never hand-edited. Regenerate it with:

    pwsh scripts/run-pester-parallel.ps1 -Directory scripts/tests -SkipInventory scripts/tests/_skip-inventory.md -WriteSkipInventory

and review the diff in the PR: a new row is a new skip somebody has to justify.

The gate (`scripts/run-pester-parallel.ps1`, enforced by `just test-scripts`) fails the run on:

- an UNAPPROVED SKIP: a skipped row with no approval written in the test itself;
- an OS-TAG MISMATCH: a `WindowsOnly`/`LinuxOnly` row that ran on the wrong OS, or a row tagged for the current OS that skipped without an `APPROVED:` reason;
- a stale `static` table (a skipped static row that is not listed, or a listed one that no longer skips);
- an unlisted `conditional` skip (a listed conditional row that did not skip is fine: a tool or root state may differ per host);
- a missing `## <os>` section for the OS the run is on (fails closed).

Approval vocabulary (closed). A skipped row is approved by a `-Tag` (its own or an enclosing block's) or, for a run-time
`Set-ItResult -Skipped`, by `-Because 'APPROVED:<tag>: <why>'`:

- `WindowsOnly`, `LinuxOnly` - static, listed in `### static`;
- `NotAsRoot` - the row cannot run as root;
- `NeedsTool:<name>` - a tool is absent (`<name>` matches `[A-Za-z0-9._-]+`);
- `FsFeature:<name>` - a filesystem feature is absent (same `<name>` rule).

The last three are conditional, listed in `### conditional`. A listed line is documentation, never a grant: approval lives in the test.

<!-- UNMEASURED 2026-10-13: the windows section does not exist yet; the gate fails closed on Windows until the owner runs the generator there and commits the result -->
