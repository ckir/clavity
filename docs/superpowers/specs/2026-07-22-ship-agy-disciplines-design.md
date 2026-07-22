# Ship the agy-driving disciplines + ME1 to users — Design

**Status:** Design approved (owner, 2026-07-22). Decomposes into sub-projects; each gets its own plan.
**Goal:** Productize the agy-driving disciplines and the ME1 consult-guard from the author's personal
`~/.claude` global config into the shipped clavity driver plugins, so any user who installs a driver
gets peer-driving *protection* and *discipline* out of the box — not just the author.

---

## Background: what already ships vs what doesn't

Four agy-driving disciplines exist. Two are already productized; two (plus ME1) are personal config.

| Discipline | What it does | Ships today? | Where |
|---|---|---|---|
| **AGY-AFTER** | adversarial multi-round review of a finished artifact | ✅ yes | `adversarial-panel-review` skill + `agy-after-reminder.sh`, duplicated in `clavity-dotnet` **and** `clavity-classic` |
| **AGY-LEARN** | capture→curate→golden-header knowledge loop | ✅ yes | `agy-autotrain` plugin (skills + hooks) |
| **AGY-FIRST** | consult agy on a design/scope fork before deciding | ❌ no | author's `~/.claude/CLAUDE.md` rule 1 + `agy-seam-inject.sh` |
| **AGY-CAPSTONE** | rounds-until-green agy review of committed code before "done" | ❌ no | author's `~/.claude/CLAUDE.md` rule 1c + `agy-seam-inject.sh` |
| **ME1** | read-only 7-axis git guard around each consult; warns if the peer wrote during a review-only ask | ❌ no | author's `~/.claude/hooks/agy-consult-guard-{lib,pre,post}.sh` |

The two driver products drive agy over **different transports**, and the shipped AGY-AFTER skill is already
**parameterized per transport** — this is the pattern to follow:
- **clavity-dotnet** → the **MCP `agy_ask` tool** (a `clavity-ls` server).
- **clavity-classic** → the **`clavity ask --review-only` CLI** (psmux).

---

## Decided product model (layered)

| Layer | Install | Contains |
|---|---|---|
| **Tier 1 — driver** (`clavity-classic` **or** `clavity-dotnet`) | required (pick one) | **ME1** (essential protection) · **panels/AGY-AFTER** (already there) · **AGY-FIRST** + **AGY-CAPSTONE** (new) |
| **Prerequisite** | **optional** | **superpowers** — needed ONLY for the optional auto-nudge hook (see Mechanism); the disciplines work without it |
| **Tier 2 — enhancer** (`agy-autotrain`) | optional | improves driving over time (the knowledge loop) |

Owner-settled; do NOT re-litigate *whether* to ship. AGY-FIRST/CAPSTONE go in Tier 1 (with the machinery
that drives agy). agy-autotrain stays the optional Tier-2 enhancer.

---

## Decision 1 — Packaging: Option A (per-plugin self-contained)

Each driver plugin ships its **own copies** of ME1 + the discipline skills/hook, parameterized per
transport — mirroring exactly how AGY-AFTER already ships (duplicated in both plugins, kept honest by a
sync-check). Rationale (agy-confirmed): in a plugin ecosystem, standalone-installability is the supreme
virtue; a shared "core" module (Option B) fights that architecture; splitting protection from methodology
(Option C) fragments a cohesive workflow. Duplication is a known, managed cost here.

**Rejected / out of scope:**
- **Option B (shared core)** — couples otherwise-standalone plugins.
- **Option C (split ME1 vs disciplines)** — contradicts the Tier-1 decision.
- **Option D (merge the two drivers into one transport-negotiating plugin)** — agy floated it to kill
  duplication; it reopens the deliberate two-product strategy (`clavity-dotnet` is the greenfield rebuild
  of `clavity-classic`) and is therefore OUT OF SCOPE. Noted only as a long-term consideration: if classic
  is ever retired, the duplication cost disappears on its own.

---

## Decision 2 — Mechanism: Hybrid (opt-in skills + optional auto-nudge)

