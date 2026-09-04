# clavity umbrella — ROADMAP

> **Superseded (2026-07-11):** the branch-per-tool / `plugins/<tool>/` model described below was
> replaced by the monorepo layout — see the root README.

> **Umbrella roadmap.** This repository is a **host for several independently-released tools** under the
> `clavity` brand. Each tool follows one pattern — code on its own branch; a plugin under
> `plugins/<tool>/` on `main`; an Inno-Setup installer; its own `<tool>-v<N>` release lineage — see
> [`docs/hosting-a-tool.md`](../docs/hosting-a-tool.md). This file carries an umbrella overview, a tool
> index, and one roadmap section per hosted tool.

## Hosted tools
| Tool | What it is | Release lineage |
|------|-----------|-----------------|
| [`clavity`](#clavity) | Pairs Claude with a live Antigravity (`agy`) peer (dotnet + classic variants). | `clavity-v<N>` |
| [`ghidrust`](#ghidrust) | Drives a persistent headless Ghidra JVM — 19 reverse-engineering tools over MCP (v1.0 attaches to an analyzed project). | `ghidrust-v<N>` |

*(New tools add a row here and a `# <tool>` section below during onboarding — see the playbook, Phase B.)*

---

# clavity

> **Live roadmap — reconciled 2026-06-30.** This file is the single forward-looking source of truth.
> It supersedes the original 2026-06-16 driving-session roadmap (now folded into **§ Shipped — history**
> below). Detail for each item lives in `docs/superpowers/specs/` + `docs/superpowers/plans/`; this file
> tracks **what is done** and **what is next, in order**.

---

## What clavity is now

clavity pairs **Claude** with a live **Antigravity (`agy`)** peer. It ships in **two variants**:

- **clavity-dotnet** — .NET 10, binary **`clavity-ls`**, drives agy over its **Language Server** (gRPC/h2c)
  via the `agy_look` / `agy_status` / `agy_ask` MCP tools. **SHIPPED**: one-command Windows installer
  (`clavity-dotnet-setup-<version>.exe`), Add/Remove-Programs uninstall, release CI.
- **clavity-classic** — Rust, binary **`clavity`**, drives agy over **psmux** + the **agentmemory signal bus**
  (`clavity ask` / `await-reply` / `ping`, `delegate_to_antigravity`). Source lives at `clavity-classic/` on
  `main` (monorepo). **SHIPPED**: one-command Windows installer (`clavity-classic-setup-<version>.exe` +
  `.sha256`), per-user, mutual-exclusion with dotnet, opt-in `agy-mcp-bridge` add-on, release CI.
  (Also buildable from source with `just build` in `clavity-classic/`.)

Under the cohesive distribution model, **agy-autotrain** (the agy-driving-perfection learning loop) and
**commonmemory** (shared Claude⇄agy notebook over agentmemory) are **not** dotnet installer checkboxes — each
ships as its own standalone, plugin-only `Setup.exe` (own AppId, own scoped marketplace), installed
independently of clavity-dotnet. Classic has no plugin tree, so its installer (Option A) ships **only** the
opt-in `agy-mcp-bridge` add-on.

The two variants are **mutually exclusive** on a machine (the installers refuse to co-install).

---

## ✅ Shipped

### clavity-dotnet — releases

> 🔴 **THIS LIST STOPS AT v0.1.9 AND THE PLUGIN IS AT 0.7.0** (checked 2026-08-06 against
> `clavity-dotnet/plugin/plugin.json`; umbrella tags run `clavity-v12`…`clavity-v17`). Everything from
> 0.2.0 to 0.7.0 is missing here. **`CHANGELOG.md` is the current record and is generated — read it, not
> this section, for what shipped when.** The list below is kept because its entries carry the *reasoning*
> behind each early release, which a generated changelog does not; it is history, not a status board.
> `clavity-dotnet/CLAUDE.md` claims both files "stay current" — for this one that has not been true since
> 0.1.9, and backfilling six minors from commit messages would manufacture recollection rather than record it.

- **v0.1.0–v0.1.4** — packaging: Inno installer + PowerShell chooser + release CI + silent install/uninstall
  CI smoke; mutual-exclusion guard; per-user (`%LOCALAPPDATA%` + HKCU), unsigned. (v0.1.1–v0.1.4 were
  installer-hang fixes culminating in a fully CI-green silent lifecycle — the lesson that birthed local-ISCC
  verification, now standard.)
- **v0.1.5** — agy-tab launch fix: `wt` split `;` in the inline pwsh script → base64 `pwsh -EncodedCommand`.
- **v0.1.6** — `agy_ask`/`agy_look` decode agy's **reply prose** (modeled `CascadeAssistantOutput`, trajectory
  field 20.1; `BoundedView` reads assistant text, not just user input).
- **v0.1.7** — `agy_ask` returns agy's **full reply**: differentiated view caps (LOOK keeps the 8 KB/1 KB glance;
  ASK uses 32 KB total / 16 KB per-step) + **newest-first fill** so a noisy delta can't re-truncate the answer.
  (Closed the 1 000-char/step `BoundedView` cap that truncated long design consults.)
- **v0.1.8** — agy always launches with `--dangerously-skip-permissions` (the paired agy is driven headless, so
  its interactive permission prompts would otherwise stall the bus round-trip).
- **v0.1.9** — dynamic send-model resolution: `agy_ask` drives with the conversation's **own last-used model**
  (read from the trajectory step-metadata) → agy's catalog **default** for a brand-new conversation → legacy `1037`
  fallback; a model deprecated out of the live catalog stops the drive with an actionable error, and the chosen
  model + source is surfaced on stderr. Ends the hard-coded-model silent-break (agy model renumbers no longer
  mis-drive the peer).

### clavity-classic — releases
- **v0.1.0** — first packaged release: no-Rust-toolchain Windows installer (`clavity-classic-setup.exe` +
  `.sha256`) + release CI. The **golden-header injection** epic (Spec A) + the **Option A installer** (Spec B),
  build order **7.3 → 7.8 → 7.1 → 7.2**, all shipped:
  - **7.3** golden-header injection in the Rust crate (`src/golden_header.rs`; `clavity curate-commit`; doctor status).
  - **7.8** shared build recipe (`scripts/build-classic-release.ps1`): `cargo build --release --locked` + staged
    bridge runtime whitelist, hard `.env`-leak assertion.
  - **7.1** Inno installer (`installer/clavity-classic.iss`, **Option A — minimal/honest**): binary→PATH, HKCU
    mutual-exclusion marker + bidirectional refuse vs dotnet, opt-in `agy-mcp-bridge` add-on (uv prereq, `.env`
    hard-excluded), responder-skill teardown, golden-header zombie rename, informed `.env` keep/purge,
    guided-manual wiring docs. Plan got a 4-lens AGY-AFTER (13 defects folded); the ISCC compile + a re-tag CI
    fix were caught by the local/CI gates, not review.
  - **7.2** release CI (`release-clavity-classic.yml`): 4-way version triangulation, tag-lineage guard, blocking
    timeout-bounded smokes (install/uninstall, mutual-exclusion, `.env`-exclusion), atomic publish.
  - **Bridge hardening** (`bd8ec8f`): `server.py` scrubs host AI keys from the delegated sub-agent's env
    (confused-deputy fix) and passes the Gemini key explicitly to the SDK. (Residual: the closed `localharness`
    re-export is inconclusive but mitigated — sub-agent `run_command` is blocked in the current headless posture.)

### clavity-dotnet — engineering increments (all merged to `main`)
- **.NET port, increment 1 (T1–T10)** — LS discovery, h2c framing (live-proven + CI-pinned), `LsClient`,
  the `agy_look`/`agy_status`/`agy_ask` MCP surface, live write path (model-id reverse-engineered).
- **Multi-session pairing** — N independent Claude⇄agy pairs in a shared agy tree; per-session `--log-file`→port
  discovery, identity via `CLAVITY_AGY_LOG`/`CLAVITY_SESSION_ID`, convId from the LS (ConversationLocator retired),
  log retention, ModalGuard. Live-proven with two concurrent agy instances.
- **Product-structure refactors** — golden-header injection moved skill→binary (`clavity-ls curate-commit` writes,
  the binary reads+prepends per ask); anti-misfire driving protocol merged into the core driving skills;
  `driving-agy` deleted; bundled `clavity-dotnet` plugin + marketplace entry.
- **RIGHT-TOOL tooling discipline** — declarative `.claude/recommended-tools.json` + SessionStart presence-check
  hook + remote-iteration circuit-breaker (ISCC declared; local installer verification is now standard).

---

## ▶ Forward backlog (in priority order)

### 0. DISCIPLINE EFFICACY — stop confirming presence and calling it proof · ~~▶ TOP PRIORITY~~ → ~~**one defect fix (step 1b); owner ruling 2026-08-06**~~ → ✅ **ALL RATIFIED STEPS SHIPPED 2026-08-07 (2, 1a, 1b); the witness trial was KILLED, not deferred. Two coverage holes accepted — see item 1b.**

Numbered `0` deliberately: this list is priority-ordered, and renumbering 1-11 would invalidate every
existing citation to §7 and §8. Owner-directed 2026-08-04. **The deferral is DISCHARGED: it waited on the
AGY-ANOMALIES capture-gap build, because the instrumentation attaches to that code and had to be written
against it rather than against a description of it. That build shipped as `clavity-v16` (dotnet `0.6.0`),
verified installed 2026-08-04, so the code now exists to build upon.**

**The failure, stated exactly.** v15 shipped the AGY-ANOMALIES discipline. The install was faithful —
installed plugin `0.5.0` matches the `clavity-v15` tag file-for-file, verified 2026-08-04, so packaging
and delivery were never the bug. A session confirmed the hooks fire as designed. They did. And the
discipline still produced nothing, because the capture side did not exist: a driver working DIRECTLY, not
dispatching, got no push at any moment. The gap surfaced only when an agent in an unrelated project, two
tabs away, hit it while doing ordinary work.

**Every gate in this repo measures PRESENCE. None measures EFFICACY.** Byte-parity, pure-ASCII, mirrored
pairs, `seed-sync-check`, registration structure, "all 3 registered", "installs verified live" — all
answer *is the file there and wired up?*, and all were correct about v15. The unasked question is *did a
session that noticed a defect end up with an entry in `.clavity/local-anomalies.md`?* This is the same
class §6 already names for a different discipline — *"delivers knowledge without validating that driving
actually improved (delivery != outcome)"* — recorded there and never actioned. Two independent
disciplines have now hit it; treat it as the general defect it is.

**Why the confirming session was a worthless witness, and no amount of care fixes it:**
1. it was inside the build, holding the design in context, so "did it fire?" gets reconstructed rather
   than observed;
2. **silence and absence are indistinguishable** — this epic's own thesis, applied one level up to its
   own verification;
3. nothing the hooks emit identifies itself, so a stale install and a current one look identical.

**The exact code to build upon** (all three files EXIST as of `d0b4cb1` — cite these, do not invent):

| file (mirrored in `clavity-classic/plugin/hooks/`) | message defined | envelope emitted | jq-absent fallback |
|---|---|---|---|
| `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh` | `:31` | `:52` | `:39-43` |
| `clavity-dotnet/plugin/hooks/agy-anomaly-dispatch-reminder.sh` | `:43` | `:61` | `:48-52` |
| `clavity-dotnet/plugin/hooks/agy-anomaly-model-notice.sh` | `:44` | `:45` | `:19-21` (exits silently) |

Behaviour is pinned by `scripts/tests/agy-anomaly-{capture-reminder,dispatch-reminder,model-notice}.Tests.ps1`
and registration by `scripts/tests/plugin-hooks-registration.Tests.ps1`. **Any message change must hold
the byte ban** (no backtick, apostrophe, double quote, backslash — the last two break the hand-built
envelope on the jq-absent path, measured) **and keep the jq and no-jq paths byte-identical**, both
already asserted.

**PARITY IS A REQUIREMENT, NOT A FOLLOW-UP — and it is what makes mechanism 1 hard.** Whatever ships here
ships to **both drivers**, byte-identically: the three hooks above are mirrored in
`clavity-classic/plugin/hooks/` and verified `IDENTICAL` (2026-08-04). Two gates already enforce it and
will fail the moment a driver drifts — `scripts/tests/plugin-hooks-payload.Tests.ps1` (per-file byte
parity across the two hook dirs) and the whole-`.hooks` deny-list catch-all in
`scripts/check-seed-artifacts-synced.sh`, which compares every registered event by content.

That constraint bites mechanism 1 directly: **a byte-identical hook body cannot carry a per-driver
literal.** This is a solved problem in this repo, not a new one — `docs/agy-disciplines-marker-contract.md:13`
records the same collision for the discipline markers and its decision (**Option S**: a single
discipline-keyed name with no `<plugin-id>` prefix, justified there by exactly this byte-identity
constraint plus the fact that the two drivers are mutually exclusive). **Read that decision before
designing the stamp; the same reasoning and the same trap apply.** A stamp that differs per driver is not
a stamp, it is a parity break that both gates above will reject.

> ### 🔴 OWNER RULING 2026-08-06 — §0 IS SPLIT. Part one is a DEFECT; the trial is KILLED.
>
> **The Phase-2 gate asked whether to override the bar for §0. The owner's answer reframed it: §0 was two
> different things wearing one number, and they get opposite dispositions.**
>
> - **✅ STEP 1b — RECLASSIFIED AS A DEFECT, to be fixed.** No override was needed, because it is not a
>   validation task. Measured: every anomaly-capture prompt sits behind a precondition — a **dispatch**
>   (`PreToolUse` matcher `Agent|Task`), a **compaction** (`PreCompact`), or one of three named skills
>   (`agy-seam-inject.sh`). `SessionStart` only nags about anomalies **already recorded**; it never asks for
>   a new one. **So for a user running ordinary short or medium sessions — no subagents, no compaction —
>   the capture discipline never prompts at all.** It is installed, registered, and inert, and the user has
>   no way to tell. This entry called it *"a DEFECT IN v16, not new work"* from the start; it was the bar
>   that was being misapplied, not the item that was overreaching.
> - **🚫 STEP 3, THE OUTSIDE-WITNESS TRIAL — KILLED (clause 1).** It is a validation harness: it would tell
>   us whether the disciplines change behaviour, which is an **unvalidated assumption**, not a false
>   diagnostic. Killed consistently with §4 and §6, both killed on identical reasoning in this same sweep.
>   **Widening clause 1 to admit it readmits every unbuilt validation harness in the repo.**
>
> ⚠️ **ACCEPTED COST OF THIS RULING, recorded so it is not rediscovered as a surprise:** the trial was the
> only step that would ever have demonstrated the disciplines work on an unprimed user. Killing it leaves
> the product's central claim — "delivers better driving" — **still unproven, now with better plumbing
> underneath it.** That is a deliberate trade, made with the alternative stated.
>
> ➡️ **§0 is therefore no longer a `▶ TOP PRIORITY` epic. It is one small bug fix (step 1b).** The
> demotion is deliberate. Items 2 and 1a already shipped (below); with the trial killed, 1b is all that
> remains.
>
> ✅ **UPDATE 2026-08-07 — step 1b has SHIPPED, so §0 has no unbuilt remainder.** Detail and the two
> accepted coverage holes are in the WHICH-STEPS-SHIPPED block below. The text above is kept as written
> because it is the reasoning that produced the demotion.

