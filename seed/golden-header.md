<!-- Compiled SEED baseline for the golden-header (accumulated agy-driving wisdom). Seeded verbatim into
     %USERPROFILE%\.clavity\golden-header.seed.md and injected as the SEED region of every ask.
     Keep dense + decision-changing only. If empty/absent, injection silently omits it. -->

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
- Latency is BIMODAL / payload-bound, not a constant. Focused, bounded asks (one question, artifact sent
  by filepath, scoped) return in ~45–90s and a sync call does NOT time out. Only deep-generative mega-payloads
  — or asks fired while agy is still mid-turn (the doorbell idle-gate serializes them) — reach minute-scale
  (~9–10 min); for those prefer async (fire → work → await-reply). Either way a reply can land AFTER a sync
  timeout: it's on the bus, recover it. Reducers: tighten/decompose the ask; send a filepath not the payload;
  don't fire while busy.
- agy replies on a NEW bus thread per request; correlate by req_id / replyTo, not the request's thread.
- agy verifies >> discovers: seeded with invariants it finds genuine must-fix defects. Always pair the
  critique with a generative "what's missing / simpler / stronger" ask.
- agy may be quota/backend-locked (silent timeout); keep a Claude fallback for critical-path work.
