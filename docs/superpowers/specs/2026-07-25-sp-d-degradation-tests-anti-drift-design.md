# SP-D -- Degradation, dependency guards, tests + anti-drift -- Design

**Status:** Design (brainstormed 2026-07-25; AGY-FIRST + AGY-NEGOTIATE consulted, detection fork converged
`[VERDICT: ALIGNED]`). The **final** subproject of the ship-agy-workflow epic
(`docs/superpowers/specs/2026-07-24-ship-agy-workflow-design.md`). Gated on SP-0/SP-A/SP-B/SP-C -- all
complete + capstone-GREEN on local `main` (owner owns the push/merge).

**Goal:** Close out the epic that productizes the owner's four-part peer-driving workflow (AGY-FIRST /
AGY-NEGOTIATE / AGY-AFTER / AGY-CAPSTONE). SP-A/B/C shipped the disciplines + the auto-fire hook; SP-D ships
the remaining **Decision-3** guarantees -- the shipped disciplines must **never silently die** -- plus the
comprehensive hook-activation tests, the anti-drift enrollment, the prerequisite docs, and one folded-in
leftover (the SP-0 namespace-gate regression test). Then **ONE combined release** closes the epic.

**Architecture:** Best-effort, in-flow prompt-discipline (per the epic's Posture -- NOT a code-enforced
sandbox). SP-D adds a per-plugin SessionStart liveness hook + hardens the two existing bash hooks against a
missing runtime dep, all shipped byte-identical across both driver plugins and kept honest by the seed-sync
gate. No new agy transport, no headless shell-out.

**Tech stack:** Bash hooks (`*.sh`, LF-pinned by `.gitattributes:12`), per-plugin `hooks.json` manifests,
`jq` for JSON I/O, Pester (`scripts/tests/*.Tests.ps1`, run via `just test-scripts`), the `bash` seed-sync
gate (`scripts/check-seed-artifacts-synced.sh`, `just seed-sync-check`).

---

## Context -- what is already done (measured, not assumed)

| Subproject | Status | Evidence |
|---|---|---|
| SP-0 (plugin identity -> `clavity`) | complete + capstone-GREEN | Spike-B = clean replacement (Task 6.3 skipped); index "SP-0 IMPLEMENTATION COMPLETE" |
| SP-A (agy-first + AGY-NEGOTIATE) | complete + capstone | all Decision-2 tokens/caps/impasse + the `skipped.log` durable record shipped (`agy-first/SKILL.md`) |
| SP-B (agy-capstone) | complete + capstone | round-cap + human-adjudicated GREEN + override re-entry + `skipped.log` shipped (`agy-capstone/SKILL.md`) |
| SP-C (auto-fire hook) | complete + capstone-GREEN | `agy-seam-inject.sh` byte-identical both plugins + `PreToolUse(Skill)` registration + seed-sync + Pester smoke |
| **Decision 3 (degradation/deps/tests/anti-drift)** | **NOT shipped** | **= this subproject** |

The ONLY unshipped epic Decision is Decision 3. Everything else is done pending the owner's push.

---

## Scope -- 6 items

1. **SessionStart liveness/degradation notice** (Decision 3.2 + the `.no-agy`-announce of Decision 1).
2. **Runtime-dependency guards** -- retrofit the jq-guard onto `agy-after-reminder.sh`; state the honest
   bash-missing limit (Decision 3.4).
3. **Comprehensive hook-activation test category** (Decision-3 testing posture).
4. **Anti-drift enrollment** of any new shared artifact into `check-seed-artifacts-synced.sh` (Decision 4).
5. **Docs** -- superpowers-prerequisite messaging + the accepted best-effort limits.
6. **SP-0 namespace-gate regression test** (owner-folded leftover -- locks the gate's gitignored-artifact +
   self-match behavior).

**Explicitly out of scope:** the per-skill-ID probe of epic Decision 3.3 (see D1); ME1 / the consult-guard
and AGY-LEARN / the knowledge loop (epic-excluded); the owner's push/merge; product-roadmap features
(nothing foldable -- all four ROADMAPs + the ranked backlog were harvested).

---

## D1 -- Degradation detection: targeted registry presence-check (AGY-NEGOTIATE -- ALIGNED)

**The fork and its resolution.** Epic Decision 3.3 called for a SessionStart probe verifying the *specific
hooked superpowers skill IDs* still exist. Both agy (formal challenge) and the driver judged that unsafe: a
fragile per-skill-ID probe of an opaque plugin **will eventually false-positive and tell a healthy user
their setup is broken** -- the worst outcome. Decision 3.3's own robustness caveat already licensed
"a presence check + a documented manual line rather than a fragile ID probe." **Resolution (binding, agy
`[VERDICT: ALIGNED]` after one negotiation round): drop the per-skill-ID probe; use a targeted, registry-
authoritative presence check.**

