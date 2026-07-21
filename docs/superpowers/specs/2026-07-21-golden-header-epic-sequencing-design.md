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
   trigger was concrete rather than a vibe: **if T4-0 returns answer (b)** — the driver channel cannot
   carry the header — **the epic has materially grown and the split must be reconsidered**, because the
   decision was taken against a smaller T4 than would then exist.

   **RESOLVED. The trigger fired, the decision was re-opened, and the constraint was re-confirmed.**
   T4-0 returned a qualified (b): the channel cannot carry the header as it stands, but the remedy is
   three scoped edits (see [T4-0 result](#t4-0--feasibility-spike-run-and-resolved)), not a new-channel
   design. So the premise behind the re-examination trigger — "the epic just got materially larger" —
   turned out to be false, and the single-release constraint now rests on stronger evidence than when it
   was first taken. Two further findings from the re-open, both measured, are recorded because they
   bear on the sequence rather than on the release: **T6 does not gate the six unpushed commits** (no
   doc surface documents anything they change), and **T4 does not make the corrupt `growth.md` moot** —
   `GoldenHeader.cs:159` reads it regardless of audience, so T4 changes the file's consumer, not its
   corruption. This fork is closed; do not re-open it without new evidence.
2. **User-facing docs (T6) are a hard gate before any push.**
3. **T4 pins current behaviour before changing it** (T4a/T4b below), rather than writing only
   post-change assertions.
4. **T4 lands in both variants simultaneously.** One curated file driving different behaviour per
   running server is the failure mode.

## The sequence

```
✅ backup  →  T4-0  →  T5  →  T4a  →  T4b  →  T6  →  RELEASE  →  ⏸ install  →  T3
(done)        (done)                                              (manual)
```

The **backup comes first, not inside T3**, and is already done. T4b's work involves deliberately
exercising the over-cap driver-channel path, which means editing a local `growth.md`; ordering the
backup as a sub-step of the final task would leave the only copy of the corrupt-but-recoverable corpus
exposed for the whole epic. See [T3](#t3--repair-the-corrupt-growth-region) for the paths.

**The sequence is not required to be linear.** Pausing between steps to run a one-off task by hand —
installing a release, invoking a verb from a local build, fixing up state — is an intended and
supported way to execute this, not a deviation from it. The `⏸ install` step above is the one such
pause the sequence *depends* on: see [T3's precondition](#t3--regenerate-the-corrupt-growth-region)
for why a released-but-not-installed binary silently re-corrupts the file.

### T4-0 — feasibility spike (RUN AND RESOLVED)

This ran before anything else, because it could have invalidated the rest of the sequence. It did not.
The panel's Cascade Analyst raised it as a blocking feasibility threat rather than a deferrable open
question, and that was correct — placing T4b on the critical path of a blocked release without first
validating a basic physical constraint is how a sequence compounds a delay instead of absorbing one.

**The spike's own premise was wrong.** The `[driver_guidance]` block was described as a **≤150-token
nudge**; that figure describes the *content* of the baseline floor, not any cap. The channel's real
mechanical cap is **4 KB** — `DriverCheatsheet.MaxBytes` (`clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs`)
and `driver_cheatsheet::MAX_BYTES` (`clavity-classic/src/driver_cheatsheet.rs:8`), the two variants
agreeing. The gap is therefore 1.67×, not the two orders of magnitude this spec assumed.

**Measured** (`%USERPROFILE%\.clavity`): `golden-header.seed.md` 2,067 B + `golden-header.growth.md`
4,755 B = **6,822 B** of header against a **4,096 B** channel cap. `driver-cheatsheet.md` is 1,139 B
today. `GoldenHeader.MaxBytes` is 16 KB, applied per region (`golden_header.rs:104`).

**Answer: a qualified (b).** The channel cannot carry the header as it stands — it is already 1.67×
over, and GROWTH grows by design, so it will not start fitting. But the remedy is bounded, and T4b
remains a routing change rather than a new-channel design. Three questions T4b must answer:

1. **Raise the cap in lockstep across both variants — and NOT to 16 KB.** The obvious-looking answer is
   wrong. `MaxBytes` is enforced **per region**, not on the composition: `try_read_file` applies it once
   for SEED and once for GROWTH (`golden_header.rs:104`, called per file), so a fully-loaded composed
   header is bounded at **32 KB**, before `EscalationIndex` is appended at `AgyView.cs:131-132`. A 16 KB
   driver cap would therefore be under-sized by more than 2× at the worst case while looking, in the
   diff, like it matched. Derive the value from the composition bound, and write the derivation into a
   comment beside the constant so the next person does not re-make this mistake.
   ⚠️ **The 6,822 B figure from T4-0 must NOT be used to size this.** It is one measurement from the
   maintainer's box; `growth.md` is per-user accumulated data, so a heavier user's file is larger and a
   fresh install's is near-empty. Size against the enforced bound, never the observed sample.
   ⚠️ **Nothing today asserts the two constants are equal.** `DriverCheatsheet.MaxBytes` (C#) and
   `driver_cheatsheet::MAX_BYTES` (`driver_cheatsheet.rs:8`) are independent literals with no
   cross-variant parity test — the existing parity test at `driver_cheatsheet.rs:101-107` covers the
   baseline *text*, not the cap. Raising one and forgetting the other produces exactly the
   one-file-two-behaviours failure that constraint 4 exists to prevent, and it fails silently. Add the
   parity assertion as part of this change, not after it.
2. **Replace the over-cap failure mode — this is the spike's real finding, and it is not about size.**
   `DriverCheatsheet.Read` handles over-cap by returning `BaselineFloor` with only a warning (Rust:
   `driver_cheatsheet.rs:22-24`, pinned by a test at `:82-83`). Today that is benign, because the file
   is a small static cheatsheet and the baseline is a reasonable stand-in for it. Once this channel
   carries GROWTH, the same branch means **every accumulated observation is silently replaced by a
   hardcoded paragraph** the moment the payload crosses the line — data-loss-shaped, not
   truncation-shaped, and invisible at the call site. Raising the cap without changing this behaviour
   moves the cliff rather than removing it.
3. **Confirm the delivery-semantics change is deliberate — and price the staleness window it opens.**
   `TryTakeGuidanceBlock` fires once per process (`AgyView.cs:54`, `Interlocked.Exchange`); the golden
   header is currently applied on every ask (`AgyView.cs:133`). This spec already intends
   once-per-process, so the change itself is a confirmed consequence rather than a surprise. What the
   spec previously missed — round-2 panel, State Corruptor — is its effect on the autotrain feedback
   loop: **a drain that lands while the MCP server is running becomes invisible until that process
   restarts.** Today's per-ask read has no such window; the next ask picks the new content up.
   *Correcting the panel's mechanism:* `curate-commit` is a deliberate maintainer drain
   (`just drain-knowledge`), not something the peer performs mid-conversation, so this is a
   latency regression on a human-initiated operation rather than a live read-after-write race. That
   makes it smaller than the panel argued, but not nothing: the drain-then-observe cycle is exactly how
   this loop is validated, and "restart the server first" becomes a required, documentable step.
4. **Keep the two readers strictly isolated — do NOT reuse `DriverCheatsheet.Read` for the header.**
   Round-2 panel, Cascade Analyst, and it is the sharpest finding of the round. `BaselineFloor` is
   *driver-cheatsheet* content — four static reminders about driving the peer. It is a sane stand-in
   for a missing cheatsheet and a nonsensical one for a missing golden header. If T4b routes SEED+GROWTH
   through that reader, then any over-cap or unreadable header silently injects the driver cheatsheet
   **in place of** the accumulated corpus, and the substitution is invisible at the call site because
   both paths return a plausible-looking string. Note this compounds item 2: raising the cap without
   separating the readers moves the cliff instead of removing it, and leaves a wrong-document fallback
   sitting behind it.

Note that `driver-cheatsheet.md` is a third file, independent of seed/growth. T4b may reuse the
once-per-process *mechanism* without routing through that file — and per item 4, it should.

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

**Assert the extracted values are non-empty BEFORE comparing them.** Round-3 panel, Mechanism Gamer.
The natural implementation pulls `AppVersion` out of the `.iss` and `.version` out of the installed
`plugin.json` and compares. If either extraction silently yields empty — a regex that stops matching
after a formatting change, a `jq` path that no longer resolves — the comparison degenerates to
`"" == ""` and the gate reports GREEN while comparing nothing. That failure is worse than no gate,
because it is a gate everyone believes is watching. Both extractions must be asserted non-empty and
well-formed (a version-shaped string) as separate, individually-failing checks before equality is
evaluated. Note this is the same defect-class as the existence check above, one level up: there, an
absent file passed a value comparison vacuously; here, an absent *value* does.

**To verify during planning (NOT yet read):** the five `ci-installer-*.yml` workflows are believed
to install each member already, which would make this an assertion added to an existing install
step rather than new infrastructure. This has not been confirmed by reading them.

**Confirm they INSTALL, not merely BUILD — and confirm the install is unattended.** Round-4 panel,
Activation Auditor. The assumption above is load-bearing in a way the wording understates: this whole
task asserts against `{app}`, a path that only exists if an installer actually ran. If the workflows
only compile `.iss` files into `dist/`, then `{app}` is never materialized and the new assertion either
fails confusingly or — worse, if written defensively — skips itself and reports green. And an Inno
installer invoked without `/VERYSILENT /SUPPRESSMSGBOXES` will sit on a GUI prompt no one can see,
hanging the job until it times out. So the planning step has three questions, not one: do the workflows
run the installer at all, do they pass unattended flags, and does the resulting `{app}` path match what
the assertion will read? Answer all three by reading the files before writing a line of the gate.

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

1. **Which driver-side destination `EscalationIndex` gets — not *whether* it moves.** Round-3 panel,
   Axiom Breaker: this question was previously phrased as "where does it go", which contradicts T4b's
   own intent. If the peer receives the ask payload ONLY, then an index that today hands the peer
   absolute local paths (`AgyView.cs:131-132`) cannot stay where it is — that answer is already
   excluded by the constraint, and leaving it nominally open invites a circular design pass. The live
   question is narrower: which driver-side channel carries it, or is it dropped entirely?
2. **Whether once-per-process driver delivery suffices — the failure is broader than a long session.**
   Round-3 panel, Cascade Analyst. `_guidanceDelivered` is guarded by `Interlocked.Exchange`
   (`AgyView.cs:54`) on an `AgyView` registered as `AddSingleton` (`Program.cs:38`), so the flag latches
   for the **entire lifetime of the language-server process**, not of a conversation. Every conversation
   after the first that shares that process receives **no** driver guidance at all. The earlier framing
   here — "if a long session loses the block" — understated this materially.
   *Correcting the panel's scope:* its claim that this starves "every subsequent conversation on the
   machine" is too strong. MCP stdio servers are spawned per client, so a separate Claude Code session
   gets a separate process and a fresh flag. The real blast radius is conversations sharing one server
   process — which includes the common case of continuing work after a context clear.
   This must be resolved against the **existing SessionStart re-injection path**, which is the
   mitigation the original phrasing gestured at: determine whether that path can re-arm the flag, and if
   it cannot, once-per-process is the wrong mechanism for content this load-bearing.
3. **The Rust parity change** — the same split in `golden_header.rs` / `main.rs`, landing together
   with the C# change.
4. **Whether the driver channel can physically carry the payload — ANSWERED by T4-0, but it left three
   sub-decisions.** The channel's cap is 4 KB, not a ≤150-token nudge, and the header measures 6,822 B,
   so it does not fit as-is. See [T4-0](#t4-0--feasibility-spike-run-and-resolved) for the measurements.
   T4b must decide: (a) the new cap value, in lockstep across both variants; (b) what replaces the
   silent `BaselineFloor` fallback on over-cap, which is the dangerous part and is independent of
   whatever cap is chosen; (c) nothing else — this is no longer a threat to T4b's size.
5. **Whether losing per-turn reinforcement costs drift resistance**, per the superseded backlog stub
   above. If this is judged to need measurement rather than assumption, the measurement is designed in
   T4b's own pass — but note the stub itself concluded the fix "is not obviously safe", so an explicit
   accept-the-risk decision is required either way. Do not let this question be silently dropped.

**Completion oracle.** Round-5 panel, Oracle Auditor: T4b was the ONLY task in this spec with no
completion oracle at all, while carrying the epic's entire point. Every other task had one, which is
exactly how the gap survived four rounds. Four conditions, all required:

1. **Invert T4a's pins.** The tests T4a wrote to assert the header IS in the peer payload must be
   flipped to assert it is NOT, and must be seen failing against the pre-T4b code. This is what makes
   T4a's investment pay: the pins prove the change landed at the wire, not just in a unit under test.
2. **Prove the driver actually receives the block over the live MCP wire** — not merely that a function
   returns it. An implementer can satisfy every unit test while the block never reaches the client,
   because `TryTakeGuidanceBlock`'s output must survive the MCP tool-result path (`McpTools.cs:23`,
   `AgyAsk`) to be worth anything. Observe it arriving in a real session.
3. **Both variants, same curated file, same observable outcome.** This is constraint 4 made checkable:
   run the same `growth.md` through the C# and Rust servers and diff what each sends the peer.
4. **The over-cap path does not silently substitute.** Feed a deliberately over-cap header and confirm
   the failure is loud and does NOT inject `BaselineFloor` in the header's place (question 4 above).

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

### T3 — repair the corrupt GROWTH region

**Intent.** Repair `~/.clavity/golden-header.growth.md`, which currently holds mojibake
(`ΓÇö` where an em dash belongs). The code fix does not repair an already-corrupt file.

⚠️ **"Re-drain" is the WRONG verb, and the round-4 panel was right to reject it.** This spec previously
said re-drain, which implies the content is regenerated from an upstream source. **There is no upstream
source.** `agy-curate/SKILL.md:194-195` ends every drain with "**Empty the inbox** — reset `## Pending`
to empty", so the observations that compiled into today's GROWTH are gone. The corrupt `growth.md` is
the **only surviving copy of its own content**. A cold successor following the old wording would run the
drain against an empty inbox and confidently overwrite the only copy with near-nothing.

**What actually repairs it: a DETERMINISTIC transform, not a curate pass and not an LLM.** An earlier
draft of this section said "curate pass … fix the mojibake at the content level", and the round-5 panel
was right to reject that too: it replaces an impossible mechanical task with an unreliable cognitive
one. Asking a model to verbatim-retranscribe 4.7 KB invites summarisation, padding, and silent drops —
and it would pass the oracle below while destroying content, because a model can drop the mojibake,
invent plausible bullets to satisfy a count, and preserve the one string the check names.

The damage is a pure byte-level transformation and is exactly invertible. The original UTF-8 bytes were
decoded as CP437 into characters and re-encoded as UTF-8; reversing it is: **decode the file as UTF-8 →
encode those characters as CP437 → decode the resulting bytes as UTF-8.**

**Two safety properties make this safe to run on the only copy, and BOTH must be asserted at runtime,
before anything is written:**
1. **Strict-encode guard.** Encode with a CP437 encoder configured with `EncoderFallback.ExceptionFallback`.
   The default encoder silently substitutes `?` for any character CP437 cannot represent — which would
   destroy data invisibly. If the strict encode throws, the file is NOT purely CP437 mojibake, the
   transform does not apply, and the repair must **abort**, not proceed.
2. **Bijection check.** Re-mangle the repaired text (encode UTF-8 → decode CP437) and assert it
   reproduces the original file **byte-for-byte**. If it does, the transform is a bijection on this
   exact data, so it provably cannot have lost anything.

**Measured on the live corrupt file, 2026-07-21** — this is verification already performed, not a
prediction: strict encode **succeeded** (4,684 bytes, so every character is CP437-representable);
round-trip **exact**; U+0393 count **22 → 0**; **15** em dashes and the warning sign recovered; **0**
U+FFFD replacement characters. Sample of the repaired text: `GROWTH region — newly-learned agy-driving
wisdom` and `[⚠️ CRITICAL ANTI-PATTERNS — newly learned, additive to SEED]`.

**The decoder fix is a precondition, not the repair.** `0470832` stops the commit path creating *new*
mojibake. It does not touch bytes already on disk. Both halves are required: repair the bytes
deterministically, and write them through a binary that will not re-mangle them on the way out.

**Precondition — an explicit MANUAL step, not something the sequence performs.** The released, fixed
`clavity-dotnet` must be **installed**, so that `clavity-ls` on `PATH` carries the strict-UTF-8 decoder.
A release pipeline publishes artifacts; it does not install them on the executing machine, so a
developer running this sequence linearly would hit T3 with the OLD binary still on `PATH` and quietly
re-corrupt the file. **The sequence is not required to be linear**: pausing after RELEASE to install by
hand, or invoking the verb from a local build output instead of `PATH`, are both acceptable and are the
intended way to satisfy this.

**Verify the binary FUNCTIONALLY, not by version string.** Round-3 panel, Dependency Cynic, and it
overturns this spec's previous instruction to check `clavity-ls --version`. That check is worthless for
the local-build path this same paragraph endorses: a dev build reports a static, unbumped version
(`0.3.0`-shaped) that is identical before and after the fix, so a stale local build passes the check
while carrying the CP437 decoder. The only sound precondition is a **functional probe**: pipe a
multi-byte character (an em dash is the natural choice) through the verb into a scratch
`CLAVITY_GOLDEN_HEADER` directory and confirm it round-trips as U+2014 rather than `ΓÇö`. That probe
tests the decoder itself, which is the actual precondition; the version string is a proxy for it and a
broken one.

**Back up the corrupt file — ✅ DONE, and deliberately moved to the FRONT of the sequence.**
Round-3 panel (Blindspot Auditor) required the backup; round-5 panel (Ordering Skeptic) then showed it
was ordered fatally late as a sub-step of the LAST task. T4b's own work involves exercising the
over-cap driver-channel path, which means deliberately bloating or editing a local `growth.md` — so the
old ordering left the single un-backed-up copy exposed across the entire epic. The backup is not a T3
step; it is a **precondition of the whole sequence**, and it has been performed:

    ~/.clavity/golden-header.growth.md.corrupt-backup-2026-07-21          (4,755 B, byte-identical)
    ~/.clavity/golden-header.growth.md.sha256.corrupt-backup-2026-07-21

Both verified byte-identical to their sources at copy time. The names deliberately do not match any
path the reader resolves — `SeedPath`, `GrowthPath`, or `LegacyFileName` (`GoldenHeader.cs:27-29`,
`:37-38`) — so the copies are inert and cannot be picked up as a region. This backup is also the fixed
reference the completion oracle compares against, which is what makes condition 1 below a repair
verification rather than a standing rule.

**Completion oracle.** Three conditions, all required:
1. **Every U+0393 sequence present in the BACKUP is absent from the repaired file** — a one-shot
   comparison against the pre-repair copy, NOT a standing invariant on the file.
   The signature is exact and scannable: every CP437 mojibake family in the currently-corrupt file leads
   with U+0393 (GREEK CAPITAL LETTER GAMMA, UTF-8 `CE 93`) — `ΓÇö` (em dash, **15 occurrences**),
   `ΓÜá∩╕Å` (warning emoji), `ΓåÆ` (→), `Γëñ` (≤), `Γëá` (≠). Scanning for the one lead codepoint covers
   all five, where scanning for `ΓÇö` alone would pass a file still carrying the other four.
   ⚠️ **Why it must be scoped to the backup diff rather than written as "zero Γ in the file".** Round-4
   panel, Regression Archaeologist, and the finding is sharp: this spec is read by the same agent that
   curates the corpus, and the corpus is an accumulating memory of observed defects. An observation
   about *this very bug* — "the CP437 defect produced Γ-led sequences" — is exactly the kind of entry
   the loop is designed to capture, and curating it would legitimately introduce Γ into GROWTH. A
   standing "zero Γ" gate would then fail forever, by the system working as intended. Anchoring the
   check to "what the backup contained" makes it a repair verification with a fixed reference, which
   cannot be invalidated by later legitimate content.
2. Its `.sha256` sidecar verifies against the file.
3. **Content retention — now PROVEN, not sampled.** Re-mangle the repaired file (encode UTF-8 → decode
   CP437) and assert the result is **byte-identical to the backup**. Because the transform is a
   bijection on this data, that single assertion proves nothing was lost, added, reordered, or
   summarised — it is strictly stronger than any count-and-spot-check.
   This replaces an earlier "bullet count ≥ pre-repair count, plus one named entry survives verbatim"
   condition, which round 5 correctly shot down: that condition was designed against an *LLM* repair,
   and a model can satisfy it while destroying the corpus — drop the mojibake, invent plausible bullets
   to make the count, preserve the one string the check names, and pass. The count-based oracle was
   only ever necessary because the proposed mechanism was untrustworthy. With a deterministic
   transform, the mechanism carries its own proof, and the weaker check is not worth keeping.

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
| T4 turns out open-ended, holding the merged fixes unshipped indefinitely | RETIRED by T4-0: T4b is three scoped edits across two variants, not an open-ended design. The release fork was re-opened on this basis and the single-release constraint re-confirmed |
| T5's gate is written but never observed failing | Its completion oracle requires a deliberate red run |
| T4b changes one variant only | Cross-variant oracle tests named above; both variants in one change |
| T3 run against a stale `PATH` binary re-corrupts the file | Install step is an explicit precondition, and the byte check would catch it |
| The driver channel cannot carry the header (T4b question 4) | MEASURED by T4-0: it cannot — 6,822 B against a 4 KB cap. Remedy is bounded (raise the cap in both variants). The residual risk is not the size but the silent `BaselineFloor` fallback on over-cap, which discards all accumulated wisdom rather than truncating; T4b must replace it |
| T4b ships and the split proves wrong in live use | It is one release; a revert restores per-ask injection in both variants. The T4a pinning tests are what make a revert verifiable rather than hopeful — a second reason to build them first |

## Exhaustiveness audit

Run against this document on 2026-07-21, per the standing self-audit requirement. Gaps found and
closed in-document: (1) T5 did not say WHICH members or that **existence** must be asserted separately
from version equality — the original defect was an absent file, which a value comparison alone would
pass vacuously; (2) T4b did not confront the header-vs-driver-channel size mismatch, raised as open
question 4 and a risk, and since **measured** by T4-0; (3) no revert story for T4b, now in the risk table.

**The audit's own to-verify flag paid off, and in the direction that matters.** It flagged the
≤150-token driver-block figure as cited-not-measured. When T4-0 measured it, the figure was **wrong** —
it describes the baseline floor's content, not a cap, and the real cap is 4 KB. Two conclusions this
document had drawn from it (that the mismatch was two orders of magnitude, and that T4b was therefore
likely a new-channel design) were both false, and the second of those was load-bearing for the
release-sequencing decision. Recorded because it is the generalisable lesson: an unmeasured figure
inherited from another document had propagated into a risk rating, an open question, and a
decision-re-examination trigger before anyone opened the file that defines it.

Deliberately deferred, with WHERE each resolves: T4b's remaining open questions resolve in **T4b's own
design pass** against the real code, not here. T5's line-level shape resolves in the **implementation
plan**, after the five `ci-installer-*.yml` files are read — see [Plan vs spec
boundary](#plan-vs-spec-boundary).