The disciplines ship as **first-class, opt-in clavity skills** (e.g. `agy-design-consult` for AGY-FIRST,
`agy-capstone` for AGY-CAPSTONE) **plus** an **optional auto-nudge hook** that fires them at the right
workflow moments for users who also run superpowers.

Rationale (agy-challenged the original "stealth-hook + hard superpowers prerequisite" idea, owner accepted
the hybrid):
- **Robustness:** own-skills don't depend on superpowers' *internal skill names*; if superpowers is absent
  or renamed, the disciplines still exist and work. The old stealth-hook would *silently orphan* (the user
  believes AGY-CAPSTONE is firing; it never does).
- **Non-intrusive default:** forcing an agy-consult nudge on *every* `brainstorming` session is too
  opinionated for a stranger who is just prototyping — a fast route to uninstall. Opt-in is the safe default.
- **Preserves auto-fire for power users:** the optional hook (only active when superpowers is present)
  gives the author-style auto-fire without imposing it.

**Intrusiveness nuance (from agy risk (e)):** AGY-FIRST intercepts the *creative* phase → default **opt-in
only** (auto-nudge off by default, or gated behind a config flag). AGY-CAPSTONE is a *completion gate*, not
a creative-phase intrusion → its auto-nudge is safer to enable by default. Final per-discipline default set
in the SP4 plan.

**Safety rails for the shipped disciplines (panel R2 — required in SP4):**
- **Hard round cap on AGY-CAPSTONE (F8).** "Rounds-until-green" with no ceiling is an infinite-loop risk:
  the peer can re-assert a confabulated/unfixable "defect" every round with identical confidence, so GREEN
  becomes unreachable and the loop drains the user's token quota. The shipped AGY-CAPSTONE MUST carry a hard
  `MAX_ROUNDS` ceiling + a human override at the cap (exactly the `adversarial-panel-review` round-3 halt-
  and-ask precedent) — never an unbounded auto-loop on a stranger's budget.
- **Debounced auto-nudge (F9).** The auto-nudge is a REMINDER (injected context, like `agy-after-reminder`),
  NOT an auto-executed consult — so it does not fan out peer executions. But firing it on every raw
  `Write|Edit` save is still noise; SP4 must debounce it / bind it to a phase-transition, not raw saves, and
  the docs must make explicit that the nudge never auto-runs a consult (the human decides to invoke it).

**Superpowers dependency direction:** the discipline SKILLS are always superpowers-independent (a user
invokes them directly) — that is the load-bearing guarantee, and it holds unconditionally. The **optional
auto-nudge** is subtler (two panel findings corrected an earlier over-optimistic claim here):
- Hooking a `docs/superpowers/` PATH (the `agy-after-reminder.sh` precedent) does NOT couple to superpowers'
  skill *names*, but it IS coupled to superpowers in *practice* — without superpowers, nobody writes to
  those paths, so the trigger never fires. The path is not a superpowers-free signal.
- A raw `git commit` trigger for AGY-CAPSTONE would SPAM every intermediate WIP commit, violating its
  "completion gate" intent — there is no clean discrete "finishing" signal in the shell.
- **Resolution (SP4 decides the final form):** since the auto-nudge is *optional* anyway, it MAY couple to a
  superpowers workflow signal when superpowers is present (degrading to "no auto-nudge" when absent — the
  skills still work); OR both AGY-FIRST and AGY-CAPSTONE ship as pure OPT-IN skills with no auto-nudge at
  all. Either way superpowers is NOT required for the shipped disciplines to function — only, at most, for
  the convenience of auto-firing. AGY-FIRST is opt-in regardless (auto-nudging every design phase is too
  intrusive, per risk (e)).

---

## Decision 3 — ME1 productization + hardening (ship-gates)

ME1 protects the review-only consult path and is **essential** in Tier 1. It is NOT ship-ready yet. Before
it goes onto a stranger's machine, ALL of these must hold:

1. **Green capstone.** ME1's capstone was WAIVED at round 2 (not green). SP1 resumes it from the already-
   staged brief `.clavity/seams/me1-capstone-r3.md`, rounds-until-green. **COI caveat (panel finding):**
   agy judges its own leash here, so a HUMAN must adjudicate ME1's capstone GREEN — do not defer to agy's
   verdict on whether ME1's own constraints are warranted.
