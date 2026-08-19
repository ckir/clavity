# Stage 2 fix batch — design

**Status:** **fully owner-ruled as of 2026-08-11.** The three negotiated decisions (D1, D2, D3) plus F1,
F6 and F17 are all settled; **no decision remains open** and nothing in the batch waits on the owner.
**Branch:** `feature/injected-context-governance` (46 ahead of `origin/main`, nothing pushed).
**Inputs:** the Stage 2 sweep — 10 rounds, 15 verified findings, plus R5-O2 and F17. Run report
`.clavity/scratch/stage2-scope/round-1.md`; negotiation outcome `.clavity/scratch/fixbatch/converged.md`.

## Goal

Close **17** findings over `agy-autotrain/`, `ghidrust/` and `commonmemory/` — the **15** the Stage 2
anomaly sweep produced, plus **R5-O2** (surfaced by the sweep, initially dropped from this spec and restored
by panel round 1) and **F17** (surfaced while verifying a peer measurement during the F1/F6 negotiation) —
without invalidating the AGY-CAPSTONE GREEN held at `06a39afe47ae479bcba5101e7142e63f188f9031`.

## The governing constraint

An **implementation-source** change to `scripts/check-injected-context.ps1` invalidates that GREEN and
forces a full re-capstone of the gate. **Every decision below is deliberately shaped to avoid one.** The
batch changes the gate's COMMENTS and its two config files' TEXT, never its behaviour. If a later decision
reverses that, the re-capstone cost lands in one place (Group D) rather than being smeared across the batch.

**The rule this batch relies on, stated explicitly because it is load-bearing.** The capstone-invalidation
rule names an *implementation-source refactor*. This batch edits the gate's **comments** and its two config
files' **text**, and adds **tests**. None changes what the gate computes. **Therefore `06a39af` stands.** If
the owner reads that rule more strictly — any byte of `check-injected-context.ps1` invalidates it — then
D1 step 2 and the Group D comments must move into a single re-capstoned commit, and the batch cost rises by
one full capstone. **This is the owner's call and is not assumed silently.**

**Success criterion for the batch:**
1. `just test-scripts-fast` green — **backgrounded** (~696 s, over the 600 s tool cap). Read the
   `Tests Passed:` line; its absence is an aborted run, not a pass.
2. `bash scripts/check-seed-artifacts-synced.sh` exit 0.
3. `pwsh -File scripts/check-injected-context.ps1` exit 0 — **and this alone proves nothing, because the
   gate already exits 0 today.** Each new test added by this batch must be shown non-vacuous by a
   **logic mutant** that turns exactly that test red, per the project's standing rule that a guard which
   fails open certifies what it stopped checking.
4. Every one of the **17** findings (15 from the sweep + R5-O2 + F17) is either closed here or recorded in
   `docs/coverage-debt.md` with its compensation **and a code anchor whose disappearance voids the entry** —
   that file's own contract, which a bare "deferred, see spec" would violate.
5. **F1, F6 and F17 are all OWNER-RULED as of 2026-08-11 and are closed in this batch, not deferred.**
   Nothing in the batch now depends on a pending decision.
   *(This criterion previously carried a deferral escape hatch, which peer panel round 10 correctly found
   was declared but unwired. The hatch is now moot — there is nothing left to defer — and the two
   conditional rows it required have been removed from the deferred table.)*
6. 🔴 **`cd ghidrust && just test` green — the criterion the peer panel found MISSING, and it is the one
   that matters most.** `just test-scripts-fast` is a **PowerShell** suite: it runs no Rust tests at all.
   Group B is the **only** group that changes executable behaviour (`--emit` output), so without this
   criterion the batch could report GREEN on criteria 1-3 with the `--emit` strip wrong, the oracle failing
   to compile, or the byte comparison red — and nobody would know. Run it after commit 4.
   *(The peer reached this from a superseded quote — it read the draft that placed the oracle in the
   Ghidra tier, which panel round 2 had already corrected. The quote is stale; **the defect is not**, because
   `test-scripts-fast` would not have run the oracle in either tier. Folded on the surviving substance.)*

---

## The three negotiated decisions

### D1 — F9: `.iss` references are never resolved

**Measured.** `$ShippedExtensions` (`check-injected-context.ps1:390`) omits `iss`, so
`Test-IsPathCandidate:423` drops every `.iss` token before `Resolve-Reference`. `$AssertPrefixes:427`
nevertheless lists `'installer/'`, and `installer/` holds 5 `.iss` files to 1 `.ps1`. Bypassing only the
allowlist, 8 `.iss` references reach resolution and 2 fail — both `installer/_shared/plugin-registration.iss`,
at `commonmemory/ROADMAP.md:21` and `:31`, and **both are correct prose about a deleted file.**

