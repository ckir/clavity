# agy Capability Profile — Implementation Plan

> ## 🗄️ ARCHIVED — superseded, kept for provenance only
>
> Design artifact from the pre-monorepo clavity-classic tree, frozen by the 2026-07-09 vendor-in
> (`63fbef8`). The work it describes has since shipped and been restructured. **Do not read it as a
> description of the current tree.** Excluded from the docs-rationalize pass by `docs/docs-spec.md`.
> **Status 2026-06-16:** #1 profile + #2 wording protocol + acceptance suite (**10/10** live against
> agy 1.0.8) complete on clavity `main`. **Task 9 (global promotion) NOT done** — a corelib attempt was
> reverted as wrong-target (corelib is unrelated); the conventions live in clavity only, pending a
> correct shared destination.
>
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`)
> syntax for tracking.

**Goal:** Build `docs/agy-capabilities.md` — a provenance-tagged, version-pinned **capability profile**
that lets Claude route work to agy (an external, multi-model agent) by capability — and wire it into
the existing "how to ask agy" wording protocol.

**Architecture:** agy is, to Claude, an external **multi-model platform**. Three layers: **#1 WHAT it
can do** (this profile — the deliverable), **#2 HOW to ask it** (extend the existing protocol doc, then
promote to global), **#3 WHEN to ask automatically** (the existing hook — referenced only). The profile
is built by triangulating four sources — `[corpus]` (the user's validated knowledge), `[doc]` (web:
official docs + user findings; **primary**, since agy is closed-source), `[local]` (config files +
observed behavior), `[bus]` (agy's self-report; cross-check only) — synthesized on the main thread.

**Tech Stack:** Markdown docs; `clavity ask` (bus round-trips to the live agy); the Agent tool for
parallel web research; `WebSearch`/`WebFetch`; `Read`/`Glob`/`Grep` for corpus + config introspection.

**Full design:** `2026-06-16-agy-capability-profile-design.md` (read it first).

---

## File Structure

- **Create:** `docs/agy-capabilities.md` — the synthesized capability profile (#1). Axes A–G,
  provenance tags, `Verified against` header, refresh footer, links out.
- **Create:** `docs/agy-capabilities-research.md` — the raw source-tagged findings log (the evidence
  trail the profile distills; committed per research pass).
- **Modify:** `docs/agy-remote-control-protocol.md` → the "Driving conventions" section (#2): link to
  #1, make it capability- and model-aware.
- **Promote (Task 9):** the global AGENTS.md "Working with Antigravity" wording guidance — the shared
  upstream — *after* the local #2 extension is validated. Resolve the exact path at that task.
- **Reference only (never edit):** `~/.claude/hooks/agy-first-brainstorm.sh` (#3).

**Provenance legend (used throughout):** `[corpus]` user's validated knowledge · `[doc]` web (cite
URL) · `[local]` installed agy config/behavior · `[bus]` agy self-report · `[verified]` ≥2 sources
agree · `[conflict: …]` sources disagree (`[local]`/`[corpus]` win for our version).

---

## Task 1: Scaffold the two docs

**Files:**
- Create: `docs/agy-capabilities-research.md`
- Create: `docs/agy-capabilities.md`

- [ ] **Step 1: Create the research evidence log** with the source legend and one heading per pass.

```markdown
# agy capability research — raw findings (evidence log)

Raw, source-tagged findings that `agy-capabilities.md` distills. Each fact: a tag + (for `[doc]`) a
URL. Legend: [corpus] [doc] [local] [bus]. Conflicts noted inline.

## Pass 0 — corpus  ·  ## Pass 1 — web  ·  ## Pass 2 — local  ·  ## Pass 3 — bus
```

- [ ] **Step 2: Create the profile skeleton** with the header, axis stubs, and footer (content filled in Task 6).

```markdown
# agy capability profile — what agy can do, and how to route to it

