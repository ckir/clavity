# Hardening & Golden-Header Completion — epic decomposition

> **What this is.** The next development group after the clavity-classic v0.1.0 installer epic, chosen 2026-06-30
> (agy-consulted + user-approved). It is an EPIC of four sequenced sub-projects, each getting its own
> spec → plan → implementation cycle. This doc captures the **sequence + the one non-obvious dependency**; the
> per-item designs live in their own specs.

## Why this group (not the alternatives)

Classic just absorbed a large v0.1.0 change — let it soak. Pivot to **dotnet correctness** + **completing the
just-shipped golden-header subsystem**. These two themes are braided by the sidecar contract (item #5 is both a
dotnet-hardening fix AND the prerequisite for the cross-variant tamper-detection #2). `clavity --restart-agy`
(backlog #1) is deferred to the next cycle — it mutates classic's process-lifecycle and classic should stabilize
first.

## The sequence (and the gate)

1. **Dynamic send-model resolution (dotnet)** — *first, by RISK; no dependencies.* The live-write path hard-codes
   a version-specific agy model-id enum (`MODEL_GEMINI_3_1_PRO_HIGH = 1037`). When agy bumps its model
   definitions, the live-write **silently breaks**, on a schedule we don't control. Resolve the id dynamically
   from the running agy instead. This is a latent critical bug, not mere polish — do it first regardless of theme.
2. **dotnet golden-header parity** — *second; the linchpin.* Align dotnet's `GoldenHeader.Apply` trim to classic's
   canonical **ASCII-only** whitespace set, and make the `.sha256` sidecar write **after-move/atomic** (classic is
   the proven oracle). The atomic-sidecar half is a hard **prerequisite for #2**.
3. **Golden-header tamper-detection (both variants)** — *third; safe ONLY after #2-parity.* At read-time, compare
   `golden-header.md` to its `.sha256` sidecar: a loud plain-English warning on mismatch, a subtle active-marker
   otherwise. Honest threat model — defends accidental corruption / naive hand-edits only (a same-user adversary
   rewrites both; accepted boundary).
4. **Packaging verifications (dotnet)** — *last; low-code cooldown.* Confirm the dual-plugin format scopes the
   driving skill to Claude and the pairing skill to agy; confirm agents don't auto-update a path-installed plugin
   off the version-pinned `{app}` binary.

### ⚠️ The dependency to honor: #5 (atomic sidecar) gates #2 (tamper-detection)

If read-time tamper-detection ships before dotnet writes the sidecar atomically, a crash or power-loss **mid
sidecar-write** leaves a **torn `.sha256`** → the next read sees header ≠ sidecar → a scary **false "tampered!"
warning** over what was just a crash. Classic already writes the sidecar atomically (it is the oracle), so this
race is specifically **dotnet-side** — which is exactly why the dotnet atomic-sidecar fix (part of parity, the 2nd
item) must land before the cross-variant tamper-detection (3rd item).

## Out of scope (this epic)

- `clavity --restart-agy` (backlog #1) — deferred to the next cycle.
- Any new classic feature work — classic soaks after v0.1.0.

## Per-item specs (to be authored, in order)

Each item below gets its own `docs/superpowers/specs/…` + plan when it reaches the front of the queue. We start
with #3 (dynamic send-model resolution).
