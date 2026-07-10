# Phase 2 — Seed Extraction (agent artifacts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `adversarial-panel-review` discipline **driver-native** — move the (transport-agnostic) panel skill + the AGY-AFTER reminder hook out of the optional `agy-autotrain` (AUTO) plugin into each driver's marketplace plugin, and thin the two driving skills' duplicated agnostic prose to transport + a pointer — with **zero runtime-path risk**.

**Architecture:** This phase touches only **agent artifacts** (skills/hooks discovered by the marketplace from a committed plugin dir) and **documentation**. The panel skill + AGY-AFTER hook are committed into BOTH driver plugins (`clavity-dotnet/plugin`, `clavity-classic/plugin`) — the only channel that makes them marketplace-discoverable per driver — kept identical by a byte-for-byte sync-check. Both driving skills (`clavity-ls-driving`, `clavity-driving`) drop their mirrored agnostic sections and point at the co-located panel skill. The Phase-1 fork-repoint deferral is completed here against the CURRENT canonical (`agy-autotrain/knowledge/`).

**The DATA move is explicitly NOT in this phase.** Moving the manuals + golden-header source out of `agy-autotrain` requires a runtime-resolution model (installer seeds `%USERPROFILE%\.clavity\`; agy-curate reads the shared path) that lands in **Phase 3** — doing the file move now would orphan the data (staged with no consumer) and break `agy-curate` install-side. So `seed/` is NOT created here, no installer is touched, and `agy-curate` is left untouched. **Acceptance #1 ("a no-agy-autotrain driver has the manual") is a Phase-3 deliverable.**

**Tech Stack:** Markdown (skills/docs), Bash hooks + `hooks.json`, `just` recipes, `lefthook`, grep oracles. No compiled-code changes; no installer changes.

---

## Locked design decisions

- **Scope (AGY-FIRST cascade `0d033d59`; user-ratified 2026-07-10):** dotnet-first (B2), with classic's driving skill also thinned and classic's plugin also receiving the agent artifacts (doc/plugin-only — classic installer/binary untouched). **clavity-classic is the confirmed LIVE FAILOVER** (used when an agy upgrade breaks clavity-dotnet); its DATA + installer staging is the definite next phase, and the next public release is gated on it (the failover must not ship un-seeded). "Don't experiment on your failover" — prove the pattern on the primary first.
- **DATA move deferred to Phase 3 (AGY-AFTER panel R1; agy + controller converge, user-ratified):** the panel caught that moving the data ahead of its runtime-resolution model orphans it and breaks agy-curate. Phase 2 is therefore agent-artifacts + doc-thinning only; the data move + installer seeding + agy-curate repointing land atomically in Phase 3.
- **Agent-artifact single-sourcing (Fork A refinement):** the panel skill must be committed in each driver plugin (marketplace discovers skills/hooks only from a committed dir — a build-time copy would be invisible to a dev/marketplace load). Two committed copies, guarded by a byte-identical sync-check.
- **F1 fold — the panel skill is de-transported first:** the shipped skill hardcodes `agy_status`/`agy_ask` (dotnet MCP) in 3 places, so it is NOT transport-agnostic as-is. Task 1 de-transports its escalation step (enumerate both drivers' review-ask transports) BEFORE it is duplicated into the classic plugin — only then is byte-identical duplication + the sync-check valid.

## Disposition contract (every artifact's destination)

| Artifact (current path) | Phase-2 destination | Kind |
|---|---|---|
| `agy-autotrain/skills/adversarial-panel-review/` | de-transport, then → `clavity-dotnet/plugin/skills/…` **and** `clavity-classic/plugin/skills/…`; remove from source | AGENT — move+dup |
| `agy-autotrain/hooks/agy-after-reminder.sh` + its `hooks.json` PostToolUse entry | → `clavity-dotnet/plugin/hooks/…` **and** `clavity-classic/plugin/hooks/…`; remove from source | AGENT — move+dup |
| `agy-autotrain/hooks/agy-learn-reminder.sh` + SessionStart/PreCompact entries | STAYS (AUTO) | AGENT — keep |
| driving skills' 2 panel-specific sections (`## Multi-lens panels`, `### Seat palette`) | DELETE, replace with a pointer at the panel skill | prose — thin |
| driving skills' everyday-discipline sections (`## Task-assignment protocol`, `## agy is a peer…`) | **KEEP** (single-sourcing rides Phase 3) | prose — keep |
| `clavity-classic/docs/agy-assumptions.md` + `agy-capabilities.md` (Phase-1 stubs) | DELETE; repoint referrers to `agy-autotrain/knowledge/…` (current canonical) | prose — retire |
| **`agy-autotrain/knowledge/*.md` (all 4), `agy-curate`/`agy-learn`/`verify`, `seed/`** | **UNCHANGED — Phase-3** | — |

**KEEP list (must NOT change this phase):** everything under `agy-autotrain/knowledge/`; `agy-curate`/`agy-learn`/`verify` skills; the SessionStart/PreCompact `agy-learn-reminder.sh` hook entries; all clavity-classic Rust/binary code; every `.iss` installer; NO `seed/` dir is created.

---

## Task 0: Baseline capture (BEFORE any mutation)

**Files:** none created — records current-state oracles.

- [ ] **Step 1: Record the repoint worklist + confirm the move inputs exist**

```bash
# (a) agent artifacts that MUST move (expect present)
ls -1 agy-autotrain/skills/adversarial-panel-review/SKILL.md agy-autotrain/hooks/agy-after-reminder.sh agy-autotrain/hooks/hooks.json
# (b) the panel skill's dotnet-transport couplings that Task 1 must de-transport (expect 3-4 matches: lines ~51/59/121)
grep -nE 'agy_ask|agy_status' agy-autotrain/skills/adversarial-panel-review/SKILL.md
# (c) all clavity-classic referrers of the two stubbed docs (the Task-5 worklist) — SAVE this list
grep -rnE 'agy-(assumptions|capabilities)\.md' clavity-classic --include='*.rs' --include='*.md' | grep -v 'docs/superpowers/' | sort
# (d) both variant CLAUDE.md pointers into the manuals
grep -nE 'agy-assumptions\.md' clavity-dotnet/CLAUDE.md clavity-classic/CLAUDE.md
# (e) KEEP-IN-SYNC markers in the two driving skills (thinning targets)
grep -nE 'KEEP IN SYNC' clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md clavity-classic/plugin/skills/clavity-driving/SKILL.md
```

- [ ] **Step 2: Confirm no destination collisions**

Run: `ls clavity-dotnet/plugin/hooks 2>/dev/null; ls clavity-classic/plugin/hooks 2>/dev/null; ls seed 2>/dev/null`
Expected: all three print nothing / "No such file" — neither plugin `hooks/` dir exists yet, and `seed/` does NOT exist (and must NOT be created this phase). If any exists, STOP and report `STATE_MISMATCH: <what>`.

- [ ] **Step 3: Confirm the lint gate is green BEFORE mutation** (so Task 6.7 can't be blocked by pre-existing red)

Run: `just lint` — expected: exits 0. If it is already red, STOP and report `STATE_MISMATCH: lint red at baseline` (fix or get a waiver before proceeding).

- [ ] **Step 4: No commit** — Task 0 is read-only.

---

## Task 1: De-transport the panel skill; move it + the AGY-AFTER hook into `clavity-dotnet/plugin`; remove from agy-autotrain

**Files:**
- Modify (in place, before move): `agy-autotrain/skills/adversarial-panel-review/SKILL.md` (de-transport the 3 escalation refs)
- Create: `clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md` (via git mv)
- Create: `clavity-dotnet/plugin/hooks/agy-after-reminder.sh` (via git mv), `clavity-dotnet/plugin/hooks/hooks.json`
- Modify: `agy-autotrain/hooks/hooks.json` (remove ONLY the PostToolUse Write|Edit entry; keep SessionStart + PreCompact)
- Modify: `agy-autotrain/README.md`, `agy-autotrain/CHANGELOG.md`, `agy-autotrain/plugin.json` + `.claude-plugin/plugin.json`

- [ ] **Step 1: De-transport the panel skill's escalation step (F1)**

In `agy-autotrain/skills/adversarial-panel-review/SKILL.md`, the escalation round (Step 2) hardcodes dotnet MCP verbs. Make it transport-agnostic (the skill will be shipped to BOTH drivers). Replace the three references:
- The `agy_status`/`agy_ask` sentence (line ~51) — replace `Precheck that agy is idle (\`agy_status\`) before sending, then send the review request via \`agy_ask\` using filepath transport:` with: `Precheck the peer is idle, then send the review request over your driver's review-ask transport using filepath transport (clavity-dotnet: the \`agy_ask\` MCP tool, after an \`agy_status\` idle-check; clavity-classic: \`clavity ask --review-only\`):`
- The two later mentions of "the `agy_ask` payload" (lines ~59, ~121) — replace `agy_ask payload` with `review-ask payload` (transport-neutral).

Verify: `grep -nE 'agy_ask|agy_status' agy-autotrain/skills/adversarial-panel-review/SKILL.md` — expected: the ONLY remaining matches are inside the clavity-dotnet enumeration on the line ~51 sentence (i.e. the dotnet-specific mention now sits beside the classic one). Confirm `grep -c 'clavity ask --review-only' agy-autotrain/skills/adversarial-panel-review/SKILL.md` → ≥1.

- [ ] **Step 2: git-move the (now de-transported) skill + hook into the dotnet plugin**

```bash
mkdir -p clavity-dotnet/plugin/hooks
git mv agy-autotrain/skills/adversarial-panel-review clavity-dotnet/plugin/skills/adversarial-panel-review
git mv agy-autotrain/hooks/agy-after-reminder.sh       clavity-dotnet/plugin/hooks/agy-after-reminder.sh
```

The hook body is cwd-relative (`$cwd`, `$HOME/.claude/.no-agy`, the `docs/superpowers/(specs|plans)/*.md` glob) — no plugin-relative paths — so it needs no edits after the move. Confirm: `grep -nE 'CLAUDE_PLUGIN_ROOT|agy-autotrain' clavity-dotnet/plugin/hooks/agy-after-reminder.sh` → expected NO output.

- [ ] **Step 3: Create `clavity-dotnet/plugin/hooks/hooks.json`** (dotnet plugin had none; `hooks/hooks.json` is auto-loaded — verified: agy-autotrain uses the same convention with no manifest key)

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-after-reminder.sh\"" }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Remove the PostToolUse entry from agy-autotrain's `hooks.json`, keeping the learn-reminder entries**

Rewrite `agy-autotrain/hooks/hooks.json` to retain ONLY SessionStart + PreCompact (both invoking `agy-learn-reminder.sh`):

```json
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|clear|compact",
        "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-learn-reminder.sh\" SessionStart" } ] }
    ],
    "PreCompact": [
      { "matcher": "manual|auto",
        "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-learn-reminder.sh\" PreCompact" } ] }
    ]
  }
}
```

- [ ] **Step 5: Verify source removal + destination presence**

```bash
ls agy-autotrain/skills/adversarial-panel-review 2>/dev/null && echo "FAIL: still in agy-autotrain" || echo "OK removed"
ls agy-autotrain/hooks/agy-after-reminder.sh 2>/dev/null && echo "FAIL: hook still in agy-autotrain" || echo "OK hook removed"
ls clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-dotnet/plugin/hooks/agy-after-reminder.sh clavity-dotnet/plugin/hooks/hooks.json
grep -c 'agy-after-reminder' agy-autotrain/hooks/hooks.json   # expected: 0
grep -c 'agy-learn-reminder' agy-autotrain/hooks/hooks.json   # expected: 2
jq . agy-autotrain/hooks/hooks.json >/dev/null && echo "OK hooks.json parses" || { echo "FAIL: hooks.json is not valid JSON"; exit 1; }
jq . clavity-dotnet/plugin/hooks/hooks.json >/dev/null && echo "OK dotnet hooks.json parses" || { echo "FAIL"; exit 1; }
```

- [ ] **Step 6: Update agy-autotrain self-description + version**

In `agy-autotrain/README.md`: remove the "Review discipline — `adversarial-panel-review`" section and the `skills/adversarial-panel-review/` Layout line; add one line noting the panel skill + AGY-AFTER hook now ship with the driver's plugin. In both `agy-autotrain/plugin.json` and `agy-autotrain/.claude-plugin/plugin.json`, bump `version` `0.1.3` → `0.1.4`. Add a `CHANGELOG.md` 0.1.4 entry: "Move the `adversarial-panel-review` skill (de-transported) + AGY-AFTER hook into each driver's plugin — the panel discipline is now driver-native. agy-autotrain retains the learning loop (learn/curate/verify + observations inbox). (The agnostic manuals + golden-header baseline move to the driver seed in Phase 3.)"

**Transition note (version-skew — documented):** agy-autotrain and the driver plugin version independently, so during rollout:
- *Hook:* old agy-autotrain 0.1.3 (hook present) + new driver plugin (hook present) → the AGY-AFTER reminder fires **twice** (harmless); new 0.1.4 (hook removed) + old driver (no hook) → fires **zero times** until both update (a missing nudge, not a break).
- *Skill (panel R2/R3):* in the same window, TWO installed plugins expose a skill named `adversarial-panel-review` (old agy-autotrain 0.1.3 + the new driver). Claude Code skills are **plugin-namespaced** (invoked as `plugin:skill`, e.g. `agy-autotrain:adversarial-panel-review`), so the most likely outcome is a **namespaced shadow/ambiguity**, not a hard failure — the driver's copy is authoritative and the ambiguity resolves the moment agy-autotrain updates to 0.1.4 (drops the skill → one copy). **UNVERIFIED RISK (panel R3, agy):** if a given loader instead enforces globally-unique skill names and *rejects* on a duplicate, the window could be worse than a shadow. Mitigation is cheap and worth taking regardless: **VERIFY the loader's behavior on a duplicate name during Task 6 Step 6's discovery check**, and order the release so agy-autotrain updates to 0.1.4 (drop) at/after the driver update, minimizing the window. Steady-state is clean either way.

- [ ] **Step 7: Verify agy-autotrain no longer claims the moved artifacts**

Run: `grep -rnE 'skills/adversarial-panel-review|agy-after-reminder' agy-autotrain/ | grep -v CHANGELOG || echo "OK"`
Expected: `OK` (only the CHANGELOG may mention them in prose).

- [ ] **Step 8: Commit**

```bash
git add agy-autotrain/ clavity-dotnet/plugin/
git commit -m "feat(seed): de-transport + move adversarial-panel-review skill + AGY-AFTER hook into clavity-dotnet plugin; agy-autotrain -> 0.1.4"
```

---

## Task 2: Mirror the agent artifacts into `clavity-classic/plugin`; add the byte-identical sync-check

**Files:**
- Create: `clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md`, `clavity-classic/plugin/hooks/agy-after-reminder.sh`, `clavity-classic/plugin/hooks/hooks.json` (identical copies)
- Create: `scripts/check-seed-artifacts-synced.sh`
- Modify: root `justfile` (add `seed-sync-check`) + `lefthook.yml` (run it pre-push)

- [ ] **Step 1: Copy the three agent-artifact files verbatim into the classic plugin**

```bash
mkdir -p clavity-classic/plugin/skills clavity-classic/plugin/hooks
cp -r clavity-dotnet/plugin/skills/adversarial-panel-review clavity-classic/plugin/skills/adversarial-panel-review
cp    clavity-dotnet/plugin/hooks/agy-after-reminder.sh       clavity-classic/plugin/hooks/agy-after-reminder.sh
cp    clavity-dotnet/plugin/hooks/hooks.json                  clavity-classic/plugin/hooks/hooks.json
```

- [ ] **Step 2: Write the sync-check** at `scripts/check-seed-artifacts-synced.sh`

```bash
#!/usr/bin/env bash
# Fails if the seed AGENT artifacts drift between the two driver plugins.
# The (transport-agnostic) adversarial-panel-review skill + AGY-AFTER hook are single-source-of-truth but
# must be committed in BOTH driver plugins (marketplace discovers skills/hooks only from a committed dir).
set -euo pipefail
D=clavity-dotnet/plugin
C=clavity-classic/plugin
status=0
for rel in \
  skills/adversarial-panel-review/SKILL.md \
  hooks/agy-after-reminder.sh \
  hooks/hooks.json ; do
  if ! diff -q "$D/$rel" "$C/$rel" >/dev/null 2>&1; then
    echo "SEED-DRIFT: $rel differs between clavity-dotnet/plugin and clavity-classic/plugin" >&2
    status=1
  fi
done
[ "$status" -eq 0 ] && echo "seed agent artifacts in sync (dotnet == classic)"
exit "$status"
```

- [ ] **Step 3: Wire the check into `justfile` + `lefthook.yml`**

Add to root `justfile`:
```
# Verify the seed agent artifacts are byte-identical across the two driver plugins
seed-sync-check:
    bash scripts/check-seed-artifacts-synced.sh
```
In `lefthook.yml`, under the existing `pre-push` commands (alongside `just lint`), add:
```yaml
    seed-sync:
      run: just seed-sync-check
```

- [ ] **Step 4: Run the check — it must PASS**

Run: `bash scripts/check-seed-artifacts-synced.sh`
Expected: `seed agent artifacts in sync (dotnet == classic)`, exit 0.

- [ ] **Step 5: Negative check — mutate a real JSON value (not corrupt the file) to prove the guard catches logical drift**

```bash
sed -i 's/"Write|Edit"/"Write|Edit|MultiEdit"/' clavity-classic/plugin/hooks/hooks.json
bash scripts/check-seed-artifacts-synced.sh; echo "exit=$?"
git checkout -- clavity-classic/plugin/hooks/hooks.json
```
Expected: prints `SEED-DRIFT: hooks/hooks.json …`, `exit=1`, then the file is restored (still valid JSON throughout). Re-run Step 4 to confirm green again.

- [ ] **Step 6: Commit**

```bash
git add clavity-classic/plugin/ scripts/check-seed-artifacts-synced.sh justfile lefthook.yml
git commit -m "feat(seed): mirror panel skill + AGY-AFTER hook into clavity-classic plugin; add byte-identical sync-check"
```

---

## Task 3: Thin `clavity-ls-driving` (dotnet) — move ONLY the panel-specific sections

**Files:** Modify `clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md`

**Consumer-driven scope (user, 2026-07-10):** thin ONLY the two panel-specific sections — `## Multi-lens panels` and `### Seat palette` — into a pointer at the co-located `adversarial-panel-review` skill. **KEEP** `## Task-assignment protocol` (misfire-prevention used on EVERY agy delegation) and `## agy is a peer, not an oracle` (the everyday consult-first/review-after/verify posture) — these are everyday driving discipline, not panel ceremony, and exiling them to a panel skill would degrade routine driving. Their single-sourcing (they are duplicated across the two driving skills) rides the **Phase-3** seed extraction. The `<!-- KEEP IN SYNC … -->` comment on Task-assignment protocol STAYS (still duplicated). Retained transport sections: `## Results you must handle`, `## Injection is automatic`.

- [ ] **Step 1: Replace only the two panel-specific sections with a pointer**

Delete everything from `## Multi-lens panels — the high-leverage review mode` through the end of `### Seat palette — a priority reminder, NOT a required roster` (the block between `## Task-assignment protocol` and `## agy is a peer, not an oracle`). Insert in its place:

```markdown
## Convening a review panel — see the panel skill

For a formal multi-seat review of a high-leverage artifact, the panel procedure — trigger gate, the seat
palette, running rounds, verify-before-folding, the PANEL VERDICT — lives in the transport-agnostic
**`adversarial-panel-review`** skill (shipped in this same plugin). Invoke it when you finish or
materially edit a high-leverage spec/plan/design, or need an adversarial multi-seat teardown. Route the
panel over `agy_ask` (the WRITE tool above). The everyday driving discipline (the task-assignment
protocol above, and the consult-first/review-after/verify decision loop below) stays here — it applies to
every agy delegation, not just formal panels.
```

- [ ] **Step 2: Verify**

```bash
grep -cE '^## Multi-lens panels|^### Seat palette' clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md   # expected: 0 (moved out)
grep -cE '^## Task-assignment protocol|^## agy is a peer' clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md   # expected: 2 (KEPT — everyday discipline)
grep -c 'adversarial-panel-review' clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md   # expected: >=1
grep -c 'KEEP IN SYNC' clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md   # expected: 1 (STAYS — Task-assignment still duplicated)
grep -cE '^## Results you must handle|^## Injection is automatic' clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md   # expected: 2
```

- [ ] **Step 3: Commit**

```bash
git add clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md
git commit -m "refactor(clavity-ls-driving): thin to transport + pointer at adversarial-panel-review skill"
```

---

## Task 4: Thin `clavity-driving` (classic) — move ONLY the panel-specific sections

**Files:** Modify `clavity-classic/plugin/skills/clavity-driving/SKILL.md`

**Consumer-driven scope (user, 2026-07-10):** mirror Task 3 — thin ONLY `## Multi-lens panels` and `### Seat palette` into a pointer; **KEEP** `## Task-assignment protocol` and `## agy is a peer, not an oracle` (everyday driving discipline; single-sourcing rides Phase 3). Retain the transport sections (`## 0.`–`## 5.`, `## Prepend the golden header`, `## 6. Clarify / cancel / recover`). Update the trailing `<!-- KEEP IN SYNC … -->` comment to name only the retained duplicated sections (task-assignment protocol + peer-decision-loop).

- [ ] **Step 1: Replace only the two panel-specific sections with the classic pointer**

Delete from `## Multi-lens panels — the high-leverage review mode` through the end of `### Seat palette — a priority reminder, NOT a required roster` (the block between `## Task-assignment protocol` and `## agy is a peer, not an oracle`). Insert in its place:

```markdown
## Convening a review panel — see the panel skill

For a formal multi-seat review of a high-leverage artifact, the panel procedure — trigger gate, the seat
palette, running rounds, verify-before-folding, the PANEL VERDICT — lives in the transport-agnostic
**`adversarial-panel-review`** skill (shipped in this same plugin). Invoke it when you finish or
materially edit a high-leverage spec/plan/design, or need an adversarial multi-seat teardown. Route the
panel over `clavity ask --review-only` (the review transport above). The everyday driving discipline (the
task-assignment protocol above, and the consult-first/review-after/verify decision loop below) stays
here — it applies to every agy delegation, not just formal panels.
```

Then update the `<!-- KEEP IN SYNC with clavity-ls-driving … -->` comment (now near the peer-decision-loop) so it references only the still-duplicated sections: `task-assignment protocol + peer-decision-loop (transport idioms differ)`.

- [ ] **Step 2: Verify**

```bash
grep -cE '^## Multi-lens panels|^### Seat palette' clavity-classic/plugin/skills/clavity-driving/SKILL.md   # expected: 0 (moved out)
grep -cE '^## Task-assignment protocol|^## agy is a peer' clavity-classic/plugin/skills/clavity-driving/SKILL.md   # expected: 2 (KEPT)
grep -c 'adversarial-panel-review' clavity-classic/plugin/skills/clavity-driving/SKILL.md   # expected: >=1
grep -c 'KEEP IN SYNC' clavity-classic/plugin/skills/clavity-driving/SKILL.md   # expected: 1 (retained, rescoped)
grep -cE '^## 0\. Readiness|^## Prepend the golden header|^## 6\. Clarify' clavity-classic/plugin/skills/clavity-driving/SKILL.md   # expected: 3
```

- [ ] **Step 3: Commit**

```bash
git add clavity-classic/plugin/skills/clavity-driving/SKILL.md
git commit -m "refactor(clavity-driving): thin to transport + pointer at adversarial-panel-review skill"
```

---

## Task 5: Fork repoint — retire the Phase-1 stubs; point referrers at the current canonical

**Repoint target (this phase):** the manuals' CURRENT canonical home, `agy-autotrain/knowledge/agy-assumptions.md` / `agy-capabilities.md` (where the Phase-1 stubs already redirect). Phase 3 will re-repoint these to `seed/` atomically with the data move — that second hop is a mechanical sweep; doing this hop now removes the ugly Phase-1 stubs and keeps every reference resolving to real canonical content.

**Exact relative path per referrer** (computed from each file's directory to repo-root `agy-autotrain/knowledge/`):

| Referrer file | Its dir depth from repo root | Relative prefix to `agy-autotrain/knowledge/` |
|---|---|---|
| `clavity-classic/src/membus.rs` | `clavity-classic/src/` (2 deep) | `../../agy-autotrain/knowledge/` |
| `clavity-classic/README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `ROADMAP.md` | `clavity-classic/` (1 deep) | `../agy-autotrain/knowledge/` |
| `clavity-classic/docs/agy-remote-control-protocol.md`, `docs/agy-test-suite.md` | `clavity-classic/docs/` (2 deep) | `../../agy-autotrain/knowledge/` |
| `clavity-dotnet/CLAUDE.md` | `clavity-dotnet/` (1 deep) | `../agy-autotrain/knowledge/` (already correct today — verify) |

- [ ] **Step 1: Delete the two redirect stubs**

```bash
git rm clavity-classic/docs/agy-assumptions.md clavity-classic/docs/agy-capabilities.md
```

- [ ] **Step 2: Repoint the Markdown link referrers (mechanical rule — no per-line judgment)**

Decision rule (deterministic): for every referrer file, any Markdown link of the form `](…docs/agy-assumptions.md)` or `](…docs/agy-capabilities.md)` (i.e. pointing at the now-deleted stub) → rewrite the link target to the table's relative prefix + `agy-assumptions.md`/`agy-capabilities.md`. Bare in-prose citations that are NOT Markdown links (e.g. "assumption #13") → leave the prose untouched. Apply to: `clavity-classic/README.md:265,272,314`, `CONTRIBUTING.md:29`, `CLAUDE.md:8`, `docs/agy-remote-control-protocol.md:48,180,223`, and each `ROADMAP.md` line from Task-0 step 1c that is a Markdown link. `clavity-dotnet/CLAUDE.md` already points at `../agy-autotrain/knowledge/agy-assumptions.md` — confirm and leave if correct.

- [ ] **Step 3: Repoint the Rust doc-comments (comments only — NO code change)**

`clavity-classic/src/membus.rs` line 10: `see \`docs/agy-assumptions.md\` #13` → `see \`../../agy-autotrain/knowledge/agy-assumptions.md\` #13`. Line 19: `See \`docs/agy-assumptions.md\`.` → `See \`../../agy-autotrain/knowledge/agy-assumptions.md\`.`

