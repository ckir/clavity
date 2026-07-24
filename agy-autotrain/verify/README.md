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
- A committed SessionStart reminder re-arms the probes when `agy --version` changes.

## Quickstart

- Run an existing probe → follow [`run-verification.md`](run-verification.md).
- Design a new one → read [`probe-design.md`](probe-design.md).
