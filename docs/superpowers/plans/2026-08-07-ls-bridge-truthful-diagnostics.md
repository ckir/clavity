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

### 🔴 What this plan still actually BUILDS, after two review rounds

State it plainly, because the answer changed twice and a stale scope claim is the defect this whole epic exists to remove:

| Task | Status after rounds 1-2 |
|---|---|
| **1 — `ChannelDown` classifier + `StatusFor`** | **BUILDS.** The core fix. |
| **2 — gRPC receive limit** | **BUILDS** — code + a deterministic oversized-message test. Whether the cap *helps in practice* stays open until Step 3c's optional live probe; the hint half stands regardless. |
| **4 — `agy_look` newestFirst** | **BUILDS.** Smallest and most certain. |
| 3 — no-open-conversation | **BUILDS NOTHING — CLOSEABLE.** Remedy shipped (`waiting_for_human`); retirement gate met by `AgyChannelDownTests.cs:284` + `:358`. Peer-confirmed. |
| 5 — stalled-reply recovery | **BUILDS NOTHING — CLOSEABLE.** Remedy shipped via `lastProgress`; entry names no test gate. Peer-confirmed. |

🔴 **Two of the four entries this plan was written to fix need a DISPOSITION, not code — both confirmed against their own acceptance text by an independent reviewer.** That is the review working, not the plan failing. But it means the plan delivers **three fixes, not five**: a truthful fault classifier, a deliberate receive ceiling, and a corrected `agy_look` ordering. **Do not let a later reader infer that five tasks means five fixes.**

**Plan 2's gate, recorded so it is not skipped:** ROADMAP §0 states the 1b trigger placement "is to be **decided from 1a's data rather than guessed**". The 1a recorder exists at `scripts/discipline-reaching-report.ps1`. Plan 2's first task must RUN it and choose the trigger from its output. The witness trial (step 3) is KILLED — do not reinstate it.

---

## Preamble — read before the evidence in any task

These are not general advice. Each one cost a real defect in the epic that produced this plan.

0. **Read the STATUS LINE before the evidence.** A grep hit inside a section whose heading says `SHIPPED` is not an open item. This plan's own epic nearly ordered a shipped item killed three times, always from stopping at the hit.
1. **Every number in this plan is stale.** Line numbers cited here were measured 2026-08-07 against `d895cf3` and the tasks below *edit those files*. Anchor to the quoted TEXT and re-locate; never trust an offset, and never derive a line number by counting from a `sed` window.
2. **A fix must be RUN, not read.** Re-run every command after you change it.
3. **A probe needs a control that CAN fail.** Before believing a zero, run the same probe against something known-present.
4. **`rg` in the Bash tool on this machine is GNU grep 3.0, not ripgrep.** `--no-ignore` and `--glob` produce silent null results. Measured 2026-08-07. Use the Grep tool for repo-wide searches.
5. 🔴 **`dotnet test --filter` EXITS 0 WHEN IT MATCHES NOTHING — measured, not assumed.** Run 2026-08-07 against this repo:

   ```
   $ dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~ThisClassDoesNotExistAnywhere"
   No test matches the given testcase filter `FullyQualifiedName~ThisClassDoesNotExistAnywhere` in ...Clavity.Ls.Tests.dll
   === EXIT CODE: 0 ===
   ```

   A typo in a class name, or a test file never added to the project, reports **success**. Every filtered run in this plan is therefore ambiguous between "passed" and "never ran". **Whenever a step says a filtered run should PASS, read the printed test COUNT and confirm it matches the number of tests you wrote** — never accept the absence of a failure as evidence. This is the same class as the plan's own `BoundedView` defect: a green that was never capable of going red.
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

Then in `clavity-dotnet/src/Clavity.Mcp/McpTools.cs`, in the `catch (Exception ex) when (ChannelDown.IsChannelDown(ex))` block, change `status = ChannelDown.Status,` to `status = ChannelDown.StatusFor(diag),`. Apply the same change in `AgyView.StatusAsync` where it builds its `AgyStatus` from `ChannelDown.Status`.

🔴 **The two surfaces are NOT the same field, and a test enforces the difference.** `agy_ask` / `agy_look` fail into an anonymous envelope with a lowercase `status`; `agy_status` returns the `AgyStatus` record, which serializes PascalCase `State`. `AgyChannelDownTests.cs:257-258` asserts **both** — `State == "channel_down"` **and** that a lowercase `status` property is *absent*:

