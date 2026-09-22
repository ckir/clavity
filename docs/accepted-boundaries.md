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

- [boundary] The `ls -t` sort-failure fallback in `agy-consult-recovery.sh` (the `_ordering_lost` degrade-to-unsorted path + the "could not be ordered by recency" honesty note) is not covered, and cannot be on this harness: its trigger is a seams dir that globs by name but cannot be stat-ed by `ls -t` (read-but-no-execute permission, or ARG_MAX), neither reproducible on the case-insensitive Windows dev FS. Raised as AGY-TEST-AUDIT 2026-09-14 accepted boundary (a) and honored by the peer. * clavity-dotnet/plugin/hooks/agy-consult-recovery.sh:124 * compensation=the reader is fail-open and the fallback is straight-line degrade-never-drop logic reviewed SOUND in the section-24 design consult during AGY-CAPSTONE (worst case is unsorted output prefixed with an explicit name-order note, never a crash or a dropped seam - `agy-consult-recovery.sh:116-125` and `:175`) * 2026-09-14
- [boundary] The Linux-only uppercase-extension reply case `<stem>-REPLY.MD` on a case-SENSITIVE FS (the case-class reply-probe glob) is not asserted, and is vacuous to assert on the case-INsensitive Windows dev FS. Raised as AGY-TEST-AUDIT 2026-09-14 accepted boundary (b) and honored by the peer. * clavity-dotnet/plugin/hooks/agy-consult-recovery.sh:152 * compensation=the test `a .MD-cased seam extension still flags an existing -REPLY` (`scripts/tests/agy-consult-recovery.Tests.ps1`) exercises the SAME case-class glob on Windows, and the glob was verified SOUND in the section-24 design consult; a case-sensitive FS is needed to show the Linux-only benefit, and this repo's suite runs only on Windows * 2026-09-14

## clavity-classic

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

- **The successful `-Resume` drop is never driven end-to-end through `release.ps1`.**
  Anchor: `scripts/tests/release.Tests.ps1` (`New-ReleaseScenario`); all six rows exit via `Die` or
  `-WhatIf` before the compute step.
  COMPENSATION: the drop ITSELF is covered at unit level by the four `Invoke-DropReleaseCandidate` rows
  in `scripts/tests/release-lib.Tests.ps1` (tip reset, non-conflicting replay, conflicting replay with a
  clean abort, and merge-topology survival), and everything downstream of the drop is the ordinary
  first-release path that predates `-Resume` and is gated by the existing release suites. An end-to-end
  happy-path row would need the whole `build/members.json` + per-member plugin structure stood up in a
  throwaway repo, against a suite whose rows already cost ~9,4s each because every one spawns a pwsh
  running a COPY of `release.ps1`. OWNER-RULED 2026-09-22 after the peer argued the opposite position
  ("proving the orchestrator can say no does not prove it can finish the job") — the argument is on the
  record in `docs/agy-test-audit-ledger.md`, and this boundary is the owner's answer to it.
  Raised by AGY-TEST-AUDIT 2026-09-22, frame-rejection question.

- **`Get-DanglingReleaseCommits`'s `.Trim()` is unobservable and no row can kill its mutant.**
  Anchor: `scripts/lib/release-lib.ps1`, the `ForEach-Object { $_.Trim() }` in
  `Get-DanglingReleaseCommits`.
  COMPENSATION: MEASURED 2026-09-22 — deleting the `.Trim()` leaves the suite fully GREEN, because
  `git log --format=%H` emits no surrounding whitespace, so no fixture can produce an input that
  distinguishes the two. Rather than write a row that pins nothing, the test that FALSELY CLAIMED to
  cover it was renamed (it had been `... newest-first, trimmed`) and now asserts the contract that is
  real and checkable: every returned element matches `^[0-9a-f]{40}$`, which would catch stray
  whitespace if git ever emitted any.
  Raised by AGY-TEST-AUDIT 2026-09-22, driver branch census.

- **`Get-DropConflictStatus`'s `-not $head -or -not $cand` guard is defence-in-depth, not a gap.**
  Anchor: `scripts/lib/release-lib.ps1`, `if (-not $head -or -not $cand) { return 'unknown' }`.
  COMPENSATION: MEASURED 2026-09-22 — disabling the guard leaves the suite GREEN because the
  fallthrough reaches `merge-tree`, which fails on the same bad ref and lands in the `default` switch
  arm returning the SAME `'unknown'`. Two independent paths produce one answer, so a single-point mutant
  cannot redden anything; that is multi-guard redundancy rather than a vacuous test, and the `default`
  arm IS pinned (changing it to `'clean'` reddens the fail-closed row).
  ⚠ RE-VALIDATE: this rests on the `default` arm continuing to return `'unknown'`. If that arm is ever
  narrowed, this guard becomes the only path and needs its own row.
  Raised by AGY-TEST-AUDIT 2026-09-22, driver branch census.

- **`Get-DanglingReleaseCommits`'s second throw (range resolved, git still failed) has no test.**
  Anchor: `scripts/lib/release-lib.ps1`, the `if ($LASTEXITCODE -ne 0)` that follows the
  `git log 'origin/main..HEAD'` call.
  COMPENSATION: its trigger is a repository whose `origin/main` RESOLVES and whose `git log` then still
  fails - corruption, an unreadable object, a hostile config - and no fixture in this suite can produce
  that without corrupting a real repo on disk, which would make the row environment-dependent. Two
  independent things make its absence safe rather than merely unmeasured. First, BOTH call sites now
  catch: `Test-ResumeState` turns any failure into a Problem with `Ok=$false`, and `release.ps1`'s gate
  turns it into a `Die` - so the path fails CLOSED whether git reports by exit code or by throwing.
  Second, that also disposes of the related observation that the throw is BYPASSED when
  `$PSNativeCommandUseErrorActionPreference` is `$true` (the native error throws before `$LASTEXITCODE`
  is read): the escaping `NativeCommandError` lands in the same two catches and produces the same clean
  refusal, so the bypass changes the message, never the safety.
  ⚠ RE-VALIDATE: this rests on both call sites keeping their catch. If either is removed, this branch
  becomes the only thing standing between a corrupt repository and a fail-open gate, and needs a row.
  Raised by AGY-TEST-AUDIT 2026-09-22 (driver prediction) and AGY-CAPSTONE round 6 (Mechanism Gamer +
  Protocol Pedant).
