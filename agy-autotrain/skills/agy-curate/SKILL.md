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

## For each inbox entry — decide

- **promote** — into the compiled GROWTH header, subject to the **promotion rubric** below, and only if the
  rule is not already stated in the SEED floor (dedupe — see Inputs).
- **reinforce** — already carried by a prior GROWTH run: GROWTH is regenerated wholesale each run, so just keep
  the strongest phrasing when you recompile.
- **contradict** — conflicts with a SEED claim: prefer **dropping** the candidate (SEED is the driver-owned
  floor) unless you have strong, verified evidence agy's behavior actually changed for the current version; if
  sources genuinely disagree, record a `[conflict]`.
- **drop** — noise, too specific, duplicate, or already covered by SEED.

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

    # classic variant — `clavity curate-commit` also exists and is tested, but clavity-classic is not yet
    # split-file aware (its parity is release-gated), so until then it writes the legacy flat
    # %USERPROFILE%\.clavity\golden-header.md — which the split-aware binary reads as a one-time migration
    # fallback and a classic install reads directly:
    clavity curate-commit < compiled-growth.md

`curate-commit` (dotnet) writes **only** `golden-header.growth.md`; it never touches the SEED. Do NOT edit the
shared files by hand, and do **not rename or remove** a legacy flat `%USERPROFILE%\.clavity\golden-header.md` if
one is present — the binary reads it as a migration fallback (GROWTH present → legacy ignored), and renaming it
would break a clavity-classic failover that cannot yet read the split files.

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
