# Phase 1 — Agnostic Knowledge Scrub — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `agy-autotrain/knowledge/agy-assumptions.md` + `agy-capabilities.md` **version-agnostic and driver-agnostic** (the SEED's Layer-1 content), reconcile the three-way knowledge fork, and land the removed driver-specific transport mechanics in clavity-classic's own docs.

**Architecture:** Prose refactoring, no code. The two files are rewritten to state only *peer-truth about agy* (what it does, how it behaves, how to work with it) — never *how a clavity variant reaches it* (psmux verbs, the bus REST schema, `agy_ask` MCP, driver CLI names, `src/*.rs` paths) and never *which agy version* (no "verified against 1.0.x" stamps). Driver-specific transport content is relocated to clavity-classic docs (its natural home — nearly all of it is classic psmux/bus). The stale clavity-classic forks of these two files (verified this session to hold nothing but old stamps) are retired.

**Tech Stack:** Markdown; POSIX shell for verification greps.

**Source spec (READ FIRST):** `docs/superpowers/specs/2026-07-10-agy-autotrain-seed-and-auto-split-design.md` — Component 1 (SEED, driver-agnostic + version-agnostic) and Phasing item 1.

**Shell convention (MANDATORY):** every snippet runs in the **Bash tool (Git Bash / POSIX sh)**, NOT PowerShell.

**Verified repo facts (2026-07-10):**
- Canonical base = `agy-autotrain/knowledge/agy-assumptions.md` (164 lines) + `agy-capabilities.md` (168 lines) — newest/fullest (has the A1–A5 driving-protocol section; stamped 1.0.10).
- Stale forks to retire = `clavity-classic/docs/agy-assumptions.md` (129 lines) + `agy-capabilities.md` (163 lines). Diff-verified: classic-only lines are **just** the old `1.0.8`/`2026-06-16` stamps — nothing substantive unique.
- `clavity-dotnet` has **no** `docs/` dir; the dotnet transport (`agy_ask` MCP) is barely present in these files. Relocation target for driver-specific transport = **clavity-classic** docs.
- 3 companion docs exist only in `clavity-classic/docs/`: `agy-capabilities-research.md`, `agy-remote-control-protocol.md`, `agy-test-suite.md` (not forks).

**Scope note:** Phase 1 leaves the scrubbed files IN `agy-autotrain/knowledge/` (made agnostic). Physically moving them into the driver as the seed is **Phase 2** (out of scope here).

---

## Categorization contract — every section's disposition

**`agy-assumptions.md`:**
| Section (current) | Disposition |
|---|---|
| Header/intro (L1–16) | **KEEP**, scrub the "clavity depends on / psmux" framing + drop the §G/1.0.8 cross-reference |
| `## Verified against` (L17–24) | **DROP** (pure version stamps) |
| `## Quick re-verification playbook` (L26–34) | **RELOCATE** → classic (uses `clavity doctor/capture/ring`) |
| Assumptions #1 headless-print-hangs, #5 shell=pwsh, #6 skill-cache, #8 workspace-only-writes, #9 keyring-auth | **KEEP** (agnostic peer facts) — scrub the driver-fix column + version stamps |
| Assumptions #2 psmux-verbs, #3 footer-markers, #4 cancel-key, #7 send-keys-queued, #10 bus, #11 psmux-session-lifecycle, #12 closing-tab, #13 bus-daemon-REST | **RELOCATE** → classic (all psmux/bus transport) |
| `### Note on #6` (L53–61) | **KEEP** the agnostic fact (agy caches skills per session), drop the version stamp + the classic `[ping]`/responder test |
| `### How await-reply/ask read` (L63–79) | **RELOCATE** → classic (bus read-state mechanics) |
| `## Driving-protocol A1–A5` (L81–99) | **KEEP** (agnostic peer behavior) — drop the version stamp + the `../verify/` link |
| `### Failure modes / anti-patterns` (L101–113) | **KEEP** (agnostic) |
| `## Transient runtime gotchas` (L115–149) | **SPLIT**: KEEP backend-overload + cwd-relative-file-reads (agnostic); RELOCATE the agentmemory-daemon-flap bullet (bus) → classic |
| `## All the knobs` (L151–157) | **RELOCATE** → classic (`AGY_*` env, `src/*.rs`) |
| `## Deferred / known gaps` (L159–164) | **KEEP** the agnostic gaps; RELOCATE bus-auth/multi-folder (classic) |

