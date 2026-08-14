---
slug: idle-status-is-not-completion
variant: both
observed: 2026-08-10
source-inbox-entry: "AN IDLE STATUS FROM A PEER IS NOT EVIDENCE THE PEER FINISHED"
status: open
---

# An idle peer status is reported as a completion signal, so a null answer reads as a clean result

## Steps to Reproduce

On either bridge, send a consult that the peer cannot complete (quota wall, or a request whose
cascade dies before emitting its final text step):

1. `clavity ask "<payload>" --review-only` (classic) or `agy_ask` (dotnet).
2. The call returns with no answer text and exit 0.
3. Probe `agy_status` immediately afterwards - it reports **idle**.
4. The deliverable the payload asked the peer to write does not exist on disk.

Measured 2026-08-10: idle was reported immediately after a round that produced no reply and wrote no
file, and reported idle again after a follow-up that failed the same way. Idle only means nothing is
currently executing, which is equally true of a peer blocked on an approval it will never receive.

## Code-level Mitigation

The bridge must not report success on an empty answer. Two concrete changes in the ask path:

1. Treat `answer.text` empty/whitespace as a **distinct terminal outcome** (`no-answer`) rather than a
   successful empty reply, and surface it with a non-zero status distinguishable from a transport error.
2. Where the caller supplied a deliverable path, gate completion on the artefact existing rather than on
   the RPC returning - i.e. `idle AND no deliverable` is reported as `blocked`, never as `done`.

Both are in the bridge's own result-classification code and need no peer cooperation.

## Notes

Deterministic on both variants: the status probe and the empty-answer return are bridge-side facts, not
peer judgements, so both transports can observe them.

Adjacent but distinct from `idle-wait-false-modal` (a cap expiring while the peer is still producing
steps) and `working-vs-stuck-step-delta` (telling a stall from progress). Those cover DETECTION during a
run; this one covers the terminal classification after it. Related: `stalled-reply-recoverable-not-lost`
covers RECOVERY once a reply is known to be stranded.

Carried driver rule stays until the retirement gates are met: never treat idle as a completion signal;
gate completion on the deliverable existing.
