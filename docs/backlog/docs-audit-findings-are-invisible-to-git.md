# Backlog stub - a generated findings view is gitignored, so its findings reach nobody

**Status:** OPEN. Promoted 2026-08-27 from `.clavity/local-anomalies.md`.
**Raised:** 2026-08-27.

## The observation

`docs/docs-audit-findings.md` is a GENERATED findings view that is gitignored (`.gitignore:50`, by owner
ruling, regenerated per run). VERIFIED: the file exists on disk with 152 lines and `git check-ignore -v`
confirms the rule.

## The consequence

Docs-audit findings **never appear in `git status`, are not carried between sessions, and nothing
surfaces them.** A reviewer cross-checking whether a finding was already known cannot see them at all.

The gitignore itself is a deliberate ruling and is not in question - regenerating a view per run is
correct. What is missing is any channel by which the findings reach a human or a later session. Compare
`.clavity/local-anomalies.md`, which is also gitignored but has a SessionStart hook that nags until it is
empty; this file has no equivalent.
