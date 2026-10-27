# Backlog stub - a fresh install injects SEED only; the knowledge store is never projected into GROWTH

**Status:** IMPLEMENTED 2026-10-27 - on branch `feat/project-store-growth`: the silence is ended by a SessionStart warning and the projection by a helper that proposes through the agy-curate human gate; install-time seeding is NOT built (ruled out, below); flips to SHIPPED when that branch is merged

> **Previous status:** OPEN 2026-10-11 - Raised while regenerating the runtime GROWTH on a new development machine.
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

## Decision (owner, 2026-10-27; AGY-FIRST consult, agy and the driver agreed)

Option 1 of the sketch (project on install, never overwrite) is NOT built; option 2 (warn) is, and it gets the action it points at. Reasons: after the sidecar fix GROWTH has exactly one sanctioned writer, `curate-commit` after the agy-curate human gate, so an installer seeding a GROWTH file would either be refused by the readers or write its own sidecar and bypass that gate; the store's INDEX says GROWTH is a bounded SELECTED projection, which is a judgement (the combined header already uses 16 339 of 32 768 bytes with 18 rules); the Windows installer data cannot be compiled on the Linux box that builds this; and the drivers should not carry another plugin's content. Built, all in the `agy-autotrain` plugin, bash only, no reader or installer change:

- `agy-autotrain/skills/agy-curate/project-store.sh` compiles the store in INDEX order into a GROWTH PROPOSAL on stdout and never writes. MEASURED against the real store: its output is byte-identical (11 221 B, `diff` empty) to the hand projection of 2026-10-11. Gates: ASCII only (exit 3), the combined SEED + GROWTH header within the 32 768-byte reader cap, counted as the reader joins them (exit 4), INDEX/rule Section agreement (exit 6), a missing file (exit 2), nothing to project (exit 5).
- `agy-curate/SKILL.md` has a "Project the knowledge store" step: run the helper, treat its output as the run's GROWTH proposal, show it at the human gate, publish only the approved bytes through `curate-commit`.
- `agy-curate-nudge.sh` (SessionStart) says "golden-header: SEED only - the knowledge store has N rules that this machine does not inject" when the plugin has a store with rules and the machine has NEITHER a GROWTH file (an empty one counts) NOR the legacy flat file, naming that step; it rides in the same message as the inbox nudge, honours `CLAVITY_GOLDEN_HEADER`, the 7-day snooze and `.no-agy`, and is checked before the inbox gates that exit early.

**Not built, stated so nobody assumes it:** a fresh install still starts on SEED alone until someone runs the step; the warning ends the silence, not the wait. The adjacent `curate-commit --help` empty-write quirk is a separate stub.

**Reopen if:** a machine is found running on SEED alone with a store present and no warning (check `CLAUDE_PLUGIN_ROOT` reaches the hook), or the owner wants installs to seed GROWTH after all (then it must go through `curate-commit`, not around it).
