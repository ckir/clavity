# agy assumptions — moved (see the canonical, portable manual)

> **This file is now a pointer.** The canonical `agy-assumptions.md` — every load-bearing agy behavior
> clavity depends on, how each was verified, and how to re-verify/fix it — ships inside each driver's
> plugin so it travels with the plugin when installed:
>
> ### 👉 [`clavity-dotnet/plugin/knowledge/agy-assumptions.md`](../clavity-dotnet/plugin/knowledge/agy-assumptions.md)
>
> That copy is the single source of truth (the `clavity-classic` plugin carries a byte-identical mirror,
> kept in sync by `scripts/check-seed-artifacts-synced.sh`). This `docs/` breadcrumb exists only so a
> reader who starts in `docs/` is routed to it — **do not re-add content here** (it would drift from the
> canonical copy; that duplication is exactly what this pointer removes).

See also its companion, [`clavity-dotnet/plugin/knowledge/agy-capabilities.md`](../clavity-dotnet/plugin/knowledge/agy-capabilities.md)
(what agy can do + how to route work to it). For the **.NET / Language-Server** variant's assumptions, see
[`agy-ls-assumptions.md`](agy-ls-assumptions.md).
