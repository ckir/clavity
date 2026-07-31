# agy verification harness

The empirical-verification harness for the live agy peer. agy is external and non-contract, so
load-bearing assumptions about it are VERIFIED with synthetic probes rather than trusted, and
re-verified whenever agy's version changes.

## The pieces

| File | What it is |
|---|---|
| [`assertions.md`](assertions.md) | The probe suite — each testable assumption with its synthetic ask, observable, PASS criterion, and version-stamped last run. Records MEASURED outcomes; treat as data. |
| [`run-verification.md`](run-verification.md) | How to EXECUTE a probe — preflight, per-probe procedure, recording. |
| [`probe-design.md`](probe-design.md) | How to DESIGN a probe, especially the paired (A/B) kind. |
| [`../../docs/agy-verify-needed.md`](../../docs/agy-verify-needed.md) | Assumptions parked awaiting a probe. |

## Status columns

`assertions.md` carries one status column per driver (`dotnet`, `classic`), read by the SessionStart
gate in `.claude/hooks/agy-verify-reminder.sh`.

| Token | Meaning | Gate |
|---|---|---|
| `PASS <ver>` | Observed to pass at that agy version | silent while the version is current |
| `FAIL <ver>` | Observed to fail | **always nags** |
| `PARTIAL <ver>` | Some parts unrun — work in progress | **always nags** |
| `ACKED <ver>` | Verified, unresolvable by us, disposition recorded | silent while current |
| `N/A` | Not applicable to that driver | always silent |

**Unresolved states nag; only resolved or explicitly-dispositioned states can be silent.** A `FAIL`
cannot be quieted by bumping a version — that is deliberate, and it is the whole point of the column.
A new row starts at `PARTIAL <live>`.

## Two probe shapes

- **Single-shot** — a deterministic property (one ask + one observation). Execute via
  [`run-verification.md`](run-verification.md).
- **Paired (A/B)** — a probabilistic / comparative claim (control vs treatment). Design via
  [`probe-design.md`](probe-design.md).

## The loop

- `agy-curate` runs the relevant probe before promoting or keeping an assumption.
- A pass is recorded in [`assertions.md`](assertions.md); the knowledge flows to the golden-header
  GROWTH region.
- A fail, or an un-probed assumption, stays parked in
  [`../../docs/agy-verify-needed.md`](../../docs/agy-verify-needed.md).
- A committed SessionStart gate reads the per-driver status columns and nags while any probe is
  unresolved or stale — see **Status columns** above. `FAIL`/`PARTIAL` nag regardless of version, so a
  re-stamp cannot silence them.

## Quickstart

- Run an existing probe → follow [`run-verification.md`](run-verification.md).
- Design a new one → read [`probe-design.md`](probe-design.md).
