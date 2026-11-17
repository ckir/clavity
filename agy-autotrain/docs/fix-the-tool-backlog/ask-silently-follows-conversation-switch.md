---
slug: ask-silently-follows-conversation-switch
variant: clavity-dotnet
observed: 2026-11-16
source-inbox-entry: "An ask goes to whichever conversation is most recent at that moment, so"
status: SHIPPED
fixed-by: de7f0785, c081e394
fixed-on: 2026-11-18
---

# A series of asks can silently jump to a different agy conversation, and nothing in the result says so

## Steps to Reproduce
1. In agy, open conversation A and send `agy_ask` a first brief; note `CascadeId` in the result.
2. Without telling the driver, open conversation B in agy (a new chat, or re-select an older one) and send it any message so it is the most recently active one. The server follows the most recently active conversation.
3. Send `agy_ask` again from the same driver session.

Observed: the second result simply carries B's `CascadeId` (`clavity-dotnet/src/Clavity.Ls/AskReply.cs:167`, filled from the trajectory read at `clavity-dotnet/src/Clavity.Ls/AgyView.cs:429`). No notice says the conversation changed. The peer, now in a conversation with none of the earlier rounds, spends several times the steps of the previous round and answers without its context. A driver only notices if it compares ids by hand.

## Code-level Mitigation
In `AgyView`, remember the `CascadeId` of the previous ask for the same MCP session. When an ask's result `CascadeId` differs from it, add a notice to the result in the same channel the `[13b]` completeness notices use, for example `[conv] CONVERSATION CHANGED: <previous> -> <current>; this ask ran with no earlier context, treat it as a first brief`. The first ask of a session, and an unchanged id, add nothing. No change to what is sent to the peer.

## Notes
- Variant: reproduced on clavity-dotnet. clavity-classic (`clavity ask`) not checked; verify before marking `both`.
- Until fixed, the driving move is the carried rule: compare the id in every result with the one before, and treat a change as a first brief (self-contained, counted against the allowance as such). It is not in the driver cheatsheet yet (cap reached; see the agy-curate run of 2026-11-17).
- A step-2 measurement script (compaction study) already pins the chat before every ask by `TotalSteps`/trajectory id; that is the client-side form of the same check.
