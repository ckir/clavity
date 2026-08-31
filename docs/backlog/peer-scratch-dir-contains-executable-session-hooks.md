# Backlog stub - the scratch directory handed to the peer contains code this machine executes

**Status:** PARTIALLY CLOSED 2026-08-31 - the three hooks are un-wired (owner instruction). The
remaining scope is the durable question in `## What is still open`, not the original exposure.
Promoted 2026-08-31 from `.clavity/local-anomalies.md`.
**Raised:** 2026-08-30, during agy-capstone round 3 on the review-only envelope.
**Re-verified 2026-08-31** during AGY-TEST-AUDIT: still true then, all three files present.
**Un-wired later the same day** - see the update at the foot of this file.

## The fact, AS FOUND on 2026-08-30 (the wiring was removed on 2026-08-31 - see the update below)

Three executable scripts under `.clavity/scratch/discipline-efficacy/` were wired as **live
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


## Update 2026-08-31 - option 1 taken, exposure closed

The owner instructed un-wiring. The entire `hooks` block was removed from
`.claude/settings.local.json` - it contained nothing but these three probes, so no empty scaffolding was
left behind. VERIFIED by parsing both versions and diffing the decoded objects: `hooks` is the ONLY key
that changed; `env`, `permissions` and `enabledPlugins` are value-identical. A backup of the previous
file was taken first. No hook anywhere is now wired from `.clavity/`.

**The code is still there, it is merely no longer invoked.** Six mode-755 scripts remain in the peer's
sanctioned write zone:

    abs-probe.sh   env-probe.sh   probe-hotreload.sh
    probe12-sessionend.sh   probe7-concurrent-append.sh   sessionstart-probe.sh

Only three of those six were ever wired. That ratio is the reason this item is not closed outright:
executable files accumulate in `scratch/` as a by-product of ordinary probe work, and the wiring is a
separate, easily-repeated act.

## What is still open

The durable question, unchanged by the un-wiring: **`.clavity/scratch/` is a directory the peer is
explicitly invited to write to, and the consult guard records it by NAME ONLY.** Un-wiring removed
today's exposure; it did not make the write zone monitored, and nothing prevents a future session from
wiring something from there again.

Option 3 above - censusing the **executable bit** rather than content - remains the only proposal that
keeps this correct without reintroducing false alarms on sanctioned peer writes. Worth scheduling on its
own merits.
