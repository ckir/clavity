# Direct-driver anomaly capture + invocation-path-independent inbox snapshot — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Close ROADMAP §0 step 1b (no hook prompts a driver working directly to capture an anomaly) and the
`inbox-snapshot-misses-slash-command-path` backlog entry, both by registering `UserPromptSubmit` and doing
the discrimination **inside the script**.

**Architecture:** One newly-established hook contract serves both items. `UserPromptSubmit` is registered
**bare** — no `matcher` key — in two different plugins, and each hook decides for itself whether to act:
the capture reminder gates on a once-per-session debounce that skips the first prompt; the inbox snapshot
gates on the prompt text naming its slash command. Neither depends on a declarative matcher, because the
matcher contract for this event **is not established** (§ "What was measured").

**Tech Stack:** bash hooks (POSIX-ish, fail-open, zero-subprocess), `hooks.json` manifests, Pester 5 tests.

---

## What was measured before this plan was written

Every claim below was checked against a file in this repo or on this machine. Nothing here is inferred from
the backlog entry's own text, which is where two of these went wrong.

1. **`UserPromptSubmit` is a real, registrable event.** It appears in the hook-event enum in
   `~/.claude/plugins/cache/ecc/ecc/2.0.0/schemas/hooks.schema.json`, and two first-party plugins register
   it: `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/hookify/hooks/hooks.json` and
   `.../security-guidance/hooks/hooks.json`.
2. 🔴 **Both first-party registrations are BARE — neither carries a `matcher` key.** The schema permits
   `matcher` on any entry syntactically, but nothing establishes that it is evaluated **against prompt
   text** for this event. **The backlog entry's preferred mitigation 2 — `"matcher": "^/agy-autotrain:agy-curate\b"`
   — is therefore NOT safe to build on**, exactly as
   `docs/superpowers/specs/2026-08-06-open-work-reconsideration-design.md:295-304` warned. Both first-party
   plugins pass the payload to a script and inspect the prompt there. **This plan does the same.**
3. 🔴 **The backlog entry's mitigation 1 is architecturally wrong and this plan does NOT implement it.**
   It says to snapshot "inside `curate-commit`". `curate-commit` is not an agy-autotrain script — it is a
   **driver CLI verb implemented twice**, at `clavity-dotnet/src/Clavity.Ls/CliVerbs.cs:36` and
   `clavity-classic/src/main.rs:700`. Its doc comment (`CliVerbs.cs:8-14`) shows it reads the compiled
   golden-header from stdin and writes the GROWTH region in a dir resolved from `CLAVITY_GOLDEN_HEADER`.
   **It has no knowledge of the inbox at all.** Implementing mitigation 1 would make the clavity driver
   binary, in two languages, depend on the *agy-autotrain plugin's* file layout
   (`${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md`) — a cross-plugin coupling between two
   independently installed plugins. The entry did not notice this; it is why mitigation 2 wins here.
4. **Envelope shape is event-specific and getting it wrong is silent.**
   `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh:9-15` records a three-arm sentinel
   measurement: plain stdout at exit 0 reaches the model **not at all**, and `hookSpecificOutput` is
   **invalid** for `PreCompact`. Every other shipped hook in this repo uses
   `hookSpecificOutput{hookEventName:"<Event>",additionalContext:...}` (`agy-seam-inject.sh:61`,
   `agy-after-reminder.sh:45`, `agy-anomaly-dispatch-reminder.sh:75`). **The `UserPromptSubmit` arm has not
   been measured on this machine, so Task 0 measures it before anything is built on it.**
5. **The write-side axiom does NOT forbid the debounce marker this plan adds.**
   `docs/agy-disciplines-marker-contract.md` states "The hook never writes the `.head` marker", and gives
   the reason: *a PreToolUse hook fires before the consult and cannot know its outcome.* That axiom is
   scoped to `.head` **discipline** markers and its reason does not apply to a hook recording a fact it
   does know (that it already emitted this session). **Constraints this plan imposes to keep the
   distinction sharp are in Task 2, Step 3.**
6. **Baseline registrations, read today.** `clavity-dotnet/plugin/hooks/hooks.json` is 68 lines with
   `PreToolUse` / `PostToolUse` / `SessionStart` / `PreCompact` and **no `UserPromptSubmit`**.
   `agy-autotrain/hooks/hooks.json` is 18 lines with `PreToolUse` / `SessionStart` / `PreCompact` and **no
   `UserPromptSubmit`**.

### Accepted limitation, stated rather than discovered later

**A session containing exactly one user prompt is structurally unreachable by this mechanism.** The gate
deliberately does not fire on the first prompt, because at that moment the driver has done no work and can
have observed nothing — prompting there produces the reflexive "none" answer that
`docs/superpowers/specs/2026-08-04-agy-anomaly-capture-gap-design.md:65,:67` records as worse than no prompt.
The only events that land *after* work in a one-prompt session are `Stop` (withdrawn, `:65`) and
`SessionEnd` (measured dead: `${CLAUDE_PLUGIN_ROOT}` does not resolve there, cancelled 3/3 —
`clavity-dotnet/ROADMAP.md:315-321`). **This is a real coverage hole and it is accepted, not closed.**

---

## File structure

| File | Change | Responsibility |
|---|---|---|
| `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh` | Modify | Becomes event-aware: two messages, two envelopes, one gate |
| `clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh` | Modify | **Byte-identical mirror.** Non-negotiable |
| `clavity-dotnet/plugin/hooks/hooks.json` | Modify | Register `UserPromptSubmit` bare |
| `clavity-classic/plugin/hooks/hooks.json` | Modify | Same |
| `agy-autotrain/hooks/agy-inbox-snapshot.sh` | Modify | Accept a second invocation path; match prompt text in-script |
| `agy-autotrain/hooks/hooks.json` | Modify | Register `UserPromptSubmit` bare |
| `scripts/tests/BashHookHelpers.ps1` | Modify | `Invoke-BashHook` gains `-Arguments` (shared infrastructure) |
| `scripts/tests/BashHookHelpers.Tests.ps1` | Modify | Pin the new parameter and its default |
| `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1` | Modify | Pin both messages, both envelopes, the gate |
| `scripts/tests/plugin-hooks-registration.Tests.ps1` | Modify | Pin the new registration — **using `Get-OwningGroupCount`** |
| `scripts/tests/agy-inbox-snapshot.Tests.ps1` | Modify | Pin the slash-command path |
| `agy-autotrain/docs/fix-the-tool-backlog/inbox-snapshot-misses-slash-command-path.md` | Modify | Status + the two corrections above |
| `clavity-dotnet/ROADMAP.md` | Modify | §0 step 1b status |

---

## Panel ledger — folded before this plan was presented

Round 1 (solo panel + agy escalation) produced eight findings. All were verified by measurement before
folding; the disposition of each is recorded so a later reader does not re-derive them.

| # | Finding | Disposition |
|---|---|---|
| AB-1 | The gate reads `session_id` from a payload never verified to carry it; if absent the hook ships inert | **FOLDED** — Task 0 Step 1 dumps the payload, Step 5 is a hard `STATE_MISMATCH` stop |
| CA-1 | Unchecked marker write: an unwritable temp silences the reminder for the whole session, silently | **FOLDED, then CORRECTED in round 3** — the first fold fell through to emit, which fires on *every* prompt for the rest of the session: a silent failure traded for a noisy one. Now falls back to a second location, and warns on stderr while staying silent to the model if both fail. *Found independently by both panels; the bad fix was caught by probing agy's GREEN* |
| LI-1 | Task 1/4 tests invoked `bash` directly, bypassing the `HOME` isolation every existing test uses | **FOLDED** — both rewritten onto `Invoke-BashHook` + `New-CleanHome` |
| LI-2 | `Invoke-BashHook` has no way to pass `$1`, which Task 1 requires | **FOLDED** — new Task 0.5 adds `-Arguments` with its own control test |
| MG-1 | `$script:ObsDir` does not exist; the negative control would have passed unconditionally | **FOLDED** — rewritten onto `New-PluginRoot`/`BakCount`, plus a `CLAUDE_PLUGIN_ROOT` warning |
| MG-2 | Task 1 Step 7's control expected one red test; two go red because the markers are coupled | **FOLDED** — both named explicitly; a third failure is now the stop condition |
| AA-1 | A bare registration spawns bash on every prompt for every user, cost never measured | **FOLDED** — Task 0 Step 6 measures it; stated as a number to the owner, not a gate |
| AX-1 | *(raised by agy)* This plan's "correction" of `ROADMAP.md:299-300` was itself wrong | **FOLDED — the correction was REVERTED.** agy was right; re-measured with `awk` line numbers. See the note in Task 5 |

