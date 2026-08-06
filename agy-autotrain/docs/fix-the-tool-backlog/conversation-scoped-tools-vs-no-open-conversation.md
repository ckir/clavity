---
slug: conversation-scoped-tools-vs-no-open-conversation
variant: clavity-dotnet
observed: 2026-08-03
source-inbox-entry: "Endpoint-reachable is not conversation-open: when every peer tool is scoped"
status: open
last-triaged: 2026-08-06   # oracle: no "no open conversation"/NoConversation/conversation-existence split anywhere in Clavity.Ls/*.cs -> confirmed still open
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
