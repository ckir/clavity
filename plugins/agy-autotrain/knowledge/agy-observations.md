# agy observations inbox (raw, project-agnostic)

Captured live by `agy-learn`; drained by `agy-curate` into the canonical manual
(`agy-capabilities.md` / `agy-assumptions.md`) and recompiled into `golden-header.md`. One bullet per
observation. Project nouns are forbidden here (Structured Abstraction Schema). Provenance tags:
`[corpus]` observed live · `[doc]` from docs · `[local]` this install · `[verified]` ≥2 sources.

## Pending

- [anti-pattern] A review/consult request sent WITHOUT a loud, enumerated REVIEW-ONLY (no-edit/no-commit) banner makes agy drift into *executing* the task instead of reviewing it. `[corpus]` · 2026-06-20
- [assumption] agy reliably honors a loud REVIEW-ONLY banner with an explicit forbidden-actions list — it makes no edits and returns a verdict. `[corpus]` · 2026-06-20
- [assumption] agy's first-token latency for a deep consult is minute-scale (~9–10 min); a synchronous blocking driver call commonly hits its timeout even though agy did reply — the reply is still on the bus and is recoverable. `[corpus]` · 2026-06-20
- [assumption] agy replies on a NEW bus thread per request; correlate the reply by req-id / replyTo, never by the request's own thread id. `[corpus]` · 2026-06-20
- [heuristic] agy verifies far better than it discovers: when seeded with specific invariants on a real review it surfaces multiple genuine must-fix defects, including subtle concurrency/idempotency and error-handling hazards. `[corpus]` · 2026-06-20
- [anti-pattern] Mixing exploration and execution in a single payload degrades the build (agy's context fills with raw search output) — isolate phases explicitly. `[corpus]` · 2026-06-20
- [assumption] A delegated mutating task should instruct agy to make a recoverable checkpoint (stash/branch) before touching the live tree. `[corpus]` · 2026-06-20
- [assumption] Across five consecutive deep design consults, EVERY synchronous driver call timed out at its cap (~9–10 min) yet every reply still landed on the bus — for deep/generative consults, asynchronous invocation (or sync purely as a fire-and-recover-from-bus) is mandatory, not optional. `[corpus]` (N=5) · 2026-06-20
- [heuristic] On a design consult that asks BOTH "pressure-test this" AND "what's missing / simpler / stronger", agy reliably returns adopted, high-leverage additions across rounds — always pair a critique request with an explicit generative ask. `[corpus]` · 2026-06-20
