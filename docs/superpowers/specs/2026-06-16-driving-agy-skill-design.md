# Design — `driving-agy`: a living, authoritative skill for driving Antigravity

> Status: approved design (brainstormed 2026-06-16). Next step: implementation plan (writing-plans).
> Provenance: clavity's purpose is for Claude to drive `agy`; optimal driving needs deep, current
> knowledge of agy. clavity's existing agy knowledge is deliberately **empirical** (observed on this
> machine) because "agy's behavior is not a stable contract." This spec adds an **authoritative**
> knowledge layer sourced from the web, cross-checked against the installed agy and agy's own
> self-report, packaged as a Claude-side skill that extends Claude's driving capability.

---

## 1. Goal & purpose

Build `skills/driving-agy/SKILL.md` — a Claude-side skill that Claude auto-loads when it is about to
drive agy — holding a comprehensive, **provenance-tagged**, version-pinned reference to Antigravity
(`agy`): its CLI surface, configuration, skills/MCP wiring, TUI, models/headless/auth, and version
history/quirks. The skill is **living**: it pins the version it was verified against and carries a
refresh runbook to re-validate after an `agy update`.

**Non-goal:** replacing the empirical layer. This skill is the authoritative "what *is* agy"
reference; the empirical, version-verified "what we confirmed here / how to re-verify" stays in
`docs/agy-assumptions.md`, and the step-by-step "how to drive" stays in
`docs/agy-remote-control-protocol.md`. The skill **links to** these and does not duplicate them.

---

## 2. Where the knowledge lives (layering)

| Layer | Answers | Authority |
|---|---|---|
| `skills/driving-agy/SKILL.md` (**new**) | "What *is* agy? What can it do; how is it configured?" | Authoritative (web) + cross-checked locally |
| `docs/agy-assumptions.md` | "What have we *verified* on this machine, and how to re-verify?" | Empirical, version-pinned |
| `docs/agy-remote-control-protocol.md` | "How do I drive it, step by step?" | Procedure |

Rationale for a **skill** (vs. a plain doc): the stated purpose is to extend *Claude's* capability;
a skill is auto-loaded on relevant intent, a doc is not.

---

## 3. The skill artifact

**Trigger.** The skill's `description` fires on agy-driving intent: driving agy, delegating a task to
agy, composing a bus request, or debugging an agy round-trip.

**Provenance is mandatory on every fact.** The central risk is "authoritative but wrong for our
installed version." Each fact is tagged inline:

- `[doc]` — official docs / codelab / changelog (cite the URL).
- `[local]` — confirmed by introspecting the installed agy (`agy --help`, config files, logs).
- `[bus]` — agy's own self-report over the clavity bus.
- `[verified]` — cross-checked and agreeing across **≥2** sources (gold standard).
- `[conflict: …]` — sources disagree; surfaced explicitly. For *our* version, `[local]`/`[bus]` win
  over `[doc]`.

**No untagged claims.** Facts that touch a flag/path/command we actually drive must be `[verified]`
or at least `[local]` before being stated unqualified.

**Body sections** (the six research clusters):
1. **CLI surface** — flags, subcommands (`-p`/prompt, `--model`, `models`, `update`, `changelog`, …).
2. **Config & directories** — `~/.gemini/antigravity-cli/`, `~/.gemini/config/mcp_config.json`,
   `~/.gemini/skills/` vs `~/.gemini/antigravity-cli/skills/`, GEMINI.md, env.
3. **Skills & MCP wiring** — how agy discovers/loads skills and MCP servers; global vs shared; caching.
4. **TUI** — footers (idle/busy markers), `/`-panels (`/agents`, `/config`, `/keybindings`), keybindings.
5. **Models, headless & auth** — model selection, headless/print behavior, keyring/OAuth auth.
6. **Version/changelog & known quirks** — version history, notable changes, documented gotchas.

**Header & footer.** A `Verified against: agy <version>` header; the refresh runbook (§6) as footer.

---

## 4. Research execution (Hybrid — three passes + synthesis)

**Pass 1 — Web sweep (parallel, delegated).** One research subagent per cluster (6 total), on a
lower tier (high-volume/low-judgment fan-out). Strict dispatch contract per agent:
- *Scope:* its cluster only; seeded with known URLs (`antigravity.google/docs/*`, the Google
  codelab, community guides) plus free web search.