Round 4 — run because the CA-1 correction was itself unreviewed code — produced four more. **The
round-after-a-fold was again the highest-yield round.**

| # | Finding | Disposition |
|---|---|---|
| SC-1 | The ledger justified skipping marker cleanup as "OS temp reaping handles it", but the new fallback writes to `$HOME/.clavity-tmp`, where **no reaper runs** — unbounded growth on any machine with a broken `TMPDIR` | **FOLDED** — a `find -mtime +7 -delete` prune runs once per session on the first prompt only. *The fix invalidated its own justification; that is what the round caught* |
| BS-1 | `sid` is captured as `[^"]*` and concatenated into a path, so `/` or `..` in a session id escapes the marker directory | **FOLDED** — sanitized to `[A-Za-z0-9_-]`, with two tests including a traversal attempt |
| LI-3 | The Step 4 bash block could not run as written and emitted on prompt 1, inverting the gate; it shipped with a note telling the engineer to restructure it, beside a SHAPE-DIVERGENCE warning telling them not to improvise | **FOLDED** — the gate is now written correctly as a loop; the contradictory note is gone |
| LI-4 | `NAME THE ORACLE` still named a **deleted** test and asserted the **opposite** trade from the one the code now implements | **FOLDED** — re-pointed at the two replacement tests. *A textbook incomplete fold* |

Round 5 returned an all-seats-clean GREEN. **It was probed rather than banked** — four numbered
quote-the-line questions plus three trace questions — and the probe produced two more findings, from the
same reply that had just declared the artifact clean. This is the second time in this review that probing a
clean verdict found a real defect.

| # | Finding | Disposition |
|---|---|---|
| RV-2 | `-mtime +7` deletes the markers of a session still OPEN longer than the window, from a different session, making it emit twice | **FOLDED** — window widened to `+30`, with the reason stated in the code |
| MG-3 | The traversal test checked one guessed directory, without `-Recurse` — an escape to any other level would pass unnoticed | **FOLDED** — replaced with an exhaustive `$TestDrive` sweep asserting every marker found sits in the resolved dir, plus a non-vacuity guard |

**Round 6 — GREEN.** All three seats clean on the round-5 fixes, and unlike the earlier clean verdicts this
one **demonstrated the read in the same reply**: asked to quote the `find` line and the non-vacuity guard
verbatim, it returned both exactly, at the correct line numbers, and correctly described what removing the
guard would do. That is the difference between a verdict and a concession.

**Not folded, recorded instead:** when **no** marker location is writable the stderr warning repeats each
turn. There is no state available to debounce it — that is the failure being reported — and stderr is not
the model's context, so it costs the operator a repeated line rather than training a reflex. Accepted.

### Round 7 — found at EXECUTION time, by tracing the tests against the code. Two were BLOCKING.

Round 6 declared GREEN. These were found immediately afterwards, while preparing the Task 1 dispatch, by
running the premise the tests rest on instead of reading them. **Six panel rounds missed all three.**

| # | Finding | Disposition |
|---|---|---|
| EX-1 | 🔴 **BLOCKING.** Both fallback tests set the "unwritable" location to a merely NONEXISTENT nested path — but the gate's own `mkdir -p` CREATES it. MEASURED: `mkdir -p ./definitely-not-a-directory/nested` succeeds and the marker write succeeds. So `falls back to a second marker location` passed **vacuously** (it re-tested the ordinary path), and `warns on stderr and stays SILENT` **fails against correct code** — no warning is ever emitted. Under NAME THE ORACLE ("the tests win") an implementer would have been sent to break working code | **FOLDED** — both now block with a regular FILE as a parent component (`mkdir -p` then fails ENOTDIR, measured) |
| EX-2 | 🔴 **BLOCKING.** Step 7's mutation instruction named an `if [ ! -f "$seen" ]` / `else` block that **does not exist** — LI-3 rewrote the gate as a loop in round 4 and Step 7 was never re-derived | **FOLDED** — rewritten with the correct mutation, plus a note on why deleting the `exit 0` outright produces silence rather than the needed emission |
| EX-3 | Step 7 demanded "**EXACTLY TWO** tests red" and made a third a hard stop. That count predates rounds 4-5, which added six more gate tests; the true blast radius is seven, because the markers are coupled | **FOLDED** — the must-fail control is now named singly, the collateral is a prediction to confirm rather than a count to match, and the stop condition is named as four specific gate-independent tests |

Three more followed, found the same way — by executing the plan rather than reading it:

| # | Finding | Disposition |
|---|---|---|
| EX-4 | 🔴 **The test helpers could never have been called.** `New-GateEnv` and `Invoke-Prompt` were bare `function` statements in the `Describe` body. In Pester 5 a function declared there is visible only during the DISCOVERY pass and is gone by RUN — every `It` calling them threw `CommandNotFoundException` unconditionally, whatever the hook did | **FOLDED** — both bodies moved byte-identically into `BeforeAll`, which is where this very file already keeps `New-CleanHome`/`New-Workspace`/`Payload`. The plan cited that harness and still got the placement wrong |
| EX-5 | 🔴 **Round 5's own fix (MG-3) created this.** The exhaustive `Get-ChildItem -Path $TestDrive -Recurse` sweep is cross-test contaminated: `$TestDrive` is per-CONTAINER, not per-`It`, and the gate tests never clean up. The test passes ALONE and fails after its 8 siblings, tripping on a sibling's own CORRECT marker | **FOLDED** — one `AfterEach` clearing `$TestDrive`. Exhaustiveness preserved, non-vacuity guard still bites |
| EX-6 | Task 3 Step 6 demanded "**Two** tests must go red". Same stale-count class as EX-3: written before the `passes the event name as an argument` test existed, whose regex requires a literal `agy-anomaly-capture-reminder\.sh` and so also fails under the typo. The true count is three | **FOLDED** — three named, the must-fire control identified, the typo scoped to the dotnet manifest, and a red `classic` variant made the stop condition |

**What this round is evidence of.** The two clean verdicts that were *probed* both broke (rounds 2 and 5) —
and now the round-6 GREEN broke too, under a probe the panel format cannot perform: **executing the
premise.** All three findings live in the plan's VERIFICATION steps, not its implementation steps, which is
where five of the previous fourteen also lived. A panel reasons over the artifact; it never runs it.

### What this ledger is evidence of

Six rounds, **14 findings folded**. The distribution is the point, and it is worth carrying into the next
plan:

- **The two clean verdicts that were probed both broke.** Rounds 2 and 5 returned all-seats-GREEN; probing
  them with numbered quote-the-line questions produced CA-1's bad fix and then RV-2 + MG-3. A clean round
  that cites nothing is not yet a verdict.
