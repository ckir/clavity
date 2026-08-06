---
slug: working-vs-stuck-step-delta
variant: clavity-dotnet
observed: 2026-07-01
source-inbox-entry: "- [anti-pattern] A single HEAVY PURE-REASONING turn (e.g. a large multi-part code/design review,"
status: open
last-triaged: 2026-08-06   # oracle: no step-delta/StepDelta symbol in Clavity.Ls/*.cs. NB AgyView.cs:270-273 does track step PROGRESS for the stall window; this entry asks for the delta to be surfaced as a working-vs-stuck signal to the caller, which it is not.
---

# Heavy pure-reasoning turn exceeds idle-wait causing false modal

## Steps to Reproduce
fire a heavy pure-reasoning ask; the fixed idle-wait reports modal while the cascade step-count still climbs.

## Code-level Mitigation
(dotnet) distinguish working-vs-stuck by the cascade step-delta before reporting modal.

## Notes
classic = carried driver rule (F6b), lower retirement confidence.