**`agy-capabilities.md`:**
| Section (current) | Disposition |
|---|---|
| Header (L1–15) | **KEEP**, drop "Verified against 1.0.8" + the concrete active-model line |
| `## A. Strengths` (L16–45) | **KEEP** (agnostic; agy-native tool names like `/agent`,`multi_replace_file_content` are agy features, not driver transport — allowed) |
| `## B. Weaknesses` (L47–69) | **KEEP** (agnostic) |
| `## C. Reasoning profile & model selection` (L71–86) | **PRINCIPLE-ONLY**: keep "route by task shape (deep-reasoning vs cheap-parallel vs cheap-second-opinion)"; DROP the concrete versioned model table + benchmarks |
| `## D. Operational reach` (L88–107) | **KEEP** (agnostic: shell=pwsh, path-agnostic writes, agy-native MCP/subagents) |
| `## E. Control surface` (L109–121) | **KEEP**, drop version-tagged claims |
| `## F. Routing` (L123–138) | **KEEP** the principles; genericize any concrete model names |
| `## G. Version & drift` (L140–152) | **DROP** (pure version content) |
| `## Refresh after an agy update` (L154–168) | **REPLACE** with a one-line pointer: refreshing is the AUTO layer's job (observe → capture → curate), not a manual version chase |

---

## Task 1: Create the classic transport doc + relocate driver-specific content out of `agy-assumptions.md`

**Files:**
- Create: `clavity-classic/docs/agy-classic-transport.md`
- Modify: `agy-autotrain/knowledge/agy-assumptions.md`

- [ ] **Step 1: State-verification.**
```bash
head -1 agy-autotrain/knowledge/agy-assumptions.md
grep -qE '^## Driving-protocol assumptions' agy-autotrain/knowledge/agy-assumptions.md && echo "OK A1-A5 present" || echo "STATE_MISMATCH"
test ! -e clavity-classic/docs/agy-classic-transport.md && echo "OK dest absent" || echo "STATE_MISMATCH: dest exists"
```
Expected: title line, "OK A1-A5 present", "OK dest absent". Any mismatch → STOP, report.

- [ ] **Step 2: Create `clavity-classic/docs/agy-classic-transport.md`** and move into it (verbatim, then lightly reframed as classic-transport reference) every RELOCATE row from the assumptions contract: the re-verification playbook; assumptions #2/#3/#4/#7/#10/#11/#12/#13; the `### How await-reply/ask read` section; the daemon-flap gotcha; the knobs section; the bus-auth/multi-folder deferred gaps. Give it a header noting it is the **classic (psmux/bus) transport manual**, the driver-specific companion to the agnostic `agy-autotrain/knowledge/` manual.

- [ ] **Step 3: Delete those same relocated blocks from `agy-assumptions.md`.** Leave the KEEP rows.

- [ ] **Step 4: Verify the relocation is complete + lossless.**
```bash
A=agy-autotrain/knowledge/agy-assumptions.md; C=clavity-classic/docs/agy-classic-transport.md
# driver-specific transport terms must be GONE from the agnostic file:
grep -niE 'psmux|send-keys|capture-pane|footer marker|AGY_[A-Z]|src/(tmux|bus|membus|main|platform)\.rs|clavity (doctor|capture|ring|state|cancel|await-reply|ping)|127\.0\.0\.1:3111|agentmemory (bus|daemon)|memory_signal' "$A" && echo "FAIL: transport left in agnostic file" || echo "OK agnostic file has no transport"
# and PRESENT in the classic doc (spot-check):
for k in psmux 'send-keys' 'AGY_IDLE_MARKER' '127.0.0.1:3111'; do grep -qF "$k" "$C" && echo "OK relocated: $k" || echo "MISSING in classic doc: $k"; done
```
Expected: "OK agnostic file has no transport" + all "OK relocated".