- **The round after a fold was twice the highest-yield round.** Round 4 (after round 2's folds) found four;
  round 5's probe found two more. A fix is unreviewed code.
- **Half the findings were defects in the review itself, not the design** — MG-2, LI-4 and MG-3 were a wrong
  control, a stale oracle, and a weak assertion. The plan's verification steps needed as much adversarial
  attention as its implementation steps.
- **The peer was right and I was wrong on a line-cited factual claim** (AX-1), for the third time in this
  epic. Each time the pattern was identical: I read tool output positionally instead of reading line
  numbers.

---

## Task 0: Measure the `UserPromptSubmit` envelope before building on it

**Why this task exists and must not be skipped.** `agy-anomaly-capture-reminder.sh:9-15` records that a hook
emitting the wrong envelope produces "no error, no output, and looks installed and working". This plan would
ship exactly that failure if the envelope is guessed. The repo already paid for this lesson once.

**Files:**
- Create: `.clavity/scratch/upsubmit-envelope/` (gitignored; no repo file is created by this task)

- [ ] **Step 1: Write a three-arm sentinel hook that ALSO captures the payload**

🔴 **The payload capture is not optional and is the more important half.** Task 1's gate reads
`session_id` out of the `UserPromptSubmit` payload and exits silently when it is absent. **Nothing has
verified that this event carries `session_id` at all.** If it does not, the gate's own guard makes the hook
exit on every prompt forever — shipping a discipline that is installed, registered and inert, which is
verbatim the defect §0 exists to fix. Measure the payload before writing any code that reads it.

Create `.clavity/scratch/upsubmit-envelope/sentinel.sh`:

```bash
#!/usr/bin/env bash
set +e
input=$(cat)
# Dump the RAW payload. This is the artifact Task 1 depends on: it must show which of session_id, cwd,
# prompt and transcript_path are present, and their exact spelling.
printf '%s\n' "$input" > "$(dirname "$0")/payload.json"
printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"UPSUBMIT-ARM-A hookSpecificOutput reached the model"}}'
exit 0
```

- [ ] **Step 2: Register it temporarily and observe**

Register the sentinel on `UserPromptSubmit` in `.claude/settings.local.json` **only** — never in
`~/.claude/settings.json`, and never in a shipped `hooks.json`. Submit a prompt. Record which arm text, if
any, appears in the model's context.

Repeat with arm B (`{"systemMessage":"UPSUBMIT-ARM-B ..."}`) and arm C (bare `printf` of the text, no JSON).

- [ ] **Step 3: Record the result and REMOVE the sentinel**

Write the measured answer into `.clavity/scratch/upsubmit-envelope/RESULT.md` — which arm reached the model,
verbatim. Then delete the registration from `.claude/settings.local.json`.

🔴 **`.claude/settings.local.json` has been swept into a commit on this PUBLIC repo before.** Verify with
`git status --short` that it is not staged, and never `git add -A` while this task is in flight.

- [ ] **Step 4: STOP if the answer is not arm A**

If `hookSpecificOutput` is not the arm that reaches the model, **stop and report
`STATE_MISMATCH: UserPromptSubmit envelope is <arm>, not hookSpecificOutput`.** Tasks 1-3 below assume arm A
and every emission line in them must change if it is wrong.

- [ ] **Step 5: STOP if the payload has no `session_id`**

Open `.clavity/scratch/upsubmit-envelope/payload.json`. Confirm a `session_id` field exists and note its
exact spelling.

**If it is absent, stop and report `STATE_MISMATCH: UserPromptSubmit payload has no session_id; fields are
<list>`.** Do not substitute a different key, do not fall back to a fixed filename, and do not proceed. A
gate keyed on something session-invariant would suppress the reminder for every session after the first on
that machine — permanently, and silently. If `session_id` is absent but `transcript_path` is present, that
is the fallback to propose to the owner, because it is unique per session; propose it, do not adopt it
unilaterally.

- [ ] **Step 6: Price the per-prompt cost**

The registration in Task 3 is **bare**, so this hook spawns bash on **every prompt, in every session, for
every user of both drivers**, to deliver one message per session. This repo treats hook latency as
load-bearing (`agy-anomaly-capture-reminder.sh:48-51` records a 20314ms-vs-9282ms measurement that shaped
the root walk). Measure the added cost:

```bash
time (for i in $(seq 1 20); do printf '{"session_id":"x","cwd":"/tmp"}' | bash clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh UserPromptSubmit >/dev/null; done)
```

Record the per-invocation mean in `.clavity/scratch/upsubmit-envelope/RESULT.md`. **This is a measurement,
not a gate** — there is no threshold to pass. But the number must be known and stated to the owner, because
it is paid by every user on every turn and nothing else in this plan surfaces it.

- [ ] **Step 6b: Find out whether stderr at exit 0 is visible on this event**

Task 1's marker-failure path warns the operator on **stderr at exit 0**. Whether that is visible for
`UserPromptSubmit` is unmeasured. Add a fourth sentinel arm that writes only to stderr and exits 0, submit a
prompt, and record whether the text appears anywhere the operator would see.

**This does not block the plan.** If stderr at exit 0 turns out to be invisible, the fallback path is still
correct — it stays silent to the model rather than spamming, which is the load-bearing half — but the
warning is then decoration and the plan should say so instead of implying an operator will be told. Record
the answer either way. **Do not "fix" it by switching to exit 2:** exit 2 is blocking on some events, and
blocking a user's prompt to report a marker problem is out of all proportion.

- [ ] **Step 7: Commit**

Nothing to commit — this task creates no tracked file. Proceed to Task 0.5 with the measured answers in hand.

---

## Task 0.5: Teach the test helper to pass positional arguments

**Files:**
- Modify: `scripts/tests/BashHookHelpers.ps1` (`Invoke-BashHook` at `:31-39`)
- Test: `scripts/tests/BashHookHelpers.Tests.ps1`

**Why this task exists.** Task 1 makes the capture reminder take its event name as `$1`. Every existing test
invokes hooks through `Invoke-BashHook`, whose parameters are exactly `-HookPath`, `-Payload`, `-Env`
(`BashHookHelpers.ps1:35-39`) — **there is no way to pass a positional argument.** Without this task an
implementer would either bypass the helper (losing the `HOME` isolation every capture test depends on) or
improvise a change to shared infrastructure mid-task.

- [ ] **Step 1: Write the failing test**

Add to `scripts/tests/BashHookHelpers.Tests.ps1`:

```powershell
It 'forwards positional arguments to the hook' {
    $probe = Join-Path $TestDrive 'echo-args.sh'
    Set-Content -LiteralPath $probe -Value "#!/usr/bin/env bash`ncat >/dev/null`nprintf '%s' `"`$1`"" -NoNewline
    $r = Invoke-BashHook -HookPath $probe -Payload '{}' -Arguments @('UserPromptSubmit')
    $r.Stdout | Should -BeExactly 'UserPromptSubmit'
}

It 'passes no argument when -Arguments is omitted' {
    # CONTROL: guards the default path every EXISTING caller uses. If -Arguments defaulted to something
    # non-empty, every hook in the repo would start receiving a spurious $1.
    $probe = Join-Path $TestDrive 'echo-args.sh'
    Set-Content -LiteralPath $probe -Value "#!/usr/bin/env bash`ncat >/dev/null`nprintf '[%s]' `"`$1`"" -NoNewline
    $r = Invoke-BashHook -HookPath $probe -Payload '{}'
    $r.Stdout | Should -BeExactly '[]'
}
```

- [ ] **Step 2: Run and verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/BashHookHelpers.Tests.ps1 -Output Detailed"`
Expected: the first fails on an unknown `-Arguments` parameter.

- [ ] **Step 3: Add the parameter**

In `scripts/tests/BashHookHelpers.ps1`, add to the `param(...)` block at `:35-39`:

```powershell
        [string[]]$Arguments = @()
```

and append `$Arguments` to the bash invocation after the hook path. **SHAPE-DIVERGENCE STOP:** do not change
the existing `$HookPath`, `$Payload` or `$Env` parameters, their types, or their defaults — every hook suite
in the repo calls through them.

- [ ] **Step 4: Run and verify they PASS, then run the full helper suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/BashHookHelpers.Tests.ps1 -Output Detailed"`
Expected: `Failed: 0`.

Then run **every** suite that uses the helper, because this edits shared infrastructure:
`pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-anomaly-capture-reminder.Tests.ps1,scripts/tests/agy-inbox-snapshot.Tests.ps1,scripts/tests/agy-anomaly-dispatch-reminder.Tests.ps1 -Output Detailed"`
Expected: `Failed: 0` — no existing caller regressed.

- [ ] **Step 5: Commit**

```bash
git add scripts/tests/BashHookHelpers.ps1 scripts/tests/BashHookHelpers.Tests.ps1
git commit -m "test(helpers): Invoke-BashHook can forward positional arguments"
```

---

