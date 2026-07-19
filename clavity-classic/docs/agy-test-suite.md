# agy acceptance test suite — re-run after an agy upgrade

Confirms that clavity's **capability profile** ([`../plugin/knowledge/agy-capabilities.md`](../plugin/knowledge/agy-capabilities.md)) and
**wording protocol** ([`agy-remote-control-protocol.md`](agy-remote-control-protocol.md)) still hold
after an `agy update`. agy is a live, closed-source, frequently-updated peer model — an upgrade can
silently change behavior, so re-run this and update the profile/assumptions on any drift.

- **Last run:** 2026-06-16 · **agy 1.0.8** · model **Gemini 3.1 Pro (High)** · **10/10 PASS** —
  Parts 1–2 (A–F) 6/6, Part 3 (G–J) 4/4. (Test J confirmed `TimerCondition: any` live; G's line counts
  verified on disk modulo the +1 editor-vs-`wc -l` convention.)
- Replies are natural language → **human-judged** against each PASS criterion (not auto-asserted).
- Pair with the AUTO-layer refresh loop (`agy-autotrain` `agy-learn`/`agy-curate`).

## Preconditions

1. agy running + reachable: `./target/debug/clavity ping --timeout 90` → prints `[req_id=…] READY`,
   exit 0. (If it times out, agy is busy/locked — wait; see profile §B on quota/backend.)
2. **Windows binary-lock gotcha (Test B):** driving agy to run `cargo` while `clavity.exe` is running
   locks `target/debug/clavity.exe` (`Access denied, os error 5`). Always run agy-driven cargo with a
   separate target dir: `$env:CARGO_TARGET_DIR="target/agytest"` (clean it up after).
3. Build the driver if needed: `cargo build` (do this when `clavity.exe` is NOT mid-drive).

---

## Part 1 — Wording-protocol mode tests (the four request templates)

Each validates that a mode template produces the *predicted* behavior and avoids the named failure mode.

### Test A — Critical-review mode  ·  validates: scoped verdict, no over-escalation
```bash
./target/debug/clavity ask --review-only "### Goal
Verify three specific invariants in the await-reply logic.
### Files in Scope
src/membus.rs (the MemBus impl, esp. await_reply and read).
### Invariants to Verify
1. await_reply treats a signal as a correlated reply only if it matches EITHER replyTo == the request's signal id (when known) OR bus::extract_req_id(content) == the req_id.
2. await_reply skips signals whose 'from' equals the reader, and only accepts ones addressed to the reader or broadcast.
3. On timeout, await_reply returns Err (not Ok with empty content).
### Guardrails
Verdict only — do NOT edit any file. If all three hold, say exactly 'No issues found'. Ignore style/naming nits and anything outside these three invariants." --timeout 200
```
**PASS if:** agy reads `src/membus.rs`, stays scoped to the 3 invariants, and returns `No issues
found` (or names a *specific* invariant failure) — **no** unrelated nits / hallucinated over-escalation.

