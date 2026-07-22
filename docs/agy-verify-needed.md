# agy verify-needed backlog

Empirical Assumptions parked by `agy-curate` pending a live-agy verify-probe. They are NOT promoted into
the golden-header GROWTH/SEED until their probe passes 100% and is recorded in `agy-autotrain/verify/assertions.md`
(procedure: `agy-autotrain/verify/run-verification.md`). A stale probe is RE-RUN, never re-stamped.

## Pending

- [assumption] (peer/probabilistic) Documentation of an agent's OWN failure modes, injected into that agent's
  context, may PRIME the behaviour it describes rather than prevent it: a corpus line of the form "without X the
  agent does Y" is read as a self-description, and absent X the agent is MORE likely to do Y. Actionable form
  (already applied architecturally by the golden-header audience split): route behavioural knowledge to whoever
  must ACT on it and away from its subject; when subject == audience, phrase the rule as a directive ("do Y only
  when X"), never a self-description ("without X, you do Y"). PROBE: same task, same absent precondition, corpus
  line present vs absent; measure whether Y's rate rises when the self-description is in context. Captured
  2026-07-21, parked 2026-07-22.
