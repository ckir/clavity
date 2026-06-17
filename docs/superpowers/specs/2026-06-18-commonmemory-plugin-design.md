# commonmemory — Shared-Memory Conventions Plugin — Design

**Date:** 2026-06-18
**Status:** Approved (design); implementation plan pending.
**Author:** Costas Kirgoussios (with Claude + agy ground-truth review)

---

## 1. Context & purpose

`commonmemory` is the **second plugin** in the clavity suite (after `clavity-classic`). It is a
**skills-only universal dual-plugin** that teaches Claude and agy to use a **common, deliberate
cross-agent memory** — a shared handoff scratchpad + shared project context.

**Premise correction (verified — see §2):** the original idea was "wire both agents to a shared
store." That wiring is **unnecessary — agentmemory memories are already shared between Claude and
agy out of the box.** So commonmemory adds **conventions only**, not plumbing: it makes the
already-shared store *usable on purpose* (consistent tagging + proactive recall) instead of by
accident.

---

## 2. Verified facts

*(Source: live ground-truth probe, 2026-06-18, `req-djboiru4bfqw`.)*

- **agentmemory memories are shared cross-agent.** Claude `memory_save`d a fact containing the token
  `COMMONMEMORY-PROBE-djboiru4`; agy then **found it via `memory_smart_search`**. So a memory written
  by one agent is recallable by the other with no extra wiring.
- The memory tools (`memory_save` / `memory_smart_search` / `memory_recall`) take **no `agentId`**
  parameter — memories are global/project-scoped, not per-agent siloed. Consistent with the probe.
- **Implication:** the only gap is **conventions** (consistent format + proactively querying the
  other agent's notes) — exactly what this plugin ships, and nothing more.

---

## 3. Locked decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Skills-only dual-plugin** (no binary, no MCP config, no hooks) | The store already exists + is shared; only a skill is needed. Distributing it as an installable skill (vs a buried doc) is the suite's purpose. |
| D2 | **Tag = concept `common` + a `[common]` content prefix + the repo name** | A searchable marker that flags a memory as cross-agent, scoped per project **without** relying on agentmemory's per-session `project` id matching between the two agents. |
| D3 | **Proactive recall on start/handoff** | Shared memory is worthless if neither agent looks; the skill makes querying `[common]` notes a startup/handoff step. |
| D4 | **Light fixed format** (incl. a `Status:` field) | So a note from the other agent is immediately usable, and stale handoffs are visible. |
| D5 | **Proactive recall needs a one-line global rule** in each agent's instructions (agy: `~/.gemini/GEMINI.md`; Claude: `CLAUDE.md`) | agy ground-truthed (`req-djbootj52zmw`): installing the skill does **not** auto-trigger recall; only a global rule guarantees "search `[common]` at task start." Same pattern as the clavity responder's GEMINI.md pointer. |

---

## 4. The convention (what the skill teaches)

Both agents, via the bundled `commonmemory` skill:

**Tagging a cross-agent note** — when saving something the *other* agent should know, use
`memory_save` with:
- `concepts` including **`common`** (+ the repo name, e.g. `clavity`),
- `content` beginning with **`[common] (<repo>)`**, then the note in the light format below.

**When to save a `[common]` note:**
- **Handoff state** — what you just did and what's next ("for agy/claude: …").
- **Shared decisions / architecture** — a choice both agents must respect.
- **Codebase gotchas** — non-obvious traps the other agent would otherwise re-hit.
- **Fixed bugs** — root cause + fix, so the other agent doesn't re-diagnose.

**Light format:**
```
[common] (<repo>) — <what> · Why: <why> · Status: <done | in-progress | blocked> · Next: <next step / for whom>
```

**Recalling — proactively, before acting:**
- At **session start** and when **picking up handed-off work**, run
  `memory_smart_search query="[common] <repo>"` (and/or `memory_recall`) and read the other agent's
  notes **before** starting, so you don't re-explain or re-discover.
- **Mind staleness** — agentmemory is append-mostly, so superseded `[common]` notes linger. Prefer
  the **most recent** note (check its timestamp), trust the `Status:` field, and don't act on an old
  handoff. *(agy spec review `req-djbootj52zmw`.)*

**Guardrails the skill states:**
- Tag `[common]` **only** for genuinely cross-agent-relevant notes (avoid flooding the shared pool).
- Don't duplicate what the code/git already records; capture the *non-obvious* (same discipline as a
  good memory note).

---

## 5. Packaging — plugin contents

`plugins/commonmemory/` (a universal dual-plugin per `docs/plugin-formats.md`):
```
plugins/commonmemory/
├── .claude-plugin/plugin.json   # Claude manifest  (name/version/description)
├── plugin.json                  # agy manifest     (same fields; disjoint filename → coexists)
├── skills/commonmemory/SKILL.md # the one skill — the convention above
└── README.md                    # what it is, the prerequisite, install, how it works
```
- **No** `.mcp.json` / `mcp_config.json` (no server), **no** binary, **no** hooks.
- Both manifests carry `name: "commonmemory"`, a `version`, and `description`.
- The README documents a **one-line global rule** to paste into each agent's instructions for D5
  (`~/.gemini/GEMINI.md` for agy — inside its `<user_rules>` block; `CLAUDE.md` for Claude), e.g.
  *"At the start of a task, `memory_smart_search` for `[common] <repo>` notes before acting."* The
  plugin MAY also ship an agy-side `rules/commonmemory.md` (agy reads `rules/`) as
  belt-and-suspenders — verify in the plan whether agy's plugin `rules/` auto-applies.

---

## 6. Prerequisite
**agentmemory** MCP server configured in **both** Claude Code and agy (the same global module → one
shared store). This is the *entire* dependency, and it's the same step as `clavity-classic`'s
agentmemory setup. (No psmux, no binary, no bus-addressing — this plugin is pure convention over the
shared memory store.)

---

## 7. Non-goals
- **No wiring / no config** to "share" memory — it's already shared (§2).
- **No reliance on agentmemory's `project` id** matching across the two agents — the `[common]
  (<repo>)` tag does the per-project scoping in content, robustly.
- **No new MCP tools / server / binary.** Advisory skill only.
- Not a structured DB, namespace system, or handoff state-machine — just the tagging + recall
  convention (YAGNI; richer designs are a later, separate concern).

---

## 8. Testing / acceptance
- **Packaging (automatable):** `claude plugin install ./plugins/commonmemory` and `agy plugin
  install ./plugins/commonmemory` are accepted; the `commonmemory` skill is discovered; the JSON
  manifests parse.
- **Round-trip (manual, mirrors the §2 probe):** one agent saves a `[common] (<repo>)` note; the
  other, following the recall convention, finds it via `memory_smart_search` and acts on it. (This is
  the same shape as the verified probe, now driven by the skill rather than by hand.)

---

## 9. Risks
- **Advisory, not enforced** — skills guide; they don't guarantee. **Proactive recall** in particular
  does **not** fire from the installed skill alone — it is made reliable by the **required global
  rule** (D5): one line in `~/.gemini/GEMINI.md` (agy) and `CLAUDE.md` (Claude). agy confirmed this
  is necessary, not optional (`req-djbootj52zmw`). Saving/tagging is still advisory (the agent must
  choose to record a `[common]` note).
- **Shared-pool noise** — over-tagging `[common]` dilutes value; mitigated by the §4 guardrail.
- **agentmemory dependency** — the one external dependency; if its memory API changes, the tool calls
  in the skill need re-verification (same `agy-assumptions` discipline as the rest of the suite).
