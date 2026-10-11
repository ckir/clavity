# Backlog stub - a fresh install injects SEED only; the knowledge store is never projected into GROWTH

**Status:** OPEN. Raised 2026-10-11 while regenerating the runtime GROWTH on a new development machine.
**Scope:** the installer / `agy-autotrain` plugin, `GoldenHeader` readers in both variants, the knowledge
store at `agy-autotrain/knowledge/rules/`.

## What happened

A new machine (set up 2026-10-08) ran every `agy_ask` for three days with `~/.clavity/golden-header.seed.md`
alone: no `golden-header.growth.md`, no legacy `golden-header.md`. Both readers treat an absent GROWTH as
legitimate (it is: a docs-only drain publishes nothing), so nothing warned. The 18 rules the autotrain loop
had earned - split into the knowledge store on 2026-08-27 precisely so they would survive outside one
machine's runtime path - were preserved as text and injected nowhere.

The store's own INDEX says GROWTH "is a bounded selected projection of this store", yet no step performs
that projection: the installer seeds SEED only, agy-curate compiles GROWTH from INBOX entries, and
`drain-knowledge.ps1` is dev-only. The projection was done by hand on 2026-10-11 (18 rules verbatim in
INDEX order, 11 221 B; combined 16 339 B of the 32 KiB cap) and published through `curate-commit`.

## Why it matters

The whole return on agy-learn / agy-curate is the injected GROWTH. A machine that lacks it silently gets
the behaviour the loop exists to improve on, and the owner has no signal short of listing `~/.clavity/`.

## Mitigation sketch

1. **Project on install.** Ship a compiled `golden-header.growth.md` built from the store (a deterministic
   script: INDEX order, section headers, ASCII gate, budget gate) and seed it beside the SEED when no GROWTH
   and no legacy file exist. Never overwrite an existing GROWTH - a machine that has drained has more than
   the store.
2. **Or warn.** When the reader finds SEED but no GROWTH and the installed plugin carries a non-empty store,
   warn once per session on stderr ("golden-header: SEED only - the knowledge store has N rules that are not
   injected; run <command> to project them").

Adjacent quirk hit during the manual projection: `clavity-ls curate-commit --help` reads stdin and WROTE an
empty GROWTH (see `agy-autotrain/docs/fix-the-tool-backlog/curate-commit-accepts-empty-stdin.md`).