SHAPE-DIVERGENCE STOP: these are `//!`/`//` comments. If making the reference resolve would require changing ANY Rust code, STOP and report.

- [ ] **Step 4: Rewrite the `agy-test-suite.md` references that cite Phase-1-DROPPED content**

`clavity-classic/docs/agy-test-suite.md` lines 3, 12, 114, 197, 198 cite the moved docs AND content Phase 1 deleted (`§G`, the "Refresh after an `agy update`" runbook, "bump `Verified against`"). Repoint links to `../../agy-autotrain/knowledge/…`, and rewrite the prose naming deleted content:
- line 12 "the refresh runbook in `agy-capabilities.md` §\"Refresh after an `agy update`\"" → "the AUTO-layer refresh loop (`agy-autotrain` `agy-learn`/`agy-curate`)".
- line 114 "…update `assumption #6` … and the profile §G" → replace "the profile §G" with "the capability profile (`../../agy-autotrain/knowledge/agy-capabilities.md`)".
- lines 197–198 "update `agy-capabilities.md` (re-tag the affected claim, bump `Verified against`)" → replace "bump `Verified against`" with "capture the drift via `agy-learn` for `agy-curate` to fold".

- [ ] **Step 5: Verify NO referrer still points at the deleted stubs; targets resolve**

