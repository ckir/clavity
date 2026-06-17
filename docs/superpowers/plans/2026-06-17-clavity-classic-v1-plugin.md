# clavity-classic — v1 Plugin Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Package clavity **v1** (the Rust psmux+bus remote-control) as `clavity-classic`, a universal dual-plugin (installable by both `claude plugin install` and `agy plugin install`) that ships the two skills + both manifests + a README, with the binary delivered via `cargo install --git`.

**Architecture:** A skills-only plugin directory (`plugins/clavity-classic/`) — no MCP server, no bundled binary. The agy-side `claudavity-responder` skill is copied verbatim from the `v1` branch; the Claude-side `clavity-driving` skill is a focused distillation of v1's protocol runbook; both hosts' manifests coexist via disjoint filenames. v1's code stays frozen.

**Tech Stack:** Markdown skills, JSON manifests. No build/test toolchain (content packaging). Validation via `python`/`json` parse + the two CLIs' `plugin install`.

**Spec:** `docs/superpowers/specs/2026-06-17-clavity-classic-v1-plugin-design.md`

**Source note:** v1 content lives on the **`v1` git branch** (not the working tree), so the responder skill is pulled with `git show v1:<path>`.

---

## File Structure

| Path | Responsibility |
|---|---|
| `plugins/clavity-classic/.claude-plugin/plugin.json` | Claude Code manifest (name/version/description) |
| `plugins/clavity-classic/plugin.json` | Antigravity manifest (same fields; disjoint filename) |
| `plugins/clavity-classic/skills/claudavity-responder/SKILL.md` | agy responder — copied verbatim from `v1` |
| `plugins/clavity-classic/skills/clavity-driving/SKILL.md` | Claude driving protocol — distilled from v1 |
| `plugins/clavity-classic/README.md` | prerequisites, install, the lock caveat + recovery, platforms |

---

## Task 1: Scaffold the plugin + manifests + copy the responder skill

**Files:**
- Create: `plugins/clavity-classic/.claude-plugin/plugin.json`, `plugins/clavity-classic/plugin.json`, `plugins/clavity-classic/skills/claudavity-responder/SKILL.md`

- [ ] **Step 1: Verify state**

Run: `git rev-parse --abbrev-ref HEAD` (any branch is fine for this packaging work) and confirm the v1 source exists:
Run: `git cat-file -e v1:agy_skills/claudavity-responder/SKILL.md && echo OK`
Expected: prints `OK`. If it errors, STOP and report `STATE_MISMATCH: v1 responder skill not found`.

- [ ] **Step 2: Write the Claude manifest**

`plugins/clavity-classic/.claude-plugin/plugin.json`:
```json
{
  "name": "clavity-classic",
  "version": "0.1.0",
  "description": "clavity v1: Claude drives a live agy peer via a psmux doorbell + the agentmemory bus."
}
```

- [ ] **Step 3: Write the agy manifest** (same fields; disjoint filename → coexists in one dir)

`plugins/clavity-classic/plugin.json`:
```json
{
  "name": "clavity-classic",
  "version": "0.1.0",
  "description": "clavity v1: Claude drives a live agy peer via a psmux doorbell + the agentmemory bus."
}
```

- [ ] **Step 4: Copy the responder skill VERBATIM from the v1 branch**

Run (PowerShell), creating the dir then writing the file from the v1 branch:
```
New-Item -ItemType Directory -Force plugins/clavity-classic/skills/claudavity-responder | Out-Null
git show v1:agy_skills/claudavity-responder/SKILL.md | Set-Content -Encoding utf8 plugins/clavity-classic/skills/claudavity-responder/SKILL.md
```
Then verify it is non-empty and starts with frontmatter:
Run: `Get-Content plugins/clavity-classic/skills/claudavity-responder/SKILL.md -TotalCount 3`
Expected: the first line is `---` (YAML frontmatter). Do NOT edit the content — it ships verbatim.

- [ ] **Step 5: Validate the manifests parse**

Run: `uv run python -c "import json; [json.load(open(f,encoding='utf-8')) for f in ['plugins/clavity-classic/.claude-plugin/plugin.json','plugins/clavity-classic/plugin.json']]; print('json ok')"`
Expected: `json ok`.

- [ ] **Step 6: Commit**

```bash
git add plugins/clavity-classic/.claude-plugin plugins/clavity-classic/plugin.json plugins/clavity-classic/skills/claudavity-responder
git commit -m "feat(clavity-classic): manifests + responder skill (copied from v1)"
```

---

## Task 2: Author the Claude-side `clavity-driving` skill

**Files:**
- Create: `plugins/clavity-classic/skills/clavity-driving/SKILL.md`

