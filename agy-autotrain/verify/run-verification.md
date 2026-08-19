# Verification harness - runbook

Test-drives the Empirical Assumptions in `assertions.md` against the LIVE agy. No binary: each probe is
a real synchronous ask plus an outcome check - see the appendix for how to issue one on your driver. Run
before promoting an assumption (invoked by `agy-curate`) and after any `agy --version` bump.

To DESIGN a new probe - especially a paired (A/B) one - see [`probe-design.md`](probe-design.md); this
runbook covers EXECUTING a probe that already exists.

## Preflight

The harness needs three capabilities. How you get them depends on which driver is installed - the two
are mutually exclusive, so a machine has one. See the appendix for the invocations.

1. **Liveness** - confirm the peer is reachable and idle before firing. Do not fire while it is busy.
2. **Synchronous ask** - send a probe payload and get the reply.
3. **Version** - note `agy --version`; stamp it on every result.

## Per-probe procedure

For each row in `assertions.md`:

1. **Set up** any throwaway target the probe needs (a scratch file in agy's cwd; capture
   `git status`/reflog as the "before").
2. **Fire** the synthetic payload using your driver's synchronous ask (see the appendix). Keep the payload
   focused and bounded - deep or bundled asks can run to minute scale. On a driver with an async path,
   prefer send + await-reply and recover the reply from the bus if a sync call times out.
3. **Observe** the signal named in the row (reply text, `git status`, `threadId`, reflog).
4. **Record** the outcome in the row: the evidence in the narrative "Last run" cell, AND the status cell for
   the driver you actually ran under (`dotnet` or `classic`) - `PASS <ver>` * `FAIL <ver>` * `PARTIAL <ver>` *
   `ACKED <ver>` * `N/A`. Never record a pass you did not physically observe, and never set the OTHER
   driver's column by inference - a probe you did not run there stays `PARTIAL`.
5. **Tear down** the throwaway target.

## Outcome

- All relevant probes PASS -> the assumption may be promoted/kept; refresh its "verified against" stamp.
- Any FAIL -> drift: hand the item back to `agy-curate` (return to inbox, fix the claim + probe).

## Automated re-run reminder (status-gated)

A committed SessionStart hook - `.claude/hooks/agy-verify-reminder.sh`, wired via `.claude/settings.json` -
reads the per-driver status columns in `assertions.md` and reminds you whenever the suite is not in a
resolved, current state. `FAIL` and `PARTIAL` nag **regardless of the recorded version**, so re-stamping
cannot silence an unresolved probe. `PASS` and `ACKED` nag only once their stamped version falls behind the
live `agy --version`. `N/A` is always silent. Anything the gate cannot read - a blank or unrecognised status
cell, no parsed rows, a missing `awk` - nags as well, because a gate that goes quiet while it cannot see is
exactly the defect this design removes. Completing a pass therefore means **setting the status cell**, not
merely bumping a version. (First session after adding it, Claude Code asks you to approve the new project
hook command - one-time.)

## Notes

- Run probes that place/cancel orders or mutate state ONLY against throwaway targets.
- Backend overload / quota lockout / daemon flap can abort a probe with no reply - that is an
  environment condition, not a FAIL; retry when healthy.

## Appendix - per-driver invocations

| Capability | clavity-classic | clavity-dotnet |
|---|---|---|
| liveness / reachability | `clavity doctor`, `clavity ping` | `agy_status` (MCP tool) |
| synchronous ask | `clavity ask "<payload>"` | `agy_ask` (MCP tool) |
| async send + read reply | send + `clavity await-reply` | n/a - `agy_ask` is synchronous |

The driver ids in this table (`dotnet`, `classic`) are the same ids naming the status columns in
`assertions.md` and detected by `.claude/hooks/agy-verify-reminder.sh`. Keep the three in step.
