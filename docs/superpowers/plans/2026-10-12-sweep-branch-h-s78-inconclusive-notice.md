# Branch H, section 78: the consult guard says NOT VERIFIED on an unfinished consult - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the post hook runs for an `agy_ask` that has NOT finished (the harness backgrounded it at 120 s, or `clavity-ls` returned early with `[PEER STILL BUSY]`), it stops reading as "verified clean": it says NOT VERIFIED, and the four review skills tell the peer to build only OUTSIDE the repository.

**Architecture:** The post hook's one existing `jq` call also classifies the payload's `tool_response` into `peer-busy`, `backgrounded`, `long` or empty; the clean branch emits a notice when the class is non-empty, and the breach branch appends a caveat. The four review skills (identical in both plugins) gain one sentence, and the skills linter gains a rule that pins it. No late diff is built: `PostToolUse` fires once, not again at completion (measured).

**Tech Stack:** bash 3.2+ hooks with jq; PowerShell 7 + Pester 6 suites; the repo `justfile` gates.

**Spec:** `clavity-dotnet/ROADMAP.md` entry `### §78` (the `MEASURED 2026-10-12` blocks and the `OWNER RULING 2026-10-12`: H + F) and the Branch H paragraph of `docs/superpowers/specs/2026-10-08-final-sweep-sequence-design.md`.

## Global Constraints

