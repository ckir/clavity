# Backlog stub - the agy consult guard keeps its "unfinished" marker after a backgrounded consult completes

**Status:** OPEN 2026-11-19 - promoted from `.clavity/local-anomalies.md`; not yet scheduled

**Raised:** 2026-11-18, AGY-CAPSTONE and test-audit consults for ROADMAP section 106; re-observed on every
consult of the three-licences work on 2026-11-19 (about a dozen more).
**Scope:** the agy consult guard under `/tmp/claude-agy-consult-guard/<session>.unfinished`.

## The defect

When the harness moves an `agy_ask` call to the background (the call outlives the foreground wait), the
guard's `<session>.unfinished` file stays in place even after the consult has completed and delivered its
result. Every later consult start then repeats the "previous consult ended unfinished" notice until the file
is removed by hand.

## Workaround in force

Remove `/tmp/claude-agy-consult-guard/<session>.unfinished` by hand before the next consult.

## What a fix has to establish

Where the guard clears the marker (on the foreground return path only, as observed) and whether the
background completion notification can clear it as well. Reproduce first: start a consult, let it background,
let it complete, then list the guard directory.
