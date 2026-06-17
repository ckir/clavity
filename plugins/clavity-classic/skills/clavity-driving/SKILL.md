---
name: clavity-driving
description: Use to drive a live agy peer via the clavity CLI — readiness ping, request shaping, per-mode templates, and cancel/recover.
---

# Driving agy with clavity (v1)

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

## 6. Clarify / cancel / recover
- agy reads the bus only at the START of a turn — it can't ingest new instructions mid-turn.
  To pivot: `clavity cancel` (Escape) + an `alert` `[req_id=…] cancel`, let it idle, then resend.
- **If a terminal locks** (the raw-mode `tmux attach` watch tab), run `clavity cancel` — or any
  `clavity` command — from a DIFFERENT, non-attached shell to drive/unstick agy. Prefer running
  with `AGY_WATCH=0` and observing via `clavity capture` to avoid the lock entirely.
