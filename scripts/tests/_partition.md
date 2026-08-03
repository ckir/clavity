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

- `just test-scripts-fast` — the agent inner-loop gate. **15 suites, 177 tests, measured 124,6s**
  (2026-08-03, ONE sample at THIS configuration — see the two-sample rule below; the count is
  deterministic, the time is not). The immediately preceding sample, 150,6s, was 14 suites / 175 tests,
  so the two are NOT two samples of the same thing and must not be averaged or compared.
- `just test-scripts-slow` — everything else. **13 suites, 238 tests, measured 653,5s** (2026-08-03,
  ONE sample). NOT on any git hook; it **exceeded the 600s foreground tool cap on that very run** and
  must be BACKGROUNDED by an agent, blocked on by reading its own `Tests completed` line — never by
  watching a process count.
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
test raises it. The count today is fast **177** and slow **238**, **both measured, not added up**. It is a
fact, not a contract, and it was 358 / 363 / 368 / 372 earlier.

Fast was re-measured five times on 2026-08-03, every time by running the recipe: **166 / 143,9s** when
`agy-curate-nudge.Tests.ps1` was added at 4 tests, **169 / 145,3s** after capstone round 1 added 3 more,
then **171 / 132,3s** after capstone round 2 added 2 more, and **173 passed / 0 failed in 145,9s**
after capstone round 3 added 2 more. A fifth run, after the cost-clause work added 2 tests to
`agy-after-reminder`, measured **175 passed / 0 failed in 150,6s**. A sixth, after
`plugin-hooks-payload.Tests.ps1` was added as a NEW 15th fast suite at 2 tests, measured
**177 passed / 0 failed in 124,6s** — note the run got FASTER while gaining a suite, which is the
run-order/cold-start effect this file warns about, not a speed-up.

Slow WAS re-measured on 2026-08-03, at the same time, as the sole command on the machine:
**238 passed / 0 failed in 653,5s**. Note what that number exposes — the previously recorded slow
count was **210**, and the cost-clause work added only 6 tests to that half. The other ~22 arrived
from intervening epics that never re-measured this half. **A count in this file decays silently
whenever a suite in the OTHER half is edited; treat any figure here as stale until you re-run the
recipe.** Do not reconcile a surprise like that by arithmetic — the measurement is the fact.

If you move a file between halves, re-measure BOTH halves and update this file; do not edit it from
memory, and do not compute the new number by subtraction (see above).

**THE SUITE COUNT IS A COUNT TOO — and it decayed silently for longer than the test count did.** On
2026-08-03 this file claimed 13 fast and 12 slow suites while the recipes actually listed 15 and 13.
It went wrong the way the rest of this file warns about: someone adding a suite **incremented the
printed number instead of counting the recipe**, and the error then survived every later edit because
each subsequent editor incremented the already-wrong figure in turn. Do not add one. Count:

```bash
for r in fast slow; do
  printf '%s %s\n' "$r" "$(sed -n "/^test-scripts-$r:/,/^$/p" justfile \
    | grep -oE 'scripts/tests/[A-Za-z0-9._-]+\.Tests\.ps1' | sort -u | wc -l)"
done
```

The `## Measured runtimes` table below is also NOT self-maintaining: `agy-inbox-snapshot.Tests.ps1`
was in `test-scripts-slow` and absent from the table entirely. To find that class of omission,
diff the recipe membership against the table rather than reading down it.

## Measured runtimes

These are per-file numbers taken in one sweep and are INDICATIVE ONLY — the section above explains why a
per-file time is not a stable quantity and is not used as the partition rule. `agy-consult-guard` was
measured separately (2026-08-02) in isolation, as the sole command on a quiet machine.

```
abort-drain.Tests.ps1                           261,3s   13 tests
agy-consult-guard.Tests.ps1                      78,4s    8 tests   <- SLOW, moved 2026-08-02; count 2026-08-03
accept-drain.Tests.ps1                           51,2s   10 tests
agy-after-reminder.Tests.ps1                      8,8s   10 tests   <- count 2026-08-03, time older
agy-anomaly-reminder.Tests.ps1                   21,4s   16 tests
agy-curate-nudge.Tests.ps1                       29,2s   11 tests   <- FAST, added 2026-08-03
agy-inbox-snapshot.Tests.ps1                    100,4s   22 tests   <- SLOW; was MISSING from this
                                                                      table entirely until 2026-08-03
agy-liveness-check.Tests.ps1                     40,9s   27 tests
agy-seam-inject.Tests.ps1                        18,0s   19 tests   <- count 2026-08-03, time older
agy-test-audit-reminder.Tests.ps1                32,5s   14 tests   <- count 2026-08-03, time older
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
plugin-hooks-payload.Tests.ps1                    2,2s    2 tests   <- FAST, added 2026-08-03
register-plugin.Tests.ps1                        18,6s   18 tests
release-lib.Tests.ps1                            14,3s   23 tests
```
