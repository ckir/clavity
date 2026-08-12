# Backlog stub — LS discovery misreports a BUSY peer as "starting or exited"

**Status:** 🔴 **OPEN.** Reporting defect, not a logic defect — the loop already computes everything the
fix needs.
**Raised:** 2026-08-12, during an AGY-CAPSTONE round. A consult failed `channel_down` mid-review; the
operator ran `/mcp` reconnect on the strength of the message and the channel came back.
**Scope:** `clavity-dotnet` — `src/Clavity.Ls/AgyView.cs`, `ChannelDown.Hint`.

## The defect

`ConnectAndResolveAsync` (`AgyView.cs:320-393`) polls every 500 ms against a **10-second
`BootRaceTimeout`** (`AgyView.cs:13`). Inside the loop it carefully separates the failure states —
`reachedLsButEmpty`, `sawChannelDeath`, and "DeadlineExceeded is the clamped budget expiring, NOT a
death" (`AgyView.cs:365-371`, each with a comment explaining why the distinction is load-bearing).

At the deadline (`AgyView.cs:387-389`) **all of that is discarded** and one string is emitted regardless
of which path arrived there:

> `agy Language Server not reachable within {BootRaceTimeout} via {CliLogPath}; the agy session is still
> starting or has exited.`

At least three materially different situations reach that line, and the message is only true for two:

| observed state | message accurate? | what the operator should do |
|---|---|---|
| no address resolved (log absent, or no listening line) | yes | check agy is running |
| **address resolved, every poll hit `DeadlineExceeded`** | **NO — the peer is alive and busy** | **retry the call** |
| `Unavailable` / `Internal` — a genuine death | yes | restart agy |

## Measured, 2026-08-12

The failing call named `logs/clavity-60e95692-89d6-4726-ba31-01befd60f55d.log`. Traced:

- that log announces ports **58520 / 58521**;
- `agy` PID 3896 was **LISTENING on 58520 / 58521** at the time of the failure;
- `agentapi get-conversation-metadata` against **58521** returned **3439 bytes of real metadata**
  (`"branchName": "main"`), i.e. the endpoint was serving;
- `agy_status` had been reporting `State: working` throughout.

So the session had **not** exited and was **not** still starting. It was mid-turn and did not answer
inside a 10-second budget.

## Why it reads to users as a broken product

`LsDiscovery.ReadCliLogText` is called **inside** the poll loop (`AgyView.cs:337`), so the address is
re-read every 500 ms and re-resolved on every subsequent call. **There is no cached binding to clear.**
A `/mcp` reconnect therefore fixes nothing that the next call would not have fixed by itself — but the
hint recommends restarting the MCP server or the whole Claude Code session. The operator performs a
heavyweight recovery action, it appears to work, and the reasonable conclusion is that the channel is
unreliable. The component already self-heals; the message conceals that and points at the most drastic
remedy first.

## Recommended fix — cheapest first

1. **Carry the observed state into the exception** (`AgyView.cs:387`). Three messages, three actions, per
   the table above. The loop already tracks the discriminators; nothing new needs measuring.
2. **Stop applying a BOOT budget to a LIVENESS question.** 10 s is the right budget for *"has it
   started?"*. Once an address resolves, that question is answered and the remaining question is *"will a
   busy LS answer?"* — which deserves its own, longer budget. This is the root cause of the false
   negative.
3. **Demote the restart advice in `ChannelDown.Hint`.** Lead with "retry the call"; mention reconnecting
   only after repeated failures.
4. **Pin it.** `tests/Clavity.Ls.Tests/ChannelDownTests.cs` already asserts which hints contain
   `"shut down or restarted"` (`:54`, `:66`, `:96`). Add the resolved-but-unanswered case, asserting the
   hint does NOT say that and DOES say retry — otherwise the honest message is one refactor from
   regressing.

## Honest caveat

**It was not proven that a bare retry would have succeeded**, because the operator reconnected instead of
retrying, which destroyed the evidence. The code makes it very likely (the address is re-resolved per
poll, and the endpoint demonstrably served an unrelated client during the outage), but a clean repro —
fire a consult while `agy_status` reports `working`, let discovery fail, then retry WITHOUT reconnecting —
would settle it and should precede the fix.

## Relation to the assertions harness

`agy-autotrain/verify/assertions.md` row **A6** records *"process-alive is not endpoint-reachable"* — a
live process being no proof the endpoint connects. This defect is the **mirror image**: the endpoint WAS
reachable and the discovery probe reported that it was not. A6 covers the false positive; the false
negative has no row. Worth adding one when this is fixed.