**Decision.** Do not add `iss`. Do not add an exemption. Instead:

1. Rewrite the two `commonmemory/ROADMAP.md` references so a deleted file is not cited as a live
   backticked path. A backticked path conventionally means "this exists and you can act on it"; a dead one
   is a reader-level defect independent of the gate.
   **Exact replacement text, because "reword it" is where the peer failed twice — it proposed two
   rewrites, caught itself that the first still contained backticks, then produced a second that also did:**
   - `:21` — replace `` `installer/_shared/plugin-registration.iss` `` with
     *"the former Inno-Pascal registrar under installer/_shared/"* — **no backticks at all**.
     🔴 **The peer panel was right to push here and my first draft was half a fix.** I had kept the bare
     filename in backticks and justified it on gate mechanics (`Test-IsPathCandidate` rejects it anyway).
     But D1's own rationale is that **backticks signal "this exists and you can act on it"** — that argument
     applies to a bare filename exactly as it applies to a path. Keeping backticks would have fixed the
     gate concern I was not even relying on, while leaving the reader-level defect this decision exists to
     remove.
   - `:31` — replace the sentence with
     *"The Inno-Pascal registrar under `installer/_shared/` has been deleted; the Pascal implementation no
     longer exists."* The **directory** reference ends in `/`, which `Test-IsPathCandidate` skips by rule
     (`$Token.EndsWith('/')` → `return $false`), so it is stable regardless of any future `iss` decision.
   **Verify after editing:** re-run the resolver over `commonmemory/ROADMAP.md` and confirm the
   path-candidate count drops from 5 with 0 failures to 5 with 0 failures **and** that neither replacement
   string is extracted as a candidate.
2. Add a comment beside `$AssertPrefixes` recording the real boundary: `installer/` is asserted only for
   `.ps1`, and `.iss` is deliberately unresolvable because installer content is packaging input, not
   injected context.

**Rejected, with reasons.** Adding `iss` red-gates on true statements. A `reference` exemption for
`ROADMAP.md` would amnesty *every* reference in that file, including ones not yet written. Removing
`'installer/'` from `$AssertPrefixes` shrinks the audit surface to fix a prose problem.

**Verified during negotiation:** the peer's claim that `$AssertPrefixes` "stays to catch any future
backticked `.iss` reference" is false — measured, `installer/_shared/anything.iss` → candidate `False`,
`installer/_shared/register-plugin.ps1` → `True`. The extension test runs before any prefix logic.
*(Panel round 8 caught that an earlier draft cited `installer/_shared/real.ps1` here — a placeholder name
invented during the probe, which does not exist. The measurement was still sound, because
`Test-IsPathCandidate` is a pure string test that never touches the filesystem, but citing a fabricated
filename inside a refutation is the "fabricated precision" failure this project's plan discipline names.
Re-measured against the real file, which is the only `.ps1` under `installer/`.)*

**Cost:** two prose lines + one comment. No behaviour change. **Gives up:** a genuinely broken `.iss`
reference still sails past.

### D2 — R2-F10: "fixed" and "fixed for the user" are conflated

**Measured.** Repo and installed plugin trees diverge in 20 of 40 files. Two are executable: the installed
`hooks.json` has no `UserPromptSubmit` registration and the installed `agy-inbox-snapshot.sh` matches only
the Skill-tool path — the exact defect recorded at
`agy-autotrain/docs/fix-the-tool-backlog/inbox-snapshot-misses-slash-command-path.md`, `status: fixed`,
whose own remedy #2 IS that hook. Fixed in the repo; not in the install.

**Decision — the peer's amendment, which beat the driver's proposal.** Replace the status enum rather than
adding a field beside it, so the ambiguous value cannot be written at all:

    status: open | fixed-in-repo | released | wont-fix
    # On `released`, ALSO set: released-in: <version or sha range>

Backfill all existing items. **Measured population, and an earlier draft of this spec got it wrong:**
of 11 files, **7 are `status: fixed`, 1 is `wont-fix`, 1 is the `_template.md` placeholder carrying
`open`**, and the remaining 2 are `README.md` and `DRY-RUN-2026-07-11.md`, which carry no status field and
need none. **So 7 items are backfilled, not 8**, and every one of the 11 files is accounted for. (The peer's
separate claim of "40 entries / 32 not yet backfilled" was measured false.)

