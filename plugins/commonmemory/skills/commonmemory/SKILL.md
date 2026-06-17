---
name: commonmemory
description: Use to share context, decisions, gotchas, and handoffs between Claude and agy via the shared agentmemory store — tag [common] notes and proactively recall them.
---

# commonmemory — shared cross-agent memory

Claude and agy both connect to the **same agentmemory store**, so a memory saved by one is
recallable by the other (no wiring needed). This skill is the **convention** that makes that shared
store useful on purpose: tag cross-agent notes, and proactively recall them.

## Recall FIRST (before acting)
At the start of a task — and whenever picking up handed-off work — search the shared store for the
other agent's notes BEFORE doing anything:
```
memory_smart_search query="[common] <repo>"
```
(`<repo>` = this repository's name, e.g. `clavity`.) Read what the other agent left. **Mind
staleness:** agentmemory is append-mostly, so superseded notes linger — prefer the most recent note
(check its timestamp), trust its `Status:`, and don't act on an old handoff.

## Save a [common] note when the OTHER agent should know
Use `memory_save` with `concepts` including `common` + the repo name, and `content` in this form:
```
[common] (<repo>) — <what> · Why: <why> · Status: <done | in-progress | blocked> · Next: <next step / for whom>
```
Save one when you have:
- **Handoff state** — what you just did and what's next (for the other agent).
- **A shared decision / architecture choice** both agents must respect.
- **A codebase gotcha** — a non-obvious trap the other agent would otherwise re-hit.
- **A fixed bug** — root cause + fix, so it isn't re-diagnosed.

## Guardrails
- Tag `[common]` ONLY for genuinely cross-agent-relevant notes — over-tagging dilutes the shared pool.
- Don't duplicate what the code/git already records; capture the **non-obvious**.
- Keep notes current; supersede a stale handoff by saving a new note with an updated `Status:`.

## Example
```
memory_save(
  concepts="common, clavity, escape-time",
  content="[common] (clavity) — psmux escape-time default 500ms is the keyboard-lock cause; set 10. · Why: a bare Esc is held ~500ms. · Status: done · Next: rebuild the v1 binary so clavity start sets it."
)
```
