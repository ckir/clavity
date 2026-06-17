# commonmemory Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `commonmemory`, a skills-only universal dual-plugin that teaches Claude and agy to use the already-shared agentmemory store as a deliberate cross-agent memory (tag `[common]` notes; proactively recall them).

**Architecture:** Pure content — both manifests + one `SKILL.md` (the convention) + a README + an agy-side `rules/` file. No binary, no MCP server, no hooks, no wiring (agentmemory memories are already shared cross-agent — proven). Proactive recall is made reliable by a one-line global rule documented in the README (agy confirmed it's required).

**Tech Stack:** Markdown skill + JSON manifests. No build/test toolchain. Validation via `python`/`json` parse + the two CLIs' `plugin install` + a live save/recall round-trip.

**Spec:** `docs/superpowers/specs/2026-06-18-commonmemory-plugin-design.md`

---

## File Structure

| Path | Responsibility |
|---|---|
| `plugins/commonmemory/.claude-plugin/plugin.json` | Claude manifest (name/version/description) |
| `plugins/commonmemory/plugin.json` | agy manifest (same fields; disjoint filename) |
| `plugins/commonmemory/skills/commonmemory/SKILL.md` | the shared-memory convention (read by both CLIs) |
| `plugins/commonmemory/rules/commonmemory.md` | agy-native `rules/` recall rule (agy reads `rules/`; Claude ignores it) |
| `plugins/commonmemory/README.md` | what it is, prereq, install, the required global-rule, how it works |

---

## Task 1: Scaffold the plugin + manifests + agy rules file

**Files:**
- Create: `plugins/commonmemory/.claude-plugin/plugin.json`, `plugins/commonmemory/plugin.json`, `plugins/commonmemory/rules/commonmemory.md`

- [ ] **Step 1: Verify state**

Run: `git rev-parse --abbrev-ref HEAD`
Expected: `main` (or whatever branch you intend). Confirm `plugins/clavity-classic/` exists (the suite's working example). If the repo layout differs, STOP and report `STATE_MISMATCH: <what>`.

- [ ] **Step 2: Write the Claude manifest**

`plugins/commonmemory/.claude-plugin/plugin.json`:
```json
{
  "name": "commonmemory",
  "version": "0.1.0",
  "description": "Shared cross-agent memory conventions for Claude + agy over the agentmemory store."
}
```

- [ ] **Step 3: Write the agy manifest** (same fields; disjoint filename → coexists)

`plugins/commonmemory/plugin.json`:
```json
{
  "name": "commonmemory",
  "version": "0.1.0",
  "description": "Shared cross-agent memory conventions for Claude + agy over the agentmemory store."
}
```

- [ ] **Step 4: Write the agy-native rules file** (agy auto-reads `rules/`; Claude ignores it)

`plugins/commonmemory/rules/commonmemory.md`:
```markdown
# commonmemory — proactive recall

At the START of a task, and whenever picking up handed-off work, run
`memory_smart_search query="[common] <repo>"` (where `<repo>` is the current repository's name) and
read the other agent's notes BEFORE acting. Prefer the most recent note (check its timestamp), honor
its `Status:`, and do not act on a superseded handoff.
```

- [ ] **Step 5: Validate the manifests parse**

Run: `python -c "import json; [json.load(open(f,encoding='utf-8')) for f in ['plugins/commonmemory/.claude-plugin/plugin.json','plugins/commonmemory/plugin.json']]; print('json ok')"`
Expected: `json ok`.

- [ ] **Step 6: Commit**

```bash
git add plugins/commonmemory/.claude-plugin plugins/commonmemory/plugin.json plugins/commonmemory/rules
git commit -m "feat(commonmemory): manifests + agy rules file"
```

---

## Task 2: Author the `commonmemory` skill

**Files:**
- Create: `plugins/commonmemory/skills/commonmemory/SKILL.md`

- [ ] **Step 1: Write the skill**

`plugins/commonmemory/skills/commonmemory/SKILL.md`:
```markdown
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
  content="[common] (clavity) — psmux escape-time default 500ms is the keyboard-lock cause; set 10. · Why: a bare Esc is held ~500ms. · Status: done · Next: rebuild the clavity-classic binary so clavity start sets it."
)
```
```

- [ ] **Step 2: Validate the skill frontmatter**

Run: `python -c "import pathlib; p='plugins/commonmemory/skills/commonmemory/SKILL.md'; t=pathlib.Path(p).read_text(encoding='utf-8'); print('frontmatter ok' if t.startswith('---') and 'name: commonmemory' in t else 'BAD')"`
Expected: `frontmatter ok`.

- [ ] **Step 3: Commit**

```bash
git add plugins/commonmemory/skills/commonmemory
git commit -m "feat(commonmemory): the shared-memory convention skill"
```

---

## Task 3: Author the README

**Files:**
- Create: `plugins/commonmemory/README.md`

- [ ] **Step 1: Write the README**

`plugins/commonmemory/README.md`:
```markdown
# commonmemory (universal dual-plugin)

Shared cross-agent memory conventions for **Claude Code** and **Antigravity (`agy`)**. Both already
connect to the same **agentmemory** store, so a memory one agent saves is recallable by the other —
this plugin ships the *convention* (a single skill) that makes that shared store useful on purpose:
tag `[common]` notes, and proactively recall them on task start / handoff. No binary, no MCP server.

## Prerequisite
**agentmemory** MCP server configured in BOTH CLIs (the same global `@agentmemory/agentmemory`
module → one shared store). Same setup as `clavity-classic` (see its README step 3). That is the
only dependency.

## Install (both CLIs, one directory)
```
claude plugin install ./plugins/commonmemory
agy    plugin install ./plugins/commonmemory
```

## Required: turn on proactive recall (one line per agent)
Installing the plugin makes the skill *available* but does **not** make either agent auto-search on
its own. Add a one-line rule to each agent's global instructions so they recall `[common]` notes at
the start of a task:
- **agy** — in `~/.gemini/GEMINI.md` (inside its `<user_rules>` block):
  > At the start of a task, `memory_smart_search` for `[common] <repo>` notes (repo = the current
  > repository name) and read them before acting.
  (The bundled `rules/commonmemory.md` ships the same rule; if your agy auto-applies plugin
  `rules/`, the GEMINI.md edit is redundant — verify once.)
- **Claude** — add the same one-line rule to your `CLAUDE.md` (project or user scope).

## How it works
- **Recall:** `memory_smart_search query="[common] <repo>"` before acting; honor the newest note's
  `Status:`; ignore stale handoffs.
- **Save:** `[common] (<repo>) — <what> · Why: <why> · Status: <…> · Next: <…>` for handoffs, shared
  decisions, codebase gotchas, and fixed bugs.
See `skills/commonmemory/SKILL.md` for the full convention.

## Contents
- `skills/commonmemory/SKILL.md` — the shared-memory convention (read by both CLIs)
- `rules/commonmemory.md` — agy-native proactive-recall rule (Claude ignores it)
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests
```

- [ ] **Step 2: Commit**

```bash
git add plugins/commonmemory/README.md
git commit -m "docs(commonmemory): README (prereq, install, the required recall rule)"
```

---

## Task 4: Packaging acceptance

**Files:** none (validation + a manual install + live round-trip runbook).

- [ ] **Step 1: Confirm the full tree**

Run (PowerShell): `Get-ChildItem -Recurse -File plugins/commonmemory | ForEach-Object { $_.FullName.Replace("$PWD\","") }`
Expected exactly:
```
plugins/commonmemory/.claude-plugin/plugin.json
plugins/commonmemory/plugin.json
plugins/commonmemory/README.md
plugins/commonmemory/rules/commonmemory.md
plugins/commonmemory/skills/commonmemory/SKILL.md
```

- [ ] **Step 2: Validate all JSON parses**

Run: `python -c "import json,glob; [json.load(open(f,encoding='utf-8')) for f in glob.glob('plugins/commonmemory/**/*.json', recursive=True)]; print('json ok')"`
Expected: `json ok`.

- [ ] **Step 3: Manual install acceptance (runbook — record results)**

```
claude plugin install ./plugins/commonmemory     # accepted; commonmemory skill discoverable
agy    plugin install ./plugins/commonmemory      # accepted; skill discoverable
```
Confirm each CLI accepts the install and lists the `commonmemory` skill. Restart agy so the plugin
registers (and so it picks up `rules/` if it auto-applies them).

- [ ] **Step 4: Live round-trip test (mirrors the spec's verified probe)**

1. In one agent (say Claude), save a `[common]` note per the convention:
   `[common] (clavity) — round-trip test of commonmemory. · Why: verify cross-agent recall. · Status: in-progress · Next: agy recalls this.`
2. In the other agent (agy), follow the recall convention:
   `memory_smart_search query="[common] clavity"` → confirm it finds the note and reports its content.
3. **Verify the agy auto-recall question:** start a *fresh* agy task and see whether agy proactively
   searches `[common]` WITHOUT being told (i.e. did the `rules/` file or GEMINI.md rule fire?). Record
   which mechanism was needed (plugin `rules/` auto-apply vs. the explicit GEMINI.md rule) and update
   the README's "Required" note if `rules/` alone suffices.
4. Clean up the test note (`memory_governance_delete`, or the `forget` skill).

- [ ] **Step 5: Commit any fixes**

If Step 3/4 surfaced a fix (a manifest field a CLI rejects, or the README's recall-rule guidance
needs correcting per the Step-4 finding), apply it, re-validate (Steps 1–2), and commit:
```bash
git add -A
git commit -m "fix(commonmemory): adjust per live install + round-trip acceptance"
```

---

## Self-Review

**Spec coverage:** §3 D1 skills-only → Tasks 1–3 (manifests + skill + README; no server/binary/hooks);
D2 tag convention (`[common] (<repo>)` + concept `common` + `memory_smart_search` recall) → Task 2
SKILL.md; D3 proactive recall + D5 global rule → Task 2 (recall section) + Task 1 `rules/` + Task 3
README "Required" section; D4 light format incl. `Status:` + staleness guardrail → Task 2; §5 packaging
→ Tasks 1–3; §6 prerequisite → Task 3 README; §8 acceptance (packaging + round-trip) → Task 4; the
"verify whether agy plugin `rules/` auto-applies" open item → Task 4 Step 4.3.

**Placeholder scan:** none — every file's full content is inline; `<repo>` / `<what>` / `<why>` are
literal template placeholders that are part of the convention's format, not unfilled plan gaps.

**Type consistency:** the plugin name `commonmemory` and version `0.1.0` match across both manifests
(Task 1) and the README (Task 3); the skill `name: commonmemory` matches its directory; the tag/format
(`[common] (<repo>) — … · Status: … · Next: …`) and the recall query (`memory_smart_search
query="[common] <repo>"`) are identical in the SKILL.md (Task 2), the `rules/` file (Task 1), and the
README (Task 3); all paths match the File Structure table and the Task-4 tree check.
