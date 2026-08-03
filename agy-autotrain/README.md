# agy-autotrain — learn from every agy call, and keep the driving sharp

An **optional** Claude Code add-on for the agy-driving **learning loop**, with **no
binary changes** (it composes the existing `clavity` commands + markdown). Everyday agy-driving usage
feeds the loop, and the curated wisdom is injected back into every future call.

> **Driving itself lives in the CORE plugins, not here.** The task-assignment protocol that stops agy
> misfiring (REVIEW-ONLY banner, phase isolation, mandatory pre-mutation checkpoint,
> seed-the-invariants) ships in the core driving skills — `driving` (classic) and
> `ls-driving` (dotnet) — so you can drive agy with or without this add-on. agy-autotrain adds
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
locally — a scoped `clavity-agy-autotrain` marketplace under its own install dir — with Claude Code
only (never agy, which has no use for it). No manual `plugin install`, and no remote marketplace: the
plugin ships inside the installer.

**From a clone (developers):**
```
claude plugin install ./agy-autotrain
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
- **Install/uninstall refuses to run with an error dialog.** The installer detects a running Claude
  Code and blocks — Claude Code rewrites the plugin registration on its own startup/exit, which would
  overwrite what the installer just did. Close Claude Code completely, then run the installer again
  (source: `installer/agy-autotrain.iss`).

## Recovering lost observations or a bad GROWTH region

Both artifacts keep the newest 5 pre-mutation snapshots. A backup nobody can restore from is theatre, so
both procedures are one command.

**The observations inbox:**

```powershell
$k = "$env:LOCALAPPDATA\Programs\agy-autotrain\plugins\agy-autotrain\knowledge"
Get-ChildItem "$k\agy-observations.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$k\agy-observations.md.<stamp>.bak" "$k\agy-observations.md"
```

A restored inbox is a PRE-drain inbox. Its entries were already folded into GROWTH by the drain you are
undoing, so **reconcile before the next drain**: compare the restored `## Pending` against the current
GROWTH region and delete anything already represented there. Skipping this duplicates rules in the header
injected into every ask.

**The GROWTH region — restore both files, always:**

```powershell
Get-ChildItem "$HOME\.clavity\golden-header.growth.md.*.bak" | Sort-Object LastWriteTime -Descending
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak"        "$HOME\.clavity\golden-header.growth.md"
Copy-Item "$HOME\.clavity\golden-header.growth.md.<stamp>.bak.sha256" "$HOME\.clavity\golden-header.growth.md.sha256"
```

Restoring the header alone leaves the previous sidecar in place; the hashes mismatch and the read side
silently drops the region. The restore looks successful and does nothing.

Snapshots rotate on the `.bak` suffix only, so a hand-made backup named anything else (a
`*.preinstall-backup`, a dated `*.corrupt-backup-*`) sits outside the ring and is never evicted by it.

**What snapshots do not cover.** These protect against loss — a truncated file, a bad edit, a drain that
went wrong. They do not detect silent corruption: if content is wrong when it arrives, the snapshot
faithfully preserves the wrong content.

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
