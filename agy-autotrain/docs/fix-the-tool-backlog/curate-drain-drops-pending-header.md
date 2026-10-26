---
slug: curate-drain-drops-pending-header
variant: both
observed: 2026-10-26
source-inbox-entry: "- [tool] agy-curate's drain rewrote ~/.clavity/agy-observations.md WITHOUT the `## Pending` header"
last-triaged: 2026-10-26   # oracle: after a drain, `rg -n '^## Pending' ~/.clavity/agy-observations.md` prints a line
status: OPEN
---

# The curate drain rewrites the inbox without its `## Pending` header, orphaning every later capture

## Steps to Reproduce
Run an `agy-curate` drain on an inbox that holds pending bullets (observed on the 2026-10-26 16:10:22 drain; the
`.bak` beside the inbox holds the pre-drain layout WITH the header). Afterwards the inbox is the header prose
followed directly by bullets: `rg -n '^## Pending' ~/.clavity/agy-observations.md` prints nothing. `agy-learn`
appends below that (it creates the header only when the FILE is missing), and `drain-lib.ps1`
`Get-PendingRegionLines` and `hooks/agy-curate-nudge.sh` open the region only on `^##\s+Pending\s*$`
(`agy-curate-nudge.sh:73`, `:90`), so the nudge counted 0 while 2 bullets were present and the next drain would
collect nothing.

## Code-level Mitigation
The drain's rewrite must emit the `## Pending` heading (followed by a blank line) even when the region it writes
back is empty, and `agy-learn`'s create-if-missing should also check for the HEADING, not only the file, before
appending (restore it when absent). Add a probe to `verify/assertions.md`: after a drain, the heading exists.

## Notes
Hand-repaired on the observing box by inserting the heading before the first bullet (backup
`agy-observations.md.pre-pending-repair.bak`). The capture skill forbids read-then-rewrite of the inbox, so
agents cannot self-heal this without a rule change; the fix belongs in the drain.
