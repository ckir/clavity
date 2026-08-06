---
slug: stalled-reply-recoverable-not-lost
variant: clavity-dotnet
observed: 2026-07-31
source-inbox-entry: "- [assumption] (driver/deterministic) A review transport can stall mid-step while the peer's work continues to completion"
status: open
last-triaged: 2026-08-06   # oracle: no idle-expiry poll / retry path in AgyView.cs -> expiry still throws rather than re-polling, confirmed still open
---

# An idle-wait expiry discards a reply the peer already finished producing

## Steps to Reproduce
Fire a synchronous ask whose reply is large or whose turn is long. The bridge's fixed idle-wait expires
and returns a timeout/stall to the caller, while the peer's step counter keeps advancing and the turn
reaches completion. The reply then exists on the peer side but never reaches the caller, so it reads as
"never produced" rather than "produced and dropped in transit".

Corroborated live on 2026-08-02 against agy 1.1.9 by verify-harness probe A2 (see
`agy-autotrain/verify/assertions.md`, row A2). An oversized single-shot ask returned with
`AnswerTruncated=true`, cut mid-word, and a minimal decomposed re-ask recovered the exact continuation
from the precise cut point - proving the tail existed on the peer side the whole time. The truncation
path and this stall path differ in mechanism but share the consequence: completed work is discarded by
the transport, and the caller cannot tell that from work never done.

## Code-level Mitigation
On idle-wait expiry, do not surface a bare timeout. Poll `agy_status` until the cascade reports idle
(bounded by a separate, longer deadline), then retrieve the completed turn from the cascade trajectory
and return it. Only if the step counter is genuinely NOT advancing should the call be reported as
stalled. This makes "the transport gave up" distinguishable from "the peer is stuck", which is the
distinction the caller actually needs.

Sibling constraint: trajectory retrieval is currently capped by `grpc-default-max-message-size` (see
that item) - the channel takes gRPC's 4 MB default, so a large trajectory readback fails
`ResourceExhausted`. That item should land first or alongside; otherwise this mitigation inherits the
same ceiling and silently fails on exactly the large replies that most need recovering.

## Notes
The driving-side workaround is ALSO carried as a cheatsheet-adjacent rule and must not be retired when
this is fixed: ask the peer to RESTATE its already-reached conclusion rather than re-sending the
original ask, because re-sending re-bills and re-runs work that is already done. Offer a licensed
"NO PRIOR RESULT" escape hatch so a genuine absence is reportable instead of confabulated - measured
working on 2026-08-02: the hatch was available, unused, and the continuation resumed at the exact cut.

## Disposition — open-work sweep, 2026-08-06

**KEPT — all three clauses met.**

1. **Loss AND lie.** An idle-wait expiry returns a timeout while the peer's turn completes, so a finished
   reply exists on the peer side and never reaches the caller — reading as *"never produced"* rather than
   *"produced and dropped in transit"*. **The induced wrong action is re-asking**, paying for the turn
   again. Corroborated live 2026-08-02 against agy 1.1.9 by verify-harness probe A2: a decomposed re-ask
   recovered the exact continuation from the precise cut point, proving the tail existed the whole time.
2. **Unavoidable.** Large or long turns are ordinary for review work.
3. **Mechanism.** On expiry, poll `agy_status` to a longer deadline and retrieve the completed turn from
   the trajectory; report stalled only if the step counter is genuinely not advancing.
