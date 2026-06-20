# `agy-autotrain` — a self-improving agy driving + knowledge plugin

**Goal:** Give the Claude driver a distributable clavity plugin that (1) makes invoking the `agy`
peer feel like calling a model/subagent, and (2) auto-trains clavity's knowledge of agy from everyday
usage — capture → test → promote — keeping the knowledge **project-agnostic** so it generalises across
every project and every clavity user.

**Architecture:** A new universal dual-plugin `plugins/agy-autotrain/` (Claude + agy manifests, shared
`skills/`). It adds **no Rust** — it composes the *existing* `clavity` binary commands (`ask`,
`await-reply`, …) and the existing knowledge docs. Three skills (drive, learn, curate) plus a
verification harness implement a closed loop: a **raw observations inbox** decouples fast live capture
from slow deliberate curation; curation promotes verified, generalised entries into the canonical
`agy-capabilities.md` / `agy-assumptions.md`; a harness re-verifies the testable subset against live
agy and the loop is promoted from project-local → global once it proves out.

**Tech stack:** Markdown skills + docs (no compiled code). Consumes `clavity` (≥ the version exposing
`ask`/`await-reply`), the `agentmemory` bus, and `git`. Distributed via GitHub like the other clavity
plugins.

---

## Background — why this plugin

Four observed problems motivate it (all seen in real driving sessions; see "Evidence" below):

1. **Abstraction leak.** clavity already exposes a clean one-shot primitive (`clavity ask`), yet the
   driver hand-rolls the raw bus protocol (`req-id` + `memory_signal_send` + `ring` + `memory_signal_read`
   + manual polling) because the low-level primitives are visible in context. Visible primitives invite
   an LLM to over-orchestrate. → Treat agy as a *function*, not a *system on a bus*.
2. **Bad task assignment causes misfires.** agy drifts into *executing* a task that was meant as a
   *review* when the request lacks a loud, explicit no-edit contract. The optimal **driving protocol**
   (how to frame a task so agy does the right thing) is load-bearing knowledge that lives only in the
   driver's head today.
3. **No feedback loop.** `agy-capabilities.md` / `agy-assumptions.md` are rich but **hand-curated**;
   nothing feeds live-session observations (latency, calibration, new failure modes) back in.
4. **Generalisation is hard mid-task.** A driver embedded in a specific codebase leaks project nouns
   when trying to write a "general rule," so naive capture would pollute the knowledge base with a
   project journal.

## Design principles

- **One front door.** The driver is taught exactly one invocation path (`clavity ask`, sync; or the
  send-then-`await-reply` async escape hatch). Low-level bus commands are *diagnostics*, not the
  default — hidden from the driving skill but kept available for recovery.
- **Capture is cheap and live; curation is deliberate and offline.** A raw inbox decouples the two.
- **Sanitise before store.** Capture's first job is to strip project specifics and emit a general rule.
- **No binary changes.** Everything composes existing `clavity` commands + markdown. (agy's
  telemetry-footer / `clavity log` auto-capture are deferred binary work — see "Deferred".)
- **Project-local first, global later.** Prove the loop in one project, then promote skills + knowledge
  to the global config — the established trial-then-globalise pattern.

---

## Components

### 1. Plugin skeleton `plugins/agy-autotrain/`

A universal dual-plugin per `docs/plugin-formats.md`: `.claude-plugin/plugin.json` + root `plugin.json`,
a shared `skills/` dir, and a `README.md`. Contents:

```
plugins/agy-autotrain/
  .claude-plugin/plugin.json      # Claude manifest
  plugin.json                     # agy manifest
  README.md                       # what it is, install, the loop
  skills/
    driving-agy/SKILL.md          # the invocation + task-assignment protocol (Claude-side)
    agy-learn/SKILL.md            # capture: sanitise → append to inbox
    agy-curate/SKILL.md           # curation workflow: inbox → canonical docs, optimise, empty
  knowledge/
    agy-observations.md           # the raw inbox (provenance-tagged, project-agnostic)
  verify/
    assertions.md                 # the testable Empirical Assumptions + their synthetic probes
    run-verification.md           # runbook the harness skill follows
```