```bash
grep -rnE '\]\((\.\./)*docs/agy-(assumptions|capabilities)\.md\)' clavity-classic clavity-dotnet --include='*.md' | grep -v 'docs/superpowers/' || echo "OK no stub links remain"
grep -nE '§G|Refresh after an .agy update.|bump .Verified against.' clavity-classic/docs/agy-test-suite.md || echo "OK dropped-content refs rewritten"
ls agy-autotrain/knowledge/agy-assumptions.md agy-autotrain/knowledge/agy-capabilities.md   # targets exist
```

- [ ] **Step 6: Commit**

```bash
git add clavity-classic/ clavity-dotnet/CLAUDE.md
git commit -m "docs(seed): retire Phase-1 redirect stubs; repoint referrers to agy-autotrain/knowledge canonical; rewrite dropped-content citations"
```

---

## Task 6: Final acceptance gate

**Files:** none — verification only. Negative-assertion checks HARD-FAIL (exit non-zero on a match) so a subagent cannot false-GREEN by ignoring stdout.

- [ ] **Step 1: The panel discipline is driver-native in BOTH plugins; sync holds**

```bash
ls clavity-dotnet/plugin/skills/adversarial-panel-review/SKILL.md clavity-dotnet/plugin/hooks/hooks.json
ls clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md clavity-classic/plugin/hooks/hooks.json
bash scripts/check-seed-artifacts-synced.sh   # expected: in sync, exit 0
```

