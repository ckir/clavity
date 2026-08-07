# LS bridge — truthful diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the clavity-ls → agy bridge report *why* it failed, instead of blaming a peer shutdown for every fault, and raise the transport ceiling that causes the most common false report.

**Architecture:** Four of the five KEPT `fix-the-tool` entries are the same defect wearing three root causes. `ChannelDown.Hint(ChannelDiagnostic d)` accepts a diagnostic and then ignores it — the narrative text is fixed at "agy's language server appears to have shut down or restarted". `ChannelDown.IsChannelDown` admits *any* non-`Cancelled` `RpcException`, so an oversized-payload `ResourceExhausted` and a no-open-conversation error both funnel into that one message. The fix is a discriminating classifier: `Hint` switches on a cause derived from the diagnostic, each root cause gets its own remedy text and its own regression test, and the transport cap that generates the most frequent false report is set deliberately rather than inherited.

**Tech Stack:** C# / .NET, `Grpc.Net.Client`, xunit (`[Fact]`, `Assert.*`).

---

## Scope — this is plan 1 of 3 for Phase 3's buildable track

Owner rulings 2026-08-07: §7 shape = **Option B** (cross-cutting amendment); Phase 3 sequencing = **Option Y** (two tracks). Under Y the buildable track proceeds now; §7's spec runs its own consult→spec→panel timeline.

| Plan | Covers | State |
|---|---|---|
| **1 — this plan** | 4 C# entries: `grpc-default-max-message-size`, `conversation-scoped-tools-vs-no-open-conversation`, `agy-look-tail-truncation`, `stalled-reply-recoverable-not-lost` | ready |
| 2 — hooks | ROADMAP §0 step 1b (direct-driver prompt trigger) + `inbox-snapshot-misses-slash-command-path` | not written; §0 1b needs a measurement first (below) |
| 3 — assertion strength | ROADMAP §11, both plugins byte-identical + new PostToolUse hook | not written |

**Plan 2's gate, recorded so it is not skipped:** ROADMAP §0 states the 1b trigger placement "is to be **decided from 1a's data rather than guessed**". The 1a recorder exists at `scripts/discipline-reaching-report.ps1`. Plan 2's first task must RUN it and choose the trigger from its output. The witness trial (step 3) is KILLED — do not reinstate it.

---

## Preamble — read before the evidence in any task

These are not general advice. Each one cost a real defect in the epic that produced this plan.