🔴 **Panel round 4 (Sweep-Regression Auditor): the backfill needs a DECISION RULE, and the spec had none.**
Round 9 of the sweep verified that all eight fixes **exist in the repo**. That does not tell an executor
which are `released`. Guessing re-creates the exact conflation D2 exists to remove — and would mark
`inbox-snapshot-misses-slash-command-path` as `released` when round 2 measured that its fix is **absent
from the install**, which is the finding that motivated this whole decision.
**The rule, and it is measurable:** an item is **`released`** if its fix is present in the **installed**
plugin tree under `%LOCALAPPDATA%\Programs\<product>\plugins\<product>\`; **`fixed-in-repo`** if present in
the repo only. Round 2's repo-vs-install sweep is the procedure — re-run it per item rather than inferring
from a commit date, because a commit can predate the last release and still not be in it.
**Known answer for at least one item:** `inbox-snapshot-misses-slash-command-path` → **`fixed-in-repo`**
(the installed `hooks.json` has no `UserPromptSubmit` block and the installed
`agy-inbox-snapshot.sh` matches only the Skill-tool path).

**Rejected:** a `check-install-synced.ps1` in CI. The installed tree is a user-machine artifact CI cannot
see, so the check would be green-by-absence — a guard that fails open.

**Recorded as the escalation path, not built:** an **install-time** diagnostic inside the installer, which
reaches the user rather than CI, if this recurs.

**Cost:** one `_template.md` enum line + **7 item edits** — the 7 `status: fixed` items, each becoming
`released` or `fixed-in-repo` by the rule above. The single `wont-fix` item needs **no** edit (that value
survives the new enum unchanged), and `README.md` / `DRY-RUN-2026-07-11.md` carry no status field.
**Gives up:** no automated drift detection.
*(Panel round 7 caught this line still reading "9 item edits" after the population was corrected from 8 to
7 — the second consecutive round to find an incomplete fold of my own correction. See the numeric sweep
below.)*

### D3 — R3-F12: 12.7 KB of MCP tool descriptions outside the domain

**Measured.** `ghidrust/crates/ghidrust-mcp/src/tools.rs` holds 19 `pub const DESC_*` blocks = 12 746 B,
delivered to every agent by MCP `tools/list`, carrying 25 non-ASCII characters. `ghidrust/crates` is not in
`$DomainRoots`, and the gate's completeness argument (`:22-32`) is stated entirely in terms of `SKILL.md`.

**Decision, two parts.**

1. **Unconditional.** Correct the ignorelist rationale at `injected-context-ignore.txt:34-35` — *"Source
   code and an env template are executed and read by machines, never injected into an agent's context."*
   The rule's SCOPE (`**/*.py`) is right; its stated REASON is a general claim this case falsifies, and it
   is what will mislead the next maintainer.
2. **Document the boundary; add no domain entry.** The encoding invariant exists for the **Inno / CP437**
   route. MCP descriptions travel **UTF-8 JSON-RPC over stdio**, where UTF-8 is well-defined, so the
   invariant categorically does not apply and adding the file would red-gate correct content.
   🔴 **Panel round 11: the target file was never named, and the two candidates are not equivalent.**
   The boundary note goes in **`scripts/injected-context-ignore.txt`**, immediately after the corrected
   `**/*.py` rationale from part 1 — **not** in a comment beside `$DomainRoots` in
   `check-injected-context.ps1`. Two reasons: it sits directly beneath the very sentence whose
   over-generalisation caused this finding, which is where a maintainer will actually read it; and it keeps
   the gate script untouched by D3, so the only `.ps1` edits in the whole batch remain D1 part 2 and Group
   D's `msg*` note — which is what keeps the strict-capstone-reading escape hatch a single-commit
   operation.

**Amendment the peer missed, and it is part of this decision:** encoding is not the only invariant. A
description could carry a dead reference or plan residue. Round 3 verified the current set **by hand** —
all 19 documented tool names exist in `ghidrust/crates/`, and all five tools the skill says will "dead-end"
are genuinely absent. Record that as a **hand-verified, dated fact with a named re-check trigger** (re-check
when a tool is added or renamed), not as coverage.

**Cost:** one rationale rewrite + two comment lines + one debt-file entry. **Gives up:** zero automated
coverage of `tools.rs`.

---

## The remaining twelve findings

### Group A — agy-autotrain skill coherence (doc-only, `skills/agy-curate/` and `skills/agy-learn/`)

| # | Fix |
|---|---|
| **F4** | `agy-curate/SKILL.md:38` — remove the doubled space left by the `§`→`section ` expansion. |
| **F5** | Add a "compile the cheatsheet as pure ASCII" rule mirroring the GROWTH rule at `:219`, and correct `:95-96`, which currently tells the curator to *preserve* em dashes in a file the gate requires to be pure ASCII. |
| **R2-F11** | Add a non-interactive fallback to the human-approval gate at `:195-202`, mirroring the shape already used at `:242` for "No driver installed?": do **not** publish, emit a clear non-blocking message, exit. |
| **F2 + F7** | Make the inbox format spec accurate without putting non-ASCII in a non-exempt file: `agy-learn/SKILL.md:50` and `:66` keep their ASCII rendering, and gain a sentence **naming** the real delimiter — "the live inbox delimits with U+00B7 MIDDLE DOT, not an ASCII asterisk". ASCII text naming a non-ASCII character is both accurate and gate-clean. 🔴 **Write the code point, NEVER the glyph.** `agy-learn/SKILL.md` is in the corpus and is **not** exemption-covered, so pasting an actual U+00B7 to be "helpful" red-gates it on `encoding`. This is the exact trap that produced F2 and F7 in the first place; the fix must not re-enter it. |
| **F16** | Rewrite the `reason` field of the `agy-autotrain/knowledge/agy-observations.md` entry **in `scripts/injected-context-exemptions.json`** — 🔴 **not** `scripts/injected-context-ignore.txt`, which panel round 12 found was the only similarly-named file the spec actually named, making the wrong edit the likelier one. Its current retirement condition is false: it claims the waiver "stays needed only because line 7 of the header carries 3x U+00B7 and 1x U+2265", but the file carries **49 non-ASCII characters — 4 on line 7, 6 in pending bullets, and 34 lines' worth in the append-only drain-log comments a drain never removes.** Per the owner ruling, state the exemption as **permanent while drain logs are append-only** and drop the stale "delete this entry" instruction. |

**F1 — the cheatsheet budget. ✅ OWNER-RULED 2026-08-11: relax the instruction AND enforce it.**
`agy-curate/SKILL.md:80` budgets `<= ~150-token / ~3-bullet`; `knowledge/driver-cheatsheet.core.md` is
5 bullets / 433 words / 2 561 B.
🔴 **A cap DOES exist, and an earlier draft of this spec said it did not — the peer corrected me.**
`clavity-classic/src/driver_cheatsheet.rs:12` declares `pub const MAX_BYTES: usize = 16 * 1024`, enforced at
`:28-29` (`m.len() > MAX_BYTES` → *"driver-cheatsheet exceeds … bytes; using baseline floor"*). It is a cap
on the **runtime `driver-cheatsheet.md`**, separate from the SEED+GROWTH cap.
**The artifact sits at 2 587 B against 16 384 — 6.3× headroom.** So the `~150-token` figure protects
nothing that exists, and nothing enforces it: the pinning tests
(`driver_cheatsheet.rs` `baseline_floor_matches_canonical_core_source`,
`DriverCheatsheetTests.cs` `BaselineFloor_matches_the_canonical_core_source`) assert byte-identity only.
**Do:** (1) replace the `~150-token / ~3-bullet` clause with a figure tied to the real cap and the current
shape (5 bullets, well under `MAX_BYTES`); (2) **add a size assertion** to
`scripts/tests/drain-knowledge.Tests.ps1`, which already reads the canonical file at `:57` and runs under
`just test-scripts-fast`. Enforcement is the point: replacing one unenforced number with another is how it
drifted to 4× in the first place.
**Rejected (b):** trimming to 3 bullets deletes 2 of 5 verified driving rules and forces both compiled-in
baselines to be rewritten. An agent complying literally with today's text performs (b) — which is the
hazard, not the fix.

**F6 — the promotion rubric's missing class. ✅ OWNER-RULED 2026-08-11: state the existing bar in the rubric.**
The rubric (`:122-147`) states bars for **Heuristic** (>=2 independent observations) and **Empirical
Assumption** (100 % harness pass) but **never for `anti-pattern`** — the class `:185` ranks *first* in
GROWTH and agy-learn calls "the highest-value class".
🔴 **The bar already exists; it is simply not in the rubric.** `:251-252` — the anti-poisoning
circuit-breaker — instructs the curator to *"REJECT a self-reported 'learning' that is unverified,
over-general, or **a one-off impression**"*, and it applies to every candidate regardless of class.
**Do:** add a third rubric row for `anti-pattern` whose content is that existing test, noting the
human-approval gate (`:195-202`) and the priority placement (`:185`). A one-off is **rubric-parked**, which
`:265-266` already permits for *"any entry the promotion rubric explicitly parks there"*.
**Rejected (b), a mechanical corroboration bar** — and note *why*, because the first objection to it was
wrong: I argued a bar would strand a one-off with no legal move, since HELD is `[assumption]`-only
(`:158`). **Measured false** — rubric-parking generalises (`:265-266`), so (b) creates no deadlock. It is
rejected on better grounds: a corroboration *count* is the wrong epistemics for this class, and it would
strand the one peer-routed anti-pattern now in the inbox until a known driver-breaking failure recurred —
against the capture-fast discipline for the class the system values most.

**F17 — the SEED+GROWTH headroom. ✅ OWNER-RULED 2026-08-11: in scope, added to this batch.**
🔴 **`agy-curate/SKILL.md:191` says the over-cap degrade happens "silently". That is STALE.** Both drivers
warn, with the identical message: `clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:186` and
`clavity-classic/src/golden_header.rs:237` — *"combined golden-header at {dir} exceeds the {MaxBytes}B cap
— dropping GROWTH, keeping SEED"*. `agy-autotrain/ROADMAP.md:135` already records the fix
(*"That drop is no longer silent"*), so the SKILL is the only place still claiming otherwise.
**Measured now:** seed **5 190** + growth **7 984** = **13 174 of 16 384 — 80 % full, 3 210 bytes of
headroom.**
**Do:** correct `:191` to drop "silently" and cite the warning both drivers emit, so a curator knows the
signal exists; and record the measured headroom beside the existing
`16 KB - (size of golden-header.seed.md)` guidance at `:193`, so the number is concrete rather than
an instruction to go and compute it. Doc-only.

### Group B — ghidrust (F3, R7-F15)

One mechanism closes both. `skill_asset.rs:53` claims `ghidrust skill --emit` *"round-trips into the plugin
copy exactly"*; it does not, because `DRIVER_SKILL` is `include_str!` of the canonical **including** its
9-line header (`:1-9`) and `main.rs:34` prints it verbatim, while the shipped copy starts at `---`.

1. Make `--emit` strip the canonical's leading HTML comment block, so the emitted bytes equal the shipped
   plugin copy and the documented regeneration stops being a trap.
2. **Add the missing oracle:** a test asserting the committed plugin copy equals `--emit` output. Nothing
   compares them today — `skill_asset.rs:52-53` compares the embedded const to the **canonical**, never to
   the copy, and the ship-guard at `:22` is a `.contains(...)` substring check that passes whether
   frontmatter sits at line 1 or line 11.
3. Correct the false round-trip claim in the comment.

This is ghidrust source and belongs to **ghidrust's own** test suite, not the injected-context gate — it
does not touch `check-injected-context.ps1` and does not invalidate its capstone.

### Group C — registration (R6-F14)

`agy-autotrain/hooks/hooks.json:8,10` uses `startup|clear|compact` and `startup|resume` — complementary,
non-overlapping subsets of this repo's own convention, which `plugin-hooks-registration.Tests.ps1:51,176,179`
pins **exactly** as `startup|resume|clear|compact`. Nothing tests agy-autotrain's `hooks.json` at all.

1. Align both matchers to `startup|resume|clear|compact`.
   ⚠ **The panel flagged the fix's own consequence, which the finding did not.** Widening
   `agy-curate-nudge.sh` from `startup|resume` to all four sources means it now also fires on **clear** and
   **compact**. Its output is threshold-gated (`count >= THRESHOLD` or `age_stale`), so it is silent when
   the inbox is small — but on an over-threshold inbox a compaction-heavy session will now nudge on every
   compact as well as every startup. **That is the intended behaviour** (the nudge exists because a full
   inbox is a live problem, and a compaction is exactly when the earlier nudge left context), but it is a
   real change in nudge frequency and is recorded here rather than discovered later.
2. Extend the registration suite to cover `agy-autotrain/hooks/hooks.json` (it is currently parameterised
   over `dotnet`/`classic` only, `:14-15`). Assert the matcher strings **exactly**, matching the sibling
   assertions' `Should -BeExactly` shape, so a future partial subset fails rather than passing silently.

Consequence being fixed: on a **resumed** session the agy-LEARN reminder never fires — against that skill's
own premise, *"capture is cheap and live; do not batch."*

### Group D — gate documentation and the extractor test (R4-F13, plus D1/D3's comment work)

**R4-F13, per the owner ruling: test + document, no gate change.**
Measured with a control: a hook using `msg='...'` + `jq --arg m "$msg"` is caught; `body=$(...)` and
`payload="$a$b"` yield **0** extracted messages and **no** tag-hygiene violation on a message carrying
anomaly A1's duplicated tag. `Get-HookMessages` binds `(?<var>msg[A-Za-z0-9_]*)`, and the requirement is
documented nowhere.

1. Add a test asserting that **every corpus hook which actually emits an agent-visible message yields at
   least one extracted message.**
   🔴 **The naive form of this test is WRONG and the panel caught it. Measured:**
   `agy-liveness-check.sh` and `agy-anomaly-reminder.sh` each MENTION `additionalContext`/`systemMessage`
   exactly once — inside a comment explaining why they deliberately do **not** use it — and emit via
   **stderr + `exit 2`** instead (11 and 5 `exit 2` sites respectively). A test keyed on "the file mentions
   `additionalContext`" would therefore **red on two correct hooks.**
   **The discriminator must be actual emission on a non-comment line**: a `jq` invocation constructing
   `{systemMessage:...}` or `{hookSpecificOutput:{...additionalContext:...}}`, with lines whose first
   non-whitespace character is `#` excluded. Hooks that emit only to stderr are **out of scope by
   construction** and the test must say so in its `-Because`, naming those two as the reason.
   **Prove it non-vacuous** with a logic mutant. 🔴 **The peer panel found two traps here and both are
   closed:**
   - **Name the mutant target.** "A fixture hook" is not enough: if the executor picks
     `agy-liveness-check.sh` or `agy-anomaly-reminder.sh`, the mutant **passes silently** because the test
     deliberately excludes stderr-emitting hooks — a control that fails for the wrong reason, which this
     project treats as no control at all. **Mutate `agy-autotrain/hooks/agy-learn-reminder.sh`**: it is in
     the corpus, it genuinely emits `additionalContext`/`systemMessage`, and it uses `msg` variables
     (measured: 2). Rename its `msg` to `payload` and confirm **this specific test** goes red.
   - **Say what the mutant IS.** It is a **temporary, uncommitted** edit, reverted immediately after the
     red is observed. Nothing about it is committed. The evidence recorded is one line in the commit
     message naming the test that went red under it. There is no mutant artifact, no permanent fixture,
     and no sign-off step.