**Contract.**
- **Detection reads the ENABLED-plugins map, not the installed list (panel F1, measured).**
  `installed_plugins.json` lists installed-but-**disabled** plugins too (measured: `frontend-design` is present
  there yet disabled), so keying on it would **false-GREEN on an installed-but-disabled superpowers** (entry
  present -> we stay silent -> but auto-fire is dead). The authoritative "will superpowers actually load and
  auto-fire" signal is the **`enabledPlugins`** map, where an enabled plugin is `"<name>@<marketplace>": true`
  and a disabled one is `: false` (both measured).
- **The enabled-check honors Claude Code's SETTINGS HIERARCHY, not just the global file (panel F8, measured).**
  `enabledPlugins` is a project-scopable key: measured, this repo's `.claude/settings.local.json` enables
  `csharp-lsp` at **project-local scope only** (which is why `claude plugin list` reports it `scope: local`).
  A global-only read would false-positive (globally disabled, locally enabled) or silent-drop (globally
  enabled, locally disabled). The hook therefore resolves `enabledPlugins` across the hierarchy, more-specific
  scope winning per plugin key: **project-local (`$CLAUDE_PROJECT_DIR/.claude/settings.local.json`) > project
  (`$CLAUDE_PROJECT_DIR/.claude/settings.json`) > user (`<config-dir>/settings.json`,** where `<config-dir>` =
  `$CLAUDE_CONFIG_DIR` if set else `~/.claude` -- exact env-var names re-verified in the plan**)**. superpowers
  is live only when the merged map has a key matching **`^superpowers@` resolving to `true`** -- a **prefix
  match, NOT the exact `superpowers@superpowers-marketplace` key** (panel F2: the marketplace suffix is not
  guaranteed).
- **A MISSING settings file at a scope is NORMAL, not a not-live signal (panel F9).** Most projects have no
  `settings.local.json` (and many none of the three); the hook reads **only files that exist** and MUST NOT
  let a missing optional file error the merge -- `jq -s '.[0]*.[1]...'` over a non-existent path crashes and
  outputs nothing (measured: `jq: error: Could not open file ... exit 2`), which would misfire the advisory on
  ~99% of healthy installs. Build the merge from existing paths only. Only a genuine absence of an enabling
  `^superpowers@` key across all PRESENT scopes, a `false` at the winning scope, or an unreadable/corrupt
  PRESENT file -> not-live -> the advisory (fail-toward-loud).
- **Present -> silent.** No banner on a healthy install (honors Decision 3.2's "notice **when missing**"
  intent; an every-session banner trains the user to ignore the one moment it must land).
- **Absent -> loud, but phrased as a POSSIBILITY, never a certainty.** Emit a single `[AGY-DISCIPLINES]` line
  along the lines of: *"superpowers not detected -- the agy disciplines won't auto-fire; install superpowers,
  or invoke `agy-first` / `agy-capstone` manually."* It MUST NOT assert "disabled" as fact.
- **Sideload edge-case (agy-surfaced, folded).** A dev who clones superpowers straight into
  `~/.claude/plugins/` without `claude plugin install` leaves no registry entry though the plugin is live.
  The possibility-framed wording degrades gracefully there (a soft advisory, not a false "broken"), so no
  extra detection is warranted.

**`.no-agy` announce (Decision 1, panel R2-S4).** `.no-agy` (cwd or `~/.claude`) suppresses all auto-fire,
but a forgotten **global** `~/.claude/.no-agy` would silently kill the disciplines for every project. The
SessionStart hook MUST announce when `.no-agy` is suppressing them, naming the path:
*"[AGY-DISCIPLINES] suppressed by .no-agy at &lt;path&gt;."* (Loud, not silent -- the whole point of Decision 3.)
- **On `.no-agy`, ANNOUNCE the suppression then exit -- a LOUD early exit, not a SILENT one, and NOT a
  fall-through (consuming-agent expertise + panel delta-review).** Two opposite mistakes to avoid: (a) the
  sibling hooks (`agy-seam-inject.sh`, `agy-after-reminder.sh`, `agy-drive-session-reset.sh`) do
  `[ -f .no-agy ] && exit 0` early and **silently** -- copying that verbatim reintroduces the silent-kill
  Decision 3 forbids, so this hook must NOT silently early-exit on `.no-agy`; (b) but `.no-agy` means
  auto-fire is definitively off, so the hook must NOT fall through to ALSO emit the jq-missing +
  superpowers-missing notices -- that would triple-spam a single boot (panel delta finding). **Correct
  behavior:** when `.no-agy` is present, emit the single `.no-agy` suppression announce (stderr + `exit 2`,
  per D2) and stop; otherwise (no `.no-agy`) run the superpowers / jq checks. It still fails open (`exit 0`,
  silent) on a genuine internal error.