0. **Read the STATUS LINE before the evidence.** A grep hit inside a section whose heading says `SHIPPED` is not an open item. This plan's own epic nearly ordered a shipped item killed three times, always from stopping at the hit.
1. **Every number in this plan is stale.** Line numbers cited here were measured 2026-08-07 against `d895cf3` and the tasks below *edit those files*. Anchor to the quoted TEXT and re-locate; never trust an offset, and never derive a line number by counting from a `sed` window.
2. **A fix must be RUN, not read.** Re-run every command after you change it.
3. **A probe needs a control that CAN fail.** Before believing a zero, run the same probe against something known-present.
4. **`rg` in the Bash tool on this machine is GNU grep 3.0, not ripgrep.** `--no-ignore` and `--glob` produce silent null results. Measured 2026-08-07. Use the Grep tool for repo-wide searches.
5. **Verify a suggested FIX, not just the finding.** A correct finding routinely arrives with a wrong or incomplete remedy.

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs` | Classify a caught exception, diagnose it, produce the hint | Add a cause classifier; `Hint` switches on it |
| `clavity-dotnet/src/Clavity.Ls/LsChannel.cs` | gRPC channel factory | Set `MaxReceiveMessageSize` deliberately |
| `clavity-dotnet/src/Clavity.Ls/AgyView.cs` | The three tool surfaces + idle-wait | `agy_look` ordering; idle-expiry final readback |
| `clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs` | **New.** Pins each fault → its own hint | Created in Task 1 |
| `clavity-dotnet/tests/Clavity.Ls.Tests/AgyStatusShapeTests.cs` | Existing `ChannelDown` coverage | Untouched — it pins `IsChannelDown`/`Diagnose`, which stay behaviour-compatible |
| `agy-autotrain/docs/fix-the-tool-backlog/*.md` | The four entries | `status:` flipped in Task 6 only |

**Measured coverage gap (do not treat as pre-existing-and-therefore-fine):** there is no `ChannelDownTests.cs`. `IsChannelDown` and `Diagnose` are covered incidentally by `AgyStatusShapeTests.cs`; `Hint` — the thing that lies — has **zero** tests. Task 1 creates the file.

---

## Task 0: Baseline

**Files:** none (measurement only)

- [ ] **Step 1: Record the base SHA and confirm a clean tree**

```bash
git rev-parse HEAD
git status --porcelain
```

Expected: a SHA, and **no output** from the second command. Write the SHA into this plan's execution memory as the plan base — a later capstone reviews `<base>..HEAD`. If the tree is dirty, STOP and ask.

- [ ] **Step 2: Confirm the suite is green BEFORE any change**

```bash
cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests
```

Expected: build succeeds; the test run ends with a `Passed!` line and `Failed: 0`. **Record the passing test count.** A suite that is already red makes every later "it passes" claim meaningless — if it is red, STOP and report.

- [ ] **Step 3: Branch**

This work accumulates on `main` by owner ruling (risky tasks may accumulate there), so no branch is required. Do NOT create one unless the owner asks.

---

## Task 1: Make `ChannelDown.Hint` discriminate — the spine

Everything else attaches here. `Hint` currently takes a `ChannelDiagnostic` and ignores its cause.

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs`
- Create: `clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs`

- [ ] **Step 1: Write the failing test**

Create `clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ChannelDownTests
{
    [Fact]
    public void An_oversized_payload_is_not_reported_as_a_peer_shutdown()
    {
        var d = new ChannelDiagnostic("ResourceExhausted", "Received message exceeds the maximum configured size");
        var hint = ChannelDown.Hint(d);

        // The whole defect in one assertion: the operator must not be sent to inspect a healthy process.
        Assert.DoesNotContain("shut down or restarted", hint);
        Assert.Contains("too large", hint);
        Assert.Contains("fresh cascade", hint);
    }

    [Fact]
    public void A_genuine_transport_death_still_reports_a_peer_shutdown()
    {
        // The existing behaviour must survive: this is the case the old hint was written for.
        var d = new ChannelDiagnostic("Unavailable", "connection refused");
        var hint = ChannelDown.Hint(d);

        Assert.Contains("shut down or restarted", hint);
    }

    [Fact]
    public void Every_hint_names_the_status_code_and_detail_it_was_given()
    {
        // Distractor case: a fault we have not special-cased must still surface its real diagnostic
        // rather than falling through to an empty or generic string.
        var d = new ChannelDiagnostic("Internal", "backend exploded");
        var hint = ChannelDown.Hint(d);

        Assert.Contains("Internal", hint);
        Assert.Contains("backend exploded", hint);
    }
}
```

- [ ] **Step 2: Run it and watch it fail for the RIGHT reason**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~ChannelDownTests"
```

Expected: `An_oversized_payload_is_not_reported_as_a_peer_shutdown` **FAILS** — `Assert.DoesNotContain` fails because the current hint always contains "shut down or restarted". The other two **PASS** already (the current hint does interpolate status code and detail).

**If the oversized test passes, STOP** — the code is not what this plan measured.

- [ ] **Step 3: Add the classifier and make `Hint` switch on it**

In `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs`, replace the `Hint` method (the one whose body begins `$"clavity-ls -> agy channel is down ([{d.StatusCode}] {d.Detail}). agy's language server appears to have "`) with:

```csharp
    /// <summary>Why the channel call failed. The bridge used to report every fault as a peer shutdown, which sent
    /// the operator to inspect a healthy process while the real cause was the response SIZE or a closed
    /// conversation. Each cause names its own remedy.</summary>
    public enum Fault { TransportDown, PayloadTooLarge }

    /// <summary>Classify a diagnosed fault by its gRPC status code.</summary>
    public static Fault Classify(ChannelDiagnostic d) =>
        d.StatusCode == nameof(Grpc.Core.StatusCode.ResourceExhausted)
            ? Fault.PayloadTooLarge
            : Fault.TransportDown;

    public static string Hint(ChannelDiagnostic d)
    {
        var prefix = $"clavity-ls -> agy channel call failed ([{d.StatusCode}] {d.Detail}). ";
        return Classify(d) switch
        {
            Fault.PayloadTooLarge =>
                prefix + "The response was too large for the channel's receive limit — the peer is NOT down, and " +
                "restarting will not clear it. Start a fresh cascade, or raise MaxReceiveMessageSize in " +
                "LsChannel.cs. Trajectory size, not step count, is what crosses the limit.",
            _ =>
                prefix + "agy's language server appears to have shut down or restarted (it does this " +
                "intermittently). Restart the Claude Code session (or the clavity-ls MCP server) to re-establish " +
                "the channel. agy's own logs are at ~/.gemini/antigravity-cli/ (cli.log + " +
                "logs/clavity-<sessionId>.log) if you need to confirm the shutdown.",
        };
    }
```

**Shape note:** the leading text changes from "channel is down" to "channel call failed", because the old wording asserts the very thing that was false. That is deliberate, not incidental.

- [ ] **Step 4: Run the tests and verify they pass**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~ChannelDownTests"
```

Expected: all three PASS.

- [ ] **Step 5: Run the FULL suite — the wording change may break a pinned string elsewhere**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
```

Expected: `Failed: 0`, and a passing count **≥ Task 0 Step 2's count + 3**. If another test pinned the old "channel is down" prose, fix **that test's expectation** only if its intent was to pin the shutdown narrative for a genuine transport death; if it pinned the prose for a non-transport fault, that test was encoding the defect — report it rather than editing it silently.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/ChannelDown.cs clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs
git commit -m "fix(ls): ChannelDown.Hint names the real fault instead of always blaming a peer shutdown"
```

---

## Task 2: Set the gRPC receive limit deliberately

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/LsChannel.cs`

- [ ] **Step 1: Confirm the current state**

```bash
grep -n "MaxReceiveMessageSize" clavity-dotnet/src/Clavity.Ls/LsChannel.cs
```

Expected: **no output** — the option is never set, so the channel inherits gRPC's 4 MB default. If it prints a line, STOP: someone set it since this plan was written.

- [ ] **Step 2: Set the limit**

In `clavity-dotnet/src/Clavity.Ls/LsChannel.cs`, find the return statement whose body reads `new GrpcChannelOptions { HttpHandler = effective });` and replace that whole `return` expression with:

```csharp
        return GrpcChannel.ForAddress(
            $"http://127.0.0.1:{httpPort}",
            new GrpcChannelOptions
            {
                HttpHandler = effective,
                // A cascade's trajectory grows without bound, and gRPC's 4 MB DEFAULT was being inherited by
                // accident — every readback past it died ResourceExhausted while the peer was healthy. 64 MB is a
                // deliberate ceiling well above the largest realistic trajectory; null (unbounded) was rejected so
                // a runaway response still fails loudly instead of exhausting memory.
                MaxReceiveMessageSize = 64 * 1024 * 1024,
            });
```

- [ ] **Step 3: Build and run the full suite**

```bash
cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests
```

Expected: build succeeds, `Failed: 0`.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/LsChannel.cs
git commit -m "fix(ls): set MaxReceiveMessageSize deliberately instead of inheriting gRPC's 4 MB default"
```

---

## Task 3: A live endpoint with no open conversation must not report a shutdown

**This task has a measurement step before its code step, deliberately.** The entry specifies the remedy but not the wire signal agy produces when no conversation is open. Do not guess a status code — measure it.

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs`

- [ ] **Step 1: Reproduce and capture the real diagnostic**

Follow `agy-autotrain/docs/fix-the-tool-backlog/conversation-scoped-tools-vs-no-open-conversation.md` "Steps to Reproduce": with the agy host running and **no** conversation open, call `agy_status`.

Record verbatim: the `StatusCode` and the `Detail` string. That pair is the mapping input.

**If you cannot reach that state** (no agy host, or a conversation cannot be closed), STOP and report `BLOCKED: cannot reproduce no-open-conversation state`. Do **not** invent a status code — a wrong mapping makes the hint lie in a new way, which is the defect this plan exists to remove.

- [ ] **Step 2: Write the failing test using the MEASURED values**

Add to `ChannelDownTests.cs`, substituting the status code and a distinctive fragment of the detail you measured in Step 1:

```csharp
    [Fact]
    public void No_open_conversation_is_not_reported_as_a_peer_shutdown()
    {
        // Status code and detail fragment MEASURED against a live agy host with no conversation open.
        var d = new ChannelDiagnostic("<MEASURED_STATUS_CODE>", "<MEASURED_DETAIL_FRAGMENT>");
        var hint = ChannelDown.Hint(d);

        Assert.DoesNotContain("shut down or restarted", hint);
        Assert.Contains("no agy conversation is open", hint);
    }
```

- [ ] **Step 3: Run it and watch it fail**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~ChannelDownTests"
```

Expected: the new test FAILS on `DoesNotContain`.

- [ ] **Step 4: Extend the classifier**

Add `NoConversation` to the `Fault` enum, extend `Classify` to return it for the measured signal, and add its arm to the `Hint` switch:

```csharp
            Fault.NoConversation =>
                prefix + "The channel is healthy but no agy conversation is open — restarting will NOT clear this " +
                "(it survives an agy restart and a machine restart). Open a conversation in agy, then retry.",
```

- [ ] **Step 5: Run tests, verify green**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
```

Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/ChannelDown.cs clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs
git commit -m "fix(ls): distinguish no-open-conversation from a dead endpoint"
```

---

## Task 4: `agy_look` must keep the NEWEST steps

The fix already exists and is tested — `BoundedView.Summarize` takes `bool newestFirst = false` and `agy_ask` passes `true`. `agy_look` just does not pass it, so a long trajectory drops the tail the caller actually wants.

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/BoundedViewTests.cs`

- [ ] **Step 1: Confirm the call site**

```bash
grep -n "BoundedView.Summarize" clavity-dotnet/src/Clavity.Ls/AgyView.cs
```

Expected: one line reading `return BoundedView.Summarize(trajectory, budgetChars);` — **no** `newestFirst` argument. If it already passes one, STOP.

- [ ] **Step 2: Write the failing test**

Append to `clavity-dotnet/tests/Clavity.Ls.Tests/BoundedViewTests.cs`, inside the existing test class. Match the trajectory-construction helper the neighbouring `Ask_newestFirst_*` tests use — read them first and reuse that helper rather than inventing one:

```csharp
    [Fact]
    public void Look_keeps_the_newest_steps_when_the_budget_is_tight()
    {
        // agy_look's whole purpose is "what just happened", so a tight budget must drop the OLDEST steps.
        var t = /* same helper the Ask_newestFirst_* tests use, with enough steps to overflow the budget */;

        var v = BoundedView.Summarize(t, budgetChars: 8000, maxStepChars: 16000, newestFirst: true);

        // Assert IDENTITY of the boundary step, never a count — a count is invariant under any permutation.
        Assert.Contains("<the newest step's distinctive text>", v);
        Assert.DoesNotContain("<the oldest step's distinctive text>", v);
    }