- [ ] **Step 2: The shipped skill is transport-agnostic (F1) — HARD FAIL if a bare dotnet-only coupling remains**

```bash
# the classic copy must NOT instruct agy_ask without also offering the classic transport
grep -q 'clavity ask --review-only' clavity-classic/plugin/skills/adversarial-panel-review/SKILL.md || { echo "FAIL: classic panel skill lacks classic transport"; exit 1; }
echo "OK: panel skill enumerates both transports"
```

- [ ] **Step 3: Driving skills thinned — HARD FAIL if panel prose remains**

```bash
if grep -qE '^## Multi-lens panels' clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md clavity-classic/plugin/skills/clavity-driving/SKILL.md; then
  echo "FAIL: panel prose still embedded in a driving skill"; exit 1; fi
grep -q adversarial-panel-review clavity-dotnet/plugin/skills/clavity-ls-driving/SKILL.md && \
grep -q adversarial-panel-review clavity-classic/plugin/skills/clavity-driving/SKILL.md && echo "OK: both driving skills thinned + point at panel skill"
```

- [ ] **Step 4: No stub links remain — HARD FAIL if any (INCLUDING the `.rs` doc-comment)**

The Task-5 repoint touches `clavity-classic/src/membus.rs` (a `.rs` file), so the gate must scan `.rs` too — an md-only grep would false-GREEN a botched membus edit (panel R3).

