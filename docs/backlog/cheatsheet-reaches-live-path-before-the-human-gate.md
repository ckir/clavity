# Backlog stub — the driver cheatsheet reaches a live path before the human review gate

**Status:** 🔴 **OPEN.** Pre-existing ordering defect. A doc note in `agy-curate/SKILL.md` now describes
it accurately; nothing yet changes the ordering.
**Raised:** 2026-08-12, AGY-CAPSTONE round 4. The peer challenged a safety claim the driver had written
into the skill; verifying the claim showed the claim was false and the underlying gap real.
**Scope:** `agy-autotrain/skills/agy-curate/SKILL.md` — the ordering of the cheatsheet write against the
human approval gate.

## The defect

Two artifacts are distilled from the same source — the `agy-observations.md` inbox, which the skill itself
describes as *"untrusted machine-local captures"* — and only one of them passes a human gate.

| artifact | path | human-gated? |
|---|---|---|
| `golden-header.growth.md` (GROWTH) | user profile | **yes** — `SKILL.md:224-228`, "Do not publish until the user approves" |
| `driver-cheatsheet.md` | user profile | **no** — written at `SKILL.md:110-111`, well before the gate |

The gate's own justification (`SKILL.md:226-228`) is:

> *"These are untrusted machine-local captures about to become a live injection into every ask; the human
> gate is the safeguard the model depends on, not a formality."*

That reasoning applies to the cheatsheet as much as to GROWTH — same source inbox, same distillation step
— but the cheatsheet is written unconditionally and earlier. The phrase *"entries that survived the gate"*
at `SKILL.md:79` refers to the **promotion rubric**, applied by the skill itself, not to human approval.

**It is live, not inert.** Both drivers read that filename: `clavity-classic/src/driver_cheatsheet.rs:7`
and `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs:10`.

**Reachable on the headless path in particular.** The no-interactive-approval branch writes the cheatsheet,
reaches the gate, and exits 2 without publishing GROWTH. The run therefore ends having put unreviewed
distilled content on a live path while correctly withholding the artifact it was told to withhold.

## What made this hard to see

A revision of that section (commit `cadfe25`) asserted the cheatsheet was
*"unreviewed-content-free by construction (it is distilled, not captured)"* and instructed readers not to
add a cleanup step. **Distilling untrusted input does not make it trusted**, and the sentence presented a
real gap as a settled design property — the kind of invented rationale that becomes load-bearing precisely
because it sounds like it was reasoned. The claim has been removed and replaced with an accurate
description; this stub records the gap it was covering.

## Candidate fixes — not chosen

1. **Move the cheatsheet write after the approval gate**, so both artifacts share one safeguard. Cleanest,
   but changes when a driver surface gets its cheatsheet, and the headless path would then produce neither.
2. **Gate the two separately** — a lighter confirmation for the cheatsheet, on the argument that it is
   driver guidance rather than peer-facing content. Preserves the headless path's usefulness.
3. **Accept and document** that the cheatsheet is agent-reviewed only, and say so where the gate is
   described, so the asymmetry is deliberate and visible rather than implicit.

Option 3 is the smallest and is partly done already; options 1 and 2 are real design changes and belong
to the owner.