```

**Assertion discipline (this repo's standing rule, and ROADMAP §11's whole subject):** assert *which* step survived, never *how many*. `Count(SortAndTruncate(c, K))` is invariant under any permutation before truncation, so a cardinality assertion passes over reversed sort logic.

- [ ] **Step 3: Run it and watch it fail**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~BoundedViewTests"
```

Expected: the new test FAILS.

- [ ] **Step 4: Pass `newestFirst` at the `agy_look` call site**

In `clavity-dotnet/src/Clavity.Ls/AgyView.cs`, change the line reading:

```csharp
            return BoundedView.Summarize(trajectory, budgetChars);
```

to:

```csharp
            // agy_look answers "what just happened", so a tight budget must drop the OLDEST steps — same
            // ordering agy_ask already uses. Without this the tail the caller asked for is what gets cut.
            return BoundedView.Summarize(trajectory, budgetChars, newestFirst: true);
```

**Shape check before you write it:** confirm the third parameter of `BoundedView.Summarize` is `maxStepChars` and `newestFirst` is the fourth, so the named argument is required and a positional third argument would silently bind the wrong parameter. Read the signature at `BoundedView.cs`.

- [ ] **Step 5: Run tests, verify green**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests
```

Expected: `Failed: 0`.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AgyView.cs clavity-dotnet/tests/Clavity.Ls.Tests/BoundedViewTests.cs
git commit -m "fix(ls): agy_look keeps the newest trajectory steps under a tight budget"
```