## Task 1: Make the capture reminder event-aware (dotnet)

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh` (107 lines today)
- Test: `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1`

**Context.** The hook takes no arguments today and hardcodes one message and one envelope. Its sibling
`agy-autotrain/hooks/agy-learn-reminder.sh` already demonstrates the pattern this task follows: it takes the
event name as `$1` and branches the envelope on it (`agy-learn-reminder.sh:32-40`).

- [ ] **Step 1: Write the failing tests**

**Use the suite's OWN harness.** This file already defines `New-Workspace`, `New-CleanHome` (`:25`) and
`Payload`, and every existing test calls `Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env
@{ HOME = $h }` (`:52-54`, `:63-65`, `:75-77`). **Do not invoke `bash` directly.** The `-Env @{HOME=$h}` is
what stops an ambient `~/.claude/.no-agy` on the developer's machine from suppressing the hook at
`agy-anomaly-capture-reminder.sh:46,:79` — bypassing it makes a suppressed hook and a working hook produce
the same empty output, so an emptiness assertion would pass vacuously.

`-Arguments` comes from Task 0.5. `TMPDIR` is redirected per-test so the gate markers cannot leak between
tests — without it, test order decides the result.

Add to `scripts/tests/agy-anomaly-capture-reminder.Tests.ps1`:

```powershell
# One isolated session: a fresh HOME, a fresh workspace, a fresh TMPDIR, and a unique session id.
# The TMPDIR isolation is load-bearing: the gate's markers are named by session id, so two tests that
# share a temp dir AND a session id would silently depend on execution order.
function New-GateEnv {
    $h = New-CleanHome
    $t = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $t -Force | Out-Null
    @{ Home = $h; Tmp = $t; Sid = [guid]::NewGuid().ToString() }
}
function Invoke-Prompt { param($g, $w)
    Invoke-BashHook -HookPath $script:Hook `
        -Payload ('{"cwd":"' + ($w -replace '\\','/') + '","session_id":"' + $g.Sid + '"}') `
        -Arguments @('UserPromptSubmit') `
        -Env @{ HOME = $g.Home; TMPDIR = $g.Tmp }
}

It 'emits the compaction wording and a systemMessage envelope when invoked as PreCompact' {
    $w = New-Workspace; $h = New-CleanHome
    $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Arguments @('PreCompact') -Env @{ HOME = $h }
    $r.Stdout | Should -Match 'BEFORE COMPACTION'
    ($r.Stdout | ConvertFrom-Json).systemMessage      | Should -Not -BeNullOrEmpty
    ($r.Stdout | ConvertFrom-Json).hookSpecificOutput | Should -BeNullOrEmpty
}

It 'defaults to PreCompact behaviour when given NO argument' {
    # REGRESSION GUARD for every existing caller. hooks.json registers the PreCompact hook without an
    # argument today, and Task 3 does not change that line.
    $w = New-Workspace; $h = New-CleanHome
    $r = Invoke-BashHook -HookPath $script:Hook -Payload (Payload $w) -Env @{ HOME = $h }
    $r.Stdout | Should -Match 'BEFORE COMPACTION'
}

It 'emits NOTHING on the first prompt of a session' {
    # THE CONTROL. Without it, the emission test below passes even if the gate never closes.
    $g = New-GateEnv; $w = New-Workspace
    (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty -Because 'at prompt 1 the driver has done no work and can have observed nothing'
}

It 'does NOT say BEFORE COMPACTION when it emits on UserPromptSubmit' {
    # On a prompt event there is no compaction, and a reminder describing a moment that is not happening
    # trains the reader to discount it.
    $g = New-GateEnv; $w = New-Workspace
    $null = Invoke-Prompt $g $w
    $out  = (Invoke-Prompt $g $w).Stdout
    $out | Should -Not -Match 'BEFORE COMPACTION'
    $out | Should -Match 'AGY-ANOMALIES/1'
    ($out | ConvertFrom-Json).hookSpecificOutput.hookEventName    | Should -BeExactly 'UserPromptSubmit'
    ($out | ConvertFrom-Json).hookSpecificOutput.additionalContext | Should -Not -BeNullOrEmpty
}

It 'emits at most once per session' {
    $g = New-GateEnv; $w = New-Workspace
    $null  = Invoke-Prompt $g $w
    $two   = (Invoke-Prompt $g $w).Stdout
    $three = (Invoke-Prompt $g $w).Stdout
    $four  = (Invoke-Prompt $g $w).Stdout
    $two   | Should -Not -BeNullOrEmpty
    $three | Should -BeNullOrEmpty
    $four  | Should -BeNullOrEmpty
}

It 'treats a DIFFERENT session id as a fresh session' {
    # Guards the gate keying on the right thing. Keyed on anything session-invariant, the second session
    # on a machine would be suppressed forever.
    $w = New-Workspace
    $a = New-GateEnv
    $b = @{ Home = $a.Home; Tmp = $a.Tmp; Sid = [guid]::NewGuid().ToString() }  # SAME tmp, different session
    $null = Invoke-Prompt $a $w
    $null = Invoke-Prompt $a $w
    $null = Invoke-Prompt $b $w
    (Invoke-Prompt $b $w).Stdout | Should -Not -BeNullOrEmpty
}

It 'falls back to a second marker location when TMPDIR is not writable' {
    # The gate must survive an unwritable TMPDIR rather than either going silent forever or emitting on
    # every prompt. HOME is writable here, so the fallback location carries the session.
    #
    # 🔴 MEASURED 2026-08-07: A MERELY NONEXISTENT NESTED PATH IS NOT UNWRITABLE. The gate's own
    # `[ -d "$_cand" ] || mkdir -p "$_cand"` CREATES it, and the marker write then succeeds. An earlier
    # draft set $g.Tmp to 'definitely-not-a-directory/nested' and so exercised the ORDINARY path while
    # claiming to exercise the fallback -- it passed vacuously. The only portable way to make a location
    # genuinely unusable is to put a regular FILE where a parent directory component must be; `mkdir -p`
    # then fails ENOTDIR. Verified: mkdir -p on ./blocker/nested with ./blocker a file -> "Not a directory".
    $g = New-GateEnv; $w = New-Workspace
    $blocker = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    Set-Content -LiteralPath $blocker -Value 'x' -NoNewline
    $g.Tmp = Join-Path $blocker 'nested'
    $null  = Invoke-Prompt $g $w                      # prompt 1: suppressed via the fallback marker
    (Invoke-Prompt $g $w).Stdout | Should -Not -BeNullOrEmpty   # prompt 2: emits
    (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty        # prompt 3: gated, NOT spamming
}

It 'warns on stderr and stays SILENT when NO marker location is writable' {
    # THE CORRECTED TRADE. An earlier draft fell through to emit here, which means emitting on EVERY
    # prompt for the rest of the session -- the high-frequency spam this plan's own rationale calls worse
    # than no prompt at all. The operator gets a diagnostic; the model gets nothing.
    #
    # 🔴 BOTH locations must be blocked with a regular FILE as a parent component, for the reason measured
    # in the previous test. With merely-nonexistent paths the gate's `mkdir -p` CREATES both, no warning is
    # ever emitted, and this test FAILS AGAINST CORRECT CODE -- which under the NAME THE ORACLE rule below
    # would send an implementer to break working code to satisfy an impossible premise.
    $g = New-GateEnv; $w = New-Workspace
    $blockT = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    $blockH = Join-Path $TestDrive ([guid]::NewGuid().ToString())
    Set-Content -LiteralPath $blockT -Value 'x' -NoNewline
    Set-Content -LiteralPath $blockH -Value 'x' -NoNewline
    $g.Tmp  = Join-Path $blockT 'nested'
    $g.Home = Join-Path $blockH 'nested'
    $r1 = Invoke-Prompt $g $w
    $r2 = Invoke-Prompt $g $w
    $r3 = Invoke-Prompt $g $w
    $r1.Stdout | Should -BeNullOrEmpty
    $r2.Stdout | Should -BeNullOrEmpty -Because 'emitting here would fire on every prompt for the whole session'
    $r3.Stdout | Should -BeNullOrEmpty
    $r1.Stderr | Should -Match 'AGY-ANOMALIES'
    $r1.ExitCode | Should -Be 0 -Because 'exit 2 is BLOCKING on some events and must never gate a user prompt'
}

It 'does not let a session id escape the marker directory' {
    # The regex captures [^"]*, so a payload can contain path separators. Unsanitized, "../../x" would
    # place a marker outside the marker dir -- a payload deciding where a file lands.
    $g = New-GateEnv; $w = New-Workspace
    $g.Sid = '../../escaped'
    $null = Invoke-Prompt $g $w
    $null = Invoke-Prompt $g $w

    # EXHAUSTIVE SWEEP, not one directory level. An earlier draft checked only the grandparent of $g.Tmp
    # with no -Recurse, so an escape to $TestDrive itself, to three levels up, or into the HOME fallback
    # would have passed unnoticed -- a negative assertion scoped to one guessed destination proves only
    # that the marker did not land THERE.
    $all = @(Get-ChildItem -Path $TestDrive -Recurse -Force -Filter '.clavity-anomaly-*' -ErrorAction SilentlyContinue)
    $all.Count | Should -BeGreaterThan 0 -Because 'zero markers anywhere would satisfy the loop below vacuously, and would also mean the sanitized id silently disabled the gate'
    foreach ($m in $all) {
        $m.DirectoryName | Should -BeExactly (Resolve-Path $g.Tmp).Path -Because 'every marker must sit in the resolved marker directory, wherever the payload tried to send it'
    }
}

It 'still gates correctly when the session id needs sanitizing' {
    # Sanitizing must not break the gate: prompt 1 silent, prompt 2 emits, prompt 3 silent.
    $g = New-GateEnv; $w = New-Workspace
    $g.Sid = 'abc/def:ghi'
    (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty
    (Invoke-Prompt $g $w).Stdout | Should -Not -BeNullOrEmpty
    (Invoke-Prompt $g $w).Stdout | Should -BeNullOrEmpty
}

It 'holds the byte ban on the UserPromptSubmit message' {
    # Existing suites assert this for the compaction message; the new message is a new surface.
    $g = New-GateEnv; $w = New-Workspace
    $null = Invoke-Prompt $g $w
    $ctx  = ((Invoke-Prompt $g $w).Stdout | ConvertFrom-Json).hookSpecificOutput.additionalContext
    $ctx | Should -Not -BeNullOrEmpty -Because 'an empty string satisfies every ban below vacuously'
    foreach ($banned in @('`', "'", '"', '\')) {
        $ctx | Should -Not -BeLike "*$banned*" -Because 'the jq-absent path hand-builds JSON with no escaping machinery'
    }
}
```

- [ ] **Step 2: Run them and verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed"`