2. Document the `msg*` convention in two named places: a comment beside `Get-HookMessages` in
   `scripts/check-injected-context.ps1`, and `agy-autotrain/CONTRIBUTING.md`, which is the file that tells
   contributors how to work on that plugin.

**Non-goal, stated explicitly:** widening the extractor to follow command substitution and concatenation.
The shape space is open-ended, so it cannot be made complete, and it is a behaviour change requiring a
re-capstone.

---

## Sequencing

Four commits, in this order, so that nothing depends on a later step:

1. **Group A** — agy-autotrain skill coherence + the exemption `reason` rewrite (F16) + **F1, F6 and F17**,
   all three now owner-ruled and closed here (F1 also adds its enforcement assertion to
   `scripts/tests/drain-knowledge.Tests.ps1`, so commit 1 is doc **and** test).
2. **Group C + D2** — hook matchers, the new registration test, the backlog enum + backfill.
3. **Group D** — the extractor test, the gate comments (D1 part 2, D3 parts 1-2), and the `coverage-debt.md`
   entries.
4. **Group B** — ghidrust emit + its new oracle test.

Groups A–D touch no gate behaviour, so `06a39af` stands throughout.

🔴 **Commit 3 is the ONLY commit that edits `scripts/check-injected-context.ps1`** — it carries both gate
comments (D1 part 2 beside `$AssertPrefixes`, and Group D's `msg*` note beside `Get-HookMessages`).
Nothing in commits 1, 2 or 4 touches that file. **This is deliberate and must stay true**, because it is
what makes the strict-reading escape hatch cheap: if the owner rules that *any* byte of the gate
invalidates `06a39af`, then **commit 3 alone** is the re-capstone target — no archaeology, no squashing
across commits. Commit 3's message must name the file explicitly so that decision stays a one-commit
operation.
*(Panel round 10 raised this as comments "scattered across commits 2 and 3". Measured: they are already
consolidated in commit 3 — the premise was wrong, but the underlying gap was real. Nothing SAID so, and
an implementer under the strict reading had no way to know which commit to target.)*

**When to run each criterion — panel round 10 found these contradictory.**
Criteria **1-5 after every commit.** Criterion **6 (`cd ghidrust && just test`) only after commit 4**, the
one that lands Group B. Running it earlier exercises nothing this batch changed and can only produce a
misleading result — a trivial pass, or a red for an unrelated pre-existing ghidrust reason.
`just test-scripts-fast` must be **backgrounded** (~696 s, over the 600 s tool cap).

## Specification gaps closed by the self-audit

The audit mapped all 17 findings to sections (all covered) and found four places where an executor would
have had to guess. Closed here rather than left to the plan:

1. **Group B's new oracle — how it obtains emit output.** It must **not** re-implement the header-strip in
   the test, which would test the test. It runs the built binary **via `env!("CARGO_BIN_EXE_ghidrust")`**
   — the single mechanism, stated once, per the reconciliation below —
   and compares stdout byte-for-byte against the committed
   `ghidrust/plugin/skills/ghidra-re-driver/SKILL.md`.
   ✅ **Path verified, not assumed** (panel round 10 asked): that file exists at 16.5 KB, and
   `find ghidrust -name 'SKILL.md' -path '*ghidra-re-driver*'` returns exactly one match. There is no
   `plugins/` variant — the whole product contains only two `SKILL.md`, this one and the canonical
   `ghidrust/skill/SKILL.md`. **Finding refuted; the concern was that a wrong path would make the oracle
   pass vacuously, which is right in principle and does not apply here.**
   🔴 **Panel round 2 corrected an error here.** An earlier draft placed this oracle in the **Ghidra-backed**
   tier. That is wrong and would have gutted it: `just test-all` needs `GHIDRA_INSTALL_DIR` (Ghidra 12.1.2)
   **and JDK 21** (`ghidrust/CLAUDE.md:19`), so the oracle protecting the emit contract would almost never
   run. **`skill --emit` needs a BUILD, not Ghidra** — it prints an embedded `include_str!` const and never
   starts a JVM. The binary is `[[bin]] name = "ghidrust"`, so a normal Rust integration test reaches it via
   `env!("CARGO_BIN_EXE_ghidrust")` with no `cargo run` subprocess indirection.
   🔴 **Panel round 14 (two seats, independently) caught that this spec stated TWO mechanisms for one
   task** — an earlier draft said `cargo run -p ghidrust-mcp -- skill --emit` here and my round-2 edit
   added the env-var form without removing it. **`env!("CARGO_BIN_EXE_ghidrust")` is the one and only
   mechanism.** Measured: `ghidrust/crates/ghidrust-mcp/Cargo.toml` declares exactly **1** `[[bin]]`, so
   the `cargo run` form is unambiguous *today* — but it is subprocess indirection this spec explicitly
   argues against, and it would become ambiguous the moment a second binary is added. **This was my fourth
   incomplete fold of the review** (after rounds 6, 7 and 12); it survived because none of the four
   exhaustive sweeps covered "two mechanisms stated for one task", which is now swept as a fifth class.
   **It belongs in the FAST tier** — `just test`, *"pure Rust, no Ghidra needed"* (`ghidrust/CLAUDE.md:49`) —
   as a new file under `ghidrust/crates/ghidrust-mcp/tests/`, beside the integration tests already there.
   **Three sub-questions the peer panel raised, answered from source so the executor does not re-derive them:**
   - **Trailing newline — already settled in the code.** `main.rs:30` states *"`print!` (no trailing
     newline) keeps the output byte-identical to skill/SKILL.md"* and `:34` uses `print!`, not `println!`.
     So a byte-for-byte compare is correct as-is; do **not** trim or append.
   - **"Which skill does `--emit` emit?" — REFUTED, the question does not arise.** `main.rs:34` emits
     `DRIVER_SKILL`, the single embedded driver skill. The peer conflated this with R3-F12's 19 `DESC_*`
     tool-description consts, which `skill --emit` never touches. There is one skill and no flag is needed.
   - **Where the strip boundary falls — measured line by line, because an earlier draft got it wrong.**
     Strip **exactly lines 1-9** of the canonical: `<!--` is on **line 1**, the comment body runs 2-8, and
     `-->` is on **line 9**. `---` is **line 10** and becomes line 1 of the emitted output.
     🔴 **There is NO blank line between `-->` and `---`. Do not strip a tenth line.** An earlier draft
     said "and the blank line that follows"; stripping 10 lines emits **224** against the plugin copy's
     **225**, and the oracle would go RED on a correct implementation.
     **Arithmetic that pins it:** canonical **234** lines − 9 stripped = **225** = the plugin copy exactly.
     🔴 **And pinned at BYTE level, which is what a byte-for-byte oracle actually needs** (a line count
     cannot catch a trailing-byte difference): canonical **17 566 B** − the 629 B of lines 1-9 = **16 937 B**
     = the plugin copy's exact size. **Both files end in `0a`**, so there is no trailing-newline asymmetry
     for `print!` to expose. If the implementer's strip does not reproduce 16 937 bytes, it is wrong before
     the oracle is even run.
