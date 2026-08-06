---
slug: agy-look-tail-truncation
variant: clavity-dotnet
observed: 2026-07-10
source-inbox-entry: "- [anti-pattern] When a synchronous review/consult payload is large enough to exceed the driver's idle-wait window,"
status: open
last-triaged: 2026-08-06   # oracle: agy_look (AgyView.cs:110) calls BoundedView.Summarize(trajectory, budgetChars) with newestFirst defaulting to false, and the McpTools.cs:14 description documents neither arm -> confirmed still open. NB the tail-anchored view DOES exist (BoundedView.cs:38-41 `newestFirst`), used only by agy_ask and tests; grep AgyView.cs alone and you will wrongly conclude no such view exists at all.
---

# Oversized reply's trajectory read-back truncates to the head

## Steps to Reproduce
after a large reply, read the trajectory via `agy_look`; it returns the HEAD/older turns and truncates before the just-completed reply's tail.

## Code-level Mitigation
(dotnet) expose a tail-anchored view (return the most-recent N steps) or document `agy_ask` as the retrieval path and `agy_look` as trajectory-inspection only.

## Notes
classic has no trajectory-look analogue → does not reproduce; the "decompose the oversized ask into terse turns" driving move is carried as a cheatsheet rule.

## Disposition — open-work sweep, 2026-08-06

**KEPT — all three clauses met.**

1. **Lie.** `agy_look` returns the HEAD of the trajectory and truncates before the just-produced reply, so a
   caller reading it to see "the latest state" is shown older turns with nothing marking them stale. **The
   wrong action it induces is concrete:** the driver concludes the peer never answered and re-asks, paying
   for the same turn twice.
2. **Unavoidable.** Nothing in the current flow neutralises it; reading a trajectory after a large reply is
   ordinary use, not an edge case.
3. **Mechanism — already built, just not wired.** `BoundedView.cs:38` exposes `newestFirst`, used by
   `agy_ask` and its tests; `AgyView.cs:110` simply does not pass it. No design fork remains.