Expected: the new tests fail. **Read the COUNT, not the absence of a failure** — a filter that matches
nothing exits 0.

- [ ] **Step 3: Implement**

In `clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh`, replace the single `msg=` assignment at
line 31 with an event-selected pair, placed immediately after `input=$(cat)` (line 27):

```bash
event="${1:-PreCompact}"

# TWO messages, ONE contract stamp. The stamp is what scripts/tests/agy-anomaly-contract-stamp.Tests.ps1
# pins and what scripts/discipline-reaching-report.ps1 counts, so it must appear in BOTH or the recorder
# under-counts the new channel silently -- the v15 failure signature, one channel over.
msg_precompact='AGY-ANOMALIES/1 check BEFORE COMPACTION: did you VERIFY a defect this session that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. Uncaptured anomalies are lost at compaction. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'

msg_prompt='AGY-ANOMALIES/1 check: earlier in this session, did you VERIFY a defect that is OUTSIDE your current task and is not yet in .clavity/local-anomalies.md? Capture it now via the open-issues skill - one line: - [type] fact * path:LINE * DATE * task=<what you were doing>. NOT an anomaly: a test you expected to fail, an error in the work you are actively doing, or anything you have not verified by measurement. If nothing qualifies, do nothing - a speculative entry is worse than none, because it lands on a blocking triage gate.'

case "$event" in
  UserPromptSubmit) msg=$msg_prompt ;;
  *)                msg=$msg_precompact ;;
esac
```

**SHAPE-DIVERGENCE STOP:** `msg_precompact` above must be **byte-identical** to the current line 31. If you
find yourself adjusting so much as a hyphen to make it fit, stop and report
`[original] -> [yours] because <reason>`. That string is pinned at byte level by two existing suites.

- [ ] **Step 4: Add the gate, before any emission**

Insert immediately after the `case` block above:

```bash
# GATE (UserPromptSubmit only). Two conditions, both required:
#   (a) never on the first prompt of a session -- at that moment the driver has done no work and can have
#       observed nothing, and a prompt that arrives before anything could be noticed trains the reflexive
#       "none" answer that the capture-gap spec records at :65/:67 as worse than no prompt at all;
#   (b) at most once per session thereafter.
#
# THIS MARKER IS NOT A DISCIPLINE MARKER. It must never live in .clavity/agy-marks/, must never be read as
# evidence that anything was DELIVERED, and must never be named *.head. docs/agy-disciplines-marker-contract.md
# forbids a hook writing a .head marker, and gives the reason: a hook fires before the consult and cannot
# know its outcome. That reason does not apply here -- this records a fact the hook does know, that it
# already emitted -- but the two must stay visibly separate or the next reader will conflate them.
#
# NO SUBPROCESS ON THE PER-PROMPT PATH: the session id comes out of the payload with a bash regex, not jq
# and not git. MEASURED 2026-08-06 and recorded at :48-51 of this file: a per-invocation subprocess on a
# path that runs every turn is not affordable. The ONE exception is the prune below, which runs at most
# once per session on the first prompt -- not every turn -- and is the price of not growing a marker
# directory without bound.
if [ "$event" = "UserPromptSubmit" ]; then
  [[ $input =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]] && sid=${BASH_REMATCH[1]}
  # No session id -> no gate is possible -> stay SILENT rather than emit on every prompt. An ungated
  # emission here would fire on every turn forever, which is strictly worse than not firing.
  [ -z "$sid" ] && exit 0

  # THE MARKER WRITE MUST BE CHECKED, AND BOTH FAILURE DIRECTIONS ARE BUGS.
  #
  # If the marker cannot be written (temp missing, read-only, quota, a sandboxed TMPDIR):
  #   - exiting quiet means the reminder NEVER fires again -- installed, registered, permanently inert,
  #     with no signal. That is verbatim the defect this item exists to remove, rebuilt one layer down.
  #   - falling through to emit means the reminder fires on EVERY prompt for the rest of the session,
  #     which is the high-frequency spam this plan's own rationale calls worse than no prompt at all
  #     (capture-gap spec :65/:67). Trading a silent failure for a noisy one is not a fix.
  #
  # So: try a SECOND location before giving up, and if both fail, warn the OPERATOR on stderr and stay
  # silent to the MODEL. Precedent for exactly this shape is agy-inbox-snapshot.sh:60-63, which warns on
  # stderr when it cannot write its .bak rather than failing silently or looping.
  #
  # STDERR AT EXIT 0, never exit 2. Exit 2 is BLOCKING on some events, and blocking the user's prompt to
  # report a marker problem is catastrophically out of proportion.
  #
  # SANITIZE THE SESSION ID BEFORE IT BECOMES A FILENAME. The regex above captures [^"]* -- anything that
  # is not a quote, which includes "/" and "..". Concatenated into a path unchecked, a payload would get
  # to decide where a file lands. Strip to a safe set; if nothing survives, there is no usable key, so
  # exit rather than fall back to a shared name that would suppress every session on the machine.
  sid=${sid//[^A-Za-z0-9_-]/}
  [ -z "$sid" ] && exit 0

  # Try each location in order. The FIRST prompt of a session creates the marker and stays quiet; every
  # later prompt finds it and proceeds. An unusable location is skipped, so a broken TMPDIR costs the
  # fallback, not the discipline.
  seen=""
  for _cand in "${TMPDIR:-/tmp}" "$HOME/.clavity-tmp"; do
    [ -d "$_cand" ] || mkdir -p "$_cand" 2>/dev/null
    _s="$_cand/.clavity-anomaly-seen-$sid"
    if [ -f "$_s" ]; then seen=$_s; sent="$_cand/.clavity-anomaly-sent-$sid"; break; fi
    if : > "$_s" 2>/dev/null; then
      # (a) FIRST PROMPT of this session: marker now recorded, emit nothing this turn.
      # Prune this location while we are here. It runs at most once per session and only on the path that
      # just proved itself writable, so it never touches the hot path. $HOME/.clavity-tmp in particular has
      # NO OS temp reaper behind it -- without this, a machine with a broken TMPDIR grows two files per
      # session forever.
      # -mtime +30, NOT +7. The markers of a session that is still OPEN are as old as that session, and
      # this prune runs from a DIFFERENT session -- so too short a window deletes a live session's markers
      # and makes it emit a second time. 30 days is comfortably longer than any real session while still
      # bounding the directory.
      find "$_cand" -maxdepth 1 -name '.clavity-anomaly-*' -mtime +30 -delete 2>/dev/null
      exit 0
    fi
  done

  if [ -z "$seen" ]; then
    printf '%s\n' "[AGY-ANOMALIES] cannot write a session marker under TMPDIR or HOME - the direct-driver capture reminder is disabled for this session" >&2
    exit 0
  fi

  # (b) SUBSEQUENT PROMPTS: emit once, then never again.
  [ -f "$sent" ] && exit 0
  : > "$sent" 2>/dev/null
fi
```

