# agy-autotrain — ROADMAP

Enhancement backlog for the agy-autotrain plugin (the thin, driver-composed agy learning loop:
`agy-learn` capture → inbox; `agy-curate` offline drain → the machine-wide golden-header GROWTH region).

Other planning surfaces already exist and are NOT replaced by this file: the external cohesive-distribution
spec (`docs/superpowers/specs/2026-07-11-cohesive-distribution-design.md`, referenced by §-numbers), the
`CHANGELOG.md` (shipped changes), and `docs/fix-the-tool-backlog/` (tool *defects*). This file holds
*enhancement* tasks that fit none of those — one heading per task, newest first.

> **Architectural guardrail (do not violate).** agy-autotrain is deliberately being **thinned** — it does NOT
> own the SEED it injects (the driver plugins do), and capabilities migrate OUT to the drivers, not IN.
> Enhancements here must protect the thin / EXTEND model, never graft standalone-product lifecycle features
> onto it. Reaffirmed by an **AGY-FIRST design consult (2026-07-17)**: the divergence from the sibling
> flaui-mcp plugin is intentional and healthy — port only mechanisms that *mechanically protect* the thin
> architecture; do not "upgrade to match" a standalone product.

---

## AT-1 — Context-pollution hardening for `agy-curate`'s GROWTH region

**Status:** open · **Opened:** 2026-07-17 · **Size:** Part A small / Part B large (see gating fork)

**The goal (what "context-pollution avoidance" means here).** The golden-header GROWTH region is prepended to
*every* agy ask, so anything low-value or off-domain that leaks into it silently taxes every future call. This
task hardens agy-curate so only **dense, relevant, decision-changing** rules reach agy's context, along two
independent axes: **volume** (Part A) and **relevance** (Part B). Both mechanisms are ported in spirit from the
sibling flaui-mcp autotrain loop, which evolved a stricter guard than agy-curate has today. An AGY-FIRST consult
(2026-07-17) confirmed these are the *only* flaui-mcp advances worth porting into a thin / EXTEND plugin — see
"Out of scope" for what was deliberately rejected.

### Part A — Volume: line-density cap + ordered breach + explicit anti-poisoning gate  *(small; markdown-only; do first)*

**Gap.** In `skills/agy-curate/SKILL.md` the *"Compile + commit the GROWTH region"* section (~:119–141) has only
a **coarse 16 KB combined *byte* cap** whose failure mode is a **silent cliff**: if `SEED + GROWTH` exceeds
16 KB the binary silently degrades to SEED-only, so an over-budget GROWTH is written yet **never injected**. The
only guidance is a soft "keep it lean." Separately, the *Promotion rubric* (~:107–117) gates *entry* quality
(Heuristic ≥2 independent observations; Empirical Assumption 100 % verify-harness pass) but there is **no single
explicit anti-poisoning gate**.

**Port** (source: the flaui-mcp repo's `plugins/flaui-mcp/skills/flaui-curate/SKILL.md`, its *"USER promote →
the project-local growth file"* section):
1. A **line-density cap** on the compiled GROWTH region **plus an ordered breach procedure**, placed **in front
   of** the existing 16 KB byte cap so active compression happens *before* the silent-degrade cliff. Adapt the
   exact flaui-curate rule to the GROWTH region (regenerated wholesale each run, prepended after SEED):
   > **HARD CAP: ≤ N lines.** On breach, in order: (1) compress/merge related rules or supersede an old one;
   > (2) drop the lowest-leverage rule.
2. An explicit **anti-poisoning gate**, in flaui-curate's voice, beside the Promotion rubric so a candidate must
   clear **both** the rubric **and** the gate before entering GROWTH:
   > Anti-poisoning gate: you are the gate; when in doubt, drop it.

**Open sub-decision (do NOT fabricate — decide during implementation).** flaui-curate's cap is **≤ 30 lines**,
but that governs a *project-local* file; agy-autotrain's GROWTH is a *machine-wide* header, so re-derive the
budget — e.g. from `16 KB − sizeof(golden-header.seed.md)` at a realistic bytes-per-line — and state the
reasoning.

### Part B — Relevance: project-local learning tier + opt-in promote-to-global  *(large; GATED — resolve the fork below FIRST)*

**Gap.** agy-curate promotes *all* learned wisdom into the **one machine-wide** golden-header, which is then
injected into *every* agy ask regardless of what the user is working on. Domain-specific wisdom (e.g. a C#
desktop-automation rule) therefore pollutes unrelated sessions (e.g. Rust backend work) — the largest
context-pollution source, and the one Part A's volume cap does not address. flaui-mcp's shape: **project-local
growth by default** (a per-project capped file) **+ an explicit user-invoked promote-to-global** step for the
rare genuinely-cross-project rule.

**🛑 GATING ARCHITECTURAL FORK (resolve via AGY-FIRST + user BEFORE building Part B).** For flaui-mcp this is
pure markdown, because its *skill* reads both a project-local and a global growth file. agy-autotrain is
different: the **clavity binary** injects a *single* machine-wide golden-header (`%USERPROFILE%\.clavity\`), and
there is **no per-project injection layer today**. So Part B splits:
- **Capture side (thin, markdown):** a per-project growth file (capped, same anti-poisoning gate as Part A) plus
  a single explicit `agy-promote` skill that copies one rule into the global growth file. This alone is
  in-keeping with the thin model.
- **Injection side (the fork):** actually getting a project-local layer *into agy's context* almost certainly
  needs **clavity-binary support that does not exist** — which would violate agy-autotrain's core "no binary
  changes" property. Questions to settle first: (a) should the binary inject a project-local growth layer atop
  the global header (env/override/CWD-scoped)? (b) if not, a project-local file that never reaches agy's context
  is useless — so is project-local scoping viable for *this* plugin at all, or does it belong on the **clavity
  binary's** roadmap instead of agy-autotrain's? Do NOT implement Part B until this is decided.

### Acceptance

- **Part A:** `agy-curate/SKILL.md` states an explicit line-density cap + ordered breach procedure *ahead of*
  (not replacing) the 16 KB byte cap, and an explicit anti-poisoning gate on GROWTH entry. No binary change, no
  new verb/file; EXTEND model untouched. `CHANGELOG.md` updated.
- **Part B:** only after the gating fork is resolved. If it proceeds, the capture side ships as markdown + an
  `agy-promote` skill; any injection-layer work is tracked separately (likely against the clavity binary).

**Explicitly out of scope** (the divergence is intentional — see the guardrail; reaffirmed AGY-FIRST 2026-07-17):
maintainer-edit-canonical mode; a `status` introspection verb; version lockstep; backlog↔xUnit regression
coupling. **Do NOT port these.**

**Provenance.** flaui-mcp ↔ agy-autotrain A/B comparison (2026-07-17); AGY-FIRST consult (agy: Part A "Rank 1 —
best fit"; Part B "Rank 2 — good fit, protects the global header from domain-specific pollution"); the folding
of both into one context-pollution task, and this ROADMAP location, were user-decided. "Token savings" in the
originating discussion = this context-pollution-avoidance logic (NOT the machine-wide `rtk` proxy).