---

## D2 -- Where the SessionStart notice lives + its anti-drift shape

- **A new per-plugin bash hook**, shipped **byte-identical** in both driver plugins (mirroring
  `agy-after-reminder.sh` / `agy-seam-inject.sh`), registered in each `plugin/hooks/hooks.json` under a
  `SessionStart` block, `matcher: "startup"`. **Exit-code contract (delta-review finding C -- resolve the
  exit-2-vs-fail-open tension; a DETECTION FAILURE is NOT a fail-open error):** three outcomes --
  (1) healthy / nothing to say -> `exit 0`, no stderr; (2) a DETECTION OUTCOME warranting a notice --
  superpowers not-live (absent OR **corrupt/unreadable settings**), `.no-agy` active, or `jq` missing ->
  write the line to stderr + `exit 2` (a corrupt `settings.json` resolves to the not-live ADVISORY, per D1,
  **not** to fail-open); (3) a genuine UNEXPECTED internal error OUTSIDE the detection logic -> `exit 0`,
  silent (fail-open, never blocks). **Do NOT use a blanket `trap 'exit 0' ERR`** -- it would swallow the
  settings-parse path and silently drop the advisory (the silent-drop Decision 3 forbids). Handle the settings
  read explicitly (a `jq`/read failure IS a not-live detection outcome -> exit 2) and reserve fail-open
  `exit 0` for the truly unexpected.
- **SessionStart provides `.cwd` and `.source` on stdin (panel F6, measured):** the existing classic
  `agy-drive-session-reset.sh` already reads both and checks `${cwd}/.no-agy` + `${HOME}/.claude/.no-agy`, so
  the `.no-agy` announce (which needs cwd) is feasible and has a working precedent to mirror.
- **Emission mechanism = stderr + `exit 2` (CORRECTED via the delta-review + the authoritative Claude Code
  hooks docs; my earlier `additionalContext` choice was WRONG for this event).** A SessionStart hook's
  `additionalContext` **and** plain stdout are injected into Claude's CONTEXT ONLY -- NOT shown to the user
  (hooks-guide.md:554: for SessionStart "anything you write to stdout is added to Claude's context").
  At boot there is no user turn, so the model does not proactively speak that context = the notice would be
  **silently absorbed** -- the exact silent-drop Decision 3 forbids (raised by agy's delta-review, then
  confirmed against the docs by the consuming agent; agy was NOT trusted as the oracle -- the CC docs were).
  The **only** documented user-visible SessionStart surface is **stderr written with `exit 2`**: for
  SessionStart, `exit 2` renders the hook's stderr in the transcript as a visible notice and **execution
  continues** (non-blocking for THIS event -- unlike PreToolUse where `exit 2` blocks the tool). So every
  user-facing line this hook emits (the superpowers advisory, the `.no-agy` announce, the jq-missing warning)
  goes to **stderr followed by `exit 2`**; a healthy/silent outcome is `exit 0` with no stderr.
