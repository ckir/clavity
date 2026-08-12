# Backlog stub — the agy-curate abort path protects the working tree with an unenforced warning

**Status:** 🔴 **OPEN — direction DECIDED (A2), implementation not started.**
**Raised:** 2026-08-12, AGY-CAPSTONE round 7 (F4).
**Decided:** 2026-08-12, after a two-turn negotiation with the agy peer. The owner delegated the call.
**Scope:** `agy-autotrain/skills/agy-curate/SKILL.md` (the terminal-exit block) plus `lefthook.yml`.

## The defect

When `agy-curate` aborts at the human approval gate — no interactive channel, or the human does not
approve — it leaves `knowledge/driver-cheatsheet.core.md` and its two compiled-in pins
(`driver_cheatsheet.rs` `BASELINE_FLOOR`, `DriverCheatsheet.cs` `BaselineFloor`) modified in the working
tree. Those edits carry content distilled from what the skill itself calls untrusted machine-local
captures.

The only protection is a STDERR message instructing that the files must neither be committed nor built.
**Nothing enforces it.** An agent can satisfy the instruction exactly; a human running through a wrapper,
in a noisy terminal, or who simply misses the last lines of output then runs `git commit -a` and ships
unreviewed content. `commit -a` invokes no `just` recipe, so no test-side check can intervene.

## Why A2 (a mechanical guard) rather than A1 (warning only)

Both parties initially argued A1 and both abandoned it once the load-bearing claim was measured.

**The claim that supported A1 was false.** The argument was that mechanically reverting the dirty repo
files would break a byte-identity invariant with the live
`<CLAVITY_GOLDEN_HEADER or %USERPROFILE%\.clavity>\driver-cheatsheet.md`. It does not. `SKILL.md:91-95`
pins byte-identity among **three repository files only** — `driver-cheatsheet.core.md` and the two
compiled-in baselines — asserted by `driver_cheatsheet::tests::baseline_floor_matches_canonical_core_source`
and `DriverCheatsheetTests.BaselineFloor_matches_the_canonical_core_source`. The runtime profile file
(`:110-115`) is compiled OUTPUT, not a pinned artifact. **Reverting all three repository files together
leaves those pinning tests green.**

**And the revert is recoverable.** The abort leaves the inbox `## Pending` section intact by design, so
the same entries are re-distilled on the next run. A reverted repo edit is re-derived, not lost.

**A hook is not new infrastructure here.** `lefthook.yml` already runs a pre-commit manager on every
commit in this repository, so a mechanical guard costs no new conceptual machinery.

## Rejected alternatives, and why

- **A1, warning only** — rests on the false invariant above; leaves the exposure entirely on human
  attention.
- **A3, defer the repository writes until after approval** — the writes land at `:110-115`, far ahead of
  the gate at `:221`, and flushing them to the tree BEFORE the gate is what lets a human inspect the
  proposed edits with `git diff` while deciding. Deferring destroys that observability.
- **A blockfile in `.clavity/` asserted by `just` recipes** — does not address the stated threat at all:
  `git commit -a` runs no `just` recipe. `.clavity/` is also gitignored, so a fresh clone or CI checkout
  never sees it.

## What to build

A `lefthook.yml` pre-commit check that fails the commit when an abort marker is present AND any of the
three pinned files is staged. The marker is written by the abort path and cleared by an explicit act.
`.clavity/` is the right home for the marker: the threat is the same developer on the same box committing
after their own aborted run, and CI never runs `agy-curate`.

**Deliberately NOT implemented inside a capstone fold.** This branch is mid-AGY-CAPSTONE and is being
driven to GREEN; adding new executable machinery to the range under review injects unreviewed code into
the very thing being reviewed. It must be built as its own unit and reviewed on its own.

## Known limit

A pre-commit hook is bypassable with `--no-verify`. That is accepted: the goal is to stop an inattentive
commit, not an adversarial one.
