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

## First-pass triage gate (run BEFORE deciding promote/reinforce/contradict/drop — spec §4/§5.C-A)

For EACH pending entry, in order:

1. **Read the two-axis tag** (`(<audience>/<nature>)`, added by `agy-learn`). If an older entry lacks it,
   assign it now: **audience** = does this shape the peer (`peer`) or how you drive it (`driver`)?
   **nature** = a peer judgment tendency (`probabilistic`) or a reproducible tool/bridge behavior
   (`deterministic`)?

2. **Route by the matrix (no entry is ever dropped — spec §4):**
   | audience \ nature | probabilistic | deterministic |
   |---|---|---|
   | **peer** | → golden-header GROWTH (unchanged) | → golden-header GROWTH (a peer behavior is P's, not our code — never "fix the tool") |
   | **driver** | → driver cheatsheet (§ "Compile the core driver-cheatsheet") | → **fix-the-tool backlog** *iff* tool-fixable, else → driver cheatsheet rule |

3. **The determinism refusal gate is MECHANICAL, not honor-system.** To route a `driver/deterministic`
   entry to `fix-the-tool`, you MUST be able to fill BOTH blocks of the backlog schema
   (`docs/fix-the-tool-backlog/_template.md`):
   - **Steps to Reproduce** — the exact reproduction on the owning variant's bridge.
   - **Code-level Mitigation** — the specific change to the bridge/tool *execution path* that removes it.

   If you CANNOT state a concrete **Code-level Mitigation** (the only fix is a *driving move*, e.g.
   "feed the peer ground truth"), then by construction it is NOT tool-fixable → it stays a **driver
   cheatsheet rule**, never a backlog item. Determinism is a PER-VARIANT judgment: the SAME observation
   may be `fix-the-tool` on one variant (its transport exposes the needed signal) and a carried
   `driver` cheatsheet rule on another (its transport cannot) — record which.

4. **Emit the backlog item** for each tool-fixable `driver/deterministic` entry: one file per entry at
   `docs/fix-the-tool-backlog/<slug>.md` from `_template.md` (append-only; never a single shared file —
   offline curate runs on different branches would merge-conflict). Committing the file IS the routing;
   automated ingest into a tracker is a phase-2 hardening, not required here.

Only entries that survive the gate (peer entries, and `driver/probabilistic` + non-tool-fixable
`driver/deterministic` entries) proceed to the promote/reinforce/contradict/drop decision below.

### Retirement is conservative + manual (spec §5.C-D)

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

### Compile the core driver-cheatsheet (spec §5.C-C)

The `driver/probabilistic` entries that survived the gate are the durable driver knowledge. Distil the
variant-agnostic core (peer psychology — identical for both drivers) into a lean ≤ ~150-token / ~3-bullet
cheatsheet. The canonical text lives at `knowledge/driver-cheatsheet.core.md`; keep it in sync there.

**⚠️ THREE files are pinned byte-identical — editing `core.md` alone RED-GATES both binaries.** A pinning
test in each driver asserts its compiled-in baseline equals `core.md` (normalized CRLF→LF, then trimmed).
If you change `core.md` you MUST also update:
- `clavity-classic/src/driver_cheatsheet.rs` → `BASELINE_FLOOR` (single-line `\n` literal)
- `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` → `BaselineFloor` (multi-line `+ "…\n"` concatenation)

Oracles — run BOTH before committing a drain; a drain that reds these is not done:
- `cd clavity-classic && cargo test --all --features test-fakes`
  → expect `test driver_cheatsheet::tests::baseline_floor_matches_canonical_core_source ... ok`
- `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests`
  → expect `DriverCheatsheetTests.BaselineFloor_matches_the_canonical_core_source` passing

Escape the literals mechanically (embedded `"` and em-dashes are easy to corrupt by hand); do not retype
the text through a terminal, whose codepage can mangle non-ASCII characters.

Write the compiled core to the shared runtime path so every driver surface reads ONE file:
`<CLAVITY_GOLDEN_HEADER or %USERPROFILE%\.clavity>\driver-cheatsheet.md`, using the SAME atomic
`.tmp`→rename the golden-header uses (a reader must never see a half-written file). Prefer the binary's
`curate-commit` path if it grows a cheatsheet subcommand; otherwise write the file directly with an atomic
rename. Do NOT lengthen it to cover per-variant transport mechanics — those belong in each variant's
driving skill appendix, not the shared core.

## For each inbox entry — decide

Entries that survive the triage gate above (peer entries, and carried `driver` cheatsheet rules) get one of
these dispositions. A `driver/deterministic` entry already routed to the fix-the-tool backlog is done — it
does not re-enter here; a carried `driver` cheatsheet rule is appended to the cheatsheet, not GROWTH.

- **promote** — into the compiled GROWTH header, subject to the **promotion rubric** below, and only if the
  rule is not already stated in the SEED floor (dedupe — see Inputs).
- **reinforce** — already carried by a prior GROWTH run: GROWTH is regenerated wholesale each run, so just keep
  the strongest phrasing when you recompile.
- **contradict** — conflicts with a SEED claim: prefer **dropping** the candidate (SEED is the driver-owned
  floor) unless you have strong, verified evidence agy's behavior actually changed for the current version; if
  sources genuinely disagree, record a `[conflict]`.
- **drop** — noise, too specific, duplicate, or already covered by SEED. (Dropping a genuinely-noise candidate
  here is a deliberate curation decision; it does not violate the triage gate's no-drop invariant, which
  guarantees every observation is *routed and considered*, not silently lost.)

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
(`%USERPROFILE%\.clavity\golden-header.growth.md`) with an atomic write + a `.sha256` **integrity** sidecar —
NOT a security control (anyone who can rewrite the header can equally rewrite or delete the sidecar); it exists
to catch torn writes, filesystem corruption, and a hand-edited header. It is **verified on read**: absent or
unreadable is accepted unchanged (a fresh install seeds SEED with no sidecar); mismatched or over its own 1 KiB
cap causes that region to be skipped with a warning. Only the binary knows `CLAVITY_GOLDEN_HEADER`. **Pipe the
header via STDIN, never as a shell argument** (a multi-line markdown header blows past command-line
quoting/length limits). GROWTH is **regenerated wholesale** each run, so the commit is idempotent:

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

- **Empty the inbox** (entries are now in GROWTH, the driver cheatsheet, the fix-the-tool backlog, or dropped) —
  reset `## Pending` to empty.
- If the loop has proven out in-project, this is the point to **promote** the skills + knowledge to the
  global config (the trial-then-globalise step).