- **Manifest divergence to respect:** `clavity-classic`'s `hooks.json` already carries a **variant-specific**
  `SessionStart` entry (its driver-guidance reset); `clavity-dotnet` has **no** `SessionStart` block today.
  So the shared degradation-notice registration must be **added to both**, and the anti-drift check must
  compare only the **shared entry**, not the whole `SessionStart` block (classic legitimately carries an
  extra entry). This is the same "shared-block-only" principle the seed-sync gate already applies to
  `PostToolUse` (classic's variant-specific hooks must not trip it); the plan resolves the exact `jq`
  selector (the shared entry is identifiable by its command referencing the degradation-hook script).
- **Both the `.no-agy` announce and the superpowers presence check live in this one SessionStart hook** (one
  liveness surface, one place the user looks at boot).

---

## D3 -- Dependency guards: jq retrofit + the honest bash limit

- **jq-guard retrofit onto `agy-after-reminder.sh`.** Measured today: with `jq` absent (bash + coreutils
  present), `agy-after-reminder.sh` on a spec/plan path that *should* fire produces **no output and exits 0**
  -- a silent-drop that violates Decision 3's "LOUD, never silent." Retrofit the **same** guard SP-C shipped
  on `agy-seam-inject.sh`: detect a missing `jq` and emit a loud, hard-coded ASCII
  `[AGY-DISCIPLINES] guard inactive: missing jq` line (never a silent no-op). The new SessionStart hook gets
  the same guard.
  - **Seam-gate the loud line (panel F3).** Without `jq` the hook cannot parse the payload to know whether the
    write was a spec/plan artifact, so a naive "emit on missing jq" would fire on **every** `Write`/`Edit` in
    the session = spam. Gate it exactly as SP-C did: first field-bounded-grep the raw payload for a
    `docs/superpowers/(specs|plans)/....md` `file_path` and emit the loud line **only on that match** (SP-C's
    loud line likewise fires only on a skill-seam match). The SessionStart hook has no such gating need (it
    always intends to run), so its jq-missing loud line is unconditional.
  - **The seam-gate grep is separator-agnostic (panel F7).** The raw JSON payload carries Windows paths with
    escaped backslashes (`docs\\superpowers\\specs\\x.md`) -- the existing `agy-after-reminder.sh` already
    normalizes `tr '\\' '/'` *after* jq extraction, but the jq-missing grep runs on the RAW payload before any
    normalization. A `/`-only pattern silently drops the loud line on a Windows box missing jq. The grep MUST
    match either separator, e.g. `docs[\\/]+superpowers[\\/]+(specs|plans)[\\/]+...\.md`.
- **The bash-missing limit is stated honestly, not faked.** A `bash` hook cannot detect its **own** missing
  interpreter -- if `bash` is absent, the hook (and every other `*.sh` hook, including this SessionStart one)
  never runs, so there is no runtime surface to announce from. Therefore bash is a **documented hard
  prerequisite** (D5), optionally verified at install time -- NOT a fake runtime guard that structurally
  cannot fire. The realistic, guardable case is "bash present, jq missing," which the jq-guard covers.
- **Per-event visibility of the jq-missing warning (delta-review + CC-docs).** The reliable USER-visible dep
  warning comes from the **SessionStart hook** (stderr + `exit 2`, D2) -- it checks `jq` at boot and tells the
  user directly. The per-event guards on `agy-after-reminder.sh` (PostToolUse) and the already-shipped
  `agy-seam-inject.sh` (PreToolUse, line 24) emit their `guard inactive: missing jq` line via `additionalContext`
  (model-relay) -- the correct/only best-effort surface for those events, which fire during an active turn the
  model relays in (`exit 2` there would block the tool / feed Claude, not reach the user). **So SP-C's shipped
  guard is NOT a latent bug** -- it is the consistent best-effort mechanism for a PreToolUse hook; the new
  SessionStart hook is what guarantees the user actually *learns* jq is missing. The retrofit onto
  `agy-after-reminder.sh` therefore mirrors SP-C's `additionalContext` approach (it fixes the measured
  silent-drop -- no output at all), while the boot-time user-visible dep warning lives in the SessionStart hook.

---

## D4 -- Comprehensive hook-activation test category

A Pester category (under `scripts/tests/`, run by `just test-scripts`) driving **synthetic payloads** through
each hook and asserting behavior -- complementing SP-C's existing `agy-seam-inject.Tests.ps1` smoke:

- **`agy-after-reminder.sh`:** fires (emits the AGY-AFTER `additionalContext`) on a
  `docs/superpowers/(specs|plans)/*.md` write; silent on a non-artifact path; suppressed under `.no-agy`
  (cwd and `~/.claude`); the **jq-missing loud-line** path.
- **`agy-seam-inject.sh`:** the **jq-missing loud-line** case SP-C deferred here (SP-C's smoke covered the
  happy/debounce/`.no-agy`/ASCII paths; the jq-missing loud line is added now).
- **The new SessionStart hook:** superpowers-present -> silent; superpowers-absent -> the possibility advisory;
  `.no-agy` at cwd / `~/.claude` -> the suppression announce (and NO superpowers/jq notice -- no spam);
  jq-missing loud-line. **Every visible-notice case asserts the line is on STDERR with EXIT CODE 2** (the
  user-visible surface, per D2) and the healthy case asserts `exit 0` with empty stderr -- a test that only
  checks stdout would pass vacuously on the (invisible) `additionalContext` path this hook must NOT use.
  Drive the hierarchy cases by pointing `$env:HOME`/`$CLAUDE_PROJECT_DIR` at fixtures with crafted
  `settings.json` / `settings.local.json` (superpowers enabled at user scope but disabled project-local, etc.).