1a. **No unguaranteed runtime deps (panel finding — the jq ship-gate).** ME1's hooks currently require
   `jq`; "jq accepted" (R1-#4) was justified only because the AUTHOR guarantees jq on PATH (portable
   toolchain). On a stranger's machine jq/sha256sum may be absent → the guard SILENTLY no-ops = false
   confidence, the worst failure for a security tool. Shipped ME1 must either bundle/detect its deps or
   fail LOUD (announce "guard inactive: missing <dep>") when a dep is absent — never silently.
2. **False-positive calibration for unknown repos** (agy's "death knell" risk, correctly generalized —
   note his specific R1/R2 examples were already fixed this session, 17/17). A security tool that trips on a
   stranger's legitimate workflow gets disabled forever. SP1 must define the default detection-bias for an
   unknown repo (quieter default? a documented dial?) and the async best-effort's user-facing behavior.
3. **Global → per-plugin hook.** Convert `~/.claude/hooks/agy-consult-guard-*.sh` into plugin-owned hooks
   (like `agy-after-reminder.sh`), registered via each plugin's `hooks.json` using `${CLAUDE_PLUGIN_ROOT}`.
4. **Per-transport variant.** dotnet's ME1 watches the MCP `agy_ask` tool; classic's watches the
   `clavity ask` CLI (see Open Fork below).
5. **Docs + productized test suite.** Port the 17-case smoke suite into repo-runnable tests; document what
   the guard does, its messages, and its async best-effort limitation.

### Open fork (resolve in SP3, via AGY-FIRST): classic ME1 — binary-native vs bash hook
For `clavity-classic`, ME1 could live **inside the `clavity` CLI binary** (it owns the consult command, so
it can bracket execution natively — no fragile state files / TTL / races) instead of a bash hook. agy's
caution: two implementations (Rust binary for classic + bash hook for dotnet) = two security surfaces that
drift. Provisional lean: **start with the bash hook for both** (parity, faster to ship), and treat the
classic binary-native guard as a follow-up that connects to the existing "wrapper-side async guard" roadmap
item. The MCP path (dotnet) **must** stay a hook regardless (Claude talks to the language server directly).

---

## Sub-project decomposition (this is an epic; each SP gets its own plan)

