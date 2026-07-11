---
name: agy-curate
description: Periodic maintenance — drain the agy-observations inbox into the GROWTH region of the shared golden-header, dedupe against the driver-owned SEED, re-verify testable claims, and empty the inbox. Run when the inbox grows or before promoting knowledge to global.
---

# agy-curate — drain the inbox, extend the golden-header GROWTH region

Deliberate and offline. This is the optimiser of the loop. Under the **EXTEND** model it owns **only** the
GROWTH region of the shared golden-header — the driver owns the SEED (the baseline + the agy manuals), which
this skill reads as a floor but never edits.

**Inputs:**
- `../../knowledge/agy-observations.md` — the capture inbox (what you drain).
- The **runtime SEED floor**: the shared `%USERPROFILE%\.clavity\golden-header.seed.md` that the driver
  actually injects (honor a `CLAVITY_GOLDEN_HEADER` **directory** override; default `%USERPROFILE%\.clavity\`).
  Read it to dedupe — a rule already stated in SEED must NOT be repeated in GROWTH. Resolve it at the RUNTIME
  shared path, NOT a repo-relative `../../../seed/…` path: once installed this skill lives under
  `{app}\plugins\agy-autotrain\…`, where a relative hop to `seed/` does not exist. If no `golden-header.seed.md`
  is present yet (a pre-seed install), treat the dedup floor as empty.
- `../../verify/assertions.md` — the probe harness (testable claims still gate here before entering GROWTH).

Under EXTEND you do **not** read or edit the `agy-assumptions.md` / `agy-capabilities.md` manuals — they are
driver-owned static SEED (they ship in each driver's `plugin/knowledge/`), refreshed only on a driver release.

## For each inbox entry — decide (the two-axis triage gate)

Exhaustively sort every inbox entry into exactly ONE of the three bins (spec §5.C-A). Do not drop any entry.

1. **`peer/probabilistic` → promote to the Golden-Header manual.**
   This is durable peer psychology. Subject to the Promotion Rubric below. If promoted, it goes into the compiled `golden-header.growth.md`.
2. **`driver/probabilistic` → the Driver Cheatsheet (carried until fixed).**
   This is a bridge quirk requiring a human driving mitigation because it's not yet fixed in the tool. Append it to `%USERPROFILE%\.clavity\driver-cheatsheet.md` (or the runtime `CLAVITY_GOLDEN_HEADER` path) so it prepends to every session's first ask.
3. **`driver/deterministic` → the Fix-the-tool backlog.**
   This is a software defect fixable in the driver's execution path. **Schema gate:** you MUST write a `Steps to Reproduce` and a `Code-level Mitigation`. If you cannot name a code-level mitigation, it is NOT deterministic — re-tag it `probabilistic` and carry it as a Driver Cheatsheet rule instead. Write the backlog item as a new `.md` file in `docs/fix-the-tool-backlog/` (one file per entry).

*(Note: `peer/deterministic` does not exist — models are not deterministic. Treat as `probabilistic`.)*

**No-drop invariant:** Every entry in the inbox MUST land in one of these three bins. If it is noise, drop it, but deliberate entries must be routed.
**Variant determinism:** A quirk may be deterministic on `clavity-dotnet` (a code fix exists) but probabilistic on `clavity-classic` (no code fix possible, driving mitigation required). Route per-variant.

## Conservative-manual retirement (Driver Cheatsheet)

Emitting a backlog item does NOT strip the corresponding rule from the driver cheatsheet. A carried
workaround rule may be deleted only when **BOTH gates hold (spec §5.C-B + §5.C-D / acceptance 5):**
1. a **permanent CI regression test** for the fixed quirk is **green AND committed** in the owning product,
   on **every variant the quirk reproduced on** (the standing test is what auto-resurfaces the rule if an
   agy update re-opens the quirk — deleting the rule without it would leave the driver blind on the next
   drift); AND
2. the fix is **widely adopted among end-users** (a rule costs ~1 line, so carrying it through the adoption
   tail is cheap and safe).

There is deliberately **no maintainer-side build-time version gate** (curate runs on the maintainer's box,
which always has the newest driver, so a local check would ship a stripped cheatsheet that still bites a
not-yet-updated end-user). Do not remove a carried rule as part of triage; retirement is a separate,
deliberate, later decision — and this MVP does not retire any current entry (the fixes + CI tests are
deferred; see "Deferred work").

## Promotion rubric (curation-fatigue guard — do not skip)

- A **Heuristic** promotes only with **≥2 independent observations across different sessions**
  (one-off impressions stay in the inbox).
- An **Empirical Assumption** promotes only after a **100% pass in the verify harness**:

  > 🛑 STOP: before promoting any Empirical Assumption you MUST open `../../verify/run-verification.md`,
  > physically execute its synthetic `clavity ask` probe against the live agy, and record the real
  > outcome in `../../verify/assertions.md`. Never mark a probe "pass" from memory or assumption.

  If a probe **fails**, that is drift: keep/return the item to the inbox and fix its probe alongside.

## Compile + commit the GROWTH region (via the binary, never a raw edit)

**Migrate a pre-split flat header first (one-time — preserves upgrading users' wisdom, spec Acceptance #4).**
If a legacy flat `%USERPROFILE%\.clavity\golden-header.md` is present **and** no `golden-header.growth.md`
exists yet, this is an upgrading user whose accumulated learned wisdom lives in that flat file. **Before
compiling, read it and FOLD its learned rules into this first GROWTH compile** — dropping anything already
stated in the SEED floor (the old baseline is now driver-owned SEED; keep only the user's learned additions).
Once this run writes `golden-header.growth.md`, the binary stops reading the legacy file (read-precedence), so
this fold is what keeps the wisdom alive — do it with **no user action required**. Leave the legacy file in
place afterwards (do not rename it — panel agy-R3-c).

Compile the dense, payload-ready GROWTH header from the verified, newly-learned inbox rules (plus any folded
legacy wisdom above) — the ones NOT already in the SEED floor:

1. **`[⚠️ CRITICAL ANTI-PATTERNS]` first** for any newly-learned failure modes — knowing how *not* to prompt
   agy is the most actionable context.
2. The handful of newly-learned load-bearing **Empirical Assumptions**.
3. Keep it short — GROWTH is prepended (after SEED) to *every* ask; trim anything not decision-changing.

**GROWTH must fit the REMAINING budget.** The binary injects `SEED + GROWTH` only when their **combined** size
is within the 16 KB cap; over that it silently degrades to SEED-only, so a GROWTH that fits the per-file cap but
overflows the combined cap is written yet **never injected**. Compile GROWTH to fit roughly
`16 KB − (current size of golden-header.seed.md)` — check the seed size and keep GROWTH lean.

Then **commit it through the binary** so it lands at the resolved shared GROWTH path
(`%USERPROFILE%\.clavity\golden-header.growth.md`) with an atomic write + a `.sha256` tamper sidecar — only the
binary knows `CLAVITY_GOLDEN_HEADER`. **Pipe the header via STDIN, never as a shell argument** (a multi-line
markdown header blows past command-line quoting/length limits). GROWTH is **regenerated wholesale** each run, so
the commit is idempotent:

    # dotnet variant — `clavity-ls curate-commit` writes golden-header.growth.md (SEED is left untouched):
    clavity-ls curate-commit < compiled-growth.md      # or: printf '%s' "$growth" | clavity-ls curate-commit

    # classic variant — `clavity curate-commit` writes golden-header.growth.md too (split-file parity landed;
    # SEED is left untouched), identical to the dotnet variant:
    clavity curate-commit < compiled-growth.md

`curate-commit` (both variants) writes **only** `golden-header.growth.md`; it never touches the SEED. Do NOT edit
the shared files by hand, and do **not rename or remove** a legacy flat `%USERPROFILE%\.clavity\golden-header.md`
if one is present — the binary reads it as a one-time migration fallback (GROWTH present → legacy ignored), and
renaming it would defeat that migration for an upgrading user.

**No driver installed?** If no clavity binary is on PATH, still compile and write `golden-header.growth.md`
(create the `.clavity` dir if absent) and emit a **non-blocking** warning — e.g. "no clavity driver detected;
the learned header won't be injected until a driver is installed." Do NOT hard-fail; the capture still has value.

**Variant-agnostic ONLY.** GROWTH carries cross-cutting agy *reasoning* wisdom (anti-patterns, load-bearing
assumptions) — forbid BOTH project nouns AND variant-specific driving mechanics (e.g. `agy_ask` argument shaping
vs `clavity ask` flags). Those belong in the per-variant core driving skill, not the shared header.

**Anti-poisoning circuit-breaker.** You (the curator) are the gate, not a transcriber. Critically evaluate each
candidate before compiling it into a law that shapes every future ask: REJECT a self-reported "learning" that is
unverified, over-general, or a one-off impression — a wrong heuristic frozen into the header poisons every
downstream call. When in doubt, leave it in the inbox.

## Finish

- **Empty the inbox** (entries are now in GROWTH or dropped) — reset `## Pending` to empty.
- If the loop has proven out in-project, this is the point to **promote** the skills + knowledge to the
  global config (the trial-then-globalise step).
