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

**Coverage, stated precisely** (an earlier draft of this plan overstated it and was corrected by a round-2 measurement): there is no `Clavity.Ls.Tests/ChannelDownTests.cs` — Task 1 creates it. `IsChannelDown` and `Diagnose` are covered by `AgyStatusShapeTests.cs`. But `Clavity.Integration.Tests/AgyChannelDownTests.cs` **does** exist and asserts the channel-down envelope across ~7 cases. So the claim is *not* "this is untested"; it is that **no test pins the hint's CAUSE-SPECIFICITY**, which is the defect.

**Additional files the Task 1 change touches — measured, not assumed:**

| File | Why it is in scope |
|---|---|
| `clavity-dotnet/src/Clavity.Mcp/McpTools.cs` | emits `status = ChannelDown.Status` in the shared catch |
| `clavity-dotnet/tests/Clavity.Integration.Tests/AgyChannelDownTests.cs` | ~7 tests assert `status`/`State` == `"channel_down"`. None uses `ResourceExhausted`, so they should still pass — **but Task 1 must run the Integration suite to prove it, not assume it** |
| `clavity-dotnet/src/Clavity.Ls/AskReply.cs` | its XML doc enumerates `State = idle \| working \| unknown \| channel_down`. Adding a value makes that enumeration **stale**, and a doc that lists the wrong permitted values is the same defect class this plan exists to remove. Update it in the same commit |

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
cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests
```

Expected: build succeeds; each run ends with a `Passed!` line and `Failed: 0`. **Record BOTH passing counts.** Task 1 changes a value the Integration suite asserts, so a baseline for only the CI-gate suite would leave the later comparison unanchored. A suite that is already red makes every later "it passes" claim meaningless — if either is red, STOP and report.

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

- [ ] **Step 3b: The machine-readable `status` field must agree with the hint**

**Without this step the plan replaces one lie with another.** `McpTools.RunAsync` emits, in the same JSON object:

```csharp
                status = ChannelDown.Status,          // the constant "channel_down"
                diagnostic = diag,
                hint = ChannelDown.Hint(diag),
```

So a payload-too-large fault would serialize as `{"status":"channel_down", "hint":"...the peer is NOT down..."}` — the field and the narrative contradicting each other. Any supervisor, hook or script that reads `status` rather than parsing prose still records a dead channel.

The codebase already has the pattern to follow: the same method emits distinct top-level statuses `possible_modal` and `waiting_for_human` for other faults. Add a status per fault:

```csharp
    /// <summary>The machine-readable status for a fault. MUST track <see cref="Hint"/>: a consumer reading the
    /// status field and a human reading the hint have to reach the same conclusion.</summary>
    public static string StatusFor(ChannelDiagnostic d) => Classify(d) switch
    {
        Fault.PayloadTooLarge => "payload_too_large",
        _ => Status,
    };
```

Then in `clavity-dotnet/src/Clavity.Mcp/McpTools.cs`, in the `catch (Exception ex) when (ChannelDown.IsChannelDown(ex))` block, change `status = ChannelDown.Status,` to `status = ChannelDown.StatusFor(diag),`. Apply the same change wherever `AgyView.StatusAsync` builds its `AgyStatus` from `ChannelDown.Status`.

Add to `ChannelDownTests.cs`:

```csharp
    [Fact]
    public void The_status_field_and_the_hint_never_contradict_each_other()
    {
        var big = new ChannelDiagnostic("ResourceExhausted", "Received message exceeds the maximum configured size");
        Assert.Equal("payload_too_large", ChannelDown.StatusFor(big));
        Assert.DoesNotContain("shut down or restarted", ChannelDown.Hint(big));

        var dead = new ChannelDiagnostic("Unavailable", "connection refused");
        Assert.Equal("channel_down", ChannelDown.StatusFor(dead));
        Assert.Contains("shut down or restarted", ChannelDown.Hint(dead));
    }
