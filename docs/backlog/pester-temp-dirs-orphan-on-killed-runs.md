# Backlog stub — Pester temp directories orphan permanently when a run is killed

**Status:** 🔴 **OPEN.** Verified by measurement, repo-wide, pre-existing.
**Raised:** 2026-08-12, AGY-CAPSTONE round 3. The peer raised it against one suite; measuring it properly
found the leak is real but in *other* suites.
**Scope:** `scripts/tests/` — **29 suites** use the `BeforeEach`-mktemp / `AfterEach`-remove pattern.

## The defect

Suites create a per-test temp directory in `BeforeEach` and remove it in `AfterEach`:

```powershell
BeforeEach { $script:Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("<prefix>-" + [Guid]::NewGuid()) ... }
AfterEach  { Remove-Item -Recurse -Force $script:Tmp -ErrorAction SilentlyContinue }
```

`AfterEach` does not run if the process is hard-terminated. The `test-scripts-fast` half is documented in
`scripts/tests/_partition.md` as running close to a 600 s wall-clock cap and is routinely BACKGROUNDED and
occasionally killed — `_partition.md` itself records a backgrounded run stopped at 9 of 13 suites. **Every
such kill orphans one directory per test that had started.**

## Measured 2026-08-12, in `C:\Users\user\AppData\Local\Temp\`

| prefix | orphaned directories |
|---|---|
| `clavity-*` | **321** |
| `drain-*` | 1 |
| `cheatbudget-*` | 0 |
| total directories in `%TEMP%` | 39,593 |

**The 0 is the interesting one.** The peer raised this against `cheatbudget-*` specifically, where nothing
has leaked. The mechanism it described is correct; the instance it chose was not. Checking the pattern
rather than the named suite is what surfaced the 321.

## Why it matters

Slow-burning rather than acute, but real: it accumulates unbounded across every killed run, on a suite
half that is *expected* to be killed. It also degrades the diagnostic value of `%TEMP%` — at ~40k
directories, looking for anything by hand there is impractical, and a future test that needs to assert
"no leftover state" has 321 pre-existing counter-examples to work around.

## Candidate fixes — not yet chosen

1. **Sweep on entry, not only on exit.** In `BeforeAll`, delete `<prefix>-*` directories older than N hours.
   Self-healing, needs no run to complete, and fixes the existing 321 on the next run. Cheapest.
2. **One parent per run.** Create a single `<prefix>-run-<guid>` directory and put per-test dirs inside it,
   so a kill orphans exactly one directory instead of one per test.
3. **Accept and document it** as a boundary in `docs/coverage-debt.md`, with a periodic manual sweep. Weakest
   — it is the option that leaves 39k directories growing.

Option 1 composes with the others and is a few lines in a shared helper; it does not need every suite edited
at once.

## Why this is filed rather than dismissed

It is PRE-EXISTING and was not introduced by the change under review, which is exactly the reasoning that
almost buried it. **"The old code did it too" is not a disposition** — a pre-existing defect earns a tracked
item, not a mention. Recording the measurement here is what makes it actionable later.
