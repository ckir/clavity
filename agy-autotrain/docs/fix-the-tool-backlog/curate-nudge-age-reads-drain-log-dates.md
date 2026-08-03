---
slug: curate-nudge-age-reads-drain-log-dates
variant: both
observed: 2026-08-03
source-inbox-entry: "(found during the 2026-08-03 drain, not from an inbox bullet)"
status: open
---

# The agy-curate age nudge reads dates out of drain-log COMMENTS, so it can never be satisfied

## Steps to Reproduce
1. Drain the inbox so `## Pending` holds only recent entries (2026-08-03 here).
2. Leave the historical drain-log HTML comments in place -- they are append-only and permanent.
3. Start a session.

Observed: `agy-curate nudge: the observations inbox's oldest pending entry (2026-06-20) is over
30 days old (only 2 entries, under the count threshold)`. Measured: `2026-06-20` occurs exactly
once in the file, at line 73, inside `<!-- Drain log 2026-06-20 (agy 1.0.10):`. No pending
bullet carries it; both real bullets are dated 2026-08-03.

Two compounding causes in `hooks/agy-curate-nudge.sh`:
- The region gate is `/^## Pending/{p=1} /^## /{p=0}`, but nothing after `## Pending` ever starts
  with `## ` -- the section is followed only by HTML comments -- so `p` stays 1 to EOF.
- Within that region the COUNT is anchored to bullets (`p && /^- \[/{c++}`, line 27) but the DATE
  scan is not (`p && match($0,/[0-9]{4}-.../)`, line 28). Hence count=2 (right) and
  oldest=2026-06-20 (wrong).

Because drain-log comments accumulate and are never removed, the age nudge is permanently latched
ON: draining the inbox cannot clear it, and only the 7-day snooze marker suppresses it. A nudge
that cannot be satisfied by doing the work it asks for trains the operator to ignore nudges.

## Code-level Mitigation
Anchor the date scan to pending bullets, exactly as the count on the line above already is:

    oldest="$(awk '/^## Pending/{p=1;next} /^## /{p=0} p && /^- \[/ && match($0,/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/){d=substr($0,RSTART,10); if(m==""||d<m)m=d} END{print m}' "$OBS" 2>/dev/null)"

Adding `/^- \[/ &&` fixes it on its own, independently of the region gate, since comment lines
never start with `- [`. Optionally also close the region on the first `<!--` for defence in depth.

## Notes
There is currently NO test file for `agy-curate-nudge.sh` in `scripts/tests/` -- the count path and
the age path are both untested, which is why an asymmetry between two adjacent lines survived. The
regression test should pin the ASYMMETRY directly: an inbox whose only old date lives in a drain-log
comment must produce NO age nudge. Applies to both drivers: the hook ships in agy-autotrain, which
is driver-agnostic.