```csharp
Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
Assert.False(doc.RootElement.TryGetProperty("status", out _));
```

So do **not** "unify" the two by adding a lowercase `status` to the `AgyStatus` shape — that test exists to prevent exactly that, and it would be a wire-contract break. Change the *value* on each surface, never the field name.

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

Expected: `Failed: 0` in both, and `Clavity.Ls.Tests` passing count **≥ Task 0 Step 2's count + 4**.

🔴 **Why 4 and not 3.** Step 1 adds three tests; Step 3b adds a fourth (`The_status_field_and_the_hint_never_contradict_each_other`). A `+3` threshold passes for an executor who implements Step 1 and **silently skips Step 3b entirely** — the wire-contract half, which is the half that stops the status field contradicting the hint. The gate must be able to detect the omission it is guarding against. If another test pinned the old "channel is down" prose, fix **that test's expectation** only if its intent was to pin the shutdown narrative for a genuine transport death; if it pinned the prose for a non-transport fault, that test was encoding the defect — report it rather than editing it silently.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/ChannelDown.cs \
        clavity-dotnet/src/Clavity.Ls/AskReply.cs \
        clavity-dotnet/src/Clavity.Ls/AgyView.cs \
        clavity-dotnet/src/Clavity.Mcp/McpTools.cs \
        clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs
git commit -m "fix(ls): ChannelDown.Hint names the real fault instead of always blaming a peer shutdown"
```

**Explicit paths, never `git add -A`** — a broad add has twice swept unintended files in this repo, once onto a public remote. If Step 3b's consumer check made you touch a file not listed here, add it deliberately and say why in the commit body.

---

## Task 2: Set the gRPC receive limit deliberately

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/LsChannel.cs`
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/LsChannelIntegrationTests.cs` (Step 3b's oversized-message test)

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

### The verification splits in two, and only one half needs the live peer

`MaxReceiveMessageSize` is a **client receive** limit, so two separate questions decide whether this task is a real fix:

1. **Does raising the client limit let an oversized response through at all?** — deterministic, no peer needed.
2. **Does agy's own server cap what it sends?** — if it does, the client change is inert in practice, and only the live peer can answer.

An earlier draft asked one expensive live probe to answer both. It cannot: a live success proves both at once, but a live *failure* cannot tell you which half failed.

- [ ] **Step 3b: The deterministic half — a permanent regression test, no agy required**

The harness already exists. `clavity-dotnet/tests/Clavity.Integration.Tests/LsChannelIntegrationTests.cs:25-38` stands up an in-process **Kestrel h2c gRPC server** with a `FakeLanguageServer` and drives it through `LsChannel.ForHttpPort(PortOf(app))` — the exact method this task modifies:

```csharp
private static async Task<WebApplication> StartFakeLsAsync(GetConversationMetadataResponse response)
{
    var builder = WebApplication.CreateBuilder();
    builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
    builder.WebHost.UseUrls("http://127.0.0.1:0");
    ...
}
```

Add a test to that file which returns a response carrying a payload **larger than gRPC's 4 MB default** (e.g. a ~5 MB string in a proto field) and asserts the round trip **succeeds**.

**Run it — and note Step 3 above does NOT:** Step 3 runs only `Clavity.Ls.Tests`, while this test lives in the Integration project. Without this command the new test is never executed:

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests
```