**NAME THE ORACLE:** the two Step 1 tests `falls back to a second marker location when TMPDIR is not
writable` and `warns on stderr and stays SILENT when NO marker location is writable` are the pinning tests
for this branch. If the code and those tests disagree, **the tests win** — they encode the accepted trade
(stay silent to the model and tell the operator, rather than either failing silently forever or emitting on
every prompt), which is a decision the owner is approving, not an implementation detail.

⚠️ **Two things about the loop are deliberate and must not be "simplified":**

1. **`seen` starts empty and is only set on the found-existing branch.** That is what makes the
   post-loop `[ -z "$seen" ]` mean "no location was usable" rather than "the last one failed".
2. **The first-prompt branch `exit 0`s from inside the loop.** Hoisting it out would require
   distinguishing "existed" from "just created" after the fact, which a `-f` test cannot do — both are
   true by then, and the gate would never open.

- [ ] **Step 5: Branch the envelope on the event, both emission paths**

Replace line 66 (`printf '{"systemMessage":"%s"}\n' "$msg"`, the jq-absent path) with:

```bash
  case "$event" in
    UserPromptSubmit) printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"%s"}}\n' "$msg" ;;
    *)                printf '{"systemMessage":"%s"}\n' "$msg" ;;
  esac
```

Replace line 106 (`jq -nc --arg m "$msg" '{systemMessage:$m}'`, the jq path) with:

```bash
case "$event" in
  UserPromptSubmit) jq -nc --arg m "$msg" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$m}}' ;;
  *)                jq -nc --arg m "$msg" '{systemMessage:$m}' ;;
esac
```

**NAME THE ORACLE:** the existing suite already asserts the jq and jq-absent paths deliver a byte-identical
string (`agy-anomaly-capture-reminder.sh:29-30` describes it). That assertion is the oracle for this step.
If the two paths diverge, the oracle wins — fix the code, never the test.

- [ ] **Step 6: Run the tests and verify they PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-anomaly-capture-reminder.Tests.ps1 -Output Detailed"`
Expected: `Tests Passed: <n>, Failed: 0` with `<n>` greater than the baseline count.

- [ ] **Step 7: Prove the gate is non-vacuous**

🔴 **This step was rewritten on 2026-08-07. Two earlier versions of it were unexecutable.** The first
said "delete the whole `if [ ! -f "$seen" ]` / `else` block" — **no such block exists**; finding LI-3
rewrote the gate as a `for` loop and this step was never re-derived against it. The second asserted
"**expect EXACTLY TWO** tests red" and made a third failure a hard stop — a count calibrated against a
much smaller test set, before rounds 4 and 5 added six more gate tests. Following either version, an
implementer would have stopped on a control that failed for what looked like the wrong reason.

**The mutation.** In the create branch of the loop, replace the `exit 0` that follows the `find` prune
with:

```bash
      seen=$_s; sent="$_cand/.clavity-anomaly-sent-$sid"; break
```

This is the mutation that expresses "the gate degrades to emit on the first prompt, once". **Do not
instead delete the `exit 0` outright** — the loop would then run on to the second candidate, fall out with
`seen` still empty, and take the no-location-writable branch, which is silence, not the first-prompt
emission this control needs to produce.

**The one failure that MUST occur — this is the control:**

- `emits NOTHING on the first prompt of a session` — it now emits. **If this test stays green, the gate is
  not doing what you think and nothing below matters.**

**Expected collateral, stated as a prediction to confirm rather than a gate.** The markers are coupled, so
moving the emission one prompt earlier flips every test that asserts on an emission at prompt 2 or later.
Predicted: `does NOT say BEFORE COMPACTION when it emits on UserPromptSubmit`, `emits at most once per
session`, `treats a DIFFERENT session id as a fresh session`, `falls back to a second marker location when
TMPDIR is not writable`, `still gates correctly when the session id needs sanitizing`, and `holds the byte
ban on the UserPromptSubmit message`. **Do not treat this list as a count to match.** Confirm each red test
is one that asserts on a prompt-2-or-later emission; that is the property, not the number.

**The genuine stop condition** is a red test that the mutation cannot explain — specifically any of these
four, none of which touch the first-prompt branch:

- `emits the compaction wording and a systemMessage envelope when invoked as PreCompact`
- `defaults to PreCompact behaviour when given NO argument`
- `warns on stderr and stays SILENT when NO marker location is writable`
- `does not let a session id escape the marker directory`

If one of those goes red, the gate is entangled with something this plan has not accounted for. **Stop and
report it.**

Restore the file and confirm it matches the committed version exactly (`git diff --exit-code <file>`).

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh scripts/tests/agy-anomaly-capture-reminder.Tests.ps1
git commit -m "feat(hooks): the capture reminder reaches a driver working directly"
```

---

## Task 2: Mirror to clavity-classic, byte-identically

**Files:**
- Modify: `clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh`

**Context.** `clavity-dotnet/ROADMAP.md:162-167`: parity is a requirement, not a follow-up. Two gates enforce
it — `scripts/tests/plugin-hooks-payload.Tests.ps1` (per-file byte parity across the two hook dirs) and the
`.hooks` deny-list catch-all in `scripts/check-seed-artifacts-synced.sh`.

- [ ] **Step 1: Copy, do not re-type**

```bash
cp clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh
```

Re-typing invites a one-byte drift that the parity gate will catch but only after wasting a cycle.

- [ ] **Step 2: Verify byte parity**

```bash
cmp clavity-dotnet/plugin/hooks/agy-anomaly-capture-reminder.sh clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh && echo IDENTICAL
```
Expected: `IDENTICAL`

⚠ **Do not "normalize" line endings.** Editing an LF file has silently converted it to CRLF four or more
times in this repo. Judge by what is COMMITTED (`git show HEAD:<file>`), not by the working tree.

- [ ] **Step 3: Run the parity gates**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/plugin-hooks-payload.Tests.ps1 -Output Detailed"`
Then: `bash scripts/check-seed-artifacts-synced.sh`
Expected: both green.

- [ ] **Step 4: Commit**

```bash
git add clavity-classic/plugin/hooks/agy-anomaly-capture-reminder.sh
git commit -m "feat(hooks): mirror the direct-driver capture reminder to classic"
```

---

## Task 3: Register `UserPromptSubmit` in both driver manifests

**Files:**
- Modify: `clavity-dotnet/plugin/hooks/hooks.json` (68 lines today; `PreCompact` block at 59-66)
- Modify: `clavity-classic/plugin/hooks/hooks.json`
- Test: `scripts/tests/plugin-hooks-registration.Tests.ps1` (202 lines today)

- [ ] **Step 1: Write the failing registration tests**

🔴 **READ THIS BEFORE WRITING THE ASSERTION.** `scripts/tests/plugin-hooks-registration.Tests.ps1:191-197`
records a measured vacuity bug: `Get-OwningMatchers` returns `$null` for a group with **no `matcher` key**,
so `@($null)` has Count 1 and `Should -BeNullOrEmpty` accepts it. **The registration this task adds is
deliberately matcher-less**, so it is exactly the shape that triggers that bug. Use `Get-OwningGroupCount`
(defined at `:31-36`), never `Get-OwningMatchers`, for anything about this registration.

