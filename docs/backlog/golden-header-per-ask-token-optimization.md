# Backlog stub — golden-header per-ask token optimization

**Status:** BACKLOG (not started). **Raised:** 2026-07-11 (token-efficiency audit of the agy-knowledge-delivery
design). **Scope:** cross-cutting — `clavity-dotnet` + `clavity-classic` (the shared golden-header injection).
**Last triaged:** 2026-08-06 — 🔴 **HALF RESOLVED, and the scope is now clavity-classic ONLY.**
**dotnet: the peer-facing per-ask header is GONE.** `AgyView.cs:178-181` (`AskAsync`) reads *"T4b (audience
split): the golden header (SEED+GROWTH) and escalation index are DRIVER guidance, not peer-facing content —
they no longer reach the wire"*, and sends `var outgoing = message;` unmodified. The surviving
`GoldenHeader.TryReadCombined` call at `AgyView.cs:83` is inside `TryTakeGuidanceBlock()`, gated at
`AgyView.cs:71` by `Interlocked.Exchange(ref _guidanceDelivered, 1) != 0` — **once per process, to the
driver, not per ask to the peer.**
**classic: STILL LIVE.** `main.rs:597` `build_payload` is *"golden header (outermost) + … instruction"*,
called by `ask` at `:643` with `read_combined` at `:892`, so every `clavity ask` still prepends it.
**NOT part of** the agy-knowledge-delivery spec (that is driver-facing delivery; this is the peer-facing header).

## Observation (VERIFIED in code — as of 2026-07-11; half of it has since expired, see Last triaged)
The golden-header (SEED+GROWTH, capped at 16 KB ≈ ~4k tokens) is **re-read and re-prepended on EVERY ask**, in both
drivers — **true for classic today, no longer true for dotnet:**
- **dotnet:** ~~`AgyView.cs:18` documents the dir as "read+prepend **per ask**"; the send path (`AskAsync`,
  ~lines 129–133) calls `GoldenHeader.TryReadCombined(...)` then `GoldenHeader.Apply(header, message)` on
  every ask — no once-per-conversation guard.~~ **SUPERSEDED — no longer true.** T4b (the audience split)
  removed the header from the peer wire entirely; `AskAsync` now sends the raw ask. Kept struck through
  rather than deleted because this bullet was labelled *VERIFIED in code* and was believed for weeks —
  deleting it would erase the evidence that a "verified" claim expired without anyone noticing.
- **classic:** `clavity-classic/src/main.rs` `ask` handler (~lines 621–628) calls `golden_header::read_combined(...)`
  (line 621) → `build_payload(...)` (line 628, which internally calls `golden_header::apply(...)` at line 585) on
  every `clavity ask` invocation.

Both drivers reuse a **persistent** conversation / psmux session, so the peer RETAINS prior turns — meaning the ~4 KB
header is re-sent every turn even though the peer already has it from turn 1. Over a 20-ask conversation that is
~80k tokens of repeated header accumulating in the peer's context.

## Candidate optimization
Inject the golden-header only on the **first ask of a conversation** (classic: first ask of a psmux session),
relying on the peer's retained conversational history to carry it forward. **The dotnet arm is moot** — T4b
went further than this stub proposed and stopped sending the header to the peer at all.

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
