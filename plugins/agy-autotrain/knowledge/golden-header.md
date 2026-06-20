<!-- COMPILED by agy-curate from the canonical manual. Auto-prepended to every `clavity ask`.
     Keep dense + decision-changing only. If empty/absent, driving-agy silently omits it. -->

[⚠️ CRITICAL ANTI-PATTERNS — how NOT to drive agy]
- A review/consult WITHOUT a loud, enumerated REVIEW-ONLY (no-edit/no-commit) banner → agy EXECUTES the
  task. Always open a review with the banner + an explicit forbidden-actions list + "permission to pass."
- Mixing exploration and execution in one payload degrades the build (context fills with raw search
  output). One phase per payload: tag [PHASE: EXPLORATION] or [PHASE: EXECUTION].
- Delegating a mutating task without ordering a pre-change checkpoint risks unrecoverable edits. Require
  a stash/temp-branch BEFORE touching the tree.
- Asking agy to "find bugs" open-endedly → over-escalation/hallucination. Seed the specific invariants
  to confirm/refute and grant "no must-fix is valid."

[LOAD-BEARING ASSUMPTIONS]
- First-token latency is minute-scale (~9–10 min for deep work); a sync call may time out though agy
  replied — the reply is on the bus, recover it. Prefer async (fire → work → await-reply) for non-trivial asks.
- agy replies on a NEW bus thread per request; correlate by req_id / replyTo, not the request's thread.
- agy verifies >> discovers: seeded with invariants it finds genuine must-fix defects. Always pair the
  critique with a generative "what's missing / simpler / stronger" ask.
- agy may be quota/backend-locked (silent timeout); keep a Claude fallback for critical-path work.
