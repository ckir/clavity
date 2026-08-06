# Backlog stub — golden-header per-ask token optimization

**Status:** BACKLOG (not started). **Raised:** 2026-07-11 (token-efficiency audit of the agy-knowledge-delivery
design). **Last triaged:** 2026-08-06 (confirmed unstarted — `AgyView.cs:83` still calls
`GoldenHeader.TryReadCombined(dir, Warn)` inside the ask path with no cache or once-per-conversation guard,
and classic does the same at `main.rs:511`; neither driver has changed).
**Scope:** cross-cutting — `clavity-dotnet` + `clavity-classic` (the shared golden-header injection).
**NOT part of** the agy-knowledge-delivery spec (that is driver-facing delivery; this is the peer-facing header).

## Observation (VERIFIED in code)
The golden-header (SEED+GROWTH, capped at 16 KB ≈ ~4k tokens) is **re-read and re-prepended on EVERY ask**, in both
drivers:
- **dotnet:** `clavity-dotnet/src/Clavity.Ls/AgyView.cs:18` documents the dir as "read+prepend **per ask**"; the send
  path (`AskAsync`, ~lines 129–133) calls `GoldenHeader.TryReadCombined(...)` then `GoldenHeader.Apply(header,
  message)` on every ask — no once-per-conversation guard.
- **classic:** `clavity-classic/src/main.rs` `ask` handler (~lines 621–628) calls `golden_header::read_combined(...)`
  (line 621) → `build_payload(...)` (line 628, which internally calls `golden_header::apply(...)` at line 585) on
  every `clavity ask` invocation.

Both drivers reuse a **persistent** conversation / psmux session, so the peer RETAINS prior turns — meaning the ~4 KB
header is re-sent every turn even though the peer already has it from turn 1. Over a 20-ask conversation that is
~80k tokens of repeated header accumulating in the peer's context.

## Candidate optimization
Inject the golden-header only on the **first ask of a conversation** (dotnet: keyed by conversation id; classic:
first ask of a psmux session), relying on the peer's retained conversational history to carry it forward.

## ⚠️ Anti-drift trade-off (load-bearing — do NOT treat inject-once as a free win)
Re-sending the header every turn may be functioning as **deliberate reinforcement against context drift**. A
documented agy behavior: the peer *drifts from / reasons off a superseded context over long conversations* (see the
agy knowledge base / observations). Per-turn re-injection pushes back on exactly that. So "inject once" trades tokens
for possibly **weaker drift-resistance** — a genuine trade-off, not a pure optimization.

**Which wins is an EMPIRICAL question about agy's behavior:** does turn-1-only injection hold up over a long
conversation, or does the peer drift without per-turn reinforcement? Resolving this needs a measurement (a probe /
verify-harness comparing per-turn vs first-turn-only injection over a long conversation), NOT an assumption. This
ties directly to the driver-side **effectiveness-measure** idea raised for the knowledge-delivery spec.

## If pursued
Warrants its own small spec (measure the drift trade-off first; then a per-variant change gated on the result).
Token cost is confirmed real; the fix is not obviously safe. Owner decides priority.
