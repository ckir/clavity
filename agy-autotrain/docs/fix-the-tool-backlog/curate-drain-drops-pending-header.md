---
slug: curate-drain-drops-pending-header
variant: both
observed: 2026-10-26
source-inbox-entry: "- [tool] agy-curate's drain rewrote ~/.clavity/agy-observations.md WITHOUT the `## Pending` header"
last-triaged: 2026-10-26   # oracle: after a drain, `rg -n '^## Pending' ~/.clavity/agy-observations.md` prints a line
status: CLOSED-BY-RULING
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

## Ruling (owner, 2026-10-27)

CLOSED-BY-RULING: not reproducible from the code. MEASURED 2026-10-27 on the real pre-drain file of the incident (`~/.clavity/agy-observations.md.20261026-161022.bak`, 11 pending lines, `## Pending` present): `Get-PendingBody` then `Set-PendingBody -Body @()` from `scripts/drain-lib.ps1` (the one implementation of the reset; no C# or Rust code touches the inbox) leaves exactly one `## Pending` line at line 9. `Set-PendingBody` keeps an existing heading (`drain-lib.ps1:87-91`) and adds one when it is absent (`:108-111`); `drain-lib.Tests.ps1` pins both. The code-level mitigation above would therefore change a function that is not the cause. The loss on 2026-10-26 is unexplained: the likeliest causes are an agent following `agy-curate` SKILL.md prose by hand instead of running `curate-commit`, or a hand repair; neither leaves evidence. Not changed: `agy-learn` still creates the heading only when the FILE is missing, so a header lost by any other route orphans later captures until the next drain re-creates it.

**Reopen if:** the heading is found missing again after a `curate-commit` run (keep the post-drain file and its `.bak` and run the same two calls on them), or the nudge reports 0 pending while bullets are present.