```bash
# Markdown links to the deleted stubs
if grep -rnE '\]\((\.\./)*docs/agy-(assumptions|capabilities)\.md\)' clavity-classic clavity-dotnet --include='*.md' | grep -v 'docs/superpowers/'; then
  echo "FAIL: a stub .md link survives"; exit 1; fi
# Rust doc-comment refs to the OLD stub path (must now point at ../../agy-autotrain/knowledge/)
if grep -rnE 'docs/agy-(assumptions|capabilities)\.md' clavity-classic/src --include='*.rs'; then
  echo "FAIL: a stub ref survives in a .rs doc-comment"; exit 1; fi
echo "OK: no stub links remain (md + rs)"
```

- [ ] **Step 5: agy-autotrain is a coherent AUTO plugin (data untouched this phase)**

```bash
grep -rnE 'skills/adversarial-panel-review|agy-after-reminder' agy-autotrain/ | grep -v CHANGELOG && { echo "FAIL: agy-autotrain still claims moved artifacts"; exit 1; } || echo "OK"
grep -c 'agy-learn-reminder' agy-autotrain/hooks/hooks.json   # expected: 2
grep -E '"version": "0.1.4"' agy-autotrain/plugin.json agy-autotrain/.claude-plugin/plugin.json   # both bumped
ls agy-autotrain/knowledge/   # expected: ALL 4 files still present (data move is Phase 3)
ls seed 2>/dev/null && { echo "FAIL: seed/ created — that is Phase 3"; exit 1; } || echo "OK: no seed/ this phase"
```

