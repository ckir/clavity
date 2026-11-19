# Backlog stub - `just lint` prints build warning xUnit1031 for a blocking Wait() in a test

**Status:** OPEN 2026-11-19 - promoted from `.clavity/local-anomalies.md`; not yet scheduled

**Raised:** 2026-11-19, reported by an implementer running `just lint` during the three-licences header rewrite.
**Scope:** `clavity-dotnet/tests/Clavity.Ls.Tests/ReviewFindingsTests.cs`. The branch that found it did not touch this
test (it only shortened the licence header at the top of the file).

## The defect

The test that exercises `TakeProfileLock` starts a background release with `Task.Run(...)` and then calls
`release.Wait()` on the test thread. xUnit's analyzer rule xUnit1031 ("do not use blocking task operations in test
methods") flags that call, so `just lint` prints a build warning. The code read at that line confirms a blocking
`Wait()`; the warning text itself was reported by the implementer and not re-run when this stub was written.

## What a fix has to establish

Make the test `async` and `await` the release task (or use the analyzer's recommended pattern), keep the 400 ms
holder and the 10 s wait so the test still proves that the lock loop keeps polling, and re-run `just lint` to see the
warning gone.
