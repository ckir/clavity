# Golden-header epic — sequencing design

**Date:** 2026-07-21
**Status:** approved (owner), pending implementation plan
**Scope:** the ORDER of the four remaining tasks in the golden-header audience-split epic, the
completion oracle for each, and the design questions each task must settle. This is a SPEC, not a
line-level plan — see [Plan vs spec](#plan-vs-spec-boundary).

## Context

Five commits sit unpushed on `main` (`origin/main` = `6440f4b`):

| Commit | What |
|---|---|
| `e5ef945` | commonmemory ships its plugin manifest (anchored Excludes) |
| `0470832` | `curate-commit` decodes stdin as strict UTF-8, not the console code page |
| `e811ac1` | `[InstallDelete]` retracts the dev marketplace that v7–v10 shipped |
| `417d999` | agy-autotrain's dev-folder excludes anchored |
| `c19a463` | truncated-sequence test + two comment corrections |

A four-round adversarial panel closed GREEN on all of the above. The remaining work is T3–T6.

## Decisions already made by the owner

1. **One release covers the whole epic.** agy challenged this — it argued that two merged,
   user-affecting fixes are held hostage behind T4, a cross-language change with no test coverage
   on the code it modifies. The owner considered the challenge and held the decision. Recorded here
   because the risk is real and should be revisited if T4 turns out to be open-ended: the
   v7–v10 marketplace-hijack retraction stays unshipped for as long as T4 takes.

   **The panel raised this challenge a SECOND time, independently, from a different seat**, arguing it
   contradicts success criterion 5 ("the unpushed window is as short as is compatible"). Formally it
   does not — criterion 5 is explicitly subordinate to criteria 1–4, and yielding is what subordinate
   means. But two independent challenges to one decision is signal, not noise, and the honest statement
   of the tension is this: **the owner's constraint makes criterion 5 the one criterion this sequence
   deliberately sacrifices.** A legitimate choice, made with the cost visible. The re-examination
   trigger is concrete rather than a vibe: **if T4-0 returns answer (b)** — the driver channel cannot
   carry the header — **the epic has materially grown and the split must be reconsidered**, because the
   decision was taken against a smaller T4 than would then exist.
2. **User-facing docs (T6) are a hard gate before any push.**
3. **T4 pins current behaviour before changing it** (T4a/T4b below), rather than writing only
   post-change assertions.
4. **T4 lands in both variants simultaneously.** One curated file driving different behaviour per
   running server is the failure mode.

## The sequence

```
T4-0  →  T5  →  T4a  →  T4b  →  T6  →  RELEASE  →  T3
(spike)
```

### T4-0 — feasibility spike (added after panel round 1)

**This runs before anything else, and it can invalidate the rest of the sequence.**

Determine whether the driver channel can physically carry the golden header. `GoldenHeader.MaxBytes`
is **16 KB**; the `[driver_guidance]` block is described in the knowledge-delivery design as a
**≤150-token nudge**. If that figure is accurate, "route SEED+GROWTH to the driver channel" is not a
routing change — it is a new-channel design, and T4b is a different size of task than this spec
assumes.

The panel's Cascade Analyst raised this as a blocking feasibility threat rather than a deferrable open
question, and that is correct: placing T4b on the critical path of a blocked release without first
validating a basic physical constraint is how a sequence compounds a delay instead of absorbing one.

**Timebox and output.** Read the knowledge-delivery design and `DriverCheatsheet.cs`, confirm or refute
the ≤150-token figure, and produce one of two answers: (a) the channel carries it, T4b proceeds as
specified; or (b) it does not, and T4b is re-scoped — at which point the single-release decision should
be re-examined, because the epic just got materially larger.

### Why this order

Ranked against the criterion the sequence was chosen on:

- **T5 is insurance, and insurance bought after the risk has passed is worthless.** It is
  independent of T3/T4/T6, and it guards the two installer changes already sitting unpushed.
- **T4a before T4b** because a behaviour change with no pre-existing assertion has nothing to catch
  a regression. This session already produced one round-1 panel finding of exactly that shape:
  tests that passed identically with the fix reverted.
- **T6 after T4b** so the docs describe final behaviour and are written once.
- **T3 after the release** because `clavity-ls` on `PATH` is the *installed* binary. Today that is
  v0.3.0, which still contains the CP437 defect, so re-draining now would re-corrupt the file.
  Running it before the release would require invoking the verb from a local build; running it
  after needs no workaround at all. T3 is per-user runtime state, not a repo artifact, so it is not
  part of the release payload and does not gate it.

**Note on T3's ordering:** an earlier candidate put T3 first, on the theory that a clean GROWTH
region improves the agy consults used to design T4. That rationale is weak, but not for the reason
agy gave (it argued T4 routes the header away — which is true only *after* T4 lands, not during its
design). The real reason is empirical: a two-day window of corrupted input produced no identifiable
degradation in peer behaviour, so the benefit was never demonstrated.

## Task specifications

### T5 — installed-tree manifest-parity gate

**Intent.** Assert, in CI, that the `version` field of the **installed** manifest at
`{app}\plugins\<member>\.claude-plugin\plugin.json` equals the version the installer was built as
(the `.iss` `AppVersion`), and that the file **exists at all** — the original defect was absence, not
mismatch, so an assertion that only compares values would pass vacuously on a missing file. Assert
existence first, explicitly.

**Which members.** All five ship a tracked `.claude-plugin/plugin.json`:
`agy-autotrain/`, `commonmemory/`, `clavity-classic/plugin/`, `clavity-dotnet/plugin/`,
`ghidrust/plugin/`. Note the path differs — two members keep it at the member root, three under
`plugin/` — so the assertion is per-member, not one shared glob.

**Why the obvious gate is wrong.** A source-side check comparing `plugin.json` to the `.iss`
`AppVersion` is a tautology for this defect class: the bug was the *packager dropping the file*, so
a source check passes cleanly while the bug ships. agy proposed the source-side gate, was shown the
hole, and conceded it completely. The gate must read the materialized artifact.

**Completion oracle.** Not "the gate passes." The gate must be **observed red twice**, against two
different deliberate breakages, then green once repaired:
1. **Missing manifest** — an exclude that drops the file from the payload. This is the original defect.
2. **Stale version** — the manifest present but holding a version the installer was not built as.

Both are required, and the panel caught why: a red run that only ever removes the file proves the
existence check works while saying nothing about version equality, so a gate exercised that way can
still pass a stale manifest silently. A gate never seen failing has not been shown to be a gate; a
gate seen failing for only one of its two assertions has only been shown to be half of one.

**To verify during planning (NOT yet read):** the five `ci-installer-*.yml` workflows are believed
to install each member already, which would make this an assertion added to an existing install
step rather than new infrastructure. This has not been confirmed by reading them.

### T4a — pin current wire behaviour

**Intent.** Add tests asserting exactly what the peer receives today: the golden header is
prepended to the ask, and the escalation index is present. Both variants.

**Completion oracle.** Temporarily remove the injection and confirm the new tests go **red**. This
is the mutation check that distinguishes a real gate from a tautological one.

**Known gap this closes.** `AgyView.AskAsync` has no unit test at all today; `GoldenHeaderTests`
pins `Apply` and `TryReadCombined` in isolation, which does not constrain what goes over the wire.
agy raised this and it was confirmed.

### T4b — the audience split

**Intent.** The peer receives the **ask payload only**. SEED + GROWTH route to the existing driver
channel instead.

**Load-bearing sites (verified 2026-07-21):**
- `clavity-dotnet/src/Clavity.Ls/AgyView.cs:133` — `GoldenHeader.Apply(header, message)`, the injection.
- `clavity-dotnet/src/Clavity.Ls/AgyView.cs:131-132` — `EscalationIndex` concatenated onto the header.
- `clavity-dotnet/src/Clavity.Ls/AgyView.cs:51-57` — `TryTakeGuidanceBlock`, the existing driver
  channel (once per process, `[driver_guidance]` label).
- `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` — driver-side reader + `BaselineFloor`.
- `clavity-classic/src/golden_header.rs`, `clavity-classic/src/main.rs` — the Rust variant.

**Cross-variant oracle.** `BaselineFloor_matches_the_canonical_core_source` (C#) and
`driver_cheatsheet::tests::baseline_floor_matches_canonical_core_source` (Rust) are the pinning
tests for cheatsheet edits, per `agy-autotrain/skills/agy-curate/SKILL.md:88-92`. If a value looks
wrong, the oracle wins — surface the conflict rather than editing the test.

**T4b supersedes a backlog item — `docs/backlog/golden-header-per-ask-token-optimization.md`.**
That stub (raised 2026-07-11, never started) proposes injecting the header only on the FIRST ask of a
conversation, and measures the current cost: the ~16 KB / ~4k-token header is re-read and re-prepended
on every ask in both variants, so a 20-ask conversation accumulates roughly **80k tokens of repeated
header** in the peer's context. T4b is a strictly stronger version of that proposal — no peer injection
at all — so it captures the whole saving. This gives T4 a concrete, measured benefit it otherwise lacks.

It also **inherits the stub's load-bearing caveat, in a more extreme form.** The stub warns that
per-turn re-injection may be functioning as deliberate reinforcement against peer context drift, and
that "inject once" therefore trades tokens for weaker drift resistance — an empirical question, not a
free win. T4b removes even the turn-1 anchor.

**How far this session's evidence actually goes.** The two-day corruption window is a natural
experiment, and it is weaker than it first appears. The SEED region rendered CORRECTLY; only GROWTH was
mojibake. So what was tested is "garbled GROWTH content, header still present every turn" — not "no
header at all". It is real evidence that GROWTH's per-turn *content* does little work. It is NOT
evidence that removing the header from the peer entirely is safe. Do not let it be cited as if it were.

The panel sharpened this further, and the sharpening is correct: **the SEED region — the foundational
baseline — was legible on every single turn throughout the incident.** The peer was anchored the whole
time. So the experiment gives essentially zero information about behaviour with no baseline present,
which is precisely the state T4b creates. Reasoning from "garbled GROWTH was survivable" to "no
anchor is survivable" is the specific leap this spec must not make.

**Four questions T4b must settle, deliberately left open here.** They require a design pass against
the real code and are not decided by this sequencing spec:

1. **Where `EscalationIndex` goes.** It currently hands the peer absolute local paths. agy's read is
   that it belongs driver-side. Decide explicitly; do not let it fall out of the refactor.
2. **Whether once-per-process driver delivery suffices**, given a SessionStart re-injection path
   already exists. If a long session loses the block, the driver silently stops receiving guidance.
3. **The Rust parity change** — the same split in `golden_header.rs` / `main.rs`, landing together
   with the C# change.
4. **Whether the driver channel can physically carry the payload.** The golden header is capped at
   **16 KB** (`GoldenHeader.MaxBytes`), while the `[driver_guidance]` block it would be routed into is
   described in the knowledge-delivery design as a **≤150-token nudge**. Those are roughly two orders
   of magnitude apart. "Route SEED+GROWTH to the driver channel" may therefore not be a routing change
   at all but a new channel, or it may require a cap/summarisation policy. **This is the single most
   likely reason T4b turns out bigger than it looks, and it must be resolved before implementation
   rather than discovered during it.** Verify the ≤150-token figure against the knowledge-delivery
   design before designing around it.
5. **Whether losing per-turn reinforcement costs drift resistance**, per the superseded backlog stub
   above. If this is judged to need measurement rather than assumption, the measurement is designed in
   T4b's own pass — but note the stub itself concluded the fix "is not obviously safe", so an explicit
   accept-the-risk decision is required either way. Do not let this question be silently dropped.

**Non-goal.** T4b does not change the curation pipeline's routing by SUBJECT (about-the-driver vs
about-agy), which already exists at `agy-curate/SKILL.md:107-109`. The gap being closed is that the
existing split is by subject while the need is by AUDIENCE — GROWTH is full of "about agy" content
that is nonetheless addressed to the driver.

### T6 — user-facing docs

**Intent.** Document the final post-T4b behaviour: what the peer receives, what the driver receives,
and where the golden header now goes. Owner's hard gate before any push.

**Completion oracle.** "Docs describe behaviour as shipped" is a truism, not a test — the panel was
right to reject it. The executable form: **follow the written docs step by step against the freshly
built binary, and confirm the observed system state matches the text at each step.** A doc step that
cannot be followed, or that produces a different result than it claims, is a defect to fix before the
gate passes. Written after T4b so the behaviour being walked through is final.

**T6 also carries three documentation corrections folded in from the roadmap** (see
[Folded from the roadmap](#folded-from-the-roadmap) for the verification behind each):

1. **Close or redirect `docs/backlog/golden-header-per-ask-token-optimization.md`.** T4b supersedes it.
   Left open, it becomes another stale spec describing an optimization that no longer applies.
2. **Strike roadmap item 5, "dotnet golden-header parity follow-ups."** Both divergences it tracks are
   already fixed and test-pinned.
3. **Correct roadmap item 2's threat model (golden-header tamper-detection, 7.4).** As written it is
   false in a way that would misdesign the feature.

### T3 — regenerate the corrupt GROWTH region

**Intent.** Re-drain `~/.clavity/golden-header.growth.md`, which currently holds mojibake
(`ΓÇö` where an em dash belongs). The code fix does not repair an already-corrupt file.

**Precondition.** The released, fixed `clavity-dotnet` must be **installed**, so that `clavity-ls`
on `PATH` carries the strict-UTF-8 decoder. Installing the release is a required step, not an
assumption — a released-but-not-installed binary leaves the old one on `PATH`.

**Completion oracle.** Three conditions, all required:
1. `golden-header.growth.md` byte-verified free of the mojibake signature.
2. Its `.sha256` sidecar verifies against the file.
3. **Content retention** — the file still carries the curated rules, checked by asserting recovery of
   specific known entries, not merely a non-zero length.

Condition 3 exists because the panel pointed out that an **empty file satisfies 1 and 2 perfectly**
while silently destroying the user's accumulated knowledge. Since T3's whole purpose is repairing a
file whose content is already damaged, an oracle that a wipe can pass is worse than no oracle. Note
also that the sidecar cannot detect the encoding defect on its own — it hashes whatever bytes it is
given — so conditions 1 and 3 are doing the real work and 2 only rules out a torn write.

## Folded from the roadmap

Each item below was VERIFIED against the code before being folded — roadmap entries go stale, and two
of these had.

### Folded IN

**1. Per-ask token optimization** (`docs/backlog/golden-header-per-ask-token-optimization.md`) — folded
into T4b, which supersedes it. Detail and the honest limits of the supporting evidence are in T4b above.

**2. Roadmap item 5, "dotnet golden-header parity follow-ups" — STALE, strike it.** It tracks two
dotnet-vs-classic divergences as open. Both are closed:
- *Trim charset* ("dotnet uses full-Unicode `TrimEnd()`; align to ASCII-only"). Already ASCII-only:
  `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:44` defines
  `AsciiWs = { ' ', '\t', '\n', '\v', '\f', '\r' }`, used at `:197` and `:202`, matching classic's
  `ASCII_WS` at `clavity-classic/src/golden_header.rs:173`. It is also cross-variant TEST-PINNED:
  `golden_header.rs:741-742` asserts NBSP (U+00A0, full-Unicode whitespace but not in `ASCII_WS`) is
  left alone, and names the mirroring dotnet test.
- *Sidecar write order/atomicity* ("dotnet writes the sidecar BEFORE the target rename and
  non-atomically"). Already corrected: `GoldenHeader.Commit` writes the header tmp→move first, then the
  sidecar tmp→move, both atomic, with a comment stating it mirrors Rust `commit`.

**3. Roadmap item 2, "Golden-header tamper-detection — 7.4" — threat model is WRONG, correct it.**
The entry claims the sidecar "defends accidental corruption / naive hand-edits only". It does not
defend the most likely accidental corruption. This session's incident is the proof: a console code page
mis-decoded the header on the way in, and the sidecar hashed the ALREADY-CORRUPT bytes, vouching for
them. Mojibake is valid UTF-8, so neither the sidecar nor the strict read-side decode can detect it —
only decoding correctly at the boundary prevents it. 7.4 designed against the current wording would
claim a protection it cannot deliver. The sidecar's real scope is torn writes and byte-level damage.

### Folded OUT (considered, declined)

**Roadmap item 6, "driver-side effectiveness measure."** It becomes more valuable once T4b routes the
header driver-side, and it shares the empirical question named in T4b's open question 4. Declined
anyway: it is a whole verify-harness, and adding it would materially extend an epic that already has a
hard docs gate and an unpushed backlog. Revisit after this epic ships.

## Plan vs spec boundary

This document is a **spec**: intent, contracts, oracles, and open forks. It is forward-writable.

A line-level implementation plan is deliberately NOT included for T5, because the five
`ci-installer-*.yml` workflows have not been read, and authoring "insert after line N" claims about
files nobody has opened produces fabricated precision that later surfaces as phantom design forks.
The plan is produced by the `writing-plans` skill, after reading them.

The code citations in T4a/T4b were verified against the files on 2026-07-21 and are safe to plan
against.

## Risks

| Risk | Mitigation |
|---|---|
| T4 turns out open-ended, holding the merged fixes unshipped indefinitely | The release-split option is recorded above; revisit rather than let the window grow silently |
| T5's gate is written but never observed failing | Its completion oracle requires a deliberate red run |
| T4b changes one variant only | Cross-variant oracle tests named above; both variants in one change |
| T3 run against a stale `PATH` binary re-corrupts the file | Install step is an explicit precondition, and the byte check would catch it |
| The driver channel cannot carry a 16 KB header (T4b question 4) | Resolve BEFORE implementing T4b; it may convert a routing change into a new-channel design |
| T4b ships and the split proves wrong in live use | It is one release; a revert restores per-ask injection in both variants. The T4a pinning tests are what make a revert verifiable rather than hopeful — a second reason to build them first |

## Exhaustiveness audit

Run against this document on 2026-07-21, per the standing self-audit requirement. Gaps found and
closed in-document: (1) T5 did not say WHICH members or that **existence** must be asserted separately
from version equality — the original defect was an absent file, which a value comparison alone would
pass vacuously; (2) T4b did not confront the ~16 KB header vs ≤150-token driver-channel size mismatch,
now raised as open question 4 and a risk; (3) no revert story for T4b, now in the risk table.

Deliberately deferred, with WHERE each resolves: T4b's five open questions resolve in **T4b's own
design pass** against the real code, not here. T5's line-level shape resolves in the **implementation
plan**, after the five `ci-installer-*.yml` files are read — see [Plan vs spec
boundary](#plan-vs-spec-boundary). The ≤150-token driver-block figure is cited from the
knowledge-delivery design and is flagged as **to-verify**, not measured for this document.