Add:

```powershell
It 'registers the capture reminder on UserPromptSubmit in exactly one BARE group - <Driver>' -ForEach @(
    @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
) {
    # COUNT GROUPS, NOT MATCHER VALUES. This group has no "matcher" key by design -- nothing establishes
    # that a matcher is evaluated against prompt text for this event, so the discrimination lives in the
    # script. Get-OwningMatchers would yield $null here and every emptiness check would accept it.
    $m = $script:Manifests[$Driver]
    Get-OwningGroupCount -Manifest $m -Event 'UserPromptSubmit' -Script 'agy-anomaly-capture-reminder.sh' |
        Should -Be 1
}

It 'passes the event name as an argument on UserPromptSubmit - <Driver>' -ForEach @(
    @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
) {
    # Without the argument the hook defaults to PreCompact wording and emits the wrong envelope --
    # a failure that produces no error and looks installed and working.
    $json = Get-Content -Raw -LiteralPath $script:Manifests[$Driver] | ConvertFrom-Json
    $cmds = @(foreach ($g in @($json.hooks.UserPromptSubmit)) { foreach ($h in @($g.hooks)) { $h.command } })
    ($cmds -join ' ') | Should -Match 'agy-anomaly-capture-reminder\.sh.*UserPromptSubmit'
}

It 'keeps the capture reminder on PreCompact manual|auto as well - <Driver>' -ForEach @(
    @{ Driver = 'dotnet' }, @{ Driver = 'classic' }
) {
    # The new channel ADDS to the compaction channel; it does not replace it. A long session that compacts
    # should still get the pre-compaction prompt, whose wording is specific to that moment.
    $matchers = @(Get-OwningMatchers -Manifest $script:Manifests[$Driver] -Event 'PreCompact' -Script 'agy-anomaly-capture-reminder.sh')
    $matchers.Count | Should -Be 1
    $matchers[0]    | Should -BeExactly 'manual|auto'
}
```

- [ ] **Step 2: Run and verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed"`
Expected: the first two new tests fail; the third already passes (it pins existing behaviour).

- [ ] **Step 3: Add the registration to `clavity-dotnet/plugin/hooks/hooks.json`**

Insert after the `PreCompact` block (which ends at line 66 with `]`), as a new sibling key:

```json
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-anomaly-capture-reminder.sh\" UserPromptSubmit" }
        ]
      }
    ]
```

Remember the comma after the `PreCompact` array's closing `]`. **No `matcher` key** — its absence is the
design, not an omission.

- [ ] **Step 4: Add the identical registration to `clavity-classic/plugin/hooks/hooks.json`**

Same block, same place. The two manifests are not byte-identical overall (classic registers
`agy-drive-session-reset.sh`, dotnet does not — pinned at `plugin-hooks-registration.Tests.ps1:69-86`), so
copy the block, not the file.

- [ ] **Step 5: Run the tests and verify they PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/plugin-hooks-registration.Tests.ps1 -Output Detailed"`
Expected: `Failed: 0`.

- [ ] **Step 6: Prove the new assertion is non-vacuous**

Temporarily change the registered script name to `agy-anomaly-capture-reminder-typo.sh` **in the dotnet
manifest ONLY**. Re-run.

🔴 **THREE tests must go red — not two.** This step said "two" until 2026-08-07; that count was written
before the second test below existed, and is finding EX-6, the same stale-expected-failure-count class as
EX-3. Check them by name:

- `registers the capture reminder on UserPromptSubmit in exactly one BARE group - dotnet` — the group count
  drops to 0. **This is the control that MUST fire.** If it stays green, the assertion is not reading what
  you think it is, and nothing else in this step matters.
- `passes the event name as an argument on UserPromptSubmit - dotnet` — its regex requires a literal
  `agy-anomaly-capture-reminder\.sh`, which `...-reminder-typo.sh` does not contain.
- the existing `names only hook files that EXIST in that plugin` at `:115-131` — the typo names a file that
  does not exist.

**The `classic` variants of all three must stay GREEN**, because only the dotnet manifest was edited. A red
classic variant means the wrong file was edited — a genuine stop. Restore and re-run to confirm green.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/plugin/hooks/hooks.json clavity-classic/plugin/hooks/hooks.json scripts/tests/plugin-hooks-registration.Tests.ps1
git commit -m "feat(hooks): register the capture reminder on UserPromptSubmit in both drivers"
```

---

## Task 4: Close the inbox-snapshot slash-command hole

**Files:**
- Modify: `agy-autotrain/hooks/agy-inbox-snapshot.sh` (70 lines today)
- Modify: `agy-autotrain/hooks/hooks.json` (18 lines today)
- Test: `scripts/tests/agy-inbox-snapshot.Tests.ps1`

**Context.** The hook decides whether to act by reading `.tool_input.skill` from a `PreToolUse` payload
(lines 24-33). A `UserPromptSubmit` payload has no `tool_input`; it carries the prompt. The hook must accept
both shapes. Everything below line 35 — the three invariants, the dedup, the FIFO prune — is unchanged and
must stay unchanged.

- [ ] **Step 1: Write the failing tests**

**Use the suite's OWN harness.** `scripts/tests/agy-inbox-snapshot.Tests.ps1` defines `New-PluginRoot`
(`:8`), `BakCount` (`:20`) and a `Payload` helper, and its tests read
`$r = New-PluginRoot $script:Good` then `Invoke-BashHook -HookPath $script:Hook -Payload (Payload '...')`
then `BakCount $r | Should -Be 1` (`:27-30`).

🔴 **There is no `$script:ObsDir` in this suite.** A draft of this plan used one. It would have expanded to
an empty string, so `Get-ChildItem` would have searched a nonexistent path and returned 0 — making the
negative control below **pass unconditionally, even if the hook snapshotted on every prompt**. Use
`BakCount $r`.

🔴 **`Invoke-BashHook` must set `CLAUDE_PLUGIN_ROOT`.** The hook resolves
`OBS="${CLAUDE_PLUGIN_ROOT}/knowledge/agy-observations.md"` (`agy-inbox-snapshot.sh:15`) and exits at `:35`
if that file is absent. Without the env var every test below exits 0 having done nothing, and every
`Should -Be 0` passes vacuously. Follow whatever the existing tests do to bind the plugin root — read
`:27-30` and copy that shape exactly rather than inventing one.

Add a prompt-payload helper alongside the existing `Payload`, then:

```powershell
# The UserPromptSubmit payload shape: a .prompt string, no .tool_input.
function PromptPayload { param([string]$Text) '{"prompt":"' + ($Text -replace '"','\"') + '"}' }

It 'snapshots when agy-curate is invoked as a SLASH COMMAND' {
    # The reported defect, verbatim: measured 2026-08-03, no new .bak appeared on this path.
    $r = New-PluginRoot $script:Good
    Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r }
    BakCount $r | Should -Be 1
}

It 'does NOT snapshot on an ordinary prompt that merely mentions agy-curate' {
    # CONTROL. A bare substring match fires on this. The existing jq-absent branch at :32 already records
    # why that is wrong: another skill could merely MENTION agy-curate in its args.
    $r = New-PluginRoot $script:Good
    Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload 'why did agy-curate skip the snapshot last time?') -Env @{ CLAUDE_PLUGIN_ROOT = $r }
    BakCount $r | Should -Be 0
}

It 'snapshots on a slash command WITH trailing arguments' {
    # /agy-autotrain:agy-curate --dry-run is a real invocation and must not be treated as prose.
    $r = New-PluginRoot $script:Good
    Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate --dry-run') -Env @{ CLAUDE_PLUGIN_ROOT = $r }
    BakCount $r | Should -Be 1
}

It 'still snapshots on the Skill-tool path' {
    # Regression guard: the path that already worked must keep working.
    $r = New-PluginRoot $script:Good
    Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r }
    BakCount $r | Should -Be 1
}
```

- [ ] **Step 2: Run and verify the first two FAIL, the third PASSES**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-inbox-snapshot.Tests.ps1 -Output Detailed"`