```

**Consumer check before you commit — and it is a STOP, not a note.** `status` is a wire value other code may switch on. Adding a new value is a contract change.

```bash
grep -rn '"channel_down"\|channel_down' --include=*.cs --include=*.sh --include=*.ps1 --include=*.json . | grep -v '/obj/\|/bin/'
```

Use the **Grep tool** rather than shell `rg` for the repo-wide sweep (preamble item 4).

- **Only `ChannelDown.cs` and its tests match** → proceed.
- **Anything else matches — a hook, a script, another C# switch** → **STOP and report `CONTRACT: <path> consumes "channel_down"`.** Do not commit, and do not "helpfully" update the consumer: whether the bridge may emit a new top-level status is the owner's call. An executor who notes this and commits anyway has shipped a silent contract break, which is the same class of defect as the hint that lies.

- [ ] **Step 4: Run the tests and verify they pass**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~ChannelDownTests"
```

Expected: all three PASS.

- [ ] **Step 5: Run BOTH suites — the wording change may break a pinned string elsewhere**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests && dotnet test tests/Clavity.Integration.Tests
```

🔴 **The Integration suite is not optional here, even though it is not the CI gate.** `AgyChannelDownTests.cs` asserts the exact `status`/`State` value this task changes, across ~7 cases. Running only `Clavity.Ls.Tests` would leave the change's blast radius unmeasured.

Expected: `Failed: 0` in both, and `Clavity.Ls.Tests` passing count **≥ Task 0 Step 2's count + 3**. If another test pinned the old "channel is down" prose, fix **that test's expectation** only if its intent was to pin the shutdown narrative for a genuine transport death; if it pinned the prose for a non-transport fault, that test was encoding the defect — report it rather than editing it silently.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/ChannelDown.cs \
        clavity-dotnet/src/Clavity.Ls/AskReply.cs \
        clavity-dotnet/src/Clavity.Mcp/McpTools.cs \
        clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs
git commit -m "fix(ls): ChannelDown.Hint names the real fault instead of always blaming a peer shutdown"
```

**Explicit paths, never `git add -A`** — a broad add has twice swept unintended files in this repo, once onto a public remote. If Step 3b's consumer check made you touch a file not listed here, add it deliberately and say why in the commit body.

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

**Why a number and not `null`.** Unbounded was rejected so a runaway response still fails loudly instead of exhausting memory. But the ceiling is not free, and the cost is worth stating: `AgyView.StatusAsync` fetches the **entire** `CascadeTrajectory` on every pre-fire check, only to read `CascadeId` and `Steps.Count`. Today the 4 MB default caps that; at 64 MB every `agy_status` call may pull and deserialize up to 64 MB over loopback. That is a **pre-existing inefficiency this change amplifies**, not one it creates — and by the standing rule that a pre-existing defect's age is not a disposition, it is recorded here rather than waved off. Do **not** fix it in this task: note it, and if `agy_status` latency degrades measurably after this lands, raise it as its own tracked item with the measurement attached.

- [ ] **Step 3: Build and run the full suite**

```bash
cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests
```

Expected: build succeeds, `Failed: 0`.

- [ ] **Step 3b: Confirm the ceiling that actually binds is the client's**

`MaxReceiveMessageSize` is a **client receive** limit. If agy's language server enforces its own **send** cap, raising the client limit moves nothing and this task ships a no-op that looks like a fix.

