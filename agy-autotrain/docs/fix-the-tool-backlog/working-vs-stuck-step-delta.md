---
slug: working-vs-stuck-step-delta
variant: clavity-dotnet
observed: 2026-07-01
source-inbox-entry: "- [anti-pattern] A single HEAVY PURE-REASONING turn (e.g. a large multi-part code/design review,"
status: wont-fix
last-triaged: 2026-08-06   # oracle: no step-delta/StepDelta symbol in Clavity.Ls/*.cs. NB AgyView.cs:270-273 does track step PROGRESS for the stall window; this entry asks for the delta to be surfaced as a working-vs-stuck signal to the caller, which it is not.
---

# Heavy pure-reasoning turn exceeds idle-wait causing false modal

## Steps to Reproduce
fire a heavy pure-reasoning ask; the fixed idle-wait reports modal while the cascade step-count still climbs.

## Code-level Mitigation
(dotnet) distinguish working-vs-stuck by the cascade step-delta before reporting modal.

## Notes
classic = carried driver rule (F6b), lower retirement confidence.

## Disposition — open-work sweep, 2026-08-06

🚫 **KILLED — subsumed by `stalled-reply-recoverable-not-lost.md`.**

**Verified by reading both entries, not assumed.** This entry asks to *"distinguish working-vs-stuck by the
cascade step-delta before reporting modal."* The mitigation in `stalled-reply-recoverable-not-lost` ends:
*"Only if the step counter is genuinely NOT advancing should the call be reported as [stalled]."*
**That final clause IS this discriminator** — implementing that entry necessarily implements this one.
Both carry `variant: clavity-dotnet`, so the overlap is total rather than per-driver.

⚠️ **Killed as a duplicate, not as a non-problem.** The false modal it describes is real; it is simply the
same defect seen from the caller's side, and tracking one defect twice is how a backlog inflates. If the
surviving entry is ever narrowed to exclude the step-delta check, this must come back.
