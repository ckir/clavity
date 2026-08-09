---
slug: stalled-reply-recoverable-not-lost
variant: clavity-dotnet
observed: 2026-07-31
source-inbox-entry: "- [assumption] (driver/deterministic) A review transport can stall mid-step while the peer's work continues to completion"
status: fixed
last-triaged: 2026-08-07   # CORRECTED. The 2026-08-06 stamp read "no idle-expiry poll / retry path in AgyView.cs -> confirmed still open". FALSE NEGATIVE on invented vocabulary (see docs/backlog-triage-runbook.md section 2): the shipped mechanism is the lastProgress loop in WaitForIdleWithProgressAsync, which IS the step-counter discriminator this entry asks for.
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

Sibling constraint: trajectory retrieval was capped by `grpc-default-max-message-size` (see that item) - the
channel took gRPC's 4 MB default, so a large trajectory readback failed `ResourceExhausted`. That item should
land first or alongside; otherwise this mitigation inherits the same ceiling and silently fails on exactly the
large replies that most need recovering.

> [!] **RESOLVED 2026-08-07.** The sibling shipped: `LsChannel` now sets `MaxReceiveMessageSize = 64 MB`
> (`80a254c`), so this constraint no longer binds. Tense corrected here because the original read "is
> currently capped" - a present-tense claim about ANOTHER entry's state, which goes stale the moment that
> entry ships and which no one re-reads. **This entry itself remains closed as already-fixed; nothing about
> its own disposition changed.**

## Notes
The driving-side workaround is ALSO carried as a cheatsheet-adjacent rule and must not be retired when
this is fixed: ask the peer to RESTATE its already-reached conclusion rather than re-sending the
original ask, because re-sending re-bills and re-runs work that is already done. Offer a licensed
"NO PRIOR RESULT" escape hatch so a genuine absence is reportable instead of confabulated - measured
working on 2026-08-02: the hatch was available, unused, and the continuation resumed at the exact cut.

## Disposition - open-work sweep, 2026-08-06

**KEPT - all three clauses met.**

1. **Loss AND lie.** An idle-wait expiry returns a timeout while the peer's turn completes, so a finished
   reply exists on the peer side and never reaches the caller - reading as *"never produced"* rather than
   *"produced and dropped in transit"*. **The induced wrong action is re-asking**, paying for the turn
   again. Corroborated live 2026-08-02 against agy 1.1.9 by verify-harness probe A2: a decomposed re-ask
   recovered the exact continuation from the precise cut point, proving the tail existed the whole time.
2. **Unavoidable.** Large or long turns are ordinary for review work.
3. **Mechanism.** On expiry, poll `agy_status` to a longer deadline and retrieve the completed turn from
   the trajectory; report stalled only if the step counter is genuinely not advancing.

## Already fixed - closed 2026-08-07, no code written

**The remedy this entry specifies was already implemented.**

**Evidence.** `clavity-dotnet/src/Clavity.Ls/AgyView.cs` - `WaitForIdleWithProgressAsync` already runs the
progress-gated wait this entry asks for. `lastProgress` starts at `before + 1`, and at `:273-274`
`if (total > lastProgress) lastProgress = total;` resets the stall window on every advance, so the wait is
never abandoned while agy is producing steps. It throws only at `:279`/`:281`, after a full window with
**no** new steps - which is precisely this entry's own condition: *"Only if the step counter is genuinely
NOT advancing should the call be reported as stalled."* The throw carries a structured `possible_modal`
envelope with the already-fetched trajectory, not a bare timeout.

**Retirement gate - none required.** Unlike its sibling `conversation-scoped-tools`, this entry's Notes
name no test gate; they only require that the driver-side "ask the peer to RESTATE" workaround is **not**
retired. That workaround stays.

[!!] **Why it was recorded open.** The 2026-08-06 probe looked for an *"idle-expiry poll / retry path"* - a
description of a mechanism, not a symbol the code contains. The shipped design solves the same problem a
different way (never expire while progressing, rather than re-poll after expiring), so the probe found
nothing and reported "confirmed still open". Corrected under `docs/backlog-triage-runbook.md` section 2.

[!] **A narrower question survives and is NOT this entry.** If agy's server ever fails to signal idle while
a turn genuinely completed, a reply could still be lost. That is unproven and unobserved; the A2 evidence
this entry cites is a **truncation** result, and the entry itself says the two mechanisms differ. Re-open
as a NEW entry with its own reproduction if it is ever measured - do not reopen this one.

**No commit from the open-work epic fixed this** - the fix predates the epic. Do not attribute it to one.