> Verified against: agy <fill in Task 2> · models per the /model menu (Task 2). Provenance-tagged
> ([corpus]/[doc]/[local]/[bus]/[verified]/[conflict]); see docs/agy-assumptions.md (empirical) and
> docs/agy-remote-control-protocol.md (how to ask). agy is a dynamic, multi-model platform: effective
> capability = active model + orchestration + native tools + loaded skills/MCP.

## A. Strengths (route toward)
## B. Weaknesses & failure modes (route away / guardrail)
## C. Reasoning profile & model selection
## D. Operational reach
## E. Control surface that changes capability
## F. Routing: whether agy, and on which model
## G. Version & drift

## Refresh after an `agy update`
(filled in Task 6)
```

- [ ] **Step 3: Commit**

```bash
git add docs/agy-capabilities-research.md docs/agy-capabilities.md
git commit -m "docs: scaffold agy capability profile + research log"
```

---

## Task 2: Pass 0 (corpus) + Pass 2 (local) — the ground-truth passes

**Files:** Modify: `docs/agy-capabilities-research.md` (append to "Pass 0" and "Pass 2").

- [ ] **Step 1: Harvest the corpus.** Read each and extract capability-relevant facts (strengths,
  weaknesses, limits, reach, wording-relevant behavior):

Read: `~/.claude/skills/token-discipline-installer/templates/AGENTS-antigravity-protocol.md`;
`~/.claude/projects/C--Users-user-Development-Node-MarketMonitor/memory/feedback_agy_review_wording.md`,
`.../project_antigravity_protocol.md`, `.../feedback_agy_consult_before_user.md`;
`~/.claude/hooks/agy-first-brainstorm.sh`; and in-repo `docs/agy-assumptions.md`,
`docs/agy-remote-control-protocol.md`, `agy_skills/claudavity-responder/SKILL.md`.

- [ ] **Step 2: Record `[corpus]` facts** under "Pass 0" — one atomic fact per bullet, each with its
  source file. (e.g. `[corpus] over-escalates on open-ended discovery; seed specific invariants — feedback_agy_review_wording.md`.)

- [ ] **Step 3: Local introspection (config + behavior only — agy is closed-source).** Capture:

```bash
agy --version        # pin this in the profile header
agy --help           # flags + subcommands
agy models           # confirm the model list (falls back to the /model menu if it needs a TTY)
agy changelog        # recent version history (TTY fallback: read via clavity capture)
```

If any of `models`/`changelog` hang without a TTY (see `agy-assumptions.md` #1), get them from the
live pane instead: type the command into agy and `./target/debug/clavity capture --viewport`.

- [ ] **Step 4: Read config files + enumerate the loaded toolset.**

Read/Glob: `~/.gemini/config/mcp_config.json`; the `~/.gemini/antigravity-cli/` tree (skills,
`plugins`, `cli.log`); `~/.gemini/skills/`. Record the **currently-loaded skills + MCP servers**
(observed live: agentmemory, agy-mcp-bridge, serena) as `[local]` — this is the dynamic toolset.

- [ ] **Step 5: Record `[local]` facts** under "Pass 2", including the exact model list from the
  `/model` menu and the `agy --version`.

- [ ] **Step 6: Commit**

```bash
git add docs/agy-capabilities-research.md
git commit -m "docs(agy-profile): corpus + local introspection findings"
```

---

## Task 3: Pass 3 — agy self-report via the bus (cross-check)

**Files:** Modify: `docs/agy-capabilities-research.md` (append to "Pass 3").

- [ ] **Step 1: Confirm agy is reachable.**

Run: `./target/debug/clavity ping --timeout 90`
Expected: prints `[req_id=…] READY`, exit 0. If exit 1, agy isn't idle/up — resolve before continuing.

- [ ] **Step 2: Ask agy to self-report (two-mode wording; cross-check only).**

```bash
./target/debug/clavity ask --review-only "Describe your own capabilities for an external orchestrator deciding what to delegate to you. Cover: (1) task types you do reliably well vs poorly; (2) hard limits (context, worktree visibility, concurrency/cross-file reasoning); (3) your file-write reach — can your native tools (write_to_file/replace_file_content) write OUTSIDE the workspace cwd, or are writes restricted to it? Be precise; (4) your available models and when each is the right choice; (5) what loaded skills/MCP servers extend you. Be honest about weaknesses. Verdict only — do not edit files." --timeout 200
```

- [ ] **Step 3: Record `[bus]` facts** under "Pass 3." Mark anything that contradicts `[corpus]`/`[local]`
  as a candidate `[conflict]` (esp. the Axis D write-reach question — corpus says workspace-only).

- [ ] **Step 4: Commit**

```bash
git add docs/agy-capabilities-research.md
git commit -m "docs(agy-profile): agy self-report (bus) findings"
```

---

## Task 4: Pass 1 — web research (parallel agents; PRIMARY)

**Files:** Modify: `docs/agy-capabilities-research.md` (append to "Pass 1").

> Dispatch the four agents **in parallel** (one message, four `Agent` calls). Use a low/mid tier
> (Haiku/Sonnet) — high-volume, low-judgment fan-out. Each agent's dispatch prompt MUST include this
> contract verbatim: *"Return atomic, source-cited facts (each fact: one bullet + its source URL) plus
> an explicit 'COULD NOT CONFIRM' list. Do NOT invent or infer; if unconfirmed, say so. Never reshape a
> flag/path/command — paste exact strings. No elided enumerations (no '…'). Return raw findings only,
> not prose, not a finished document."*

- [ ] **Step 1: Dispatch Agent A — CLI & config surface.** Scope: `agy` flags, subcommands (`-p`,
  `--model`, `models`, `update`, `changelog`, …), the `~/.gemini/...` config layout, GEMINI.md, env.
  Seed: `antigravity.google/docs/*`, the Google codelab, `agy changelog` write-ups, StackOverflow.

- [ ] **Step 2: Dispatch Agent B — skills, MCP, sub-agents, TUI.** Scope: how agy loads skills + MCP
  servers (global vs shared, caching), sub-agents (`/agents`), TUI panels/footers/keybindings.

- [ ] **Step 3: Dispatch Agent C — per-model capability sweep.** Scope: the strengths / reasoning
  depth / speed / cost / context / tool-use of **each** model agy can run: Gemini 3.5 Flash, Gemini
  3.1 Pro, Claude Sonnet 4.6, Claude Opus 4.6, GPT-OSS 120B — so the profile can advise model choice.

- [ ] **Step 4: Dispatch Agent D — quirks & user findings.** Scope: documented gotchas, headless/print
  behavior, auth/keyring, and **community/user findings** (StackOverflow, GitHub issues, blog posts)
  about agy's real-world strengths/limits.

- [ ] **Step 5: Collate** each agent's returned findings under "Pass 1" as `[doc]` facts **with their
  URLs**. Keep the "COULD NOT CONFIRM" items in a sub-list.

- [ ] **Step 6: Commit**

```bash
git add docs/agy-capabilities-research.md
git commit -m "docs(agy-profile): web research findings (docs + user findings + per-model)"
```

---

## Task 5: Synthesize the capability profile

**Files:** Modify: `docs/agy-capabilities.md` (fill axes A–G + footer from the research log).

- [ ] **Step 1: Fill Axis A (Strengths).** For each strength, write the claim + a `[tag]` + a
  **calibration note**. Promote to `[verified]` only where ≥2 sources agree. Include the corpus
  strengths (verification > discovery; protocol adherence) and `[bus]`-reported ones (native
  multi-edits, reactive async) **marked to-verify**.

- [ ] **Step 2: Fill Axis B (Weaknesses).** Open-discovery over-escalation/hallucination; cross-graph/
  concurrency local-sequential reasoning; worktree-blind-until-probe; discovery burns context;
  backend-overload aborts. Tag each.

- [ ] **Step 3: Fill Axis C (Reasoning & model selection).** State agy is a multi-model router; paste
  the exact `[local]` model list (Gemini 3.5 Flash L/M/H, Gemini 3.1 Pro L/H[current], Claude Sonnet
  4.6 Thinking, Claude Opus 4.6 Thinking, GPT-OSS 120B Medium); add the **per-model note** from Agent
  C (what each is good/cheap/strong at). Note the separate context window.

- [ ] **Step 4: Fill Axis D (Operational reach).** Shell (pwsh), the agentmemory MCP (durable
  cross-agent recall), other MCP, sub-agents, checkpoints, headless behavior. **File-write reach is a
  `[conflict]`:** `[corpus]`/empirical (agy-assumptions #8) = workspace-only (artifact-path → shell
  fallback); `[bus]` = native tools write anywhere OS perms allow. State both; **do not assert
  either**; add a one-line "to resolve: test a write outside cwd and observe."

- [ ] **Step 5: Fill Axis E (Control surface) + Axis F (Routing).** E: model selection, loaded
  skills/MCP (the dynamic part), permissions mode. F: whether-agy-vs-Claude-subagent **and**
  which-model (deep review → Opus 4.6 Thinking / Gemini 3.1 Pro High; bulk → Flash Low; cost → GPT-OSS),
  plus the redundancy guard (don't route weak-model work to agy that Claude should keep).

- [ ] **Step 6: Fill Axis G + the refresh footer.** G: `Verified against` version + a "capability
  changes by version" note. Footer: the refresh runbook — `agy changelog` diff → re-run local
  introspection → targeted web re-check → re-tag + bump version → cross-link agy-assumptions if routing
  changed. Add the links-out (agy-assumptions, protocol doc, the hook).

- [ ] **Step 7: Fill the header** `Verified against: agy <version>` from Task 2.

- [ ] **Step 8: Commit**

```bash
git add docs/agy-capabilities.md
git commit -m "docs: synthesize agy capability profile (axes A-G)"
```

---

## Task 6: Verify the profile

**Files:** Modify: `docs/agy-capabilities.md` (fix any gaps found).

- [ ] **Step 1: Provenance coverage check.** Read the profile; confirm **every capability claim** has
  a tag and every `[doc]` claim cites a URL. Fix any untagged claim.

Run: `grep -nE '^[-*] ' docs/agy-capabilities.md | grep -viE '\[(corpus|doc|local|bus|verified|conflict)' || echo "ALL TAGGED"`
Expected: `ALL TAGGED` (or fix the lines it prints).

- [ ] **Step 2: Conflict + calibration check.** Confirm the Axis D write-reach `[conflict]` is present
  and unresolved, and that every Axis A strength has a calibration note. Fix omissions.

- [ ] **Step 3: Spot-check 3 claims against the installed agy.** Pick one flag/subcommand, one model
  list entry, and one operational limit; confirm against `agy --help` / the `/model` menu / observed
  behavior. Correct the profile if any fails. (Verifies inversely to tier — web findings checked hard.)

- [ ] **Step 4: Commit**

```bash
git add docs/agy-capabilities.md
git commit -m "docs(agy-profile): verify provenance, conflicts, spot-checks"
```

---

## Task 7: Extend the wording protocol (#2, local)

**Files:** Modify: `docs/agy-remote-control-protocol.md` → "Driving conventions (agy's stated preferences)".

- [ ] **Step 1: Add a capability-routing pointer** at the top of "Driving conventions":

```markdown
**Route by capability first.** Before phrasing an ask, consult the capability profile
([`docs/agy-capabilities.md`](agy-capabilities.md)) to decide **whether** to delegate to agy at all,
**what** to delegate (strengths vs weaknesses), and **which model** to set agy to for the task.
```

- [ ] **Step 2: Make the existing discipline capability-aware.** Cross-reference each rule to its
  profile axis (e.g. "front-load context — agy is worktree-blind, Axis B"; "seed invariants, don't ask
  for open discovery — Axis B"; "pick the model — Axis C/F"). Keep the two-mode ask, severity-gating,
  evidence mandate, no-hyperbole, delegation-boundary rules already present.

- [ ] **Step 3: Verify the link resolves.**

Run: `grep -n "agy-capabilities.md" docs/agy-remote-control-protocol.md`
Expected: at least one match.

- [ ] **Step 4: Commit**

```bash
git add docs/agy-remote-control-protocol.md
git commit -m "docs: make agy 'Driving conventions' capability- and model-aware (cite #1)"
```

---

## Task 8: Validate #2 locally (dogfood)

- [ ] **Step 1: Use the extended protocol to route one real ask.** Pick a small task; per the profile,
  choose whether/what/which-model, then run `./target/debug/clavity ask …` accordingly. Confirm the
  capability-aware phrasing produces a well-scoped, on-target agy reply (no over-escalation).

- [ ] **Step 2: Note any wording-rule gap** the live test reveals; fix it in
  `docs/agy-remote-control-protocol.md` and re-commit if changed.

```bash
git add -A && git commit -m "docs(agy-protocol): fixes from live capability-aware dogfood" || echo "no changes"
```

---

## Task 9: Promote #2 to the global AGENTS.md (after local validation) — ⚠️ NOT DONE (attempt reverted)

**Files:** Modify: the global AGENTS.md "Working with Antigravity" wording guidance (the shared
upstream). Resolve its exact path at this task (the in-repo instance derives from
`~/.claude/skills/token-discipline-installer/templates/AGENTS-antigravity-protocol.md`).

- [ ] **Step 1: Locate the canonical global wording doc.** A 2026-06-16 attempt targeted
  `~/Development/Node/corelib/AGENTS.md` (it hosts the "Working with Antigravity" brief), but **that was
  the wrong target** — corelib is an unrelated project; clavity content does not belong in its history.
  The commit was reverted and force-removed from corelib's remote (no trace). **Correct destination is
  still TBD** — do not assume corelib.
- [ ] **Step 2: Port the capability-aware additions** into the chosen shared doc, generalized
  (transport-agnostic; cross-reference clavity's `agy-capabilities.md` / `agy-test-suite.md`).
- [ ] **Step 3: Commit** in whichever repo legitimately owns the shared brief.

> The capability-aware conventions currently live **only in clavity** (`agy-remote-control-protocol.md`
> "Driving conventions"). That is a complete, working state; promotion is optional and on hold pending
> the right destination.

---

## Task 10: Finish

- [ ] **Step 1: Cross-link** `docs/agy-assumptions.md` to the new profile (one line under its intro:
  "Capability/routing profile: `agy-capabilities.md`"). Commit.
- [ ] **Step 2:** Use **superpowers:finishing-a-development-branch** to complete the work (verify, then
  merge/PR/keep per the user's choice).

---

## Self-Review (completed by plan author)

- **Spec coverage:** #1 profile (Tasks 1,5,6) · all four sources — corpus/local (T2), bus (T3), web
  incl. per-model (T4) · provenance + conflict model (T5,T6) · multi-model axis (T3 Q4, T4 Agent C,
  T5 S3) · #2 extension local→global (T7,T8,T9) · #3 referenced not edited (T7 S2, never edited) ·
  refresh runbook (T5 S6) · success criteria (T6). Covered.
- **Placeholders:** none — every step has the concrete command, file, or text. The two intentional
  fill-ins (`agy --version`, the global-doc path) are explicitly resolved in T2/T9 with the command
  that produces them.
- **Naming consistency:** `docs/agy-capabilities.md` (#1), `docs/agy-capabilities-research.md`
  (evidence log), `docs/agy-remote-control-protocol.md` "Driving conventions" (#2) — used identically
  throughout. Axes A–G labels match the spec.