- [ ] **Step 6: Marketplace-DISCOVERY check — MANUAL / CONTROLLER handoff (NOT a subagent shell step)**

The moved skill/hook must actually be *discovered*, not merely present (this session showed a file-present-but-unloaded gap because the harness loads from the installed Programs copy, not the repo). This check requires the user-facing `/reload-plugins` slash command, which a subagent CANNOT execute (a subagent has only shell tools; it would fail, hallucinate success, or stall). So the executing subagent must STOP here and report `MANUAL_VERIFY_REQUIRED: reload-plugins + confirm discovery` rather than attempting to run it. The controller/human then runs `/reload-plugins` (or the environment's plugin-reload) and confirms `adversarial-panel-review` appears in the clavity-dotnet plugin's available-skills list and the AGY-AFTER PostToolUse hook is registered. If the harness loads plugins from an installed copy rather than the repo working tree, the controller performs the dev-deploy (mirror the change into the loaded copy) before confirming. Do NOT mark discovery verified on file-existence alone.

- [ ] **Step 7: Repo-wide lint gate**

Run: `just lint` and `bash scripts/check-seed-artifacts-synced.sh` — both green (docs/plugin-only change must not break the linters).

- [ ] **Step 8: No commit** — report the acceptance results; if all green, Phase 2 is complete.

---

## Self-review notes (controller)

- **Spec coverage (Phase-2 scope):** agent-artifact extraction + delivery via driver plugins → Tasks 1–2; thin driving skills → Tasks 3–4; Phase-1 deferred fork-repoint → Task 5. De-transport (F1) → Task 1 Step 1.
- **Explicitly Phase-3 (NOT gaps):** the DATA move (manuals + golden-header → `seed/`), the installer seeding of `%USERPROFILE%\.clavity\`, agy-curate's shared-path resolution, and Acceptance #1 ("no-agy-autotrain driver has the manual"). Also Phase-3: the second repoint hop (`agy-autotrain/knowledge/` → `seed/`).
- **Deferred by scope (B2):** classic installer/data staging + classic golden-header injection parity — the definite next phase; the next public release is gated on it (failover must not ship un-seeded).
- **Execution robustness (panel R3):** tasks are NOT re-run-idempotent — a `git mv`/`git rm` re-run after a partial failure fails "bad source". On a BLOCKED/failed re-dispatch, reset the workspace to the task's start (`git checkout -- .`, or `git reset --hard <task-start-sha>` if a partial commit landed) BEFORE retrying. Also: the sync-check (Task 2) verifies *sameness*, not *correctness* — two identically-wrong copies pass it; correctness is caught by Task 6 Step 2's transport grep, so keep both gates.
- **Panel R3 folds applied:** discovery check reframed as a manual/controller handoff (subagents can't run `/reload-plugins`); acceptance gate Step 4 now also scans `.rs` (was md-only → would false-GREEN a botched membus edit); skill-collision severity corrected (namespaced-shadow likely, hard-reject UNVERIFIED → verify at discovery + release-order mitigation).
- **Panel R1 folds applied:** F1 de-transport (Task 1.1); mkdir for the plugin hooks dir (Task 1.2 — the `seed/` mkdir is gone with the deferred data move); exact per-file repoint paths (Task 5 table); JSON-value negative sync-check (Task 2.5); hard-fail acceptance greps (Task 6); marketplace-discovery check (Task 6.6); version-skew transition note (Task 1.6).
