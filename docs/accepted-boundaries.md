# Accepted boundaries

The do-not-re-raise ledger. One entry per line, section-partitioned by product. This file is COMMITTED,
because `agy-test-audit` re-validates every entry on a later run and a gitignored file cannot serve that.

Deferred debt does NOT live here - it rides `.clavity/local-anomalies.md` to a tracked `ROADMAP.md` item.
This file holds only boundaries that are deliberately, permanently not covered.

## Entry modes

**Compensated** - the normal case. Something else covers the behaviour, and a future audit re-validates
that the compensation still exists. An entry whose compensation has vanished is promoted back to a live
gap.

```
- [boundary] <behaviour not covered> * <source/path.ext:LINE> * compensation=<what covers it, with its code anchor> * <YYYY-MM-DD>
```

**Owner-accepted** - an `UNVERIFIED-ACCEPTED` finding: neither provable nor refutable, and the owner
accepted the risk. There is no compensating artifact by definition. A future audit re-validates such an
entry by confirming the cited source anchor still exists, not by hunting a compensation nobody claimed.

```
- [boundary] <finding> * <source/path.ext:LINE> * compensation=owner-accepted:<YYYY-MM-DD> <rationale> * <YYYY-MM-DD>
```

## Maintenance

Section-partitioned to keep merge conflicts survivable: a single flat file touched at every branch-finish
is a hotspot where a careless `--ours`/`--theirs` silently drops a teammate's entry. Sort by source path
within a section.

A periodic manual whole-tree garbage-collection pass reconciles this file against current code and drops
orphaned entries. A routine diff-scoped run cannot see deleted code, so it cannot prune stale entries.

## clavity-dotnet

- [boundary] The UNC volume-root short-circuit in `agy-anomaly-reminder.sh`'s repository-root walk is not covered by any test, and cannot be: it is a LATENCY optimisation with no behavioural difference. MEASURED 2026-09-04 against a real reachable UNC path (`//localhost/C$/...`): stdout is byte-identical with the guard present and with both copies removed, because the walk finds no `.git` either way and falls back to the same root. The only possible oracle is wall-clock time, and this repo's timing discipline bars that from a suite - a figure needs a tool-idle machine and two runs quoting a range, none of which Pester can guarantee, so such a test would be flaky in CI and would erode trust in the other 25 rows. Raised by the agy peer as AGY-CAPSTONE round 5, Coverage Adversary, severity 1; the finding is TRUE - removing both guards leaves the suite 25/25 GREEN. * clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh:109 * compensation=owner-accepted:2026-09-04 the guard's own inline comment carries the measurement that justifies it (20314ms walking an unreachable //server/share/a/b/c vs 9282ms gated), and its failure mode is latency on an unreachable share, never a wrong answer * 2026-09-04

## clavity-classic

_(none yet)_

## ghidrust

_(none yet)_

## agy-autotrain

_(none yet)_

## commonmemory

_(none yet)_

## shared

Root and cross-product code: `scripts/`, root `docs/`, CI workflows.

- **Symlinked paths are never fed to `check-capstone-new-code.ps1` by its suite.**
  Anchor: `scripts/tests/check-capstone-new-code.Tests.ps1` (`New-Repo`).
  COMPENSATION: creating a symlink on Windows needs elevation or Developer Mode, so such a row would
  pass or fail on the HOST'S PRIVILEGE LEVEL rather than on the code — an environment-dependent row is
  worse than an absent one. The behaviour itself is compensated structurally: a symlink's path is
  matched by the same string predicates every other path takes (`Test-IsTestPath` / `Test-IsCodeFile` in
  `scripts/check-capstone-new-code.ps1`), neither of which dereferences anything.
  Raised by AGY-TEST-AUDIT 2026-09-05, Boundary Smuggler.

- **Submodule entries (gitlinks) are never fed to it either.**
  Anchor: the absent-at-base guard in `scripts/check-capstone-new-code.ps1` (Rule B's
  `git show "${BaseRef}:$path"` followed by `if ($LASTEXITCODE -ne 0)`).
  COMPENSATION: a gitlink has no blob, so that `git show` exits non-zero and the file takes the SAME
  fail-safe branch a genuinely new file takes — verified by reading, and the peer independently traced
  the same path. A fixture would need a second repository stood up to exercise a branch already proven
  safe by two routes.
  Raised by AGY-TEST-AUDIT 2026-09-05, Boundary Smuggler / Cascade Analyst.

  ⚠ **RE-VALIDATE BOTH COMPENSATIONS BEFORE HONOURING THE DO-NOT-RE-RAISE.** They rest on two specific
  things staying true: that the path predicates never dereference, and that the absent-at-base guard
  still exists. The second one was EDITED on 2026-09-05 (it now retries against a rename origin before
  giving up), so it is exactly the kind of anchor that can move.
