---
slug: answer-null-content-only-in-truncated-activity
variant: clavity-dotnet
observed: 2026-08-15
source-inbox-entry: "- [anti-pattern] (driver/deterministic) A consult protocol with NO FAILOVER loses completed work"
status: open
---

# `agy_ask` returns `Answer: null` while the reply text survives only as a truncated Activity summary

## Steps to Reproduce

On the dotnet bridge (`mcp__plugin_clavity_clavity-ls__agy_ask`), fire a review-sized ask whose reply the
peer composes across several assistant steps. Observed repeatedly on 2026-08-15 during a 17-round panel:

1. `agy_ask` returns a JSON envelope with **`"Answer": null`** and `"AnswerTruncated": false`.
2. The reply text is nonetheless present — as the `Summary` field of the FINAL `Kind: 15` (assistant)
   entry inside `Activity[]`.
3. That `Summary` is **cut off mid-sentence** (measured: `"...creating false-greens that would silently
   certify broken or dangerous implemen"`), so the caller receives a partial answer with no signal that
   it is partial: `AnswerTruncated` is `false` because the *Answer* field was never populated at all.

The same call shape returned a full multi-kilobyte `Answer` on the immediately preceding and following
rounds, so this is intermittent rather than payload-size-deterministic on its face.

**Why the existing items do not cover it.** `stalled-reply-recoverable-not-lost` is about an idle-wait
expiry discarding a completed reply, and `agy-look-tail-truncation` is about `agy_look` returning the head
of a trajectory. This one is `agy_ask` itself reporting success, reporting *not truncated*, and returning
the content only in a lossy secondary field.

## Code-level Mitigation

Two changes to the `agy_ask` return path, both in the bridge:

1. **When `Answer` resolves null but the trajectory contains assistant steps, populate `Answer` from the
   last assistant step's FULL text** rather than leaving it null and letting the caller scrape a summary.
   The summary field is a display projection and must not be the only carrier of the payload.
2. **`AnswerTruncated` must describe what the caller actually receives.** If the returned text is a
   summary rather than the full step, set it `true`. A `false` on a field that was never populated is the
   fail-open: it tells the caller "this is complete" about content that is not there.

Optionally (cheap, and it makes the failure recoverable rather than merely visible): persist the raw
unbounded reply to a file and return its path, so a caller that hits any bounding can re-read the original.

## Notes

- **Determinism:** dotnet-only as observed. The classic variant returns replies over a different path
  (`clavity ask` / relay file) and was not exercised here — do not assume it reproduces there.
- **The driver-side rule stays regardless of this fix** (retirement needs a green CI regression test plus
  end-user adoption, per agy-curate 5.C-B/5.C-D): byte-count every reply against that peer's OWN recent
  replies, never against zero. A 100-byte answer where the last three ran 3-6 KB is a failed consult, not
  a terse one — and in this failure mode neither the exit status nor `AnswerTruncated` will tell you.
- **Do not conflate with peer SELF-truncation**, which is already canonical in the golden header (the peer
  emitting a stub that claims the full answer was delivered, usually caused by a monotonically growing
  brief). That one is peer behaviour with a driving fix; this one is the bridge's envelope.
