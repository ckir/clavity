# Backlog stub - AgyView boot-race deadline uses the wall clock, so its tests must wait the full budget

**Status:** OPEN 2026-11-04 - decision from the review-decisions consult (owner kept the 10s timeout); unscheduled.

**Raised:** 2026-11-04, resuming the `review-decisions-first` seam (D3).

## The observation

`AgyView.ConnectAndResolveAsync` computes its deadline as `DateTime.UtcNow + _options.BootRaceTimeout`
(`clavity-dotnet/src/Clavity.Ls/AgyView.cs:602`) and issues the verdict only at that deadline (`:686`), so a
test of the boot-race path always takes the whole `BootRaceTimeout`.
`Boot_race_reached_empty_then_cli_log_unreadable_keeps_waiting_for_human` flaked 2 of 3 runs under heavy load at 2s,
so it now uses 10s (`clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs:504`). Eight sibling tests
in the same file still use 2s (`:306 :337 :401 :435 :460 :544 :585 :662`) and are exposed to the same load.

## Proposed direction (not decided)

Inject a `TimeProvider` into `AgyViewOptions` / `AgyView` so tests advance virtual time instead of waiting, then
drop the per-test timeouts back to small values. This is a production-code change and needs its own capstone and
test audit when scheduled.

## What is NOT known

- Whether 10s is enough under the worst CI runner starvation (not measured).
- Whether the verdict flips from `waiting_for_human` to `channel_down` when poll 1 is delayed past the timeout
  (claimed by the agy peer, not reproduced).

## Owner and slot

Owner: the `clavity-dotnet` maintainer. Slot: unscheduled (`OPEN`).
