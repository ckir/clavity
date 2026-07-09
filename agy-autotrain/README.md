# agy-autotrain — learn from every agy call, and keep the driving sharp

An **optional** dual-plugin (Claude + agy) add-on for the agy-driving **learning loop**, with **no binary
changes** (it composes the existing `clavity` commands + markdown). It is the driving-PERFECTION loop:
everyday usage teaches it, and the distilled wisdom flows back into every call.

> **Driving itself lives in the CORE plugins, not here.** The task-assignment protocol that stops agy
> misfiring (REVIEW-ONLY banner, phase isolation, mandatory pre-mutation checkpoint, seed-the-invariants)
> ships in the core driving skills — `clavity-driving` (classic) and `clavity-ls-driving` (dotnet) — so you
> can drive agy with or without this add-on. agy-autotrain adds only the *learning* on top.

What this add-on does: **capture → curate → verify → compile**, then promote project-local → global, and
emit a compiled `golden-header.md` that the binary (dotnet `clavity-ls`) prepends to every ask — or that the
classic `clavity-driving` skill prepends manually until the classic binary injects it.

## The loop

```
drive agy (core driving skill) ──learn──▶ knowledge/agy-observations.md   (inbox: sanitised general rules)
        ▲                                          │
        │ golden-header (injected by the binary)   │ periodic
        │                                          ▼
 shared golden-header.md ◀──compile+commit── agy-curate ──promote(rubric)──▶ knowledge/agy-capabilities.md
   (%USERPROFILE%\.clavity\)                       │                              + agy-assumptions.md (canonical)
                                                   └──verify (synthetic clavity ask)──▶ verify/assertions.md
```

- **Capture** (`agy-learn`): the moment you learn something general about agy, a Structured Abstraction
  Schema strips project nouns into a `[General Rule]`, classified `assumption | heuristic | anti-pattern`,
  appended to the inbox. Fast, live, project-agnostic.
- **Curate** (`agy-curate`): drains the inbox into the canonical manual under a promotion rubric
  (heuristic ≥2 cross-session obs; empirical = 100% harness pass — physically run the probe), dedupes/
  prunes/resolves drift, recompiles the golden header and **commits it via the binary** (`clavity-ls
  curate-commit`), empties the inbox.
- **Verify** (`verify/`): each Empirical Assumption has a synthetic `clavity ask` probe + pass/fail.
- **Knowledge** (`knowledge/`): the canonical `agy-capabilities.md` / `agy-assumptions.md` travel *inside*
  the plugin, so it ships as a portable, standalone "agy instruction manual."

## Layout

```
agy-autotrain/
  .claude-plugin/plugin.json · plugin.json   # dual manifests
  skills/agy-learn/          # capture (sanitise → inbox)
  skills/agy-curate/         # curate (promote/verify/recompile → curate-commit)
  knowledge/agy-capabilities.md · agy-assumptions.md   # canonical manual (portable)
  knowledge/agy-observations.md   # inbox (raw, project-agnostic)
  knowledge/golden-header.md      # the compiled header source (committed to the shared path by agy-curate)
  verify/assertions.md · run-verification.md   # the live test harness
```

## Install

```
claude plugin install ./plugins/agy-autotrain
agy    plugin install ./plugins/agy-autotrain
```

Driving needs only the core plugin; install this add-on when you also want agy to *learn*. When you learn
something about agy, run `agy-learn`; periodically run `agy-curate` to compile + commit the golden header.

## Scope

Project-local first (prove the loop), then promote the skills + knowledge to the global config — the
established trial-then-globalise pattern. Deferred (binary, out of scope): auto-telemetry footer on
`clavity ask` + a `clavity log` history dump — revisit only with a compelling reason.