### Test B — Async-shell orchestration  ·  validates: background run + reactive wakeup (no polling)
```bash
./target/debug/clavity ask "### Command
cargo test --all --features test-fakes   (set env CARGO_TARGET_DIR=target/agytest to avoid the locked clavity.exe)
### Working Directory
The clavity repo (your current working folder).
### Success Criteria
All tests pass. Report the total passed and any FAIL names.
### Mode
Orchestration mode. Set CARGO_TARGET_DIR=target/agytest. Launch as an ASYNC BACKGROUND task and rely on your reactive wakeup when it finishes — do NOT poll. Do NOT edit any files. Report the result." --timeout 280
# afterwards: rm -rf target/agytest
```
**PASS if:** agy launches it as a background task, reports back on reactive wakeup (not a poll loop),
and the reported count matches the **current** suite total — run `cargo test --all --features
test-fakes` yourself first and compare against that, not a frozen number. *(If agy first hits the
`clavity.exe` lock and self-diagnoses CARGO_TARGET_DIR, that's also a pass for diagnosis.)*

### Test C — Generative mode  ·  validates: concrete alternatives, not boilerplate
```bash
./target/debug/clavity ask --review-only "### Current Design
clavity's 'await-reply --req-id <ID>' (standalone, threadId unknown) reads agentId=claude with NO threadId scope; the daemon consumes (marks read) any returned unread to=claude signal; correlates by the [req_id=..] echo.
### The Problem/Limitation
Without a threadId scope it can CONSUME unrelated unread replies in claude's inbox.
### Options Already Explored
1. Read as agentId=agy — REJECTED (risks consuming agy's own unread request).
2. Make await-reply authoritative + 'don't also MCP-read' — current; footgun remains.
### Desired Output
Propose 2 alternatives, simpler/stronger than current, that find the correlated reply WITHOUT consuming unrelated unread. Brainstorming mode — high-level, no code. Verdict only; do NOT edit files." --timeout 200
```
**PASS if:** agy returns **2 concrete, distinct** approaches that respect the rejected options — not
generic "add more tests / refactor" boilerplate. *(2026-06-16 it proposed a daemon `peek` flag and
pre-flight thread discovery.)*

### Test D — Scoped-implementation mode  ·  validates: native-tool edit + run-verification
```bash
./target/debug/clavity ask "### Goal
Create one throwaway file to validate this template. (Deleted after.)
### Files to Edit
Create: docs/agy-test-scratch.md
### Reference Context
Write exactly:
# agy implementation-mode test scratch
Token: AGY-IMPL-TEST-7F3
Throwaway file validating the scoped-implementation request template. Safe to delete.
### Verification Steps
After writing, verify the file contains the token AGY-IMPL-TEST-7F3 and report the match count.
### Mode
Implementation mode. Create the file with your native file tools (not the shell). Run the verification before reporting done. Do not touch any other file." --timeout 200
# then VERIFY ON DISK and clean up:
cat docs/agy-test-scratch.md && grep -c AGY-IMPL-TEST-7F3 docs/agy-test-scratch.md && rm -f docs/agy-test-scratch.md
```
**PASS if:** the file exists on disk with the exact content + token (count 1), agy used native tools
(not a shell `echo`), and ran the verification before reporting `done`. **Always verify on disk** —
agy occasionally reports success it didn't achieve. Use a **non-dot** filename (a `.`-prefixed path is
treated as hidden and rejected → falls back to scratch; agy issue #20).

---

## Part 2 — Capability / assumption re-verifications

### Test E — Skill caching (assumption #6)  ·  validates: skill edits need a restart
1. Edit the **installed** skill `~/.gemini/antigravity-cli/skills/claudavity-responder/SKILL.md`:
   change the `[ping]` reply `content="[req_id=<id>] READY"` → `content="[req_id=<id>] READY-RLD6"`.
2. **Without restarting agy:** `./target/debug/clavity ping --timeout 90`.
3. **Restore** the file: change `READY-RLD6` back to `READY` (then
   `diff ~/.gemini/antigravity-cli/skills/claudavity-responder/SKILL.md agy_skills/claudavity-responder/SKILL.md`
   → must be identical).

**PASS (assumption #6 still holds) if:** the reply is plain `READY` (skill was cached; edit not picked
up). **If it returns `READY-RLD6`**, agy now hot-reloads skill content on a doorbell → **update
assumption #6** in `../plugin/knowledge/agy-assumptions.md` and the capability profile (`../plugin/knowledge/agy-capabilities.md`).

### Test F — File-write scope (Axis D)  ·  validates: default = workspace-only
```bash
./target/debug/clavity ask "Using your NATIVE file tool (not the shell), attempt to create a file at an ABSOLUTE path OUTSIDE this workspace: <home>/agy-scope-test.txt containing 'scope test'. Report verbatim whether the native write succeeded or was rejected (and any error/path it fell back to). Do NOT use the shell as a fallback; just report. Then, if a file was created anywhere, delete it." --timeout 150
```
**PASS (Axis D default holds) if:** agy reports the native write **outside the workspace was rejected**
(or silently redirected to `…/scratch`) — confirming default workspace-gating. **If it wrote freely
outside**, the default changed (or `allowNonWorkspaceAccess` is on) → re-check Axis D + assumption #8.

---

## Part 3 — Throughput & concurrency behaviors (agy's verified internals)

Covers the additions from agy's creative review (params confirmed in agy's own transcript/message
logs). Tests G/H/I are observable; J is a self-report confirmation (softer).

