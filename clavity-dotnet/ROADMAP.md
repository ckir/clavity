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

### 0. DISCIPLINE EFFICACY — stop confirming presence and calling it proof (▶ TOP PRIORITY, after the current build)

Numbered `0` deliberately: this list is priority-ordered, and renumbering 1-11 would invalidate every
existing citation to §7 and §8. Owner-directed 2026-08-04. **Deferred until the AGY-ANOMALIES capture-gap
build ships, because the instrumentation attaches to that code and must be written against it, not
against a description of it.**

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

**Three mechanisms, cheapest first. Sequence and scope are the open forks — AGY-FIRST before designing.**

1. **Version-stamp the emitted text.** A build identifier inside each message turns "it fired" into a
   string that can be checked, and makes a stale install distinguishable from a silent one. Smallest
   change; kills the ambiguity that made every past confirmation unfalsifiable. Open fork: where the
   stamp comes from, given the hooks are plain bash with no build step and the byte ban constrains the
   format.
2. **Have each discipline record its own firing** — an append-only count, so `nudges fired last 7 days`
   and `anomalies captured` are both answerable. `0 / 0` means it is not reaching; `12 / 0` means it
   fires and does not work. Today those two are indistinguishable, which is precisely why v15 looked
   fine. Open forks: where the counter lives (`.clavity/` is gitignored runtime state), and whether a
   hook that must fail open may ever write.
3. **Institutionalise the outside witness.** The agent two tabs away was the only valid experiment run on
   v15, and it happened by accident. The design is: a fresh session, in an unrelated repo, given ordinary
   work, never told the discipline exists — then inspect for the observable afterwards. **The session
   that builds a discipline may never be the session that confirms it.**

**The acceptance test for this item is itself an efficacy test**: it is done when you can answer "is
AGY-ANOMALIES working for real users?" from recorded evidence, without asking any agent what it thinks
happened.

### 1. `clavity --restart-agy` (classic) — 7.7
Agy-only restart: tear down + relaunch ONLY the agy psmux session under the same `--session`, WITHOUT co-launching
a new Claude (today only `clavity start` relaunches, which orphans the driving session). Re-run agy's exact launch
+ confirm readiness via a `ping`. Surfaced 2026-06-29 when an agy MCP hang forced a full teardown mid-session.

### 2. Golden-header tamper-detection — 7.4
Compare `golden-header.md` to its `.sha256` sidecar at read-time; LOUD plain-English warning on external change,
subtle active-marker otherwise. Honest threat model: the sidecar defends accidental corruption / naive hand-edits
only (same-user adversary rewrites both — the accepted same-user boundary). Staged after the injection MVP.

### 3. Dynamic send-model resolution (dotnet) — T10 follow-up
`AgyView` hard-codes the send model id (`MODEL_GEMINI_3_1_PRO_HIGH = 1037`); the enum ints are version-specific to
the running agy. Resolve dynamically (`GetAvailableModels` `default_agent_model_id`, or the conversation's own
model) so a model/version change can't break the live write. User-accepted as deferred (pre-1.0 scope; the paired
agy uses its default model).

### 4. Packaging verifications — 7.5 / 7.6
- **7.5** — confirm the dual-plugin format scopes `ls-driving` to Claude and `ls-pairing` to agy
  (else rely on contextual invocation + document).
- **7.6** — confirm Claude/agy don't auto-update a locally path-installed plugin away from the version-pinned
  `{app}` binary.

### 5. dotnet golden-header parity follow-ups
The classic 7.3 implementation (`src/golden_header.rs`) is now the canonical golden-header behavior; two dotnet
divergences were found during the Spec A capstone and are tracked as **dotnet-side code fixes** (they do not
affect the packaging `.iss`/CI contracts):
- **`GoldenHeader.Apply` trim charset** — dotnet uses full-Unicode `TrimEnd()`; classic (canonical) trims an
  **ASCII-only** whitespace set. Align dotnet to ASCII-only.
- **Sidecar write order/atomicity** — dotnet writes the `.sha256` sidecar **before** the target rename and
  non-atomically; classic writes it **after** the rename, atomically. Align dotnet to after-move/atomic.