- **SP1 — ME1 hardening.** Green capstone (resume R3) + false-positive calibration for unknown repos +
  an explicit **threat model for a stranger's machine.** The threat model MUST state plainly whether ME1
  defends against a SLOPPY peer or an ADVERSARIAL one, because that changes the design: an adversarial peer
  with filesystem write can **tamper with ME1's own baseline state file** (world-writable in `TMPDIR`) to
  forge a clean comparison (panel R2-S2) — a sloppy-peer guard need not defend that, an adversarial one
  must. Also decide the **subagent-concurrency** keying (panel R2-S1): subagents drive agy too; if a
  subagent shares the parent's `session_id`, its consult races the parent's on the same state slots — the
  key must isolate concurrent consult flows, not just sessions. **And even a single flow can multiplex
  overlapping async consults (panel F6)** — so the state key must bind to a per-consult unique id
  (the payload's `req_id`), not merely the flow/session. **Stated limitation (panel F7):** ME1's 7 axes are
  all LOCAL git state, so it CANNOT catch a peer that mutates → `git push` (exfiltrates upstream) →
  `git reset --hard` + reflog-expire before yielding — the local before/after matches, a false-GREEN. A
  local-snapshot guard structurally cannot defend network exfiltration; the threat model must state this as
  an explicit non-goal (and, if adversarial-peer defense is in scope, a separate control — e.g. a
  `git push` PreToolUse block during a consult — is required, not ME1).
  **SCOPE DECISION that bounds this (the convergence point of the panel): ME1 defends the SLOPPY peer, not
  the ADVERSARIAL one.** The empirical failure mode is a peer that *executes despite* a review-only banner
  and writes obvious artifacts (once committed 4×) — carelessness, not evasion. A local, read-only git guard
  STRUCTURALLY CANNOT stop a determined adversary: the evasion set is unbounded (network exfil via
  push-then-reset [F7]; hiding a payload in an already-`.gitignore`d path [F14]; relying on the LLM to drop
  ME1's relayed warning [F13]; timing; `.git` internals). SP1 must state plainly that **COMPLETE
  adversarial defense is an explicit NON-GOAL** — ME1 makes NO guarantee against a determined adversary; it
  is not a sandbox, and real adversarial containment needs DIFFERENT non-ME1 controls out of scope for this
  epic. Precise wording (panel F17, resolving the DiD paradox): "out of scope" means "no guarantee / not
  complete", NOT "ME1 must not look" — cheaply surfacing some adversarial TELLS locally is a permitted,
  non-promised BONUS, not a scope violation. This bounded scope is what stops the adversarial-evasion
  findings from multiplying without end: ME1 promises nothing there, so each new evasion is already covered.
  **Keying correction (panel F12, scoped by F15):** for the SYNCHRONOUS path the per-consult key is the
  hook's own `tool_use_id` (present in BOTH the Pre and Post payloads of the one blocking invocation) — NOT a
  backend `req_id` (unknowable pre-exec, unparseable from an arbitrary shell signature). BUT `tool_use_id`
  does NOT work for the ASYNC path: `clavity send` and `clavity await-reply` are SEPARATE tool invocations
  with DIFFERENT `tool_use_id`s, so the reply cannot correlate back to the dispatch baseline. Cross-
  invocation async correlation is a genuine hook-layer limitation. **Definitive resolution of the keying
  death-triangle (panel F18 — F6 vs F12 vs F15):** the async path has NO reliable hook-layer key — `session_id`
  clobbers on multiplex (F6), `req_id` is unavailable pre-exec (F12), `tool_use_id` can't span the two
  invocations (F15). **Definitive (panel F20):** a paired before/after guard with NO key is not
  "best-effort" — it is BROKEN (a reply would diff against whatever orphaned `.async` baseline happens to be
  present → random, corrupt evaluations). So the SHIPPED ME1 hook does NOT guard the async path at all: it is
  **SYNC-ONLY** (`agy_ask` MCP + `clavity ask`, keyed by `tool_use_id` — precise). The async `send`/`await-
  reply` path is owned ENTIRELY by the `clavity` wrapper (which holds the thread/req id natively); the shipped
  hook simply ignores async rather than pretending to guard it. (The author's personal ME1 keeps its
  experimental async slots; the SHIPPED build drops them.)
  **Scope-vs-machinery reconciliation (panel F16 — the sharpest catch).** ME1's 7-axis quad was built during
  ME1's OWN capstone to catch ADVERSARIAL vectors (stash-smuggle, `.git/hooks` trojan, assume-unchanged
  flags, rogue refs). But the scope decision above says ME1 guards the SLOPPY peer only — and a careless peer
  trips `status`/`diff`/`HEAD` (stray files, an accidental commit), not `stash`/`gitmeta`/`flags`/`refs`
  (those are adversarial moves, now out-of-goal). **Definitive (panel F21): the SHIPPED ME1 TRIMS to the
  sloppy-core axes `status`/`diff`/`HEAD`** and DROPS `stash`/`gitmeta`/`flags`/`refs`. Reason: those four
  monitor internal git state a legitimate human may touch mid-consult (stash WIP, edit `.git/config` while
  waiting out consult latency), so keeping them would manufacture exactly the false-positive death-knell the
  FP-calibration ship-gate outlaws — and against the SLOPPY scope they add no in-goal coverage (a careless
  peer trips `status`/`diff`/`HEAD`). This supersedes the earlier "bonus tells" option (F17): the shipped
  build simply does not carry them. (The author's personal ME1 keeps the full 7-axis for their own max-
  coverage use; the SHIPPED build is the lean, low-FP sloppy-guard.)
  Precondition for shipping ME1 anywhere. Gates SP2/SP3.
- **SP2 — ME1 → clavity-dotnet.** Per-plugin MCP-transport hook + `hooks.json` + docs + ported tests.
  **Rename-brittleness (panel R3-S1):** the matcher hardcodes the fully-qualified MCP tool name
  `mcp__plugin_clavity-dotnet_clavity-ls__agy_ask` (classic regexes the `clavity ask` verb); a plugin-id /
  tool / CLI-verb rename silently blinds the guard. Pin these identifiers to a single documented constant
  with a fail-loud self-test (assert the watched tool actually exists at install/SessionStart).
  **Liveness (panel R3-S2):** ship a positive "ME1 active" signal (a one-time SessionStart line) so a silent
  guard reads as "active + clean", never ambiguously as "not running / broken".
  **Warning-delivery is SEPARATE from liveness (panel F19).** Liveness answers "is it on"; it does NOT
  guarantee a later trip-warning reaches the human, since a `PostToolUse` warning is relayed through the LLM
  and can be silently summarized away. So each ME1 TRIP must ALSO be written to an out-of-band, user-checkable
  record (an append-only log file the user can `tail`), not relayed solely as `additionalContext`. (ME1 stays
  read-only — it does NOT block; the out-of-band record is the guaranteed-visibility channel, not a halt.)
- **SP3 — ME1 → clavity-classic.** Resolve the binary-native-vs-hook fork (AGY-FIRST), then implement.
- **SP4 — AGY-FIRST + AGY-CAPSTONE skills.** First-class opt-in skills per driver plugin + the optional
  auto-nudge hook; per-discipline default intrusiveness (FIRST opt-in, CAPSTONE auto-nudge-able).
- **SP5 — superpowers-optional + docs.** Absent-superpowers degradation (skip the auto-nudge, announce
  once); prerequisite/optionality communicated in each plugin's README + install docs.
- **SP6 — anti-drift.** Extend the existing seed/artifact sync-check to cover the new duplicated ME1 +
  discipline artifacts across the two plugins. (Correcting agy's misread: the sync-check is a CI/dev-time
  check on the repo's shipped artifacts — it does NOT run on user machines or overwrite user-local edits.)

**Suggested order:** SP1 → (SP2 ∥ SP4 ∥ SP5) → SP3 → SP6. SP1 gates the ME1 SPs; SP4/SP5 are independent of ME1.

**"Essential" vs shippable timing (panel finding).** ME1 is "essential" to the *finished* Tier-1 promise, but
SP4/SP5 (disciplines) can land first without it. Resolution: a driver release may ship the disciplines
before ME1 is green, but it must NOT advertise consult-guard protection until SP1 is green + SP2/SP3 land.
"Essential" = required before we CLAIM the protection, not a hard blocker on every intermediate release.

---

## Non-goals / explicitly deferred
- Merging the two driver plugins (Option D).
- Re-implementing AGY-AFTER or AGY-LEARN (already shipped).
- The airtight async consult guard (a separate wrapper-side roadmap item; ME1 ships with documented
  best-effort async + favor-detection bias).

## Testing posture
Per-plugin. Reuse the AGY-AFTER shipping pattern (duplicated artifact + sync-check). ME1's 17-case smoke
suite becomes repo-runnable and gates each ME1 SP. Discipline skills get activation/trigger tests
(does the skill exist, does the optional hook fire only when superpowers is present).

## Gaps flagged for the plans (not the spec)
- SP1: the exact false-positive-bias default + whether it's a config dial — decided in the SP1 plan.
- SP3: binary-native-vs-hook — decided in the SP3 plan after an AGY-FIRST consult.
- SP4: the per-discipline auto-nudge default set + the skill names/arg surface — decided in the SP4 plan.
- SP5: the exact superpowers-absent UX (SessionStart message wording, config flag names) — SP5 plan.
- SP2/SP3: **both drivers installed at once** (a user mid-migration from classic → dotnet). Each ME1
  variant matches a different transport (MCP `agy_ask` vs `clavity ask` CLI), so a single consult is
  guarded once — BUT both hooks also see plain `Bash`, so confirm the classic CLI-detection can't also
  fire on the dotnet user's shells and vice-versa (no duplicate warnings). **And (panel finding F5):** the
  two variants MUST NOT share ME1's hardcoded `${TMPDIR}/claude-agy-consult-guard` state dir + `session_id`
  keying — a concurrent dotnet `agy_ask` (sync) and classic `clavity send` (async) would race on the same
  `.sync`/`.async` slots and corrupt the baseline (false-green). Namespace the state dir/files per variant.
  Decide in the ME1 SP plans.