Fixtures follow the SP-C convention (temp dirs isolated from the real repo's `.clavity`; `bash` invoked as
the SP-C smoke does; pure-ASCII assertions on emitted lines) **plus `$HOME` isolation (panel F10): each test
sets `$env:HOME` to a temp dir so the hooks' `$HOME/.claude/.no-agy` global-kill-switch check (and the
settings-hierarchy read) resolves the fixture, not the host's real `~/.claude`** -- otherwise a developer
with a real global `.no-agy` (or global `enabledPlugins`) gets spurious happy-path failures. SP-C's smoke
does not yet mock `$HOME`; the SP-D category adds it and the plan retrofits it onto the SP-C smoke. A shared
bash-hook test helper may be extracted if it removes duplication across the three hooks' tests (the sole
roadmap adjacency).

---

## D5 -- Anti-drift enrollment

- Add the new SessionStart hook script to the **byte-identical enumeration** in
  `scripts/check-seed-artifacts-synced.sh` (the `for rel in ...` list).
- Add a **shared-`SessionStart`-entry** `jq -S` diff (scoped to the shared entry only, per D2 -- not the whole
  block, so classic's variant-specific SessionStart entry does not trip the gate), mirroring the existing
  `PostToolUse` / `PreToolUse` diffs.
- Update the `scripts/README.md` coverage row.

---

## D5b -- Docs (item 5) -- named home (panel F4)

The superpowers-prerequisite messaging lands as a short line in **each driver plugin's `plugin/README.md`**
(the user-facing install doc): *"superpowers is required only for the disciplines to **auto-fire**; without
it they stay manually invokable (`agy-first` / `agy-capstone`)."* This mirrors the SessionStart advisory in
prose form for a reader who never opens a session. The **accepted best-effort limits** are already documented
in this spec + the shipped skill bodies; no separate limits doc is created (YAGNI). If both READMEs carry the
same shared line, the plan decides whether it also enrolls in the seed-sync gate (low priority -- README drift
is not load-bearing the way a hook script is).

---

## D6 -- SP-0 namespace-gate regression test (owner-folded leftover)

SP-0's Phase-4 hardened the namespace-rename completeness gate so it enumerates tracked files via
`git ls-files` (deterministic) and self-excludes the gate's own docstring + Pester fixture. That fix was
recorded but never locked by a **regression test**. SP-D adds a git-fixture Pester test that pins:
- the gate ignores **gitignored** build artifacts (the false-flag it used to emit), and
- the gate's **self-match exclusion** (it must not flag its own docstring / fixture).
This is scoped to the existing namespace-gate script + its Pester suite; no product-code change.

---

## Testing posture & Definition of Done

- `just test-scripts` GREEN (the new hook-activation category + the D6 regression test + all existing suites).
- `just seed-sync-check` GREEN **and proven-to-bite** (a drift probe on the new SessionStart hook / its
  shared registration must fail the gate, then restore to GREEN).
- The new SessionStart hook manually smoke-verified for all four states (present/absent/`.no-agy`/jq-missing).
- **AGY-CAPSTONE** on the committed SP-D range (rounds-until-green over executable code + tests, verify by
  measurement, human-adjudicated GREEN).

---

## Accepted limits / non-goals (honest, per epic Posture)

- **Best-effort, not a sandbox** -- a SessionStart notice is a seatbelt reminder; it does not enforce.
- **bash-missing** is handled at the install/doc layer (D3), not a runtime guard that cannot fire.
- **No per-skill-ID probe** -- superpowers exposes no stable skill-ID API; a presence check + manual-fallback
  line is the fail-toward-loud choice (D1).
- **Detection rests on undocumented Claude Code internals** (`settings.json` `.enabledPlugins` shape, the
  config-dir env var) -- panel F5. The possibility-framed advisory absorbs drift: if the shape changes across a
  CC version and a `superpowers@*: true` key can't be read, the hook emits the **soft advisory**, never a
  false "disabled." A malformed/absent settings file is treated identically. The read is written shape-tolerant
  (no hard schema assumption beyond "an `enabledPlugins` object whose keys may be plugin@marketplace").
- **Both drivers installed** (transient migration) may double-announce -- accepted (the drivers are mutually
  exclusive; steady-state is one).
- **ME1 / AGY-LEARN** remain epic-excluded.

---

## Then: ONE combined release closes the ship-agy-workflow epic.