> The canonical `agy-capabilities.md` / `agy-assumptions.md` remain where they are (clavity `docs/`);
> this plugin's curation step *writes into them*. The plugin ships its own `knowledge/agy-observations.md`
> inbox (starts empty) and `verify/` suite.

### 2. `driving-agy` skill — the invocation + task-assignment protocol

Teaches the driver the **one front door** and the framing rules that prevent misfires:

- **Invoke via `clavity ask`** (sync) — returns agy's reply string, "like calling a subagent."
  For long consults use the **async escape hatch**: send the request, do other work, then
  `clavity await-reply --req-id <id> --thread-id <id>` (or read the bus scoped to the thread). Do NOT
  hand-roll the primitives; they are listed only under a "diagnostics / recovery" subsection.
- **Task-assignment contract.** For any *review / red-team / consult* task, prepend the canonical
  **REVIEW-ONLY banner** (no-edit/no-commit, with an explicit forbidden-actions list); for a
  *delegated implementation*, state the oracle, the exact done-condition, and the no-scope-creep rule.
  These rules are themselves *Heuristics* in the knowledge base (so they evolve via the loop).
- **Latency + availability expectations** sourced from the knowledge base (e.g. minute-scale first
  token; on a silent timeout, the reply is still recoverable from the bus; have a fallback).

### 3. `agy-learn` skill — capture

Invoked the moment the driver learns something general about agy. Steps the skill enforces:

1. **Sanitise & generalise (hard gate).** Rewrite the observation as a general rule with **zero**
   project-specific nouns (no language names, file names, ticket ids, product names). The skill's
   prompt makes this the *first and mandatory* transformation; if the observation can't be generalised,
   it isn't captured. (This is the single most important step — naive capture pollutes the base.)