---

## Task 5: An idle-wait expiry must attempt a final readback before it throws

**Depends on Task 2.** Without the raised receive limit this fix inherits the same 4 MB ceiling and fails on exactly the large replies it exists to rescue — the entry says so itself under "Sibling constraint".

**Do not rewrite the idle-wait.** `AgyView.WaitForIdleWithProgressAsync` already implements progress-aware waiting, a stall window, an absolute max, and `BuildModalHang`. The entry's proposed remedy ("poll `agy_status` until idle, then retrieve the trajectory") is *mostly already there*. The residual defect, per the entry's own `last-triaged` oracle, is narrower: **on expiry it throws rather than re-polling.**

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs` (or a new file if the fake-client harness lives elsewhere — read it first)

- [ ] **Step 1: Read the existing wait before changing it**

Read `WaitForIdleWithProgressAsync` and `BuildModalHang` in full, plus every caller. Confirm the throw site. If the method already performs a trajectory readback on expiry, STOP and report `STATE_MISMATCH: expiry already re-polls`.

- [ ] **Step 2: Write the failing test**

Using the fake/canned client harness the existing tests use (find it — `Clavity.Integration.Tests` carries a fake LS), assert: when the idle wait expires **but the trajectory has advanced past the pre-ask snapshot**, the call returns the completed reply instead of throwing.

Assert on the returned reply's identity — a distinctive fragment of the final step — not on a count or on "did not throw" alone.

- [ ] **Step 3: Run it and watch it fail**

Expected: it throws the modal-hang exception.

- [ ] **Step 4: Implement — a single bounded readback at the throw site**

Before throwing, perform one final `GetCascadeTrajectoryAsync`. If the trajectory has advanced beyond the `before` snapshot, return the new steps as the reply. Only if the step counter is genuinely **not** advancing does the existing throw stand.

Keep the existing exception path intact for the genuinely-stuck case: this is an added branch, not a replacement. Report stalled only when there is no progress.

- [ ] **Step 5: Run the full suite**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests
```

