# Backlog stub — the driver cheatsheet reaches a live path outside the human review gate's scope

**Status:** 🔴 **OPEN.** Pre-existing SCOPE defect. A doc note in `agy-curate/SKILL.md` now describes it
accurately; nothing yet changes what the gate covers.
**Raised:** 2026-08-12, AGY-CAPSTONE round 4. The peer challenged a safety claim the driver had written
into the skill; verifying the claim showed the claim was false and the underlying gap real.
**Scope:** `agy-autotrain/skills/agy-curate/SKILL.md` — what the human approval gate covers, and what it
does not.

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

## It is a SCOPE gap, not an ORDERING gap

🔴 **Corrected 2026-08-12.** An earlier revision of this stub described the defect as the cheatsheet being
written *before* the gate, and proposed moving the write below it. **That fix would not work.**

`SKILL.md:121` routes carried `driver` cheatsheet rules to the cheatsheet, **not to GROWTH**.
`SKILL.md:224` instructs the gate to show **the compiled GROWTH proposal**. The cheatsheet is therefore
outside the gate's scope **at any ordering** — moving the write below it changes when an ungated artifact
is produced, not whether it is gated.

## Candidate fixes — not chosen

1. **Extend the gate's scope** to show the compiled cheatsheet alongside the GROWTH proposal, and withhold
   both until approval. Closes the gap directly. Costs the headless path both artifacts rather than one.
2. **Gate the two separately** — a lighter confirmation for the cheatsheet, on the argument that it is
   driver guidance rather than peer-facing content. Preserves some headless usefulness.
3. **Accept and document** that the cheatsheet is rubric-reviewed only, and say so where the gate is
   described, so the asymmetry is deliberate and visible rather than implicit.

Option 3 is the smallest and is done: `SKILL.md` now states the scope limit at the exit-2 branch. Options
1 and 2 are design changes and belong to the owner. **Any fix must change the gate's SCOPE; none can work
by changing the write ORDER alone.**
