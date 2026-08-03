# Test suite partition

**Why the split exists (the state that forced it, 2026-08-01).** `just test-scripts` then ran 358 tests in
a single Pester invocation, measured at 917s, 650s, 586s and 590s on four consecutive runs against a 600s
foreground tool cap. It STRADDLED the cap: it worked until it did not. Those figures are history — the
current, re-measured numbers are further down.

The split is decided by measuring the RECIPE as one batch, not by thresholding per-file numbers.

**Per-file runtime here is not a stable quantity, so it cannot be a rule.** Measured three times on one
commit and machine, the same suite swings up to 5.9x purely on its position in the run, because whichever
suite executes first absorbs pwsh + Pester cold-start for the whole run: `agy-after-reminder` measured
48.9s first and 8.3s last; `release-lib` measured 25.7s first and 4.8s last. Eight of twelve suites were
stable within 15%; four were not. A ">= 20s means SLOW" rule classifies those four differently depending
only on sort order, so it is not reproducible and is not used.

**Batching is not a saving.** The 13 fast suites as one `Invoke-Pester` process measured 94.2s / 75.1s /
73.7s, against a 65.8s warm per-file sum. One process saves repeated pwsh startup but pays cold module
load once and accumulates across files.

- `just test-scripts-fast` — the agent inner-loop gate. **13 suites, 162 tests, measured 125.6s and
  128.5s** (two consecutive quiet-machine runs, 2026-08-02).
- `just test-scripts-slow` — everything else. **12 suites, 206 tests, measured 503.6s** (2026-08-02).
  NOT on any git hook; it can exceed the 600s foreground tool cap and must be BACKGROUNDED by an agent,
  blocked on by reading its own `Tests completed` line — never by watching a process count.
- `just test-scripts` — both, unchanged in meaning: still every test.

**The runtime target is ~120s, and it is a TARGET, not an enforceable invariant.** Do not gate anything on
it. Day-to-day variance on this machine exceeds the margin it would police: the SAME 162-test fast half
measured ~95s on 2026-08-01 and 125.6-128.5s on 2026-08-02 (a 33% swing on identical code), and the slow
half measured 1192.6s on 2026-08-01 and 469.5s / 503.6s on 2026-08-02 (a factor of 2.5). The dominant
variable is what else the machine is doing, including the driving agent's own tool calls — the same CPU
runs the tests and the agent. Two consequences, both learned the hard way:

1. **Never conclude from one sample.** Take at least two, as the sole command in their message.
2. **Never predict a partition change by SUBTRACTION.** Moving the 78.4s `agy-consult-guard` suite out of
   the fast half was predicted (twice, independently) to land it at ~113s. It measured ~127s. Whichever
   suite runs first absorbs pwsh + Pester cold-start for the whole batch, so removing a suite does not
   remove its share of that cost — it redistributes it. Measure the recipe after the move, every time.

**Neither recipe is wired to `lefthook.yml`, deliberately.** The full suite used to run on pre-push and
was removed because git opens the SSH connection before the hook and the idle time made GitHub hang up
mid-push (`lefthook.yml:11-18`). This split exists to solve the 600s *foreground tool cap* an agent hits,
which is a justfile concern only.

**Every test remains reachable from some recipe. The invariant is STRUCTURAL, not numeric:** every
`*.Tests.ps1` in this directory appears in exactly one of the two halves. The oracle is

```bash
diff <(ls scripts/tests/*.Tests.ps1 | xargs -n1 basename | sort) \
     <(grep -oE "scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1" justfile | xargs -n1 basename | sort -u)
```

which exits 0 when clean and names the orphan when a suite is unreachable. **Do not pin a test COUNT as
the invariant** — 358 was pinned once and was wrong by the next task, because every milestone that adds a
test raises it. The count today is fast **169** and slow 210, **both measured, not added up**. It is a
fact, not a contract, and it was 358 / 363 / 368 / 372 earlier.

Fast was re-measured twice on 2026-08-03, both times by running the recipe: **166 passed / 0 failed in
143,9s** when `agy-curate-nudge.Tests.ps1` was added at 4 tests, then **169 passed / 0 failed in 145,3s**
after the capstone round added 3 more to that file. Slow was NOT re-measured that day, so do not add these
two and publish the sum as a measured total — that is exactly the addition this section forbids.

If you move a file between halves, re-measure BOTH halves and update this file; do not edit it from
memory, and do not compute the new number by subtraction (see above).

## Measured runtimes

These are per-file numbers taken in one sweep and are INDICATIVE ONLY — the section above explains why a
per-file time is not a stable quantity and is not used as the partition rule. `agy-consult-guard` was
measured separately (2026-08-02) in isolation, as the sole command on a quiet machine.

```
abort-drain.Tests.ps1                           261,3s   13 tests
agy-consult-guard.Tests.ps1                      78,4s    5 tests   <- SLOW, moved 2026-08-02
accept-drain.Tests.ps1                           51,2s   10 tests
agy-after-reminder.Tests.ps1                      8,8s    8 tests
agy-anomaly-reminder.Tests.ps1                   21,4s   16 tests
agy-curate-nudge.Tests.ps1                       18,4s    7 tests   <- FAST, added 2026-08-03
agy-liveness-check.Tests.ps1                     40,9s   27 tests
agy-seam-inject.Tests.ps1                        18,0s   13 tests
agy-test-audit-reminder.Tests.ps1                32,5s   13 tests
BashHookHelpers.Tests.ps1                         1,5s    4 tests
check-agy-discipline-skills.Tests.ps1             6,9s   14 tests
check-core-integrity.Tests.ps1                   24,1s    7 tests
check-growth-budget.Tests.ps1                    14,1s    7 tests
check-member-docs.Tests.ps1                       3,0s   35 tests
check-plugin-namespace.Tests.ps1                 25,8s    8 tests
check-roster.Tests.ps1                            5,3s    5 tests
check-seed-artifacts-synced.Tests.ps1             4,1s    2 tests
check-seed-budget.Tests.ps1                       8,2s    4 tests
check-user-facing-docs.Tests.ps1                  3,3s   15 tests
compute-release.Tests.ps1                        22,6s    7 tests
docs-audit.Tests.ps1                            120,6s   80 tests
drain-knowledge.Tests.ps1                        38,2s    7 tests
drain-lib.Tests.ps1                               5,2s   20 tests
generate-scoped-manifest.Tests.ps1                0,7s    2 tests
register-plugin.Tests.ps1                        18,6s   18 tests
release-lib.Tests.ps1                            14,3s   23 tests
```
