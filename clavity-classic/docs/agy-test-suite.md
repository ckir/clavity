# agy acceptance test suite — moved (see the umbrella copy)

> **This file is now a pointer.** The acceptance suite tests the **agy peer** — a dependency both
> clavity variants drive, not a clavity-classic-specific asset — so it lives at the umbrella level:
>
> ### 👉 [`../../docs/agy-test-suite.md`](../../docs/agy-test-suite.md)
>
> That copy is the single source of truth. **Do not re-add content here.** This file and the umbrella
> copy drifted apart unnoticed and ended up instructing readers to take *different* actions on a
> detected drift — which is exactly what this pointer removes. The parity gate
> (`scripts/check-seed-artifacts-synced.sh`) covers the two `plugin/` trees, **not** `docs/`, so nothing
> caught it.

The suite's commands invoke `./target/debug/clavity ask`, so they are run from `clavity-classic/`; the
umbrella copy states that working directory explicitly.
