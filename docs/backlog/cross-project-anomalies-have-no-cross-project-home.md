# Backlog stub — the anomaly channel is repo-local, so a CROSS-PROJECT finding is invisible everywhere else

**Status:** 🔴 **OPEN.** Promoted from `.clavity/local-anomalies.md` at the 2026-08-25 triage.
**Raised:** 2026-08-19, alongside the dependency-pin captures that demonstrate it.

## The defect

`.clavity/local-anomalies.md` is **repo-local and gitignored** by design — that privacy is deliberate and
should not change. But it is the ONLY capture channel, so an anomaly that is not about this repo has
nowhere correct to live. It gets written into whichever repo the agent happened to be working in, and is
invisible from every other repo it applies to. The SessionStart hook that surfaces the count only reads
the current repo's file, so nothing ever resurfaces it elsewhere.

## It is not hypothetical, and this stub is itself an instance

The dependency-pin cluster (`dependency-pins-are-never-re-resolved.md`) is confirmed by the owner as
cross-project — *"it happens to other projects as well"* — and at this triage it was promoted into
**clavity's own `docs/backlog/`**, because that is the only tracked home that exists. A reader in another
repo will never see it. The triage that promoted it reproduced the defect it was promoting.

## What changed recently, and what it does not solve

`~/.claude/CLAUDE.md` now carries genuinely cross-project disciplines (the timing-measurement protocol was
promoted there on 2026-08-25). That proves a machine-wide channel EXISTS for *rules*. It is not a home for
*open findings*: it is instructions loaded into every session, not a triage queue, and filling it with
untriaged defects would tax every prompt in every project.

## The fix direction

A machine-wide anomalies file beside the global instructions (e.g. `~/.claude/local-anomalies.md`) that
the SessionStart hook reads IN ADDITION to the repo-local one, with capture choosing between them on a
single question: is this about THIS repo, or about the toolchain/workflow generally? Both stay gitignored
or outside any repo, so the privacy property is preserved.

⚠ **Do not solve it by committing the repo-local file.** The gitignore is what makes capture safe to do
without review; publishing untriaged findings is the thing it exists to prevent.