Expected: `Failed: 0` in both.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AgyView.cs clavity-dotnet/tests/Clavity.Ls.Tests
git commit -m "fix(ls): recover a completed reply on idle-wait expiry instead of discarding it"
```

---

## Task 6: Retire the four entries and update the roadmap

Only now — an entry is retired by a shipped fix plus its regression test, never by intent.

**Files:**
- Modify: `agy-autotrain/docs/fix-the-tool-backlog/grpc-default-max-message-size.md`
- Modify: `agy-autotrain/docs/fix-the-tool-backlog/conversation-scoped-tools-vs-no-open-conversation.md`
- Modify: `agy-autotrain/docs/fix-the-tool-backlog/agy-look-tail-truncation.md`
- Modify: `agy-autotrain/docs/fix-the-tool-backlog/stalled-reply-recoverable-not-lost.md`

- [ ] **Step 1: Check each entry's own retirement gate**

`conversation-scoped-tools-vs-no-open-conversation.md` states: *"Retirement gated on a permanent regression test asserting the two failure modes map to distinct errors."* Read each entry's Notes section and confirm its named gate is satisfied by a test you actually ran. **An unsatisfied gate means the entry stays `open`** — say so rather than flipping it.

- [ ] **Step 2: Flip `status:` and record the fix**

For each entry whose gate is satisfied, set `status: fixed` in the frontmatter and append:

```markdown
## Fixed — 2026-08-07

