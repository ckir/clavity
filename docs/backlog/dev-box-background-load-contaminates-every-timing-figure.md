# Backlog stub — an unidentifiable process holds a full core, contaminating every timing figure

**Status:** 🔴 **OPEN — needs an OWNER action, not a code change.** Verified by measurement 2026-08-25.
**Raised:** during the subagent-timing probe. Promoted from `.clavity/local-anomalies.md`.

## The fact

`UninstallMonitor.exe` (PID 11228, started **2026-08-20 15:58**) consumes **~99% of one core
continuously** on this 4-core box. Measured twice by CPU-delta over wall-clock windows:

- 18,4s over 20s (**92% of a core**) with other load present
- 29,8s over 30s (**99% of a core**) with the machine otherwise quiet

Cumulative **147.768 CPU-seconds ≈ 41 core-hours**. Its `ExecutablePath`, `CommandLine`, `Company` and
parent lookup all return EMPTY — a normal-integrity query cannot identify it, and a `fd` sweep of
`Program Files` / `ProgramData` / `LOCALAPPDATA` timed out without locating it.

## Why it is tracked rather than ignored

It is a permanent **25% capacity loss** on the machine every timing figure in `scripts/tests/_partition.md`
is measured against, including the 493-550s committed in `a1ad1d1`. It does not invalidate those figures —
they are honest measurements of "this recipe on this machine" — but it does mean:

- no figure here is comparable to one from another machine;
- the fast half's 92%-of-cap reading would have real headroom on a box without it.

The measurement discipline in `~/.claude/CLAUDE.md` now requires stating that background load was
uncontrolled, precisely because of this.

## What the owner needs to decide

Identify it (an elevated process explorer / Autoruns will show the path a normal query cannot), then keep
or kill it. If it is killed, the fast half is worth re-measuring — the cap-adjacency conclusion may not
survive it.

## Related

`docs/coverage-debt.md` and the `## Measured runtimes` note in `scripts/tests/_partition.md` record the
never-idle floor, including the measurement hole where `Get-Process` reads the antivirus at 0,00
CPU-seconds while a perf counter reads it at 3,88-5,43% of a core.


## Update 2026-08-31 - it RESTARTS, so the recorded identity above is stale

Re-measured during AGY-TEST-AUDIT. The process above was recorded as **PID 11228, started 2026-08-20**.
It is now **PID 3976, started 2026-08-30 18:03**, at **37.033 CPU-seconds** (about 10 core-hours in this
run alone).

That is the new fact and it changes the disposition: this is **not one long-lived process to identify and
kill once** - it respawns. A one-time kill buys days at most, so "keep or kill it" is not the whole
decision; whatever spawns it has to be found.

## A second contaminant, observed and resolved 2026-08-31

An orphaned `find / -maxdepth 6 -iname rmcp-3.1* -type d` (PID 4628, started 04:11) had burned
**10.822 CPU-seconds over 3,7 hours** holding a full core. It was left behind by an earlier agent
session searching for a Rust crate directory; nothing would ever have reaped it. The owner authorised
killing it and it is gone.

Recorded because the CLASS matters even though this instance is closed: **an agent session can strand a
filesystem-root scan that outlives it and silently taxes every later measurement.** Nothing enumerates or
reaps these, and they are invisible unless someone censuses the process list - which is why the timing
discipline requires that census before any figure is quoted.

Measured effect on this repository's own gate, same suite, same commit: **1593s under the two-holder
load, 457s once one holder was killed.**
