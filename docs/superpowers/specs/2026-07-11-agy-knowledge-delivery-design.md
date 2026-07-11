# Design spec — agy-autotrain knowledge **delivery** (close the consume-side gap)

**Status:** DRAFT (pre-AGY-AFTER panel, pre-plan). **Date:** 2026-07-11.
**Spans two products:** `agy-autotrain` (triage/curation) + `clavity-dotnet` (bridge quirk-fixes + point-of-use delivery).

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

### C-B — retire the deterministic entries + fix the bridge (clavity-dotnet)
The three inbox entries (idle-wait timeout surfaces as `possible_modal` while the peer is still working; the
trajectory-`look` view truncates the recent tail / can report a different conversation id; a timed-out reply parks
and needs a resend to retrieve) are **deterministic**. Fix them in the bridge, then **retire the entries**:
- `agy_ask`/`ask`: distinguish **working vs stuck** by the peer's **advancing step count** (poll step-delta) rather
  than declaring `possible_modal` purely on an idle-wait elapsed timeout; only surface a modal/stuck signal when
  steps are **not** advancing.
- Parked-reply **auto-retrieval**: on the next bridge call, correlate and return the parked reply (by req-id /
  content) instead of requiring a manual "resend your last result" turn.
- (Optional) `agy_look`: expose a tail-anchored / less-truncated view for reading a just-completed reply, or
  document that `ask` is the retrieval path and `look` is for trajectory inspection only.
Once shipped, the corresponding knowledge entries are deleted from the inbox/manuals (immune-system principle, G3/G4).

### C-C — driver cheatsheet, **push-delivered at point-of-use** (both products)
The residual `probabilistic` driver knowledge (peer confabulation on external facts; leading-frame/hypothesis bias;
"panel ≠ code-review gate"; verify-facts-it-volunteers; hold-your-ground framing for negotiation) is compiled by
`agy-curate` into a **lean, curated cheatsheet — the 3–5 decision-changing rules, not a dump** (a static blob still
becomes wallpaper if it is long).
- **MCP transport (main-thread bridge tools):** embed the cheatsheet into the **tool schema descriptions** of the
  bridge tools (`agy_ask`/`agy_look`/`agy_status`) in the clavity-dotnet MCP server. The model reads a tool's
  description exactly when it is considering that tool → point-of-use push, no hook.
- **CLI transport (`clavity ask`, used by subagents):** a bash command has no model-read description, so the
  per-variant **driving skill** remains the home for the CLI path; keep the same curated cheatsheet content in sync
  there (single source: `agy-curate` writes one artifact, both surfaces render it).

## 6. Design forks / open questions (for the AGY-AFTER panel to pressure)

- **F1 — single source of the cheatsheet.** Where does the curated driver cheatsheet physically live so BOTH the
  MCP tool-descriptions and the CLI driving skill render the same content without drift? (a curate-written file the
  MCP server reads at startup to compose its tool descriptions vs. a build-time codegen step vs. hand-sync.)
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
  delete a rule while the quirk still bites in some path?

## 7. Acceptance criteria (testable)

1. `agy-curate/SKILL.md` documents the two-axis classification and the determinism-refusal gate; a deterministic
   candidate is demonstrably refused (dry-run over the current inbox re-classifies the three trigger entries as
   `driver/deterministic → fix-the-tool`).
2. The bridge no longer reports `possible_modal` while the peer's step count is advancing (probe: a long peer turn
   returns a working signal, not a modal signal, as long as steps climb).
3. A timed-out reply is retrievable on the next bridge call without a hand-authored resend turn.
4. The bridge `agy_ask` tool description contains the curated driver cheatsheet (≤ the F2 budget), sourced from the
   single curate-written artifact (F1); the CLI driving skill renders the same content.
5. After C-B ships and its probe passes (F5), the three trigger entries are gone from the inbox/manuals and the
   base carries no `deterministic` driver entries.

## 8. Ownership summary

- **agy-autotrain:** C-A (triage gate in `agy-curate/SKILL.md`), the audience/determinism tags in `agy-learn`, the
  single curate-written driver-cheatsheet artifact, entry retirement (C-B second half).
- **clavity-dotnet:** C-B bridge quirk-fixes (`agy_ask` working-vs-stuck + parked-reply auto-retrieve), C-C MCP
  tool-description embedding; the per-variant driving skill renders the cheatsheet for the CLI path.