2. **F5 — what `:95-96` should say.** Replace the em-dash-preservation guidance with: *"Compile the
   cheatsheet as pure ASCII, for the same reason GROWTH is (see 'Compile GROWTH as pure ASCII'). The inbox
   it is distilled FROM is the one file exempted to carry non-ASCII, so strip any U+00B7, em dash or arrow
   when you lift text out of it."* This is the actual hazard F5 names — the source is exempt, the
   destination is not.
3. **F16 — the replacement `reason` text.** *"Owner ruling 2026-08-08, reason corrected 2026-08-11. The
   agy-learn inbox is in the domain and every other invariant applies. Its non-ASCII is NOT confined to the
   header: measured 2026-08-11, the file carries 49 non-ASCII characters — 4 on the header line, 6 in
   pending bullets, and the remainder across 34 lines of drain-log comments, which are append-only and are
   never removed by a drain. This exemption is therefore PERMANENT while drain logs remain append-only. Do
   not expect it to become unused; the earlier note predicting that was wrong."*
4. **R2-F11 — the fallback's exact shape.** Mirror `:242`: if no interactive approval channel is available,
   **do not publish**, emit a non-blocking message — *"no interactive approval channel; the compiled GROWTH
   was NOT published. Re-run agy-curate interactively to publish."* — and exit without error. Publishing
   unreviewed GROWTH is the one outcome the gate exists to prevent, so the fallback fails CLOSED.
   🔴 **Panel round 3 (Boundary Smuggler) added the half that makes it safe.** Failing closed here means a
   completed curation is discarded, which is a silent-loss path unless the inbox survives. It does: the
   skill's Finish ordering (`:257-262`) already resets `## Pending` **only when `curate-commit` exits 0**,
   so an unpublished run leaves every entry in place and a later interactive run simply recompiles. **The
   fallback MUST state that explicitly** — "the inbox is deliberately left unreset; nothing is lost" — so
   nobody later 'helpfully' adds a reset to the non-interactive path and turns a safe abort into data loss.
   Only compute is wasted, and only once.