The suite cannot answer this — no unit test crosses a real 4 MB gRPC response. Verify against the live peer: drive a conversation until its trajectory exceeds 4 MB (per the entry's repro, accumulated **bytes**, not step count — asks have succeeded at 996/1111/1203/1290 steps, so never use step count as the trigger), then call `agy_look`.

- **Call succeeds** → the client limit was the binding constraint. Record the measured trajectory size in the entry's Fixed section.
- **Call still fails `ResourceExhausted`** → a server-side cap binds too. The Task 1 hint is still correct and still valuable (it stops the false shutdown report), but the *cap* half is unfixed. Report `PARTIAL: server-side send cap binds at <size>` and leave `grpc-default-max-message-size` at `status: open` in Task 6.

**If no live peer is available,** do not silently skip: record it as unverified and leave the entry `open`. An unverified ceiling fix is exactly the "confirm X with no deliverable" shape the bar killed §4 for.

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

- [ ] **Step 1b: Verify the fault REACHES the classifier at all — this task is void without it**

`Hint` is only ever called from inside `catch (Exception ex) when (ChannelDown.IsChannelDown(ex))`. `IsChannelDown` admits an `RpcException` (non-`Cancelled`), `ObjectDisposedException`, `LsDiscoveryException`, or an `AgyModelUnavailableException` wrapping one of those — **and nothing else**.

So if the no-open-conversation failure surfaces as anything else (an `InvalidOperationException` from local id resolution, a null-conversation guard, a `Cancelled` status), it never enters the handler, and extending `Classify`/`Hint` **changes nothing while appearing to work**.

Confirm from the Step 1 reproduction which exception type actually escapes, then take one of two paths:

- **It is admitted by `IsChannelDown`** → proceed to Step 2 unchanged.
- **It is NOT admitted** → the fix is no longer a `Hint` mapping. `IsChannelDown` must be widened to admit it, or the fault caught where it is raised. STOP and report `SCOPE: no-open-conversation escapes as <ExceptionType>, not admitted by IsChannelDown` and let the owner rule before writing code.

A test that constructs a `ChannelDiagnostic` by hand (Step 2) passes either way — it exercises `Hint` directly and cannot see this gap. That is exactly why this step exists and why it is not optional.

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

- [ ] **Step 2: Write the failing test — against `AgyView`, NOT against `BoundedView`**

🔴 **The obvious test does not work, and it fails in the direction that looks like success.** `BoundedViewTests.cs` already contains `BoundedView.Summarize(t, budgetChars: 8000, maxStepChars: 16000, newestFirst: true)` and it already passes — `BoundedView` is not the broken component. A new test calling `Summarize(..., newestFirst: true)` directly would go **green on the first run**, and an executor following "watch it fail" would either fake the red or conclude the defect is already fixed. The unwired call site is `AgyView`'s `agy_look` path; only a test that goes through **`AgyView.LookAsync`** can pin this.

Write the test against `AgyView.LookAsync` using the fake/canned LS client the existing tests use. Find that harness first:

```bash
grep -rn "class .*Fake\|CannedHandler\|LsClient" clavity-dotnet/tests/ | head -20
```

`clavity-dotnet/tests/Clavity.Integration.Tests/LsFramingConformanceTests.cs` builds a client over a `CannedHandler`; if the fake-LS harness lives in `Clavity.Integration.Tests`, put this test there and run it with that project's command. **State in the test file which project it lives in** — the two suites have different run commands and only one is the CI gate.

The test: drive `LookAsync` against a canned trajectory with more steps than the budget allows, then assert **identity** of the boundary steps:

```csharp
    [Fact]
    public async Task Look_keeps_the_newest_steps_when_the_budget_is_tight()
    {
        // agy_look answers "what just happened", so a tight budget must drop the OLDEST steps.
        // This goes through AgyView.LookAsync deliberately: BoundedView already handles newestFirst
        // correctly and testing it directly would pass without exercising the defect.
        var view = /* AgyView over the fake client, canned with a trajectory that overflows the budget */;

        var v = await view.LookAsync(/* a budget smaller than the trajectory */);

        Assert.Contains("<the NEWEST step's distinctive text>", v);
        Assert.DoesNotContain("<the OLDEST step's distinctive text>", v);
    }
```

**Assertion discipline (this repo's standing rule, and ROADMAP §11's whole subject):** assert *which* step survived, never *how many*. `Count(SortAndTruncate(c, K))` is invariant under any permutation before truncation, so a cardinality assertion passes over reversed sort logic.

- [ ] **Step 3: Run it and watch it fail for the RIGHT reason**

Run the suite the test landed in. Expected: it FAILS because the **oldest** step survived and the newest was dropped.

🔴 **If it passes on the first run, do NOT proceed to Step 4.** A green here means the test is not reaching the defect — almost certainly because it is exercising `BoundedView` rather than `AgyView`. Fix the test's target first.

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

### 🔴 STOP — this task's PREMISE is unproven, and the entry's proposed fix is already implemented

An adversarial panel over this plan (2026-08-07) killed the original version of this task. Measured against `AgyView.WaitForIdleWithProgressAsync`:

- The entry's remedy — *"Only if the step counter is genuinely NOT advancing should the call be reported as stalled"* — **is what the code already does.** `lastProgress` starts at `before + 1` and the loop resets its stall window on every advance (`if (total > lastProgress) lastProgress = total;`). It throws only when a full window passed with **no** new steps.
- Therefore the naive condition "trajectory advanced past `before` ⇒ return it as the reply" is **true on essentially every modal hang** — any turn that emitted a step and then blocked on a dialog. Implementing it would convert genuine modal-hang detection into a false "completed reply", regressing the F5/F2/F3 machinery.
- The method returns `Task`, not a reply, and has **four** throw sites. "Return the new steps" is not expressible without a signature change.
- The existing probe is deliberately wrapped in `catch (RpcException) when (!cancellationToken.IsCancellationRequested)` with a comment stating that an unguarded re-fetch would *"ESCAPE the loop as an uncaught RpcException -> central catch -> channel_down"*. An unguarded final readback does exactly that.

**So do not implement a fix here until the defect is demonstrated.** Proceed as measurement-first.

**Files:** none until Step 3 resolves.

- [ ] **Step 1: Read the machinery before forming any opinion**

Read `WaitForIdleWithProgressAsync` in full (all four throw sites), `BuildModalHang`, and every caller. Note that the happy path returns as soon as the server reports fully idle.

- [ ] **Step 2: Derive the precise conditions under which the claimed loss can occur**

The turn must have **completed** while the wait still expired. Given the happy path returns on the server's fully-idle signal, that requires the server's idle signal to fail or lag while the turn finished. Write down the exact state that produces it.

Note what the entry's own evidence does and does not cover: its corroboration is verify-harness probe A2, which is a **truncation** result — and the entry itself says *"The truncation path and this stall path differ in mechanism"*. So A2 is **not** evidence for this task's premise.

- [ ] **Step 3: Decide, and record the decision**

- **If a reachable state produces the loss** → write the failing test for *that* state through the fake-LS harness, then implement the narrowest fix. Any readback MUST sit inside the existing `RpcException` guard, and the return path MUST distinguish "turn completed" from "made progress then hung" — progress alone is not completion.
- **If no reachable state produces it** → the entry is **falsified against current code**. Report it, leave the entry `open` with the measurement recorded, and take the task no further. This is a legitimate outcome and costs nothing but the measurement.

**Either way this task ships no code without a demonstrated defect.** The plan's other four fixes stand alone; this one is deliberately gated.

- [ ] **Step 4: Commit only if Step 3 produced code**

```bash
git add clavity-dotnet/src/Clavity.Ls/AgyView.cs clavity-dotnet/tests
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

Expected, **all nine lines** the glob returns — `*.md` matches `_template.md` too, and an expected list that omits it makes a correct run look wrong:

| file | expected `status:` |
|---|---|
| `_template.md` | `open` — it is the template, never flip it |
| `agy-look-tail-truncation.md` | `fixed` |
| `conversation-scoped-tools-vs-no-open-conversation.md` | `fixed` **only if** Task 3 completed — it has TWO stop paths (`BLOCKED: cannot reproduce`, and `SCOPE: … not admitted by IsChannelDown`). If either fired, it stays `open` |
| `grpc-default-max-message-size.md` | `fixed` — **unless** Task 2 Step 3b reported `PARTIAL`, in which case `open` |
| `stalled-reply-recoverable-not-lost.md` | `fixed` **only if** Task 5 Step 3 produced code; otherwise `open` |
| `curate-nudge-age-reads-drain-log-dates.md` | `fixed` (already) |
| `idle-wait-false-modal.md` | `fixed` (already) |
| `inbox-snapshot-misses-slash-command-path.md` | `open` — belongs to plan 2 |
| `working-vs-stuck-step-delta.md` | `wont-fix` |

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

## Panel ledger — AGY-AFTER round 1, RED (do NOT re-raise)

Solo pass (2 findings) + live-peer escalation (8 findings, 7 seats). **All 10 verified by measurement before folding; none refuted.** Brief: `.clavity/seams/ls-bridge-plan-panel.md`.

| # | Finding | Fold |
|---|---|---|
| 1 | Task 3 could ship while the fault never reaches `ChannelDown` — `Hint` is only called under a `when (IsChannelDown(ex))` filter | Task 3 Step 1b: verify admission, STOP if not admitted |
| 2 | `MaxReceiveMessageSize` is a *client receive* limit; a server send cap would make Task 2 a no-op | Task 2 Step 3b: live verification, `PARTIAL` report |
| 3 | `status` field would still say `channel_down` while the hint says the peer is healthy | Task 1 Step 3b: `StatusFor()` + consumer check |
| 4 | Task 4's test called `BoundedView.Summarize` — already green, bypasses the defect entirely | Task 4 Step 2 retargeted at `AgyView.LookAsync` |
| 5 | Task 5's `total > before` fires on every modal hang that emitted a step | Task 5 gated; premise must be demonstrated first |
| 6 | `WaitForIdleWithProgressAsync` returns `Task` and has 4 throw sites — "return the steps" is inexpressible | same |
| 7 | An unguarded final readback escapes as a false `channel_down`, which a code comment explicitly warns against | same |
| 8 | An un-stabilized snapshot can project a null `Answer` under a success status | same |
| 9 | 64 MB ceiling amplifies `StatusAsync`'s full-trajectory fetch | Task 2: cost recorded, explicitly not fixed here |
| 10 | Task 6's `*.md` glob matches `_template.md`, omitted from the expected list | Task 6 Step 3: full nine-row table |

🔴 **The two findings that would have cost the most were both "the test passes when it should fail":** #4 (test targets a component that already works) and #5 (a fix that regresses modal-hang detection while looking correct). Both are Law 1 — defects found by reasoning about *running* code, not by reading the plan.

**Round 2 is owed** (owner's standing ruling: repeat until green). Tasks 1, 4 and 5 changed materially, and in this project a fold has twice spawned its own defect.

## Self-review

Run against the four entries and the two owner rulings:

1. **Coverage.** `grpc-default-max-message-size` → Tasks 1+2 (both halves: the cap *and* the hint, which the entry insists matters as much). `conversation-scoped-tools` → Task 3. `agy-look-tail-truncation` → Task 4. `stalled-reply-recoverable-not-lost` → Task 5. `inbox-snapshot-misses-slash-command-path` is **deliberately excluded** (a hook fix, plan 2) — that is scope, not an omission.
2. **Ordering holds.** Task 2 precedes Task 5 (the entry's stated sibling constraint). Task 1 precedes 2 and 3 (both attach to the classifier).
3. **No fabricated wire values.** Task 3's status code is measured, not guessed — the one place this plan could have invented a contract, it refuses to.
4. **Placeholders.** Task 3 Step 2 and Task 4 Step 2 carry `<MEASURED_*>` / helper markers. These are **measurement outputs**, not deferred decisions: each has a command that produces the value and a stated stop condition if it cannot. Task 5 Steps 2 and 4 are specified as intent rather than exact code because the idle-wait internals must be read first — Step 1 enforces that read, and a `STATE_MISMATCH` stop guards it.
5. **Type consistency.** `Fault` enum introduced in Task 1 (`TransportDown`, `PayloadTooLarge`), extended in Task 3 (`NoConversation`). `Classify` and `Hint` are the only members added; `IsChannelDown` and `Diagnose` are untouched, so `AgyStatusShapeTests.cs` keeps passing.
6. **Known risk, stated.** Task 1 changes user-visible hint prose. If another suite pinned the old wording, Task 1 Step 5 catches it and gives a rule for which way to resolve it.
