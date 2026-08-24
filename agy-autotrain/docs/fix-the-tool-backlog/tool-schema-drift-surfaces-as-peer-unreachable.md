---
slug: tool-schema-drift-surfaces-as-peer-unreachable
variant: both
observed: 2026-08-21
source-inbox-entry: "A peer tool that errors on EVERY call while sibling tools on the same"
status: open
---

# An input-validation rejection is surfaced as a generic channel failure, so schema drift is diagnosed as an outage

## Steps to Reproduce

1. Call the ask tool with a parameter name the current schema does not declare (the natural case: the
   caller was written against an older or newer build than the one installed - see the sibling item
   `stale-client-binary-blamed-on-the-peer`).
2. Every call to that ONE tool fails. Sibling tools on the same server - the status probe in particular -
   answer normally throughout.
3. The failure text names no parameter and does not say the request was rejected before it left the
   client, so it reads as "the channel is down".

Measured 2026-08-21: four consecutive failures read as an outage, an operator was asked to restart the
peer for nothing, and the peer was healthy the whole time. The discriminator was available and unused -
**an outage takes the whole server down; schema drift takes exactly one tool down.**

Reproducible on this install today, which is what makes it worth fixing rather than only documenting:
the installed `clavity-ls.exe` is dated 2026-08-09 while `agy_ask` gained its `discipline` and
`artifactPath` parameters on 2026-08-19/20 (`fc5766e`). The running server therefore advertises a
strictly older `agy_ask` schema than the repo defines, so any caller written against HEAD sends
arguments the installed binary does not declare.

## Code-level Mitigation

In the bridge's own tool-dispatch error path, two changes:

1. **Classify before reporting.** An argument-validation failure is a distinct terminal outcome from a
   transport failure. Surface it as such, and name the offending parameter plus the parameters the tool
   actually declares. The information is already in hand at the rejection site - it is discarded on the
   way out.
2. **Say the discriminator in the message.** When one tool fails and the server is otherwise answering,
   emit the one line that ends the misdiagnosis: "this tool rejected the request; the server is up (the
   status probe answered). Compare the parameter names against the tool's own schema." Pair it with the
   build stamp the sibling item already asks for, since the usual root cause is a stale binary.

Both are in the client's result-classification code and need no peer cooperation.

## Notes

Deterministic on both variants: each dispatches its own tool calls and each can distinguish a local
argument rejection from a transport error before anything leaves the process.

Sibling of `stale-client-binary-blamed-on-the-peer` (the usual CAUSE of the drift) and of
`idle-status-is-not-completion` (a different way a healthy-looking channel returns nothing useful).
This item covers the MISDIAGNOSIS; that one covers the terminal classification of an empty answer.

Carried driver rule stays until the retirement gates are met: before reporting a peer unreachable,
check whether SIBLING tools on the same server still answer, and re-fetch the failing tool's own schema
to compare parameter names. One tool down is drift; all tools down is an outage.