**Also stated, because it was an unhandled case:** if `just test-scripts-fast` goes red mid-batch, stop and
diagnose before continuing — do not proceed to the next commit. Each commit's verification is meaningless
once an earlier one is red.

**Not applicable, checked:** the standing "byte-identical pair must mirror to classic" rule does not fire
anywhere in this batch. `agy-autotrain/` and `commonmemory/` are standalone products, and the gate comments
are not twin-plugin files.

## Explicit non-goals

- No `iss` in `$ShippedExtensions`; no third exemption; no `ghidrust/crates` domain entry.
- No CI check comparing the installed tree to the repo.
- No widening of `Get-HookMessages`.
- No change to `check-injected-context.ps1` behaviour, and therefore no re-capstone of the gate.

## R5-O2 — the finding this spec originally dropped

**The panel caught that R5-O2 appeared nowhere in the batch — neither closed nor deferred.** A sweep
finding that silently vanishes between the sweep and the fix batch is exactly the failure the batch exists
to prevent, so it is restored here.

**R5-O2:** `commonmemory/rules/commonmemory.md` is audited as injected context, but the product's own
`README.md:22` and `:77` annotate it *"agy-native proactive-recall rule (Claude ignores it)"*, and `:57-58`
leaves the loading mechanism **unconfirmed** — *"if your agy auto-applies plugin `rules/` … verify once."*
Neither manifest declares a `rules/` surface. The gate is right to audit it (fail-safe over-coverage); the
open question is that **"verify once" appears never to have been verified**, so whether commonmemory's core
recall mechanism fires for agy at all is unknown.

