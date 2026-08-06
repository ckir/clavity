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
