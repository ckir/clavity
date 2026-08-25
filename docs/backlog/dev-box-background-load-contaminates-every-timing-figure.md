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
