---
slug: agy-look-tail-truncation
variant: clavity-dotnet
observed: 2026-07-10
source-inbox-entry: "- [anti-pattern] When a synchronous review/consult payload is large enough to exceed the driver's idle-wait window,"
status: fixed
last-triaged: 2026-08-07   # FIXED by this epic. The 2026-08-06 oracle was SOUND (it named an externally-defined symbol, `newestFirst`, that the code really does use) and it correctly found the call site unwired at AgyView.cs:110.
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

## Fixed — 2026-08-07

Shipped in `141dcc4`. `AgyView.LookAsync` now calls
`BoundedView.Summarize(trajectory, budgetChars, newestFirst: true)` — a NAMED argument, because `newestFirst`
is the FOURTH parameter and a positional third would silently bind `maxStepChars`.

**Regression test:** `clavity-dotnet/tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs` ::
`Look_keeps_the_newest_steps_when_the_budget_is_tight`.

**The test was proven non-vacuous before the fix landed.** Verbatim red run against the unfixed call site:

```
Assert.Contains() Failure: Filter not matched in collection
Collection: [BoundedStep { Kind = 14, Text = OLDEST-STEP-MARKER... }, BoundedStep { Kind = 14, Text = FILLER-STEP-1... }]
```

— `agy_look` kept the two OLDEST steps and dropped `NEWEST-STEP-MARKER` entirely, which is exactly this
entry's complaint.

🔴 **The test drives `AgyView.LookAsync`, NOT `BoundedView.Summarize`, and that is deliberate.** `BoundedView`
already handled `newestFirst` correctly and its own tests already passed; a test calling `Summarize` directly
would have gone GREEN on its first run without ever touching the defect. The unwired call site was the bug.
**Do not "simplify" this test down to a `BoundedView` unit test — that would silently un-cover the defect.**

**Assertion shape:** it asserts WHICH step survived (marker identity), never HOW MANY. A cardinality assertion
is invariant under reversed ordering and would pass over the bug.

**The carried driving rule stays.** "Decompose the oversized ask into terse turns" remains a cheatsheet rule;
this fix bounds what `agy_look` drops, it does not remove the underlying budget.
