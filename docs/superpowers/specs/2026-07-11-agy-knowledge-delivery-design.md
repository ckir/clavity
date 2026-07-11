# Design spec — agy-autotrain knowledge **delivery** (close the consume-side gap)

**Status:** DRAFT (pre-AGY-AFTER panel, pre-plan). **Date:** 2026-07-11.
**Spans three products:** `agy-autotrain` (triage/curation) + **BOTH driver variants** `clavity-dotnet` and
`clavity-classic` (each variant's own bridge quirk-fixes + point-of-use delivery). The two drivers are mutually
exclusive but co-equal peers (see the cohesive-distribution work) — any driver-side fix MUST be variant-symmetric,
or the un-fixed variant regresses relative to the other.

## 1. Problem

agy-autotrain's learn-loop is **capture → curate → inject**. It works for *peer-facing* knowledge (the golden-header
is pushed into every request **to the peer P**). It has **no delivery path for driver-facing knowledge** (how to
drive the bridge; peer-driving anti-patterns). `agy-curate` deliberately keeps variant-specific driving mechanics
OUT of the golden-header ("belong in the per-variant core driving skill, not the shared header"), but nothing
forces that skill — or any distilled form — into the **driver's** working context at the moment it drives.

**Concrete failure (2026-07-11):** the driver ran a peer review over the bridge `ask` tool; it timed out
(`possible_modal`) while the peer was still working; the reply parked under a different conversation id; the
trajectory-`look` tool returned a truncated tail. The driver treated this as a *new discovery* and opened the
capture flow — but this exact behavior was **already in the inbox** (three entries, captured weeks earlier). The
knowledge existed and was never delivered; the driver rediscovered it blind and nearly logged a duplicate.

## 2. Root cause (adopted from the agy consult, cascade `0d033d59`)

**An asymmetric delivery contract: push vs pull.** Peer knowledge is *pushed* (header injection). Driver knowledge
is *pulled* (the driver must explicitly invoke a skill). Under cognitive load a driver never pauses to pull generic
docs — so a **pull** model for a **prerequisite** guarantees it is ignored. "Capture-loud / consume-silent" is the
symptom; the push/pull asymmetry is the mechanism.

**Second, load-bearing insight:** capturing *deterministic tool workarounds* as "knowledge" **pollutes** the base.
A mature knowledge system is an **immune system, not a crutch for bad DX** — the durable fix for a deterministic
quirk is to fix the tool, not to deliver the workaround more reliably. The three entries that triggered this failure
are deterministic tool quirks that should never have been knowledge.

## 3. Goals / non-goals

**Goals**
- G1. Driver-facing knowledge that is a *prerequisite* for a bridge action reaches the driver's context **at the
  point of that action**, by **push**, without an intrusive per-call banner that gets tuned out.
- G2. `agy-curate` **triages** every observation and **refuses** to promote deterministic tool-workarounds into any
  knowledge artifact; it routes them to a **fix-the-tool** backlog instead.
- G3. The specific deterministic bridge quirks behind the failure are **fixed in the bridge**, then their knowledge
  entries are **retired**.
- G4. The knowledge base trends toward *probabilistic peer psychology only* (the durable, non-fixable class).

**Non-goals**
- N1. Not changing the golden-header's peer-facing role or the SEED/GROWTH split.
- N2. Not building a general "docs search" — this is targeted point-of-use delivery of a small, curated set.
- N3. Not eliminating the `agy-learn` capture reminder (capture stays; consume becomes symmetric).

## 4. The model — classify every observation on two axes

`agy-learn` (at capture) and `agy-curate` (at drain, the authoritative gate) tag each observation:

