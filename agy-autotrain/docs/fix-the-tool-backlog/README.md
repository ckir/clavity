# Fix-the-tool backlog

Deterministic bridge/tool quirks that `agy-curate`'s triage gate (spec §5.C-A) refused to promote into
knowledge because they are **software defects fixable in a driver's execution path** — not durable peer
psychology. Each is one file, `<slug>.md`, created from [`_template.md`](./_template.md).

**Rules**
- **One file per entry** (append-only). Never a single shared file — offline curate runs on different
  branches would merge-conflict.
- An entry belongs here ONLY if its `Code-level Mitigation` block names a concrete change to a bridge/tool
  execution path. If the only mitigation is a *driving move*, it is a driver-cheatsheet rule, not a
  backlog item.
- **Per-variant:** a quirk may be `fix-the-tool` on one variant and a carried driver-cheatsheet rule on
  another. State which variant(s) the mitigation applies to.
- Committing the file IS the routing. Automated ingest into an issue tracker is a phase-2 hardening.
- Emitting a backlog item does NOT strip the carried cheatsheet rule — retirement is conservative + manual
  (spec §5.C-D).
