# Backlog stub — golden-header per-ask token optimization

**Status:** ✅ **RESOLVED / OBSOLETE — closed 2026-08-06. Superseded by the audience split, in BOTH drivers.**
**Raised:** 2026-07-11 (token-efficiency audit of the agy-knowledge-delivery design).
**Original scope:** cross-cutting — `clavity-dotnet` + `clavity-classic` (the shared golden-header injection).

**Why it is closed.** The optimization this stub proposed — inject the header once per conversation instead
of per ask — was overtaken by a larger change that stopped sending the header **to the peer at all**. The
golden header is now DRIVER guidance, not peer-facing content, so the per-ask token cost this stub exists
to reduce is **zero on both drivers**, not merely smaller.

- **dotnet:** `AgyView.cs:178-181` (`AskAsync`) — *"T4b (audience split): the golden header (SEED+GROWTH)
  and escalation index are DRIVER guidance, not peer-facing content — they no longer reach the wire"* —
  then `var outgoing = message;`, sent unmodified. The surviving `GoldenHeader.TryReadCombined` at
  `AgyView.cs:83` is inside `TryTakeGuidanceBlock()`, gated at `AgyView.cs:71` by
  `Interlocked.Exchange(ref _guidanceDelivered, 1) != 0` — once per process, **to the driver**.
- **classic:** `main.rs:641-647` — *"The PEER gets the ask only — never the golden header, never the driver
  cheatsheet"* — passes `&golden_header::HeaderState::Absent` into `build_payload`. The `inject_golden`
  flag documented at `main.rs:623-628` now *"gates only whether the DRIVER guidance block is emitted to
  stdout"*, once per session via the `.active-drive-session-*` file flag.

🔴 **Triaged wrong TWICE on 2026-08-06 before this, both times by the same mistake, and both caught by an
adversarial peer rather than by me.** First: "confirmed unstarted", from a grep hit at `AgyView.cs:83`
whose enclosing method I never opened. Second: "half resolved, classic still live", from citing
`read_combined` at `main.rs:892` — which is inside `fn doctor()` (`main.rs:859`), a diagnostic surface, not
the ask path. **Both readings cited real lines and both were false.** The lesson is recorded in
`docs/backlog-triage-runbook.md` §2: a grep result is a list of lines, not a verdict — open the enclosing
function and find the caller. This entry is the case that earned it.

**NOT part of** the agy-knowledge-delivery spec (that is driver-facing delivery; this was the peer-facing header).

## Observation as written 2026-07-11 — ⚠️ ENTIRELY SUPERSEDED, kept as the record

> **Everything in this section was true when written and is false today.** It is struck through rather than
> deleted because it was labelled *VERIFIED in code* and stayed believed for weeks after it stopped being
> true — deleting it would erase the evidence that a "verified" claim can expire with nobody noticing,
> which is the whole reason the triage discipline exists.

~~The golden-header (SEED+GROWTH, capped at 16 KB ≈ ~4k tokens) is **re-read and re-prepended on EVERY
ask**, in both drivers:~~
- ~~**dotnet:** `AgyView.cs:18` documents the dir as "read+prepend per ask"; the send path (`AskAsync`,
  ~lines 129–133) calls `GoldenHeader.TryReadCombined(...)` then `GoldenHeader.Apply(header, message)` on
  every ask — no once-per-conversation guard.~~
- ~~**classic:** the `ask` handler (~lines 621–628) calls `golden_header::read_combined(...)` →
  `build_payload(...)`, which internally calls `golden_header::apply(...)`, on every `clavity ask`.~~

~~Both drivers reuse a persistent conversation / psmux session, so the peer RETAINS prior turns — meaning
the ~4 KB header is re-sent every turn even though the peer already has it from turn 1. Over a 20-ask
conversation that is ~80k tokens of repeated header accumulating in the peer's context.~~

**Today: neither driver sends the header to the peer, so the accumulation is zero, not reduced.**

## Candidate optimization — ⚠️ MOOT, do not implement
~~Inject the golden-header only on the **first ask of a conversation**, relying on the peer's retained
conversational history to carry it forward.~~ **Both drivers went further than this and stopped sending the
header to the peer entirely.** An engineer taking this instruction literally today would find nothing to
change: dotnet sends the raw ask, classic passes `HeaderState::Absent`.

## ⚠️ Anti-drift trade-off (load-bearing — do NOT treat inject-once as a free win)
Re-sending the header every turn may be functioning as **deliberate reinforcement against context drift**. A
documented agy behavior: the peer *drifts from / reasons off a superseded context over long conversations* (see the
agy knowledge base / observations). Per-turn re-injection pushes back on exactly that. So "inject once" trades tokens
for possibly **weaker drift-resistance** — a genuine trade-off, not a pure optimization.

**Which wins is an EMPIRICAL question about agy's behavior:** does turn-1-only injection hold up over a long
conversation, or does the peer drift without per-turn reinforcement? Resolving this needs a measurement (a probe /
verify-harness comparing per-turn vs first-turn-only injection over a long conversation), NOT an assumption. This
ties directly to the driver-side **effectiveness-measure** idea raised for the knowledge-delivery spec.

## If pursued — nothing to pursue here
~~Warrants its own small spec (measure the drift trade-off first; then a per-variant change gated on the
result). Token cost is confirmed real; the fix is not obviously safe. Owner decides priority.~~

**The token cost is no longer real** — it is zero on both drivers. This stub is closed.

**What did NOT get answered, and is the only thing worth carrying forward:** the anti-drift question above
was never measured. The audience split removed the per-ask header for a *different* reason (audience, not
tokens), so it settled the cost question by making it moot while leaving the behavioural one open — **does
the peer drift more now that nothing re-reinforces the curated context per turn?** That is a probe for the
verify harness, not a backlog item about token cost, and it belongs with the agy assumption probes if
anyone wants it.
