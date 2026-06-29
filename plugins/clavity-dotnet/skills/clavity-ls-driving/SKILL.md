---
name: clavity-ls-driving
description: Use to drive a paired agy peer via the clavity-ls MCP tools (agy_look / agy_status / agy_ask) — when to look vs ask, write/quota semantics, and handling waiting/modal results.
---

# Driving agy with clavity-ls (MCP)

You (Claude) drive a paired agy over its Language Server via three MCP tools exposed by `clavity-ls`:

- **`agy_look`** — read the active conversation's bounded trajectory. No quota; safe to call freely.
- **`agy_status`** — lightweight liveness + step count.
- **`agy_ask`** — send a message and return agy's reply. **This is a quota-consuming WRITE** that posts a
  human-visible message in agy's tab. Use it for an independent second-model review / generative design
  partner — not for chatter. Prefer `agy_look` when you only need to observe.

## Results you must handle

- **`waiting_for_human`** — agy is up but has no conversation yet. STOP and wait for the human to start or
  continue the agy session; do NOT loop-retry.
- **`possible_modal`** — the idle-wait hit the client timeout; agy may have a blocking modal open. Surface it
  to the human; do not assume a silent failure or retry blindly.

## Task-assignment protocol — what stops agy misfiring

<!-- KEEP IN SYNC WITH clavity-driving (plugins/clavity-classic/skills/clavity-driving/SKILL.md) -->

agy is bold and acts on what you give it. Frame the task precisely:

- **Review / red-team / consult → loud REVIEW-ONLY banner.** Open the payload with a 🛑 banner that
  forbids edits/commits and **enumerates** the forbidden actions (no file writes, no git, no bridge
  task). Without it, agy will *execute* a task you meant as a review. End with explicit permission to
  return "no blockers."
- **Phase isolation.** Never mix research and implementation in one payload. Tag
  `[PHASE: EXPLORATION]` (gather/opine, no build) **or** `[PHASE: EXECUTION]` (build to a spec) — mixing
  fills agy's context with raw search output and degrades the build.
- **Mandatory checkpoint for mutating delegations.** If you delegate a task that changes files, the
  payload must instruct agy to make a recoverable checkpoint (`git stash` / temp branch) **before**
  touching the tree.
- **Delegated implementation → name the oracle + the done-condition + "no scope creep."** Seed the
  exact invariants/tests that define correct; tell it to STOP and report rather than adapt on a mismatch.
- **Seed invariants, don't ask it to "find bugs."** agy verifies far better than it discovers; give it
  the specific things to confirm/refute and permission that "no must-fix is valid."

## Injection is automatic — do NOT prepend the golden header yourself

`clavity-ls` reads `%USERPROFILE%\.clavity\golden-header.md` (when the agy-autotrain add-on is installed) and
prepends it to every `agy_ask` for you. Do NOT read or prepend it manually. If the file is absent (add-on not
installed), the binary simply skips it and you drive with this baseline protocol.

If the human asks you to permanently remember a project rule and no `agy-curate` skill is present, permanent
learning needs the **agy-autotrain** add-on — tell them to re-run the clavity installer and tick it.
