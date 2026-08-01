# Test suite partition

`just test-scripts` ran 358 tests in a single Pester invocation, measured at 917s, 650s, 586s and 590s on
four consecutive runs against a 600s foreground tool cap. It STRADDLED the cap: it worked until it did not.

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

- `just test-scripts-fast` — the agent inner-loop gate. **157 tests, measured 74-94s.** Ceiling: 120s.
- `just test-scripts-slow` — everything else. **201 tests, ~670s.** NOT on any git hook; it exceeds the
  600s foreground tool cap and must be BACKGROUNDED by an agent.
- `just test-scripts` — both, unchanged in meaning: still every test.

**Neither recipe is wired to `lefthook.yml`, deliberately.** The full suite used to run on pre-push and
was removed because git opens the SSH connection before the hook and the idle time made GitHub hang up
mid-push (`lefthook.yml:11-18`). This split exists to solve the 600s *foreground tool cap* an agent hits,
which is a justfile concern only.

**Every test remains reachable from some recipe. The sum of the two halves is 358.** If you move a file
between halves, re-measure and update the table below; do not edit it from memory.

## Measured runtimes

```
abort-drain.Tests.ps1                           261,3s   13 tests
accept-drain.Tests.ps1                           51,2s   10 tests
agy-after-reminder.Tests.ps1                      8,8s    8 tests
agy-anomaly-reminder.Tests.ps1                   21,4s   16 tests
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
