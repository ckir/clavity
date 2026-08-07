---
slug: conversation-scoped-tools-vs-no-open-conversation
variant: clavity-dotnet
observed: 2026-08-03
source-inbox-entry: "Endpoint-reachable is not conversation-open: when every peer tool is scoped"
status: fixed
last-triaged: 2026-08-07   # CORRECTED. The 2026-08-06 stamp read "no NoConversation/conversation-existence split in Clavity.Ls/*.cs -> confirmed still open". That was a FALSE NEGATIVE on invented vocabulary (see docs/backlog-triage-runbook.md §2): the shipped path is AgyConversationPendingException, and it is partly in Clavity.Mcp, outside the grep's scope.
---

# A live endpoint with NO open conversation fails every tool identically to a dead endpoint

## Steps to Reproduce
1. Have the agy host process running and the LS transport freshly connected.
2. Ensure NO agy conversation is open (close them, or start the host with none active).
3. Call the read-only `agy_status`.

Observed: it errors. Critically it errors in the SAME shape as a write would, which no
transport fault would produce -- a read-only status call and a mutating call failing
identically is the tell that the fault is conversation scope, not reachability. The
condition survives both an agy restart and a full machine restart, so "restart it" -- the
natural response to a perceived transport fault -- never clears it.

## Code-level Mitigation
In the LS client, separate CONVERSATION-EXISTENCE from ENDPOINT-REACHABILITY before mapping
an error:
- On the failure path, query the active-conversation lookup (the same id resolution the
  tools already perform) as a distinct step from the channel health check.
- When the channel connects but no conversation resolves, return a distinct typed error with
  a Hint naming the real cause and the real remedy -- "no agy conversation is open; open one
  in agy, then retry" -- instead of the current generic hint that blames a shutdown.
- Keep the existing unreachable-endpoint hint for the case where the channel itself fails.

This is the same DEFECT CLASS as `grpc-default-max-message-size.md` -- an opaque error whose
Hint misattributes the cause to "the peer is down" -- but a different root cause. Fixing the
message size does not fix this one.

## Notes
Deterministic on the clavity-dotnet bridge, where every exposed tool (`agy_ask`, `agy_status`,
`agy_look`) is conversation-scoped, so the whole surface fails at once. Classic's transport is
the signal bus plus psmux and is not scoped this way, so this is NOT carried as a classic item.
Retirement gated on a permanent regression test asserting the two failure modes map to distinct
errors.

## Disposition — open-work sweep, 2026-08-06

**KEPT — all three clauses met, and clause 1 is the textbook case.**

1. **Lie, with the wrong action named in the entry itself.** A live endpoint with no open conversation
   fails identically to a dead one, so the operator reads "transport fault" and restarts — and the entry
   records that the condition *"survives both an agy restart and a full machine restart, so 'restart it' …
   never clears it."* A diagnostic that reliably induces a useless recovery action is exactly what clause 1
   is for.
2. **Unavoidable.** No invariant or driving convention distinguishes the two states today; the tell (a
   read-only call failing in the same shape as a mutating one) requires already knowing the answer.
3. **Mechanism.** Separate conversation-existence from endpoint-reachability in the LS client before
   mapping the error. Bounded and specified.

## Already fixed — closed 2026-08-07, no code written

**The remedy this entry specifies was already implemented, and this entry never should have been KEPT.**

**Evidence.** `clavity-dotnet/src/Clavity.Ls/AgyView.cs:381` throws `AgyConversationPendingException`
— *"agy is running but has no conversation yet. WAIT for the human to start or continue the agy session,
then try again — do NOT auto-retry in a loop."* — under `if (reachedLsButEmpty && !sawChannelDeath)`, which
is exactly the conversation-existence / endpoint-reachability split this entry asks for. It surfaces as a
distinct status via `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:52-55`
(`status = "waiting_for_human"`), not as the generic shutdown hint.

**Retirement gate — MET.** This entry's own Notes require *"a permanent regression test asserting the two
failure modes map to distinct errors."* Two exist, asserting both directions:
- `clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs:284`
  `Boot_race_reached_empty_then_dead_reports_channel_down_not_waiting_for_human`
- `…:358` `Boot_race_transient_death_then_reached_empty_reports_waiting_for_human_not_channel_down`

🔴 **Why it was recorded open.** The 2026-08-06 triage probe searched for `NoConversation` /
`"no open conversation"` / `"conversation-existence split"` — **names the implementation never uses** — and
scoped itself to `Clavity.Ls/*.cs`, while half the shipped path lives in `Clavity.Mcp`. A probe keyed on
invented vocabulary reports ABSENT for something present and cannot return its failing answer. That
probe was following `docs/backlog-triage-runbook.md` §2, whose rule (*"a negative result is decisive"*) was
itself inverted; the rule was corrected on 2026-08-07 and this entry is the worked example in it.

**No commit from the open-work epic fixed this** — the fix predates the epic. Do not attribute it to one.
