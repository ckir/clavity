---
slug: agy-look-tail-truncation
variant: clavity-dotnet
observed: 2026-07-10
source-inbox-entry: "- [anti-pattern] When a synchronous review/consult payload is large enough to exceed the driver's idle-wait window,"
status: open
---

# Oversized reply's trajectory read-back truncates to the head

## Steps to Reproduce
after a large reply, read the trajectory via `agy_look`; it returns the HEAD/older turns and truncates before the just-completed reply's tail.

## Code-level Mitigation
(dotnet) expose a tail-anchored view (return the most-recent N steps) or document `agy_ask` as the retrieval path and `agy_look` as trajectory-inspection only.

## Notes
classic has no trajectory-look analogue → does not reproduce; the "decompose the oversized ask into terse turns" driving move is carried as a cheatsheet rule.
