# Backlog stub — the agy-curate abort path protects the working tree with an unenforced warning

**Status:** ✅ **BUILT — 2026-08-12.** `scripts/check-curate-in-progress.ps1` +
`scripts/tests/check-curate-in-progress.Tests.ps1`, wired at `lefthook.yml` `pre-commit`, armed by
`agy-autotrain/skills/agy-curate/SKILL.md` "STEP ZERO" and cleared by its "Finish" step.
**Raised:** 2026-08-12, AGY-CAPSTONE round 7 (F4).
**Decided:** 2026-08-12, after a two-turn negotiation with the agy peer. The owner delegated the call.
**Built:** 2026-08-12, owner-approved after a design consult that **changed the mechanism** — see
"What was actually built" below, which supersedes the original "What to build".
**Scope:** `agy-autotrain/skills/agy-curate/SKILL.md` (Step Zero + Finish) plus `lefthook.yml`,
`scripts/check-curate-in-progress.ps1` and its suite.

## The defect

When `agy-curate` **ends in any way other than completing normally** it can leave
`knowledge/driver-cheatsheet.core.md` and its two compiled-in pins (`driver_cheatsheet.rs`
`BASELINE_FLOOR`, `DriverCheatsheet.cs` `BaselineFloor`) modified in the working tree. Those edits carry
content distilled from what the skill itself calls untrusted machine-local captures.

⚠ **SCOPE — corrected 2026-08-12, and it changes what must be built.** This stub originally said "aborts
at the human approval gate". That is narrower than the rule the skill now states. Across capstone rounds
8-13 that rule was reformulated six times and settled on **any ending that is not a normal completion**,
which covers the two gate aborts (exits 2 and 3) *and* an error exit (1) at any point — including one
struck **inside** the Finish step, after some work has already landed. **A guard built only for gate
aborts would miss the error paths**, so the marker below must be written on every abnormal ending, not
just when the gate is refused.

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

## What was actually built — and the one way it departs from the original plan

A `lefthook.yml` pre-commit check that fails the commit when the marker is present AND any of the three
pinned files is staged. `.clavity/` is the right home for the marker: the threat is the same developer
on the same box committing after their own failed run, and CI never runs `agy-curate`.

🔴 **THE MARKER IS INVERTED RELATIVE TO WHAT THIS STUB ORIGINALLY SPECIFIED.** The original text read
*"the marker is written on every ending that is not a normal completion"*. It is instead **written at
STARTUP, as the skill's first act, and deleted ONLY on a normal completion** — so its presence *is* the
predicate "a run started and did not finish normally", with nothing to evaluate.

The design consult raised this and it holds on two independent grounds:

1. **Write-on-abort needs the dying run to still be able to write.** A `kill -9`, an OOM, or a power cut
   writes no marker at all, so the guard would pass silently on exactly the endings that most deserve
   blocking — a guard that fails open, certifying what it stopped checking.
2. **Write-on-abort makes the agent evaluate a predicate at exit time.** That predicate is the one this
   skill records getting wrong in five distinct formulations, two of which mutually reverted. Creating a
   file unconditionally as the first act cannot be got wrong. **The inversion removes the class rather
   than restating the rule correctly a sixth time.**

The original instruction — *"do not re-derive the trigger condition from the exit codes"* — survives
intact and is in fact strengthened: there is now no code, and no condition, on either half.

**Deliberately NOT implemented inside a capstone fold.** The branch was mid-AGY-CAPSTONE when this was
raised; adding new executable machinery to the range under review injects unreviewed code into the very
thing being reviewed. Built as its own unit after that capstone went GREEN and its test audit closed.

## Known limit

A pre-commit hook is bypassable with `--no-verify`. That is accepted: the goal is to stop an inattentive
commit, not an adversarial one.
