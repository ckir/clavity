---
slug: idle-wait-false-modal
variant: both
observed: 2026-06-30
source-inbox-entry: "- [anti-pattern] Bundling an external TOOL-ACTION into a consult reply — asking the peer"
status: open
---

# Bundled tool-action exceeds idle-wait causing false modal

## Steps to Reproduce
fire an `agy_ask`/`clavity ask` whose peer turn bundles a tool-action so it exceeds the fixed idle-wait; observe a false `possible_modal`/modal report while the peer step-count still advances.

## Code-level Mitigation
make the idle-wait budget configurable (env/option) and/or gate the "modal" verdict on a stalled step-count rather than a fixed deadline.

## Notes
The "don't infer a hang from the return alone" driving move is ALSO carried as a cheatsheet rule (per-variant appendix).
