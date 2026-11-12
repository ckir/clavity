# Design doc outline

Write the design doc so a talented builder could plan from it without going back to the owner, and
so a reader a year later can see what was decided, by whom, and on what evidence. By default save it as
`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` (the project's own convention overrides the path)
on a design branch, and commit it at each reviewed state.

## Header

Title, date, status line that changes over time (DRAFT for owner approval; APPROVED on date;
REVISED on date after ruling X, with the sections touched), and a pointer to where the review trail
lives (the seams and scratch files under `.clavity/`).

## Sections

1. **Intent.** What this is and the thesis in one paragraph. The product shape in one name the team
   will use ("a staleness compiler", "a workflow bridge").
2. **Who it is for.** The first adopter as a person with a role, a company size, a trigger and a
   ten-minute path; why this adopter, with the verified facts that justify it; a success criterion
   the owner can check later.
3. **Goals, non-goals, anti-goals.** Non-goals are deliberately later; anti-goals would make the
   product a failure even if it worked.
4. **Constraints.** Team size, runtime, required services, licence posture, invariants that bind
   every later section.
5. **Approaches considered.** One block per fork: the options, what the peer argued, what was
   measured, what was picked and why. Supersessions are recorded here as a later fork.
6. onwards. **The decided mechanism**, section per subsystem, with the contract-level rules stated as
   rules ("null means use the chain; empty means show nothing"), the measured results in their own
   subsection, and "deferred, not precluded" items with the migration that would add them.
- **Interfaces.** Packages, commands, SDK functions by name, the wire and file formats that are
  contracts.
- **Left to the builder, and to the owner.** Two lists. Owner items stay open with their names; a
  required spike before a later plan is written goes here.
- **What done looks like.** One paragraph walking the first adopter through the product; the
  procedure-walker seat will trace it, so every step must rest on a rule stated earlier.
- **Appendix A. Review ledger.** Every folded, rejected and discarded finding by round, with the
  measurement or quote that settled it, and every owner ruling with its date and wording.
- **Stand-downs.** The discarded-below-floor and unverified-accepted items, one line each with the
  guard or the owner's acceptance.

## Conventions

- Rules are sentences with a verb, in the section that owns them, stated once and referenced by
  section number elsewhere. Two sections that disagree are a defect a builder resolves by guessing.
- Numbers that were measured carry what was measured and under what conditions; numbers that were
  proposed carry `[PROPOSED, UNMEASURED]`; claims about the world carry `[CLAIM]`.
- The status line and the owner-decisions paragraph are the two places a later ruling must touch
  first; the sections that depended on the earlier decision are revised next; the review ledger
  records the supersession last.
- Never describe a product as "open source" unless its licence is; say "source-available" when that
  is what it is.