### 6. agy-autotrain knowledge-delivery — driver-side effectiveness measure
The agy-knowledge-delivery design (`docs/superpowers/specs/2026-07-11-agy-knowledge-delivery-design.md`, panel-GREEN)
closes the driver-facing consume gap — it pushes a curated `[driver_guidance]` cheatsheet at drive-time. But it
**delivers** knowledge without **validating** that driving actually improved (delivery ≠ outcome; a ≤150-tok block is
a nudge, not enforcement). The peer side has a verify-harness (`agy-autotrain/verify/`); the driver side does not.
Add a **driver-side effectiveness measure** — a probe / verify-harness confirming a delivered rule demonstrably
changes driver behaviour on a known-failure scenario — so "delivers better driving" is substantiated, not assumed.
Shares the same empirical-measurement question as the golden-header per-ask backlog stub
(`docs/backlog/golden-header-per-ask-token-optimization.md`, the anti-drift trade-off). Owner-surfaced 2026-07-11.

### 7. AGY-SCOPE — "pre-existing defects are always in scope" as a shipped discipline (BRAINSTORM FIRST)
**Status: brainstorming task, not yet designed.** Owner-directed 2026-07-31; to ship, like its siblings, with the
clavity plugin (alongside `adversarial-panel-review` / `agy-test-audit`, mirrored to clavity-classic).

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

### 8. Audit spending — round count, capstone placement, model tiering (BRAINSTORM FIRST)
**Status: brainstorming task, not yet designed.** Owner-directed 2026-07-31.

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

### 9. Tracked debt — clavity-classic ME1 guard: binary-native vs bash hook

`docs/superpowers/specs/2026-07-22-ship-agy-disciplines-design.md:134` left this fork open "to resolve
in SP3, via AGY-FIRST". That spec was superseded by the ship-agy-workflow epic, which drops ME1 from
scope, so the fork was orphaned rather than decided. Owner ruling 2026-07-31: it does NOT gate the
productize release. It remains undecided and is recorded here so it stops being invisible.

### 10. Follow-on epic — productize the two later disciplines

`agy-test-audit` (shipped 2026-07-27) and the planned `AGY-SCOPE` postdate the ship-agy-workflow epic
and are not in its model. Owner ruling 2026-07-31: they are a follow-on, not a re-scope — retroactively
widening a stalled epic prevents it closing. This epic closes at four disciplines.

### 11. PINNING-ASSERTION-STRENGTH — ship assertion-strength as a mechanical discipline

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
  Step 5 (`:88-96`), widened to reach tests written during ordinary implementation. That paragraph already
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
4. `agy-test-audit-reminder.sh:10` states it **never** writes a marker, by design. A debounce marker is a
   different thing from an outcome marker, but the deviation needs a deliberate decision, not a silent one.

**Cost:** ~80 tokens per firing, ~2 firings per session; verification is one targeted test run per
directional or fallback assertion. Both variants' plugins must change together (byte-identical pair).

### Stretch (not planned)
- **NativeAOT** — ruled infeasible with the current gRPC/protobuf/MCP-reflection stack; revisit only if that stack
  changes.

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
**SHIPPED — v1.0.0.** `ghidrust serve` attaches to a **pre-analyzed, GUI-closed** Ghidra project and drives
it: decompile/navigate (`inspect_function`, `get_disassembly`, `get_xrefs`, …) plus durable, CAS-guarded
writes saved to disk (`rename`, `comment`, `set_datatype`, `set_prototype`, `set_local`). Delivered
two-channel: `ghidrust-setup-<VERSION>.exe` installs the binary→PATH; the plugin (skill + `.mcp.json`) ships
via the marketplace. Runtime prereqs: Ghidra 12.1.2 + JDK 21.

## ▶ Forward backlog (v1.1)
- **`import_binary`** — create a project + import/analyze a binary (removes the "pre-analyze in the GUI"
  constraint) — the headline v1.1 feature.
- **Smart-server onboarding** — self-registering binary (`ghidrust register`), agent-driven lazy config (a
  `configure_ghidrust` MCP tool), and JIT MCP diagnostics (`ghidrust doctor` in the boot path turning bad
  config / open-GUI into actionable agent prompts). Requires new binary code (out of the v1.0 packaging).
- **Lazy-boot worker** re-architecture (paired with `import_binary`).
