# Coverage debt and accepted test boundaries

The rolling, committed output of **AGY-TEST-AUDIT**. It holds only what must persist between audits:
owner-deferred coverage gaps (tracked debt) and the accepted-boundary ledger (the do-not-re-raise list).
Closed gaps are REMOVED from this file, not marked done.

Per-run audit reports are ephemeral and are NOT committed - they live under `.clavity/scratch/`.

> **Re-validate before honouring a do-not-re-raise entry.** Each accepted boundary records the specific
> compensation that justifies it. An entry whose compensation has vanished from the code is promoted back
> to a live gap - the ledger is not a permanent amnesty.

---

## Tracked debt - verified gaps the owner deferred

### 1. `'still subtracts the REAL build directories, by anchored path'` is a parser test, not a corpus test

- **Where:** `scripts/tests/check-injected-context.Tests.ps1`, the `-ForEach` row over five build paths.
- **What it asserts:** `Test-IsIgnored -RelPath $Rel -Globs (Get-IgnoreGlobs ...) | Should -BeTrue`.
- **What its name claims:** that those paths are subtracted from the audited corpus.
- **The gap:** it never runs the corpus walk. It would still pass if the walk stopped consulting the
  ignorelist entirely, because the glob itself would still match the path.
- **The regression that would slip through:** a change to `Get-InjectedContextFiles` that drops the
  `Test-IsIgnored` call. The corpus would silently grow by a virtualenv and every ignored build artifact,
  and this row - the one named for the behaviour - would stay green.
- **The test that should exist:** assert `Get-InjectedContextFiles -RepoRoot $d` does NOT contain each of
  those five paths, against a fixture that actually plants them.
- **Deferred by the owner:** 2026-08-10, AGY-TEST-AUDIT on `c17bcbe..06a39af`. Verified by reading the row.

---

## Accepted-boundary ledger - deliberately uncovered, do NOT re-raise

### A. The two walk-level guards (`2fa88e0`, `76e1ba8`)

- **Behaviour:** `Get-InjectedContextFiles` and `Get-UnexpectedBuildDirs` each seed their visited set with
  a guarded `Get-Item -ErrorAction SilentlyContinue`, falling back to the raw path. Without it, a domain
  root that disappears or locks between `Test-Path` and `Get-Item` throws through
  `$ErrorActionPreference = 'Stop'` and the gate exits by neither documented route.
- **Why uncovered:** no portable behavioural pin exists. Reproducing it needs either a `Get-Item` mock
  (fragile structural coupling) or a real delete-vs-walk race whose timing window is too narrow to be
  deterministic. Reached independently by capstone R20 and again by the AGY-TEST-AUDIT peer, which
  considered adapting the existing `Start-Job` junction-hang pattern and rejected it.
- **Compensation:** verified by direct manual control at fold time; the guard is a two-line fallback with
  no branching logic of its own.
- **Anchor:** the `$rootItem = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue` lines in both
  functions. **If either loses its `-ErrorAction SilentlyContinue`, this entry is void and the gap is live.**

### B. `payload-budget` measures the template, not the interpolated result

- **Behaviour:** the invariant parses the hook message TEMPLATE. At runtime an interpolated value (e.g. a
  `git log` result) can push the delivered message over the budget.
- **Guarantee as written:** "no over-budget TEMPLATE ships" - NOT "no over-budget message reaches an agent".
- **Why uncovered:** bounding the interpolated result requires executing the hooks, which the gate does not
  and should not do.
- **Compensation:** documented in-source as an intended limit, adjacent to the check itself.
- **Anchor:** the comment block above the `payload-budget` emission in `check-injected-context.ps1`.
  **If that comment goes, the limit is no longer documented and this entry is void.**

### C. The junction / symlink / reparse-point / cross-root-alias family

- **Why uncovered:** unreachable on real inputs. Measured 2026-08-10: this tree contains zero reparse
  points, `git checkout` creates none, and a file symlink cannot be created on Windows without elevation.
  The only junctions that have ever existed here were created by this suite's own fixtures.
- **Compensation:** the walk fails CLOSED - an aliased file is audited more than once, never zero times -
  so no content reaches an agent unaudited even if the topology did occur.
- **Note:** the per-route subtraction asymmetry was ruled out of scope and documented as intended in
  `06a39af`. Re-raising this family is a wrong answer unless the reachability facts above change.