- [ ] **Step 3: Implement the second path**

In `agy-autotrain/hooks/agy-inbox-snapshot.sh`, replace the whole skill-detection block (lines 22-33) with:

```bash
# WHICH invocation is this? Two payload shapes reach this hook and they carry different fields:
#   PreToolUse       -> .tool_input.skill  (the Skill tool was called)
#   UserPromptSubmit -> .prompt            (the user typed the slash command)
# The slash-command path is the one the defect was measured on: 2026-08-03, invoking the curator as
# /agy-autotrain:agy-curate produced NO new .bak, because PreToolUse never fires for it.
#
# The match is done HERE, in the script, and NOT with a declarative "matcher" regex in hooks.json.
# Nothing establishes that a matcher is evaluated against prompt text for UserPromptSubmit: the schema
# permits the key syntactically, but both first-party plugins that register this event do so BARE and
# inspect the prompt in their own script. Building on the matcher would be an unchecked assumption, and
# it would fail SILENTLY -- the hook would simply never fire, which is the defect this closes, restored.
matched=""
if command -v jq >/dev/null 2>&1; then
  skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)
  case "$skill" in *agy-curate) matched=1 ;; esac
  if [ -z "$matched" ]; then
    prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
    # ANCHORED at the start and bounded at the end. An unanchored match fires on a prompt that merely
    # discusses the curator, which is not an invocation and must not burn a snapshot slot.
    case "$prompt" in
      /agy-autotrain:agy-curate|/agy-autotrain:agy-curate\ *) matched=1 ;;
      /agy-curate|/agy-curate\ *) matched=1 ;;
    esac
  fi
else
  # FIELD-BOUNDED, never a bare substring -- same reasoning as the jq path above.
  if printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*agy-curate"'; then
    matched=1
  elif printf '%s' "$input" | grep -Eq '"prompt"[[:space:]]*:[[:space:]]*"/(agy-autotrain:)?agy-curate([[:space:]][^"]*)?"'; then
    matched=1
  fi
fi
[ -z "$matched" ] && exit 0
```

**NO ELIDED ENUMERATIONS:** the four `case` patterns above are the complete set. Do not add a catch-all.

- [ ] **Step 4: Register the event**

In `agy-autotrain/hooks/hooks.json`, add after the `PreCompact` array (ends line 16):

```json
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/agy-inbox-snapshot.sh\"" } ] }
    ]
```

Note: **no event argument here.** Unlike the capture reminder, this hook discriminates on payload fields
that are already distinct between the two shapes, so it needs no event name to tell them apart.

- [ ] **Step 5: Run the tests and verify they PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path scripts/tests/agy-inbox-snapshot.Tests.ps1 -Output Detailed"`
Expected: `Failed: 0`.

- [ ] **Step 6: Verify the dedup invariant still bounds the new path**

The hook now has two ways to fire in one drain (the user types the slash command **and** the skill body
later triggers the Skill tool). Line 56-57's dedup — `cmp -s "$OBS" "$latest"` — is what prevents that
burning two slots. Add:

```powershell
It 'burns only ONE slot when both paths fire in the same drain' {
    $r = New-PluginRoot $script:Good
    Invoke-BashHook -HookPath $script:Hook -Payload (PromptPayload '/agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r }
    Invoke-BashHook -HookPath $script:Hook -Payload (Payload 'agy-autotrain:agy-curate') -Env @{ CLAUDE_PLUGIN_ROOT = $r }
    BakCount $r | Should -Be 1 -Because 'the dedup invariant at :53-57 exists for exactly this'
}
```

Run the suite again. Expected: `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add agy-autotrain/hooks/agy-inbox-snapshot.sh agy-autotrain/hooks/hooks.json scripts/tests/agy-inbox-snapshot.Tests.ps1
git commit -m "fix(autotrain): snapshot the inbox on the slash-command path too"
```

---

## Task 5: Reconcile the documents with what shipped

**Files:**
- Modify: `agy-autotrain/docs/fix-the-tool-backlog/inbox-snapshot-misses-slash-command-path.md`
- Modify: `clavity-dotnet/ROADMAP.md` (§0, lines 118-359)

- [ ] **Step 1: Update the backlog entry**

Set `status: fixed` in the frontmatter and update `last-triaged` to the implementation date. Add a
`## Fixed — <date>` section that records **both corrections this plan established**, because an entry that
is marked fixed while still recommending a wrong mitigation will mislead the next reader:

- mitigation 2 shipped, but **as a bare registration with in-script matching**, not the declarative
  `matcher` regex the entry proposed — nothing establishes that a matcher is evaluated against prompt text;
- mitigation 1 was **not** implemented and should not be: `curate-commit` is a driver CLI verb
  (`clavity-dotnet/src/Clavity.Ls/CliVerbs.cs:36`, `clavity-classic/src/main.rs:700`) that writes the
  golden-header GROWTH region and has no knowledge of the inbox; implementing it there would couple the
  driver binary, in two languages, to a separate plugin's file layout.

Name the pinning tests by name.

- [ ] **Step 2: Update ROADMAP §0**

In the `📏 WHICH STEPS HAVE SHIPPED` block, change the **Item 1b** bullet (currently at
`clavity-dotnet/ROADMAP.md:218-223`, reading `❌ NOT SHIPPED. The original defect is unchanged.`) to record
that it shipped, the event it shipped on, and the accepted limitation from this plan's header — the
one-prompt session. **Do not delete the measurement that recorded it as unshipped**; it is the provenance
for why this work happened.

🔴 **Grep the whole repo for the fact you changed.** The dominant defect in this repo is an incomplete fold.
`clavity-classic/ROADMAP.md` points at dotnet §0 **by design** — do not "restore parity" by copying the body
across. Check `docs/` and both `CHANGELOG.md` files for any claim that the count of hooks prompting a direct
driver is zero.

> ⚠️ **A draft of this plan added a Step 2b here "correcting" `clavity-dotnet/ROADMAP.md:299-300` from
> `:65`/`:67` to `:64`/`:66`. That correction was WRONG and has been removed.** The panel caught it.
> Re-measured with explicit line numbers: `:65` **is** the `Stop` row and `:67` **is** the tool-output row,
> so the ROADMAP was right all along. The error came from reading `sed -n '60,70p'` output and counting
> positions instead of printing line numbers — the range began on a blank line. **Do not re-introduce this
> "fix".** Use `awk 'NR>=a && NR<=b {print NR"|"$0}'` when a line number is load-bearing.

- [ ] **Step 3: Commit**

```bash
git add agy-autotrain/docs/fix-the-tool-backlog/inbox-snapshot-misses-slash-command-path.md clavity-dotnet/ROADMAP.md
git commit -m "docs: record the direct-driver capture channel and the inbox-snapshot fix"
```

---

## Completion gate

- [ ] Run the fast suite: `just test-scripts-fast`. ⚠ It is **cap-adjacent** (429s solo, 665s under
      contention) — never run it alongside the slow half.
- [ ] Run the slow suite **backgrounded**, blocking on its own `Tests completed` line, never on a process
      count. **A log with no `Tests Passed:` line is an ABORTED run, not a pass.**
- [ ] Register any new test file in the `justfile` — **test registration is an explicit list, not a glob**,
      enforced by `scripts/tests/test-suite-registration.Tests.ps1`. This plan adds no new file, only
      modifies existing suites, so no registration change is expected. Confirm that rather than assuming it.
- [ ] **AGY-CAPSTONE** on the committed range, per the standing rule. The marker records the **reviewed**
      tip, never ambient HEAD.

---

## Owner decisions carried into review

Two points this plan resolved on measurement but which are the owner's to ratify, flagged here rather than
buried:

1. **This ships a new prompt to every user of both drivers, once per session.** That is a product-visible
   behaviour change, not just a bug fix. The gate keeps it to one emission per session and never on the
   first prompt, but the owner may want it opt-in for a release rather than on by default.
2. **The one-prompt session stays uncovered**, and the two events that would cover it are measured dead or
   withdrawn. If that hole matters, the only remaining route is the outside-witness trial — which this
   epic's own owner ruling **KILLED** (`clavity-dotnet/ROADMAP.md:190-193`).