**Disposition: deferred as tracked debt, not fixed here.** Closing it means an empirical test against a
live agy — out of scope for a doc-and-test batch, and agy is quota-blocked. Logged with the re-check
trigger below.

## Deferred to `docs/coverage-debt.md`

Each entry carries its compensation **and a code anchor whose disappearance voids it**, per that file's own
contract — a bare "deferred, see spec" would violate it.

| Item | Compensation | Anchor (its disappearance voids the entry) |
|---|---|---|
| `.iss` references unresolvable by design (D1) | Installer content is packaging input, never injected context; the two known references are rewritten so no dead path is cited | the comment beside `$AssertPrefixes` in `check-injected-context.ps1` |
| `tools.rs` has zero automated coverage (D3) | Accuracy hand-verified 2026-08-11: all 19 documented tool names exist in `ghidrust/crates/`; all 5 "will dead-end" tools absent. **Re-check trigger: a tool added or renamed.** | `ghidrust/crates/ghidrust-mcp/src/tools.rs`'s `DESC_*` const block |
| Repo-vs-install drift undetected (D2) | The status enum makes "fixed for the user" a distinct, required state; escalation path is an install-time diagnostic if it recurs | the `status:` enum line in `agy-autotrain/docs/fix-the-tool-backlog/_template.md` |
| R5-O2 commonmemory recall unverified | The rule is inert if it never loads — a no-op, not a wrong action. **Re-check trigger: the next time a live agy is reachable.** | `commonmemory/README.md:57-58`'s "verify once" sentence |

🔴 **Round 6 (fold audit) originally added two conditional rows here for F1/F6, because criterion 5 had
been amended to reference them and this table did not list them — the project's dominant fold defect.
**Both rows are now REMOVED: the owner ruled F1, F6 and F17 on 2026-08-11, so all three are closed in
commit 1 and none is deferred.** The lesson the rows were added to record still stands: grep the whole
artifact for the fact you changed, not just the sentence you were editing.