- The three guard hooks are BYTE-IDENTICAL in `clavity-dotnet/plugin/hooks/` and `clavity-classic/plugin/hooks/` (pinned by `agy-consult-guard.Tests.ps1` row `is byte-identical to the clavity-classic mirror`). Edit the dotnet file, then `cp` it over the classic one. Likewise the four SKILL.md files are byte-identical across `clavity-dotnet/plugin/skills/` and `clavity-classic/plugin/skills/`.
- Hooks are fail-open and read-only: they never revert, stage or block. Hook text is pure ASCII (pinned by row `ships as pure ASCII`).
- A message string in the hook sits inside bash double quotes: use no backticks and no `$`.
- Process budget: the consult path is pinned by `$script:ConsultPin` (`hook-spawn-budget.Rows.ps1:12`, `PostMcp = 114`), NOT by the generic `$script:HookCeiling = 13` (line 6) that other hooks use - the existing consult rows pass `-Max $script:ConsultPin.PostMcp` (line 153). The inconclusive path may cost exactly ONE process more than that pin (the `jq -nc` inside `emit`); every other path costs the same as today.
- No manual plugin version bump (the release bumps it). Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- The hook-spawn-budget suite measures through a Windows Job Object and cannot run on Linux; Task 2's row is written here and verified on Windows or by the Linux proxy below, and the plan says which.
- Out of scope, recorded in Task 4: the Bash/CLI consult path (classic's `clavity ask`) was never measured, and the harness's backgrounding text is a Claude Code string that can change.

## Review Focus

- A peer reply that merely QUOTES `[PEER STILL BUSY]` or the harness phrase inside its answer must not raise the notice (the match is per content block, not over the whole text).
- An unfinished consult whose VCS state ALSO changed must show the breach alarm and the not-finished caveat together, alarm first; one must never replace the other.
- If the harness rewords its backgrounding message, `duration_ms >= 120000` on an `agy_ask` still raises the notice, worded as a possibility (`long`), never as the fact the harness did something.
- The driver's own `tool_input` message may quote the markers; only `tool_response` blocks are classified (row 5b).
- A `PostToolUse` payload with no `tool_response`, one shaped differently (a Bash object, a plain string), or with a malformed block (a non-string `text`, a null block) stays silent about the new notice, never errors, and never costs the guard its tool, cwd or session (a jq error would blank all of them); the existing rows that send payloads without `tool_response` stay green.
- The bash 3.2 read path (`CLAVITY_HOOK_BASH3=1`) and the no-jq branch behave exactly as before; the no-jq branch does not classify (it already announces that the consult was not checked).

## Before execution (the sequence spec's rules, not optional)

Re-measure at start (the item reproduces today: ROADMAP `### §78` MEASURED blocks, 2026-10-12). The dry run by a fresh executor in a throwaway worktree HAS BEEN DONE (see the Dry-run record below); its findings are folded. A final review of the folded plan by the owner comes before Task 1 starts. Branch H ends with a capstone and a test-audit once §70, §75 and §80 are also built; this plan is the §78 portion only.

## File Structure

- `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` (modify) and its classic mirror (copy): the classification and the two emissions.
- `scripts/tests/agy-consult-guard.Tests.ps1` (modify): the `Payload` helper at line 30 and the new rows.
- `scripts/tests/hook-spawn-budget.Rows.ps1` (modify): `New-ToolPayload` (line 83) and one new row beside line 148.
- `clavity-dotnet/plugin/skills/{agy-first,agy-capstone,agy-test-audit,adversarial-panel-review}/SKILL.md` (modify) and the four classic copies.
- `scripts/check-agy-discipline-skills.ps1` (modify: one rule after the `sanctioned scratch directory` rule at line 375) and `scripts/tests/check-agy-discipline-skills.Tests.ps1` (modify: rows beside line 947).
- `clavity-dotnet/ROADMAP.md` (modify: §78 status, new §85).

---

### Task 1: The post hook classifies an unfinished consult and says so

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh` (the jq read at lines 55-57; the clean branch at lines 141-147; the breach message at line 181)
- Copy to: `clavity-classic/plugin/hooks/agy-consult-guard-post.sh`
- Test: `scripts/tests/agy-consult-guard.Tests.ps1`

**Interfaces:**
- Consumes: `agy_guard_have_hash`, `agy_guard_quad` (lib, unchanged), `emit "<text>"` (post hook line 49, one `jq -nc`).
- Produces: a shell variable `inc` set from the payload to exactly one of `peer-busy`, `backgrounded`, `long`, or empty; the notice text below, which Task 2's row and Task 4's docs refer to by the phrase `consult not finished`.

**Classification program (verified 2026-10-12 against the two real captured payloads, six controls, and malformed shapes; do not loosen it).** It replaces the single `jq -j` program at line 56; the first four output fields keep their order and values, the fifth is `$inc`. Every classification step is wrapped in `try`/`tostring` because the plain form was MEASURED to fail on a block whose `text` is not a string (`jq: error: startswith() requires string inputs`), and a jq error prints NOTHING, which would blank tool, cwd and session too and make the guard drop the consult silently - worse than today:

```
(.tool_name // "") as $tn
| (try (.tool_response | if type == "array" then map(if type == "object" then ((.text // "") | tostring) else "" end) else [] end) catch []) as $blocks
| (try (if ($tn | endswith("agy_ask")) then
     (if any($blocks[]; startswith("[PEER STILL BUSY]")) then "peer-busy"
      elif any($blocks[]; startswith("MCP tool ") and contains("moved to the background")) then "backgrounded"
      elif (((.duration_ms // 0) | tonumber? // 0) >= 120000) then "long"
      else "" end)
   else "" end) catch "") as $inc
| $tn, "\u0000", (.tool_input.command? // ""), "\u0000", (.cwd // "."), "\u0000", (.session_id // "default"), "\u0000", $inc, "\u0000"
```

Why block-level `startswith`: the reply JSON (block 0) holds the peer's whole answer, so a substring match would fire on a peer that quotes the marker; the driver's own `[PEER STILL BUSY]` notice is a separate block that STARTS with it, and the harness message is a whole block that starts `MCP tool `.

**The notice** (one `emit`, ASCII, no backticks, no `$`). `<reason>` is `agy ended its turn while background work was still running (the driver returned PEER STILL BUSY)` for `peer-busy`, `the harness moved the call to the background after 120 s while the peer was still working` for `backgrounded`, and `the call ran for 120 s or more, the point at which the harness moves a call to the background, so it may have been backgrounded while the peer was still working` for `long` (duration alone, with no recognisable harness text - the program must not assert as fact what only the clock shows):

(The leading `> ` below is plan markup; do not put it in the hook.)

> AGY CONSULT GUARD - NOT VERIFIED (consult not finished): this agy_ask returned before the peer finished - `<reason>`. The version-control check ran NOW and cannot see anything the peer does afterwards, so a clean result here means only 'nothing so far'. Treat this consult as UNCHECKED until it really ends: run git status --short now (or use the snapshot you took before asking), run it again when the task-completion notification or the result arrives, treat anything new in between as suspect, and do not revert anything you did not verify the peer made.

- [ ] **Step 1: Record the baseline.** Run `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Files scripts/tests/agy-consult-guard.Tests.ps1 -ShowMessages`. Expected: the suite's existing Linux failures only (2026-10-12: 1 row; write its name down). Everything below must leave that set unchanged.

- [ ] **Step 2: Extend the `Payload` helper (`agy-consult-guard.Tests.ps1:30`)** with two optional parameters, `[object[]]$Response` and `[int]$DurationMs`; when given, add `tool_response = $Response` and `duration_ms = $DurationMs` to the hashtable it already serialises. Add two literals in `BeforeAll`, copied from the 2026-10-12 captures:
  - `$script:BusyResponse` = two text blocks: block 0 `{"CascadeId":"c","Answer":"The command has been launched in the background. Waiting for it to finish...","PeerStillBusy":true}`; block 1 starting `[PEER STILL BUSY] agy's turn ended`.
  - `$script:BackgroundedResponse` = one text block `MCP tool "plugin:clavity:clavity-ls/agy_ask" is still running after 120s. It was moved to the background as task kxiidbwop and keeps running; you''ll receive a notification with the result when it completes.` (inside a single-quoted PowerShell string the apostrophe is doubled, so the literal stays verbatim)

- [ ] **Step 3: Write the failing rows** (each uses `New-GuardRepo`, `Invoke-BashHook` for Pre then Post, and removes the repo in `finally`, like the row at line 79). With the mcp tool name `mcp__plugin_clavity_clavity-ls__agy_ask`:
  1. `NOT-VERIFIED notice on an early PEER STILL BUSY return when nothing changed`: Post payload with `-Response $script:BusyResponse -DurationMs 78377`; stdout matches `NOT VERIFIED \(consult not finished\)` and `PEER STILL BUSY`; does not match `VERSION CONTROL CHANGED`.
  2. `NOT-VERIFIED notice when the harness backgrounded the call`: `-Response $script:BackgroundedResponse -DurationMs 120005`; matches `consult not finished` and `moved the call to the background`.
  3. `notice still fires on duration alone if the harness rewords its message`: a one-block response `some future harness wording`, `-DurationMs 120005`; matches `consult not finished` and `may have been backgrounded`, and does not match `the harness moved the call`.
  4. `is SILENT on a normal return` (distractor): the Busy response's block 0 only, with `"PeerStillBusy":false`, `-DurationMs 40000`; stdout is empty.
  5. `is SILENT when the peer's ANSWER merely quotes the markers` (distractor): one block whose JSON text contains `the [PEER STILL BUSY] marker` and `moved to the background`, `-DurationMs 40000`; stdout empty.
  5b. `is SILENT when the driver's own MESSAGE quotes the markers` (distractor for the raw-text trap): a normal one-block response, `-DurationMs 40000`, and `-Cmd '[PEER STILL BUSY] and MCP tool x moved to the background'`; stdout empty.
  6. `shows the alarm AND the caveat when an unfinished consult also changed VCS`: mutate with `Invoke-ConsultAround`'s pattern (commit a file between Pre and Post) with the Busy response; stdout matches `VERSION CONTROL CHANGED`, `consult not finished` and `PEER STILL BUSY` (the reason survived into the caveat), and the first occurrence is the alarm.
  7. `stays silent and does not error without a tool_response, or with a Bash-shaped or string response` (`-ForEach` over exactly these three payloads: no `tool_response` key at all; `tool_response = @{ stdout = 'x'; stderr = '' }`; `tool_response = '[PEER STILL BUSY]'` as a plain string); stdout empty, stderr empty.
  8. `reports BOTH degraded and unfinished in one message`: the temp-copy technique of the row at line 447 (copy the three hooks, force `agy_guard_have_hash() { return 1; }` on the copy only), Busy response, nothing changed; exactly ONE non-empty stdout line, which parses as JSON and whose `additionalContext` matches both `PARTIALLY VERIFIED` and `consult not finished`.
  9. `notice also works on the bash 3.2 read path`: `CLAVITY_HOOK_BASH3 = '1'` via `-Env`, Busy response; matches `consult not finished`.
  10. `a malformed tool_response block does not blind the guard`: a response whose one block has `text = 5` (a number) PLUS a VCS change between Pre and Post; stdout still matches `VERSION CONTROL CHANGED` (cwd and session survived) and the run writes nothing to stderr.

- [ ] **Step 4: Run to verify they fail.** `pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99; Invoke-Pester scripts/tests/agy-consult-guard.Tests.ps1 -Output None -PassThru | % { \"failed=$($_.FailedCount)\" }"`. Expected: rows 1, 2, 3, 6, 8, 9 fail (no notice yet); rows 4, 5, 5b, 7, 10 already pass (distractors and the malformed-shape row, which must keep passing - row 10 only goes red if Step 5 is implemented WITHOUT the try/tostring wrapping).

- [ ] **Step 5: Implement in `agy-consult-guard-post.sh`:** (a) replace the jq program at line 56 with the one above and add `IFS= read -r -d '' inc` as the fifth read at line 55; (b) in the clean branch (line 141, `if [ "$before" = "$after" ]`), build ONE message from the existing degraded text (line 145, unchanged wording, present only when `degraded` is 1) and, when `inc` is non-empty, the notice; join the two with exactly one space when both are present, emit whichever is present unchanged when only one is, and `emit` once if the result is non-empty (with `inc` empty the output is byte-for-byte what it is today); (c) in the breach branch, append to `msg` just before `emit "$msg"` (line 182), when `inc` is non-empty, exactly this text (one leading space, `<reason>` as above): ` ALSO: consult not finished - <reason>; the check above covers only what had changed before the early return, so keep watching until the result arrives.` The breach text itself stays first and unchanged. Add a comment citing ROADMAP section 78 and the 2026-10-12 measurements (the payload shapes and the 78 s / 120005 ms durations). The no-jq branch (lines 33-43) is untouched.

- [ ] **Step 6: Mirror.** `cp clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh clavity-classic/plugin/hooks/agy-consult-guard-post.sh`.

- [ ] **Step 7: Run to verify.** Re-run Step 4's command. Expected: `failed` equals the baseline from Step 1 (the rows named `is byte-identical to the clavity-classic mirror`, `ships as pure ASCII`, `is SILENT across an MCP consult that changed nothing` and the `without jq` rows all pass). Run `bash -n clavity-dotnet/plugin/hooks/agy-consult-guard-post.sh`; expected no output.

- [ ] **Step 8: Mutants (the repo's test-audit habit).** One mutant at a time, never in parallel: the suite hard-codes session id `guardtest` and a shared state directory under `TMPDIR`, so two concurrent runs of it collide (MEASURED 2026-10-12: solo 58 passed / 1 failed, two concurrent runs 57 / 2 each). Before the first mutant copy BOTH hook files to `.clavity/scratch/<topic>/` as backups; for each mutant overwrite the dotnet hook AND its classic mirror with the same mutated text (so the byte-identical row stays out of the result), run the suite, and restore both from the backups (not `git checkout`: the files still carry your uncommitted work). Expected per mutant: the baseline failing row plus the one row named here, nothing else. Mutants: block-level `startswith` replaced by `contains` (row 5); the `duration_ms` clause removed (row 3); the breach-branch append removed (row 6); the degraded concatenation removed (row 8); the `try`/`tostring` wrapping removed from the jq program (row 10).

- [ ] **Step 9: Commit** the hook, its mirror and the test file: `fix(hooks): the consult guard says NOT VERIFIED when the consult has not finished (section 78, H)`.

---

### Task 2: A process-budget row for the inconclusive path

**Files:**
- Modify: `scripts/tests/hook-spawn-budget.Rows.ps1` (`New-ToolPayload` at line 83; a new row after the row at line 148)

**Interfaces:**
- Consumes: Task 1's notice phrase `consult not finished`; `$script:ConsultPin.PostMcp` (line 12, value 114); `$mcp` (the MCP tool name already used at line 149).
- Produces: nothing later tasks use.

- [ ] **Step 1: Extend `New-ToolPayload`** with optional `[object[]]$Response` and `[int]$DurationMs` (added to the hashtable only when supplied; existing callers unchanged).

- [ ] **Step 2: Add the row** `PINNED consult: MCP agy_ask, inconclusive return (after its pre)` beside line 148: same setup as that row but the Post payload carries `-Response @(@{ type = 'text'; text = 'MCP tool "plugin:clavity:clavity-ls/agy_ask" is still running after 120s. It was moved to the background as task t1 and keeps running.' })` (an inline literal: `$script:BackgroundedResponse` lives in the other suite and does not exist in this file) and `-DurationMs 120005`; `-Fixture @{ NoClavity = $true }`; `-Max ($script:ConsultPin.PostMcp + 1)`; `-Expect 'consult not finished'`. The comment states why +1: the `jq -nc` inside `emit`, the only added process.

- [ ] **Step 3: Verify.** On Windows: `Invoke-Pester scripts/tests/hook-spawn-budget.Tests.ps1`; expected the new row green. On Linux the Job Object harness cannot run (all rows fail structurally); use the proxy instead: in a plain temp git repo run the Pre hook, then `strace -ff -e trace=execve -o <dir>/t bash <post hook> < <payload>` for (a) a normal payload and (b) the backgrounded payload, count the lines ending `= 0` across `<dir>/t.*` (one file per process: `-f` into one file drops split lines). Expected: (b) = (a) + 1. If the Windows number differs, adjust the row's `-Max` to the measured value and say so in the commit message.

- [ ] **Step 4: Commit:** `test(hooks): pin the inconclusive-return path of the consult guard at the clean count plus one process`.

---

### Task 3: The review briefs name a build location OUTSIDE the repository (F)

**Files:**
- Modify: the four `SKILL.md` files in `clavity-dotnet/plugin/skills/` (step 4 "Point at files, not summaries": `agy-first` line 93, `agy-capstone` line 116, `agy-test-audit` line 147, `adversarial-panel-review` line 57), then copy each to the matching classic path.
- Modify: `scripts/check-agy-discipline-skills.ps1` (new rule after line 375's `sanctioned scratch directory` rule)
- Test: `scripts/tests/check-agy-discipline-skills.Tests.ps1` (rows beside line 947)
- Modify: `clavity-dotnet/ROADMAP.md` (the section-14 table rows that cite these four skills' line counts and two `agy-capstone` anchors; found in Step 5)

**Interfaces:**
- Consumes: the rule shape used at line 375 (`@{ Name; AppliesTo = { param($ctx, $rule) ... }; Check = { param($ctx, $rule) ... $ctx.Raw ... $ctx.Report("...") } }`).
- Produces: the rule `sanctioned out-of-repository build location`, failing with the text `names no out-of-repository build location`.

**The sentence** (identical in all four, ASCII, inserted directly after the step-4 sentence ending `writes to cwd.`, as continuation text of the numbered step with the same 3-space indent as the lines around it; the leading `> ` below is plan markup and is NOT inserted):

> A named scratch directory does not bind a build's output, which lands in the working directory: any build, compile or throwaway test program the peer must run to measure something goes to a directory OUTSIDE the repository (for example `${TMPDIR:-/tmp}/agy-<topic>/`, named in the payload), and anything it writes inside the repository outside `.clavity/scratch/<topic>/` is a breach. The shipped writer below prepares only the in-repository paths; the out-of-repository directory is the peer's own `mkdir`.

Wrap lines anywhere EXCEPT inside the clause `goes to a directory OUTSIDE the repository`: the linter matches it with a plain `Contains`, so a line break inside it fails the gate. In `agy-first` and `adversarial-panel-review` the step-4 sentence ending `writes to cwd.` is followed on the SAME line by `Prepare that` / `Prepare it`; start the inserted text on a new line and reword those two openers to `Prepare the scratch directory`, so their antecedent is not the out-of-repository path just named. `agy-capstone` and `agy-test-audit` (`Prepare BOTH`) keep their wording; the closing clause above says which paths the writer takes.

- [ ] **Step 1: Write the failing rows:** (a) `REJECTS <skill> when the out-of-repository build location is stripped` for the four skills, in the style of the row at line 947 (stage with `New-ScratchRoot`, strip the clause `goes to a directory OUTSIDE the repository` from the real skill, each row first asserts, as its sibling at line 947 does, `$real.Contains('goes to a directory OUTSIDE the repository') | Should -BeTrue -Because "the fixture needs the clause present in $skill before it can be stripped"`, then strips it, runs the linter, expects exit 1 and `names no out-of-repository build location`); (b) the real skills pass (the existing all-skills-OK row, unchanged, must stay green).

- [ ] **Step 2: Run to verify they fail.** `pwsh -NoProfile -c "Import-Module Pester -MinimumVersion 6.0.0 -MaximumVersion 6.99.99; Invoke-Pester scripts/tests/check-agy-discipline-skills.Tests.ps1 -Output None -PassThru | % { \"failed=$($_.FailedCount)\" }"`. Expected (MEASURED in the 2026-10-12 dry run): the four (a) rows fail at their OWN PRECONDITION (`the fixture needs the clause present in <skill>`), because the skills do not yet carry the sentence; every pre-existing row passes. This red proves the rows cannot pass vacuously; it does NOT yet prove the rule - Step 4b does.

- [ ] **Step 3: Add the rule** in the checker: `AppliesTo` all four disciplines (as the scratch rule at 375); `Check` reports `"$($ctx.Rel) : names no out-of-repository build location - a measure-and-reproduce consult's build would land in the repository"` unless `$ctx.Raw.Contains('goes to a directory OUTSIDE the repository')` (the whole distinctive clause, not a bare phrase a stray comment could satisfy; like the sibling rules it proves PRESENCE, not meaning - the linter's own stated limit).

- [ ] **Step 4: Add the sentence** to the four dotnet skills exactly as specified above (wrapping and the two reworded openers included), then `cp` each to `clavity-classic/plugin/skills/<skill>/SKILL.md`.

- [ ] **Step 4b: Prove the rule, not just the sentence.** Run the four (a) rows: they must now PASS. Then, on a scratch copy of the linter, delete the new rule and confirm all four (a) rows go red (the stripped skill now lints clean, so the expected exit 1 never comes); discard the copy.

- [ ] **Step 5: Run to verify, and repair the claims this edit stales (a BLOCKER the dry run found: the plan used to skip this).** `pwsh -NoProfile -File scripts/check-agy-discipline-skills.ps1` exits 0 and prints `agy-discipline skills OK`; the checker's Pester suite passes (116 rows at the dry run); `scripts/tests/check-injected-context.Tests.ps1` still shows only its 2 Linux-only failures (`The term 'cmd' is not recognized`, already in the 2026-10-12 baseline). THEN run `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1`: adding lines to the four SKILL.md files makes it report STALE line counts for them and two ANCHOR-MISS pointers for `agy-capstone` (at the dry run: 6 false claims, all in the section-14 table around ROADMAP lines 1294-1299). Update each claimed count to the actual one the checker prints, and re-point the two `agy-capstone` anchors (`Seats (defect-class lenses)`, `Rotate seats across rounds`) to the lines where those texts now sit in the edited skill; re-run until it prints OK.

- [ ] **Step 6: Commit** the four dotnet skills, their four classic copies, the checker, its test file and `ROADMAP.md`: `docs(skills): review briefs name a build location outside the repository, and the linter pins it (section 78, F)`.

---

### Task 4: Close out the entry and record what is left

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` (`### §78` status line; a new `### §85` before `## Non-goals / accepted limitations`)

- [ ] **Step 1: §78 status.** Replace the `**Status:**` line with `**Status:** IMPLEMENTED <date> - H and F built on <branch> (`<sha>`)` while unmerged (the sha in BACKTICKS: the gate only reads backticked shas), `SHIPPED` with the merge sha after the merge. Keep every existing `> **Previous status:**` / legacy line; put the line you replaced above them as one more `> **Previous status:**` line.
- [ ] **Step 2: Add `### §85 — The Bash/CLI consult path's unfinished returns are unmeasured, and the harness's backgrounding text can change`** (an em dash, like the neighbouring headings) with exactly this status line: `**Status:** OPEN <date> - the Bash/CLI consult path's unfinished returns were never captured; next step: capture them with the temporary-hook method of section 78's round-2 block`. Body, two short paragraphs: classic's `clavity ask` runs through a Bash tool call whose `tool_response` is an object and whose backgrounding behaviour was never captured, and Task 1 classifies only the MCP path; the harness's backgrounding wording is covered by the `long` class (duration alone) for the MCP path but not for the CLI path.
- [ ] **Step 3: Verify:** `just check-tracker-status` and `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1` both print OK.
- [ ] **Step 4: Full affected run, both lanes** (the guard suite is in the SLOW half, the skills checker suite in the FAST half). `pwsh -NoProfile -File scripts/run-pester-parallel.ps1 -Recipe test-scripts-slow -Exclude hook-spawn-budget -ShowMessages`: expected `files=48 excluded=1`, `failed=83`, `badContainers=19`, `passed=1202` (the 2026-10-12 baseline 1189 plus Task 1's 13 rows; MEASURED in the dry run). `just test-scripts-fast-parallel`: expected `failed=59` and `passed=634` (baseline 630 plus Task 3's 4 rows). Any other change is investigated against the per-suite counts of the 2026-10-12 baseline, not accepted.
- [ ] **Step 5: Commit:** `docs(roadmap): section 78 H and F recorded; section 85 opened for the CLI path`.

## Self-review (run 2026-10-12)

- **Spec coverage:** H (Task 1, 2) and F (Task 3) are the owner ruling's two halves; the ruling's "still to decide at plan time" items are decided here: the notice wording (Task 1), NO open-marker (a later reminder is YAGNI: the hook cannot fire at completion and the next consult takes a fresh baseline), the classic mirror by byte-copy (Global Constraints). The rejected options A to D and E are not built.
- **Type consistency:** `inc` takes the values `peer-busy` / `backgrounded` / `long` / empty in the jq program, the clean branch, the breach branch and the rows; the notice phrase `consult not finished` is the same in Tasks 1, 2 and 4; the checker's failure text is the same in Task 3's rows and rule.
- **Gaps carried, each with where it resolves:** the Windows count for Task 2's row (resolved by the Windows run in Task 2 Step 3); the CLI path (Task 4, §85); the harness wording drift (the `duration_ms` fallback plus §85); `hook-spawn-budget` under parallel load on Windows is §82, unrelated to this plan.
- **Proportion:** the plan carries the one verified jq program and the notice text because the tests do not determine them; all other bodies are left to the executor.

## Panel record (adversarial-panel-review, 2026-10-12; solo seats + one agy round)

Seated: Axiom Breaker, Cascade Analyst, State Corruptor, Boundary Smuggler, Protocol Pedant, Blindspot Auditor, Literal Implementer, Activation Auditor, Mechanism Gamer, Dependency Cynic. Dropped: Resource Vampire (no loops, network or unbounded collections). Every claim below was measured before it was folded; agy's artifact line count (173; actual 172) was wrong.
- `FOLDED:` the jq program wrapped in `try`/`tostring` (solo, Cascade Analyst; MEASURED: the plain form printed nothing on `text: 5`, blanking tool, cwd and session); the notice's remedy rewritten so it does not presuppose a snapshot the driver may not have (solo, Blindspot); the linter needle widened to the whole clause (solo, Mechanism Gamer); the process-budget constraint now names `ConsultPin`, not `HookCeiling` (agy, Axiom Breaker; verified `Rows.ps1:153`); a separate `long` class for a duration-only hit (agy, Protocol Pedant; verified against the real captures and a reworded-text control); the exact breach-branch sentence and the clean-branch join rule (agy, Literal Implementer x2); the inline literal in Task 2 (agy; verified the Rows file cannot see the other suite's variable); the `> ` markup and indentation notes (agy); row 5b (solo, Boundary Smuggler).
- `REJECTED:` "ConvertTo-Json default depth flattens `tool_response`" - measured identical to `-Depth 6` on pwsh 7.6.6.
- Round 2 (agy: fold auditor + false-green hunter; its chat reply ended in a "standing by" wrap-up and the driver rescued the full report from the peer's own reply file; its line count, 191, was again one too many): `FOLDED:` the class roster now agrees in all five places (the Architecture line and the type-consistency line still omitted `long`); row 6 now asserts the reason. Not adopted: placing the breach-branch sentence earlier in the message (it is appended LAST on purpose so the existing breach text, matched by the rows at `agy-consult-guard.Tests.ps1:56-74`, stays byte-identical at the front). Seat B found no surviving false-green in the other twelve rows; the Linux-unobservable step (Task 2 Step 3) is already handled by the `strace -ff` proxy.
- Not adopted: removing Task 1 row 9 (agy, Q2). It is true that `CLAVITY_HOOK_BASH3` governs only the stdin read (`post.sh:19`) and that `hook-spawn-budget.Tests.ps1:74` runs every row on that path - but that suite runs on Windows only, so on the machine that executes this plan row 9 is the only bash 3.2 coverage, and the existing row at `agy-consult-guard.Tests.ps1:142` sets the convention.

## Stand-downs

- `DISCARDED-BELOW-FLOOR: a renamed or missing duration_ms is unreachable as a defect because` the program's `(.duration_ms // 0) | tonumber? // 0` term makes an absent or non-numeric value inert, leaving the text match as the only path (agy Q3, the "least vouched" assumption; a risk, not a defect, and tracked as the harness-drift item in section 85).
- The Activation Auditor reported "no new findings" without having read `hooks.json`; the driver verified both plugins register `Bash|PowerShell|mcp__.*agy_ask` for the post hook (2026-10-12).

## Dry-run record (fresh Sonnet executor, throwaway worktree at ae9d8bb5, 2026-10-12)

Executed all four tasks as written, TDD order, mutants included; the main checkout was never touched (verified: same HEAD, clean tree, same plan hash). 1 blocker, 3 material, 5 minor defects found and folded above. Verified by the driver before folding: the BLOCKER (Task 3 leaves 6 false claims in the ROADMAP section-14 table: four stale line counts, two moved anchors; reproduced by running `check-roadmap-claims.ps1` at the Task 3 commit), the antecedent shift in `agy-first`/`adversarial-panel-review` ("Prepare that directory" now follows the out-of-repository path), the wrong red-state prediction in Task 3 Step 2 (the rows fail at their own precondition), and the "missing 4 passes" (the checker suite is in the fast lane). Everything in Tasks 1 and 2 ran as written; the strace proxy gave +1 process on the inconclusive path (44 -> 45 successful execs). NOT exercised by the dry run, by construction: the Windows Job Object budget row (Task 2 Step 3), and anything on macOS or Windows.

A first attempt used the harness's isolated-worktree option and could not start: that option bases the worktree on the pushed tip (`origin/main`), not on local `HEAD`, so an unpushed plan is invisible to it (captured as a local anomaly). The retry used a worktree created from local `HEAD`.

