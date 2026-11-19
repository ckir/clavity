# Backlog stub - a Monitor running `tail -F` on files that did not exist yet delivered no events (reported, unverified)

**Status:** OPEN 2026-11-19 - promoted from `.clavity/local-anomalies.md`; reported by a subagent, not reproduced

**Raised:** 2026-11-18, section 113 test audit (reported by the audit agent).
**Scope:** the Monitor tool used from an agent session; not repository code.

## The claim

A Monitor started on `tail -F` of files that did not exist at start delivered no events for 30 minutes, even
after the files appeared.

## Status of the evidence

Reported, unverified. Nobody has reproduced it. A reproduction needs a Monitor on `tail -F` of a path that is
created after the Monitor starts, then lines appended to it, and a check that events arrive.

**Reopen if:** not applicable while OPEN. If a reproduction shows the claim false, close this stub as KILLED
with the measurement; if it holds, it is a harness defect to report upstream and to record as a workaround
(start the Monitor after the file exists).
