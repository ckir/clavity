# Backlog stub - GoldenHeader.Commit threw access-denied on a .bak delete under concurrent writers (Windows CI)

**Status:** OPEN 2026-11-03 - observed once on windows-latest, cause not reproduced; unscheduled. Promoted from `.clavity/local-anomalies.md`.

**Raised:** 2026-11-03, while merging PR #94 (an unrelated `--help` change that does not touch this code).

## The observation

`Clavity.Ls.Tests.GoldenHeaderTests.Commit_leaves_no_stray_tmp_under_concurrent_writes` failed once on the
`test` job of `windows-latest` (run 41701964931): `Parallel.For(0, 8, ...)` over `GoldenHeader.Commit` threw
`UnauthorizedAccessException: Access to the path '...golden-header.seed.md.20261103-191931-0001.bak' is denied`
from `File.Delete(stale)` at `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:338` (the ring-eviction loop).
The same suite passed on `main` and on `feat/start-profile` earlier the same day, and the failing PR's diff
does not touch `GoldenHeader.cs`.

## What is NOT known

- The cause. The guess is that one writer evicts a `.bak` slot that another concurrent writer has just written
  or is copying, and Windows refuses the delete while the file is open. Nothing here reproduced it.
- Whether it is reachable outside the test: concurrent `curate-commit` calls on the same header directory would
  take the same path.
- How often it happens. One observation.

## Owner and slot

Owner: the `clavity-dotnet` maintainer. Slot: unscheduled (`OPEN`). First step when scheduled: loop the test on
a Windows runner to measure the failure rate before changing `GoldenHeader.Commit` or the test.
