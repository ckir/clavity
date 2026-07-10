---
name: clavity-driving
description: Use to drive a live agy peer via the clavity CLI — readiness ping, request shaping, per-mode templates, multi-lens review panels, and cancel/recover.
---

# Driving agy with clavity

Claude drives a live, signed-in `agy` peer in the same folder. Payloads travel over the
**agentmemory signal bus** (your `memory_signal_send` / `memory_signal_read` tools); the
**doorbell** (`clavity ring`) wakes agy. The `clavity` binary provides the psmux/state
plumbing + the `[req_id]` convention. **Correctness rests on the bus, not the TUI** — a
state misread only affects ordering (a doorbell sent while agy is busy is queued).

## 0. Readiness — gate first contact
- `clavity state` → expect `idle`/`busy` (not `dead`; if `dead`, ask the human to start agy).
- agy loads its MCP servers (agentmemory) a few seconds AFTER launch, so its idle prompt can
  appear before the bus is up. Gate first contact on a bus round-trip:
  `clavity ping`  (sends `[ping]` + ring + blocks for `READY`; exit 0 = agy + bus live).

## 1. One-shot round-trip
`clavity ask "<instruction>"` mints a req-id, posts to the bus, rings, blocks for agy's
correlated reply, and prints it. Add `--review-only` for a no-edit / consult ask.

## 2. Route by capability
agy is an external, multi-model peer — treat picking it like choosing a subagent tier. Route
TO agy for an independent second-model perspective (divergent review, design input, async
orchestration). KEEP on Claude mechanical sweeps / well-specified implementation. Pick the
model for the task (`--model`): deep reasoning → a Thinking/High model; bulk → Flash Low/Med.

## 3. Request shape — DO
- Lead with an imperative goal; list the exact file paths in scope; give a Definition of Done /
  how to verify; state guardrails ("Do NOT modify X").
- Carry your own context — separate context windows; paste the relevant trace/snippet/types.
- Front-load ALL targets (agy parallelizes tool calls in a turn); for review-only say
  "Just REPLY on the bus — do NOT write or edit files."

## 4. Request shape — AVOID
- Vague scope ("fix the bug") — give the error/trace or the precise mismatch.
- **Line numbers** — agy's edits need exact string matches; target function names / snippets.
- Interactive confirmations — agy replies only when done or blocked.
- Parallel edit calls to the SAME file (they race and corrupt) — tell agy to use ONE
  multi-chunk edit call instead.

## 5. Per-mode templates
- **Review / red-team:** "Just REPLY — do NOT edit." Sections: `### Goal` · `### Files in Scope`
  · `### Invariants to Verify` · `### Guardrails`. Give invariants to check, not "find bugs".
- **Generative design:** "Brainstorming mode. No implementation code." Sections: `### Current
  Design` · `### Problem` · `### Options Explored` · `### Desired Output`.
- **Scoped implementation:** "Implementation mode. Edit files; run the verification before
  reporting done." Sections: `### Goal` · `### Files to Edit` · `### Reference Context` ·
  `### Verification`.
- **Async orchestration:** "Orchestration mode. Launch the background task and await your
  reactive wakeup; do not poll." Sections: `### Command` · `### Working Directory` ·
  `### Success Criteria`.

## Task-assignment protocol — what stops agy misfiring

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

## Convening a review panel — see the panel skill

For a formal multi-seat review of a high-leverage artifact, the panel procedure — trigger gate, the seat
palette, running rounds, verify-before-folding, the PANEL VERDICT — lives in the transport-agnostic
**`adversarial-panel-review`** skill (shipped in this same plugin). Invoke it when you finish or
materially edit a high-leverage spec/plan/design, or need an adversarial multi-seat teardown. Route the
panel over `clavity ask --review-only` (the review transport above). The everyday driving discipline (the
task-assignment protocol above, and the consult-first/review-after/verify decision loop below) stays
here — it applies to every agy delegation, not just formal panels.

## agy is a peer, not an oracle — the decision loop

The value of a paired agy is a *second model* on your work. Two disciplines get most of it, and one caveat
keeps it honest:

- **Consult FIRST on hard forks.** On a real design/scope/approach/sequencing fork, get agy's read BEFORE you
  commit — but the **human owns the decision**: hand them BOTH agy's recommendation AND your own. Never
  delegate the final call to agy.
- **Review AFTER you author.** When you finish a spec, plan, or design, proactively route the finished
  artifact to agy (`clavity ask --review-only`, or a full panel) BEFORE presenting it to the human — don't
  wait to be asked.
- **Verify, never rubber-stamp.** agy is bold and states confident false claims. Confirm any bare factual
  claim by measurement before acting, and fold agy's findings together with your OWN assessment.

<!-- KEEP IN SYNC WITH clavity-ls-driving (plugins/clavity-dotnet/skills/clavity-ls-driving/SKILL.md) — task-assignment protocol + peer-decision-loop (transport idioms differ: classic uses `clavity ask`, dotnet uses `agy_ask`) -->

## Prepend the golden header (manual — until the classic binary injects it)

Before sending any payload, prepend the contents of `%USERPROFILE%\.clavity\golden-header.md` (the
compiled agy-driving wisdom) when that file exists; if it is absent or empty, silently skip it (the
agy-autotrain add-on simply isn't installed). Do this **manually**: unlike the dotnet `clavity-ls`
binary — which auto-injects — the classic `clavity` binary does not yet read the header, so the skill
prepends it. (This manual step is removed once the classic binary injects on its own in a later release.)

If the human asks you to permanently remember a project rule and no `agy-curate` skill is present,
permanent learning needs the **agy-autotrain** add-on — tell them to re-run the clavity installer and
tick it.

## 6. Clarify / cancel / recover
- agy reads the bus only at the START of a turn — it can't ingest new instructions mid-turn.
  To pivot: `clavity cancel` (Escape) + an `alert` `[req_id=…] cancel`, let it idle, then resend.
- **If a terminal locks** (the raw-mode `tmux attach` watch tab), run `clavity cancel` — or any
  `clavity` command — from a DIFFERENT, non-attached shell to drive/unstick agy. Prefer running
  with `AGY_WATCH=0` and observing via `clavity capture` to avoid the lock entirely.