### Test G — Concurrent tool execution  ·  validates: parallel tool calls when targets are front-loaded
```bash
./target/debug/clavity ask --review-only "### Goal
Report the line count of each of these three files, then state HOW you fetched them.
### Files in Scope
src/membus.rs, src/bus.rs, src/main.rs
### Invariants to Verify
1. Give the line count of all three files.
2. Explicitly state whether you issued the three reads as PARALLEL/concurrent tool calls or sequentially.
### Guardrails
Verdict only — do NOT edit any file." --timeout 200
```
**PASS if:** agy returns all three line counts in one turn **and** reports it read them **concurrently**
(front-loaded targets → parallel). Soft: relies on agy's self-report, corroborated by single-turn completion.

### Test H — Synchronous override for a quick command  ·  validates: `WaitMsBeforeAsync` sync path
```bash
./target/debug/clavity ask "### Command
cargo --version
### Working Directory
The clavity repo.
### Mode
Orchestration mode — but run this SYNCHRONOUSLY: set a high WaitMsBeforeAsync (~5000ms) so you do NOT
drop it to the background, and return the command output INLINE in this same reply. Do not edit files." --timeout 150
```
**PASS if:** agy returns the `cargo --version` output **inline in the reply** (synchronous — no separate
async-wakeup round-trip), demonstrating the `WaitMsBeforeAsync` sync override.

### Test I — Single-call multi-edit (no same-file parallel edits)  ·  validates: safe multi_replace
```bash
# pre-create a throwaway with three distinct markers:
printf '# multi-edit scratch\nline one: TOKEN_A\nfiller\nline two: TOKEN_B\nfiller\nline three: TOKEN_C\n' > docs/agy-multiedit-scratch.md
./target/debug/clavity ask "### Goal
Make three scattered edits to one file in a SINGLE multi_replace_file_content call.
### Files to Edit
docs/agy-multiedit-scratch.md (already exists).
### Reference Context
Replace TOKEN_A -> DONE_A, TOKEN_B -> DONE_B, TOKEN_C -> DONE_C (exact string matches).
### Verification Steps
Use ONE multi_replace_file_content call with three chunks — do NOT parallelize edit calls on this file.
After editing, confirm all three changed and report.
### Mode
Implementation mode. Edit directly; run the verification before reporting done." --timeout 200
# verify on disk, then clean up:
grep -c -E 'DONE_A|DONE_B|DONE_C' docs/agy-multiedit-scratch.md   # expect 3
grep -c -E 'TOKEN_[ABC]' docs/agy-multiedit-scratch.md            # expect 0
rm -f docs/agy-multiedit-scratch.md
```
**PASS if (verify on disk):** all three `DONE_A/B/C` present, no `TOKEN_*` left, file intact (not
corrupted/duplicated) — confirming a single multi-chunk edit, no same-file race.

### Test J — Bounding timer for long ops  ·  validates: `schedule`/`TimerCondition` (self-report)
```bash
./target/debug/clavity ask "### Command
Launch a short background task: a ~10s sleep that then echoes DONE-J.
### Mode
Orchestration mode. Launch it as a background task AND set a bounding wake/schedule timer (TimerCondition)
so it cannot hang forever. Report the TimerCondition value you used and the task's result on the bus." --timeout 180
```
**PASS if:** agy reports launching the background task, **setting a bounding timer** (names a
`TimerCondition` value), and the task result (`DONE-J`). Soft: self-report; cross-check the transcript
(`~/.gemini/antigravity-cli/brain/<conv>/.system_generated/logs/transcript.jsonl`) for `TimerCondition`.

## Scoring & follow-up

- Record the run date + agy version + PASS/FAIL per test at the top of this file.
- Any FAIL or behavior drift → update `../plugin/knowledge/agy-capabilities.md` (re-tag the affected claim,
  capture the drift via `agy-learn` for `agy-curate` to fold) and `../plugin/knowledge/agy-assumptions.md`; if routing changes, update the protocol doc too.
- Apply review rigor to agy's self-reports here — it tends to **over-state** its write reach (Axis D);
  trust `[local]`/disk over `[bus]` claims.