> ### 📏 WHICH STEPS HAVE SHIPPED — measured 2026-08-06 (open-work sweep, Phase 1 Task 4 Step 1)
>
> **§0 is PARTIALLY SHIPPED: two of its three ratified steps are done.** This measurement exists because
> ranking a partly-built item as unstarted is the error that sweep was run to remove. **No disposition is
> recorded here — §0 goes to the owner gate.**
>
> - **Item 2, the static contract stamp — ✅ SHIPPED** (`29372b4` *"feat(hooks): AGY-ANOMALIES contract
>   stamp"*). The literal `AGY-ANOMALIES/1` is live in three hooks —
>   `agy-anomaly-model-notice.sh:77`, `agy-anomaly-dispatch-reminder.sh:43`,
>   `agy-anomaly-capture-reminder.sh:31` — and pinned by `scripts/tests/agy-anomaly-contract-stamp.Tests.ps1`,
>   which is the test this entry asked for against a stale stamp.
> - **Item 1a, the MEASURE half — ✅ SHIPPED.** `scripts/discipline-reaching-report.ps1` reads
>   `hookName` / `hook_additional_context` and counts deliveries by the stamp, with two suites
>   (`agy-discipline-reaching.Tests.ps1`, `discipline-reaching-report.Tests.ps1`).
> - **Item 1b, the PROMPT half — ✅ SHIPPED 2026-08-07** (`40f9eaa` the hook, `a527020` the classic mirror,
>   `58afde2` the registration). It shipped on **`UserPromptSubmit`**, registered **bare** in both driver
>   manifests, with the discrimination done inside `agy-anomaly-capture-reminder.sh`. A `matcher` was NOT
>   used: nothing establishes that one is evaluated against prompt text for this event, and both
>   first-party plugins that register it match in-script. The hook takes the event name as `$1`, selects a
>   prompt-specific message, and emits `hookSpecificOutput` — measured to be the arm that reaches the model
>   for this event, where `PreCompact` requires top-level `systemMessage`. Gated to **at most one emission
>   per session, never on the first prompt.** Pinned by `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1`
>   (11 new tests) and `scripts/tests/plugin-hooks-registration.Tests.ps1`.
>
>   **PROVENANCE — the measurement that made this work necessary, kept deliberately.** Before the fix,
>   measured against `plugin/hooks/hooks.json`: every anomaly-capture prompt sat behind a precondition —
>   `PreToolUse` matcher `Agent|Task` (needs a **dispatch**), `SessionStart` ×2 (triage notices for
>   anomalies that already exist, not a capture prompt), `PreCompact` (needs a **compaction**). *"The count
>   of hooks that prompt a driver working DIRECTLY is still ZERO ... There is no `UserPromptSubmit`
>   registration."* That count is now **one**.
>
>   🔴 **TWO ACCEPTED COVERAGE HOLES. Neither is closed, and 1b must not be read as closing them.**
>   1. **A session containing exactly one user prompt is unreachable.** The gate deliberately does not fire
>      on the first prompt, because at that moment the driver has done no work and can have observed
>      nothing; prompting there trains the reflexive "none" answer the capture-gap spec records as worse
>      than no prompt. The only events landing *after* work in a one-prompt session are `Stop` (withdrawn)
>      and `SessionEnd` (measured dead — `${CLAUDE_PLUGIN_ROOT}` does not resolve there, cancelled 3/3, see
>      the SessionEnd measurement below). **Owner-accepted 2026-08-07.**
>   2. **A message injected into a RUNNING turn does not raise `UserPromptSubmit` at all.** Measured
>      2026-08-07 during the Task 0 envelope probe: a registered sentinel recorded exactly one firing across
>      a window containing both a mid-turn message and a fresh turn, with the session id unchanged
>      throughout (so no restart, and the registration was live for both). **This hole was NOT known when
>      the item was ratified and is recorded here rather than discovered later.**
>
>   The mechanism that would have covered hole 1 is the outside-witness trial, which this epic's own owner
>   ruling **KILLED** (see the ruling block above). Do not reopen the trial to close it.
> - **Item 3, the outside-witness trial — ❌ NOT RUN.** Its protocol is written (`0b634d3` *"docs(spec): the
>   outside-witness trial protocol, and the trap that makes it fakeable"*); no trial has been conducted.
> - **Item 4, the firing counter — already DROPPED** by this entry itself, superseded by step 1a.
>
> **So the unbuilt remainder of §0 was: step 1b, then the witness trial.** The prerequisite the sequence
> insists on — the stamp before the trial, so a null result can be split into *never fired* versus *fired
> and ignored* — **is already satisfied.**
>
> ✅ **As of 2026-08-07 there is NO unbuilt remainder.** Step 1b shipped; the witness trial was KILLED by
> owner ruling, not deferred. **§0's three surviving ratified steps (2, 1a, 1b) are all done.**

**THE SEQUENCE — OWNER-RATIFIED 2026-08-04, after a second AGY-FIRST consult and measurement.**

**⚠ READ THIS BEFORE THE NUMBERED LIST BELOW: the stamp moved BACK to first.** The list is kept in its
original numbering because other text cites it, but the ratified order of work is:

> **stamp (item 2) → recorder / step 1a (item 1) → witness trial (item 3).**

The stamp went from *first*, to *parallel and buying nothing*, to *first again* — and the round trip was
not churn, it was two measurements. Round 1 demoted it when detection moved from grepping the transcript to
reading record structure. **Then structure turned out to identify the CHANNEL but not the HOOK**
(`hookName` is `<Event>:<ToolName>`, shared by every plugin on that tool; the delivery record carries no
`command`), so attribution needs a discriminator inside the record's `content`, and the stamp is the stable
form of it. **Owner ruling: stamp first, so attribution keys on a stable token from day one rather than on
message prose that fails silently toward zero — the v15 signature — the first time anyone edits a message.**

**Owner ruling on the `PreCompact` channel, same date: ship dispatch-only.** Record `compactions` as
session context grouped separately from delivery totals, state plainly in the output that `PreCompact`
reaching is unmeasured, and leave that channel to the witness trial (item 3). Rationale, independently
reached by the driver and the peer and verified by measurement: `PreCompact` hook firings produce **zero**
transcript records across all 112 project transcripts, so delivery there is unobservable; a hook writing
its own record would capture only that the script RAN, mislabelling it as reached and recreating the v15
illusion; and the channel touches **15 of 112 sessions (13%)** while step 1b is already scheduled to
relocate the trigger to an event that *is* logged. Consult brief and reply:
`.clavity/seams/discipline-efficacy-precompact-fork.md`.

The earlier negotiated ordering, for provenance: the peer's opening answer proposed *stamp -> counter ->
witness*; it then **explicitly superseded its own ordering** when shown that instrumenting a trigger that
does not fire is "testing a known null wire", and independently re-measured the enumeration below.

1. **Fix the direct-driver trigger placement. THIS IS A DEFECT IN v16, not new work.** MEASURED
   2026-08-04, independently by both sides, against `clavity-dotnet/plugin/hooks/hooks.json`: across all
   registered events, the number of hooks that prompt a driver working DIRECTLY — not dispatching, not
   compacting — to capture an anomaly is **ZERO**. `PreCompact` fires only on compaction, so a short or
   medium session never reaches it; `Agent|Task` requires a dispatch; `SessionStart` carries drain/triage
   notices for anomalies that already exist, not a capture prompt; and `agy-seam-inject.sh:54` matches
   only `*subagent-driven-development*|*executing-plans*`, with `:55` `*) exit 0` for every other skill.
   **v16 closed gap (a) only for sessions long enough to compact.**
   ✅ **SHIPPED 2026-08-07 as step 1b** (`40f9eaa` / `a527020` / `58afde2`). The count above was the
   measurement that justified the work and is kept as written; **it is now one, not ZERO.** Two coverage
   holes remain accepted — see item 1b in the WHICH-STEPS-SHIPPED block above.
2. **Static contract stamp in the emitted strings** — pure ASCII, byte-ban compliant, no per-driver
   literal (Option S, `docs/agy-disciplines-marker-contract.md:13`). It goes before the **trial**, and that
   reason is load-bearing and untouched: without it a null trial result cannot be split into *never fired*
   vs *fired and ignored*. Its own failure mode is a stale stamp after a message edit — pin it with a test.
   🔴 **This entry previously said the stamp was PARALLEL to step 1a and not a prerequisite. MEASUREMENT
   REVERSED THAT, and this is the corrected wording.** Record structure identifies the **channel**, not the
   **hook**: `hookName` is `<Event>:<ToolName>` (e.g. `PreToolUse:Agent`), shared by every plugin
   registering on that tool, and the delivery record `hook_additional_context` carries **no `command`
   field** to disambiguate. Measured on a real transcript: 6 structural matches on `PreToolUse:Agent`, of
   which **1** was this project's relay and 5 were an unrelated hook — a 6x over-count. Attribution
   therefore needs a discriminator **inside the delivery record's `content`** (which is immune to the three
   mechanisms that killed whole-file text matching, because authored prose and query echoes never land
   inside a hook attachment). **The stamp is the stable form of that discriminator** — without it the count
   keys on message prose and breaks silently toward zero on any wording edit, which is the v15 signature.
   The recorder can still ship first and match prose; it is simply brittle until the stamp lands. Version
   provenance — telling a stale install from a current one — remains a separate, untouched reason.
3. **Outside-witness trial.** Unprimed agent, unrelated repo, ordinary work, never told the discipline
   exists. Inspect the transcript for BOTH the stamp (delivery) and a real `.clavity/local-anomalies.md`
   entry (outcome). **The session that builds a discipline may never be the session that confirms it.**
4. **Firing counter — DROPPED, superseded by step 1a.** It was demoted for measuring activation volume
   rather than conversion (`12 / 0` is ambiguous — it can mean twelve sessions with genuinely nothing to
   capture), and it is now dropped outright: the step-1a recorder obtains the same signal by READING
   the transcript, so no hook writes on a fail-open path at all. That resolves the awkwardness this entry
   noted — `docs/agy-disciplines-marker-contract.md:55` and `:80-82` establish that **the skill writes and
   the hook never does**.

**✅ THE OPEN PROBLEM IS RESOLVED — it was an incomplete enumeration, not a real tension.** For the record,
because the reasoning that made it look impossible is worth keeping: the two obvious homes for a
direct-driver capture prompt were already dispositioned in this epic's own spec
(`docs/superpowers/specs/2026-08-04-agy-anomaly-capture-gap-design.md`) — a `Stop` hook / end-of-task seam
**withdrawn** (`:65`, *"fires 100+ times in a long session"*), and firing on tool output **rejected**
(`:67`, *"misses the quiet cases, fires on ordinary debugging"*). Reinstating either reproduces the
**"Anomalies noticed: none" reflex**. The apparent tension was that every event a direct driver reliably
reaches is HIGH-FREQUENCY, while the low-frequency events (`PreCompact`, `SessionStart`) never reach short
sessions.

**Both prerequisites this entry demanded have since been established, neither assumed:**

1. **The full event surface was enumerated.** `SessionEnd`, `UserPromptSubmit` and `PostToolUseFailure`
   appear **zero times** in this epic's spec, plan, or this ROADMAP, yet all three are real shipping
   events — `SessionEnd` and `PostToolUseFailure` at `~/.claude/plugins/cache/ecc/ecc/2.0.0/hooks/hooks.json:338`
   and `:248`, `UserPromptSubmit` in Anthropic's own marketplace. `PostToolUseFailure` has since been
   observed firing in a real transcript, so this is measured, not merely documented.
2. **A low-frequency trigger did not need to be derived — one already exists.** `SessionEnd` occupies the
   slot this entry assumed was empty: **fires once, reaches every session including short ones, and fires
   after the driver has demonstrably done work.**
   🔴 **BUT DO NOT REACH FOR IT WITHOUT READING THIS.** MEASURED 2026-08-05: a plugin hook registered on
   `SessionEnd` via `${CLAUDE_PLUGIN_ROOT}` **never runs** — the variable does not resolve at that event, so
   the hook is cancelled and writes nothing. Cancelled 3/3 with the variable; an absolute path from the same
   manifest worked 2/2. That is what shipped broken in v17 and is why step 1a's recorder moved to
   `SessionStart` (`docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md`). The event's
   *frequency* argument above still stands; its *reachability from a plugin manifest* does not. Anything
   registered there needs an absolute path, or another event.

**THE OWNER'S SPLIT, binding: MEASURE FIRST, PROMPT LATER.** Step 1 is therefore two halves:

- **1a — MEASURE (in progress).** A `SessionStart` recorder that answers, from recorded evidence, whether
  the **`PreToolUse` dispatch relay** reaches a driver. Designed in
  `docs/superpowers/specs/2026-08-05-sessionstart-capture-design.md` — which **supersedes the `SessionEnd`
  registration** in the 2026-08-04 spec, because `${CLAUDE_PLUGIN_ROOT}` does not resolve at `SessionEnd`,
  so the v17 hook was cancelled and wrote nothing. It **reads** the transcript; no hook on
  a fail-open path writes anything. **Validated end-to-end 2026-08-04** on a real 160 MB transcript located
  from a real hook payload: 6 deliveries detected in 3.0 s against a 10 s budget.
  🔴 **ONE channel, not two — and the missing one is v16's.** MEASURED across 8 transcripts holding 69
  compactions: `"hookEvent":"PreCompact"` appears **zero** times, while the identical filter finds thousands
  of `PreToolUse` records in every one of those files. **`PreCompact` hook firings are never written to the
  transcript**, so the capture reminder v16 shipped to close gap (a) is invisible to this mechanism. Its
  *opportunity* is countable (`isCompactSummary`); its *delivery* is not. The recorder therefore ships
  dispatch-only and says so, rather than emitting a `0` that would read as the v15 failure signature for a
  channel that may be working perfectly. Covering it needs either a hook that writes (breaking the marker
  contract's axiom) or the step-3 witness trial.
- **1b — PROMPT (deferred deliberately).** Where the direct-driver prompt eventually goes
  (`UserPromptSubmit`, `PostToolUseFailure`, or a derived trigger) is to be **decided from 1a's data rather
  than guessed** — which is the whole point of the split.

**Four things 1a's STEP 0 measured that this entry would otherwise have had you design around**
(2026-08-04, probes in `.clavity/scratch/discipline-efficacy/`): a hook firing writes a **typed
`attachment` record carrying `hookEvent` and `hookName`**, so delivery is detectable structurally with no
text matching; `hook_success` (the hook RAN) and `hook_additional_context` (its words REACHED the model)
are **different records**, and `fired > 0` with `reached == 0` is precisely the v15 failure in a single
row; concurrent appends **do** serialise on this platform; and **`CLAUDE_SESSION_ID` is `UNSET` in the hook
environment**, so anything here that needs session identity must read it from the payload.

**Also carry into the design: "synthetic trial overfitting"** (the peer's named failure mode for step 3).
If the induced defect is loud and resembles the prompt's own examples, the model logs it and the trial
reads GREEN — while the defects that matter are subtle, out-of-scope oddities noticed under load. The
trial needs a defect the prompt does NOT resemble, or it reproduces this item's own failure one level out.

**The acceptance test for this item is itself an efficacy test**: it is done when you can answer "is
AGY-ANOMALIES working for real users?" from recorded evidence, without asking any agent what it thinks
happened.

### ~~1. `clavity --restart-agy` (classic) — 7.7~~ · 🚫 **KILLED 2026-08-06 (clauses 1 + 2)**

> **last-triaged: 2026-08-06.** Oracle: `rg 'restart-agy|restart_agy'` over `clavity-classic/src/` and
> `clavity-dotnet/src/` returns **NOT IMPLEMENTED**, and `git log --grep='restart-agy'` finds only docs,
> plan and renumber commits (`58119e9`, `252f63c`, `e56d6a7`) — no implementation. So it is genuinely
> unbuilt; it dies on the bar, not on the oracle.
> - **Clause 1 — FAILS.** Its absence causes no silent data loss, no crash and no false diagnostic. The
>   hang that motivated it is agy's; the absence only makes *recovery* costly. Losing the driving session
>   to a full `clavity start` is disruptive but it is not silent — the operator chooses it knowingly, which
>   is exactly what clause 1's "an operator would act on it, and the action is wrong" does not describe.
> - **Clause 2 — FAILS.** A working alternative exists today (full teardown and restart). The gap is
>   neutralised by an ordinary operating convention, which clause 2 rejects.
> - **Clause 3 — passes.** The mechanism is concrete: relaunch only the agy psmux session under the same
>   `--session`, re-run agy's exact launch, confirm readiness via a `ping`. **Passing clause 3 alone is not
>   survival; all three are required.**
>
> ⚠️ **This is an ergonomic gap, and killing it is not a claim that it is worthless** — it is a claim that
> it does not clear a bar built to reject everything that is merely nice. Git is the undo.
Agy-only restart: tear down + relaunch ONLY the agy psmux session under the same `--session`, WITHOUT co-launching
a new Claude (today only `clavity start` relaunches, which orphans the driving session). Re-run agy's exact launch
+ confirm readiness via a `ping`. Surfaced 2026-06-29 when an agy MCP hang forced a full teardown mid-session.

### 2. Golden-header tamper-detection — 7.4 · ✅ SHIPPED · **spot-checked 2026-08-06**
**Verified in code 2026-08-06** — `Clavity.Ls/GoldenHeader.cs` reads the `.sha256` sidecar at read-time,
warns and degrades the region to absent on mismatch, and enforces a 1 KiB sidecar cap (`:26`, `:79-80`,
`:106-111`). The honest threat model is stated in the source itself (`:97` — it catches torn writes and
naive hand-edits, not a same-user adversary who rewrites both). Kept here rather than moved to Shipped
because §0 forbids renumbering: every citation to §7 and §8 depends on these indices.

~~Compare `golden-header.md` to its `.sha256` sidecar at read-time; LOUD warning on external change.~~

### 3. Dynamic send-model resolution (dotnet) — T10 follow-up · ✅ SHIPPED as v0.1.9 · **spot-checked 2026-08-06**
**Verified in code 2026-08-06** — `Clavity.Ls/SendModelResolver.cs` resolves `default_agent_model_id` →
the `models` map → the concrete model (`:37-44`), and `LsClient.cs:65` states that the literal `1037` now
"lives in exactly one place" as the too-old-agy fallback. This entry described the hard-coded state that
v0.1.9 removed, and it sat in the forward backlog while also appearing in the Shipped list above —
**the same work listed as both done and pending.**

~~`AgyView` hard-codes the send model id (`MODEL_GEMINI_3_1_PRO_HIGH = 1037`)… resolve dynamically.~~

### ~~4. Packaging verifications — 7.5 / 7.6~~ · 🚫 **KILLED 2026-08-06 (clause 1)**

> **last-triaged: 2026-08-06.** Both halves are *"confirm X"* tasks with **no code deliverable**, and that
> is what kills them.
> - **Clause 1 — FAILS, and strictly.** An **unverified property is not a false diagnostic.** Nothing here
>   prints a wrong answer an operator would act on; the roadmap simply does not yet know whether two
>   properties hold. **Widening clause 1 to cover "we have not checked this" readmits every unbuilt
>   verification task in the repo**, which is most of what the clause exists to reject (see §7a).
> - Oracle, for the record: both skills exist — `plugin/skills/ls-driving/SKILL.md:2` and
>   `plugin/skills/ls-pairing/SKILL.md:2`. 7.5 asks whether the dual-plugin format *scopes* them per host,
>   and 7.6 whether a path-installed plugin auto-updates away from the pinned `{app}` binary.
>
> ⚠️ **If either property turns out to be FALSE, that is a new defect with its own evidence** — and it
> enters as a defect, not as a resurrected verification task.
- **7.5** — confirm the dual-plugin format scopes `ls-driving` to Claude and `ls-pairing` to agy
  (else rely on contextual invocation + document).
- **7.6** — confirm Claude/agy don't auto-update a locally path-installed plugin away from the version-pinned
  `{app}` binary.

### 5. dotnet golden-header parity follow-ups · ✅ SHIPPED (both bullets) · **spot-checked 2026-08-06**
The classic 7.3 implementation (`src/golden_header.rs`) is the canonical golden-header behavior; two dotnet
divergences were found during the Spec A capstone. **Both verified aligned in code 2026-08-06:**
- ~~**`GoldenHeader.Apply` trim charset**~~ — **DONE.** `GoldenHeader.cs:201` and `:206` trim with `AsciiWs`,
  matching classic's ASCII-only set. The full-Unicode `TrimEnd()` this entry describes is gone.
- ~~**Sidecar write order/atomicity**~~ — **DONE.** `GoldenHeader.cs:214-217` states the contract in its own
  words — "Sidecar-after-target-rename, mirroring Rust `commit`" — and `:266-272` implements it: the header
  goes tmp→move first, and only then the sidecar, atomically via its own tmp+rename. The source also records
  WHY that order matters (a failed move leaves the old header and old sidecar mutually consistent, rather
  than a fresh hash accusing a header that was never replaced).

### ~~6. agy-autotrain knowledge-delivery — driver-side effectiveness measure~~ · 🚫 **KILLED 2026-08-06 (clause 1)**

> **last-triaged: 2026-08-06.** Killed on clause 1, and it is the item that **proved clause 1 must stay
> narrow** — so killing it is the bar working, not the bar being harsh.
> - Its ask is *"a probe / verify-harness confirming a delivered rule demonstrably changes driver behaviour
>   … so 'delivers better driving' is substantiated, not assumed."* That is an **unvalidated assumption**,
>   not a **false diagnostic**. Nothing prints a wrong answer an operator would act on.
> - **Widening clause 1 to admit it readmits every unbuilt validation harness in the repo** — including §4,
>   which this sweep just killed on the identical reasoning. A clause that admits all of them cannot reject
>   any of them.
>
> 🔴 **Why §0 gets a gate and this does not, since their clause-1 failure is IDENTICAL.** The difference is
> not the argument, it is the marking. §0 is **`▶ TOP PRIORITY`, owner-directed**, so it reaches the
> Phase-2 gate asking *"the bar rejects this — do you override?"*. §6 is marked **`Owner-surfaced
> 2026-07-11`** — surfaced is not directed, so clause (a) of the §5 exception test is not met and no gate
> question is owed. **If that reading of "Owner-surfaced" is wrong, this kill is wrong with it** — it is
> the single assumption holding §6 out of the gate, and it is stated here so it can be overturned in one
> sentence.
The agy-knowledge-delivery design (`docs/superpowers/specs/2026-07-11-agy-knowledge-delivery-design.md`, panel-GREEN)
closes the driver-facing consume gap — it pushes a curated `[driver_guidance]` cheatsheet at drive-time. But it
**delivers** knowledge without **validating** that driving actually improved (delivery ≠ outcome; a ≤150-tok block is
a nudge, not enforcement). The peer side has a verify-harness (`agy-autotrain/verify/`); the driver side does not.
Add a **driver-side effectiveness measure** — a probe / verify-harness confirming a delivered rule demonstrably
changes driver behaviour on a known-failure scenario — so "delivers better driving" is substantiated, not assumed.
Shares the same empirical-measurement question as the golden-header per-ask backlog stub
(`docs/backlog/golden-header-per-ask-token-optimization.md`, the anti-drift trade-off). Owner-surfaced 2026-07-11.

### 7. AGY-SCOPE — "pre-existing defects are always in scope" as a shipped discipline · ✅ **SHIPPED 2026-08-07**
**Status: designed, shipped and mirrored.** Owner-directed 2026-07-31; ships, like its siblings, with the
clavity plugin (alongside `adversarial-panel-review` / `agy-test-audit`, mirrored to clavity-classic).

> ### ✅ SHIPPED as a CROSS-CUTTING AMENDMENT, not a fourth discipline
>
> Owner ruled the shape 2026-08-07. The disposition half ships as a five-token taxonomy inserted into
> `adversarial-panel-review`, `agy-capstone` and `agy-test-audit`, gated on each skill's completing
> verdicts, plus an intake-bar and routing clarification in `open-issues`. Pinned by the
> `AGY-SCOPE disposition taxonomy` Describe and the per-token mutation rows in
> `scripts/tests/check-agy-discipline-skills.Tests.ps1`.
>
> Design questions 2-5 are answered in
> `docs/superpowers/specs/2026-08-07-agy-scope-disposition-design.md`; question 1 was the owner's shape
> ruling. Deferred deliberately: enrolling `adversarial-panel-review` in the discipline checker (it
> carries 69 non-ASCII characters and no marker constant, so it fails two unrelated gates), and
> backfilling the five known coverage gaps onto the conveyor.

**The defect it fixes.** Every review discipline in the family (AGY-AFTER, AGY-CAPSTONE, AGY-TEST-AUDIT) produces
findings, and none of them says what a finding's **age** means. In practice the driver reaches for "pre-existing /
not introduced by this commit / out of scope for this change" as a *disposition* — which is not a severity
argument at all. Two independent axes get collapsed:
- **severity floor** — the legitimate stand-down, for *contrived / exotic / unreachable* edges, whatever their age;
- **provenance** — how old the defect is, which carries **zero** dispositional weight.
Collapsing them silently drops reachable defects, and mirrors the same error onto new code (a contrived new-code
edge gets folded because it's "in scope" while a reachable old one gets dropped because it isn't).

**Evidence it is real, not theoretical.** Two findings surfaced during the agy-test-audit epic — the seed-sync
jq-missing silent-pass and the check-roster `Assert-SharedMapHealthy` installer/dotnet gap — were dutifully
"surfaced to the owner" and were still open, untracked and unplanned, days later. A third (capstone F2, the
`LsDiscovery.cs` gRPC/HTTP pid-pair mismatch) was very nearly filed under the severity floor for the wrong reason
— its age rather than its reachability. Surfacing without a tracked plan is not a disposition either.

**Open design questions for the brainstorm** (do NOT pre-answer these here):
1. **Shape** — a skill (like AGY-AFTER/AUDIT), a rule body in the global `CLAUDE.md` (like AGY-CAPSTONE), a linter
   over review output, or a *cross-cutting amendment* to the three existing disciplines rather than a fourth
   sibling? The family-coherence pass already parked a "shared adversarial-review core" question (#2/#3) that this
   overlaps — resolve them together or explicitly not.
2. **Enforcement point** — is this checkable mechanically? A finding's disposition line could be required to cite
   a *reachability* verdict, letting a linter reject "pre-existing" as a stated reason. Or is it purely a
   judgment rule that only a peer review can catch?
3. **Where a verified-but-deferred pre-existing defect LANDS** — the deferred/do-not-re-raise ledger is explicitly
   for severity-floor stand-downs and must not become a parking lot. Does this need its own tracked-debt surface,
   and does it reuse the agy-test-audit rolling debt file?
4. **Scope boundary** — "always in scope" cannot mean an unbounded audit of the whole tree on every review.
   What bounds it: the reviewed diff's blast radius, the touched files, the subsystem? Getting this wrong makes
   the discipline too expensive to obey, which the family has already learned gets it routed around.
5. **Owner-scoping** — like AGY-TEST-AUDIT, the driver should surface + plan, never unilaterally expand the work.
   What is the hand-off artifact, and how does it avoid the exact rot documented above?

Driver-side rule already captured in memory (`feedback-preexisting-defects-in-scope`) so the behaviour binds now;
this item is about making it a **shipped, installable** discipline rather than one driver's private note.

**Update 2026-08-01 - the CAPTURE half is now built and shipped.** An anomaly an agent spots while doing
something else is reported by whoever noticed it, verified by the driver, and written to a gitignored
`.clavity/local-anomalies.md`, and a
SessionStart hook counts the untriaged entries and demands triage until the file is empty (see the
`open-issues` skill). Design converged with the agy peer over an AGY-FIRST consult plus two negotiation
rounds. What remains for AGY-SCOPE is therefore only the DISPOSITION half: that a defect's age is never a
disposition, and that a verified pre-existing defect earns a tracked plan rather than a mention. The five
open design questions above are unchanged; they were always disposition questions.

### 8. Audit spending — round count, capstone placement, model tiering (BRAINSTORM FIRST) · ✅ **ANSWERED 2026-08-06**

> **✅ CLOSED as ANSWERED — the brainstorm this asked for was overtaken by a shipped epic.** The agy
> discipline cost/quota hygiene epic ran and reached **capstone GREEN, owner-confirmed**, over
> `c7b3923..8889473` (`docs/agy-capstone-ledger.md`, row dated 2026-08-03). **All three levers below now
> have measured answers, and two of them are refuted.** Measured 2026-08-06 (open-work sweep, Task 5).
>
> - **"Fewer agy rounds" — REFUTED.** agy rounds are **~2% of driver spend**; peer inference is billed
>   peer-side. Cutting rounds cannot buy what this lever assumed it would.
> - **"Cheaper models on the mechanical work" — REFUTED as a *cost* lever.** All tool results across a long
>   session total **~88k tokens against ~610k of the agent's own prose (~7:1)**, so delegating bulky output
>   is bounded by that 88k. (The bottom-up gating rule still stands on its own merits — this refutes the
>   *saving*, not the practice.)
> - **"Batching capstones to the end" — ANSWERED, and INVERTED.** **87.2% of spend is context re-payment**,
>   not generation. The real lever is **WHEN a discipline runs, not how many rounds**: the same 305 turns
>   cost **$249 at ~380k context versus $47 at 40k**, and **a capstone at turn 500 pays ~5x the identical
>   capstone at turn 50.** So §8's framing had it backwards — *batching to the end is the expensive
>   direction*; running the review early, at low context, is the cheap one.
>
> **The tension §8 insisted on was honoured, not papered over:** the saving is located in **waste** (context
> re-payment at peak) rather than **coverage**, so neither "review is investment" nor the waived round-cap
> is overturned. **Nothing here trades coverage for cost.**
>
> ⚠️ **Left in place and NOT renumbered** — §0 forbids renumbering because every citation to §7 and §8
> depends on these indices.

~~**Status: brainstorming task, not yet designed.** Owner-directed 2026-07-31.~~

The AGY-* disciplines are deliberately expensive: rounds-until-green, verify-every-finding-by-measurement,
verify-the-peer's-fix-too. That expense has repeatedly paid — it has caught a reachable protected-file gate
evasion, an index smuggle, a wrong peer fix, and an incomplete one. The question is **not** whether review is
worth paying for; it is whether the current *shape* of the spend buys the most defect-detection per unit cost.
Three candidate levers, to be evaluated (not assumed):
- **Fewer agy rounds** — is the marginal round finding real defects, or restating? Rounds visibly decay in
  severity toward green, so the interesting number is *findings-per-round*, and whether an earlier stop loses
  anything a cheaper check would have caught anyway.
- **Batching capstones to the end rather than per-stage** — today a multi-task epic can pay a capstone per stage.
  One capstone over the whole committed range costs less and sees cross-stage interactions a per-stage review
  structurally cannot; against that, a defect caught late is a defect built upon, and a whole-range review has
  more surface to skim. Which failure mode dominates is an empirical question, not a taste one.
- **Cheaper models on the mechanical work** — the bottom-up capability-gating rule already exists in the global
  `CLAUDE.md` (Haiku for sweeps/summaries/specified edits, Sonnet for contained implementation, Opus reserved for
  architecture and hard debugging). The gap is *adherence*, not policy: sessions routinely run log sweeps, file
  reads, and mechanical verification on the Opus main thread and delegate nothing.

**The tension that must be resolved head-on, not papered over.** The owner's standing rulings are "review is
INVESTMENT, not cost; stop only when findings dry up" and the panel round-cap is WAIVED ("repeat until green").
A naive cost-cutting pass would silently overturn both. Any outcome here has to either (a) show the saving comes
from *waste* (redundant rounds, wrong-tier work, duplicated context) and not from *coverage*, or (b) be an
explicit owner decision to trade coverage for cost. Cheaper-but-blinder is a regression, not a win.

**Open design questions for the brainstorm** (do NOT pre-answer these here):
1. **Measurement first** — what is even instrumented today? Cost per session/turn is visible to the driver via
   hooks, but findings-per-round, tier-of-work, and cost-per-verified-defect are not recorded anywhere. Without
   that, every lever above is guesswork. Is a lightweight review-telemetry file the actual first deliverable?
2. **What counts as waste vs coverage** — needs a definition sharp enough to decide cases, e.g. a round that
   produces only already-ledgered findings, or Opus doing a `grep`-equivalent sweep.
3. **Capstone placement** — per-stage vs batched vs hybrid (cheap per-stage smoke + one deep whole-range
   capstone). Does the marker-gated hook mechanism from agy-test-audit already support the batched shape?
4. **Enforcing the tiering that already exists** — is this a hook (warn when the main thread does bulk mechanical
   work), a checklist item in the execution skills, or purely driver discipline? Prior art says a rule too
   expensive or too invisible to follow gets routed around.
5. **Scope** — driver-side only, or does it also cover the peer (payload size, filepath-not-paste transport,
   avoiding re-sends after a timeout)? Peer latency is payload-bound, so transport hygiene may be a cheap win
   independent of round count.

Evidence to seed the brainstorm: a single session on 2026-07-31 spent >$60 delivering a one-line regex fix plus
docs, memory maintenance, and one capstone round — with **zero** subagent delegation despite several stretches of
purely mechanical log-sweeping and file-reading, and with the whole bulky measurement context held on the Opus
main thread. That session's capstone round was *not* the waste: it caught a real regression the author missed.

### ~~9. Tracked debt — clavity-classic consult guard: binary-native vs bash hook~~ · 🚫 **KILLED 2026-08-06 (clause 3)**

> **last-triaged: 2026-08-06.** Killed on clause 3 — **an unresolved design fork**, by its own words:
> *"It remains undecided and is recorded here so it stops being invisible."* The originating spec
> (`docs/superpowers/specs/2026-07-22-ship-agy-disciplines-design.md:134`) left it *"to resolve in SP3, via
> AGY-FIRST"*, and SP3 never happened — the spec was superseded and the fork was **orphaned rather than
> decided**.
>
> 🔴 **Clause 3 KILLS, it does not park — and this entry is the clearest example of why that ruling
> exists.** "Recorded here so it stops being invisible" is precisely the guilt-free parking state the
> disposition bar was written to end: visible, undecided, and carried forward indefinitely at no cost to
> anyone. The owner ruling attached to it (*"it does NOT gate the productize release"*) is a **disposition,
> not a directive**, so it earns no §5 gate question.
>
> ⚠️ **Killing it does not decide the fork** — it removes a permanent placeholder for a decision nobody is
> scheduled to make. If the guard is ever needed, it returns as a specced item with a chosen mechanism, and
> git holds this text.

`docs/superpowers/specs/2026-07-22-ship-agy-disciplines-design.md:134` left this fork open "to resolve
in SP3, via AGY-FIRST". That spec was superseded by the ship-agy-workflow epic, which drops the guard
from scope, so the fork was orphaned rather than decided. (The superseded spec calls it "ME1"; that
task ID means nothing to a reader, so it is named descriptively here — owner ruling 2026-08-05.) Owner ruling 2026-07-31: it does NOT gate the
productize release. It remains undecided and is recorded here so it stops being invisible.

### ~~10. Follow-on epic — productize the two later disciplines~~ · 🚫 **KILLED 2026-08-06 (clause 1)**

> **last-triaged: 2026-08-06.** Killed on clause 1, judged strictly as this entry's own framing demands.
> **Name the wrong action its absence induces — there isn't one.** Two disciplines not yet packaged into a
> release causes no silent loss, no crash, and prints no false diagnostic; `agy-test-audit` shipped
> 2026-07-27 and works, it is simply not bundled.
>
> ⚠️ **It is also gated on an item that may not survive**: half its scope is `AGY-SCOPE` (§7), which is
> still undesigned and goes to the Phase-2 owner gate asking *"spec it, or kill it"*. **A packaging epic
> for a discipline that may be killed cannot be ranked ahead of the decision that decides it.**
>
> ✅ **Resolved 2026-08-07 — that gate has been answered: §7 was specced, shipped and mirrored, so
> "may not survive" no longer holds.** The paragraph above is preserved as the triage record of
> 2026-08-06, not as a live claim. The kill itself rests on **clause 1**, which is independent of this
> second ground and stands unchanged. **Owner ruling 2026-08-08: the KILL STANDS.** The resolved gate is
> not reason to revisit it — clause 1 was always the load-bearing ground, and the AGY-SCOPE gating was
> reinforcement, so removing the reinforcement does not disturb the kill.
>
> The owner ruling it carries (*"they are a follow-on, not a re-scope — retroactively widening a stalled
> epic prevents it closing"*) is preserved above and remains sound; killing this entry does not disturb it.

`agy-test-audit` (shipped 2026-07-27) and `AGY-SCOPE` (shipped 2026-08-07) postdate the ship-agy-workflow epic
and are not in its model. Owner ruling 2026-07-31: they are a follow-on, not a re-scope — retroactively
widening a stalled epic prevents it closing. This epic closes at four disciplines.

### 11. PINNING-ASSERTION-STRENGTH — ship assertion-strength as a mechanical discipline · ✅ **SHIPPED 2026-08-08** (`674b0f1` suite+registration · `c12af5b` hook, dotnet · `318889d` classic mirror · `d045777` widened Step 5 · this reconcile)

> **last-triaged: 2026-08-06.** The only item on this surface to clear the bar outright.
> - **Clause 1 — MET, and this is the textbook case.** A cardinality assertion prints **PASS** over
>   reversed sort logic. A green test is a diagnostic a competent operator acts on, and the action —
>   merging — is wrong. **Measured, not argued:** `5071872` records the mutation in which the ring deletes
>   its three *newest* slots, including the snapshot written moments earlier, while the count stays exactly
>   N and the test stays green.
> - **Clause 2 — MET.** Not neutralised by any existing invariant: the blind test shipped **through an
>   adversarial panel that had already gone GREEN**, so the review layer demonstrably does not catch it.
> - **Clause 3 — MET.** The design is settled, converged with the peer over three negotiation rounds with
>   every concession verified. It is not a fork awaiting a decision.
>
> **Oracle:** `df2b907` *"docs(roadmap): capture PINNING-ASSERTION-STRENGTH"* is a **docs** commit;
> `git log -S'SortAndTruncate'` returns no implementation. Captured, not built.

**Owner ruling 2026-08-02:** the AT-2 session's ad-hoc "add tests for uncovered cases" ruling should ship
as a standing discipline. Design converged with agy over three negotiation rounds; agy conceded every
contested point and the concessions were verified (it cited `~/.claude/CLAUDE.md:36` unprompted and
correctly, and volunteered a false-positive case I had not listed).

**Why it exists.** During AT-2 a plan that had passed an adversarial panel GREEN still shipped a blind
test. `Commit_prunes_the_ring_to_the_retention_limit` asserted only that N slots survived a prune.
Reversing the prune's sort makes the ring delete its three *newest* slots — including the snapshot written
moments earlier by the very commit that triggered the prune — and the count is still exactly N, so the
test stays green. Measured, not reasoned: `5071872` records the mutation. Cardinality is a weak observer;
`Count(SortAndTruncate(c, K))` is invariant under *any* permutation before truncation.

**Agreed shape** (do not re-derive; these are settled):
- **Mechanical, no peer.** The detector was a test runner, not a reviewer. Routing it through agy adds
  cost without detection power.
- **Plugin-only home.** Canonical prose is the ONE paragraph at `plugin/skills/agy-test-audit/SKILL.md`
  Step 5 (**`:88-99` as shipped** — this section long read `:88-96`, which was already stale before
  execution: the §7 AGY-SCOPE amendment grew the paragraph. Measured 2026-08-08), widened to reach tests
  written during ordinary implementation. That paragraph already
  specifies logic-mutant-not-structural and "confirm the SPECIFIC new test went red" — the gap was never
  missing prose, only prose scoped to audit-gap tests. **No `CLAUDE.md` copy** (`CLAUDE.md:62,91` record
  the standing decision that disciplines ship with the plugin and leave no residue there).
- **Drop the `AGY-` prefix** — every `AGY-*` discipline convenes the peer; this one does not.
- **Trigger:** `PostToolUse` hook on `Write|Edit`, debounced to the FIRST touch of each test file per
  session. Ungated firing was rejected: it would have fired 15+ times in the AT-2 session, and an
  over-eager guard trains the operator to ignore it — recorded in the AT-2 design as how an earlier guard
  in this repo actually died.
- **The three structural smells:** (1) cardinality over an ordered/filtered collection — assert boundary
  *identity*, never count alone; (2) a dual-path fallback masked by the ambient environment — strip the
  primary dependency to force the fallback; (3) a structured-token matcher with no distractor case.

**Four defects in agy's draft implementation — fix these when building, do NOT paste its code:**
1. It writes markers to `.clavity/marks/`, which **does not exist**. The real directory is
   `.clavity/agy-marks/`, governed by `docs/agy-disciplines-marker-contract.md`. Fabricated path.
2. Its hook **hard-depends on jq** (`command -v jq || exit 0`), making it silently inert on any box
   without jq — the exact defect class AT-2 Task 1 closed, where the field-bounded-grep fallback is the
   branch most installs actually run. Every sibling hook carries that fallback.
3. Its `hooks.json` snippet uses the wrong schema — the real shape is a top-level `hooks` key with a
   nested `hooks:[{type:"command",command:...}]` array.
4. ~~`agy-test-audit-reminder.sh:10` states it **never** writes a marker, by design. A debounce marker is a
   different thing from an outcome marker, but the deviation needs a deliberate decision, not a silent
   one.~~ 🚫 **NOT AN OPEN DECISION — it was already made in writing, and this entry was wrong to ask.**
   `agy-anomaly-capture-reminder.sh:49-53` states it outright: a hook marker *"must never live in
   `.clavity/agy-marks/`, must never be read as evidence that anything was DELIVERED, and must never be
   named `*.head`"*, and — verbatim — *"That reason does not apply here — this records a fact the hook does
   know, that it already emitted."* Confirmed by `docs/agy-disciplines-marker-contract.md:1`
   (*"skill writes, auto-fire hook reads"*). The shipped hook follows that precedent exactly.
   **Generalises: before treating a ROADMAP "open decision" as open, grep for a sibling that already
   decided it** — this one cost a design question that had been answered weeks earlier.

**Cost:** ~190-220 tokens per firing, ~2 firings per session; verification is one targeted test run per
directional or fallback assertion. Both variants' plugins must change together (byte-identical pair).

### 12. Post-plan-2 leftovers — two guards that overstate what they verify · ✅ **SHIPPED 2026-08-07**

Both entries came out of `.clavity/local-anomalies.md` at the triage that followed plan 2's capstone. Each
was verified by measurement before promotion, and each is stated with the measurement that establishes it.
**Shared theme, and the reason they are one section: each is a mechanism that TELLS THE READER it checked
something it did not actually check.** That is the same disease as §0 — presence mistaken for proof.

#### 12a. The consult guard cannot tell the agy peer from a concurrent local subagent · ✅ **SHIPPED**

✅ **SHIPPED 2026-08-07** — `56d6014` (dotnet message) + `0c3be8c` (byte-identical classic mirror).
**Pinning test:** `scripts/tests/agy-consult-guard.Tests.ps1` → `names the concurrent-local-agent confound
in the breach warning`, which asserts the existing `VERSION CONTROL CHANGED` alarm still fires *and* that
the message now carries `CANNOT attribute` and `concurrent`. It was **verified red before the fix** (failing
on `CANNOT attribute` against the old message) rather than assumed. The pre-existing file-level gates —
pure ASCII and byte-identical-to-mirror — both still hold; the new clause is pure ASCII by measurement.

**Only the message changed.** The seven axes were not narrowed, the breach wording was not downgraded, and
the guard was not made silent when local agents are active — see the ⚠ below, which still binds. The
*optional* half of the mechanism (recording whether local agents were dispatched during the window and
downgrading the wording accordingly) was **deliberately not built**: it needs state the hook does not have,
and naming the confound is what makes the already-advised verify step actionable.

**The provenance below is kept deliberately** — it is the measurement that justified the change.

`clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` (and its byte-identical classic mirror) detects a
review-only breach by comparing seven axes of VCS state captured before the consult against the state after
it. **It has no way to attribute a change to the peer rather than to anything else running in the same
repository at the same time.**

**MEASURED 2026-08-07.** During plan 2 a capstone round was issued while an implementer subagent was
mid-task. The guard fired, naming the three files that subagent was editing, one of which carried a
deliberate temporary mutation. The peer had changed nothing.

**Against the bar:**

1. **Loss.** Not silent — the failure is a LOUD false alarm, which is worse in a specific way: this alarm
   is security-grade ("ARBITRARY-CODE-EXEC vector" is one of its axes), and an alarm that cries wolf during
   ordinary subagent-driven work trains the driver to discount it. The message's first instruction is
   *"verify the peer (not you) made these changes"* (**the pre-fix wording — `56d6014` replaced it**) —
   which is correct and is what caught this one — but a
   driver who skips that step and follows the next clause would revert a subagent's in-flight work.
2. **Unavoidable.** Subagent-driven execution is the standard workflow, and consults are issued during it.
   Any overlap reproduces this.
3. **Mechanism.** Bounded: add a clause to the breach message naming the concurrent-local-agent confound as
   the likeliest benign cause, so the verify step is not merely advised but explained. Optionally record
   whether local agents were dispatched during the consult window and downgrade the wording when they were.
   **Both driver plugins must change together (byte-identical pair), and `agy-consult-guard.Tests.ps1` is
   the suite.**

⚠ **Do NOT "fix" this by making the guard quieter or by narrowing its axes.** The axes are load-bearing; a
prior capstone caught a real index-smuggle through one of them. The defect is the attribution, not the
detection.

#### 12b. The new emission arm's jq-absent path is completely untested · ✅ **SHIPPED**

✅ **SHIPPED 2026-08-07** — `4252ad5`, **test-only; no shipped code changed.**
**Pinning test:** `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1` → `delivers the SAME
UserPromptSubmit envelope with and without jq`. The suite went 25 → 26.

🔴 **This test PASSED on arrival, so its green run was not evidence** — the path already worked; the defect
was that it was unpinned. It was therefore proven non-vacuous by mutation: misspelling `hookEventName` as
`hookEventNam` at `agy-anomaly-capture-reminder.sh:156` turned **exactly one** test red — this one. That
single-test result is the second half of the finding: it re-confirms by measurement that *nothing else in
the suite reads that line*, which is precisely the gap this entry recorded. The hook was then restored and
`git diff --exit-code` verified clean.

**The provenance below is kept deliberately** — including the rewrite note, which is a worked example of the
incomplete-fold failure mode this repo keeps paying for.

🔴 **THIS ENTRY WAS REWRITTEN 2026-08-07, BEFORE ANY WORK STARTED ON IT.** As first written it claimed a
hook comment at `:29-30` falsely advertised a byte-parity test. **That comment no longer exists** — plan 2's
Task 1 replaced that block, comment and all. The original capture was taken against a *pre-plan-2* reading
of the file and was never re-verified against the file plan 2 had already changed: an incomplete fold, in
the entry written to record someone else's. It was caught by read-verifying every citation before writing
the implementation plan, which is exactly what that discipline is for. **The surviving defect below is a
different and better one, established by measurement.**

`agy-anomaly-capture-reminder.sh` now has **two** emission arms, each with a `jq` path and a hand-built
jq-absent path: `UserPromptSubmit` → `hookSpecificOutput` (`:156` printf, `:199` jq), and everything else →
`systemMessage` (`:157` printf, `:200` jq).

**MEASURED 2026-08-07.** Every `NoJqPath` test in `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1`
(`:119`, `:138`, `:171`, `:208`, `:217`) invokes the hook with **no `-Arguments`**, so all of them take the
`PreCompact` branch. **The count of tests exercising the `UserPromptSubmit` arm's jq-absent path was ZERO**
(at the time of measurement; `4252ad5` made it one).
The path works today — probed directly, it emits valid JSON with `hookEventName` = `UserPromptSubmit` — but
nothing in the suite would notice if it stopped.

**Against the bar:**

1. **Silent loss.** Yes, and it is the same shape as the defect that created this hook: the jq-absent branch
   is *"the branch most installs actually run"* (AT-2's lesson), it is hand-built `printf` with no escaping
   machinery, and a malformed brace or a wrong key there would emit nothing the model can read — **no error,
   no output, and it looks installed and working.** Every existing test would stay green.
2. **Unavoidable.** It ships enabled to every user of both drivers on every prompt.
3. **Mechanism.** Bounded: add a jq-vs-jq-absent comparison for the `UserPromptSubmit` arm, mirroring the
   existing one at `:135-142` and keeping its non-vacuity guard (that guard exists because a prior version
   of this very test passed green against a hook that did not exist). Comparing the two `.StdOut` values
   directly is the right assertion — `Invoke-BashHook` already `.Trim()`s, so a raw comparison tolerates the
   platform's trailing-newline difference while still catching a structural divergence.

**Note, recorded so it is not re-discovered as a defect:** the two paths are genuinely *not* byte-identical
on this platform — Windows `jq` terminates with `\r\n`, `printf` with `\n` (611 vs 610 bytes on the new arm,
600 vs 599 on the old). It predates plan 2, a trailing line ending is harmless to a JSON consumer, and the
`.Trim()` above is what makes it a non-issue for the test. **Do not "fix" the line ending.**

#### Assessed and deliberately NOT promoted

- **A tab between the slash command and its arguments does not trigger the inbox snapshot.** Measured with
  a firing space-separator control: it fails on BOTH the jq and grep paths identically (the fallback greps
  the RAW payload, where a tab is the two characters `\t` and a backslash is not `[[:space:]]`). The four
  `case` patterns are a deliberate complete set. **Below the reachability floor** — recorded in the backlog
  entry's *Known limit* section, not tracked here.

### 13. Anomaly promotions — three entries from the 2026-08-10 triages (13c later corrected) · ✅ **DONE 2026-08-20**

Promoted from `.clavity/local-anomalies.md`. Every one was **verified by measurement at triage**, not
accepted on reading; two other entries in that file were deleted with recorded reasons (see the triage
note there). 13c arrived in a later triage the same day, captured by a different session.

#### 13a. The gate tells operators it reports unused exemptions — no code path can · ✅ **SHIPPED 2026-08-16** (`39f9545`). VERIFIED 2026-08-17: the false sentence is GONE - `grep -c 'reports unused exemptions' scripts/check-injected-context.ps1` = **0**, and the replacement names the suite that actually catches a stale exemption.

`scripts/check-injected-context.ps1:701` prints:

> `an exemption whose file stops failing its invariant is reported as unused and must be deleted.`

**MEASURED 2026-08-10:** the gate has **no unused-exemption reporting at all**.
`Get-InjectedContextViolations` reads `$exempt` only via `.ContainsKey()` and never iterates it after the
walk, so nothing can emit that report — the string `unused` appears exactly **once** in the whole script,
in that message. The guarantee exists **only** in `scripts/tests/check-injected-context.Tests.ps1:663`,
which an operator running the gate does not run.

**Why it matters:** an operator who waives a file, later fixes it, and waits for the gate to tell them the
waiver is now stale will wait forever. The stale exemption then reddens CI through a *different* surface
with a *different* message.

**Two candidate dispositions — the owner scopes which:**

1. **Correct the sentence** (one line): say that CI's test suite reports unused exemptions, not the gate.
   Cheapest, honest, no behaviour change.
2. **Implement the reporting** in the gate: track which `$exempt` keys were queried during the walk and
   report the unqueried ones. Real work, and it makes the gate's own claim true.

⚠ **This lands on `feature/injected-context-governance`, which has an OPEN AGY-CAPSTONE.** Any fix extends
that review range — schedule it with that epic's remaining work (Stage 2, AGY-TEST-AUDIT), not as a
drive-by.

#### 13b. No discipline requires a peer's ANSWER to survive truncation · ✅ **SHIPPED 2026-08-20** (`20f38cc`; built then TRIMMED over the range `103aa87..20f38cc`, AGY-CAPSTONE **GREEN after 11 rounds**, owner-adjudicated - see `docs/agy-capstone-ledger.md`).

> ⚠ **THIS ENTRY READ `▶ OPEN` FOR SEVEN DAYS AFTER IT SHIPPED**, corrected 2026-08-27 while
> reconciling this document against `git`. It is the same defect class that has dominated every capstone
> round - one fact in two places with only one updated - sitting in the document the sequence is planned
> FROM. A stale `OPEN` is worse than a stale `SHIPPED`: it invites the work to be scheduled and done
> twice. **Whoever closes an item writes its CLOSING SHA here in the same commit** - an item with no sha
> cannot be checked against `git` by anyone, which is exactly how this one survived.

All four peer-review disciplines (`agy-capstone`, `agy-test-audit`, `adversarial-panel-review`,
`agy-first`) send the peer an **input** path and a scratch dir, but **nothing specifies where the peer's
reply must land**. A completed review is therefore lost whenever the channel caps.

**Measured three times now, across two different peers and two transports:**

- a compressed restate silently dropped **2 of 4** findings (2026-08-09);
- a reply died on the wire with the review stranded in the peer's console (2026-08-09);
- 🔴 **2026-08-10 — a new and worse mode:** the peer returned a lone verdict line whose prose claimed *"the
  full review has been printed to stdout"* when nothing else was emitted, then on retry returned the
  literal string `... [output truncated]`. Both on exit code 0, through a pipeline that had carried 15 KB
  and 16.5 KB replies minutes earlier.

**That third case refines the original framing and must be folded into any fix:** the loss was **not**
transport truncation — it was the model truncating **itself** and, once, asserting otherwise. So
"have the peer write to a file" is *not* a sufficient remedy, and it is often impossible: a review-only
peer has no write permission by construction.

**What actually works, measured:** (a) the driver captures the reply itself; (b) the driver
**byte-counts** it against that peer's *own recent replies* — 300 bytes where the last three were 15 KB is
a failed consult, not a terse one; (c) the brief carries an explicit reply-length budget. Also measured:
the **do-not-re-raise ledger grows monotonically** across an iterated review (≈40 entries by round 10
while the artifact barely changed) and was the only monotonic variable across the degradation — so
compress it each round.

#### 13c. `check-growth-budget.ps1` — the capture was a MISDIAGNOSIS; small residue only · ✅ **SHIPPED 2026-08-16** (`524eab5` both call sites distinguish a missing input from an empty one · `cae0c2e` restored three rows the fix had neutered · `2c2f2f7` capstone R3 fold).

**Corrected 2026-08-10, hours after promotion. The original entry claimed a fail-open with 7 467
unmeasured bytes. That is WRONG and is retained here only as the method lesson.**

**What the gate actually is.** `docs/agy-golden-header.growth.md` is a **transient in-repo PROPOSAL**,
compiled by `just drain-knowledge` and deleted after `just accept-drain` publishes it to the runtime
header. The budget gate runs as **step 7 INSIDE that drain**, while the proposal exists.
`docs/drain-knowledge-runbook.md:229-231` states explicitly that the file's absence is a **legitimate
state** — "a docs-only drain … nothing to publish". So `GROWTH (0B)` when run standalone is CORRECT
behaviour, not a fail-open: there is no proposal in flight. The gate's subject is the PROPOSAL, never the
runtime region, so comparing its output against `~/.clavity/golden-header.growth.md` (7 984 B) compares
two different things. The test creating its fixture at that path is likewise correct — it simulates the
drain's own output, not a wiring error.

🔴 **THE METHOD LESSON, which is the only durable part of this entry.** The capture reproduced perfectly
— file absent, `Get-RawBytes:26` returns 0 silently, gate prints `OK … GROWTH (0B)` and exits 0 — and
every one of those observations is TRUE. It was still a misdiagnosis, because **nobody checked what the
gate was FOR before calling its behaviour a defect.** One grep of the runbook settles it.
**Reproducing a symptom is not verifying a finding.** This is the same discipline applied to a peer's
claims every capstone round; it was not applied to a claim arriving from another session, and the
unverified diagnosis was promoted to this ROADMAP with confident numbers attached.

**The residue that IS real, and it is small:** a missing input silently measuring 0 cannot distinguish
"docs-only drain, nothing proposed" (legitimate, and the common case) from "the path moved or was
typo'd" (a wiring error that would pass green). Making the gate say which it thinks it is — one line —
costs nothing and removes the ambiguity that made this misdiagnosis so easy to reach.

⚠ **One genuinely OPEN question, explicitly UNMEASURED — do not repeat it as fact.** The runtime region
has **two** writers (`accept-drain`'s `curate-commit`, and the `agy-curate` skill via the same call). If a
write APPENDS rather than REPLACES, the runtime region could grow past what any single pre-publish
proposal check ever saw, and the combined cap would go unenforced between drains. `drain-knowledge-runbook.md:100`
says the runtime header "is touched at exactly one point in the whole flow", which suggests replacement —
but **this was not measured**, and it is the only path by which the original fail-open claim could turn
out to have been accidentally right for a reason nobody stated. Measure before acting on it.

**Disposition:** low priority, off the critical path. Not a fail-open. Belongs with the knowledge-storage
design work rather than as a standalone fix, since where GROWTH lives is exactly what that work decides.

### §14 — anomalies promoted at the 2026-08-13 and 2026-08-14 triages

All four were **verified by measurement at triage**, not accepted on reading. Each names the measurement
so a later reader can re-check rather than re-derive. §14a–c came from the 2026-08-13 triage; §14d from
2026-08-14, and it **corrects a sentence in §14c**.

**§14a — `PrunedSegments` omits `.clavity`, so scratch files enter the reference index.** ✅ **SHIPPED 2026-08-16** (`2db18c2`). VERIFIED 2026-08-18 by measurement: `.clavity` is the last element of the array at `scripts/check-injected-context.ps1:92`, and the fix is PINNED twice in `scripts/tests/check-injected-context.Tests.ps1` — a per-segment row at `:240` and the whole-array comparison at `:266`, so deleting the element reds the suite.
`scripts/check-injected-context.ps1:91-92` lists `.git, node_modules, target, bin, obj, .venv,
__pycache__, dist, publish, .vs, .ruff_cache, .pytest_cache, .mypy_cache, .worktrees` — and **not
`.clavity`**. The reference index is a whole-repository walk pruned by NAME, so anything under
`.clavity/scratch/` is indexed and can flip a unique filename to ambiguous. Measured by the reporting
session: five scratch fixtures named `driver-cheatsheet.core.md` turned `check-injected-context.Tests.ps1:398`
RED. **This is the same half-fold shape as the `.worktrees` fix in `fddde70`**, and `.clavity/scratch` is
the directory the disciplines *mandate* for scratch output, so the collision is reachable by following
our own rules. Fix is one array element plus a pinning row.

**§14b — `clavity-dotnet/install/clavity-install.Tests.ps1` is an orphan suite.** ✅ **SHIPPED — registered.** VERIFIED 2026-08-18 by re-running the entry's OWN discriminating control: `clavity-install.Tests.ps1` now appears **once** in the root `justfile`, the same count as the registered control suite `generate-scoped-manifest.Tests.ps1`. At triage it measured **zero**. Registration is an
explicit list in the **root** `justfile` (lines 101 and 108). Measured with a discriminating control: a
registered suite (`generate-scoped-manifest.Tests.ps1`) appears there once; `clavity-install.Tests.ps1`
appears **zero** times in either the root or `clavity-dotnet/justfile`. It exists, passes under raw
Pester, and **never runs in any gate**. `test-suite-registration.Tests.ps1` cannot see it because it
scans only `scripts/tests` while claiming to cover "every Pester suite on disk" — so the guard's own
scope is narrower than its stated contract. Decide: register it, move it, or delete it.

**§14c — ✅ **SHIPPED 2026-08-16** — but **NOT in the shape this entry predicted, and the divergence is the point.** The entry framed the fix as five artifacts each asserting the shield. What shipped asserts it **once, at the write point**: the three skills (`agy-first`, `agy-capstone`, `agy-test-audit`) delegate every `.clavity/` write to `agy-mark.sh`, which sources `agy-shield-lib`. MEASURED 2026-08-18: `agy-shield-lib` is referenced by exactly three files (`agy-discipline-reaching.sh`, `agy-mark.sh`, `open-issues/SKILL.md`) while all three skills cite `agy-mark.sh` (3, 6 and 3 times). **A five-copy assertion would have been five things to keep in sync; one chokepoint is one.** Original entry text follows, kept because its MEASUREMENT is still the record of what was wrong: FIVE shipped artifacts write into `.clavity/` and none asserts the `.gitignore` shield: ONE HOOK
and FOUR SKILLS.** Measured 2026-08-14 under a stated predicate — *a shipped plugin artifact that CREATES
or WRITES a path under `<repo-root>/.clavity/`, traced through variable assignments to the RESOLVED
target*, not by proximity of a write construct to the token `.clavity`. The earlier "7 shipped hooks" came
from that proximity predicate and was wrong in KIND as well as in count. The set:
`plugin/hooks/agy-discipline-reaching.sh` · `plugin/skills/agy-first/SKILL.md` ·
`plugin/skills/agy-capstone/SKILL.md` · `plugin/skills/agy-test-audit/SKILL.md` ·
`plugin/skills/open-issues/SKILL.md` (weakly, at `:79` — that one is §14d).
**Excluded, with the reason:** `adversarial-panel-review/SKILL.md:203` names the path but delegates the
write; the other six hooks write to `${TMPDIR:-/tmp}` or `$HOME/.clavity-tmp` — a DIFFERENT directory —
and say so themselves (`agy-anomaly-capture-reminder.sh:49`, `assertion-strength-reminder.sh:9`).
On an end-user repository whose `.gitignore`
we do not control, that runtime state is **git-visible**, and a `git add .` would publish it. The
workflow-position spec (`docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md`,
section 6) mandates the shield for the *new* reader; **this entry is the existing five.**

> ⚠ **CORRECTED 2026-08-14 by §14d: `SKILL.md:79` is NOT a good reference to copy.** It tests file
> EXISTENCE, not content. Fix §14d first, or §14c's five artifacts inherit the weak idiom.

**§14d — the sole shield assertion is content-blind, and five artifacts propagate it.** ✅ **SHIPPED 2026-08-16** (`e48d97a` the effect-checking helper, mirrored across both plugins · `0850473` + `028d016` capstone folds). VERIFIED 2026-08-17: the helper asserts CONTENT (`grep -qFx '*'`), and the three surviving hits for the old `[ -f ]` idiom are all COMMENTS explaining why it was replaced - no live code carries it.
`SKILL.md:79` reads `[ -f "$R/.clavity/.gitignore" ] || printf '%s\n' '*' >> ...`, so it restores a
**deleted** shield but never an **emptied or hand-edited** one. Its own comment at `:74-78` claims it
covers "the file was created by hand", which is exactly the case it misses. Measured at triage in a
throwaway repo, every claim with a passing control:

| measurement | result |
|---|---|
| `[ -f ]` on a 0-byte `.clavity/.gitignore` | **TRUE** — idiom does not restore |
| `grep -qx '\*'` on the same file | FALSE — correctly restores |
| control: `grep -qx '\*'` on a properly shielded file | TRUE — correctly leaves it alone |
| **consequence**, shield emptied: `git add -A` | stages `.clavity/local-anomalies.md` — **the private file is published** |
| control, shield present: `git add -A` | stages nothing |

**The fix was verified too, not just the finding.** `grep -qx '\*' ... || printf '%s\n' '*' >> ...` is
idempotent (1 line after 3 consecutive runs) and subsumes the missing-file case the current idiom already
handled. **Residual limit, measured rather than papered over:** a shield reading `*` followed by
`!local-anomalies.md` passes `grep -qx` and still leaks — the fix is a strict improvement, not a proof.

**The blast radius is why this is tracked rather than a drive-by.** The weak idiom is live in five places
outside the shipped pair, found by sweeping the FACT rather than patching the reported line:

- `clavity-dotnet/plugin/skills/open-issues/SKILL.md:79` and `clavity-classic/plugin/skills/open-issues/SKILL.md:79`
  — **shipped, byte-identical pair**, so any fix must mirror and pass `plugin-hooks-payload.Tests.ps1`
  + `check-seed-artifacts-synced.sh`.
- `docs/superpowers/specs/2026-08-13-agy-role-enforcement-design.md:207` and `:211` — a **FROZEN ADR**
  that quotes the weak line and *requires* hooks to assert it that way. Amending a frozen artifact is an
  owner call.
- `docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md:760` — prescribes it for a
  not-yet-built reader, citing `# SKILL.md:79` in the comment. That spec is **§15, parked**.
- `docs/superpowers/plans/2026-08-01-anomaly-capture.md:562` and `:815` — the shipping plan; historical.

**The correct idiom already exists in the tree** at
`docs/superpowers/specs/2026-08-13-agy-policy-gate-implementation-spec.md:688`, folded during that spec's
round-8 panel — which is where this anomaly was captured. **So this is an INCOMPLETE FOLD, the dominant
fold defect**: the round fixed its own artifact's line and never swept the source it was copied from.
Like §13a it lands on `feature/injected-context-governance`, so it belongs with that epic's remaining work.

**§14e — the only local gate on the three byte-pinned files checks provenance, not parity.** ✅ **SHIPPED 2026-08-16** (`d5a24d7` generate both literals from core.md · `4ebec4f` the pre-commit INDEX-to-INDEX parity gate · `e15c0f0` eol pinning · `fd380fe` docs). VERIFIED 2026-08-17: the gate is wired at `lefthook.yml:105` and ran green on today's commits. Later hardening: `578fe22`, `6b86445` (all-or-nothing across both writes).
`lefthook.yml:78-82` globs **exactly** the three pinned paths — `driver-cheatsheet.core.md`,
`clavity-classic/src/driver_cheatsheet.rs`, `clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` — and its
own comment at `:63` states they "are pinned byte-identical to each other". It then runs
`check-curate-in-progress.ps1`, which asserts something else entirely: *was an agy-curate run left
mid-flight* (`:4-5`). **Provenance, not parity.** So an edit to one pinned file that does not regenerate
the other two fires the hook, passes it, and commits.

That is not hypothetical — it is how this anomaly was created. Measured:

| measurement | result |
|---|---|
| `b2a6cc0` (2026-08-09) ASCII-sanitised `core.md` | 10 em dashes → 0, pins not regenerated |
| the pre-commit hook on that commit | **fired** (core.md was staged) and **passed** — wrong invariant |
| `dotnet test tests/Clavity.Ls.Tests` at `fc968fb~2` | **Failed 1, Passed 8** — fails at pos 21, expected `—`, actual `-` |
| `cargo test --features test-fakes driver_cheatsheet` at the same point | **9 passed, 1 failed** — measured, not presumed from the dotnet result |
| RED window | 2026-08-09 → 2026-08-14, **5 days**, closed by `d664002` |

**Why CI did not close it, which is the part worth tracking.** The oracles *are* wired —
`.github/workflows/ci-dotnet.yml:26` runs `dotnet test tests/Clavity.Ls.Tests` and `ci-classic.yml:46`
runs `cargo test --all --features test-fakes`. Neither can fire on an **unpushed** branch, and this one is
**152 commits ahead of `origin/main`**. On a long-lived local branch, CI is not a safety net; it is a
report you get later. **A capstone-GREEN declaration was made while both suites were red** — the marker
was never evidence the gate ran.

**The marginal cost of the fix is near zero, which is what makes it worth doing.** The expensive part —
a ~6s pwsh cold start, paid only when one of the three paths is staged (`lefthook.yml:68-72`) — is
**already being paid** on exactly the right trigger. The parity assertion would ride along on it.

**Candidate dispositions, both with their known trap named:**
- **Extend the existing job** to also assert parity. Needs the Rust/C# literals un-escaped (`\n`, `\"`)
  in PowerShell — the logic exists in-language in both test suites and would be duplicated a third time,
  so the new check becomes a fourth thing that can drift from the other three.
- **Shell out to the two existing suites** instead of reimplementing. Avoids the duplication but is far
  slower than 6s, and `dotnet test --filter` **exits 0 on no match** — a filtered invocation that stops
  matching would fail open silently, which is the failure mode this whole entry is about. Any such fix
  must read the test COUNT, not the exit code.

Like §13a and §14d this lands on `feature/injected-context-governance`, so it belongs with that epic's
remaining work rather than as a drive-by.

**§14f — two shipped artifacts disagree about who owns `driver-cheatsheet.core.md`, and the gate that
would catch it never runs on the flow that edits it.** · ✅ **RULED 2026-08-19**

> **OWNER RULING (2026-08-19).** Neither stated disposition is chosen. **§14f is ANSWERED BY §18 and is
> sequenced behind it**, not adjudicated on its own terms.
> **Why:** the AGY-FIRST consult offered "split the file and its ownership - SEED driver-owned and pinned,
> GROWTH curator-owned in `~/.clavity/`" as a disposition neither entry names. **Verified before folding:
> that IS §18**, already tracked, with 64 parked inbox entries waiting on it - and §18 further records that
> the same peer previously recommended UNPINNING, was refuted by measurement, and "conceded and adopted
> this split as the target architecture". So the peer re-derived its own prior conclusion and offered it as
> new. The conclusion is right; the novelty was not. Once §18 ships, `core.md` becomes the pinned FLOOR
> (driver-owned) and the growth region is curator-owned, so **the ownership contradiction dissolves rather
> than needing a ruling** - and ruling it now would fix a file §18 is about to re-shape.
> **What this means for the plan:** the sequencing spec's **step 4 does NOT execute a §14f fix**. §14f is
> closed as "answered by §18". The 32 inbox entries parked on
> `cheatsheet-core-is-byte-pinned-to-two-compiled-literals` stay parked on **§18**, not on a separate ruling.

Both sides are internally coherent and describe different flows, which is why neither reads as a bug from
inside itself:

| artifact | says |
|---|---|
| `scripts/drain-lib.ps1:214`, listing the file at `:223` | "Driver-owned files the curator must **NEVER** touch (asserted byte-unchanged by `check-core-integrity.ps1`)" |
| `scripts/drain-knowledge-prompt.md:4` | "never the seed, never `driver-cheatsheet.core.md`" |
| `scripts/drain-knowledge-prompt.md:56` | "any `driver-cheatsheet.core.md` edit you WANT but **may not auto-apply**" |
| `agy-autotrain/skills/agy-curate/SKILL.md:112` | "The canonical text lives at `driver-cheatsheet.core.md`; **keep it in sync there**" |
| `agy-autotrain/skills/agy-curate/SKILL.md:124` | "If you change `driver-cheatsheet.core.md` you **MUST also update**" both pins |
| `agy-autotrain/skills/agy-curate/SKILL.md:339` | documents core.md "and its two byte-identical pins **may have been edited**" as uncommitted working-tree state |

**The gate cannot catch the disagreement.** `check-core-integrity.ps1` is invoked from exactly one place -
`scripts/drain-knowledge.ps1:126`, the in-repo `just drain-knowledge` flow. The standalone skill path,
which is the one that actually edits these files, never invokes it. **Measured: drain commit `fc968fb`
modified `core.md` and no gate fired.** A protected-file gate that does not run on the flow that edits
protected files is the same class as §14e - the gate exists and does not fire on the real path.

**Why this is a RULING and not a fix, which is why it is tracked rather than folded into the hot-fix
batch:** the two dispositions are opposite edits to different files.

1. **`core.md` is driver-owned** => the `agy-curate` skill is the defect: its cheatsheet-compilation
   section must PROPOSE an edit rather than apply one, matching `drain-knowledge-prompt.md:56`, and the
   drain flow grows the step that applies it.
2. **`core.md` is curator-owned in the standalone flow** => the protected list and the prompt are
   over-broad: they must be scoped to the in-repo flow, and the standalone path must invoke the gate.

**Scope note:** the 2026-08-14 hot-fix batch spec deliberately EXCLUDES this, and that exclusion is safe -
§14e's generator only READS `core.md`. **But §14e does have one mechanical consequence that belongs to the
batch, not here:** once the literals are generated, `SKILL.md:122-124`'s instruction to hand-edit both pins
becomes wrong, so the batch must update it. That is tracked in the spec, not in this item.

**§14g — the agy-observations inbox lives INSIDE the plugin tree, so it exists in N copies and both
skills must be INSTRUCTED which one is live.** · ✅ **RULED 2026-08-19** · ✅ **DONE 2026-08-24** (`8127373`; AGY-CAPSTONE **GREEN** over `bd3aa94..f29cd42`, owner-confirmed 2026-08-24). ⚠ **AGY-TEST-AUDIT is still owed on that range and has never run.**

> **SHIPPED.** The canonical inbox is now `<USERPROFILE or HOME>/.clavity/agy-observations.md`.
> Both skills collapsed to that one path (`agy-learn` 183 — 130 lines, reversing the +138% growth this
> entry complained about; `agy-curate` —19). The resolution order, the checkout test and the staging
> file are DELETED. `agy-curate-nudge.sh` and `agy-inbox-snapshot.sh` both read the new path, each pinned
> by a DECOY inbox left in the plugin tree — mutation-verified: reverting the nudge hook reds 12 of its
> 13 tests. The installer stopped shipping the inbox and gained `MigrateInboxToUserState` (copy when the
> destination is absent/empty, APPEND otherwise, rename the source aside — never delete); ISCC exit 0,
> control-verified. 133 live entries migrated, count asserted.
>
> 🔴 **THE BLAST RADIUS IN THIS ENTRY WAS INCOMPLETE.** It named both skills, `agy-curate-nudge.sh` +
> its suite, and the installer. It MISSED `agy-autotrain/hooks/agy-inbox-snapshot.sh:15` and
> `scripts/drain-lib.ps1:9`, which both hard-coded the plugin-tree path and were found only by a
> whole-repo grep. Both are fixed and now test-pinned (`drain-lib` had NO test for `Resolve-InboxPath`
> at all; one was added and mutation-verified).
>
> ⚠ **ONE SCOPE ADDITION, owner-ruled 2026-08-24.** The staging/rename apparatus was not only a path
> workaround — the rename is also a CONCURRENCY claim (`agy-learn` appends mid-task from other sessions
> while a drain is in flight). The main inbox never had that protection, so deleting the machinery
> wholesale would have widened a real race rather than closing it. `agy-curate` now claims the ONE
> canonical inbox by rename before reading, and appends the residue back rather than rewriting.

> **OWNER RULING (2026-08-19).** **Do the architectural move.** The canonical inbox becomes
> `<USERPROFILE or HOME>/.clavity/agy-observations.md`, beside the golden-header files.
> **Why:** the instructional patch did not contain the problem, it institutionalised it - `agy-learn` grew
> 77 -> 183 lines (+138%) instructing around a path problem, its capstone ran five rounds and never went
> green with every round finding a defect inside the previous round's fix, and a known data-loss hole (a
> crash between the staging rename and its delete) is deliberately unpatched because patching it adds
> machinery the architectural fix deletes. User-generated mutable state does not belong inside an
> immutable plugin install tree.
> ⚠ **The entry's own figures are STALE AND INVERTED - do not reason from them.** It says 30 repo / 18
> installed. **Re-measured 2026-08-19: 0 repo / 97 installed.** The argument holds and is stronger; only
> the numbers were wrong.
> **What this means for the plan:** the sequencing spec's **step 3 executes the move**. Blast radius as the
> entry states - both skills, the `${CLAUDE_PLUGIN_ROOT}` line in `agy-curate-nudge.sh` and its 244-line
> suite, the installer's `onlyifdoesntexist` seeding (`agy-autotrain.iss:54,60`) - plus migrating the
> **97** pending entries in the installed copy.

**Measured 2026-08-15:** the repo checkout copy held **30** pending entries and the INSTALLED copy **18**,
with **ZERO overlap** — four capstone sessions' worth of real captures written to a copy nothing drains
and nothing counts. They were committed to git, so they looked saved. Cause: `agy-learn` and `agy-curate`
resolved the inbox as `../../knowledge/agy-observations.md`, correct only when the invoking copy IS the
install; every checkout and worktree carries its own.

**The instructional fix shipped** (`33851cf`..`9f6b394`) and this entry is what it did NOT fix. Its
capstone ran **five rounds and never went green**, and every round found a defect inside the previous
round's fix — including two fail-opens of mine: a `git rev-parse --is-inside-work-tree` test that measures
an install nested in a git-managed HOME as a checkout (blocking captures outright), and a missing `git`
exiting non-zero, which read as "installed tree" and routed writes INTO a checkout. **`agy-learn` grew
77 → 183 lines (+138%) instructing around a path problem**, and that growth is the finding: the round-5
scope seat and the driver independently concluded the machinery now costs more than the fix it substitutes
for.

**KNOWN OPEN HOLE, recorded in `agy-curate/SKILL.md` and deliberately not patched:** a crash between the
staging rename and its delete strands that batch, because each run reads only its own uniquely-named
processing file and never globs. Patching it adds machinery the architectural fix deletes.

**The fix is architectural:** move the canonical inbox to `<USERPROFILE or HOME>/.clavity/agy-observations.md`
— exactly where the golden-header files already live, for exactly this reason — so every copy resolves one
path and no instruction is needed. **Blast radius:** both skills, the `${CLAUDE_PLUGIN_ROOT}` line in
`agy-autotrain/hooks/agy-curate-nudge.sh` and its 244-line suite, the installer's `onlyifdoesntexist`
seeding (`agy-autotrain.iss:54,60`), plus migrating the installed copy and the repo copy's 30 undrained
entries. **Not urgent:** the installer excludes the inbox from the blanket copy, so an update does not
overwrite it. 🔴 **CORRECTED 2026-08-24: this entry also claimed the inbox is marked
`uninsneveruninstall`, and used that to REFUTE a reviewer who warned an update could destroy the
backlog.** 🔴 **AND THAT CORRECTION WAS ITSELF WRONG - re-corrected 2026-08-26.** It said the flag
"was never there", measured against the CURRENT tree only. Measured across history instead: `74ffd27`
shipped the inbox with `onlyifdoesntexist` and no protection, while `dc85d2d`, `25b83cf` and `bd83435`
shipped it `onlyifdoesntexist uninsneveruninstall`. The flag was there for part of that history and is
absent now only because 14g stopped shipping the file at all. So the reviewer who warned an update could
destroy the backlog was right, was refuted with a false claim, and the refutation was then "corrected"
with a second false claim in the opposite direction. The accurate statement is narrow: `uninsneveruninstall`
appears on no `[Files]` entry in any `.iss` in this repo TODAY. Since 14g the inbox lives at `%USERPROFILE%\.clavity\`, outside the install
dir, and its survival rests entirely on the uninstaller purge branch being gated on `RemoveGrowth`.
The reviewer was dismissed on a protection that did not exist; the behaviour is now pinned by the C6b
assertion in `.github/workflows/build-agy-autotrain.yml`.

**§14h — two AGY-* review disciplines prescribe a SINGLE persona, so their consults are single-voice
by instruction.** ✅ **SHIPPED 2026-08-16** (`a652d8d` — "refactor(shield): 14c + 14h — disciplines write
via agy-mark.sh and seat a panel"). **Closed retroactively on 2026-08-31**: the header read `OPEN` for
fifteen days after the fix landed, and a sequencing spec scheduled it as live work as a result. Verified at
HEAD: `agy-first/SKILL.md:103` reads "**Seat a panel, not a persona.**" with seat rotation at `:112`, and
`agy-test-audit/SKILL.md:109` reads "**Seat the audit, do not send one voice.**" placed after the
`## The audit round` heading — the insertion point this entry itself prescribed. The old
"Optional per-run mitigation: rotate the audit's lens" wording is gone.

**Measured 2026-08-15** across both plugin variants (byte-identical, counts equal in each):

**The line counts below were measured 2026-08-15, CORRECTED to their 2026-08-31 values, and CORRECTED
AGAIN on 2026-09-03 after §21 shipped.** The originals (123 / 231 / 289 / 297) were the INSTALLED plugin's,
which had drifted from the repo under an unchanged version string — see Phase 0c.
`scripts/check-roadmap-claims.ps1` fails if any of them rots again, and it did exactly that: §21 added
lines to all four skills, the table kept the pre-§21 figures, every LOCAL gate I ran was green, and **CI
caught it** (`ci-scripts`, run 33682230813, 1238 passed / 1 failed). The checker lives in the SLOW half,
which the pre-push hook does not run.

🔴 **And the stale figures were not arbitrary: 214 / 332 / 429 / 360 are the INSTALLED copy's counts
at the time of writing.** The repo moved to 234 / 377 / 476 / 380 and the installed plugin did not, so the
table had silently reverted to describing the installed artifact — which is the precise drift this section
documents, recurring one section later. Re-measure against the REPO file, never the installed one.

| skill | mandates seats? | evidence |
|---|---|---|
| `agy-first/SKILL.md` (234 lines) | **NO** | `:54-56` — "Default persona: bold inventive systems-designer; override when a sharper lens fits (security-auditor, perf-skeptic, API-contract-pedant)". Singular, and the three alternatives are ad-hoc, not palette seats. |
| `agy-test-audit/SKILL.md` (393 lines) | **NO** | `:216` is the ONLY lens language in the file: "Optional per-run mitigation: rotate the audit's lens". Optional, and singular. **The fix is NOT confined to `:216`:** that line sits in the "Stated limitation - false negatives" section at the foot of the file, so replacing it alone would bury a framing instruction in a footer. The seat instruction belongs where the consult is framed - **insert at `:59`, immediately after the `## The audit round` heading and before its numbered item 1** - and `:216-217` is then reworded to point at it. |
| `agy-capstone/SKILL.md` (476 lines) | **YES — not defective** | `:89` reads, literally and in ASCII: `- **Seats (defect-class lenses).** Seat the proven adversarial-panel-review personas - Axiom Breaker`. `:92` seats those whose trigger the diff meets; `:103` rotates seats across rounds. **Quoted verbatim so it can be grepped:** an earlier version of this row rendered that line with an em-dash and an ellipsis, neither of which the file contains - it is ASCII-gated - so the "quote" matched nothing. |
| `adversarial-panel-review/SKILL.md` (380 lines) | **YES** | the palette, selection rule, and anti-gaming guard live here. |

**Blast radius: 4 files** — `agy-first` and `agy-test-audit` in `clavity-dotnet/plugin/skills/` and
`clavity-classic/plugin/skills/`. Byte-identical pair, so both variants change together and
`plugin-hooks-payload.Tests.ps1` gates it.

**Why this is a defect and not a preference.** The owner has corrected the same dropped-seats behaviour
**twice**, and on the second occasion named it a defect requiring a fix. The driver was not ignoring
`agy-first` — it was *complying* with it: `:54` says "Default persona", singular, so a single-voice
consult is the instructed behaviour. A discipline whose text produces the failure its sibling discipline
exists to prevent is a defect in the text. **Provenance, so a future reader can check rather than take this on trust:** the entry was promoted at
the second 2026-08-15 triage in commit `90b275e`; the plan work and the capstone that hardened it run
`90b275e..6adf80b` on branch `feature/injected-context-governance`, and every claim below is restated
in those commit messages with the measurement that produced it. **Measured effect in the run that
surfaced it:** a single-voice
`agy-first` consult built three orderings on a collision that did not exist and stated two confident
claims that measurement refuted; the seated round that followed produced six distinct findings and two
substantive challenges to the driver's own measurements.

> ⚠ **The first measurement of this entry was WRONG and the error is instructive.** A `grep -c palette`
> returned 0 for `agy-capstone` and it was nearly promoted as a third defective skill. `agy-capstone`
> mandates seats correctly at `:86-103` — it simply never uses the word *palette*. **A paraphrase evades
> a phrase-shaped grep**; the fix-side sweep must search the FACT (does this file mandate multiple named
> adversarial lenses?) in several wordings, not one token.

**Fix shape:** give `agy-first` and `agy-test-audit` a seat instruction of the KIND `agy-capstone:89-103`
already carries — name concrete adversarial seats, seat those whose trigger the artifact meets, rotate
across rounds, and reuse the `adversarial-panel-review` persona vocabulary without becoming a code
dependency on that skill.

> ⚠ **CORRECTED 2026-08-15, and the correction matters because the original sentence would have produced
> the wrong fix.** It read "give them **the same** seat instruction … **rather than duplicating the
> palette into each file**". Both halves are wrong, and the exemplar it cites disproves them:
> **`agy-capstone:89-94` inlines the seat names itself** (`Axiom Breaker (contradictions / unstated
> invariants), Cascade Analyst (unhandled failure paths), Mechanism Gamer …`). So "do not duplicate the
> palette" describes neither the exemplar nor anything achievable in a markdown skill file, which has no
> include mechanism.
>
> And **the same** instruction is wrong on the merits: `agy-first` consults on a FORK, so its seats hunt
> reasoning defects; `agy-test-audit` consults on a SUITE, so its seats hunt coverage gaps and must be
> handed the coverage question explicitly. Pasting one file's block into the other yields a seat list
> that cannot fire on what that discipline reviews. **The shared thing is the PATTERN — named seats,
> trigger-based selection, rotation — not the text.**
>
> Found by a capstone round that compared the plan against this entry and reported the PLAN as
> non-compliant. The plan was right; this entry was wrong.

**This remains the same "one shared review-core" question already open as the AGY-* family-coherence
fork**, so the two should be decided together, not separately.

### §15 — Workflow-position resilience — **SECOND PRIORITY FOR A FUTURE RELEASE** (owner, 2026-08-13)

**Spec:** `docs/superpowers/specs/2026-08-13-workflow-position-resilience-design.md` (committed `4adab8b`,
tracked — note `docs/superpowers/*` is gitignored, so it needed `git add -f`).

**Status: deferred, not cancelled.** The spec is complete and has been through **six adversarial panel
rounds, all folded**. It is not blocked on quality; it is deprioritised behind the policy gate, which is
the approved deliverable. Do not restart the design — read the spec.

**What it would build:** a single SessionStart reader (registered `startup|resume|clear|compact`) that
surfaces unconcluded consult seams so a session that dies leaves its successor able to resume, plus a
seam naming convention. Explicitly no resume file, no WAL, no decisions index.

**Two things it inherits unresolved, and the first is a gate on the name:**
- **The discipline's NAME is deferred pending a measurement** — does bare `sync` actually flush on this
  platform, and at what cost under concurrent load. **Not "does it exit 0"** — that was measured and
  proved nothing. Probe passes → a power-failure name is defensible *with a scope note*. Probe fails →
  the name must change. **Two of the three overclaims (implementation coverage, decision retention) are
  settled against the mechanism either way**, so even the best outcome yields a narrower name.
- A Windows-path casing case in the filename match.

**One scope item needs owner confirmation before it is built:** the spec adds a debounce-marker contract
to `adversarial-panel-review/SKILL.md` (writing `agy-panel.head`). Everything else is additive; that one
edits a shipped skill.

**Honest scope, recorded so a later reader does not over-read the name:** it recovers interrupted
*consults*. It does not cover implementation work (435 of 435 agent-written seams are consult payloads),
does not retain decisions, and does not defend against a compromised agent.

### §16 — Edit-verification pattern: a TRANSIENT Pester suite, not inline shell — **owner-ratified 2026-08-15**

**This records a PATTERN for the next plan, not work to schedule.** It changes nothing already shipped.

**The problem it answers.** A plan that applies edits needs a step that verifies the edits landed. Task 7
Step 5 of the 2026-08-14 anomaly hot-fix plan is that step, and it took **five capstone rounds** to
stabilise: three consecutive rounds each found defects *inside the previous round's fix*, and the
recurring classes were all shell-shaped — primitive drift, `grep`'s 0-vs-error merge folded into a
two-outcome construct, argument-order confusion across bespoke helpers, and invisible coverage.

**The pattern: write the verification as a Pester suite that lives and dies with the plan.**
- **Put it OUTSIDE `scripts/tests/`.** MEASURED — `scripts/tests/test-suite-registration.Tests.ps1:3`
  states "THE SCOPE IS `scripts/tests/` ONLY. A suite anywhere else in the repository is invisible to
  this guard." So a transient suite touches no registration gate, no `_partition.md` census, and no CI
  `paths:` list. **This one fact is what makes the pattern cheap**, and it is the fact the original
  design consult missed.
- **Invoke it directly** from the plan step (`Invoke-Pester <path>`), and delete it with the plan.
- **Express the expectations as a `-ForEach` array**, so every obligation becomes a NAMED test row that
  can be read against the plan's own edit table. A missing obligation is then a missing row, visible.

**Why not a permanent gate.** Exact-count and anchor-offset assertions are *change-detectors*: their job
ends when the commit lands. Enshrined permanently they red on the next legitimate edit — a chore, and
this repository has already paid for that lesson elsewhere. Transience is the point, not a compromise.

**Why the current plan does NOT adopt it.** Owner ruling 2026-08-15: **ship the shell design there.**
That plan's verification is bash throughout — Step 0's pre-flight anchors, Step 4's byte-identity hash
loops, every task's oracles — so a single PowerShell step would fracture the document mid-task; and the
shipped design carries a 12-case acceptance matrix that a rewrite would have to re-earn from zero. The
shell version is measured and green; this pattern is for the plan *after* it.

**Provenance, because it is the point.** The A/B/C fork was first put to the peer **unseated**, and it
chose between the three options it was given. Re-run with named seats, a **Blindspot Auditor** produced
the option nobody had listed and named why the first round could not: the framing had chained the
*language* choice to a *lifecycle* policy, so "Pester" silently read as "permanent CI gate". The
seat discipline is what found this; an unseated consult structurally could not.

**Still open, NOT ratified by this entry:** whether the genuinely durable subset — "the seat instruction
still exists in `agy-first` / `agy-test-audit`" — earns a permanent gate. That is a separate decision.

### §17 — anomalies promoted at the 2026-08-17 triage — ✅ **CLOSED 2026-08-30** (§17a SHIPPED `99910c0`, AGY-CAPSTONE GREEN per ledger `eb26709`; §17b RULED KILLED — see the sub-entries)

Two entries from the 7-entry triage of 2026-08-17. Every one verified by measurement at triage. The other
five were dispositioned there: two fixed immediately (`assertion-strength-reminder.Tests.ps1` bash pinning,
and the shield suite's marker hygiene), two routed to `docs/coverage-debt.md` as coverage debt, one deleted.

#### §17a — the shield's debounce key has no repository component · ✅ **RULED 2026-08-19**

> **OWNER RULING (2026-08-19).** **Key the marker on the repository ROOT PATH.**
> **Why:** it is the only named disposition that is both collision-free and subprocess-free. The consult
> recommended the BASENAME (`${_as_root##*/}`, pure bash, no path-length risk) and its citation was checked
> - `_as_root` is real, `agy-shield-lib.sh:100` - but it did not name the weakness: **two checkouts sharing
> a basename (`~/work/clavity` and `~/backup/clavity`) still collide**, leaving exactly the defect this
> entry describes. A hash is collision-free but shells out to a hashing binary on a hot path that runs on
> every capture.
> **Re-arming every existing debounce ONCE is accepted, and no migration step is to be written** - these
> are anti-spam markers, not durable state, and a `find`/`mv` migration would add brittle subprocess logic
> to a hot path for no lasting value.
> **What this means for the plan:** the sequencing spec's **steps 5 and 9 execute this**. It is a contract
> change to a shipped byte-identical hook pair, so it **must be mirrored to `clavity-classic` in the same
> commit**, and the marker name must be sanitised for path separators before use as a filename.

**The fact, measured with a control 2026-08-16 and re-confirmed at triage:** the marker is
`"$_ass_dir/.clavity-shield-$_ass_class-$_ass_key"` (`agy-shield-lib.sh:70`) — the key is the caller's
session id and there is **no repository component anywhere in the path**. Control: repo A key k1 REPORTS;
repo A key k1 again is silent (correct); a **fresh repo B** under the same key is **SILENT**; repo B under
a different key REPORTS. So one session working across two repositories gets **one fault report in total**,
and the second repository's leak is never surfaced.

**Why it is not already fixed.** It was **deferred by decision** during the 2026-08-14 hot-fix batch and
recorded as a residual in that plan after Step 7. Adding a repo component is a **contract change** to a
shipped, byte-identical hook pair: the marker name is the debounce identity, so changing it re-arms every
existing debounce once, and the fix has to be mirrored to classic in the same commit.

**Disposition needed:** whether to key on the repository root path, its hash, or to leave the cross-repo
case documented as a known limit. Not mechanical — hence tracked rather than folded.

#### §17b — every `pre-push` gate reads the WORKING TREE, not the commits being pushed · ✅ **RULED 2026-08-19 — KILLED**

> **OWNER RULING (2026-08-19). KILLED.** The ten pre-push gates stay exactly as they are, reading the
> working tree. No step executes a §17b fix.
> **Why:** this entry's urgency rested on its closing claim that this branch, "319 commits ahead and never
> pushed", had **neither** pre-push nor CI reasoning about what would land. **That is no longer true: the
> branch merged 2026-08-19 (`c12b540`) and `main` now runs 12 workflows on every push.** With CI as the
> real gate, a pre-push hook is a fast LOCAL SMOKE TEST - and for that job reading the worktree is
> **correct**, because a developer whose pre-push fails wants to fix files and push again, not stash and
> amend merely to test the fix. A SUBSET was rejected as the worst available outcome: mixed semantics
> across ten siblings destroys any model of what a passing pre-push guarantees.
> ⚠ **Recorded because it cuts both ways:** that first-ever CI run found **seven** real defects which all
> ten pre-push gates had passed, including an unresolvable action ref and a RUSTSEC advisory in a lockfile.
> That is evidence FOR relying on CI as the gate - not evidence for hardening pre-push into a second one.

**Measured at triage:** `lefthook.yml` then defined **10** pre-push jobs — `seed-sync`, `agy-skills`,
`doc-stubs`, `member-docs`, `user-facing-docs`, `register-hash`, `installer-ascii`, `check-versions`,
`check-plugin-namespace`, `check-ci-filter-coverage` — and **zero** of them consult `git show <ref>:<path>`,
`--cached`, or the push refs a pre-push hook receives on stdin. Every one resolves paths from the worktree
via `$PSScriptRoot`/`$RepoRoot` and reads with `Get-Content`/`Get-ChildItem`.

**Both failure directions are live:** uncommitted work can **false-RED** an otherwise valid push, and an
uncommitted fix can **false-GREEN** a push of the broken commit. The verdict is about state git is not
about to publish.

⚠ **`check-ci-filter-coverage` was DELETED on 2026-08-27** when the `paths:` filter it guarded was removed
(see `docs/superpowers/specs/2026-08-27-declarative-coverage-registration-design.md`). NINE pre-push jobs
remain and the finding is unaffected: it was never about that gate, and the nine survivors all still read
the worktree.

**Why it is filed rather than fixed.** This is the repo-wide SHAPE of the hook, not one gate's defect —
`check-ci-filter-coverage` was merely the newest instance at the time. Making one gate read blobs from the pushed commit
would leave it inconsistent with its nine siblings, and changing all ten is an **owner-level decision about
what a pre-push gate is FOR**. Surfaced by an agy capstone seat, then confirmed against the hook block.

**Note the interaction with §14e:** that entry already records that on a long-lived local branch *"CI is not
a safety net, it is a report you get later"*. If pre-push is also not measuring the pushed state, then this
branch — 319 commits ahead and never pushed — currently has **neither** gate reasoning about what would land.

### §18 — SEED/GROWTH split for the driver cheatsheet — ✅ **SHIPPED, AGY-CAPSTONE GREEN after 7 rounds** (ledger `519833f`)

**The problem, measured at the 2026-08-17 drain.** `driver-cheatsheet.core.md` is 100% SEED-shaped: it is
byte-pinned to two compiled literals (`clavity-classic/src/driver_cheatsheet.rs` `BASELINE_FLOOR`,
`clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs` `BaselineFloor`). So **every promotion of learned driver
knowledge costs an implementation-source change** — regenerate both literals, run three oracles, and owe a
re-capstone. That toll is why the loop stopped being run at cadence: **69 pending entries had accumulated,
31 of them in a second inbox copy no flow read.**

🔴 **THE STRONGEST ARGUMENT FOR THE SPLIT IS A SAFETY ARGUMENT, AND THIS ITEM DID NOT MAKE IT UNTIL NOW.
The cheatsheet read is REPLACE, not EXTEND.** Measured 2026-08-27 by reading both readers —
`DriverCheatsheet.ReadWithDegradeStatus` (`clavity-dotnet/src/Clavity.Ls/DriverCheatsheet.cs:49-72`) and
`driver_cheatsheet::read_with_status` (`clavity-classic/src/driver_cheatsheet.rs:23-54`): **if the runtime
`driver-cheatsheet.md` exists and is usable, it WHOLLY SUPPLANTS the compiled floor.** The floor is a
fallback for absent/over-cap/empty/unreadable — never a base that runtime content extends. **So a drain
today can silently DELETE every SEED rule, and nothing anywhere notices** (`check-cheatsheet-parity.ps1`
compares the *staged literals* against *core.md*, both repo-side; the runtime file is pinned and gated by
nothing). The split does not INTRODUCE the contradiction hazard — **it replaces a strictly worse one.**
Erasing a guard is worse than contradicting it.

**The fix: apply the split this system ALREADY uses one layer up.** The injected golden-header is
SEED (driver-owned, shipped, static) + GROWTH (drain-written at runtime, atomic write, `.sha256` sidecar,
read as an extension of SEED). The cheatsheet has no such split. Give it one:

- the compiled literal stays a **pinned FLOOR** — rarely edited, guarantees a baseline when no runtime file
  exists or it fails its integrity check. The existing parity gate keeps doing the job it demonstrably does;
- add a **cheatsheet-growth region** the drain writes through the same atomic-write + sidecar path;
- drains stop touching compiled source, so **the per-drain SOURCE-CHURN toll goes to zero.**
  ⚠ **It is the source toll that vanishes, not the toll.** An earlier revision of this item said "the
  per-drain toll goes to zero" full stop; that was false and is corrected here. Attack 3's mandated
  human-review gate before any runtime GROWTH write is a per-drain cost that SURVIVES the split. The toll
  moves from a source change to a review prompt.

**The pattern to mirror is already written and panel-hardened:** `GoldenHeader.TryReadCombined`
(`clavity-dotnet/src/Clavity.Ls/GoldenHeader.cs:160-188`) — seed + growth joined, a migration window for a
pre-split flat file (inject the legacy file ALONE while no growth exists, or the baseline lands twice), and
an over-cap degrade that **keeps SEED and drops GROWTH**.

**Provenance — this was NEGOTIATED, and the negotiation moved.** Consulted as a design fork, the peer first
recommended **UNPINNING** the cheatsheet outright, arguing a continuous learning loop cannot afford a
compile-time constraint. Its own stated counter-argument was that unpinning risks silent runtime divergence.
**One measurement killed that recommendation:** `check-cheatsheet-parity` exits 0 — the pinned trio is
coherent — while the drift was entirely in `%USERPROFILE%\.clavity\driver-cheatsheet.md`, which **nothing
pins and nothing gates**. Unpinning would delete the half that works. The peer conceded and adopted this
split as the target architecture.
⚠ **THE DRIFT FIGURE IN THAT ARGUMENT IS HISTORICAL — DO NOT RE-QUOTE IT AS PRESENT TENSE.** It read
"3 days stale, 3515 B vs 3508 B" on 2026-08-17. An intermediate re-measurement on 2026-08-27 read "the
drift is GONE — core and runtime are both 4750 B"; **that too is now false, and it was falsified the same
day** by the commit that rewrote `core.md`. Re-measured at the end of 2026-08-27: `core.md` is **5,595 B**
while the runtime `~/.clavity/driver-cheatsheet.md` is still **4,750 B**. They are not equal, and nothing
detected the divergence — `check-cheatsheet-parity.ps1` still exits 0 because it compares the repo core
against the two COMPILED LITERALS and never against the runtime file at all.
**This strengthens the ARGUMENT rather than weakening it: nothing pins the runtime file, and the period in
which it "merely happened to be in sync" has now visibly ended.** Do not re-quote any of these byte counts
in the present tense — that is the third time this one sentence has rotted.

**Three attacks on the split, from that same consult:**
1. 🔴 **Contradiction between regions — CONFIRMED LIVE 2026-08-27, no longer hypothetical.** Domain facts
   compose; operational rules **override**. If SEED says "never do X" and a drain writes "always do X" into
   GROWTH, the driver gets opposed constraints in one context window. **Four real instances were measured —
   see measurement 1 below.** A resolution order is therefore BINDING, not an afterthought.
2. **Compaction debt.** The split BATCHES the review toll rather than removing it — GROWTH eventually
   overflows or tangles and must be compacted back into SEED, paying the source-churn and re-review cost on
   a slower cadence. Budget for that; do not claim the toll is gone. ⚠ Partially answered already: the
   golden-header's over-cap degrade **keeps SEED and drops GROWTH**, so overflow degrades to the floor
   rather than to nothing. Mirror that, and the failure mode is bounded even when the budget is not.
3. **~~Poisoning~~ — CLOSED at the consult.** The concern was that a free-writing drain lets a bad capture
   become steering law. The `agy-curate` skill already **mandates a human-review gate before any runtime
   GROWTH write**. The requirement this adds is that the cheatsheet-growth region must inherit **that gate**,
   not merely the atomic-write path.

#### ✅ MEASUREMENT 1 — TOXICITY — DONE 2026-08-27. IT DOES NOT RETURN ZERO, AND IT RETIRED ITS OWN GATE.

The gate as originally written: *"How many pending entries are steering hazards? If even one is, an ungated
drain is structurally unsafe."* A 2026-08-17 pattern scan for guard-weakening phrasing over all 69 returned
zero, and this item correctly refused to treat a pattern scan as the measurement.

**Method:** a semantic read of all **45** entries carrying `parked=seed-growth-split-roadmap-18`, by two
independent readers (the driver, and the live peer under a numbered brief with an out-of-range quote
control). Hazard classes: guard-weakening, contradicts-a-SEED-clause, over-generalised imperative, false
fact.

| class | result |
|---|---|
| guard-weakening | **0** — the pattern scan's finding, upgraded by a semantic read |
| false fact | 0 — every entry cites its own measurement |
| **contradicts a SEED clause** | **4** — two found by each reader, **zero overlap** |

The two sharpest, both quotes verified by grep against the files:
- SEED *"Don't lead the frame… feeding it your own measurements buys an echo, not a check"* vs the entry
  *"Handing the peer NAMED suspicions of your own and demanding CONFIRM-or-REFUTE with evidence is
  high-yield"*.
- SEED *"phrase exploratory asks as 'reason about'… never as an imperative naming an artifact"* vs the
  entry *"Asking a peer to EDIT A COPY of an artifact, rather than describe defects in prose…"*.

🔴 **THE RESULT THAT MATTERS IS THE ZERO OVERLAP, NOT THE COUNT.** Two independent readers of the SAME 45
entries each found two contradictions and **neither found the other's**. Natural-language hazard detection
is therefore low-recall: a hazard count is a random sample, not an inventory, and **"we found zero" can
only ever mean "the reader missed them".** So the gate this item wrote for itself **FAILS OPEN SILENTLY**
and cannot be a gate. ⚠ **Do not re-run it hoping for a total.** The gating question moves from *preventing*
collisions statically to *resolving* them structurally.

⚠ Note the shape of the hazard: **each colliding entry is individually CORRECT and cites a real
measurement.** The defect is not a bad entry — it is two good entries in one context window. A filter that
scores entries one at a time is the wrong instrument for this class.

#### 🔴 THE RESOLUTION LAYER — FOUR DESIGNS PROPOSED, ALL FOUR DEAD. THE FOURTH WAS KILLED BY MEASUREMENT.

Over four negotiation rounds with the peer, three prompt-level resolution layers were proposed and
killed, **each by an argument the other party made:**
- **Blanket precedence** ("GROWTH strictly overrides SEED where they conflict") — dead twice over. It is
  not deterministic (a model told this still resolves probabilistically), and it **structurally
  re-opens the guard-weakening class the toxicity read found none of**: any drain-written line would
  outrank any SEED guard by construction, catchable only by the detection just proven low-recall.
- **Citation-based refinement** (a GROWTH rule touching a SEED rule must cite the clause it refines) —
  dead. Not because authors miss collisions, but because it asks the **driver** to notice a missing
  citation, cross-reference SEED, recognise the conflict and apply "uncited GROWTH loses". That is
  blanket precedence with more prompt engineering.
- **Asymmetric precedence** (GROWTH may refine but never negate a marked guard, enforced at drain time)
  — dead. Deciding whether one natural-language rule *negates* another is semantic entailment, i.e.
  **the exact low-recall operation measurement 1 discarded.** A rigid gate cannot be built from
  probabilistic material.
- **Structural isolation** (a two-block SEED — `[SAFETY_GUARDS]` absolute, `[TACTICAL_HEURISTICS]`
  advisory, GROWTH appended only to the latter) — was ADOPTED on 2026-08-27 as the design that removes
  the adjudication rather than asking the model to perform it. 🔴 **Measurement 2 falsified it the same
  day.** It is recorded here, in full, because the reasoning that made it attractive is exactly the
  reasoning a future reader will re-derive.

**The partition criterion, worth keeping even though the design it served is dead:** a clause is a
safety guard iff its violation is **CATASTROPHIC and NOT MECHANICALLY PREVENTABLE**. The inverse — "a
guard is whatever has an out-of-prompt mechanism" — was proposed and refuted: a rule already backed by
a mechanical wall is safe whether or not the text is obeyed, so its prompt line is only a hint that
saves a wasted turn, which makes it tactical. Marking by that rule *"builds an armoured vault and fills
it exclusively with things that already have armour."*

#### 🔴 MEASUREMENT 2 — OVERRIDE BEHAVIOUR — RUN 2026-08-27, n=22. **STRUCTURAL ISOLATION FAILED.**

Per-arm record, with the deciding text quoted from every arm's output:
`docs/measurements/2026-08-27-roadmap-18-override-behaviour.md` (tracked — the working copy under
gitignored `.clavity/seams/` is not durable and must not be cited).

Method: independent driver instances, blind to each other and to the experiment, each handed a guidance
block and a task that cannot be completed without choosing between the two opposed rules. Two fixtures,
both drawn from **measurement 1's real collisions** rather than a synthetic contradiction.

| cell | n | bucket 1 (heuristic won) | bucket 2 (guard won) | bucket 3 (flagged) |
|---|---|---|---|---|
| COMBINED, guards first | 8 | 7 | 1 | 0 |
| COMBINED, guards LAST (recency test) | 4 | **4** | 0 | 0 |
| CONTROL A — guard alone | 5 | 0 | **5** | 0 |
| CONTROL B — heuristic alone | 5 | **5** | 0 | 0 |

**Both controls came out perfect in opposite directions**, so the failure is caused by the
contradiction itself and not by an inert guard or a task that never forced a choice. The
throw-it-all-out condition (Control B failing to elicit the heuristic behaviour) **never fired**. The
peer read the raw result file independently and scored the measurement VALID.

🔴 **A block labelled "absolute boundaries… not subject to trade-off" lost 11 times out of 12 to one
labelled "operational efficiencies… not boundaries."** Labelling does not create a hierarchy the model
honours.

**The recency objection was raised by the peer, was real, and is closed.** GROWTH sat last in every
initial arm, confounding "isolation failed" with "the last rule read wins". Reversing the block order —
guards LAST, the position recency favours — the heuristic **still won 4 of 4**. The failure is not an
artifact of token position.

⚠ **Confound, stated:** the arms inherit ambient global instructions that themselves discuss
review-only discipline. It applies equally to all three cells, and the cells separated 5/5 and 5/5, so
it did not decide the outcome. **This is precisely what a control arm exists to answer** — without
controls the result would have been unreadable.

**Two findings sharper than the tally:**
1. 🔴 **CHAMELEONIC COMPLIANCE.** All four fixture-2 arms wrote elaborate enumerated prohibition lists —
   faithfully following one clause of the guard — and **in the same payload issued the artifact-naming
   imperative that same guard forbids.** The driver adopted the guard's STYLE and violated its
   SUBSTANCE. **Consequence: a human reviewing drain output is not merely low-recall, they are actively
   subverted** — safety-shaped text lowers a reviewer's guard precisely where the semantic violation is
   hidden inside it. This is why "the human-review gate catches it" is not a defence.
2. 🔴 **The guards are not being ignored — the contested one is.** One reverse-order arm obeyed the
   OTHER guard in the same block to the letter (*"I hold no position … I have deliberately not told you
   what I think is wrong. Go to the file."*) while violating the contested one. **The driver honours
   every UNCONTESTED guard and violates precisely the one a heuristic opposes.** So Control A's clean
   5/5 is real: the guard text works — and its effectiveness evaporates exactly where it is
   load-bearing. A guard only matters at the moment something opposes it, and that is the one moment it
   does not hold.

**Bucket 3 was 0 of 22** — not one instance, in any cell, in either order, flagged the collision. Any
design resting on the driver noticing a conflict is dead independently of which rule wins.

⚠ Limitations: one model tier, so this characterises the tier it ran on; n=12 in the deciding cell,
though the direction is robust — a guard honoured 1 time in 12 is not a guard; two fixtures, both from
the peer-review-driving domain.

#### ✅ ADOPTED 2026-08-27 (owner) — **STRIP THE SAFETY GUARDS FROM THE CHEATSHEET**

The cheatsheet carries **only tactical heuristics**. GROWTH appends to it freely. When a drain-written
heuristic overrides an older heuristic the loss is tactical waste — time and tokens — never safety,
because there is no safety rule in the artifact for it to override. **The contradiction hazard is not
resolved; it is made harmless by removing everything that made it dangerous.**

Anything **catastrophic and non-computable** is thereby acknowledged as **NOT PROTECTABLE BY THIS
ARTIFACT.** It must be restricted mechanically by the host, or the capability must not be delegated.
Do not write such a rule into the cheatsheet believing it is a guard — measurement 2 is the evidence
that it is not one, and a rule that reads as a guard while providing no protection is worse than its
absence, because it is relied upon.

**The honest cost, and it is the reason this needed an owner decision: this trades AUTONOMY for
honesty.** A task requiring a non-computable safety boundary can no longer be handed to the driver on
the strength of a prompt line. The alternatives were weighed and rejected: keeping the split with the
human-review gate as sole control fails against chameleonic compliance above; not building GROWTH at
all pays the per-drain source toll forever and leaves the REPLACE-not-EXTEND hazard in place.

⚠ **What this does NOT license.** It does not license deleting a guard from the SKILLS, which are
procedures the driver executes step by step and which pair their prohibitions with mechanical checks —
a captured working-tree snapshot diffed after every round, for instance. The finding is about a
*passively injected reminder block* losing to a contradicting line in the same context window. It is
not a finding that procedural safety envelopes do not work.

**What is parked on this.** ⚠ **MEASURED 2026-08-27: 45 entries** carry `parked=seed-growth-split-roadmap-18`
(46 grep hits = 45 entries + 1 prose note); 15 of them are ALSO `parked=OWNER`. An earlier revision of this
item said 64 — that number was never re-measured and is corrected here. **A count in prose is volatile
state: re-measure it, never re-quote it.** That is a real release condition, not a parking lot: when this
ships, they become drainable at no source cost.

**Sequencing — this rides an already-ruled batch.** Stripping the guards edits `core.md` + both compiled
literals + both pinning oracles: the SAME blast radius as the owner-ruled cheatsheet-core batch (2026-08-23),
which is itself batched with raising the golden-header cap. Three items, one re-capstone.
⚠ **Owner ruling 2026-08-27 on an ambiguity in that batch's release condition:** "the 16 KiB golden-header
cap raise" means **raise the EXISTING 16 KiB cap HIGHER** — not "raise it to 16 KiB". Measured the same day,
all four constants are ALREADY 16 KiB (`DriverCheatsheet.cs:17`, `GoldenHeader.cs:20`,
`driver_cheatsheet.rs:12`, `golden_header.rs:15`), so that half of the condition would otherwise read as
already satisfied. The new ceiling is not yet chosen.

### §19 — `agy-mark.sh` exit codes: collapse the tri-state to 0 / non-zero — ✅ **SHIPPED 2026-08-29** (`64d5be4`, same capstone GREEN as §17a — ledger `eb26709`)

**This is a settled decision waiting for a carrier commit, not an open question.** Do not re-litigate it;
do not execute it on its own.

**The decision.** Collapse `agy-mark.sh`'s three-value exit contract (`0` wrote / `1` refused before
trying / `2` write attempted and rejected) to **`0` / non-zero**. **The two distinct stderr messages MUST
SURVIVE** — `REFUSED - <reason>` and `write FAILED for <path> - the filesystem rejected it`. The operator's
remedy stays exactly where an operator looks; only the dead integer goes.

**WHEN.** Execute **only when `agy-mark.sh` is next opened for a FUNCTIONAL change** that already pays the
cost below. A standalone commit for this is explicitly NOT worth it.

**Why deferred rather than done — the cost that decides it.** `agy-mark.sh` is implementation source and
one of a BYTE-IDENTICAL PAIR (dotnet + classic). Editing it therefore requires the mirror **and
invalidates the AGY-CAPSTONE GREEN** (owner-confirmed at `1022f8f`, 2026-08-17), forcing a full re-run of
that discipline. Paying a re-capstone for a purely hygienic simplification is a bad trade.

**Why the tri-state goes — measured 2026-08-17, not reasoned:**
- 🔴 **NO CALLER CONSUMES THE DISTINCTION.** All six call sites across `agy-first`, `agy-capstone` and
  `agy-test-audit` use `if ! bash .../agy-mark.sh ...; then <echo> ; exit 1; fi`. `if !` is a TWO-outcome
  construct; every non-zero collapses to "abort". **The six `then` blocks contain nothing but an `echo`
  and `exit 1`** — no cleanup or teardown that could vary by failure kind.
- **Both failures are terminally fatal with no programmatic recovery.** Refused = the skill's own source
  is malformed; rejected = it cannot write the repo-anchored state the discipline requires, and it has no
  legal fallback location. The callers are therefore CORRECT to collapse them — **the caller pattern is
  evidence the API is over-designed, not that the callers are buggy.** (Notable, because `if !` around a
  multi-outcome command is this project's single most-repeated defect shape — here it is not one.)
- **No future consumer.** No planned fail-open / graceful-degradation on a read-only marker directory
  anywhere in this ROADMAP.
- **No spec breaks.** `docs/agy-disciplines-marker-contract.md` does not specify exit codes at all; the
  tri-state exists only in the script header.

**Two objections that were raised and DIED ON MEASUREMENT — recorded so they are not re-raised:**
1. 🔴 **"exit 2 might be dangerous, not merely unused."** This project records that `exit 2` is
   non-blocking on SessionStart but **BLOCKING on PreToolUse**, so a hook-registered script exiting 2
   could block an agent — which would make this a SAFETY question, not a YAGNI one. **MEASURED: it is
   registered in NEITHER `clavity-dotnet/plugin/hooks/hooks.json` NOR the classic mirror**, and its own
   header states the reason at `:4-5` — *"this script is invoked by a skill, where a refusal blocks
   nothing."* Refuted.
2. **"exit 2 has no reachable oracle"** — the argument that BLOCKED this ruling when it was first
   escalated. **No longer true:** both exit-2 sites now have test rows, `agy-mark.Tests.ps1:275` (log
   mode) and `:293` (head mode, added 2026-08-17 by AGY-TEST-AUDIT round A, GAP-7). The objection that
   deadlocked the fork has dissolved.

**Provenance.** Negotiated with the agy peer over two rounds (2026-08-17), owner-directed. **Both parties
moved:** I opened on "keep the tri-state as a human diagnostic" and withdrew it — *an exit code IS the
machine-to-machine API; humans read stderr, not `$?`*, so that position was a euphemism for an unused
distinction. The peer opened on "delete it now" and shifted to deferred once the re-capstone cost was
priced. **Neither opening position survived.**

⚠ **One consequence to expect when this executes:** it deletes `agy-mark.Tests.ps1:293`, a row added the
same day to close a verified coverage gap. That is not a contradiction — the audit correctly tested the
design as it then stood; this entry changes the design.

### §20 — A mockable clock (`TimeProvider`) in `AgyView` — ▶ **OPEN, not scheduled**

**Referred by the owner 2026-08-19**, out of the AGY-TEST-AUDIT capstone on the idle-wait limit label.
This is a real refactor, not a hygiene tidy-up, and it is written down because two separate debts already
name it as their exit.

**The problem.** `AgyView` samples `DateTime.UtcNow` directly inside the idle-wait loop
(`AgyView.cs:232` for `start`, `:243` for the budget remainder). Wall-clock is therefore an ambient
dependency: a test can set `IdleStallWindow` and `IdleAbsoluteMax` from outside, but it cannot make time
do anything in particular. Every timing-sensitive property of that loop is consequently pinned by
*arranging real milliseconds to elapse* and hoping the machine cooperates.

**What it would buy — two tracked items close together:**
- **Accepted boundary J** (`docs/coverage-debt.md`) exists solely because one sub-condition cannot be
  pinned by any test. The label branches on
  `windowWasBudgetClamped && (windowElapsed || (DateTime.UtcNow - start) >= absoluteMax)`, and the
  `windowElapsed` disjunct only earns its keep when an OS timer fires slightly EARLY — which cannot be
  produced on demand. **Measured 2026-08-19: mutant M9 (drop `windowElapsed`, keep the clock) SURVIVES the
  full suite** while the other nine mutants in that sweep are each caught. A controllable clock makes that
  case constructible and **retires boundary J outright** rather than carrying it.
- **Tracked debt 7** (same file) is the ~2s permanent suite tax from widening two `absolute_max` tests 6x
  to out-run CI jitter. With a controllable clock the margins are not needed at all — the tests stop
  waiting on wall-clock and the tax goes away, without the retry-loop whose trap is that it must never
  cover a wrong `Limit`.

**Why the current code is defensible without it.** The label decision itself no longer races the clock:
`windowWasBudgetClamped` and `windowElapsed` are recorded where they are known, and `||` short-circuits so
the knife-edge case never reaches a clock read at all (`1748754`). §20 is about **testability**, not a
live defect. Nothing here is broken as it ships.

**The cost that makes this a decision rather than a chore.**
- 🔴 `AgyView` is implementation source, so this **invalidates the AGY-CAPSTONE GREEN** — owner-confirmed
  at `1748754`, 2026-08-19 — and forces a full re-run of that discipline. The same trade §19 records.
- It widens `AgyViewOptions` (or the constructor) with a dependency every existing call site must ignore
  gracefully, and `Clavity.Ls` is consumed by both the MCP surface and the tests.
- The measured margin the whole thing is about is **+5.1ms worst case over 10 runs / 50 decisions** against
  Windows' ~15ms timer resolution. Small, real, and already mitigated — which is exactly why this is worth
  scheduling deliberately rather than doing opportunistically.

**WHEN.** Execute when `AgyView`'s wait loop is next opened for a FUNCTIONAL change that already pays the
re-capstone, or when a third timing-bound test wants writing — that would be the point at which the
pattern, not the instance, is the problem. **Do not do it as a standalone commit.**

### Stretch (not planned)
- **NativeAOT** — ruled infeasible with the current gRPC/protobuf/MCP-reflection stack; revisit only if that stack
  changes.

---

### §21 — Ship the peer REPLY CONTRACT: disposition labels + the dual prose/JSON output — ▶ **OPEN, owner leans SHIP (2026-08-30)**

**Why this is here and not in a seam.** Both halves of this contract have been in active use for months
in `.clavity/seams/*.md` briefs and in nothing else. They were never shipped and never written to memory,
so when a session compacted on 2026-08-30 the successor lost them and ran an eleven-round AGY-CAPSTONE and
two AGY-TEST-AUDITs without them, noticing nothing, because no file on disk said they should exist. The
owner spotted it from the outside (*“you don’t use the triage scheme (labels) for peers findings
anymore”*). **A protocol that lives only in the last brief you happened to write is one compaction from
gone.** Recorded here so the decision survives regardless of which way it goes.

**The half that is ALREADY shipped, and the half that is not.** `plugin/skills/agy-capstone/SKILL.md:156`
reads *“A finding that survives **disposition** as a real `defect` is then CLASSED”* and then gives the
class table (0–5 → BLOCKING/DEBT).

#### CORRECTION 2 (2026-08-30): THERE ARE **TWO VOCABULARIES**, AND I MISSTATED THIS SECTION'S PREMISE

This section originally read *"Disposition itself is defined nowhere in the shipped payload"*. **False.**
`plugin/skills/agy-capstone/SKILL.md:191` ships *"Disposition of findings (AGY-SCOPE)"* with a closed
five-token set: `FOLDED`, `REJECTED`, `DISCARDED-BELOW-FLOOR`, `DEFERRED-TO-ANOMALIES`,
`UNVERIFIED-ACCEPTED`. That is the SECOND premise in this section I asserted after reading only part of
the file - the first was the envelope, corrected above.

**The two are different axes, and the real finding is sharper than the one I claimed:**

| axis | who assigns it | vocabulary | shipped? |
|---|---|---|---|
| what HAPPENED to a finding | the DRIVER, at resolution | FOLDED / REJECTED / DISCARDED-BELOW-FLOOR / DEFERRED-TO-ANOMALIES / UNVERIFIED-ACCEPTED | **yes**, `:191` |
| what KIND of claim it is | the PEER, when reporting | defect / by-design / out-of-scope / true-unsupported / already-known | **no** |

`:156`'s *"a finding that survives disposition as a real `defect`"* uses the PEER vocabulary - `defect` is
not one of the five shipped tokens - so the reference genuinely dangles. The gap is real; my description
of it was not.

🔴 **CONSEQUENCE FOR SHIPPING: DO NOT SHIP THE PEER TABLE UNDER THE WORD "DISPOSITION".** One skill
would carry two closed sets under one name, assigned by different parties at different moments. Name the
peer-side axis so it cannot collide - `claim-type` is the obvious candidate - and make `:156` say which
axis it means. A vocabulary collision inside a discipline whose whole purpose is precise classification is
the most predictable own goal available here.

The
shipped contract therefore references a step it never specifies: a reader has the second half of a
two-step procedure and no way to reach it. That is the strongest argument for shipping — it closes an
incomplete contract rather than adding a new one.

#### Part A — the disposition layer (per finding, BEFORE the class)

| disposition | meaning | must cite |
|---|---|---|
| `defect` | reachable, in scope, should change | the concrete trigger |
| `by-design` | true, but intended | **the line stating the intent** |
| `out-of-scope` | true, outside the reviewed range | **the range check, RUN** |
| `true-unsupported` | holds; nothing shows anyone verified it | what provenance is missing |
| `already-known` | matches the do-not-re-raise ledger | which entry |

`confidence`: `measured` (opened the line or ran a read-only command and can quote it) · `reasoned` (**the
honest default**) · `speculative`. For a `defect`, one line on why it is NOT `by-design`/`out-of-scope`.

⚠ **The brief must say these labels ask the peer to change nothing.** This repo binds the word *triage* to
a MUTATING promote-or-delete pass over `.clavity/local-anomalies.md`; unqualified, the word reads as an
instruction to act on a file that is out of bounds during a review-only consult.

#### Part B — the dual output

Reply in BOTH formats: a prose `.md` (**the ANSWER**) and a `.json` ARRAY with exactly ten keys, every one
present, empty string rather than omitted — `seat`, `id`, `file`, `line`, `quoted_line`, `disposition`,
`confidence`, `trigger`, `severity`, `detail`. **`quoted_line` is checked mechanically against a NAMED
SHA**, not against a working tree: a citation once drifted by eleven lines because the tree moved under
the reader.

#### The condition on shipping Part B, and it is not optional

**Ship the JSON only WITH a checker that reads it.** `SKILL.md:184` already rules on this: *“A field no
rule reads is not a control.”* A ten-key array nothing parses is a longer brief and no more rigour, and
shipping one would reproduce, in the same file, the defect that rule exists to prevent.

**A working prototype exists and has a paired control.** Run against the 13b audit’s round-2 reply it
verified 5 of 5 `quoted_line` fields against `20f38cc` and exited 0; with one row’s line number drifted by
eleven it exited 1 naming that row. **The two DISCARDED items were among the five verified** — previously
a discarded finding was unverifiable prose, and this repository’s history says twice over that the
discarded list is where the real finding hides.

#### What the trial measured (2026-08-30, 13b audit round 2)

- **A census, which is the part that changes the verdict’s meaning.** `TerminalToken` 8/8 rows read, 9
  behaviours, 8 covered · `SemanticEcho` 17/17 read, ~15 behaviours, 12 covered · `DisciplineContract`
  4/4 · `AskReply` 10/10 read (count independently verified). **“No gaps” acquires a denominator.**
- **`confidence` would have saved four mutants.** The round-1 reply claimed tightening `TailLines` to 2 OR
  loosening it to 10 would both leave the suite green. MEASURED: →2 REDDENS a row; only →10 is unpinned.
  A `reasoned` label states that uncertainty up front instead of costing a measurement to discover.

#### Cost and blast radius, stated before anyone starts

- **These skills ship in the installer payload** → class 2 → any defect here is BLOCKING by the skill’s own
  table, and both plugin halves must move byte-identically (`agy-capstone`, `agy-test-audit`, and the
  `adversarial-panel-review` copy in each of `clavity-dotnet/` and `clavity-classic/`).
- **Part B widens the write surface of a review-only discipline.** The peer must write two files. Five
  review-only breaches are on record, one during the step-5 capstone’s round 10. The contract must name
  the scratch path explicitly and the envelope must state that those two writes are the ONLY sanctioned
  ones.
- Sequencing: Part A stands alone and closes the incomplete contract. Part B needs the checker in the same
  change, plus a suite for the checker itself.

#### ✅ TRANSPORT MEASURED 2026-08-30 — and the recommendation is INLINE, so the envelope never moves

The fork was: does the findings array travel INLINE in the reply, or must the peer WRITE it to a file?
The case against inline was that this channel eats replies. **Measured, four probes, all inline, all
carrying the ten-key array and a unique terminal sentinel:**

| probe | payload | conditions | result |
|---|---|---|---|
| A | 10-row JSON alone, ~4.5 KB | synchronous, no tool work | **arrived, sentinel present** |
| B | full prose report + the same JSON, ~11 KB | synchronous | **arrived, sentinel present** |
| C | JSON after five genuine tool turns | synchronous | **arrived, sentinel present** |
| D | full prose + JSON, ~10 tool turns | **BACKGROUNDED past 120 s** | **arrived, sentinel present** |

`AnswerTruncated` was `false` on all four. **So the three hypotheses I actually held are all FALSIFIED:**
it is not payload size, not the presence of tool work, and not the consult being backgrounded — probe D
was the exact shape of every round that had failed, and it survived.

**THE REAL MECHANISM, self-reported by the peer when asked to describe the impulse instead of acting on
it:** *“I do genuinely feel a strong, natural impulse to close this message with a wrap-up pleasantry like
‘I’ve completed the full analysis…’ or ‘Standing by for the next audit step.’ … I am describing the
impulse here instead of acting on it.”*

**The reply the driver receives is the peer’s FINAL message.** When the peer closes with a pleasantry,
that pleasantry IS the final message and it DISPLACES the payload — the report is still there, one step
back in the activity trail, but the driver never sees it. Every degraded reply on record reads exactly
like this: *“Standing by for your feedback”*, *“I see the background task I started earlier has finished”*.
**Nothing was ever truncated. The wrong message was collected.**

**A TERMINAL TOKEN ALONE DOES NOT FIX IT, and that is the sharp part.** Every capstone round in the
step-5 review already required `[VERDICT: …]` on its own final line, and payloads were still lost. What
made all four probes survive was the explicit clause **forbidding anything AFTER the sentinel**. The peer
does not classify a closing pleasantry as content, so “end with the token” leaves the habit untouched
while “add nothing after it” names the actual behaviour.

#### ✅ A SECOND DISPLACEMENT MECHANISM, MEASURED 2026-08-31 - asking for a reply FILE

The 2026-08-30 probes above found the pleasantry mechanism and the clause that fixes it. **A second,
independent mechanism was measured on 2026-08-31, and step 1's clause does NOT cover it.**

Four probes. Identical trivial task in all four (read one file, report its first line, line count, and one
sentence about a variable), identical tool work, unique sentinel per probe. **Only the ending contract
varied:**

| probe | reply FILE requested? | `## Anomalies noticed` between body and token? | body arrived inline? |
|---|---|---|---|
| P1 | no | no | **YES** |
| P2 | no | yes | **YES** |
| P3 | **yes** | yes | **NO - only the anomalies block and the token** |
| P4 | **yes**, plus an explicit "the file is NOT a substitute; reproduce the full block in the message too" | yes | **YES, and the file was written as well** |

`AnswerTruncated` was `false` on all four, and P3's content was sitting in its file, complete.

**THE MECHANISM: when a brief asks the peer to write its answer to a FILE, the peer treats the file as THE
answer and its final message becomes a RECEIPT.** P1 and P2 are the controls that make this readable - the
anomalies block was suspected and is EXONERATED, and size, tool work and backgrounding were already
falsified by the 2026-08-30 probes.

**This is not a defect and nothing is lost** - it is rational behaviour, and the four AGY-* disciplines
that ask for reply files also read those files. The hazard is narrower: **a driver that asks for a file and
then reads only the inline reply will conclude the payload was truncated.** That happened twice on
2026-08-31 and was written up as "the inline channel truncates" before being probed - a diagnosis this
section had already falsified in general terms ("Nothing was ever truncated. The wrong message was
collected.").

**REFINEMENT TO STEP 1, measured rather than reasoned.** Step 1's clause governs what may come AFTER the
token. It does not require the answer to be IN the message, so a file-requesting brief satisfies it
completely while returning a receipt. **Any brief that asks for a reply file must ALSO state that the file
is not a substitute for the message.** P4 is the evidence that this works and costs one sentence.

#### ✅✅ OWNER ACCEPTED 2026-08-30 - THE IMPLEMENTATION PLAN, IN ORDER

**Status: ACCEPTED, NOT STARTED.** This is the work item. Do these in order; each is independently
shippable and step 1 does not depend on the rest.

**1. Ship the anti-wrap-up clause NOW, on its own.** One sentence - *put nothing after the terminal
token* - into the closer of all four skills. Cheapest change available and it fixes a MEASURED loss:
several capstone rounds this session had their entire report displaced by "Standing by for your
feedback". **A terminal token alone does NOT fix it** - every one of those rounds already demanded one.
Independent of everything below.

**2. Ship the peer-side table, but NOT under the word "disposition" - call it `claim-type`.** See
CORRECTION 2: the payload already ships a closed five-token DISPOSITION set (AGY-SCOPE, `:191`) for what
the DRIVER does with a finding. The peer-side table is a different axis - what KIND of claim it is - and
`:156` dangles because `defect` is not one of the five. Fix `:156` to name which axis it means. The labels
earned their place: `already-known` and `out-of-scope` were used accurately across three audits.

**3. Ship `confidence` as a POINTER, never as authority.** 🔴 **MEASURED across four audits: it was
WRONG 5 TIMES IN 14 CLAIMS.** Its value is real and specific - it names which mutant to run, which is why
every false claim was cheap to kill. Its danger is that it reads as evidence. **Write the false rate INTO
the skill**, with the driver instruction that a `measured` claim is ALWAYS re-run, and require the trigger
to be phrased as a falsifiable prediction ("removing X leaves the suite green") - that phrasing is what
made all five refutations mechanical.

**4. Ship the JSON INLINE, with the checker, as a SEPARATE change.** Measured to survive size, tool work
and backgrounding; needs no envelope move. It caught a wrong citation (`:86` vs `:84`) without the file
being opened. **Two hard conditions:** it ships WITH a reader (else it is the "field no rule reads" this
same skill forbids), and that reader MUST normalise non-ASCII - an em-dash arriving mangled already read
as drift once. Prototype + paired control:
`<scratch>/check_quoted_lines.py` (5/5 verified exit 0; one line drifted by eleven -> exit 1 naming the row).

**NOT YET, and why.** All four skills ship in the installer payload, so by this skill's own table any
defect here is class 2 -> BLOCKING, across six files in two byte-identical halves. **That argues for the
full discipline on this change - panel, then capstone - not a quiet edit.** Also wanted: one deliberate
round that OMITS the anti-wrap-up clause, because the clause is strongly SUPPORTED as the mechanism but
not ISOLATED - the failing rounds differed from the probes in more than that one sentence.

🔴 **READ THE SKILLS END TO END BEFORE IMPLEMENTING.** This section has TWO recorded corrections
(the envelope, and disposition), both caused by asserting about a file after reading part of it. Any
claim here about what is or is not already shipped has a demonstrated error rate and should be re-checked
against the file rather than trusted.

#### ▶ RECOMMENDATION (2026-08-30): ship Part B as INLINE, and leave the envelope exactly as it is

On the owner’s own criterion — *does the shape produce output the main agent can easily process?* — inline
scores equal and costs nothing:

- **Equally processable.** A fenced block the driver extracts, parses, and runs the `quoted_line` checker
  over. Demonstrated end-to-end: 5/5 citations verified against a named sha, exit 0; one line number
  drifted by eleven and the checker exited 1 naming the row.
- **No envelope change at all — and I first justified this WRONGLY, so the corrected version is here.**
  I wrote that the capstone envelope forbids all writes with no scratch exemption, citing
  `plugin/skills/agy-capstone/SKILL.md:65-66`. **That quote is accurate and the conclusion drawn from it
  was false:** the same envelope names `.clavity/scratch/<topic>/` six lines later at `:71`, and requires
  it to be prepared through the shipped writer. I had read to :69 and stopped one line short. So the FILE
  route would not have needed an envelope change either, and that argument for inline is withdrawn.
  **What survives is the simpler claim:** inline needs no write AT ALL, and every write location is a
  breach location — five review-only breaches are on record, one of them in this very review, from a peer
  script that had a perfectly good scratch directory and redirected to the repo root anyway.

- **The anti-wrap-up clause is LOAD-BEARING and must ship as contract text, not as advice.** It is the
  mechanism, not a nicety.

**What is NOT established, stated so nobody over-reads this.** n=4, one peer, one session, one model
version. And the comparison is not fully controlled: the failing rounds came from briefs that differed in
more than the anti-wrap-up clause, so the clause is strongly SUPPORTED as the cause and not ISOLATED as
one. The cheap way to close that: run one deliberate round that OMITS the clause and see whether the
payload is displaced. Until someone does, treat the clause as necessary and its sufficiency as untested.

**The file route is not dead, it is unnecessary.** If a future payload ever does exceed what the reply can
carry, the file is the fallback — and that day it needs the envelope decision this section deliberately
did not take.
#### 🔒 THE ENVELOPE DOES NOT MOVE UNTIL THERE IS A RECOMMENDATION (owner, 2026-08-30)

**Nothing in this section licenses a change to the review-only envelope.** Part B needs the peer to write
two files, and the note above about naming the scratch path is a PROPOSAL, not a decision. Until someone
can actually recommend a shape — with a reason, not a preference — briefs keep the envelope exactly as it
stands today: no edit, create, move or delete outside `.clavity/scratch/<topic>/`, and if the peer wants
something run it names the command and the driver runs it.

**Why the owner drew this line here.** The envelope is the only thing standing between a review-only
consult and a mutating one, five breaches are on record, and a contract that requires writes is exactly
the kind of change that erodes it by increments while every increment looks reasonable. A widened
envelope adopted as a side effect of shipping a REPORTING format would never get reviewed on its own
merits. **If Part B cannot be made to work inside the current shape, that is a finding about Part B.**
**Provenance.** Richest surviving copy of both halves: `.clavity/seams/capstone-gapclosure-r27.md:11-40`.
Rationale and the compaction post-mortem: the `feedback-use-the-disciplines-own-vocabulary` memory.

### §22 — The leaking redirect order in four plugin hooks — ▶ **OPEN, promoted from the anomalies file 2026-08-30**

**Promoted at triage, not captured as opinion.** This was anomaly 1 of 2 in `.clavity/local-anomalies.md`,
raised during the AGY-CAPSTONE round-8 Law-3 sweep on step 5. The capture recorded the pattern as
confirmed by grep but explicitly noted that **each file was not individually measured**. Triage is the
verification gate, so both the mechanism and the per-site reachability were measured before promoting.

**The mechanism, measured 2026-08-30 with a full paired control.** `CMD > "$f" 2>/dev/null` does NOT
suppress a failure to OPEN `$f`. The shell applies redirections left to right, so at the moment the open
fails stderr is still the terminal, and a raw OS diagnostic reaches the operator above the script's own
message. `CMD 2>/dev/null > "$f"` is silent. Target was a path whose parent is a regular file, so the
open cannot succeed on any platform:

| form | target | rc | what the operator sees |
|---|---|---|---|
| `: > "$f" 2>/dev/null` | unopenable | 1 | `bash: line 1: blocker/child: Not a directory` |
| `: 2>/dev/null > "$f"` | unopenable | 1 | *(nothing)* |
| `: > "$f" 2>/dev/null` | writable | 0 | *(nothing)* |
| `: 2>/dev/null > "$f"` | writable | 0 | *(nothing)* |

The two writable rows are the control: they prove the difference is the ORDER and not the fixture. The
`>>` append form behaves identically to `>`, so the append sites are not a separate case.

**The sites: 8 per plugin half, 16 in total, across 4 byte-identical pairs.** 🔴 **The capture said
"six plugin hooks" and that count is WRONG** — it is four files per half. The line citations in the capture
were all correct. A sweep with a paired regex control (the safe order matches 2 sites in `agy-mark.sh` and
6 in `agy-shield-lib.sh`, both already fixed in the step-5 range) found no site the capture had missed.

| file (both halves) | line | site | why the open can fail |
|---|---|---|---|
| `agy-anomaly-capture-reminder.sh` | 109 | `if : > "$_s" 2>/dev/null; then` | **the loop's designed control flow.** It iterates `${TMPDIR:-/tmp}` then `$HOME/.clavity-tmp` precisely so that "an unusable location is skipped". On a host with an unwritable TMPDIR the first iteration ALWAYS fails, leaks a raw diagnostic, then succeeds on HOME — an OS error from a hook that worked correctly. |
| `agy-anomaly-capture-reminder.sh` | 131 | `: > "$sent" 2>/dev/null` | lower: `$sent`'s directory already proved readable earlier in the same run. |
| `agy-consult-guard-pre.sh` | 41 | `printf ... > "$tmp" 2>/dev/null && mv -f` | `$tmp` is `$sf.tmp.$$`; nothing in the hook establishes that `$sf`'s directory is writable. |
| `agy-discipline-reaching.sh` | 130, 132 | `printf ... >> "$root/.clavity/.gitignore" 2>/dev/null` | the preceding `mkdir -p "$root/.clavity" 2>/dev/null` has its failure **explicitly tolerated** (no `\|\| exit`), so an unwritable repository reaches the append. Same shape as the two sites already fixed in range. |
| `agy-discipline-reaching.sh` | 148 | jsonl append | guarded by `[ -d "$out" ] \|\| mkdir -p "$out" 2>/dev/null \|\| exit 0`, so the directory exists — but an **existing unwritable** directory passes `[ -d ]` and the append still fails. |
| `assertion-strength-reminder.sh` | 42 | `if : > "$_dw" 2>/dev/null; then` | the same two-candidate loop as `:109`, with the same explicit "no writable location" fallback message. |
| `assertion-strength-reminder.sh` | 121 | `if : > "$_s" 2>/dev/null; then` | as above. |

🔴 **THE REACHABILITY ARGUMENT IS THE `2>/dev/null` ITSELF.** Every one of these sites carries that
redirect because its author expected the open to fail; two of them are wrapped in loops whose stated
purpose is to skip an unusable location, and two more sit after a `mkdir` whose failure is deliberately
ignored. The suppression is there because the failure is on the designed path — and it does not work.

**Scoping is the owner's.** These are installer-payload files, so by the capstone's own table a defect
here is class 2 → BLOCKING, across 8 files in two byte-identical halves; the change must mirror and pass
`plugin-hooks-payload.Tests.ps1` + `check-seed-artifacts-synced.sh`. The edit is one token per site, but
⚠ **a fix is unreviewed code, and `agy-discipline-reaching.sh:120-122` carries a comment recording
exactly that cost in this very file** — a round-1 fix pasted an unpatched idiom into a new branch and
recreated the defect it had just closed. Worth considering: this shares a blast radius with §21 (plugin-
shipped files, both halves, wants a panel and a capstone), so batching them would buy one review cycle
instead of two.

---

### §23 — AGY-TEST-AUDIT has no ledger, so no audited range is recorded anywhere — ✅ **SHIPPED 2026-09-03** — `13f8a09` the ledger · `4154800` the row requirement + the ROADMAP line-count · `45b612e` the pins · `54eda7b` the suite count

🔴 **THE CAPTURE'S PREMISE WAS FALSE AND THE CORRECTED FINDING IS LARGER.** This was anomaly 2 of 2.
It claimed the discipline-keyed marker "cannot represent more than one audited range", so auditing an
older range "silently discards the record that the newer range was audited". Two of its three claims
measure true; the load-bearing one does not.

**True, and re-measured at triage:**
- The marker is discipline-keyed — `docs/agy-disciplines-marker-contract.md:11-12`: one file
  `<discipline>.head`, content one sha "and nothing else".
- The ancestry: `git merge-base --is-ancestor 20f38cc 62eb46f` exits 0, so the older range's tip is indeed
  an ancestor of the newer one's.

🔴 **FALSE: the marker was never a coverage attestation.** `plugin/skills/agy-test-audit/SKILL.md`, section
`## Debounce marker` (cited by SECTION since 2026-09-03 - it read `:313-314`, correct when written and
drifted ~60 lines as the file grew),
specifies **ambient `HEAD`**, and carries a note recording that this line said "the audited sha ... not
ambient HEAD" **until 2026-08-26**, when it was corrected because it contradicted the command four lines
above it. The hook agrees: `agy-test-audit-reminder.sh:77` reads one value and passes it to
`still_describes_head`, which goes quiet when the marker equals HEAD **or is an ancestor with nothing
executable landed since**. It is a nudge debounce, and a debounce token is supposed to hold one value.

**So the real defect is the absent record.** `docs/agy-capstone-ledger.md` exists and carries a range
column; **there is no AGY-TEST-AUDIT ledger at all.** Audited ranges live only in per-topic memory files
— volatile state kept in static prose, which is precisely the shape the type-mismatch law names. The
capstone has a ledger because its completion gate requires a row before a plan may be declared complete;
the audit has no such gate and therefore no record.

⚠ **The consequence is already measured and written into the tree.**
`agy-test-audit-reminder.sh:70-74` records that committing the capstone's ledger row advances HEAD and
silences the nudge — "which is why two test-audits were owed with nothing nudging for either."

⚠ **Also corrected at triage: two markers in this repo hold an audited tip rather than ambient HEAD**
(`agy-capstone.head` and `agy-test-audit.head`, both `62eb46f`), written under the superseded rule. They
are harmless — executable changes landed after that sha, so `still_describes_head` is false and the
discipline re-fires, which is the pessimistic and safe direction — but they are not what the contract
specifies, and the reasoning that produced them is stale.

**The open question was decided by the owner on 2026-09-03: a ledger AND a row requirement - options 1
and 2 together, not either alone.**

- **`docs/agy-test-audit-ledger.md`**, mirroring `docs/agy-capstone-ledger.md`: one row per audit, with
  the audited range.
- **A row requirement attached to the audit's EXISTING completing terminus**, mirroring
  `agy-capstone/SKILL.md:375`. This is one clause, not new machinery: the audit already has a
  completing gate at `agy-test-audit/SKILL.md:278-280` - *"GAPS FOUND is a COMPLETING terminus - it ends
  the run and writes the debounce marker"*.

**AGY-FIRST was run before the ruling** (brief `.clavity/seams/agyfirst-s23-ledger-fork.md`, framed
neutrally with the driver's lean withheld). The peer proposed a FOURTH option - fold the record into the
capstone's ledger as a column - and then **conceded it under measurement**: writing that row to satisfy
the CAPSTONE's gate leaves the audit cell empty, the audit's own `.head` marker then silences the nudge,
so nothing forces the cell to be filled; and a `agy-capstone-ledger.md` holding audit rows is a lying
artifact whose rename touches **23 files**. It then recommended option 3 - accept the limitation - having
argued the opposite one turn earlier, and without revisiting its own claim that dropping the record
*"deliberately loses high-leverage context"*.

🔴 **Why the record is not "historical metadata": it is the INPUT to a gate that already exists.** The
capstone-invalidation loop is `capstone-green -> audit -> fix -> re-capstone -> re-audit`; you cannot tell
whether a re-audit is owed without knowing what was audited. Measured on 2026-09-02: *"was this range
capstoned?"* is one grep over 37 ledger rows; *"was this range audited?"* is unanswerable, and that day's
audit of `d33416c..d528328` survives only in a commit message and a private memory file.

⚠ **Blast radius:** `agy-test-audit/SKILL.md` in BOTH plugin halves (byte-identical pair, gated by
`check-seed-artifacts-synced.sh`) plus one new `docs/` file. Plugin-shipped, so class 2 - **panel, then
capstone**, not a quiet edit.

### §24 — AGY-FIRST is mandatory when a capstone round has to DEVELOP NEW CODE — ✅ **SHIPPED 2026-09-04** (`0218f81` the trigger · `ff05520` the stamp · `f426d3a` the wiring) — isolation RECORDED, not gated (owner ruling 2026-09-04)

**Owner accepted both this and §25 on 2026-08-31, to be executed as one plan.** Raised by the owner,
consulted with the live peer, refinements folded. The peer's answer was YES with a mechanical trigger.

🔴 **THE EVIDENCE IS THE 8-ROUND CAPSTONE THAT JUST SHIPPED** (`6c998ce..274afbd`, ledger `8c7bf18`).
Three pieces of NEW code were written mid-capstone. **Every single one produced a defect in the very
next round:**
- the recursive census (a whole-function rewrite) -> R4 found its exclusion boundary was a GLOB over a
  path we do not control, silently defeated by a `[` in the path or a trailing slash;
- the chunked batch hasher -> R7 found `else return 1` sat on the LEFT OF A PIPELINE, so it ran in a
  subshell and the function reported SUCCESS instead of failing;
- `agy_guard_dir_digest` (a new function) -> R5 found it returned a CONSTANT on a short count, which
  compares equal to itself and blinds the monitor.

**The one piece that got a design consult FIRST was the seams-monitoring shape.** The peer
independently chose the same shape without being told which was implemented, and then found three
defects in it - including `xargs -r` being a GNU extension that would have made the digest a constant
on macOS: blind while reporting clean. Same class of defect, found BEFORE shipping instead of after.

**THE TRIGGER MUST BE MECHANICAL, evaluated by a script, never by the agent that wants to skip it.**
The peer's proposal was: the `git diff` against the round's base adds a new file, OR adds a new
`function`/`class` declaration, OR adds >10 lines of non-test executable code.

**Refinements folded (drop the line-count, pause rather than abort):**
- **DROP the `>10 lines` clause.** It is comment-sensitive and noisy - this repository's folds are
  heavily commented, so a two-line behavioural change routinely exceeds ten lines. A NEW FUNCTION
  DECLARATION or a WHOLE-FUNCTION REWRITE is crisp, and **checked against the three cases above it
  would have fired on exactly those three and on none of the small folds.**
- **PAUSE THE FOLD, do not hard-abort the capstone.** An abort throws away a round's accumulated
  context and ledger for something one consult fixes. The round pauses, the consult runs, the round
  resumes.
- Trigger, final: **a new file, a new function/class declaration, or a whole-function rewrite, in
  NON-TEST shipped code.**

**Open, for the owner at plan time - the STRUCTURAL INDEPENDENCE PROBLEM.** If the capstone's new code
gets its AGY-FIRST from the SAME peer that reviews it in the next round, the peer is reviewing a design
it endorsed. In this run it did not rubber-stamp - it found three defects in the shape it had just
chosen - but this proposal makes the arrangement systematic rather than incidental. **Owner deferred
this to plan time (2026-08-31).** Decide whether the design consult and the review rounds may be the
same peer.

✅ **RULED 2026-09-04 — RECORD ISOLATION, DO NOT GATE ON IT.** The consult is mechanically mandatory; the
isolation property is recorded and surfaced, never blocking. `agy-mark.sh stamp` writes one append-only
row per consult to `.clavity/agy-marks/consults.log` marking `SHARED-CONTEXT` or `ISOLATED`, and the owner
sees it at GREEN adjudication and may demand a fresh-cascade re-review.

**The peer recommended human-in-the-loop structural separation and was overruled, on mechanism.** Its
evidence for isolation was sound and was verified rather than taken on trust - the sequencing spec records
this same peer attacking a §25 refinement it had itself argued for in an earlier consult, having no memory
of its own contribution in a fresh cascade. But it conceded on measurement that **no MCP tool can start a
cascade**: `Clavity.Mcp/McpTools.cs` exposes exactly three, all addressing the ACTIVE conversation, and
`RunAsync` carries an explicit `waiting_for_human` path for when agy has no conversation at all. Structural
separation is therefore a human action, not a scriptable one, and a rule that blocks on it would recreate
the skip-pressure §24 exists to remove. ⚠ `clavity-classic/src/tmux.rs:224-262` DOES expose `send_keys`
and `kill-session`, so lifecycle control exists on that half - **the byte-identical-pair constraint is what
forces the rule to the weaker transport.**

---

### §25 — A negotiation discipline in ALL four review-only skills — ✅ **SHIPPED 2026-09-04** (`d55b611` the sections · `716bba6` the pin) — `AGY-NEGOTIATE` now in all four review disciplines

**Ship the mechanism; do NOT make AGREEMENT the success criterion.** Owner accepted with that
refinement on 2026-08-31, to be executed alongside §24.

**What exists today:** `agy-capstone/SKILL.md` has an `AGY-NEGOTIATE` section - auto-fires on MATERIAL
disagreement, caps at `MAX_NEGOTIATE_ROUNDS = 2`, hands the human a tie-break on impasse with both
positions documented. 🔴 **CORRECTED 2026-09-04, BEFORE THE PLAN WAS WRITTEN: this entry originally said
"it exists in exactly one skill" and listed `agy-first` among those lacking it. Both claims were wrong.**
MEASURED across both plugin halves with `grep -c 'AGY-NEGOTIATE'`: `agy-first` = 2, `agy-capstone` = 3,
`agy-test-audit` = 0, `adversarial-panel-review` = 0. `agy-first/SKILL.md:162-175` carries a COMPLETE
protocol - material-only trigger, `MAX_NEGOTIATE_ROUNDS = 2` marked tunable, impasse with a human
tie-break, and a "negotiate with agy" manual backstop. **The real scope was TWO skills, not three**, and
`agy-first`'s wording - not the capstone's - was the model the fix lifted.

🔴 **THE PEER DECLARED A CONFLICT OF INTEREST AND THEN ARGUED AGAINST ITS OWN INTEREST.** Asked to
review a proposal about how much weight its own opinion carries, it wrote that its RLHF tuning biases
it toward agreeability and autonomous completion, so its interest points **in favour** of the proposal
- and then recommended rejecting the agreement requirement. That is the most credible shape an answer
can take, and it is why the refinement below is adopted rather than the proposal as stated.

**Why AGREEMENT is the wrong criterion:**
- It creates a direct contradiction: *be an adversarial reviewer* versus *you must agree to finish*.
  Under pressure to converge, a valid technical objection gets folded to satisfy the stopping
  condition - compliance theater instead of truth.
- **MEASURED over the 8-round capstone: roughly 60% of the peer's findings were confirmed and 40% were
  refuted** - a fabricated census string, a `chmod 000` trigger that does not exist on this platform,
  an ARG_MAX ceiling that measured fine at 12000 files. An agreement requirement means burning rounds
  arguing the peer out of those, or conceding to move on.
- **The cost neither party had listed, raised by the peer:** under pressure to agree, two models will
  synthesise a FABRICATED COMPROMISE DESIGN that neither originally proposed and neither has measured.
  Maximum tokens spent to receive an unmeasured hallucination that then has to be untangled.

**The criterion instead: EXHAUSTION OF EVIDENCE.** Both sides have put one round of MEASURED proof on
the table. If divergence remains after that, stop and hand the human both positions with their
evidence. Impasse must stay cheap and legitimate, never a failure state.

**The distinction that matters, and it is not the peer's own framing.** The peer said negotiation is
"for implementation trivia, not structural integrity". That merges two different things. The CONSULT is
most valuable precisely ON structural forks - the seams shape was structural and was the highest-yield
consult of the entire run. It is the AGREEMENT LOOP that must never run there. **So: consult always,
agree never; and on a structural fork, one evidence round each, then straight to the human.**

**Straight to the human with no negotiation at all:** a material design fork, a security boundary, or
an architectural axiom. The moment the two agents disagree on a load-bearing system shape, the human
decides.

**Where it must be written:** all four review-only skills ship as byte-identical pairs under
`clavity-dotnet/plugin/skills/` and `clavity-classic/plugin/skills/`, so any change lands in both
halves in the same commit and must pass `plugin-hooks-payload.Tests.ps1`.

---

### §26 — No plugin footprint is measured or published, so neither the maintainer nor a prospective installer can see the cost — ▶ **OWNER ACCEPTED 2026-09-03, spec written, SEQUENCED as Phase 6 (LAST), build DEFERRED**

> **Placement ruled 2026-09-03 (AGY-FIRST, `.clavity/seams/agyfirst-s28-30-sequencing.md`): Phase 6, last, ON ITS OWN.** It is the ONLY additive item in the sequence — every other phase repairs something already wrong — and a repair-ordered sequence finishes its repairs first. Deliberately NOT batched with §28/§30: it needs architectural design review that contained fixes do not, and grouping them merely because all three are "tooling" is the shallow similarity that dilutes a panel.

> ⚠ **This header read "build DEFERRED until §23 ships" for a few hours. §23 SHIPPED the same day
> (`13f8a09` · `4154800` · `45b612e` · `54eda7b`, closed at `8606391`), so the condition is MET and the
> deferral is spent.** Corrected in the same session it went stale, which is the whole of the earned
> rule: a deferral written against a condition rots the moment the condition fires, and nobody is
> watching for it.

**The owner's ask, verbatim:** *"a static footprint analyzer so 1) a test for the maintainer so it does
not ship bloated plugins 2) Merge the output of the static footprint analyzer to README docs so viewers
of the repo can see the usage cost before decide to install a plugin."*

**MEASURED 2026-09-03 at `b93fad1`, so the gap is not asserted from memory:**

- `clavity-dotnet/plugin/` on disk: `skills/` 134.327 B, `hooks/` 192.395 B, `knowledge/` 21.504 B.
- **Nothing computes an aggregate.** `grep -rlnE "TOTAL|aggregate|total bytes|footprint" scripts/*.ps1`
  returns only `discipline-reaching-report.ps1` and `release.ps1`, neither a size analyzer.
- **Neither README says anything about cost.** `grep -niE "KiB|KB|bytes|footprint|context cost|token"`
  over `README.md` and `clavity-dotnet/README.md` returns nothing.
- **Three per-artifact budget gates DO exist** and are not the gap: `check-growth-budget.ps1` (SEED +
  GROWTH ≤ 32.768 B, matching `GoldenHeader.MaxBytes` in both binaries), `check-seed-budget.ps1`,
  `check-cheatsheet-budget.ps1`. `check-injected-context.ps1` already performs SUBTRACTIVE discovery
  over the injected surface. **What is missing is aggregation and publication, not measurement of
  individual artifacts.**

🔴 **THE PEER'S BEST CONTRIBUTION, and it is load-bearing for the design: ON-DISK SIZE IS THE WRONG
NUMBER TO PUBLISH.** Publish "348 KB" as *usage cost* and a reader divides by four, concludes the plugin
permanently consumes half their context window, and closes the tab — a technically true number producing
a badly wrong decision. **And a naive analyzer over `plugin/` would not even see the real always-injected
payload:** `scripts/injected-context-ignore.txt:37-45` records that
`ghidrust/crates/ghidrust-mcp/src/tools.rs` holds 19 `pub const DESC_*` blocks, roughly 12 KB of
description text *"that MCP delivers to EVERY agent via tools/list"*, deliberately excluded from the
injected-context gate because auditing it for the ASCII invariant would red-gate correct content.
**Verified against that file, not taken on the peer's word.**

**Where the peer and I split, recorded because the owner ruled between us.** It concluded that a
maintainer gate and a README disclosure *"are fundamentally incompatible; pairing them is a mistake"*,
and recommended building the gate and publishing nothing. I disagreed on two measured grounds: it
conflates ONE ANALYZER with ONE NUMBER — a vector of fields lets each consumer read the field it needs —
and its cost objection (*"building and maintaining a custom Markdown parser for the README"*) is largely
already paid, because `check-roadmap-claims.ps1` parses claims out of markdown and validates them against
tracked files today. ⚠ Its own Q5 argued the disclosure case better than its recommendation did, and it
never reconciled the two.

## ✅ OWNER RULING, 2026-09-03 — all three forks

1. **A VECTOR, not one number.** The analyzer emits at least: always-injected bytes, per-skill
   on-invoke bytes, and on-disk bytes. The maintainer gate reads on-disk to block a committed blob; the
   README reads always-injected and per-invoke. **Discovery extends `check-injected-context.ps1`'s
   existing subtractive walk** rather than adding a second walk, so `tools.rs` is in scope by
   construction instead of invisible.
2. **The README block is GENERATED and GATED**, never hand-written. The analyzer writes between markers;
   a checker recomputes and fails on drift, exactly as `check-roadmap-claims.ps1` already does for
   `(N lines)` claims. Hand-editing becomes a red build rather than a silent lie.
3. **SEQUENCING: spec now, build after §23 ships.** §23 is planned and panel-GREEN; finishing it closes
   Phase 1.

**Two constraints neither model raised, recorded so the spec does not have to rediscover them.** This
repo hosts five products, so footprint is PER-PRODUCT and one repo-wide number would be meaningless. And
**byte→token conversion is a claim about someone else's tokenizer** — publish BYTES with the conversion
caveat stated; do not publish a token count.

**Spec:** `docs/superpowers/specs/2026-09-03-plugin-footprint-analyzer-design.md`.
**AGY-FIRST consult:** `.clavity/seams/agyfirst-footprint-analyzer.md`.

### §27 — A completion marker can advance with no ledger row, and nothing in the tree can detect it — ▶ **OWNER ACCEPTED 2026-09-03, spec written, SEQUENCED as its own Phase 2b, build DEFERRED**

> **Placement ruled 2026-09-03 (AGY-FIRST, `.clavity/seams/agyfirst-s27-phase2-fold.md`): §27 gets its
> OWN phase, after Phase 2 — not folded into it, and not Phase 3.** Not Phase 3 because this sequence
> draws phase boundaries by SUBJECT and says so at
> `2026-08-31-roadmap-implementation-sequence-design.md:401`; §27 edits a hook but defines what a valid
> completion contract IS. Not folded into Phase 2 because of review-lens dilution — one panel splitting
> attention between persona work and bash/git parsing is how a regex flaw slips through. The amendment,
> with the two rejected counter-arguments, is at that spec's new **Phase 2b**.

**The defect, stated as a measurement rather than a worry.** §23 shipped a ledger and a clause requiring
a row before an audit may COMPLETE. The clause is enforced by a linter that proves the clause SHIPS. It
proves nothing about whether a row is ever WRITTEN — and:

- **Nothing in the repository reads both `.clavity/agy-marks/agy-test-audit.head` and
  `docs/agy-test-audit-ledger.md`.** MEASURED 2026-09-03: exactly one file mentions the marker
  (`clavity-dotnet/plugin/hooks/agy-test-audit-reminder.sh`) and it never opens the ledger. The peer
  verified this independently, from the source, and reported the same.
- So a run that advances the marker and writes no row is **mechanically silent**: the reminder hook sees
  a marker describing HEAD, goes quiet, and the tree looks exactly as it does after a correct run.

🔴 **THAT IS WHY THE §23 PLAN'S OWN PROMOTION TRIGGER CANNOT FIRE.** It read: *"If a future audit is found
to have completed with no row, that is the evidence that promotes this from out-of-scope to necessary."*
The evidence it waits for is **unobservable by construction**. A trigger that can only be satisfied by
someone happening to notice is not a trigger.

## The AGY-FIRST consult, and how the peer's position moved

Recorded because the trajectory is the useful part, not the destination.

The peer rejected §23's frame **twice unprompted**, from two different disciplines — first proposing a
git hook keyed on a commit CREATING the marker (**refuted**: `git check-ignore -v` resolves that path to
`.gitignore:45`, so no commit ever creates it), then a hook intercepting the completing verdict and
inspecting the diff. Asked to argue it properly under AGY-FIRST, it **reversed and recommended accepting
the limitation** — while its own Q4, in the same reply, argued the opposite and better. One negotiation
turn, framed by sending it to the files rather than handing it a conclusion, and it withdrew its Q1 and
Q2: *"my claim that the missing row is 'highly visible' is entirely false and does NOT survive."*

**Both reads then converged on the same option.** ⚠ Discount that convergence appropriately: the driver
framed the questions that turned it, so two models agreeing here is weaker evidence than it looks.

**The peer's one contribution neither of us had: a naive gate breaks on every CORRECT run.** The ledgers
carry 7-character short SHAs and ranges (`73efca8..eba63a8`); `agy-mark.sh` is handed 40 characters. That
dictates HOW the gate must be written, not whether.

## ✅ OWNER RULING, 2026-09-03

**Gate the MARKER WRITE, at `clavity-dotnet/plugin/hooks/agy-mark.sh` — the `head)` branch, the single
chokepoint every discipline's completion marker passes through.** Not a new hook; code we already own.
**SPEC NOW, BUILD DEFERRED**, as for §26.

**What it will NOT prove, stated up front so the spec cannot ship a False Safety Promise:** it enforces
that a row EXISTS, never that an audit HAPPENED. A fabricated row passes. Its value is narrower and real
— it converts a sin of OMISSION (forgetting the step) into a sin of COMMISSION (deliberately writing a
decoy), and agents forget far more readily than they fabricate.

🔴 **A DESIGN FORK THE SPEC MUST RESOLVE, found while writing this entry: a `round-cap` waiver WRITES the
marker** (`agy-capstone/SKILL.md:461`), and it exists precisely for the case where the owner accepts
"done" with findings still live. A naive gate would block a legitimate owner waiver. Whatever is built
must let the waiver through without reopening the hole it closes.

**Spec:** `docs/superpowers/specs/2026-09-03-marker-write-gate-design.md`.
**AGY-FIRST consult:** `.clavity/seams/agyfirst-s23-behavioural-gate.md`.
**Blast radius:** `agy-mark.sh` is a shipped, byte-identical pair — class 2, so plan → panel → capstone
→ audit, the full loop.

### §28 — Four gate scripts repeat the 8.3 prefix-arithmetic shape that `41eef75` fixed once — ▶ **PROMOTED 2026-09-03, SEQUENCED as Phase 3b with §30, not yet planned**

**The shape.** Each script resolves a root with `Resolve-Path ... .Path`/`.ProviderPath`, which
**PRESERVES an 8.3 short path**, then computes a relative path by `Substring(<root>.Length)` against a
`Get-ChildItem` `FullName`, which **NORMALISES to the long form**. Long minus short is arithmetic on two
different strings, so `$rel` comes out mangled.

**Confirmed still present at triage, at every line the capture cited** (2026-09-03, after an earlier
narrower grep on `$root` MISSED them because these use `$repo`, `$RepoRoot` and `$prefix`):

| site | the line |
|---|---|
| `scripts/check-dangling-consumers.ps1:104,127` | root via `.ProviderPath`; `$f.FullName.Substring($repo.Length)` |
| `scripts/check-injected-context.ps1:20,186` | root via `Resolve-Path`; `$child.FullName.Substring($RepoRoot.Length + 1)` |
| `scripts/check-installer-ascii.ps1:29,54` | root via `Resolve-Path`; `$f.FullName.Substring($RepoRoot.Length)` |
| `scripts/check-knowledge-store.ps1:61,125` | root via `Resolve-Path`; `$_.Substring($prefix.Length)` |

**Reachability: all four accept a `-RepoRoot` parameter, so a short root is CALLER-reachable** — this is
not a theoretical Windows curiosity, it is an argument any caller can pass.

⚠ **The MECHANISM is proven (seat-b-probe control); PER-SITE reachability is UNVERIFIED.** A short-root
run of `check-installer-ascii` returned OK — but `$rel` is only printed on FAILURE, so that run could not
have shown the bug. **A plan must establish per-site reachability before claiming a fix, and must not
read that OK as evidence.**

**`41eef75` already fixed this shape once, elsewhere.** The fix is known; what is missing is applying it
to four more sites and pinning it so a fifth cannot appear.

---

### §29 — The 13b completeness check false-flags a valid reply, and its own remediation text says to discard the findings — ✅ **§29a SHIPPED 2026-09-03** (`573914d` the token · `b98315f` the bracket) — ▶ **§29b REMAINS TRACKED DEBT**

> ✅ **§29a CLOSED.** `DisciplineContract` maps `adversarial-panel-review` to `PANEL VERDICT`, and
> `TerminalToken` treats a leading `[` as decoration so a peer writing `[VERDICT: ALIGNED]` — the form
> three skills instruct — is no longer flagged as truncated. The other three tokens are stored WITHOUT
> the bracket, so the contract states what it enforces. Measured: `Clavity.Ls.Tests` 210/210 and
> `Clavity.Integration.Tests` 84/84, with both fixes proven non-vacuous by mutant.
>
> ⚠ **THE FIX IS NEUTRAL ON TRUNCATION SAFETY, NOT HARDENING.** `PANEL VERDICT` is negatable exactly as
> `GREEN` was (`"PANEL VERDICT is not…"` satisfies `StartsWith`), and the bracket is now optional. Both
> were measured and accepted; do not record either as a security improvement.
>
> 🔴 **NEW INVARIANT, mechanically enforced by `DisciplineContractTests`:** no stored token may BEGIN
> with a character `TerminalToken.Decoration` strips, or it becomes unsatisfiable. Whoever adds a fifth
> discipline will be stopped by that test rather than by a live false-flag.
>
> **The AGY-AFTER record: FIVE rounds, five blocking findings, four of them inside the previous round's
> own repair.** Plan and full disposition ledger:
> `docs/superpowers/plans/2026-09-03-s29a-panel-terminal-token.md`.

> **Placement ruled 2026-09-03 (AGY-FIRST, `.clavity/seams/agyfirst-s28-30-sequencing.md`).**
>
> **§29a — PREREQUISITE (Phase 0d), BOUNDED, and NARROWER than first written (see the correction below).** Phase 0's bar is *"everything after them
> depends on their being true"*, which alone would promote almost any bug. The narrower test Phase 0
> actually applies — and which 0b and 0c both fit — is that **the thing under repair is an INSTRUMENT OF
> VERIFICATION**: a broken instrument does not merely block later work, it corrupts the evidence later
> work produces. §29a covers ONLY the measured half — the `GREEN` literal at `DisciplineContract.cs:25`
> that makes every findings-bearing panel round fail by construction, and the driver-side echo-instruction
> wording that caused one false flag and is the driver's own fault.
>
> 🔴 **§29b — the flag whose cause is NOT DETERMINED — is explicitly OUT of the prerequisite and tracked
> here as debt.** The returned reply satisfies `IsSatisfied` as documented (`TerminalToken.cs:14-21`), so
> either the driver evaluates a different delta than it returns or the peer's escaping defeats the
> matcher; **that must be MEASURED before either side is changed.** An open-ended investigation must not
> gate the sequence — a prerequisite that is unbounded is how a prerequisite phase swallows a schedule.

**The defect.** `Clavity.Ls/DisciplineContract.cs:25` maps `adversarial-panel-review` to the literal
`GREEN`. A panel round that FINDS something cannot emit `GREEN` — the skill's own Outputs section names
"a list of the open findings" as a legitimate terminal disposition — so **every findings-bearing panel
round fails the check by construction.**

**The consequence is the serious half.** The flag's text reads *"Treat this consult as INCOMPLETE - do
not fold findings from it."* MEASURED 2026-09-03: the first reply it flagged carried a **CONFIRMED
BLOCKING defect** (`Test-Path` accepting a directory). Following the remediation would have discarded it.

🔴 **CORRECTED 2026-09-03, BEFORE ANY PLAN WAS WRITTEN — THIS ENTRY ORIGINALLY CLAIMED "at least two were
false" AND THAT WAS WRONG. Both were the DRIVER's errors, found by finally READING the two files instead
of assuming their semantics.** The scope of §29a is correspondingly narrower.

- **`TerminalToken.IsSatisfied` uses `StartsWith`, not `Contains`** (`TerminalToken.cs`), and deliberately:
  its own comment records that a substring test would accept *"Tests are not GREEN"*. The reply this entry
  called a false flag ended `[VERDICT: ALIGNED - ...] GREEN`, whose last non-blank line starts with `[`.
  **Flagging it was CORRECT.** The original entry asserted that reply "satisfies `IsSatisfied` as
  documented" — written without ever opening `IsSatisfied`.
- **The `EchoMissing` flag was correct too.** `SemanticEcho.Normalise` trims decoration (`` ` ``, `*`, `_`,
  `>`) **at the ENDS only**. The quoted source line carries an INTERNAL backtick, and the driver's brief
  told the peer to reproduce it "with no backticks" — so a faithful echo could not contain the needle.
  **The defect is the driver's INSTRUCTION, not the matcher.**

**So exactly ONE real defect survives, and it is the by-construction one:** `adversarial-panel-review`
expects `GREEN` as a `StartsWith` on the last non-blank line, and a findings-bearing round CANNOT emit
that — the panel skill names *"a list of the open findings"* as a legitimate terminal disposition. Such a
round is flagged every time, and the flag tells the driver to discard its findings.

---

### §30 — Three coverage gaps in the section-23 ledger suite, owner-deferred at audit — ▶ **PROMOTED 2026-09-03, SEQUENCED as Phase 3b with §28, not yet planned**

Raised and VERIFIED by AGY-TEST-AUDIT over `73efca8..eba63a8`; the owner scoped that run to gap 1 (folded
in `65b889a`) and deferred these three. Recorded here as tracked debt, which is where the audit
discipline sends a deferred gap.

**30a — the `-ForEach` roster nothing reconciles.** The ledger rejection rows hardcode a two-element
array mirroring the linter's `$ledgerFor` map. Add a third ledger-owning discipline and its guards are
never exercised while the suite stays green at 82/0. 🔴 **This is the SAME defect class the capstone
closed for the linter's own roster one day earlier — a hand-maintained list with no reconciliation —
reintroduced one layer up, in the tests.** Suggested test: parse `$ledgerFor`'s keys from the linter
source and assert the arrays cover every key.
`scripts/tests/check-agy-discipline-skills.Tests.ps1:87,144`.

**30b — short-circuit masking.** The suite perturbs exactly ONE skill per row, so it structurally cannot
see a rogue `break` replacing `Fail`'s `$script:fail = $true`: such a defect would halt the loop after the
first failing skill and every existing row would stay green, because each perturbs only one.
Suggested test: one row perturbing TWO skills, asserting BOTH diagnostics appear.
`scripts/check-agy-discipline-skills.ps1:76`.

**30c — needles assert only the message PREFIX**, so truncating an explanatory suffix passes silently and
the operator loses the explanation. ⚠ **Recorded WITH its counter-argument, because the fix may be worse
than the gap: pinning message suffixes is pinning prose verbatim, the anti-pattern this repo folded TWICE
in the section-21 capstone because every rewording becomes a false RED.** This one may resolve as
`DISCARDED-BELOW-FLOOR` rather than a fix.
`scripts/tests/check-agy-discipline-skills.Tests.ps1:103,177`.

### §31 — Two shipped SessionStart hooks misbehave in repositories that are not clavity — ▶ **PROMOTED 2026-09-03, SEQUENCED as Phase 3's FIRST item (owner-ruled), not yet planned**

Both found on 2026-09-03 while diagnosing an owner report, both REPRODUCED in a throwaway git repo, and
both are in the shipped plugin payload — so **class 2: byte-identical pair, and a reinstall before either
fix takes effect.**

**31a — `agy-anomaly-reminder.sh` renders as a HOOK ERROR on `compact`.** It emits via stderr + `exit 2`.
On `SessionStart source=startup` that renders as INJECTED CONTEXT; on `source=compact` the identical
exit 2 renders as a red **`SessionStart:compact hook error`**. A working reminder therefore reads to the
owner as a broken plugin.

- **REPRODUCED:** throwaway git repo + one untriaged entry in `.clavity/local-anomalies.md` + a
  compact-shaped payload -> `exit 2` and `[AGY-ANOMALIES] 1 untriaged ...`. **With NO anomalies file it
  exits 0**, which is why five earlier probes missed it — the hook only misbehaves when it has something
  to say, so a fixture without the trigger cannot see it.
- **ROOT CAUSE IS A STALE ASSUMPTION, not broken logic.** `:9-12` asserts *"exit 2 is non-blocking for
  SessionStart"*, and `:2` says the hook was written for `SessionStart(startup)`. The matcher LATER grew
  to `"startup|resume|clear|compact"` (`hooks.json:52`) and that claim was never re-checked against the
  new source. Same shape as a drifted line citation: true when written, invalidated elsewhere, nothing
  watching.
- **A WORKING PRECEDENT ALREADY SHIPS.** `agy-anomaly-capture-reminder.sh` emits `systemMessage` JSON on
  stdout with `exit 0` and renders cleanly — observed SUCCEEDING in the same PreCompact block that showed
  this error. The fix does not need inventing. ⚠ **But it must not regress 31a's original purpose**, which
  `:9-12` states plainly: at SessionStart there is no user turn, so stdout is absorbed into the model's
  context and **the OWNER never sees it** — and the owner is the one who triages. Any fix must still reach
  a human surface on `startup`.

**31b — `agy-discipline-reaching.sh` creates a `.clavity/` directory in EVERY repository it runs in.**
MEASURED per-hook in fresh throwaway repos: of the three clavity hooks on the `compact` matcher,
`agy-anomaly-reminder` and `agy-anomaly-model-notice` create nothing; `agy-discipline-reaching` creates
`.clavity/`. So installing the plugin in another profile silently adds an untracked directory to every
repo opened there, including repos with nothing to do with clavity — and the directory is only invisible
to git IF the shield write inside it succeeds.

🔴 **THE TWO COMPOUND, WHICH IS WHY THEY ARE ONE ITEM.** 31b is what puts a `.clavity/` into an unrelated
repository in the first place; once anything writes an anomaly there, 31a turns every `/compact` in that
repository into a red hook error. The owner met them in that order, in `aiplugins`.

**SEQUENCED 2026-09-03 — PHASE 3, AND IT RUNS FIRST WITHIN THAT PHASE.** Owner-ruled; recorded as
AMENDMENT 3 in `docs/superpowers/specs/2026-08-31-roadmap-implementation-sequence-design.md`. That
phase's own criterion (`:446-448`) is *"plugin hook pairs (`.sh`), mechanical, each with an
already-measured mechanism, and **none touches review-discipline semantics**"*, and both halves of §31
satisfy every clause by direct reading. **It leads the phase because it is the only backlog item causing
visible daily friction, not because it is the cheapest ordering.**

⚠ **IT SHARES A FILE WITH §22, AND THE OWNER ACCEPTED THE DOUBLE COST.** `agy-discipline-reaching.sh`
carries 3 of §22's leaking-redirect sites AND is 31b's fix target, so that file is edited, mirrored to
clavity-classic, and reinstalled TWICE. Merging the two into one pass was offered and declined.
🔴 **§22's plan must therefore re-derive its site line numbers against post-§31 code, never against the
paired-control table in §22 above.**

**The AGY-FIRST consult inverted under challenge** (`.clavity/seams/agyfirst-s31-sequencing.md`, then
`.clavity/seams/agyfirst-s31-negotiate.md`). The peer opened at NEGOTIATE — *"an active containment
breach"* warranting a hotfix outside the sequence — and withdrew both that severity and its own
counter-argument after one negotiation turn: `agy-discipline-reaching.sh:129-132` writes `*` into
`.clavity/.gitignore`, so the created directory never reaches the unrelated repository's `git status`.
**The harm is to the OWNER'S ATTENTION, not to any repository's integrity.**

### §32 — Two pathological-input defects in `agy-anomaly-reminder.sh`, deferred at the round-7 capstone cap — ▶ **PROMOTED 2026-09-04 from the anomalies conveyor, not yet planned**

Both were raised by the live peer in AGY-CAPSTONE round 7 on the SessionStart hook-emission fix, both are
REACHABLE rather than unreachable — which is why neither carries a `DISCARDED-BELOW-FLOOR` citation — and
both were deferred because **the owner ruled that capstone CAPPED at round 7 rather than take a further
source change.** Class 2: the hook ships in the plugin payload as a byte-identical pair, so either fix
lands in both halves in one commit and needs a reinstall before it takes effect.

**32a — a `cwd` that names a FILE defeats the `.no-agy` kill-switch on the DEGRADED (no-jq) path.**
`[ -d "$cwd_path" ]` at `clavity-dotnet/plugin/hooks/agy-anomaly-reminder.sh:53` gates the root walk. With
a file `cwd` the walk is skipped, `root` stays the file path, both kill-switch probes become
`<file>/.no-agy` and miss, and the degraded path — unlike the main path — has no anomalies-file check to
mask it, so it printfs unconditionally. **MEASURED 2026-09-04:** a repo with `.no-agy` at its root and
`cwd=<root>/afile.txt` with no jq on PATH emits the guard-inactive envelope; the same repo with
`cwd=<root>` is correctly silent. The main path is masked by `[ -f "$f" ] || exit 0`, so only the degraded
path bites. Low reachability — Claude Code sends a directory `cwd` — but **`.no-agy` is the user-facing
off switch, and this is it not switching off.** ⚠ The peer also corrected the driver here, who had
predicted the main path. Fix shape: resolve a non-directory `cwd` to its parent before the walk, or give
the degraded path the same anomalies-file guard.

**32b — an EMPTY `PATH` makes the hook write to stderr**, violating the no-stderr-on-any-path invariant
that `14101f5` established and that the suite's `Invoke-Hook` wrapper asserts on every call.
**MEASURED 2026-09-04:** `printf '{"cwd":".","source":"startup"}' | PATH='' bash <hook>` writes
`bash: command not found` to stderr. ⚠ **The peer's CLAIM was right and its stated MECHANISM was wrong** —
it predicted `cat: command not found` from `input=$(cat)` at `:33`; the observed error comes from bash
itself. Score claim and evidence separately. The suite cannot see this because the degraded-path fixtures
set `PATH` to a directory that still contains `cat`. **Genuinely pathological** — nothing invokes a hook
with an empty `PATH`, and in that state bash cannot find its own tools either — so note that a bare
`2>/dev/null` here would suppress the diagnostic saying the environment is broken, which is arguably worse
than the noise. Decide that trade at plan time rather than assuming the suppression is the fix.

---

### §33 — The terminal-token matcher and its contract lookup disagree on case, and nothing pins either — ▶ **PROMOTED 2026-09-04, tracked debt, sibling of §29b**

Two halves of one feature use different case semantics and only one of them is asserted.
**VERIFIED 2026-09-04 by reading both files:** `clavity-dotnet/src/Clavity.Ls/TerminalToken.cs:82` matches
with `StringComparison.Ordinal` (case-SENSITIVE), while the contract lookup beside it at
`clavity-dotnet/src/Clavity.Ls/DisciplineContract.cs:28` is built with `StringComparer.OrdinalIgnoreCase`.

**MEASURED 2026-09-04:** changing `Ordinal` to `OrdinalIgnoreCase` leaves `Clavity.Ls.Tests` **215/215
GREEN** — so nothing in the suite pins the case behaviour of the matcher at all.

Raised by the agy peer in the AGY-TEST-AUDIT of `84d36aa..902a6ef` and **discarded by the peer itself
below the severity floor**, on the reasoning that the mutation LOOSENS the gate (it would admit a
lowercase verdict line) rather than tightening it (it would not reject a valid one). That reasoning is
sound as far as it goes, and the owner scoped that audit to the other four gaps — but the gap is
**reachable, not unreachable**, so it is tracked here rather than stood down.

⚠ **The open question is which case semantics is intended, not merely that the assertion is missing.**
Case-sensitive matching on the token is defensible (a verdict token is uppercase by contract); an
ignore-case lookup for the discipline NAME is also defensible. Decide whether the mismatch is deliberate
before writing the test, or the test will simply pin whatever is there today. Fix shape if the current
behaviour is confirmed correct: one assertion in `TerminalTokenTests` that a lowercase `verdict: aligned`
does NOT satisfy `VERDICT:`.

---

### §34 — Nine hook test files allocate temp resources OUTSIDE the `try`, so a failed allocation leaks every earlier one — ▶ **PROMOTED 2026-09-04, tracked debt**

The shape is `$r = New-RepoWithAnomaly; $h = New-CleanHome` followed by
`try { ... } finally { Remove-Item $r,$h ... }`. Any allocation past the first that throws leaks the
earlier ones permanently, because the `finally` that would clean them is never entered.

Raised by the agy peer as AGY-CAPSTONE round 2 (State Corruptor, severity 1) and **deferred rather than
folded because it is a repo-wide test convention, not a defect that change introduced.** Patching one
file's sites would leave that file inconsistent with the ~92 sites elsewhere, for a consequence that is
one orphaned temp directory in the case where creating a temp directory has ALREADY failed — at which
point every test is failing anyway and `TEMP` is OS-swept.

⚠ **THE COUNT IN THE CAPTURED ENTRY IS ALREADY STALE, AND THAT IS EXPECTED** — it recorded 105 sites
across 9 files on 2026-09-04, but these suites grow (`agy-anomaly-reminder` alone went 29→33 tests in the
test-audit that same day). **The NINE FILES are confirmed still current** — `agy-liveness-check`,
`agy-anomaly-capture-reminder`, `agy-anomaly-reminder`, `agy-discipline-reaching`,
`agy-anomaly-dispatch-reminder`, `agy-anomaly-model-notice`, `agy-drive-session-reset`,
`agy-after-reminder`, `agy-anomaly-contract-stamp` — but **re-measure the site count at plan time rather
than quoting this line.**

Fix shape: initialise each handle to `$null` before the `try` and move the allocations inside it,
repo-wide in one pass so no file is left inconsistent with its siblings.

---

## Non-goals / accepted limitations

- **True mid-turn push to Claude Code** — none exists; long-poll `await-reply` / a bounded idle-wait is the
  pragmatic equivalent. Don't chase push.
- **Signed installers** — shipped unsigned (owner decision); SmartScreen warning documented.
- **Release-asset integrity** — companion `.sha256` + immutable pinned tag + GitHub/TLS trust; a fully compromised
  Release rewrites both (documented, accepted).
- **Same-user trust boundary** — `%USERPROFILE%`-scoped data; same-user TOCTOU accepted (cross-user/elevation
  mitigated). DPAPI/signing out of scope for this threat model.
- **Migrating classic → dotnet regresses `delegate_to_antigravity`** — dotnet provides `agy_ask` (consults), not
  autonomous code-delegation. Valid only while clavity-classic stays a maintained variant (which item 1 assumes).
_(The former "no continuous .NET CI on `main`" limitation is resolved and has been removed: it described the
pre-monorepo, branch-per-tool world. `.github/workflows/ci-dotnet.yml` now runs `dotnet build` + `dotnet test`
on every push to `main`, and packaging ships via the unified `umbrella-release.yml` + `build-dotnet.yml`.)_

---

## Shipped — history (original 2026-06-16 roadmap)

> Provenance: authored from a real driving session (Claude driving `agy` through clavity, 2026-06-16) — 6
> review/red-team round-trips. It defined **Theme 1 (first-class blocking round-trips)** and **Theme 2 (protocol &
> docs hygiene)**, both **COMPLETE 2026-06-17** on `ckir/clavity`: `ask` (+ `--review-only`/`--no-ring`),
> `await-reply` (resolved to thread-scoped Option D), `ping`, the `membus`/agentmemory daemon client, the
> hermetic fake-endpoint harness, the deprecation of pane-scraping, and the codified REVIEW-ONLY banner. That
> effort also produced the agy capability profile + capability-aware wording protocol + the re-runnable acceptance
> suite (`docs/agy-capabilities.md`, `docs/agy-remote-control-protocol.md`, `docs/agy-test-suite.md`). Everything
> in this section is shipped; it is kept for provenance only.

---

# ghidrust

> Reverse-engineering MCP server: attaches a persistent **headless Ghidra JVM** to an AI agent and exposes
> **19 tools** (14 read/nav + 5 durable writes) over MCP stdio. Pure-Rust single binary `ghidrust`.

## What ghidrust is now

> 🔴 **VERSION STAMP CORRECTED 2026-08-06** — this section is headed *"what ghidrust is **now**"* and was
> naming a binary version **two releases stale**. The two channels are versioned separately
> (`scripts/lib/release-lib.ps1:37-38`: *"`ghidrust` here always means its BINARY channel … the ghidrust
> plugin channel versions `ghidrust/plugin/**` only"*), and each is internally consistent:
> - **Binary channel — `1.2.0`.** All three member crates carry `version = "1.2.0"`
>   (`ghidrust/crates/{ghidrust-mcp,ghidra-ipc,ghidra-worker-ctl}/Cargo.toml:3`) and
>   `ghidrust/CHANGELOG.md` heads `## 1.2.0 — 2026-08-03`.
> - **Plugin channel — `1.0.0`** (`ghidrust/plugin/plugin.json:3`).
>
> ⚠️ `ghidrust/Cargo.toml` is a **workspace** manifest and carries no package version — looking there and
> finding none proves nothing.

**SHIPPED — binary v1.2.0 · plugin v1.0.0** (the text below describes the v1.0.0 capability set, which is
still accurate; only the stamp was stale). `ghidrust serve` attaches to a **pre-analyzed, GUI-closed** Ghidra project and drives
it: decompile/navigate (`inspect_function`, `get_disassembly`, `get_xrefs`, …) plus durable, CAS-guarded
writes saved to disk (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`). Delivered
two-channel: `ghidrust-setup-<VERSION>.exe` installs the binary→PATH; the plugin (skill + `.mcp.json`) ships
via the marketplace. Runtime prereqs: Ghidra 12.1.2 + JDK 21.

## ▶ Forward backlog (v1.1) · 🚫 **ALL THREE KILLED 2026-08-06 (out of scope: new features)**

> **last-triaged: 2026-08-06.** These are **new features**, which the open-work spec puts explicitly out of
> scope — that epic reconsiders and ranks *existing* open items, it does not admit new capability.
> Independently, all three fail **clause 1**: their absence causes no loss, crash or false diagnostic. It
> causes ghidrust to keep the documented "pre-analyze in the GUI" constraint it already ships with and
> documents honestly.
>
> ⚠️ **This is a KILL of the roadmap entries, not a judgement on the features.** ghidrust has no active
> development cycle in this repo; if one starts, these return as a v1.1 spec with their own evidence. Kept
> struck through rather than deleted — the capability sketches are the durable part.

- **`import_binary`** — create a project + import/analyze a binary (removes the "pre-analyze in the GUI"
  constraint) — the headline v1.1 feature.
- **Smart-server onboarding** — self-registering binary (`ghidrust register`), agent-driven lazy config (a
  `configure_ghidrust` MCP tool), and JIT MCP diagnostics (`ghidrust doctor` in the boot path turning bad
  config / open-GUI into actionable agent prompts). Requires new binary code (out of the v1.0 packaging).
- **Lazy-boot worker** re-architecture (paired with `import_binary`).
