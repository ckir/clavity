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

The **determinism test** (R1/F4, refined — the triage gate's refusal criterion): *route to fix-the-tool ONLY when
the defect is fixable **in the software's own execution path** (the bridge/tool code can be changed to remove it).*
A behavior that is reproducible but whose only mitigation is a **driving move**, not a code change (e.g. "peer
confabulates external facts → always feed ground truth"), is NOT tool-fixable → it **stays a driver-cheatsheet
rule**. This closes the third bin: **no observation is ever silently dropped** — every rule lands in exactly one of
{golden-header GROWTH, driver cheatsheet, fix-the-tool backlog}.

## 5. Components

### C-A — `agy-curate` triage gate (agy-autotrain)
`agy-curate/SKILL.md` gains an explicit, **first-pass** triage step before its existing promote/reinforce/contradict/
drop decision: classify each entry on the two axes (§4); for any tool-fixable `deterministic` entry, **refuse
promotion** and emit a fix-the-tool backlog item; only the rest proceed to the audience split (peer → GROWTH as
today; driver-probabilistic → the cheatsheet, C-C). This is the **anti-poisoning gate extended**: it already
rejects unverified/over-general candidates; now it also rejects tool-fixable deterministic-workaround candidates by
*class*.

**Backlog must not be a local black hole (R1/F3):** `agy-curate` runs offline on a user's machine, so a "loose repo
issue note" silently dies there. The refused entry must become a **structured, durable record that reaches the
maintainers** — the concrete mechanism is a fork (F3): a committed repo file the dev pushes, or an emitted GitHub
issue — but NOT a file that never leaves the local `~/.clavity`.

**The gate is instruction-only — a known weakness (R1, carried).** The existing anti-poisoning gate is *also* just
an instruction, and poisoning happened anyway (the three deterministic entries were promoted-by-default). An
instruction-only classifier is gameable (a curator takes the easy "probabilistic → promote" path to avoid filing
tickets). Strengthen it with an objective signal, not prose alone — see F7.

**Delivery depends on curate being RUN — the unclosed forcing-function gap (R1, carried).** Capture is hook-driven
(SessionStart/PreCompact); curate is "deliberate/offline, run when the inbox grows" with **no forcing function**. If
curate lags, nothing is triaged or delivered and the whole fix is inert. Either add a curate-staleness nudge (a
SessionStart hook when the inbox exceeds N entries / an age threshold) or ensure the shipped baseline floor degrades
gracefully so curate-lag is not a hard failure — see F8-b.

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
**Retirement = convert the rule into a standing regression test, not a one-time probe (R1/F5).** When a quirk is
fixed, add a **permanent CI regression test** to the owning product asserting the quirk stays fixed; delete the
human-facing knowledge entry only once that test is green and committed. Because agy is empirically-derived and
mutates (an agy update can re-open a "fixed" quirk), the standing test is what **auto-resurfaces** a regression —
deleting the knowledge without it would leave the driver blind on the next drift. Retire only after the test passes
on **every variant the quirk reproduced on** — a fix on one variant does not license deleting a rule the other
still exhibits (immune-system principle, G3/G4).

### C-C — driver cheatsheet, **push-delivered at point-of-use** (all three products)
The residual `probabilistic` driver knowledge splits into a **variant-agnostic core** (peer psychology, identical
for both drivers: confabulation on external facts; leading-frame/hypothesis bias; "panel ≠ code-review gate";
verify-facts-it-volunteers; hold-your-ground framing) and a small **per-variant appendix** (mechanics true only of
one transport). `agy-curate` compiles the core once into a **lean, curated cheatsheet — ≤ ~150 tokens / ~3 bullets**
(a static blob still becomes wallpaper if it is long — R1/F2); each variant appends its own mechanics.

**Single source + shared runtime path (R1/F1+F8):** `agy-curate` writes ONE core-cheatsheet file to a **defined
shared runtime path** — `%USERPROFILE%\.clavity\driver-cheatsheet.md` (honor the same `CLAVITY_GOLDEN_HEADER`
directory override as the golden-header). All render surfaces read that one file at runtime (no build-time codegen —
it couples release cycles; no hand-sync across repos — highest drift risk). **Ship a baseline floor** in each driver
binary so a MISSING/unreadable file degrades to a shipped default, never to silent nothing (R1 Cascade) — exactly
the golden-header SEED-floor pattern.

Delivery is per-variant because the two drivers have different Claude-facing transports:
- **clavity-dotnet — MCP tools (model-read):** embed the cheatsheet into the tool schema description of **`agy_ask`
  ONLY** (NOT `agy_look`/`agy_status` — that multiplies token bloat on every tool-list and causes context
  blindness, R1/F2). **MCP lifecycle contract (R1, new):** tool descriptions are cached by the client at connect,
  so a file update does NOT propagate until the MCP server re-reads it and emits `notifications/tools/list_changed`
  (or is restarted). The server MUST re-read the shared file and re-emit `list_changed` when it changes, else the
  driver sees a stale cheatsheet — specify this or document staleness-until-restart as an accepted limitation.
- **clavity-classic — CLI only (`clavity ask` over psmux/bus):** no model-read schema, so classic's
  **`clavity-driving` skill** is the primary surface (first-class, not a fallback). Because a skill is *pulled*,
  pair it with a **point-of-use push on the CLI path**: a **`PreToolUse` hook matching the `Bash` tool** that
  regex-detects a `clavity ask` invocation and injects the core cheatsheet. (This IS possible — Claude Code
  PreToolUse hooks fire on the Bash tool and can inspect the command; the repo's own `rtk hook claude` and
  `remote-iteration-breaker.sh` are exactly Bash-PreToolUse hooks. The residual risk is *robustness*, see F6.) The
  push MUST be **stateful — fire once per session/context, not every call** (R1 Activation) or it becomes the
  wallpaper this spec forbids.

## 6. Design forks / open questions

### Resolved in panel round 1 (folded into §4–§5 above)
- **F1 (single source) — CLOSED:** a curate-written file at a shared runtime path
  `%USERPROFILE%\.clavity\driver-cheatsheet.md` (CLAVITY_GOLDEN_HEADER override), read at runtime by every surface;
  build-time codegen and cross-repo hand-sync rejected; missing-file degrades to a binary-shipped baseline floor. (§5.C-C)
- **F2 (size budget) — CLOSED:** ≤ ~150 tokens / ~3 bullets, embedded in **`agy_ask` only**. (§5.C-C)
- **F3 (backlog owner) — CLOSED in principle:** a structured, durable record that reaches maintainers, never a
  local-only file (curate runs offline on the user's box). Concrete form still a small fork below (F3-form). (§5.C-A)
- **F4 (determinism edges) — CLOSED:** only **execution-path-fixable** defects route to fix-the-tool; a behavior
  whose only mitigation is a driving move stays a cheatsheet rule; **no observation is ever dropped**. (§4)
- **F5 (retirement safety) — CLOSED:** retirement = a **standing CI regression test** (auto-resurfaces on agy
  drift), per variant the quirk reproduced on; delete knowledge only once green+committed. (§5.C-B)

### Still open (for round 2+ to pressure)
- **F3-form — the exact backlog artifact:** a committed repo file the dev pushes vs. an emitted GitHub issue vs. a
  section in each product's docs. (Constraint from R1: must escape the local machine.)
- **F6 — classic-variant feasibility + robustness (the load-bearing open fork).** (a) Which of the three quirks
  actually reproduce on classic's psmux-screen-scrape + request/reply-bus transport — established as a **codified
  cross-transport integration test**, not an honor-system manual check (R1 Mechanism Gamer). (b) Does classic's
  transport even EXPOSE a progress signal to distinguish working-vs-stuck? If psmux capture-pane + a request/reply
  bus have no "steps advancing" analogue, the working-vs-stuck fix may be **unimplementable on classic**, and the
  variant-symmetry promise needs a different classic answer (e.g. a longer/configurable idle-wait, or accept a
  residual driver-rule for classic only). (c) The classic CLI-path push is a `Bash`-`PreToolUse` hook + regex —
  **doable** (corrected in R1), but its robustness is unresolved: precise matching (avoid `ask-*`/spacing/variable
  misfire) and once-per-session state.
- **F7 — the triage gate is instruction-only (anti-gaming).** The existing anti-poisoning gate is prose-only and
  poisoning happened anyway; the new determinism gate inherits that weakness. What OBJECTIVE signal makes
  "deterministic → refuse" non-gameable rather than curator honor-system? (e.g. a checklist probe, a required
  linked repro, a second-reviewer gate.)
- **F8 — MCP reload contract:** does the clavity-dotnet MCP server actively re-read the shared cheatsheet file and
  emit `notifications/tools/list_changed`, or is staleness-until-restart an accepted limitation? (§5.C-C names the
  contract; the choice is open.)
- **F8-b — curate has no run-forcing-function.** Capture is hook-driven; curate (hence all delivery) is manual and
  can lag, leaving the fix inert. Add a curate-staleness nudge (SessionStart hook on inbox size/age) vs. rely on
  the baseline floor to degrade gracefully — unresolved.

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
5. Each fixed quirk has a **permanent CI regression test** in its owning product; only after that test is green +
   committed (on every variant it reproduced on) are the trigger entries deleted from the inbox/manuals, leaving no
   tool-fixable `deterministic` driver entries.
6. **No-drop:** a dry-run of the triage gate over the current inbox assigns every entry to exactly one of
   {golden-header GROWTH, driver cheatsheet, fix-the-tool backlog} — zero entries dropped.
7. **Graceful degrade:** with the shared `driver-cheatsheet.md` absent, each driver still delivers its shipped
   baseline floor (no empty tool description / no empty skill section); and the fix-the-tool backlog record from a
   local curate run demonstrably reaches the repo (committed file or emitted issue), not just `~/.clavity`.

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
