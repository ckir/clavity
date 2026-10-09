# Backlog stub - `agy_status` reports `working` for a peer that is idle at its prompt

**Status:** CLOSED-BY-RULING 2026-10-09 - closed by ruling at the start of Branch C, see Reopen if below
> **Legacy status (verbatim, before the 2026-10-08 normalisation):** OPEN. Promoted 2026-08-31 from `.clavity/local-anomalies.md`. · ▶ **SCHEDULED [sweep-step0 2026-09-29]: ROADMAP sweep Branch 4 (Branch 5 if re-measurement puts the cause in AgyView)**

**Ruling 2026-10-09 (owner delegated, AGY-FIRST aligned):** the state does not come from the last step kind, so the proposed fix has nothing to change. `agy_status` asks the LS (`LsClient.ProbeIdleAsync`, 300 ms deadline, `AgyView.ProbeDeadlineMs`) and `AskReply.cs:21-23` records the measured cause of a long `working` with an unchanged step count: background tasks (shell commands that never exited) keep the peer working until they end. The 2026-08-30 observation was not re-measured against that cause and has not recurred in the later sessions that polled the status.

**Reopen if:** two `agy_status` polls minutes apart report `working` with an unchanged `TotalSteps` while the agy tab is at its prompt AND agy's task list shows no running background task - then capture the probe timing (the 300 ms clamp returns `working`) before changing either side.

**Raised:** 2026-08-30, during an AGY-FIRST consult before proposing sequencing approaches.

## The fact

Two `agy_status` polls minutes apart both returned `State=working` with an **unchanged
`TotalSteps=4863`**. A working peer advances its step count, so an unchanging count with a `working`
state is self-contradicting.

Cross-checked by a direct `flaui` read of the agy terminal tab: the CLI was **sitting at its input
prompt, having already emitted `[VERDICT: GAPS FOUND]`**. The peer was idle and had been for some time.

The stale value is the previous cascade's final step (`LastStepKind=15`), never resolved to `idle`.

## Why it is tracked rather than ignored

**Every review discipline opens with a precheck-idle gate** - agy-first, agy-capstone, agy-test-audit and
adversarial-panel-review all say "do not fire while the peer is busy". A permanently-`working` status
blocks that gate, and the two available responses are both bad: wait forever, or learn to ignore the
gate. The second is what actually happens, and it defeats the check for the cases where the peer really
is busy.

It is intermittent - `agy_status` answered correctly throughout the 2026-08-31 AGY-TEST-AUDIT session -
so it cannot be relied on to reproduce on demand.

## Related, and NOT the same defect

`docs/backlog/ls-discovery-misreports-a-busy-peer-as-exited.md` is the **inverse**: that one reports a
busy peer as gone. This one reports an idle peer as busy. A fix for either should be checked against the
other, because a naive change to the state resolution can trade one for the other.

## The fix when it is scheduled

Resolve the terminal step kind to `idle` rather than carrying the last cascade's final step forward.
A cheap interim mitigation available to the driver today: treat an **unchanged `TotalSteps` across two
polls** as evidence of idleness regardless of the reported state, which is exactly the inference that
identified this in the first place.