- [ ] **Step 5: No commit yet** (Task 2 finishes the assumptions scrub; single commit at Task 2 Step 4).

---

## Task 2: Scrub `agy-assumptions.md` to agnostic (drop version stamps; agnostic peer-truth only)

**Files:** Modify `agy-autotrain/knowledge/agy-assumptions.md`

- [ ] **Step 1: Drop the `## Verified against` section and every version stamp / date** across the file. Rewrite the KEEP assumptions (#1,#5,#6,#8,#9) and A1–A5 so each states the *agy behavior* + *how to re-verify by observation* — no "verified against 1.0.x", no `../verify/` link, no clavity-variant fix column (that moved to classic).
- [ ] **Step 2: Rewrite the intro** to frame the file as the **agnostic agy manual** (peer-truth, version-independent — we cannot detect agy's version, so we assume stable behavior and refresh empirically), dropping the "clavity depends on / psmux" framing.
- [ ] **Step 3: Verify agnostic + no version stamps.**
```bash
A=agy-autotrain/knowledge/agy-assumptions.md
grep -niE '1\.0\.[0-9]+|verified against|2026-06|agentmemory 0\.9|psmux 3\.' "$A" && echo "FAIL: version/tool-version stamp remains" || echo "OK version-agnostic"
for k in 'REVIEW-ONLY' 'verifies' 'workspace' 'PowerShell'; do grep -qiF "$k" "$A" && echo "OK kept: $k" || echo "LOST agnostic content: $k"; done
```
Expected: "OK version-agnostic" + all "OK kept".
- [ ] **Step 4: Commit** (assumptions + the new classic transport doc together).
```bash
git add agy-autotrain/knowledge/agy-assumptions.md clavity-classic/docs/agy-classic-transport.md
git commit -m "refactor(agy-autotrain): make agy-assumptions.md agnostic; relocate classic transport to clavity-classic/docs"
```

---

## Task 3: Scrub `agy-capabilities.md` to agnostic (drop version section + model lineup)

**Files:** Modify `agy-autotrain/knowledge/agy-capabilities.md`

- [ ] **Step 1: Apply the capabilities contract** — drop `## G. Version & drift` and the header version stamp; reduce `## C.` to principle-only routing (no versioned model table/benchmarks); replace `## Refresh after an agy update` with a one-line pointer that refreshing is the AUTO layer's job (observe→capture→curate), not a version chase. Keep A/B/D/E/F as agnostic peer-truth.
- [ ] **Step 2: Verify.**
```bash
C=agy-autotrain/knowledge/agy-capabilities.md
grep -niE '1\.0\.[0-9]+|verified against|Gemini 3\.|Sonnet 4\.|Opus 4\.|GPT-OSS|ARC-AGI|## G\. Version' "$C" && echo "FAIL: version/model-lineup remains" || echo "OK version-agnostic"
for k in 'verifies far better than it discovers' 'over-escalation' 'route by' 'second-model'; do grep -qiF "$k" "$C" && echo "OK kept: $k" || echo "LOST: $k"; done
```
Expected: "OK version-agnostic" + all "OK kept".
- [ ] **Step 3: Commit.**
```bash
git add agy-autotrain/knowledge/agy-capabilities.md
git commit -m "refactor(agy-autotrain): make agy-capabilities.md agnostic (drop version section + model lineup → principle-only routing)"
```

---

## Task 4: Retire the stale classic forks + resolve the 3 companion docs

**Files:** Delete `clavity-classic/docs/agy-assumptions.md`, `clavity-classic/docs/agy-capabilities.md`; assess the 3 companions.

- [ ] **Step 1: Re-confirm the forks hold nothing unique** (guard against drift since planning).
```bash
diff agy-autotrain/knowledge/agy-assumptions.md clavity-classic/docs/agy-assumptions.md | grep '^>' | grep -viE '1\.0\.8|2026-06-16' && echo "FAIL: fork has unique content — STOP" || echo "OK assumptions fork stale-only"
diff agy-autotrain/knowledge/agy-capabilities.md clavity-classic/docs/agy-capabilities.md | grep '^>' | grep -viE '1\.0\.8|2026-06' && echo "FAIL: fork has unique content — STOP" || echo "OK capabilities fork stale-only"
```
Expected: both "OK …stale-only". Any FAIL → STOP and surface the unique content (do not delete).

- [ ] **Step 2: Delete the two stale forks + repoint any references.**
```bash
grep -rln 'docs/agy-assumptions\.md\|docs/agy-capabilities\.md' clavity-classic 2>/dev/null   # find referrers first
git rm clavity-classic/docs/agy-assumptions.md clavity-classic/docs/agy-capabilities.md
```
Repoint any referrer (a `clavity-classic/CLAUDE.md` or README link) to the agnostic `agy-autotrain/knowledge/` manual + the new `agy-classic-transport.md`.

- [ ] **Step 3: Resolve the 3 companion docs.** For `agy-capabilities-research.md`, `agy-remote-control-protocol.md`, `agy-test-suite.md`: keep in `clavity-classic/docs/` as classic reference for now (out of Phase 1's agnostic-scrub scope), but fix any links that pointed at the deleted forks. Do NOT fold them into the seed here — that is a later phase decision.

- [ ] **Step 4: Commit.**
```bash
git add -A clavity-classic/
git commit -m "chore(clavity-classic): retire stale agy-knowledge forks (superseded by agnostic agy-autotrain manual + classic-transport doc)"
```

---

## Task 5: Final agnostic-fidelity gate

**Files:** none (verification).

- [ ] **Step 1: Whole-Phase verification.**
```bash
for F in agy-autotrain/knowledge/agy-assumptions.md agy-autotrain/knowledge/agy-capabilities.md; do
  echo "== $F =="
  grep -niE '1\.0\.[0-9]+|verified against|2026-0|Gemini 3\.|Sonnet 4\.|Opus 4\.|GPT-OSS|psmux|send-keys|capture-pane|AGY_[A-Z]|src/[a-z]+\.rs|127\.0\.0\.1:3111|memory_signal|agy_ask|clavity-ls' "$F" && echo "FAIL: non-agnostic content in $F" || echo "OK fully agnostic: $F"
done
test -f clavity-classic/docs/agy-classic-transport.md && echo "OK classic transport doc exists" || echo "FAIL missing classic doc"
test ! -e clavity-classic/docs/agy-assumptions.md && echo "OK old fork gone" || echo "FAIL fork remains"
```
Expected: "OK fully agnostic" for both, "OK classic transport doc exists", "OK old fork gone".

- [ ] **Step 2: No commit** (verification only).

---

## Self-review (author)

- **Spec coverage:** Component-1 driver-agnostic + version-agnostic seed content → Tasks 2–3; relocation of transport mechanics to driver docs → Task 1; the fork reconciliation the spec's Phase 1 didn't foresee (discovered 2026-07-10) → Tasks 1+4.
- **Plan-vs-spec:** every section citation + line range grep-verified against the current files 2026-07-10; the fork's "nothing-unique" claim diff-verified (Task 4 Step 1 re-guards it at execution).
- **Not in Phase 1:** physically moving the seed into the driver package (Phase 2); the `adversarial-panel-review`/AGY-AFTER relocation (Phase 2); curate-extend regions (Phase 3). Phase 1 only makes the knowledge agnostic + de-forks it in place.
- **Execution:** Tasks 1–4 are subagent-implementable prose edits with grep oracles; the controller runs the two-stage review between tasks. Feature work ⇒ do it on a branch off `main`.