2. **Classify** the entry as **Empirical Assumption** (a testable constraint, e.g. "agy honors a loud
   REVIEW-ONLY banner — no edits") or **Heuristic** (a soft routing/driving guideline, e.g. "agy
   verifies better than it discovers; seed invariants").
3. **Tag provenance** (`[corpus]` = observed live this session) + date + the agy version if known.
4. **Append one bullet** to `knowledge/agy-observations.md`. Never edits the canonical docs directly.

### 4. `agy-curate` skill — curation / optimisation workflow

A deliberate, offline pass (run periodically or when the inbox grows). Steps:

1. Read `knowledge/agy-observations.md` and the canonical `agy-capabilities.md` / `agy-assumptions.md`.
2. For each inbox entry decide: **promote** (new, verified-enough → into the right canonical section),
   **reinforce** (bump confidence / add a corroborating provenance tag), **contradict** (resolve
   against the existing claim; newer `[local]`/`[corpus]` wins for the pinned version), or **drop**
   (noise / too specific / duplicate). This *is* the optimiser (dedupe / prune-stale / drift-detect).
3. When a promoted entry is an **Empirical Assumption**, add/update its probe in `verify/assertions.md`.
4. **Empty the inbox** (the entries now live in the canonical docs or were dropped).

### 5. Knowledge base structure

- **Inbox** (`knowledge/agy-observations.md`): provenance-tagged bullets, project-agnostic, transient.
- **Canonical** (`docs/agy-capabilities.md`, `docs/agy-assumptions.md`): unchanged structure; curation
  writes here. The **Empirical-vs-Heuristic split** is made explicit so the verifier knows what's
  testable.

### 6. Verification & optimisation suite (`verify/`)

A harness skill (no binary) that test-drives the **Empirical Assumptions** against live agy:

- For each assertion, fire a **synthetic `clavity ask`** with a payload that exercises the claim, then
  assert the outcome. Example: assert "honors REVIEW-ONLY banner" by sending a review request that
  *invites* an edit, then checking the agy workspace `git status` stayed clean and the reply contains a
  no-edit verdict. Each assertion in `verify/assertions.md` names: the probe payload, the observable
  signal, and pass/fail criteria.
- **Optimisation** is the curation step (5/§4) plus: assertions that fail re-open as inbox items
  (drift detected → re-curate); assertions that pass refresh their "verified against agy <version>"
  stamp. Heuristics aren't auto-tested (soft) — they're reviewed during curation.

---

## Data flow — the auto-training loop

```
everyday driving  ──(agy-learn: sanitise→classify→tag)──▶  knowledge/agy-observations.md (inbox)
        │                                                                │
        │ (clavity ask / await-reply)                                    │ (periodic)
        ▼                                                                ▼
   agy peer  ◀──(driving-agy protocol: one front door + banners)   agy-curate: promote/dedupe/prune
                                                                         │
                                          ┌──────────────────────────────┘
                                          ▼
                          docs/agy-capabilities.md + agy-assumptions.md (canonical)
                                          │
                                          ▼
                       verify/ harness ──(synthetic clavity ask + assert)──▶ pass → stamp
                                          └────────── fail (drift) ─────────▶ back to inbox

   prove in one project ──────────────────────────────────────────▶ promote skills + knowledge to global
```

## Error handling & edge cases

- **agy slow / silent timeout.** `clavity ask` may time out though agy still replies (minute-scale
  latency). The driving skill's recovery note: the reply is recoverable by reading the bus scoped to
  the thread; on a true abort, re-send with a fresh req-id. (Itself an Empirical Assumption to keep
  verified.)
- **Un-generalisable observation.** If `agy-learn` can't strip project specifics into a real rule, it
  declines to capture (better an empty inbox than a polluted one).
- **Contradiction during curation.** Resolve by provenance precedence for the pinned agy version;
  record the `[conflict]` if sources genuinely disagree (matches the existing doc convention).
- **agy version drift.** Curation/verification stamp the agy version; a version bump re-opens the
  testable subset for re-verification (ties into the existing "Refresh after an agy update" runbook).

## Testing

- **Skill dry-runs:** each skill has a worked example in its `SKILL.md` (a raw observation → the exact
  generalised inbox line; an inbox → the exact canonical edit).
- **Verification harness:** the `verify/` suite is itself the test of the *knowledge* (assertions run
  against live agy). A green run = the canonical claims still hold for the current agy version.
- **Loop acceptance:** a documented end-to-end walkthrough — capture an observation, curate it into the
  canonical doc, verify it — proves the loop before any global promotion.

## Deferred (out of scope — "binary not in scope unless compelling")

- **agy's telemetry-footer** (have `clavity ask` append latency/thread/flags to its reply) and
  **`clavity log`** (dump invocation history) — both require Rust binary changes. They would make
  capture *passive* (auto) instead of Claude-judgment-driven. Revisit only with a compelling reason;
  until then capture is deliberate via `agy-learn`.

## Open decisions resolved during brainstorming

- Inbox vs direct-append vs session-sweep → **inbox** (decouples capture/curation; agy + Claude concur).
- Sync vs async invocation → **sync default + async escape hatch**, both on the existing binary.
- Format → **structured markdown** (matches existing docs; greppable).
- Packaging → **new dual-plugin** (distributable via GitHub).
- Binary → **out of scope**; compose existing commands.

## Evidence (this design is grounded in real driving, generalised here)

Observations that seeded the design — already in project-agnostic form, ready as the inbox's first
entries: agy **verifies far better than it discovers** (it surfaced multiple genuine must-fix defects
across several reviews in one session); agy has **minute-scale first-token latency** (sync calls can
time out while the reply still lands on the bus); agy **replies on a new bus thread per request**
(correlate by req-id / replyTo, not by the request's thread); agy **reliably honors a loud REVIEW-ONLY
no-edit banner** but **drifts to execution without one**.
