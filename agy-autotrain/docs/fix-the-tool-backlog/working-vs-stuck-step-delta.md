---
slug: working-vs-stuck-step-delta
variant: clavity-dotnet
observed: 2026-07-01
source-inbox-entry: "- [anti-pattern] A single HEAVY PURE-REASONING turn (e.g. a large multi-part code/design review,"
status: open
---

# Heavy pure-reasoning turn exceeds idle-wait causing false modal

## Steps to Reproduce
fire a heavy pure-reasoning ask; the fixed idle-wait reports modal while the cascade step-count still climbs.

## Code-level Mitigation
(dotnet) distinguish working-vs-stuck by the cascade step-delta before reporting modal.

## Notes
classic = carried driver rule (F6b), lower retirement confidence.