**Prove it is non-vacuous before trusting it** (the repo's assertion-strength rule, and the reason this plan exists): temporarily revert `MaxReceiveMessageSize` and confirm this specific test goes **red** with `ResourceExhausted`. A test that passes both with and without the fix is measuring nothing. Then restore the fix and confirm it goes green.

**Read the printed test count** — a filtered run that matches nothing exits 0 (preamble item 5).

- [ ] **Step 3c: The live half — a qualification probe, NOT a blocking gate**

This answers only question 2, and it is exploratory. **Do not make it a CI gate**: forcing a real agy trajectory past 4 MB burns quota and wall-clock, and a suite that must inflate a live conversation to pass will simply be disabled. (Measured 2026-08-07: a heavily-used session reached 251 steps across five large round-trips without approaching the ceiling — so reaching it deliberately is costly.)

When convenient, drive a real conversation until its trajectory exceeds 4 MB — accumulated **bytes**, never step count; asks have succeeded at 996 / 1111 / 1203 / 1290 steps — then call `agy_look`.

- **Succeeds** → the client limit was the binding constraint. Record the measured size in the entry's Fixed section.
- **Still fails `ResourceExhausted`** → a server-side send cap binds too. Task 1's hint half remains correct and valuable; the *cap* half is not effective in practice. Report `PARTIAL: server-side send cap binds at <size>` and leave `grpc-default-max-message-size` at `status: open` in Task 6.
- **Not run** → say so plainly. Step 3b still stands on its own: it proves the code is right, which is what the commit claims.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/LsChannel.cs \
        clavity-dotnet/tests/Clavity.Integration.Tests/LsChannelIntegrationTests.cs
git commit -m "fix(ls): set MaxReceiveMessageSize deliberately instead of inheriting gRPC's 4 MB default"
```

---

## Task 3: A live endpoint with no open conversation must not report a shutdown

### 🔴 STOP — the entry's remedy appears ALREADY SHIPPED, and its own oracle was a false negative

Round-2 panel finding, verified at source. The entry asks for *"a distinct typed error with a Hint naming the real cause and the real remedy — 'no agy conversation is open; open one in agy, then retry' — instead of the current generic hint that blames a shutdown."*

That exists. `AgyView.cs:379-384`:

```csharp
// Reached-empty means "agy is up, waiting for the human to start a conversation" — UNLESS we later saw
// the channel die, in which case it's dead and the operator must restart (channel_down), not wait.
if (reachedLsButEmpty && !sawChannelDeath)
    throw new AgyConversationPendingException(
        "agy is running but has no conversation yet. WAIT for the human to start or continue the " +
        "agy session, then try again — do NOT auto-retry in a loop.");
```

`McpTools.cs:52-55` catches it and returns `{"status":"waiting_for_human", ...}` — a distinct status, a truthful cause, and the right remedy. It even discriminates against channel death explicitly (`!sawChannelDeath`).

🔴 **Why the sweep missed it — and this is the reusable lesson.** The entry's `last-triaged` line records its oracle as: *"no 'no open conversation'/NoConversation/conversation-existence split anywhere in Clavity.Ls/*.cs -> confirmed still open"*. **The probe searched for names the code does not use.** The implementation is called `AgyConversationPendingException` / `reachedLsButEmpty`. A probe keyed on invented vocabulary cannot return its failing answer — it reports ABSENT for something present. **This is the fourth recorded-open-but-shipped item in this epic, and the first caused by the probe's wording rather than by an unopened section.**

**What may still be real, and it is narrow:** the shipped path fires on the *discovery / boot-race* route, where the trajectory map is reachable-but-empty. A conversation that was resolved and then closed **mid-session** could still surface as an `RpcException` and fall through to `ChannelDown`. That is unproven.

**So this task is now measurement-first, and its most likely outcome is that the entry is re-dispositioned rather than fixed.**

**This task has a measurement step before its code step, deliberately.** Do not guess a status code — measure it.

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs`

- [ ] **Step 1: Reproduce and capture the real diagnostic**

Follow `agy-autotrain/docs/fix-the-tool-backlog/conversation-scoped-tools-vs-no-open-conversation.md` "Steps to Reproduce": with the agy host running and **no** conversation open, call `agy_status`.

**Expected, given the shipped path above: `{"status":"waiting_for_human", ...}`.** If that is what you get, the entry's remedy is already in place. **STOP and report `ALREADY-SHIPPED: waiting_for_human path handles it`** — then take Task 3 no further and mark the entry accordingly in Task 6. Re-dispositioning a KEPT backlog entry is the owner's call, not yours.

**Only if you instead get a `channel_down` envelope blaming a peer shutdown** is there a defect here. In that case record verbatim: the `StatusCode` and the `Detail` string. That pair is the mapping input, and it is the mid-session-close case, not the clean-boot case.

**If you cannot reach either state** (no agy host, or a conversation cannot be closed), STOP and report `BLOCKED: cannot reproduce no-open-conversation state`. Do **not** invent a status code — a wrong mapping makes the hint lie in a new way, which is the defect this plan exists to remove.

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

Add `NoConversation` to the `Fault` enum, extend `Classify` to return it for the measured signal, add its arm to the `Hint` switch, **and add its arm to `StatusFor` — this is not optional.**

🔴 `StatusFor`'s fallback is `_ => Status`, which returns `"channel_down"`. Adding a fault to `Classify`/`Hint` and forgetting `StatusFor` would emit `{"status":"channel_down", "hint":"The channel is healthy but no agy conversation is open…"}` — **recreating the exact contradiction Task 1 Step 3b exists to remove.** Add `Fault.NoConversation => "no_conversation",` and re-run the Step 3b contradiction test. Update `AskReply.cs`'s `State` enumeration in the same commit.

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
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs` — **NOT** `BoundedViewTests.cs`; see Step 2 for why that target is the defect this task is fixing

- [ ] **Step 1: Confirm the call site**

```bash
grep -n "BoundedView.Summarize" clavity-dotnet/src/Clavity.Ls/AgyView.cs
```

Expected: one line reading `return BoundedView.Summarize(trajectory, budgetChars);` — **no** `newestFirst` argument. If it already passes one, STOP.

- [ ] **Step 2: Write the failing test — against `AgyView`, NOT against `BoundedView`**

🔴 **The obvious test does not work, and it fails in the direction that looks like success.** `BoundedViewTests.cs` already contains `BoundedView.Summarize(t, budgetChars: 8000, maxStepChars: 16000, newestFirst: true)` and it already passes — `BoundedView` is not the broken component. A new test calling `Summarize(..., newestFirst: true)` directly would go **green on the first run**, and an executor following "watch it fail" would either fake the red or conclude the defect is already fixed. The unwired call site is `AgyView`'s `agy_look` path; only a test that goes through **`AgyView.LookAsync`** can pin this.

**The test goes in `clavity-dotnet/tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs`** — measured to exist, and it is where `AgyView` is already driven against the in-process fake LS. Read its existing tests and reuse their setup rather than inventing one.

🔴 **This changes Steps 5 and 6 below, and getting it wrong is a silent pass.** If the test lands in the Integration project but Step 5 runs only `Clavity.Ls.Tests`, the suite goes green **without ever running the new test**, and Step 6 would stage the wrong file — leaving the fix committed with zero covering test while every verification step reports success.

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

- [ ] **Step 5: Run BOTH suites, verify green**

```bash
cd clavity-dotnet && dotnet test tests/Clavity.Integration.Tests && dotnet test tests/Clavity.Ls.Tests
```

Expected: `Failed: 0` in both, and the **Integration** count is baseline + 1 — that is where the new test lives. A green `Clavity.Ls.Tests` alone proves nothing about this fix.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/AgyView.cs \
        clavity-dotnet/tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs
git commit -m "fix(ls): agy_look keeps the newest trajectory steps under a tight budget"
```

**Before committing, confirm the staged set matches what you actually edited:** `git status --short` must show no modified-but-unstaged file. Task 7's clean-tree gate will catch a miss, but catching it here costs nothing.

---

## Task 5: An idle-wait expiry must attempt a final readback before it throws

**Depends on Task 2.** Without the raised receive limit this fix inherits the same 4 MB ceiling and fails on exactly the large replies it exists to rescue — the entry says so itself under "Sibling constraint".

**Do not rewrite the idle-wait.** `AgyView.WaitForIdleWithProgressAsync` already implements progress-aware waiting, a stall window, an absolute max, and `BuildModalHang`. The entry's proposed remedy ("poll `agy_status` until idle, then retrieve the trajectory") is *mostly already there*. The residual defect, per the entry's own `last-triaged` oracle, is narrower: **on expiry it throws rather than re-polling.**

**Files: see the STOP block below — this task declares no file set until Step 3 resolves.** If it does produce code, the test belongs in `clavity-dotnet/tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs`, where `AgyView` is already driven against the in-process fake LS — **not** `AskReplyProjectionTests.cs`, which an earlier draft named and which does not host that harness.

### 🔴 STOP — this task's PREMISE is unproven, and the entry's proposed fix is already implemented

An adversarial panel over this plan (2026-08-07) killed the original version of this task. Measured against `AgyView.WaitForIdleWithProgressAsync`:

- The entry's remedy — *"Only if the step counter is genuinely NOT advancing should the call be reported as stalled"* — **is what the code already does.** `lastProgress` starts at `before + 1` and the loop resets its stall window on every advance (`if (total > lastProgress) lastProgress = total;`). It throws only when a full window passed with **no** new steps.
- Therefore the naive condition "trajectory advanced past `before` ⇒ return it as the reply" is **true on essentially every modal hang** — any turn that emitted a step and then blocked on a dialog. Implementing it would convert genuine modal-hang detection into a false "completed reply", regressing the F5/F2/F3 machinery.
- The method returns `Task`, not a reply, and has **four** throw sites. "Return the new steps" is not expressible without a signature change.
- The existing probe is deliberately wrapped in `catch (RpcException) when (!cancellationToken.IsCancellationRequested)` with a comment stating that an unguarded re-fetch would *"ESCAPE the loop as an uncaught RpcException -> central catch -> channel_down"*. An unguarded final readback does exactly that.

**✅ CONFIRMED CLOSEABLE, 2026-08-07.** Asked to rule against the entry's own acceptance text, the peer returned **(a) FULLY SATISFIED — close as already-fixed**, quoting the entry's mitigation (*"Only if the step counter is genuinely NOT advancing should the call be reported as stalled"*) against `AgyView.cs:273-281`'s `lastProgress` loop, and noting the entry names **no test retirement gate** in its Notes — unlike `conversation-scoped-tools`, which does. It was explicitly told a prior (a) on a different entry had no bearing here.

**So this task's expected outcome is a DISPOSITION, not code.** Do not implement a fix unless a reachable defect is demonstrated. Proceed as measurement-first; the likely result is that Task 6 closes the entry.

**Files:** none until Step 3 resolves.

- [ ] **Step 1: Read the machinery before forming any opinion**

Read `WaitForIdleWithProgressAsync` in full (all four throw sites), `BuildModalHang`, and every caller. Note that the happy path returns as soon as the server reports fully idle.

- [ ] **Step 2: Derive the precise conditions under which the claimed loss can occur**

The turn must have **completed** while the wait still expired. Given the happy path returns on the server's fully-idle signal, that requires the server's idle signal to fail or lag while the turn finished. Write down the exact state that produces it.

Note what the entry's own evidence does and does not cover: its corroboration is verify-harness probe A2, which is a **truncation** result — and the entry itself says *"The truncation path and this stall path differ in mechanism"*. So A2 is **not** evidence for this task's premise.

- [ ] **Step 3: Decide, and record the decision**

- **If a reachable state produces the loss** → write the failing test for *that* state through the fake-LS harness, then implement the narrowest fix. Any readback MUST sit inside the existing `RpcException` guard, and the return path MUST distinguish "turn completed" from "made progress then hung" — progress alone is not completion.
- **If no reachable state produces it** → the entry is **confirmed already satisfied by current code** — which is the expected outcome. Report `ALREADY-SHIPPED`, record the measurement, take the task no further, and **close the entry in Task 6 using template (ii)**. Do **not** leave it `open`: an entry whose remedy is demonstrably shipped is exactly what template (ii) exists to close, and leaving it open would fail Task 6 Step 3's expected-status table.

**Either way this task ships no code without a demonstrated defect.** The plan's other three fixes stand alone; this one is deliberately gated.

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

⚠️ **Two different steps in this plan are both called "Step 3b"** — Task 1's (the `status` field) and Task 2's (the oversized-message test). The ledger below inherits that ambiguity. **Always name the task when citing one.**

- [ ] **Step 1: Check each entry's own retirement gate**

`conversation-scoped-tools-vs-no-open-conversation.md` states: *"Retirement gated on a permanent regression test asserting the two failure modes map to distinct errors."* Read each entry's Notes section and confirm its named gate is satisfied by a test you actually ran. **An unsatisfied gate means the entry stays `open`** — say so rather than flipping it.

- [ ] **Step 2: Flip `status:` and record the fix**

There are **two** cases and they take different text. Using the wrong one writes a false provenance claim.

**(i) Fixed BY this plan** — `agy-look-tail-truncation`, and `grpc-default-max-message-size` if Step 3c did not report `PARTIAL`. Set `status: fixed` and append:

```markdown
## Fixed — 2026-08-07

Shipped in `<commit sha>`. Regression test: `<test file>::<test name>`.
```

**(ii) Already fixed BEFORE this plan** — `conversation-scoped-tools-vs-no-open-conversation` and `stalled-reply-recoverable-not-lost`. **There is no commit from this plan to cite, so do not invent one.** Set `status: fixed` and append:

```markdown
## Already fixed — closed 2026-08-07, no code written

The remedy this entry specifies was already implemented. Evidence: `<file:line of the shipped path>`.
Retirement gate: `<the test that pins it, or "entry names no test gate">`.
Recorded open because the triage probe searched for `<the vocabulary it used>`, which the implementation
does not use — the probe could not return its failing answer.
```

🔴 **The provenance line is the point.** An entry closed as already-fixed with a `Shipped in <sha>` claim pointing at this plan's commits would tell a future reader this plan fixed it. It did not. That misattribution is the same class of defect this plan exists to remove.

- [ ] **Step 3: Verify no entry was missed and none was flipped early**

```bash
grep -n "^status:" agy-autotrain/docs/fix-the-tool-backlog/*.md
```

Expected, **all nine lines** the glob returns — `*.md` matches `_template.md` too, and an expected list that omits it makes a correct run look wrong:

| file | expected `status:` |
|---|---|
| `_template.md` | `open` — it is the template, never flip it |
| `agy-look-tail-truncation.md` | `fixed` (template i) |
| `conversation-scoped-tools-vs-no-open-conversation.md` | `fixed` (template **ii**, already-fixed) — peer-confirmed, gate met by `AgyChannelDownTests.cs:284` + `:358`. **`ALREADY-SHIPPED` is the EXPECTED stop and means CLOSE it, not leave it open.** Only stays `open` if Task 3 hit `BLOCKED: cannot reproduce` (state unreachable) or `SCOPE:` (a real mid-session-close defect surfaced) |
| `grpc-default-max-message-size.md` | `fixed` (template i) — **unless** Task 2 **Step 3c** reported `PARTIAL`, in which case `open` |
| `stalled-reply-recoverable-not-lost.md` | `fixed` (template **ii**, already-fixed) — peer-confirmed closeable, entry names no test gate. **Only `open` if Task 5 Step 3 found a reachable defect after all** |
| `curate-nudge-age-reads-drain-log-dates.md` | `fixed` (already) |
| `idle-wait-false-modal.md` | `fixed` (already) |
| `inbox-snapshot-misses-slash-command-path.md` | `open` — belongs to plan 2 |
| `working-vs-stuck-step-delta.md` | `wont-fix` |

- [ ] **Step 4: Commit**

```bash
git add agy-autotrain/docs/fix-the-tool-backlog/
git commit -m "docs(backlog): retire four LS-bridge entries (two fixed here, two verified already-shipped)"
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

## Panel ledger — round 2, RED (do NOT re-raise)

Solo pass (5) + peer escalation (6, seats rotated to **Mechanism Gamer** and **Dependency Cynic**). **All verified by measurement; none refuted.**

| # | Finding | Fold |
|---|---|---|
| 12 | Task 6 had no conditional row for `conversation-scoped-tools` despite Task 3's two stop paths | conditional row added |
| 13 | The consumer check was advisory — an executor could note it and commit | now an explicit `CONTRACT:` STOP |
| 14 | Plan overstated "Hint has zero tests"; `AgyChannelDownTests.cs` exists | claim corrected and narrowed to *cause-specificity* |
| 15 | Task 1 changes a value the Integration suite asserts, but only the CI suite was run | Tasks 0 and 1 now run both suites |
| 16 | `AskReply.cs`'s XML doc enumerates the permitted `State` values and goes stale | added to Task 1's commit |
| 17 | 🔴 **The no-conversation remedy is ALREADY SHIPPED** (`AgyView.cs:381` → `waiting_for_human`), and the entry's own oracle grepped for vocabulary the code never uses | Task 3 gated on an `ALREADY-SHIPPED` stop |
| 18 | Task 3 added `NoConversation` to `Classify`/`Hint` but not `StatusFor`, recreating the contradiction Step 3b removes | `StatusFor` arm made mandatory |
| 19 | Step 3b edits `AgyView.cs`; Step 6's explicit `git add` omitted it | path added |
| 20 | Step 5's `+3` threshold passes for an executor who skips Step 3b entirely | raised to `+4`, with the reason stated |
| 21 | Task 4's test could land in the Integration project while Step 5 ran only the CI suite and Step 6 staged the wrong file — green with zero coverage | file named explicitly; Steps 5 and 6 corrected |
| 22 | `status` (lowercase, ask/look) and `State` (PascalCase, agy_status) are different fields, and a test asserts lowercase `status` is *absent* | Step 3b now forbids "unifying" them |

🔴 **Finding 17 is the most valuable thing either round produced, and it is a lesson about probes, not about this plan.** The sweep recorded the entry as open on the strength of a grep for `NoConversation` / `no open conversation` — **names the implementation does not use.** It is called `AgyConversationPendingException`. A probe keyed on invented vocabulary reports ABSENT for something present and cannot return its failing answer. **Fourth recorded-open-but-shipped item in this epic; the first caused by the probe's wording rather than an unopened section.**

## Panel ledger — round 3, and the entry ruling

Solo pass (2) + peer escalation (1, seats rotated to **Boundary Smuggler** and **Activation Auditor**; the last two unused of the eleven). **Yield collapsed as expected: 10 → 11 → 3.** Three of four seats returned "no new findings" with reasons, not padding.

| # | Finding | Fold |
|---|---|---|
| 23 | 🔴 **`dotnet test --filter` exits 0 when it matches nothing** — measured live, exit 0 on a typo'd class name. Every filtered step was ambiguous between "passed" and "never ran" | preamble item 5: read the test COUNT, never accept absence-of-failure |
| 24 | The plan's real deliverable shrank to 3 of 5 tasks and nothing said so | honest scope table added |
| 25 | Task 4's `Files:` header still named `BoundedViewTests.cs` after Step 2 was retargeted — an executor scoping from task metadata edits the wrong file | corrected |
| 26 | **Found by my own Law-3 sweep, not the panel:** the same stale pointer had propagated into Task 5's `Files:` block, which *also* contradicted the `Files: none` the STOP block declares | both fixed |

🔴 **Finding 26 is the fourth incomplete-fold in this epic, and it was inside the fix for finding 25.** The pattern is now beyond doubt: **after every fold, grep the whole artifact for the fact you changed.** The panel did not catch it; the grep did, and it was free.

### ✅ The `conversation-scoped-tools` entry is CLOSEABLE — verified, not accepted

The peer ruled **(a) FULLY SATISFIED** against the entry's own acceptance text. **I verified its load-bearing claim rather than banking it**, because a clean round is the least-guarded reply it gives. Both cited tests exist at the cited lines:

- `AgyChannelDownTests.cs:284` — `Boot_race_reached_empty_then_dead_reports_channel_down_not_waiting_for_human`
- `AgyChannelDownTests.cs:358` — `Boot_race_transient_death_then_reached_empty_reports_waiting_for_human_not_channel_down`

The entry's retirement gate reads *"a permanent regression test asserting the two failure modes map to distinct errors."* Those two tests assert exactly that, in both directions. **Gate met.** Task 3 should therefore close the entry rather than build a second path — but **flipping a KEPT entry to closed is the owner's call**, and Task 6 records it as such.

**PANEL VERDICT: round 3 RED (3 folded).**

## Panel ledger — round 4, the RE-GREEN round

🔴 **Why this round exists, and it is a lesson worth keeping.** GREEN was proposed at `e050d59` — then four more changes were committed on top (`7eb2eba`, `aeebbb3`). **A GREEN never covers commits made after it.** Continuing to cite that GREEN would have shipped unreviewed edits under a reviewed banner. The owner caught it; the capstone discipline already states the rule ("re-extend the range after every fold") and I applied it to code but not to this document.

Solo pass (5) + peer escalation (2). **All 11 palette seats were exhausted by round 3**, so this round used the palette's escape hatch: **Fold Auditor · Cold Reader · Provenance Auditor · Convergence Judge.**

| # | Finding | Fold |
|---|---|---|
| 27 | Task 2 Step 3 runs only `Clavity.Ls.Tests`, so Step 3b's new Integration test was **never executed** | run command added to Step 3b |
| 28 | Task 6's single `Shipped in <sha>` template would **misattribute** an already-shipped fix to this plan | split into templates (i) and (ii) |
| 29 | The `PARTIAL` cross-reference still said Step 3b after the live probe moved to Step 3c | corrected |
| 30 | The `conversation-scoped` row said `ALREADY-SHIPPED` leaves the entry `open` — **inverting the intended outcome** | rewritten; that stop now means CLOSE |
| 31 | Two different steps are both named "Step 3b" (Task 1's and Task 2's) | ambiguity called out where it bites |
| 32 | Task 5 Step 3 told the executor to leave the entry `open` — **contradicting Task 6's table**, so following it would fail Task 6's own verification | aligned to template (ii) |
| 33 | Task 6 Step 4's commit message still claimed all four entries were *"fixed by this plan"* — a false provenance claim inside the very fold that added the provenance rule | reworded |
| 34 | *(found by my own sweep, not the panel)* "the plan's other **four** fixes" survived the shrink to three | corrected |
| 35 | *(found by my own sweep, not the panel)* **the self-review had itself gone stale, twice over** — claimed `Classify`/`Hint` were the only members added after `StatusFor` was introduced, and described a Task 5 structure that no longer exists | rewritten, with the rot noted in place |

🔴 **Seven of nine round-4 findings were defects the FOLDS created.** That is now eight separate incomplete-folds in this epic, several inside the fix for the previous one. **The Fold Auditor seat earned its place immediately, and the free Law-3 grep out-performed the paid panel twice.**

**Convergence Judge, asked directly whether this is still finding execution defects or merely polishing:** *"The review has converged… Tasks 0, 1, 2, and 4 are fully specified, test-guarded, and executable. Once lines 640 and 718 are aligned, stop reviewing and execute the plan."* Those two are folded (#32, #33), plus two more I found after.

**PANEL VERDICT: round 4 RED (9 folded) — every finding a fold artefact, none touching the C# logic. The panel proposes GREEN at this tip. Awaiting owner adjudication.**

## Self-review

⚠️ **Rewritten at round 4 because it had gone stale — twice over.** It still claimed `Classify` and `Hint` were the only members added (`StatusFor` was added since) and described a Task 5 step structure that no longer exists. **A self-review is an artifact and rots like any other; re-run it after every round, do not trust the previous pass.**

Run against the four entries in scope and the current task set:

1. **Coverage.** `grpc-default-max-message-size` → Tasks 1 + 2 (both halves: the cap *and* the hint, which the entry insists matters as much). `conversation-scoped-tools` → Task 3 (expected: disposition, no code). `agy-look-tail-truncation` → Task 4. `stalled-reply-recoverable-not-lost` → Task 5 (expected: disposition, no code). `inbox-snapshot-misses-slash-command-path` is **deliberately excluded** (a hook fix, plan 2) — scope, not omission.
2. **Ordering holds.** Task 1 precedes Task 3 (Task 3 extends the `Fault`/`Classify`/`Hint`/`StatusFor` set Task 1 creates). Task 2 precedes Task 5 (the entry's stated sibling constraint), though Task 5 is now gated and likely writes nothing. Task 4 is independent of all of them.
3. **No fabricated wire values.** Task 3's status code is measured, never guessed — the one place this plan could have invented a contract, it refuses to, and now stops early because the case appears already handled.
4. **Placeholders.** Task 3 Step 2 and Task 4 Step 2 carry `<MEASURED_*>` / harness markers. These are **measurement outputs**, not deferred decisions: each has a command that produces the value and a stated stop if it cannot. Task 5 is specified as a decision procedure rather than code **on purpose** — its Step 1 forces a read of the idle-wait internals before any opinion, and Step 3 has two named terminal outcomes.
5. **Type consistency.** `Fault` is introduced in Task 1 (`TransportDown`, `PayloadTooLarge`) and extended in Task 3 (`NoConversation`). Task 1 adds **three** members — `Fault`, `Classify`, `StatusFor` — and rewrites `Hint`. `IsChannelDown` and `Diagnose` are untouched, so `AgyStatusShapeTests.cs` keeps passing. **Every fault added to `Classify` must also be added to `StatusFor`**, or the status field and the hint contradict each other (round-2 finding 18).
6. **Wire-contract risk, stated.** Task 1 changes user-visible hint prose **and** introduces new `status` values. `AgyChannelDownTests.cs` asserts the old value across ~7 cases; Task 1 Step 5 runs that suite, and Step 3b's consumer check is a hard `CONTRACT:` stop if anything outside `ChannelDown.cs` switches on `"channel_down"`.
7. **Provenance.** Two entries close as already-fixed. Task 6 template (ii) forbids citing one of this plan's commits for them, and Step 4's commit message says "two fixed here, two verified already-shipped" rather than claiming all four.
