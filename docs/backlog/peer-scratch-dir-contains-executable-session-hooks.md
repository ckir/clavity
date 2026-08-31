# Backlog stub - the scratch directory handed to the peer contains code this machine executes

**Status:** OPEN. Promoted 2026-08-31 from `.clavity/local-anomalies.md`.
**Raised:** 2026-08-30, during agy-capstone round 3 on the review-only envelope.
**Re-verified 2026-08-31** during AGY-TEST-AUDIT: still true, all three files present.

## The fact

Three executable scripts under `.clavity/scratch/discipline-efficacy/` are wired as **live
SessionStart / SessionEnd hooks**:

| file | mode | wired at |
|------|------|----------|
| `.clavity/scratch/discipline-efficacy/abs-probe.sh`          | 755 | `.claude/settings.local.json:25` |
| `.clavity/scratch/discipline-efficacy/env-probe.sh`          | 755 | `.claude/settings.local.json:30` |
| `.clavity/scratch/discipline-efficacy/sessionstart-probe.sh` | 755 | `.claude/settings.local.json:41` |

`.clavity/scratch/` is the directory **every review-only envelope explicitly hands to the agy peer as
its sanctioned write area**. So the one place the peer is told it may write is also a place this machine
runs code from, every session.

## Why it is tracked rather than ignored

This is the concrete substance behind an owner-scoped question the capstone left open: *is monitoring
`seams/` theatre while `scratch/` stays an unmonitored write zone?* The consult guard's census records
`scratch` **as a name only** and never its contents, deliberately - hashing it would turn every
sanctioned peer write into a false breach report, and false alarms are what teach an operator to ignore
a guard.

That trade-off was reasonable when `scratch/` held only notes. It is a different trade-off now that
`.claude/settings.local.json` executes three files from inside it.

**MEASURED 2026-08-31, not hypothetical:** during the AGY-TEST-AUDIT round the peer wrote **654 files /
12 MB** into `.clavity/scratch/` and the guard's 8-axis fingerprint did not move **at all** - before and
after were byte-identical. The write zone is genuinely unmonitored, and it is genuinely a code-execution
surface. Neither half is speculation.

Note this was also the finding I twice refuted before measuring it, on a grep that only covered the
plugin directories. The wider grep is what found the three wired hooks.

## The fix when it is scheduled - options, not a decision

1. **Un-wire the probes.** They are leftovers from a discipline-efficacy experiment; if they are done,
   deleting the three `settings.local.json` entries closes the surface with no design change at all.
   Cheapest, and probably correct.
2. **Move executable probes out of `scratch/`** into a directory the census covers, keeping `scratch/`
   for inert peer output only. Preserves the no-false-alarm property.
3. **Census `scratch/` for the executable bit only** - record mode, not content. A new `755` file under
   the peer's write zone becomes visible without any sanctioned note-writing tripping the guard.

Option 3 is the only one that stays correct if a future session wires something from `scratch/` again,
so it is worth considering even alongside option 1.