Shipped in `<commit sha>`. Regression test: `<test file>::<test name>`.
```

- [ ] **Step 3: Verify no entry was missed and none was flipped early**

```bash
grep -n "^status:" agy-autotrain/docs/fix-the-tool-backlog/*.md
```

Expected: the four entries above read `fixed`; `working-vs-stuck-step-delta` stays `wont-fix`; `curate-nudge-age-reads-drain-log-dates` and `idle-wait-false-modal` stay `fixed`; `inbox-snapshot-misses-slash-command-path` stays **`open`** (it belongs to plan 2).

- [ ] **Step 4: Commit**

```bash
git add agy-autotrain/docs/fix-the-tool-backlog/
git commit -m "docs(backlog): retire the four LS-bridge entries fixed by this plan"
```

---

## Task 7: Final verification gate

- [ ] **Step 1: Positive control — the diff must not be empty**

```bash
git diff --name-only <PLAN_BASE>..HEAD | wc -l
```

Expected: a non-zero count. A gate that passes on an empty diff examined nothing.

- [ ] **Step 2: Clean tree**

```bash
git status --porcelain
```

Expected: no output.

- [ ] **Step 3: Full suite, both projects**

```bash
cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests
```

Expected: `Failed: 0` in both, and the `Clavity.Ls.Tests` passing count is **strictly greater** than Task 0 Step 2's baseline.

- [ ] **Step 4: The defect is actually gone — assert on behaviour, not on the diff**

```bash
grep -c "shut down or restarted" clavity-dotnet/src/Clavity.Ls/ChannelDown.cs
```

Expected: `1` — exactly one occurrence, in the `TransportDown` arm. A `0` means the genuine-transport-death case lost its remedy text; a `2+` means an arm still carries the false narrative.

- [ ] **Step 5: AGY-CAPSTONE**

This plan is not complete until a capstone reviews `<PLAN_BASE>..HEAD` — the committed implementation, not this document — and reaches owner-confirmed GREEN. Do not write a completion marker before that.

---

## Self-review

Run against the four entries and the two owner rulings:

1. **Coverage.** `grpc-default-max-message-size` → Tasks 1+2 (both halves: the cap *and* the hint, which the entry insists matters as much). `conversation-scoped-tools` → Task 3. `agy-look-tail-truncation` → Task 4. `stalled-reply-recoverable-not-lost` → Task 5. `inbox-snapshot-misses-slash-command-path` is **deliberately excluded** (a hook fix, plan 2) — that is scope, not an omission.
2. **Ordering holds.** Task 2 precedes Task 5 (the entry's stated sibling constraint). Task 1 precedes 2 and 3 (both attach to the classifier).
3. **No fabricated wire values.** Task 3's status code is measured, not guessed — the one place this plan could have invented a contract, it refuses to.
4. **Placeholders.** Task 3 Step 2 and Task 4 Step 2 carry `<MEASURED_*>` / helper markers. These are **measurement outputs**, not deferred decisions: each has a command that produces the value and a stated stop condition if it cannot. Task 5 Steps 2 and 4 are specified as intent rather than exact code because the idle-wait internals must be read first — Step 1 enforces that read, and a `STATE_MISMATCH` stop guards it.
5. **Type consistency.** `Fault` enum introduced in Task 1 (`TransportDown`, `PayloadTooLarge`), extended in Task 3 (`NoConversation`). `Classify` and `Hint` are the only members added; `IsChannelDown` and `Diagnose` are untouched, so `AgyStatusShapeTests.cs` keeps passing.
6. **Known risk, stated.** Task 1 changes user-visible hint prose. If another suite pinned the old wording, Task 1 Step 5 catches it and gives a rule for which way to resolve it.
