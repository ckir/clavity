# Backlog stub - a whole-tree sandbox copy takes ~40 minutes and caused a real incident

**Status:** OPEN. Promoted 2026-08-27 from `.clavity/local-anomalies.md`.
**Raised:** 2026-08-26.

## The measurement

A full-tree sandbox copy of this repository copies **46,991 files when only 620 are tracked** - 36,205 of
them sit in `clavity-classic/target` and `ghidrust/target`.

MEASURED: `robocopy /E` took ~40 minutes and had not reached `scripts/` yet. **That window is what let a
coordinator edit land inside a running arm's sandbox** - a real incident, not a hypothetical.

## The fix when it is scheduled

Any dispatch that asks for a whole-subtree copy must exclude `target/ bin/ obj/ node_modules`, or copy
from `git ls-files` rather than walking the tree. The 620-vs-46,991 ratio makes the tracked-file route
roughly two orders of magnitude cheaper.