- *Deliverable shape:* a bullet list of **atomic facts, each with a source URL**, a recency/version
  note where visible, and an explicit "couldn't confirm" list. No prose essays. Return raw findings,
  **not** a finished skill.
- *Guardrails (per the repo's subagent rules):* do not invent or fill gaps — unconfirmed ⇒ say so;
  never paraphrase a flag/path/command into a different shape; paste exact strings (flags, dirs, key
  names) verbatim; no elided enumerations.

**Pass 2 — Local introspection (main thread; ground truth for our version).** Run/read the installed
agy: `agy --help`, `agy --version`, `agy models`, `agy changelog`; inspect
`~/.gemini/antigravity-cli/` (skills, `cli.log`), `~/.gemini/config/mcp_config.json`,
`~/.gemini/skills/`. Authoritative for what we actually drive.

**Pass 3 — agy self-report (main thread; via the bus).** `clavity ask --review-only` agy to describe
its own flags, config paths, skill/MCP loading, and quirks — dogfooding clavity and adding a third
triangulation point. (agy can be wrong about itself ⇒ treat as one source, cross-check.)

**Synthesis & cross-verify (main thread).** Merge the three sources into the skill: tag each fact,
promote agreeing facts to `[verified]`, surface disagreements as `[conflict: …]`. This stays on the
main thread because it is the high-judgment reconciliation that needs full context. Apply "verify
inversely to tier": the lower-tier web findings get checked harder, and any driving-critical
path/flag is confirmed against `[local]` before being stated unqualified.

---

## 5. Components & data flow

```
[6 web-sweep subagents]  -->  raw source-cited facts  ┐
[local introspection]    -->  ground-truth facts      ├─> [main-thread synthesis + cross-verify]
[agy self-report (bus)]  -->  self-reported facts      ┘            |
                                                                    v
                                              skills/driving-agy/SKILL.md
                                              (provenance-tagged, version-pinned)
                                                    |  links (no duplication)
                                                    v
                              docs/agy-assumptions.md   docs/agy-remote-control-protocol.md
```

Each unit is independently understandable: a web-sweep agent (input: cluster + seed URLs; output:
cited facts), local introspection (input: installed agy; output: ground-truth facts), the bus
self-report (input: a clavity ask; output: agy's claims), and synthesis (input: all three; output:
the skill).

---

## 6. Lifecycle — refresh procedure (baked into the skill footer)

After any `agy update`:
1. `agy changelog` → diff against the pinned version; note added/removed flags/subcommands.
2. Re-run Pass 2 introspection (`agy --help`, `agy models`, dirs) — the cheap ground-truth recheck.
3. Re-check `antigravity.google/docs` + changelog for new material (targeted, not a full re-sweep).
4. Update changed facts (re-tag provenance); bump the `Verified against` header.
5. If a *driving-relevant* behavior changed, cross-link/update `docs/agy-assumptions.md`.

This mirrors `agy-assumptions.md`'s re-verify ethos so the two stay in lockstep.

---

## 7. Success criteria

- `skills/driving-agy/SKILL.md` exists, triggers on agy-driving intent, and covers all six clusters.
- Every fact is provenance-tagged; **no untagged claims**. Driving-critical facts (flags/paths we
  use) are `[verified]` or `[local]`.
- All `[conflict: …]` items are listed explicitly, never silently resolved.
- A `Verified against: agy <version>` header and a runnable refresh procedure are present.
- The skill **links to** (does not duplicate) `agy-assumptions.md` and the protocol doc.
- Spot-check: a handful of stated flags/paths actually work against the installed agy.

---

## 8. Out of scope (YAGNI)

- The Antigravity **IDE / desktop** app — CLI (`agy`) only.
- Rewriting the responder skill or protocol doc — only cross-link if research reveals a real
  correction.
- Any automated/scheduled re-research — the refresh (§6) is a manual runbook.

---

## 9. Risks

- **Sparse/contradictory web coverage** for a young, fast-moving tool ⇒ mitigated by triangulation +
  `[conflict]` tagging + local/bus authority for our version.
- **Web facts stale vs. installed version** ⇒ provenance tags + `Verified against` pin make staleness
  visible rather than silent.
- **agy mis-reports itself** ⇒ treated as one source, cross-checked against `[local]`/`[doc]`.
- **Lower-tier web agents miss nuance** ⇒ "verify inversely to tier"; main thread re-checks
  driving-critical items.