- [ ] **Step 1: Write the driving skill** (distilled from v1's `docs/agy-remote-control-protocol.md`)

`plugins/clavity-classic/skills/clavity-driving/SKILL.md`:
```markdown
---
name: clavity-driving
description: Use to drive a live agy peer via the clavity CLI — readiness ping, request shaping, per-mode templates, and cancel/recover.
---

# Driving agy with clavity (v1)

Claude drives a live, signed-in `agy` peer in the same folder. Payloads travel over the
**agentmemory signal bus** (your `memory_signal_send` / `memory_signal_read` tools); the
**doorbell** (`clavity ring`) wakes agy. The `clavity` binary provides the psmux/state
plumbing + the `[req_id]` convention. **Correctness rests on the bus, not the TUI** — a
state misread only affects ordering (a doorbell sent while agy is busy is queued).

## 0. Readiness — gate first contact
- `clavity state` → expect `idle`/`busy` (not `dead`; if `dead`, ask the human to start agy).
- agy loads its MCP servers (agentmemory) a few seconds AFTER launch, so its idle prompt can
  appear before the bus is up. Gate first contact on a bus round-trip:
  `clavity ping`  (sends `[ping]` + ring + blocks for `READY`; exit 0 = agy + bus live).

## 1. One-shot round-trip
`clavity ask "<instruction>"` mints a req-id, posts to the bus, rings, blocks for agy's
correlated reply, and prints it. Add `--review-only` for a no-edit / consult ask.

## 2. Route by capability
agy is an external, multi-model peer — treat picking it like choosing a subagent tier. Route
TO agy for an independent second-model perspective (divergent review, design input, async
orchestration). KEEP on Claude mechanical sweeps / well-specified implementation. Pick the
model for the task (`--model`): deep reasoning → a Thinking/High model; bulk → Flash Low/Med.

## 3. Request shape — DO
- Lead with an imperative goal; list the exact file paths in scope; give a Definition of Done /
  how to verify; state guardrails ("Do NOT modify X").
- Carry your own context — separate context windows; paste the relevant trace/snippet/types.
- Front-load ALL targets (agy parallelizes tool calls in a turn); for review-only say
  "Just REPLY on the bus — do NOT write or edit files."

## 4. Request shape — AVOID
- Vague scope ("fix the bug") — give the error/trace or the precise mismatch.
- **Line numbers** — agy's edits need exact string matches; target function names / snippets.
- Interactive confirmations — agy replies only when done or blocked.
- Parallel edit calls to the SAME file (they race and corrupt) — tell agy to use ONE
  multi-chunk edit call instead.

## 5. Per-mode templates
- **Review / red-team:** "Just REPLY — do NOT edit." Sections: `### Goal` · `### Files in Scope`
  · `### Invariants to Verify` · `### Guardrails`. Give invariants to check, not "find bugs".
- **Generative design:** "Brainstorming mode. No implementation code." Sections: `### Current
  Design` · `### Problem` · `### Options Explored` · `### Desired Output`.
- **Scoped implementation:** "Implementation mode. Edit files; run the verification before
  reporting done." Sections: `### Goal` · `### Files to Edit` · `### Reference Context` ·
  `### Verification`.
- **Async orchestration:** "Orchestration mode. Launch the background task and await your
  reactive wakeup; do not poll." Sections: `### Command` · `### Working Directory` ·
  `### Success Criteria`.

## 6. Clarify / cancel / recover
- agy reads the bus only at the START of a turn — it can't ingest new instructions mid-turn.
  To pivot: `clavity cancel` (Escape) + an `alert` `[req_id=…] cancel`, let it idle, then resend.
- **If a terminal locks** (the raw-mode `tmux attach` watch tab), run `clavity cancel` — or any
  `clavity` command — from a DIFFERENT, non-attached shell to drive/unstick agy. Prefer running
  with `AGY_WATCH=0` and observing via `clavity capture` to avoid the lock entirely.
```

- [ ] **Step 2: Validate the skill frontmatter**

Run: `Get-Content plugins/clavity-classic/skills/clavity-driving/SKILL.md -TotalCount 4`
Expected: line 1 is `---`, line 2 starts `name: clavity-driving`.

- [ ] **Step 3: Commit**

```bash
git add plugins/clavity-classic/skills/clavity-driving
git commit -m "feat(clavity-classic): Claude-side clavity-driving skill (distilled from v1)"
```

---

## Task 3: Author the README

**Files:**
- Create: `plugins/clavity-classic/README.md`

- [ ] **Step 1: Write the README**

`plugins/clavity-classic/README.md`:
```markdown
# clavity-classic (universal dual-plugin) — v1 live-agy remote control

Packages clavity **v1**: Claude drives a live, signed-in **agy** peer in the same folder over a
**psmux doorbell** + the **agentmemory bus**. Installs in BOTH Claude Code and Antigravity from
one directory.

> **Most users want clavity v2 instead** — it is spawn-on-demand and **lock-free**. Use
> clavity-classic only if you specifically want to drive a *persistent live* agy session and
> accept the keyboard-lock trade-off below.

## Prerequisites (out-of-band — an advanced power-user workflow)
1. **The `clavity` binary** (builds for your platform from the v1 branch):
   `cargo install --git https://github.com/ckir/clavity --branch v1`
2. **psmux** (`psmux` / `pmux` / `tmux`) on your PATH.
3. **agentmemory** MCP server configured in BOTH Claude Code and agy (the shared bus).

## Install (both CLIs, one directory)

    claude plugin install ./plugins/clavity-classic
    agy    plugin install ./plugins/clavity-classic

## Use
Start agy + Claude in a folder (`clavity start <folder>`), then ask Claude to drive agy — it uses
the bundled **clavity-driving** skill (`clavity ping` for readiness, `clavity ask "…"` for a
round-trip). agy uses the bundled **claudavity-responder** skill to react to the doorbell and
reply on the bus.

## ⚠️ Keyboard lock — read this
clavity v1's auto-attached "watch tab" runs an **interactive `tmux attach`**, which puts YOUR
terminal into raw mode (no echo) — your keystrokes get swallowed by agy, a "keyboard lock". A
hard-kill of agy leaves psmux redrawing escape sequences to the attached terminal. To avoid it:
- **Run with `AGY_WATCH=0`** (no auto-attach). Observe agy with `clavity capture`; `tmux attach
  -t claude_agy` MANUALLY only to answer an auth prompt, then detach (`Ctrl-b d`).
- **Recovery if locked:** from a DIFFERENT (non-attached) shell, run `clavity cancel` (sends
  Escape to agy). The send-keys path reaches agy through the psmux server even when your client
  terminal is raw-mode-locked.
- For a fully lock-free experience, use **clavity v2**.

## Platforms
Windows: ✅ verified end-to-end. Linux: 🚧 compiles in CI, runtime unverified. macOS: 🚧 unverified.

## Contents
- `skills/claudavity-responder/` — agy-side responder (reacts to the doorbell, replies on the bus)
- `skills/clavity-driving/` — Claude-side driving protocol
- `.claude-plugin/plugin.json` + `plugin.json` — Claude + agy manifests
```

- [ ] **Step 2: Commit**

```bash
git add plugins/clavity-classic/README.md
git commit -m "docs(clavity-classic): README (prereqs, install, keyboard-lock caveat + recovery)"
```

---

## Task 4: Packaging acceptance

**Files:** none (validation + a manual install runbook).

- [ ] **Step 1: Confirm the full tree**

Run (PowerShell): `Get-ChildItem -Recurse plugins/clavity-classic | ForEach-Object FullName`
Expected exactly these files:
```
plugins/clavity-classic/.claude-plugin/plugin.json
plugins/clavity-classic/plugin.json
plugins/clavity-classic/README.md
plugins/clavity-classic/skills/claudavity-responder/SKILL.md
plugins/clavity-classic/skills/clavity-driving/SKILL.md
```

- [ ] **Step 2: Validate all JSON parses**

Run: `uv run python -c "import json,glob; [json.load(open(f,encoding='utf-8')) for f in glob.glob('plugins/clavity-classic/**/*.json', recursive=True)]; print('json ok')"`
Expected: `json ok`.

- [ ] **Step 3: Confirm both skills have valid frontmatter**

Run: `uv run python -c "import pathlib; [print(p, pathlib.Path(p).read_text(encoding='utf-8').startswith('---')) for p in ['plugins/clavity-classic/skills/claudavity-responder/SKILL.md','plugins/clavity-classic/skills/clavity-driving/SKILL.md']]"`
Expected: both print `True`.

- [ ] **Step 4: Manual install acceptance (runbook — record results)**

```
claude plugin install ./plugins/clavity-classic    # accepted; both skills discoverable
agy    plugin install ./plugins/clavity-classic    # accepted; claudavity-responder discoverable
```
Confirm each CLI accepts the install and lists the skills. (Full driving — `clavity ask` round-trip —
additionally needs the v1 binary + psmux + agentmemory per the README; that is v1's existing live
runbook, not re-tested here.)

- [ ] **Step 5: Commit any recorded notes (if a NOTES/results file was added); otherwise nothing to commit**

If Step 4 surfaced a fix (e.g. a manifest field a CLI rejects), apply it, re-validate (Steps 1–2),
and commit:
```bash
git add -A
git commit -m "fix(clavity-classic): adjust manifest per live plugin-install acceptance"
```

---

## Self-Review

**Spec coverage:** §2 D1 skills-only / D3 name → Tasks 1–3; §4.1 responder copied verbatim → Task 1
Step 4; §4.2 driving skill distilled → Task 2; §5 prereqs + §3 lock caveat + recovery + §7 platforms
→ Task 3 README; §6 install → Task 3 + Task 4; §8 packaging acceptance → Task 4. **D2** (`cargo
install --git` delivery) is documentation-only and lands in the README (Task 3) — no build step, by
design. **D4** (v1 frozen) is honored — no task touches v1's code; the responder ships verbatim.

**Placeholder scan:** none — every file's full content is inline; the responder is a verbatim
`git show` copy (its content is the v1 artifact, intentionally not duplicated here).

**Type consistency:** the plugin name `clavity-classic` and version `0.1.0` match across both
manifests (Task 1) and the README (Task 3); skill `name:` values (`clavity-driving`) match their
directory names; all file paths match the File Structure table and the Task-4 tree check.
