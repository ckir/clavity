# agy-autotrain — learn from every agy call, and keep the driving sharp

An **optional** dual-plugin (Claude + agy) add-on for the agy-driving **learning loop**, with **no
binary changes** (it composes the existing `clavity` commands + markdown). Everyday agy-driving usage
feeds the loop, and the curated wisdom is injected back into every future call.

> **Driving itself lives in the CORE plugins, not here.** The task-assignment protocol that stops agy
> misfiring (REVIEW-ONLY banner, phase isolation, mandatory pre-mutation checkpoint,
> seed-the-invariants) ships in the core driving skills — `clavity-driving` (classic) and
> `clavity-ls-driving` (dotnet) — so you can drive agy with or without this add-on. agy-autotrain adds
> the *learning* loop — and the `adversarial-panel-review` skill — on top.

What this add-on does: **capture → curate → verify → compile**, then promote project-local → global,
and emit a compiled golden header that both driver binaries (dotnet `clavity-ls` and classic `clavity`)
prepend to every ask.

## How it works

```
drive agy (core driving skill) ──learn──▶ knowledge/agy-observations.md   (inbox: sanitised general rules)
        ▲                                          │
        │ golden-header (injected by the binary)   │ periodic
        │                                          ▼
 shared golden-header.growth.md ◀──compile+commit── agy-curate ──dedupe vs SEED floor──▶ (SEED is driver-owned,
   (%USERPROFILE%\.clavity\ — GROWTH region)        │            NOT edited here: seed/golden-header.md baseline)
                                                   └──verify (synthetic clavity ask)──▶ verify/assertions.md
```

- **Capture** (`agy-learn`): the moment you learn something general about agy, a Structured Abstraction
  Schema strips project nouns into a `[General Rule]`, classified `assumption | heuristic |
  anti-pattern`, appended to the inbox. Fast, live, project-agnostic.
- **Curate** (`agy-curate`): drains the inbox into the **GROWTH region** of the shared golden-header
  under a promotion rubric (heuristic ≥2 cross-session obs; empirical = 100% harness pass — physically
  run the probe), deduped against the driver-owned SEED floor, and **commits it via the binary**
  (`clavity-ls curate-commit` → `golden-header.growth.md`), empties the inbox. It never edits the SEED
  manuals.
- **Verify** (`verify/`): each Empirical Assumption has a synthetic `clavity ask` probe + pass/fail.
  [`verify/README.md`](verify/README.md) indexes it; [`verify/probe-design.md`](verify/probe-design.md)
  covers designing a new (paired) probe.
- **Knowledge** (`knowledge/`): holds the `agy-observations.md` capture inbox and the pinned
  `driver-cheatsheet.core.md` baseline (kept byte-identical to constants in both driver binaries — see
  [CONTRIBUTING.md](CONTRIBUTING.md)). The canonical manuals (`agy-capabilities.md` /
  `agy-assumptions.md`) and the `golden-header.md` SEED baseline are **driver-owned** — they ship with
  the driver plugins (clavity-dotnet, clavity-classic), not here; agy-curate reads them as a floor but
  never edits them.

The `adversarial-panel-review` skill (AGY-AFTER team-panel review) and its PostToolUse reminder hook
now ship with each driver's own plugin (`clavity-dotnet/plugin`, `clavity-classic/plugin`) instead of
here — agy-autotrain retains only the learning loop (learn/curate/verify + the observations inbox).

### Scope

Project-local first (prove the loop), then promote the skills + knowledge to the global config — the
established trial-then-globalise pattern. Deferred (binary, out of scope): auto-telemetry footer on
`clavity ask` + a `clavity log` history dump — revisit only with a compelling reason.

## What's in here

```
agy-autotrain/
  .claude-plugin/plugin.json · plugin.json   # dual manifests
  skills/agy-learn/          # capture (sanitise → inbox)
  skills/agy-curate/         # curate (promote/verify/recompile → curate-commit)
  knowledge/agy-observations.md         # capture inbox (raw, project-agnostic)
  knowledge/driver-cheatsheet.core.md   # pinned baseline (see CONTRIBUTING.md)
  verify/assertions.md · run-verification.md   # the live test harness
```

## Install

**Recommended (end users):** run the standalone **agy-autotrain** installer
(`agy-autotrain-setup-<version>.exe`) from the
[clavity release page](https://github.com/ckir/clavity/releases). It stages the plugin and registers it
locally — a scoped `clavity-agy-autotrain` marketplace under its own install dir — against every
detected agent (Claude Code / agy). No manual `plugin install`, and no remote marketplace: the plugin
ships inside the installer.

**From a clone (developers):**
```
claude plugin install ./agy-autotrain
agy    plugin install ./agy-autotrain
```

Driving needs only the core plugin; install this add-on when you also want agy to *learn*. When you
learn something about agy, run `agy-learn`; periodically run `agy-curate` to compile + commit the
golden header.

## Configuration

- `CLAVITY_GOLDEN_HEADER` — overrides the directory the shared golden-header files (SEED + GROWTH) are
  read from and written to. Default `%USERPROFILE%\.clavity\`. Read/set by `agy-curate` (see
  `skills/agy-curate/SKILL.md`); only the binary can actually resolve it at injection time.

## Troubleshooting

- **Learned rules never show up in agy's context.** No clavity driver (clavity-dotnet or
  clavity-classic) is installed yet — agy-autotrain composes on top of one but ships no binary of its
  own, so nothing injects the golden header until a driver is present. Install one; expected and
  non-blocking until then (source: `installer/agy-autotrain.iss` post-install message).
- **Install/uninstall silently fails to (de)register the plugin.** Claude Code was running during
  setup — it rewrites the plugin registration on its own startup/exit and overwrites what the
  installer just did. Close Claude Code completely, then run the installer again (source:
  `installer/agy-autotrain.iss`).

## Docs

- [ROADMAP.md](ROADMAP.md) — enhancement backlog for the learning loop.
- [docs/fix-the-tool-backlog/](docs/fix-the-tool-backlog/README.md) — deterministic driver/tool defects
  `agy-curate` declined to promote into knowledge (fixable in a driver's execution path, not durable
  peer psychology).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[PolyForm Noncommercial License 1.0.0](LICENSE) (`PolyForm-Noncommercial-1.0.0`) — free for
non-commercial use. See [NOTICE](NOTICE) for the copyright line.
