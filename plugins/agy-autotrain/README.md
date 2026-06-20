# agy-autotrain — drive agy like a model, and learn from every call

A universal dual-plugin (Claude + agy) that does two things, with **no binary changes** (it composes
the existing `clavity` commands + markdown):

1. **One front door to agy.** A `driving-agy` skill so Claude calls the agy peer itself — via
   `clavity ask` (sync) or send + `clavity await-reply` (async) — *without the human typing any
   command*. It encodes the task-assignment protocol that stops agy misfiring (REVIEW-ONLY banner,
   phase isolation, mandatory pre-mutation checkpoint, seed-the-invariants) and auto-prepends the
   compiled `golden-header.md` to every payload.
2. **Auto-training knowledge loop.** Everyday usage teaches it: **capture → curate → verify → compile**,
   then promote project-local → global.

## The loop

```
drive agy (driving-agy) ──learn──▶ knowledge/agy-observations.md   (inbox: sanitised general rules)
        ▲                                      │
        │ golden-header.md (auto-prepended)    │ periodic
        │                                      ▼
 knowledge/golden-header.md ◀──compile── agy-curate ──promote(rubric)──▶ knowledge/agy-capabilities.md
                                              │                              + agy-assumptions.md (canonical)
                                              └──verify (synthetic clavity ask)──▶ verify/assertions.md
```

- **Capture** (`agy-learn`): the moment you learn something general about agy, a Structured Abstraction
  Schema strips project nouns into a `[General Rule]`, classified `assumption | heuristic | anti-pattern`,
  appended to the inbox. Fast, live, project-agnostic.
- **Curate** (`agy-curate`): drains the inbox into the canonical manual under a promotion rubric
  (heuristic ≥2 cross-session obs; empirical = 100% harness pass — physically run the probe), dedupes/
  prunes/resolves drift, recompiles the golden header, empties the inbox.
- **Verify** (`verify/`): each Empirical Assumption has a synthetic `clavity ask` probe + pass/fail.
- **Knowledge** (`knowledge/`): the canonical `agy-capabilities.md` / `agy-assumptions.md` travel *inside*
  the plugin, so it ships as a portable, standalone "agy instruction manual."

## Layout

```
agy-autotrain/
  .claude-plugin/plugin.json · plugin.json   # dual manifests
  skills/driving-agy/        # the front door + task-assignment protocol + golden-header prepend
  skills/agy-learn/          # capture (sanitise → inbox)
  skills/agy-curate/         # curate (promote/verify/recompile/empty)
  knowledge/agy-capabilities.md · agy-assumptions.md   # canonical manual (portable)
  knowledge/agy-observations.md   # inbox (raw, project-agnostic)
  knowledge/golden-header.md      # compiled, auto-prepended to every ask
  verify/assertions.md · run-verification.md   # the live test harness
```

## Install

```
claude plugin install ./plugins/agy-autotrain
agy    plugin install ./plugins/agy-autotrain
```

Then drive: when you want a second opinion/review, just call `clavity ask` (the `driving-agy` skill
guides it). When you learn something about agy, run `agy-learn`. Periodically run `agy-curate`.

## Scope

Project-local first (prove the loop), then promote the skills + knowledge to the global config — the
established trial-then-globalise pattern. Deferred (binary, out of scope): auto-telemetry footer on
`clavity ask` + a `clavity log` history dump — revisit only with a compelling reason.
