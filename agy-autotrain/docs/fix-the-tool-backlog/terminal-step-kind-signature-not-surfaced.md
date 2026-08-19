---
slug: terminal-step-kind-signature-not-surfaced
variant: both
observed: 2026-08-10
source-inbox-entry: "A PEER CASCADE THAT ENDS ON A REPEATED IDENTICAL STEP-KIND WITH NO OUTPUT"
status: open
---

# An impaired channel and an overrun are indistinguishable, though the step trajectory separates them

## Steps to Reproduce

1. Run a consult that succeeds and record its trajectory: measured, a successful round ends on a
   text-bearing step preceded by two specific marker kinds.
2. Run a consult that fails on an impaired channel. Measured, it instead ends on **three consecutive
   copies of one non-text step kind**, the peer reports IDLE, the transport returns a null answer, and
   the file the peer was asked to write does not exist anywhere on disk.
3. Re-send a short follow-up: it reproduces the identical three-step signature in nine steps rather than
   recovering - i.e. the signature is stable and cheap to detect.

A cap or overrun looks different: a long trajectory that simply lacks its final text step. Today the
driver sees the same opaque "no answer" in both cases and has to guess, and guessing wrong means
re-sending (which restarts the work and can double-charge a long review).

## Code-level Mitigation

The bridge already reads the cascade trajectory. On a null/empty answer, classify before returning:

1. Compare the tail of the step-kind sequence against a recorded known-good terminal signature. Emit
   `channel-impaired` when the tail is N identical non-text kinds, and `truncated-or-capped` when the
   trajectory is long but merely lacks its final text step.
2. Return that classification in the error surface so the driver can escalate rather than re-send. The
   two outcomes have opposite correct responses, which is what makes conflating them expensive.

The reference signature can be captured from any successful round, so this needs no peer cooperation.

## Notes

Deterministic on both variants where the transport exposes the trajectory. Confirm per variant before
closing: if one bridge cannot read the step trajectory, the rule stays a carried driver rule THERE while
this item is fixed on the other.

Adjacent to `working-vs-stuck-step-delta` (progress vs stall DURING a run) and
`idle-status-is-not-completion` (the terminal outcome is not a success). This item is specifically about
naming WHICH failure a null answer was.

Carried driver rule stays until the retirement gates are met: when a round returns nothing, compare
trajectories against a known-good round before re-sending.
