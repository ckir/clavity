# Verification harness — runbook

Test-drives the Empirical Assumptions in `assertions.md` against the LIVE agy. No binary: each probe is
a real `clavity ask` (or send+`await-reply`) plus an outcome check. Run before promoting an assumption
(invoked by `agy-curate`) and after any `agy --version` bump.

## Preflight

1. `clavity doctor` — agy session reachable, daemon healthy.
2. `clavity ping` — expect `READY` (bus round-trip works).
3. Note `agy --version` (stamp it on every result).

## Per-probe procedure

For each row in `assertions.md`:

1. **Set up** any throwaway target the probe needs (a scratch file in agy's cwd; capture
   `git status`/reflog as the "before").
2. **Fire** the synthetic payload via `clavity ask "<probe>"` (or async send + `clavity await-reply`).
   Latency is minute-scale — prefer async; recover the reply from the bus if a sync call times out.
3. **Observe** the signal named in the row (reply text, `git status`, `threadId`, reflog).
4. **Record** PASS/FAIL + the agy version + date in the row's "Last run". Never record a pass you did
   not physically observe.
5. **Tear down** the throwaway target.

## Outcome

- All relevant probes PASS → the assumption may be promoted/kept; refresh its "verified against" stamp.
- Any FAIL → drift: hand the item back to `agy-curate` (return to inbox, fix the claim + probe).

## Notes

- Run probes that place/cancel orders or mutate state ONLY against throwaway targets.
- Backend overload / quota lockout / daemon flap can abort a probe with no reply — that is an
  environment condition, not a FAIL; retry when healthy.
