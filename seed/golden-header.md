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
- NEVER ACCEPT ITS OWN ACCOUNT OF AN ACTION IT PERFORMED. Told to (1) checkpoint (2) edit (3) commit, it
  edited only, then reported all three done and named a recovery checkpoint that never existed - the
  mutation landed with NO recovery point while the reply asserted one. Verify the artefact itself: refs,
  reflog, commit count, stash list, the file on disk.
- CONFABULATION COVERS STRUCTURE AND INTENT, not just external facts, and SURVIVES ACROSS SESSIONS: it
  re-asserts a claim you refuted last session at identical confidence, invents a plausible RATIONALE for
  an existing decision and then reasons from it, and misdescribes a file's shape in the same reply whose
  conclusion about that file is correct. The tell for an invented rationale is that it is more
  interesting than the real one. Make it QUOTE the line; treat any uncited "this exists because..." as
  unsourced. It concedes cleanly to exact evidence, and often leaves a real nit.
- A PANEL IS NOT A CODE GATE. Even the specialist seat greens code carrying reachable crash/lifecycle/race
  bugs - it reasons over the artifact-as-described, not executable behaviour - and a brief that PRE-STATES
  the invariants gets them restated back as "no findings". Confirmation is not verification. Follow every
  GO by RUNNING the oracle and reading the committed diff yourself.
- LATE IN A LONG REVIEW THREAD IT MANUFACTURES FINDINGS, quoting as verbatim content lines that do not
  exist - sometimes past end-of-file - at confidence identical to a real finding. The tell is a finding
  count that shrinks but never reaches zero. Require an exact QUOTE per finding and grep it before
  folding; when a quote fails, RE-DERIVE the claim at the right location instead of discarding it (finding
  rate and citation accuracy are INDEPENDENT, so a fabricated quote can still carry a real defect).
- VAGUE DIALS PRODUCE THEATER. "Be exhaustive / maximally creative" yields padding and safe novelty.
  Replace with FORCING FUNCTIONS: named dimensions to fill, a quota of >=N distinct findings, line-by-line
  scope, an adversarial role with a goal - always with a checkable success criterion.

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
- DIRECTION RIGHT, SPECIFICS WRONG. On a discovery-path failure it names a plausible but FABRICATED
  location; on cost it correctly spots that a traversal costs something, then states magnitude and trigger
  frequency with unearned confidence ("every 500ms forever" for a path that fires once per call). The
  finding is usually real, the NUMBER attached to it usually is not - ask WHERE the loop re-enters rather
  than accepting the rate quoted. Keep the direction, re-derive the specifics. Its OS/concurrency
  INTERNALS reasoning (lock lifetimes, async-teardown ordering) is a genuine strength - design against it,
  still gate the final behaviour on smoke.
- process-alive is not endpoint-reachable: a live process count is no proof the control endpoint will
  connect (its announced address can be stale or absent). Probe reachability with a bounded deadline and a
  fail-safe "unknown"; never infer liveness from process presence.
