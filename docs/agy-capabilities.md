# agy capabilities — moved (see the canonical, portable manual)

> **This file is now a pointer.** The canonical `agy-capabilities.md` — what agy can do, where it is
> strong and weak, and how to route work to it — ships inside each driver's plugin so it travels with
> the plugin when installed:
>
> ### 👉 [`clavity-dotnet/plugin/knowledge/agy-capabilities.md`](../clavity-dotnet/plugin/knowledge/agy-capabilities.md)
>
> That copy is the single source of truth (the `clavity-classic` plugin carries a byte-identical mirror,
> kept in sync by `scripts/check-seed-artifacts-synced.sh`). This `docs/` breadcrumb exists only so a
> reader who starts in `docs/` is routed to it — **do not re-add content here** (it would drift from the
> canonical copy; that duplication is exactly what this pointer removes).

Two things the canonical copy deliberately does differently from the version this pointer replaced:

- **It pins no agy version, tool-call ceiling, or model roster.** Those drift with every agy release, and
  the copy that used to live here had gone stale on all three. The canonical manual states capabilities in
  version-independent terms instead.
- **It carries no manual refresh runbook.** Refreshing agy knowledge is the job of the **agy-autotrain**
  learning loop — `agy-learn` captures an observation the moment it is made, `agy-curate` folds the inbox
  into the shipped header. See [`../agy-autotrain/README.md`](../agy-autotrain/README.md).

See also its companion [`clavity-dotnet/plugin/knowledge/agy-assumptions.md`](../clavity-dotnet/plugin/knowledge/agy-assumptions.md)
(every load-bearing agy behavior clavity depends on, and how to re-verify it), routed from
[`agy-assumptions.md`](agy-assumptions.md). The evidence trail behind the profile is
[`agy-capabilities-research.md`](agy-capabilities-research.md).