- **Audience:** `peer` (shapes P's behavior → golden-header) · `driver` (shapes how the driver drives P).
- **Nature:** `probabilistic` (peer psychology / judgment tendencies — *not* mechanically fixable) ·
  `deterministic` (a reproducible tool/bridge behavior with a reproducible workaround — *a software defect*).

Routing matrix:

| Audience \ Nature | probabilistic | deterministic |
|---|---|---|
| **peer** | golden-header GROWTH (today's path, unchanged) | **fix the tool** (backlog) — do not freeze into the header |
| **driver** | **driver cheatsheet**, push-delivered (§5.C) | **fix the tool** (backlog) — do not carry as knowledge |

The **determinism test** (the triage gate's refusal criterion): *if the quirk AND its workaround are both
reproducible ("if X, then always do Y to recover"), it is deterministic → route to fix-the-tool, do not promote.*

## 5. Components

### C-A — `agy-curate` triage gate (agy-autotrain)
`agy-curate/SKILL.md` gains an explicit, **first-pass** triage step before its existing promote/reinforce/contradict/
drop decision: classify each entry on the two axes (§4); for any `deterministic` entry, **refuse promotion** and
emit a fix-the-tool backlog item (a short, structured note routed to the owning product — here clavity-dotnet);
only `probabilistic` entries proceed to the audience split (peer → GROWTH as today; driver → the cheatsheet, C-C).
This is the **anti-poisoning gate extended**: it already rejects unverified/over-general candidates; now it also
rejects deterministic-workaround candidates by *class*.

### C-B — retire the deterministic entries + fix the bridge (BOTH variants)
The three inbox entries (idle-wait timeout surfaces as `possible_modal` while the peer is still working; the
trajectory-`look` view truncates the recent tail / can report a different conversation id; a timed-out reply parks
and needs a resend to retrieve) are **deterministic**. They were observed on the **dotnet LS/MCP** bridge, but the
same *class* — waiting for a peer turn to go idle, and retrieving its reply — exists on the **classic** bridge
(`clavity ask` / `clavity await-reply` over the psmux doorbell + agentmemory bus). **Per-variant step 0: measure
which of the three quirks actually reproduces on each transport** (do not assume; some may be dotnet-MCP-only, e.g.
the `agy_look` trajectory truncation has no classic analogue if classic has no trajectory-look surface). Then fix
each reproduced quirk in that variant's own bridge, symmetric in intent:
- **working vs stuck:** distinguish by the peer's **advancing step count / progress signal** rather than declaring
  a modal/stuck state purely on an idle-wait elapsed timeout — dotnet: `agy_ask` uses the cascade step-delta;
  classic: `clavity ask`/`await-reply` uses whatever equivalent progress signal the bus/psmux surface exposes.
- **parked-reply auto-retrieval:** on the next bridge call, correlate and return the parked reply (by req-id /
  content) instead of requiring a manual "resend your last result" turn — in each variant's retrieval path.
- (dotnet, optional) `agy_look`: expose a tail-anchored / less-truncated view for reading a just-completed reply,
  or document that `agy_ask` is the retrieval path and `agy_look` is for trajectory inspection only.
Retire a knowledge entry only once the quirk is fixed on **every variant it reproduced on** and its retirement
probe passes (F5) — a fix on one variant does not license deleting a rule the other variant still exhibits
(immune-system principle, G3/G4).

### C-C — driver cheatsheet, **push-delivered at point-of-use** (all three products)
The residual `probabilistic` driver knowledge splits into a **variant-agnostic core** (peer psychology, identical
for both drivers: confabulation on external facts; leading-frame/hypothesis bias; "panel ≠ code-review gate";
verify-facts-it-volunteers; hold-your-ground framing) and a small **per-variant appendix** (mechanics true only of
one transport). `agy-curate` compiles the core once into a **lean, curated cheatsheet — the 3–5 decision-changing
rules, not a dump** (a static blob still becomes wallpaper if it is long); each variant appends its own mechanics.
Delivery is per-variant because the two drivers have different Claude-facing transports:
- **clavity-dotnet — MCP tools (model-read):** embed the cheatsheet into the **tool schema descriptions** of the
  bridge tools (`agy_ask`/`agy_look`/`agy_status`) in the clavity-dotnet MCP server. The model reads a tool's
  description exactly when it is considering that tool → point-of-use push, no hook. (Also render it in dotnet's
  `clavity-ls-driving` skill for the subagent/CLI form.)
- **clavity-classic — CLI only (`clavity ask` over psmux/bus):** a bash command has no model-read schema, so
  classic's **`clavity-driving` skill** is the home. This is NOT a fallback — it is classic's primary and only
  delivery surface, so it is first-class in scope. Because a skill is *pulled*, pair it with a bridge-tool-agnostic
  **point-of-use nudge** for the CLI path (e.g. the front-door seam hook that already fires on agy-facing skills, or
  a PreToolUse hook on the `clavity ask` bash pattern) so classic's driver is pushed the core, not relying on skill
  recall — otherwise classic reintroduces the exact pull-model failure this spec exists to fix.
**Single source (F1):** `agy-curate` writes ONE core-cheatsheet artifact; all surfaces render it — dotnet MCP tool
descriptions, dotnet `clavity-ls-driving`, and classic `clavity-driving` — so the two variants never drift.

## 6. Design forks / open questions (for the AGY-AFTER panel to pressure)

- **F1 — single source of the cheatsheet.** Where does the curated core cheatsheet physically live so ALL THREE
  render surfaces stay in sync without drift — dotnet MCP tool-descriptions, dotnet `clavity-ls-driving`, and
  classic `clavity-driving`? (a curate-written file each surface reads/renders vs. a build-time codegen step vs.
  hand-sync — hand-sync across two separate product repos is the highest drift risk and probably disqualified.)
- **F2 — tool-description size budget.** Embedding a cheatsheet in every bridge tool's description adds tokens to
  every session that lists the tools. What is the acceptable size, and does it go on all three tools or only
  `agy_ask` (the one with the failure modes)?
- **F3 — who owns the fix-the-tool backlog** that C-A routes to, and in what form (a repo issue file? a section in
  a clavity-dotnet doc?) so it is not a black hole.
- **F4 — determinism test edge cases.** Some behaviors are *probabilistic but with a deterministic mitigation*
  (e.g. "peer confabulates external facts → always feed ground truth"). Is the *mitigation's* determinism enough to
  route to fix-the-tool, or is fix-the-tool reserved for cases where the TOOL itself is the defect? (Proposed: only
  a **tool/bridge** defect routes to fix-the-tool; peer-psychology with a driving mitigation stays a driver rule.)
- **F5 — retirement safety.** Deleting a knowledge entry after a "fix" assumes the fix fully removes the failure.
  How do we gate retirement on evidence (a verify-harness probe that the quirk no longer reproduces) so we don't
  delete a rule while the quirk still bites in some path — and, given two variants, on evidence from **each**
  variant the quirk reproduced on (F6)?
- **F6 — variant symmetry vs asymmetric transports.** The two drivers have genuinely different bridges (dotnet
  gRPC LS/MCP with cascade step ids; classic psmux doorbell + agentmemory bus + CLI). Which of the three
  deterministic quirks actually reproduce on classic (measure, don't assume)? Does classic even have a
  trajectory-`look` analogue? And since classic's only delivery surface is a *pulled* skill, is a CLI-path
  point-of-use push (seam hook / PreToolUse on `clavity ask`) mandatory for classic to reach parity with dotnet's
  model-read tool descriptions — or is the driving skill's own front-door hook already sufficient?

## 7. Acceptance criteria (testable)

1. `agy-curate/SKILL.md` documents the two-axis classification and the determinism-refusal gate; a deterministic
   candidate is demonstrably refused (dry-run over the current inbox re-classifies the three trigger entries as
   `driver/deterministic → fix-the-tool`).
2. For **every variant a quirk reproduced on**, that variant's bridge no longer reports a stuck/modal state while
   the peer is progressing (probe per variant: a long peer turn returns a working signal, not a modal signal, as
   long as the progress signal advances). Quirks measured NOT to reproduce on a variant are documented as such.
3. A timed-out reply is retrievable on the next bridge call without a hand-authored resend turn — in **each**
   variant's retrieval path that exhibited the parked-reply behavior.
4. The curated core cheatsheet (≤ the F2 budget), from the single curate-written artifact (F1), is rendered on ALL
   THREE surfaces with identical core content: dotnet `agy_ask` tool description, dotnet `clavity-ls-driving`, and
   classic `clavity-driving`; classic's driver receives it via a point-of-use push, not skill-recall alone (F6).
5. After C-B ships and its probe passes (F5), the three trigger entries are gone from the inbox/manuals and the
   base carries no `deterministic` driver entries.

## 8. Ownership summary

- **agy-autotrain:** C-A (triage gate in `agy-curate/SKILL.md`), the audience/determinism tags in `agy-learn`, the
  single curate-written **core** driver-cheatsheet artifact (F1), entry retirement (C-B second half, gated on
  per-variant probes).
- **clavity-dotnet:** its bridge quirk-fixes (`agy_ask` working-vs-stuck via cascade step-delta + parked-reply
  auto-retrieve; optional `agy_look` tail view), C-C MCP tool-description embedding, and rendering the core in
  `clavity-ls-driving`.
- **clavity-classic:** its OWN bridge quirk-fixes where they reproduce (`clavity ask`/`await-reply` working-vs-stuck
  via the bus/psmux progress signal + parked-reply auto-retrieve), rendering the core in `clavity-driving`, and a
  CLI-path point-of-use push so the pulled skill isn't the only delivery (F6). First: **measure** which quirks
  reproduce on classic before building fixes for ones that don't.
