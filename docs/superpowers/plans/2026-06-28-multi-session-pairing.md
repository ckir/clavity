# Multi-session Claude⇄agy pairing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let N independent Claude⇄agy pairs run concurrently — each Claude drives its OWN agy instance via that agy's per-instance Language Server (LS), replacing the single-agy "newest cli.log / newest .db" heuristics with per-session identity threaded through the environment and a conversation id resolved from the LS.

**Architecture:** `clavity start` mints a per-session GUID, launches agy with a per-session `--log-file`, and exports `CLAVITY_SESSION_ID` + `CLAVITY_AGY_LOG` into Claude's environment. The MCP server (`clavity --mcp`, spawned inside Claude) reads `CLAVITY_AGY_LOG` to find the right cli.log → LS port (existing parser), and resolves the conversation id from the LS via `GetAllCascadeTrajectories` (not from disk). A bounded retry handles the agy-boot race. `ConversationLocator` (newest-`.db`) is retired — unsafe once instances share `conversations/`.

**Tech Stack:** .NET 10, C#, Grpc.Net.Client/Grpc.Tools (h2c), Google.Protobuf, ModelContextProtocol SDK, xUnit (plain `Assert`), in-proc Kestrel h2c fake LS for integration tests.

**Source-of-truth references (verified while authoring this plan):**
- Spec: `docs/superpowers/specs/2026-06-28-multi-session-design.md` (§§3–13).
- Authoritative proto field numbers: `jkfujinami/antigravity-grpc-schemas` (verified 2026-06-28):
  - `GetAllCascadeTrajectoriesRequest { bool exclude_subtrajectories = 1; }`
  - `GetAllCascadeTrajectoriesResponse { map<string, exa.jetski_cortex_pb.CascadeTrajectorySummary> trajectory_summaries = 1; }`
  - `CascadeTrajectorySummary { string summary = 1; uint32 step_count = 2; google.protobuf.Timestamp last_modified_time = 3; }`
- **Pinned concrete values** (spec §13 deferred these to the plan): boot-race timeout **10 s** total / poll **500 ms**; log retention **7 days**; `sessionId` = `Guid.NewGuid().ToString("D")` (dashed, path-safe); the >1-conversation tiebreaker field = **`last_modified_time` (field 3, `google.protobuf.Timestamp`)**.

**Build/test gate (the repo's gate — do NOT add stricter flags):**
- `dotnet build -c Release` → expect **8 projects, 0 warnings / 0 errors**.
- `dotnet test -c Release --filter "Category!=LiveAgy"` → all non-live tests pass (Live.Acceptance excluded).
- Live spikes (Task 1, and the Task 2 golden capture) require a running agy and are **manual / gated** — not part of CI.

**Working tree note:** HEAD is `c05aaf5`. Three files are dirty on disk from the **superseded** held-T8 work and are REWRITTEN by this plan, never committed as-is: `src/Clavity.Ls/Launcher.cs`, `tests/Clavity.Ls.Tests/LauncherTests.cs` (both currently untracked), and `src/Clavity.Cli/Program.cs` (modified). Tasks 5–7 replace their contents wholesale. The throwaway `scratchpad/e2probe.proto` is not part of the repo.

---

## File map

| Path | Action | Responsibility |
|------|--------|----------------|
| `src/Clavity.Ls.Proto/Protos/clavity.proto` | Modify | Add `GetAllCascadeTrajectories` rpc + 3 partial messages + WKT timestamp import. |
| `tests/Clavity.Ls.Tests/TestData/GetAllCascadeTrajectories.bin` | Create (live capture) | Golden wire bytes oracle for the new RPC. |
| `tests/Clavity.Ls.Tests/GetAllCascadeTrajectoriesGoldenTests.cs` | Create | Pin the new proto against the golden. |
| `src/Clavity.Ls/LsClient.cs` | Modify | Add `GetAllCascadeTrajectoriesAsync` → `IReadOnlyList<CascadeConversation>`. |
| `src/Clavity.Ls/CascadeConversation.cs` | Create | DTO: conversation id + last-modified time. |
| `src/Clavity.Ls/AgyView.cs` | Modify | Resolve convId from LS (retry-once boot race + most-recent tiebreak); drop `ConversationLocator`/`ConversationsDir`. |
| `src/Clavity.Ls/AgyConversationPendingException.cs` | Create | Typed "wait for the human" suspension (E3). |
| `src/Clavity.Ls/ConversationLocator.cs` | Delete | Newest-`.db` is unsafe in a shared tree (spec §4). |
| `tests/Clavity.Ls.Tests/ConversationLocatorTests.cs` | Delete | Locator removed. |
| `src/Clavity.Ls/AgyEnvironment.cs` | Create | Env var names + `ResolveCliLogPath` (per-session vs global). |
| `src/Clavity.Ls/LogRetention.cs` | Create | Age-based prune of `logs/clavity-*.log`. |
| `src/Clavity.Ls/Launcher.cs` | Rewrite | Bake `--log-file <perSessionPath>` + Claude env `CLAVITY_SESSION_ID`/`CLAVITY_AGY_LOG`; drop `CLAVITY_LAUNCHED`. |
| `src/Clavity.Cli/Program.cs` | Rewrite | `start`: mint sessionId, per-session log path, ensure `logs/`, prune, launch. `--mcp`: build options from `CLAVITY_AGY_LOG`. |
| `src/Clavity.Mcp/McpTools.cs` | Modify | Catch `AgyConversationPendingException` → typed "waiting" JSON. |
| `tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs` | Modify | Fake serves `GetAllCascadeTrajectories`; new retry + pending tests; drop `.db`/`ConversationsDir`. |
| `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` | Modify | Same fake change; drop `.db`/`ConversationsDir`. |
| `tests/Clavity.Integration.Tests/McpToolsIntegrationTests.cs` | Modify | Same fake change; add "waiting" JSON test. |
| `tests/Clavity.Integration.Tests/LsClientIntegrationTests.cs` | Modify | Add `GetAllCascadeTrajectoriesAsync` round-trip test. |
| `tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs` | Create | Unit-test env→cli.log resolution. |
| `tests/Clavity.Ls.Tests/LogRetentionTests.cs` | Create | Unit-test age-based prune. |
| `tests/Clavity.Ls.Tests/LauncherTests.cs` | Rewrite | Assert new env/argv shape. |
| `docs/agy-ls-assumptions.md` | Modify | Record E1/E3 live facts + the new RPC contract. |

---

## Task 1: E1 live spike — verify `--log-file` is honored + confirm the new RPC live (GATE)

**This is a manual, live spike. It writes no committed code. If E1 fails, STOP and revise spec §3 — the whole port-discovery design hinges on it.** Requires a running agy (CLI 1.0.11) and `grpcurl` (on PATH). Keep this agy session running into Task 2 (the golden capture reuses it).

**Files:**
- Create (scratchpad, throwaway): `<scratchpad>/e1probe.proto`
- Modify (at the end): `docs/agy-ls-assumptions.md`

- [ ] **Step 1: Launch agy with an explicit per-session `--log-file` (E1)**

In a new terminal, run agy pointed at a unique log path (NOT the global cli.log):

```
agy --log-file "C:\Users\user\AppData\Local\Temp\clavity-e1.log"
```

- [ ] **Step 2: Confirm agy wrote the port line to THAT file (E1 verdict)**

Read `C:\Users\user\AppData\Local\Temp\clavity-e1.log`. Expected: it contains BOTH lines

```
... Language server listening on random port at <N> for HTTPS (gRPC)
... Language server listening on random port at <N+1> for HTTP
```

**PASS** → agy honors per-session `--log-file`; continue. **FAIL** (lines absent / only in global cli.log) → STOP, do not proceed; report `E1 FAILED` and revisit spec §3 (fallback: have agy write its own PID to the log — never the `wt` PID).

- [ ] **Step 3: Write the minimal probe proto**

Create `<scratchpad>/e1probe.proto`:

```proto
syntax = "proto3";
package exa.language_server_pb;
import "google/protobuf/timestamp.proto";

service LanguageServerService {
  rpc GetAllCascadeTrajectories(GetAllCascadeTrajectoriesRequest) returns (GetAllCascadeTrajectoriesResponse);
}

message GetAllCascadeTrajectoriesRequest { bool exclude_subtrajectories = 1; }

message CascadeTrajectorySummary {
  string summary = 1;
  uint32 step_count = 2;
  google.protobuf.Timestamp last_modified_time = 3;
}

message GetAllCascadeTrajectoriesResponse {
  map<string, CascadeTrajectorySummary> trajectory_summaries = 1;
}
```

- [ ] **Step 4: Invoke GetAllCascadeTrajectories live (E2 re-confirm + E3 calibration)**

Use the HTTP port `<N+1>` from Step 2.

```
grpcurl -plaintext -proto "<scratchpad>/e1probe.proto" -d "{\"exclude_subtrajectories\": true}" 127.0.0.1:<N+1> exa.language_server_pb.LanguageServerService/GetAllCascadeTrajectories
```

Record:
- Whether `trajectorySummaries` is present and non-empty BEFORE any human interaction (E3: is the conversation created at process start or first message?).
- That each map key is a conversation UUID and each value carries `lastModifiedTime` (proves field 3 is populated — the tiebreaker depends on it). **If `lastModifiedTime` is absent/empty, STOP and report** — the >1 tiebreaker design (spec §6) needs it; surface the conflict, don't silently proceed.

- [ ] **Step 5: Record the live facts**

Append a short subsection to `docs/agy-ls-assumptions.md` recording: E1 result (per-session `--log-file` honored), the GetAllCascadeTrajectories request/response shape observed, whether a conversation exists at process start (E3), and that `lastModifiedTime` is populated. Cite agy version 1.0.11 and the date.

- [ ] **Step 6: Commit the doc update**

```bash
git add docs/agy-ls-assumptions.md
git commit -m "docs(clavity-dotnet): E1/E3 live spike — per-session --log-file honored; GetAllCascadeTrajectories shape"
```

Leave the agy session from Step 1 running for Task 2.

---

## Task 2: Add the `GetAllCascadeTrajectories` proto + golden

**Files:**
- Modify: `src/Clavity.Ls.Proto/Protos/clavity.proto`
- Create (live capture): `tests/Clavity.Ls.Tests/TestData/GetAllCascadeTrajectories.bin`
- Create: `tests/Clavity.Ls.Tests/GetAllCascadeTrajectoriesGoldenTests.cs`
- Create (scratchpad, throwaway): `<scratchpad>/CaptureProbe/` (a tiny console capture, deleted after)

- [ ] **Step 1: Add the import, rpc, and messages to the proto**

In `src/Clavity.Ls.Proto/Protos/clavity.proto`, add the WKT import directly after the `option csharp_namespace` line:

```proto
option csharp_namespace = "Clavity.Ls.Proto";

import "google/protobuf/timestamp.proto";
```

Add the rpc to the `service LanguageServerService { ... }` block, after the `WaitForConversationFullyIdle` line:

```proto
  rpc GetAllCascadeTrajectories(GetAllCascadeTrajectoriesRequest) returns (GetAllCascadeTrajectoriesResponse);
```

Append these messages at the end of the file (field numbers verified against `jkfujinami/antigravity-grpc-schemas`):

```proto
// --- GetAllCascadeTrajectories (multi-session): the conversation ids this LS instance knows. Used to resolve
// the per-pair conversation id from the LS (not from disk). PARTIAL — CascadeTrajectorySummary models only the
// tiebreaker timestamp. Field numbers from jkfujinami/antigravity-grpc-schemas; pinned by the golden below.
message GetAllCascadeTrajectoriesRequest {
  bool exclude_subtrajectories = 1;
}

message GetAllCascadeTrajectoriesResponse {
  // map KEY = conversation id; VALUE = its summary. Top-level trajectories only when exclude_subtrajectories.
  map<string, CascadeTrajectorySummary> trajectory_summaries = 1;
}

message CascadeTrajectorySummary {            // partial of exa.jetski_cortex_pb.CascadeTrajectorySummary
  // 1 = summary, 2 = step_count — skipped (not needed).
  google.protobuf.Timestamp last_modified_time = 3;   // >1-conversation tiebreaker (spec §6).
}
```

- [ ] **Step 2: Build the proto project (confirms it compiles + generates the client)**

Run: `dotnet build -c Release src/Clavity.Ls.Proto/Clavity.Ls.Proto.csproj`
Expected: build succeeds, 0 warnings. (Generated `LanguageServerServiceClient` now has `GetAllCascadeTrajectoriesAsync`.)

- [ ] **Step 3: Capture the golden bytes from the LIVE agy (reuse Task 1's session)**

Create a throwaway capture console at `<scratchpad>/CaptureProbe/CaptureProbe.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
  </PropertyGroup>
  <ItemGroup>
    <ProjectReference Include="C:\Users\user\Development\Rust\clavity\src\Clavity.Ls\Clavity.Ls.csproj" />
    <ProjectReference Include="C:\Users\user\Development\Rust\clavity\src\Clavity.Ls.Proto\Clavity.Ls.Proto.csproj" />
  </ItemGroup>
</Project>
```

`<scratchpad>/CaptureProbe/Program.cs` (point `cliLog` at the Task 1 per-session log):

```csharp
using Clavity.Ls;
using Clavity.Ls.Proto;

var cliLog = @"C:\Users\user\AppData\Local\Temp\clavity-e1.log";
var ep = LsDiscovery.DiscoverActive(LsDiscovery.ReadCliLogText(cliLog), new SystemListeningPorts());
using var channel = LsChannel.ForHttpPort(ep.HttpPort);
var client = new LanguageServerService.LanguageServerServiceClient(channel);
var resp = client.GetAllCascadeTrajectories(new GetAllCascadeTrajectoriesRequest { ExcludeSubtrajectories = true });

var outPath = @"C:\Users\user\Development\Rust\clavity\tests\Clavity.Ls.Tests\TestData\GetAllCascadeTrajectories.bin";
File.WriteAllBytes(outPath, resp.ToByteArray());
Console.WriteLine($"Wrote {new FileInfo(outPath).Length} bytes; {resp.TrajectorySummaries.Count} conversation(s).");
foreach (var kvp in resp.TrajectorySummaries)
    Console.WriteLine($"  {kvp.Key}  last_modified={kvp.Value.LastModifiedTime}");
```

Run: `dotnet run --project "<scratchpad>/CaptureProbe"`
Expected: writes `GetAllCascadeTrajectories.bin`, prints ≥1 conversation, and each line shows a non-empty `last_modified`. **If `last_modified` prints empty, STOP and report** (oracle conflict with the tiebreaker design).

- [ ] **Step 4: Write the golden test (structural invariants — no live-specific literals)**

Create `tests/Clavity.Ls.Tests/GetAllCascadeTrajectoriesGoldenTests.cs`:

```csharp
using Clavity.Ls.Proto;
using Google.Protobuf;

namespace Clavity.Ls.Tests;

// Multi-session: pins the partial GetAllCascadeTrajectories proto against real captured wire
// (TestData/GetAllCascadeTrajectories.bin, agy 1.0.11). The .bin is the ORACLE — if an assertion fails,
// the proto field numbers are wrong; do NOT edit the golden or weaken the assertion.
public class GetAllCascadeTrajectoriesGoldenTests
{
    private static byte[] Golden(string name) =>
        File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "TestData", name));

    [Fact]
    public void Captured_response_parses_into_partial_proto()
    {
        var resp = GetAllCascadeTrajectoriesResponse.Parser.ParseFrom(Golden("GetAllCascadeTrajectories.bin"));

        Assert.NotEmpty(resp.TrajectorySummaries);
        foreach (var kvp in resp.TrajectorySummaries)
        {
            Assert.True(Guid.TryParse(kvp.Key, out _), $"map key '{kvp.Key}' is not a conversation UUID");
            Assert.NotNull(kvp.Value.LastModifiedTime); // field 3 decodes — the >1 tiebreaker depends on it.
        }
    }
}
```

- [ ] **Step 5: Run the golden test**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~GetAllCascadeTrajectoriesGoldenTests"`
Expected: PASS (1 test).

- [ ] **Step 6: Delete the throwaway probe and commit**

Delete `<scratchpad>/CaptureProbe/` and `<scratchpad>/e1probe.proto`.

```bash
git add src/Clavity.Ls.Proto/Protos/clavity.proto tests/Clavity.Ls.Tests/TestData/GetAllCascadeTrajectories.bin tests/Clavity.Ls.Tests/GetAllCascadeTrajectoriesGoldenTests.cs
git commit -m "feat(clavity-dotnet): GetAllCascadeTrajectories proto + live golden (multi-session convId resolver)"
```

---

## Task 3: `LsClient.GetAllCascadeTrajectoriesAsync` + `CascadeConversation`

**Files:**
- Create: `src/Clavity.Ls/CascadeConversation.cs`
- Modify: `src/Clavity.Ls/LsClient.cs`
- Modify: `tests/Clavity.Integration.Tests/LsClientIntegrationTests.cs`

- [ ] **Step 1: Write the failing integration test**

Open `tests/Clavity.Integration.Tests/LsClientIntegrationTests.cs`, confirm it hosts an in-proc fake LS (`LanguageServerService.LanguageServerServiceBase`) and dials it via `LsClient`. Add a fake override for `GetAllCascadeTrajectories` and a test. The exact host scaffolding mirrors the file's existing pattern; add this test method and the matching fake override returning a two-entry map:

```csharp
[Fact]
public async Task GetAllCascadeTrajectories_returns_conversations_with_timestamps()
{
    var conversations = await _client.GetAllCascadeTrajectoriesAsync(excludeSubtrajectories: true);

    Assert.Equal(2, conversations.Count);
    Assert.Contains(conversations, c => c.ConversationId == "conv-older");
    Assert.Contains(conversations, c => c.ConversationId == "conv-newer");
}
```

In the file's fake LS class, add (timestamps chosen so `conv-newer` is later):

```csharp
public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
    GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
{
    var resp = new GetAllCascadeTrajectoriesResponse();
    resp.TrajectorySummaries["conv-older"] = new CascadeTrajectorySummary
    {
        LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
            new DateTimeOffset(2026, 6, 27, 0, 0, 0, TimeSpan.Zero)),
    };
    resp.TrajectorySummaries["conv-newer"] = new CascadeTrajectorySummary
    {
        LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(
            new DateTimeOffset(2026, 6, 28, 0, 0, 0, TimeSpan.Zero)),
    };
    return Task.FromResult(resp);
}
```

> If `LsClientIntegrationTests.cs` does not already expose a reusable `_client`/fake pair, follow its existing per-test host helper instead and adapt the assertions to construct the `LsClient` the same way the other tests in that file do. Do NOT invent a new hosting style.

- [ ] **Step 2: Run the test to confirm it fails to compile**

Run: `dotnet test -c Release tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~GetAllCascadeTrajectories_returns_conversations_with_timestamps"`
Expected: FAIL — `LsClient` has no `GetAllCascadeTrajectoriesAsync` and `CascadeConversation` is undefined.

- [ ] **Step 3: Create the DTO**

Create `src/Clavity.Ls/CascadeConversation.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>A conversation known to an agy Language Server instance: its id and last-modified time (UTC),
/// from <c>GetAllCascadeTrajectories</c>. <see cref="LastModifiedUtc"/> is null if the LS did not report one.</summary>
public sealed record CascadeConversation(string ConversationId, DateTimeOffset? LastModifiedUtc);
```

- [ ] **Step 4: Add the client method**

In `src/Clavity.Ls/LsClient.cs`, add after `WaitForConversationFullyIdleAsync`:

```csharp
    /// <summary>
    /// List the top-level conversations this LS instance knows (map key = conversation id). The multi-session
    /// convId resolver: each agy instance's LS reports only its own conversations. (GetBrowserOpenConversation
    /// is desktop-UI-only and errors on a CLI agy — E2-verified — so it is NOT used.)
    /// </summary>
    public async Task<IReadOnlyList<CascadeConversation>> GetAllCascadeTrajectoriesAsync(
        bool excludeSubtrajectories = true, CancellationToken cancellationToken = default)
    {
        var response = await _client.GetAllCascadeTrajectoriesAsync(
            new GetAllCascadeTrajectoriesRequest { ExcludeSubtrajectories = excludeSubtrajectories },
            cancellationToken: cancellationToken);

        return response.TrajectorySummaries
            .Select(kvp => new CascadeConversation(
                kvp.Key,
                kvp.Value.LastModifiedTime?.ToDateTimeOffset()))
            .ToList();
    }
```

- [ ] **Step 5: Run the test to confirm it passes**

Run: `dotnet test -c Release tests/Clavity.Integration.Tests/Clavity.Integration.Tests.csproj --filter "FullyQualifiedName~GetAllCascadeTrajectories_returns_conversations_with_timestamps"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/Clavity.Ls/CascadeConversation.cs src/Clavity.Ls/LsClient.cs tests/Clavity.Integration.Tests/LsClientIntegrationTests.cs
git commit -m "feat(clavity-dotnet): LsClient.GetAllCascadeTrajectoriesAsync + CascadeConversation DTO"
```

---

## Task 4: Rework `AgyView` to resolve convId from the LS + retire `ConversationLocator` (atomic)

**This task is atomic by design (spec §13): switch `AgyView`, update every `ConversationLocator`/`ConversationsDir` consumer, and delete the locator in ONE commit so the suite is never left broken.**

**Files:**
- Create: `src/Clavity.Ls/AgyConversationPendingException.cs`
- Modify: `src/Clavity.Ls/AgyView.cs`
- Delete: `src/Clavity.Ls/ConversationLocator.cs`, `tests/Clavity.Ls.Tests/ConversationLocatorTests.cs`
- Modify: `tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs`, `AgyAskIntegrationTests.cs`, `McpToolsIntegrationTests.cs`
- Modify: `src/Clavity.Cli/Program.cs` (the `--mcp` `AgyViewOptions` construction only — drops `ConversationsDir`)

- [ ] **Step 1: Write the new failing behavior tests (retry-success + empty→pending)**

In `tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs`, the fake LS will be revised in Step 4 to serve `GetAllCascadeTrajectories` with a configurable empty-then-nonempty script. Add these two tests (they reference fake behavior + `AgyViewOptions` fields added in Steps 2–4):

```csharp
[Fact]
public async Task LookAsync_retries_until_a_conversation_appears_then_succeeds()
{
    // Map is empty for the first 2 polls (conversation not created yet), then non-empty.
    var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: 2);
    await using var app = await StartFakeAsync(fake);
    var cliLog = WriteCliLog(PortOf(app));

    var view = new AgyView(new AgyViewOptions
    {
        CliLogPath = cliLog,
        BootRaceTimeout = TimeSpan.FromSeconds(5),
        BootRacePollInterval = TimeSpan.FromMilliseconds(50),
    });

    var bounded = await view.LookAsync();
    Assert.Equal("cascade-1", bounded.CascadeId);
}

[Fact]
public async Task LookAsync_throws_AgyConversationPendingException_when_no_conversation_within_bound()
{
    var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: int.MaxValue); // never appears
    await using var app = await StartFakeAsync(fake);
    var cliLog = WriteCliLog(PortOf(app));

    var view = new AgyView(new AgyViewOptions
    {
        CliLogPath = cliLog,
        BootRaceTimeout = TimeSpan.FromMilliseconds(300),
        BootRacePollInterval = TimeSpan.FromMilliseconds(50),
    });

    await Assert.ThrowsAsync<AgyConversationPendingException>(() => view.LookAsync());
}
```

- [ ] **Step 2: Create the pending exception**

Create `src/Clavity.Ls/AgyConversationPendingException.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>
/// Thrown when agy is reachable but has NO conversation yet (E3) after the boot-race bound. This is a
/// SUSPENSION, not a retryable error: the caller must WAIT for the human to start/continue the agy session
/// and must NOT auto-retry in a loop (spec §6, ModalGuard-style).
/// </summary>
public sealed class AgyConversationPendingException : Exception
{
    public AgyConversationPendingException(string message) : base(message) { }
}
```

- [ ] **Step 3: Rewrite `AgyView` (options, resolution, retry)**

Replace the contents of `src/Clavity.Ls/AgyView.cs` with:

```csharp
using Clavity.Ls.Proto;
using Grpc.Core;

namespace Clavity.Ls;

/// <summary>Where the live agy session's state lives + boot-race bounds (overridable for tests).</summary>
public sealed class AgyViewOptions
{
    /// <summary>The cli.log to discover the LS port from — per-session (CLAVITY_AGY_LOG) or the global default.</summary>
    public required string CliLogPath { get; init; }

    /// <summary>Total time to keep retrying connection + conversation resolution during the agy boot race.</summary>
    public TimeSpan BootRaceTimeout { get; init; } = TimeSpan.FromSeconds(10);

    /// <summary>Delay between boot-race polls.</summary>
    public TimeSpan BootRacePollInterval { get; init; } = TimeSpan.FromMilliseconds(500);
}

/// <summary>
/// The read/"look"/"ask" surface the MCP tools sit on. Resolves the active conversation id from the agy
/// Language Server (GetAllCascadeTrajectories) — NOT from disk — and bounds the agy boot race with a single
/// retry/poll at connection establishment; once connected, each call is a single round-trip.
/// </summary>
public sealed class AgyView
{
    private readonly AgyViewOptions _options;
    private readonly IListeningPorts _listening;

    public AgyView(AgyViewOptions options, IListeningPorts? listening = null)
    {
        _options = options;
        _listening = listening ?? new SystemListeningPorts();
    }

    /// <summary>Look at the active conversation's trajectory, bounded to <paramref name="budgetChars"/>.</summary>
    public async Task<BoundedTrajectory> LookAsync(
        int budgetChars = BoundedView.DefaultBudgetChars, CancellationToken cancellationToken = default)
    {
        var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
        using (client)
        {
            var trajectory = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            return BoundedView.Summarize(trajectory, budgetChars);
        }
    }

    /// <summary>Default client-side ceiling on the idle-wait, so a stuck conversation can't block forever.</summary>
    public static readonly TimeSpan DefaultIdleWaitTimeout = TimeSpan.FromSeconds(120);
    private const int IdleInactivityTimeoutSeconds = 30;
    private const int IdleStabilizationSeconds = 2;

    /// <summary>
    /// Send <paramref name="message"/> to the active conversation, wait for it to go idle, then return the NEW
    /// trajectory steps (agy's reply) as a size-bounded view. A client-side <paramref name="timeout"/> guards the
    /// idle-wait (ties to T9 ModalGuard) — on expiry a <see cref="TimeoutException"/> is thrown. ⚠ This is a WRITE:
    /// live it consumes quota and posts a visible message; live use is gated to T10.
    /// </summary>
    public async Task<BoundedTrajectory> AskAsync(
        string message,
        int budgetChars = BoundedView.DefaultBudgetChars,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        var (client, conversationId) = await ConnectAndResolveAsync(cancellationToken);
        using (client)
        {
            // Step count BEFORE sending — everything appended after this index is the reply to our message.
            var before = (await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken)).Steps.Count;

            await client.SendUserCascadeMessageAsync(conversationId, message, cancellationToken);

            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutCts.CancelAfter(timeout ?? DefaultIdleWaitTimeout);
            try
            {
                await client.WaitForConversationFullyIdleAsync(
                    conversationId, IdleInactivityTimeoutSeconds, IdleStabilizationSeconds, timeoutCts.Token);
            }
            catch (Exception ex) when (timeoutCts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
                && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
            {
                throw new TimeoutException(
                    $"agy conversation did not go idle within {(timeout ?? DefaultIdleWaitTimeout)}.");
            }

            var full = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);
            var reply = new CascadeTrajectory { CascadeId = full.CascadeId };
            reply.Steps.AddRange(full.Steps.Skip(before));
            return BoundedView.Summarize(reply, budgetChars);
        }
    }

    /// <summary>
    /// Establish a connection and resolve the conversation id, bounded by the boot race. Polls until the cli.log
    /// has the port line, the LS is reachable, AND GetAllCascadeTrajectories returns a non-empty map. On timeout:
    /// <see cref="AgyConversationPendingException"/> if the LS was reachable but reported no conversation (E3 —
    /// wait for the human); otherwise <see cref="LsDiscoveryException"/> (agy not up). Returns a LIVE client the
    /// caller must dispose.
    /// </summary>
    private async Task<(LsClient Client, string ConversationId)> ConnectAndResolveAsync(CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + _options.BootRaceTimeout;
        var reachedLsButEmpty = false;

        while (true)
        {
            cancellationToken.ThrowIfCancellationRequested();
            LsClient? client = null;
            try
            {
                client = LsClient.Connect(LsDiscovery.ReadCliLogText(_options.CliLogPath), _listening);
                var conversations = await client.GetAllCascadeTrajectoriesAsync(
                    excludeSubtrajectories: true, cancellationToken);
                if (conversations.Count > 0)
                    return (client, SelectMostRecent(conversations));

                reachedLsButEmpty = true; // LS up, but no conversation yet (E3).
                client.Dispose();
            }
            catch (LsDiscoveryException) { client?.Dispose(); }  // log/port not ready, or port not listening yet.
            catch (IOException) { client?.Dispose(); }           // cli.log not present yet.
            catch (RpcException) { client?.Dispose(); }          // LS not answering yet.

            if (DateTime.UtcNow >= deadline)
            {
                if (reachedLsButEmpty)
                    throw new AgyConversationPendingException(
                        "agy is running but has no conversation yet. WAIT for the human to start or continue the " +
                        "agy session, then try again — do NOT auto-retry in a loop.");
                throw new LsDiscoveryException(
                    $"agy Language Server not reachable within {_options.BootRaceTimeout} via {_options.CliLogPath}; " +
                    "the agy session is still starting or has exited.");
            }

            await Task.Delay(_options.BootRacePollInterval, cancellationToken);
        }
    }

    /// <summary>The instance's most-recently-active conversation. Protobuf maps are UNORDERED on the wire, so the
    /// pick MUST be by <c>last_modified_time</c> (spec §6), with conversation id as a stable tiebreaker.</summary>
    private static string SelectMostRecent(IReadOnlyList<CascadeConversation> conversations) =>
        conversations.Count == 1
            ? conversations[0].ConversationId
            : conversations
                .OrderByDescending(c => c.LastModifiedUtc ?? DateTimeOffset.MinValue)
                .ThenBy(c => c.ConversationId, StringComparer.Ordinal)
                .First().ConversationId;
}
```

- [ ] **Step 4: Update the three integration-test fakes (serve `GetAllCascadeTrajectories`; drop `.db`/`ConversationsDir`)**

The fakes no longer need a `conversations/` dir or a `.db` file — convId now comes from the LS. Apply to all three files:

**`AgyViewIntegrationTests.cs`** — replace the `FakeLs` and helpers so the fake serves a scripted `GetAllCascadeTrajectories`, and add a `WriteCliLog` helper used by the new tests. Replace the file's `FakeLs` class and the existing test's setup with:

```csharp
private sealed class FakeLs : LanguageServerService.LanguageServerServiceBase
{
    private readonly string _cascadeId;
    private int _remainingEmptyPolls;

    public FakeLs(string cascadeId, int emptyMapPolls = 0)
    {
        _cascadeId = cascadeId;
        _remainingEmptyPolls = emptyMapPolls;
    }

    public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
        GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
    {
        var resp = new GetAllCascadeTrajectoriesResponse();
        if (_remainingEmptyPolls > 0)
        {
            _remainingEmptyPolls--; // simulate "conversation not created yet" for N polls.
        }
        else
        {
            resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
            };
        }
        return Task.FromResult(resp);
    }

    public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
        GetCascadeTrajectoryRequest request, ServerCallContext context)
        => Task.FromResult(new GetCascadeTrajectoryResponse
        {
            NumTotalSteps = 2,
            Trajectory = new CascadeTrajectory
            {
                CascadeId = _cascadeId,
                Steps =
                {
                    new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "first" } },
                    new CascadeStep { Kind = 15 },
                },
            },
        });
}

private static async Task<WebApplication> StartFakeAsync(FakeLs fake)
{
    var builder = WebApplication.CreateBuilder();
    builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
    builder.WebHost.UseUrls("http://127.0.0.1:0");
    builder.Logging.ClearProviders();
    builder.Services.AddGrpc();
    builder.Services.AddSingleton(fake);
    var app = builder.Build();
    app.MapGrpcService<FakeLs>();
    await app.StartAsync();
    return app;
}

private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

// Writes a throwaway cli.log naming the fake's port; returns the cli.log path. No conversations dir/.db needed.
private static string WriteCliLog(int port)
{
    var dir = Path.Combine(Path.GetTempPath(), "clavity-agyview-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(dir);
    var cliLog = Path.Combine(dir, "cli.log");
    File.WriteAllText(cliLog,
        $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
        $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
    return cliLog;
}
```

Rewrite the file's existing happy-path test to use the new fake + `WriteCliLog` (no `.db`, no `ConversationsDir`):

```csharp
[Fact]
public async Task AgyView_looks_at_active_conversation_and_returns_bounded_view()
{
    var fake = new FakeLs(cascadeId: "cascade-1");
    await using var app = await StartFakeAsync(fake);
    var cliLog = WriteCliLog(PortOf(app));

    var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
    var bounded = await view.LookAsync();

    Assert.Equal("cascade-1", bounded.CascadeId);
    Assert.Equal(2, bounded.TotalSteps);
    Assert.Equal(2, bounded.Steps.Count);
    Assert.Equal(14, bounded.Steps[0].Kind);
    Assert.Equal("first", bounded.Steps[0].Text);
}
```

**`AgyAskIntegrationTests.cs`** — add a `GetAllCascadeTrajectories` override to `FakeAskLs` (returns a single-entry map keyed by `_cascadeId`), and change `SetUpAgyDir` to stop writing the `.db`. Add to `FakeAskLs`:

```csharp
public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
    GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
{
    var resp = new GetAllCascadeTrajectoriesResponse();
    resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
    {
        LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
    };
    return Task.FromResult(resp);
}
```

In `SetUpAgyDir`, delete the `File.WriteAllText(Path.Combine(dir, "aaaaaaaa-...db"), "")` line (the `.db` is no longer used) and construct `AgyViewOptions` in both ask tests with only `CliLogPath = cliLog` (remove the `ConversationsDir = dir` initializer). Keep the temp-dir `try/finally` cleanup as-is (it now holds only cli.log).

**`McpToolsIntegrationTests.cs`** — same fake change: add a `GetAllCascadeTrajectories` override returning a single-entry map keyed by the served cascade id (`"cascade-1"`), delete the `.db` write, and construct `AgyViewOptions` with only `CliLogPath` (drop `ConversationsDir`). Mirror the override from `AgyViewIntegrationTests.cs`.

- [ ] **Step 5: Drop `ConversationsDir` from the `--mcp` options in `Program.cs`**

This is a transitional edit so the project compiles; Task 5 rebuilds `--mcp` fully. In `src/Clavity.Cli/Program.cs`, in the `--mcp` block, remove the `ConversationsDir = ...` initializer line from the `new AgyViewOptions { ... }`. (Leave `CliLogPath` as-is for now.)

- [ ] **Step 6: Delete the locator and its tests**

```bash
git rm src/Clavity.Ls/ConversationLocator.cs tests/Clavity.Ls.Tests/ConversationLocatorTests.cs
```

- [ ] **Step 7: Build + run the full non-live suite green**

Run: `dotnet build -c Release` → expect 8 projects, 0/0.
Run: `dotnet test -c Release --filter "Category!=LiveAgy"` → all pass, including the two new AgyView tests.
Expected: PASS. (If the retry-success test is flaky, confirm `emptyMapPolls`×`BootRacePollInterval` ≪ `BootRaceTimeout`.)

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "refactor(clavity-dotnet): AgyView resolves convId via LS + boot-race retry; retire ConversationLocator"
```

---

## Task 5: `--mcp` consumes the per-session identity env (`AgyEnvironment`)

**Files:**
- Create: `src/Clavity.Ls/AgyEnvironment.cs`
- Create: `tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs`
- Modify: `src/Clavity.Cli/Program.cs` (`--mcp` block)
- Modify: `src/Clavity.Mcp/McpTools.cs` (typed "waiting" result)
- Modify: `tests/Clavity.Integration.Tests/McpToolsIntegrationTests.cs` (waiting-JSON test)

- [ ] **Step 1: Write the failing unit test for env resolution**

Create `tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class AgyEnvironmentTests
{
    private const string Home = @"C:\Users\u\.gemini\antigravity-cli";

    [Fact]
    public void ResolveCliLogPath_uses_per_session_log_when_env_set()
    {
        var perSession = @"C:\Users\u\.gemini\antigravity-cli\logs\clavity-abc.log";
        Assert.Equal(perSession, AgyEnvironment.ResolveCliLogPath(perSession, Home));
    }

    [Fact]
    public void ResolveCliLogPath_falls_back_to_global_cli_log_when_env_unset_or_empty()
    {
        var expected = Path.Combine(Home, "cli.log");
        Assert.Equal(expected, AgyEnvironment.ResolveCliLogPath(null, Home));
        Assert.Equal(expected, AgyEnvironment.ResolveCliLogPath("", Home));
    }
}
```

- [ ] **Step 2: Run to confirm it fails**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~AgyEnvironmentTests"`
Expected: FAIL — `AgyEnvironment` undefined.

- [ ] **Step 3: Create `AgyEnvironment`**

Create `src/Clavity.Ls/AgyEnvironment.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>The per-session identity threaded from <c>clavity start</c> into Claude's environment, and how
/// <c>clavity --mcp</c> consumes it. The log path is the SOLE identity handle (spec §3); the conversation id is
/// resolved from the LS, not the environment.</summary>
public static class AgyEnvironment
{
    /// <summary>Per-session agy log path (the identity handle). Presence implies a clavity-launched session.</summary>
    public const string LogPathVar = "CLAVITY_AGY_LOG";

    /// <summary>Per-session id (GUID "D"). Reserved for bus/memory scoping; not used to resolve the LS.</summary>
    public const string SessionIdVar = "CLAVITY_SESSION_ID";

    /// <summary>The cli.log to discover the LS port from: the per-session <paramref name="envLogPath"/> when set
    /// and non-empty, else the global <c>&lt;agyHomeDir&gt;/cli.log</c> (single-instance back-compat, spec §6).</summary>
    public static string ResolveCliLogPath(string? envLogPath, string agyHomeDir)
        => string.IsNullOrEmpty(envLogPath) ? Path.Combine(agyHomeDir, "cli.log") : envLogPath;
}
```

- [ ] **Step 4: Run to confirm the unit test passes**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~AgyEnvironmentTests"`
Expected: PASS.

- [ ] **Step 5: Wire `--mcp` to use it**

In `src/Clavity.Cli/Program.cs`, replace the `--mcp` options construction so `CliLogPath` comes from the env helper:

```csharp
if (args.Contains("--mcp"))
{
    var agyDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".gemini", "antigravity-cli");
    var options = new AgyViewOptions
    {
        CliLogPath = AgyEnvironment.ResolveCliLogPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.LogPathVar), agyDir),
    };

    var builder = Host.CreateApplicationBuilder(args);
    // stdout is the MCP protocol channel — all logs must go to stderr.
    builder.Logging.AddConsole(o => o.LogToStandardErrorThreshold = LogLevel.Trace);
    builder.Services.AddSingleton(options);
    builder.Services.AddSingleton(sp => new AgyView(sp.GetRequiredService<AgyViewOptions>()));
    builder.Services
        .AddMcpServer()
        .WithStdioServerTransport()
        .WithTools<McpTools>();

    await builder.Build().RunAsync();
    return;
}
```

- [ ] **Step 6: Make the MCP tools surface the pending suspension as typed JSON**

Per spec §6, the empty-conversation case must reach Claude as a clear "wait for the human" instruction, not a raw error. Replace `src/Clavity.Mcp/McpTools.cs` with:

```csharp
using System.ComponentModel;
using System.Text.Json;
using Clavity.Ls;
using ModelContextProtocol.Server;

namespace Clavity.Mcp;

/// <summary>MCP tools exposing a read-only, size-bounded "look" + an "ask" over agy's Language Server.</summary>
[McpServerToolType]
public class McpTools
{
    [McpServerTool(Name = "agy_look"), Description("Look at the active agy conversation's cascade trajectory as a size-bounded JSON summary (no verbose ids).")]
    public static async Task<string> AgyLook(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.LookAsync(cancellationToken: cancellationToken));

    [McpServerTool(Name = "agy_status"), Description("Report the active agy conversation's status: cascade id, total steps, and whether the look was truncated.")]
    public static async Task<string> AgyStatus(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(async () =>
        {
            var bounded = await view.LookAsync(cancellationToken: cancellationToken);
            return (object)new { bounded.CascadeId, bounded.TotalSteps, bounded.Truncated };
        });

    [McpServerTool(Name = "agy_ask"), Description("Send a message to the active agy conversation and return agy's reply (size-bounded JSON) once the conversation goes idle. WRITE: consumes quota and posts a visible message in the user's agy.")]
    public static async Task<string> AgyAsk(AgyView view, string message, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.AskAsync(message, cancellationToken: cancellationToken));

    // Serialize the result, or — when agy has no conversation yet — a typed "waiting" object that tells Claude to
    // wait for the human and NOT auto-retry (spec §6).
    private static async Task<string> RunAsync<T>(Func<Task<T>> action)
    {
        try
        {
            return JsonSerializer.Serialize(await action());
        }
        catch (AgyConversationPendingException ex)
        {
            return JsonSerializer.Serialize(new { status = "waiting_for_human", message = ex.Message });
        }
    }
}
```

> NOTE: `AgyStatus` casts its anonymous object to `(object)` so the generic `RunAsync<T>` infers `T = object` consistently. If the compiler is happy without the cast, drop it; do not change the JSON shape.

- [ ] **Step 7: Add the waiting-JSON integration test**

In `tests/Clavity.Integration.Tests/McpToolsIntegrationTests.cs`, add (using the `FakeLs`/`WriteCliLog` shape from Task 4; `emptyMapPolls: int.MaxValue` makes the conversation never appear, and a short boot timeout keeps it fast):

```csharp
[Fact]
public async Task Agy_look_tool_returns_waiting_json_when_no_conversation()
{
    var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: int.MaxValue);
    await using var app = await StartFakeAsync(fake);
    var cliLog = WriteCliLog(PortOf(app));

    var view = new AgyView(new AgyViewOptions
    {
        CliLogPath = cliLog,
        BootRaceTimeout = TimeSpan.FromMilliseconds(300),
        BootRacePollInterval = TimeSpan.FromMilliseconds(50),
    });

    var json = await McpTools.AgyLook(view);

    using var doc = JsonDocument.Parse(json);
    Assert.Equal("waiting_for_human", doc.RootElement.GetProperty("status").GetString());
}
```

- [ ] **Step 8: Build + run the non-live suite**

Run: `dotnet build -c Release` → 8 projects, 0/0.
Run: `dotnet test -c Release --filter "Category!=LiveAgy"` → all pass.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat(clavity-dotnet): --mcp consumes CLAVITY_AGY_LOG; MCP tools surface conversation-pending as typed JSON"
```

---

## Task 6: Rework `Launcher` for per-session identity

**Files:**
- Rewrite: `src/Clavity.Ls/Launcher.cs`
- Rewrite: `tests/Clavity.Ls.Tests/LauncherTests.cs`

- [ ] **Step 1: Write the failing launcher tests**

Replace `tests/Clavity.Ls.Tests/LauncherTests.cs` with:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class LauncherTests
{
    private static LaunchOptions Opts(
        string folder = @"C:\work\repo",
        string sessionId = "11111111-2222-3333-4444-555555555555",
        string? projectId = "proj-123",
        string logFile = @"C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log",
        bool skipPermissions = false,
        params string[] claudeArgs)
        => new()
        {
            Folder = folder,
            SessionId = sessionId,
            ProjectId = projectId,
            AgyLogFilePath = logFile,
            SkipPermissions = skipPermissions,
            ClaudeArgs = claudeArgs,
        };

    [Fact]
    public void AgyTab_is_wt_new_tab_running_pwsh_with_baked_env_and_per_session_log()
    {
        var plan = Launcher.Build(Opts());

        Assert.Equal("wt", plan.AgyTab.FileName);
        Assert.Equal(
            new[] { "new-tab", "--startingDirectory", @"C:\work\repo", "pwsh", "-NoExit", "-Command" },
            plan.AgyTab.Arguments.Take(6));
        Assert.Equal(@"C:\work\repo", plan.AgyTab.WorkingDirectory);

        var script = plan.AgyTab.Arguments[6];
        Assert.Equal(
            "$env:ANTIGRAVITY_CSRF_TOKEN='clavity'; $env:ANTIGRAVITY_PROJECT_ID='proj-123'; " +
            @"agy --log-file 'C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log'",
            script);
    }

    [Fact]
    public void ProjectId_is_omitted_when_absent()
    {
        var plan = Launcher.Build(Opts(projectId: null));

        var script = plan.AgyTab.Arguments[6];
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", script);
        Assert.StartsWith("$env:ANTIGRAVITY_CSRF_TOKEN='clavity'; agy --log-file ", script);
    }

    [Fact]
    public void SkipPermissions_appends_flag_only_when_opted_in()
    {
        Assert.DoesNotContain("--dangerously-skip-permissions", Launcher.Build(Opts()).AgyTab.Arguments[6]);
        Assert.EndsWith(" --dangerously-skip-permissions", Launcher.Build(Opts(skipPermissions: true)).AgyTab.Arguments[6]);
    }

    [Fact]
    public void Env_values_are_single_quoted_with_embedded_quotes_doubled()
    {
        var plan = Launcher.Build(Opts(logFile: @"C:\o'brien\clavity.log"));
        Assert.Contains(@"agy --log-file 'C:\o''brien\clavity.log'", plan.AgyTab.Arguments[6]);
    }

    [Fact]
    public void ClaudeLaunch_threads_session_identity_and_drops_legacy_marker()
    {
        var plan = Launcher.Build(Opts(claudeArgs: new[] { "--model", "opus" }));

        Assert.Equal("claude", plan.ClaudeLaunch.FileName);
        Assert.Equal(new[] { "--model", "opus" }, plan.ClaudeLaunch.Arguments);
        Assert.Equal(@"C:\work\repo", plan.ClaudeLaunch.WorkingDirectory);
        Assert.Equal("11111111-2222-3333-4444-555555555555",
            plan.ClaudeLaunch.Environment["CLAVITY_SESSION_ID"]);
        Assert.Equal(@"C:\Users\u\.gemini\antigravity-cli\logs\clavity-11111111-2222-3333-4444-555555555555.log",
            plan.ClaudeLaunch.Environment["CLAVITY_AGY_LOG"]);
        Assert.DoesNotContain("CLAVITY_LAUNCHED", plan.ClaudeLaunch.Environment.Keys);
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~LauncherTests"`
Expected: FAIL — `LaunchOptions` has no `SessionId`; env asserts mismatch.

- [ ] **Step 3: Rewrite `Launcher`**

Replace `src/Clavity.Ls/Launcher.cs` with:

```csharp
using System.Text;

namespace Clavity.Ls;

/// <summary>A single process to start: the executable, its argv (STRUCTURED — never a shell string),
/// the working directory, and env vars to set on the child process.</summary>
public sealed record LaunchCommand(
    string FileName,
    IReadOnlyList<string> Arguments,
    string WorkingDirectory,
    IReadOnlyDictionary<string, string> Environment);

/// <summary>The two processes a <c>clavity start</c> performs: the visible, human-owned agy tab and the
/// foreground Claude Code session.</summary>
public sealed record LaunchPlan(LaunchCommand AgyTab, LaunchCommand ClaudeLaunch);

/// <summary>Inputs to <see cref="Launcher.Build"/>.</summary>
public sealed class LaunchOptions
{
    public required string Folder { get; init; }
    /// <summary>Pre-minted per-session id (GUID "D"), threaded into Claude as CLAVITY_SESSION_ID.</summary>
    public required string SessionId { get; init; }
    public IReadOnlyList<string> ClaudeArgs { get; init; } = Array.Empty<string>();
    /// <summary>Resolved ANTIGRAVITY_PROJECT_ID, or null/empty to omit it.</summary>
    public string? ProjectId { get; init; }
    /// <summary>Per-session agy log path; baked into the agy tab as <c>--log-file</c> and exported as CLAVITY_AGY_LOG.</summary>
    public required string AgyLogFilePath { get; init; }
    /// <summary>Opt-in <c>--dangerously-skip-permissions</c> on the agy tab (spec §4: NOT default).</summary>
    public bool SkipPermissions { get; init; }
}

/// <summary>
/// PURE builder for <c>clavity start &lt;folder&gt;</c>: produces the exact commands to (1) open a visible,
/// human-owned agy tab with a PER-SESSION <c>--log-file</c> and (2) launch Claude with the per-session identity
/// in its environment. No process is spawned here (the Cli does that). The agy tab's env is BAKED INTO the
/// pwsh -Command script because Windows Terminal's single-instance delegation does not propagate the launcher's
/// process env into the new tab (verified via agy consult 2026-06-28).
/// </summary>
public static class Launcher
{
    /// <summary>A known, harmless CSRF token — agy does NOT enforce it (spec §12 T1); set to future-proof.</summary>
    public const string CsrfToken = "clavity";

    public static LaunchPlan Build(LaunchOptions options)
    {
        // Deterministic order (Ordinal) so the emitted script is stable for unit tests.
        var agyEnv = new SortedDictionary<string, string>(StringComparer.Ordinal)
        {
            ["ANTIGRAVITY_CSRF_TOKEN"] = CsrfToken,
        };
        if (options.ProjectId is { Length: > 0 } projectId)
            agyEnv["ANTIGRAVITY_PROJECT_ID"] = projectId;

        var script = BuildAgyTabScript(agyEnv, options.AgyLogFilePath, options.SkipPermissions);

        var agyTab = new LaunchCommand(
            FileName: "wt",
            Arguments: new[]
            {
                "new-tab", "--startingDirectory", options.Folder,
                "pwsh", "-NoExit", "-Command", script,
            },
            WorkingDirectory: options.Folder,
            Environment: agyEnv);

        // The per-session identity Claude (and its clavity --mcp child) reads. CLAVITY_AGY_LOG presence implies
        // clavity-launched — the bare CLAVITY_LAUNCHED marker is dropped (spec §4).
        var claudeLaunch = new LaunchCommand(
            FileName: "claude",
            Arguments: options.ClaudeArgs.ToArray(),
            WorkingDirectory: options.Folder,
            Environment: new SortedDictionary<string, string>(StringComparer.Ordinal)
            {
                [AgyEnvironment.LogPathVar] = options.AgyLogFilePath,
                [AgyEnvironment.SessionIdVar] = options.SessionId,
            });

        return new LaunchPlan(agyTab, claudeLaunch);
    }

    private static string BuildAgyTabScript(
        IReadOnlyDictionary<string, string> env, string logFilePath, bool skipPermissions)
    {
        var sb = new StringBuilder();
        foreach (var (key, value) in env)
            sb.Append("$env:").Append(key).Append('=').Append(PwshSingleQuote(value)).Append("; ");
        sb.Append("agy --log-file ").Append(PwshSingleQuote(logFilePath));
        if (skipPermissions)
            sb.Append(" --dangerously-skip-permissions");
        return sb.ToString();
    }

    /// <summary>Single-quote a value for pwsh, escaping embedded single quotes by doubling them.</summary>
    private static string PwshSingleQuote(string value) => "'" + value.Replace("'", "''") + "'";
}
```

- [ ] **Step 4: Run the launcher tests**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~LauncherTests"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/Launcher.cs tests/Clavity.Ls.Tests/LauncherTests.cs
git commit -m "feat(clavity-dotnet): Launcher bakes per-session --log-file + threads CLAVITY_AGY_LOG/SESSION_ID"
```

---

## Task 7: Rework `clavity start` + age-based log retention

**Files:**
- Create: `src/Clavity.Ls/LogRetention.cs`
- Create: `tests/Clavity.Ls.Tests/LogRetentionTests.cs`
- Modify: `src/Clavity.Cli/Program.cs` (`start` block)

- [ ] **Step 1: Write the failing retention test**

Create `tests/Clavity.Ls.Tests/LogRetentionTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class LogRetentionTests
{
    [Fact]
    public void Prune_deletes_logs_older_than_max_age_and_keeps_recent_ones()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-logret-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var now = new DateTime(2026, 6, 28, 12, 0, 0, DateTimeKind.Utc);
            var old = Path.Combine(dir, "clavity-old.log");
            var fresh = Path.Combine(dir, "clavity-fresh.log");
            var unrelated = Path.Combine(dir, "cli.log");
            File.WriteAllText(old, "");
            File.WriteAllText(fresh, "");
            File.WriteAllText(unrelated, "");
            File.SetLastWriteTimeUtc(old, now.AddDays(-8));
            File.SetLastWriteTimeUtc(fresh, now.AddDays(-1));
            File.SetLastWriteTimeUtc(unrelated, now.AddDays(-30));

            LogRetention.Prune(dir, TimeSpan.FromDays(7), now);

            Assert.False(File.Exists(old), "old clavity log should be pruned");
            Assert.True(File.Exists(fresh), "recent clavity log should be kept");
            Assert.True(File.Exists(unrelated), "non-clavity logs must not be touched");
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void Prune_on_missing_directory_does_not_throw() =>
        LogRetention.Prune(
            Path.Combine(Path.GetTempPath(), "clavity-no-such-" + Guid.NewGuid().ToString("N")),
            TimeSpan.FromDays(7), DateTime.UtcNow);
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~LogRetentionTests"`
Expected: FAIL — `LogRetention` undefined.

- [ ] **Step 3: Create `LogRetention`**

Create `src/Clavity.Ls/LogRetention.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>
/// Age-based cleanup of per-session agy logs (<c>logs/clavity-*.log</c>), run on <c>clavity start</c>.
/// NOT PID-liveness based: the captured <c>wt.exe</c> PID is not agy's (spec §3/§11a).
/// </summary>
public static class LogRetention
{
    /// <summary>Default retention window for per-session logs.</summary>
    public static readonly TimeSpan DefaultMaxAge = TimeSpan.FromDays(7);

    /// <summary>Delete <c>clavity-*.log</c> files in <paramref name="logsDir"/> older than <paramref name="maxAge"/>
    /// relative to <paramref name="nowUtc"/>. Missing dir is a no-op; a file held open by a live agy is skipped.</summary>
    public static void Prune(string logsDir, TimeSpan maxAge, DateTime nowUtc)
    {
        if (!Directory.Exists(logsDir))
            return;

        foreach (var path in Directory.EnumerateFiles(logsDir, "clavity-*.log"))
        {
            try
            {
                if (nowUtc - File.GetLastWriteTimeUtc(path) > maxAge)
                    File.Delete(path);
            }
            catch (IOException)
            {
                // A live agy may hold its log open — skip it.
            }
        }
    }
}
```

- [ ] **Step 4: Run to confirm the retention tests pass**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~LogRetentionTests"`
Expected: PASS (2 tests).

- [ ] **Step 5: Rewrite the `start` block in `Program.cs`**

Replace the `start` block in `src/Clavity.Cli/Program.cs` (the `if (args.Length > 0 && args[0] == "start")` section) with this version — it mints the session id, builds the per-session log path under `logs/`, ensures the directory (concurrency-safe), prunes old logs, and threads identity through `Launcher`:

```csharp
// `clavity start <folder> [claude-args...]` — open a visible human-owned agy tab (per-session LS log) + launch Claude.
if (args.Length > 0 && args[0] == "start")
{
    var rest = args.Skip(1).ToArray();
    string folder;
    string[] claudeArgs;
    if (rest.Length > 0 && !rest[0].StartsWith('-'))
    {
        folder = Path.GetFullPath(rest[0]);
        claudeArgs = rest.Skip(1).ToArray();
    }
    else
    {
        folder = Directory.GetCurrentDirectory();
        claudeArgs = rest;
    }

    if (!Directory.Exists(Path.Combine(folder, ".git")))
        Console.Error.WriteLine($"clavity: warning — {folder} is not a git repository.");

    var agyHome = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".gemini", "antigravity-cli");

    var sessionId = Guid.NewGuid().ToString("D");
    var logsDir = Path.Combine(agyHome, "logs");
    Directory.CreateDirectory(logsDir); // idempotent + concurrency-safe (spec §11a).
    LogRetention.Prune(logsDir, LogRetention.DefaultMaxAge, DateTime.UtcNow);
    var agyLogPath = Path.Combine(logsDir, $"clavity-{sessionId}.log");

    var plan = Launcher.Build(new LaunchOptions
    {
        Folder = folder,
        SessionId = sessionId,
        ClaudeArgs = claudeArgs,
        ProjectId = TryReadProjectId(agyHome),
        AgyLogFilePath = agyLogPath,
        SkipPermissions = false,
    });

    Spawn(plan.AgyTab, wait: false);    // agy tab boots asynchronously; human owns it.
    Spawn(plan.ClaudeLaunch, wait: true); // Claude runs in the foreground.
    return;

    static void Spawn(LaunchCommand cmd, bool wait)
    {
        var psi = new ProcessStartInfo(cmd.FileName)
        {
            WorkingDirectory = cmd.WorkingDirectory,
            UseShellExecute = false,
        };
        foreach (var arg in cmd.Arguments)
            psi.ArgumentList.Add(arg);
        foreach (var (key, value) in cmd.Environment)
            psi.Environment[key] = value;
        var process = Process.Start(psi);
        if (wait)
            process?.WaitForExit();
    }

    static string? TryReadProjectId(string agyHome)
    {
        var path = Path.Combine(agyHome, "cache", "default_project_id.txt");
        if (!File.Exists(path))
            return null;
        var id = File.ReadAllText(path).Trim();
        return id.Length > 0 ? id : null;
    }
}
```

- [ ] **Step 6: Build + run the full non-live suite**

Run: `dotnet build -c Release` → 8 projects, 0/0.
Run: `dotnet test -c Release --filter "Category!=LiveAgy"` → all pass.

- [ ] **Step 7: Commit**

```bash
git add src/Clavity.Ls/LogRetention.cs tests/Clavity.Ls.Tests/LogRetentionTests.cs src/Clavity.Cli/Program.cs
git commit -m "feat(clavity-dotnet): clavity start mints per-session identity + per-session log with age-based retention"
```

---

## Task 8 (OPTIONAL — security hardening, spec §12 T2): current-user-only ACL on `logs/`

Spec §12 T2 [MEDIUM] notes default perms on `logs/` could let other local users read a session's log path / hijack the LS. The accepted trust boundary is already the OS user account, so this is a hardening nicety — **safe to cut for a leaner increment.** If kept:

**Files:**
- Create: `src/Clavity.Ls/SecureDirectory.cs`
- Create: `tests/Clavity.Ls.Tests/SecureDirectoryTests.cs`
- Modify: `src/Clavity.Cli/Program.cs` (use it for `logsDir`)

- [ ] **Step 1: Write a cross-platform smoke test**

Create `tests/Clavity.Ls.Tests/SecureDirectoryTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class SecureDirectoryTests
{
    [Fact]
    public void CreateCurrentUserOnly_creates_the_directory_idempotently()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-secdir-" + Guid.NewGuid().ToString("N"));
        try
        {
            SecureDirectory.CreateCurrentUserOnly(dir);
            SecureDirectory.CreateCurrentUserOnly(dir); // idempotent
            Assert.True(Directory.Exists(dir));
        }
        finally
        {
            if (Directory.Exists(dir)) Directory.Delete(dir, true);
        }
    }
}
```

- [ ] **Step 2: Run to confirm failure**

Run: `dotnet test -c Release tests/Clavity.Ls.Tests/Clavity.Ls.Tests.csproj --filter "FullyQualifiedName~SecureDirectoryTests"`
Expected: FAIL — `SecureDirectory` undefined.

- [ ] **Step 3: Implement (Windows ACL; no-op elsewhere)**

Create `src/Clavity.Ls/SecureDirectory.cs`:

```csharp
using System.Runtime.Versioning;
using System.Security.AccessControl;
using System.Security.Principal;

namespace Clavity.Ls;

/// <summary>Create a directory restricted to the current user (spec §12 T2). On non-Windows it just creates the
/// directory (POSIX default umask handling is left to the OS); on Windows it sets an owner-only ACL.</summary>
public static class SecureDirectory
{
    public static void CreateCurrentUserOnly(string path)
    {
        Directory.CreateDirectory(path);
        if (OperatingSystem.IsWindows())
            RestrictToCurrentUserWindows(path);
    }

    [SupportedOSPlatform("windows")]
    private static void RestrictToCurrentUserWindows(string path)
    {
        using var identity = WindowsIdentity.GetCurrent();
        var owner = identity.User!;
        var security = new DirectorySecurity();
        security.SetOwner(owner);
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        security.AddAccessRule(new FileSystemAccessRule(
            owner,
            FileSystemRights.FullControl,
            InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit,
            PropagationFlags.None,
            AccessControlType.Allow));
        new DirectoryInfo(path).SetAccessControl(security);
    }
}
```

> NOTE: `DirectorySecurity`/`SetAccessControl` requires the `System.IO.FileSystem.AccessControl` surface. If the build reports the type is missing, add `<PackageReference Include="System.IO.FileSystem.AccessControl" Version="6.0.0" />` to `src/Clavity.Ls/Clavity.Ls.csproj`. Verify the package resolves on .NET 10 before committing; if it does not, STOP and report rather than substituting a different mechanism.

- [ ] **Step 4: Use it in `start`**

In `src/Clavity.Cli/Program.cs`, replace `Directory.CreateDirectory(logsDir);` with `SecureDirectory.CreateCurrentUserOnly(logsDir);`.

- [ ] **Step 5: Build + test + commit**

Run: `dotnet build -c Release` → 8 projects, 0/0.
Run: `dotnet test -c Release --filter "Category!=LiveAgy"` → all pass.

```bash
git add src/Clavity.Ls/SecureDirectory.cs tests/Clavity.Ls.Tests/SecureDirectoryTests.cs src/Clavity.Cli/Program.cs
git commit -m "feat(clavity-dotnet): current-user-only ACL on logs/ (spec §12 T2 hardening)"
```

---

## Task 9: Full gate + final verification

**Files:** none (verification only).

- [ ] **Step 1: Full Release build**

Run: `dotnet build -c Release`
Expected: **8 projects, 0 warnings, 0 errors.**

- [ ] **Step 2: Full non-live test run**

Run: `dotnet test -c Release --filter "Category!=LiveAgy"`
Expected: all pass. Sanity-check the deltas vs the pre-task baseline:
- `Clavity.Ls.Tests`: −4 (ConversationLocatorTests removed) +1 (GetAllCascadeTrajectoriesGoldenTests) +2 (AgyEnvironmentTests) +2 (LogRetentionTests) [+1 SecureDirectoryTests if Task 8 kept]; LauncherTests still 5.
- `Clavity.Integration.Tests`: +1 LsClient round-trip, +2 AgyView retry/pending, +1 McpTools waiting-JSON.

- [ ] **Step 3: Confirm the working tree is clean**

Run: `git status --short`
Expected: clean (no stray `Launcher.cs`/`LauncherTests.cs`/`Program.cs` diffs outside commits; no `scratchpad` artifacts tracked).

- [ ] **Step 4 (defer to T10, user present): live acceptance**

The remaining live items are out of this increment's CI scope and run with the user present at T10: E1 re-confirm in the real `clavity start` flow; a concurrent two-pair smoke (two `clavity start` runs → each MCP resolves its OWN conversation); and the deferred live `SendUserCascadeMessage` golden-pin (quota + visible message). Use `grpcurl -proto` (LS reflection is OFF).

---

## Self-review (author's pass against the spec)

- **§3 identity threading** → Tasks 6 (Launcher env), 7 (start mints id/log), 5 (`--mcp` consumes `CLAVITY_AGY_LOG`). **No PID** anywhere. ✓
- **§4 components table** → every row mapped: Launcher/LaunchOptions (T6), Cli start (T7), Cli --mcp (T5), LsClient (T3), AgyView (T4), LsDiscovery unchanged (retry lives in AgyView per the spec's "or do the retry in AgyView"), ConversationLocator removed (T4), proto (T2). ✓
- **§5 data flow / §6 error handling** → retry/poll bound (T4 `ConnectAndResolveAsync`), empty-map→`AgyConversationPendingException` no-auto-retry (T4 + surfaced as typed JSON in T5), >1 tiebreak by `last_modified_time` not map order (T4 `SelectMostRecent`), no-env fallback to global cli.log + LS resolve (T5 `ResolveCliLogPath` + unchanged AgyView path). ✓
- **§8 testing** → unit (Launcher T6, AgyEnvironment T5, LogRetention T7), integration (LsClient T3, AgyView retry/pending T4, McpTools waiting T5). ✓
- **§9 empirical** → E1 (T1 gate), E2 (already resolved; re-confirmed T1; golden T2), E3 (T1 observation + pending handling T4). ✓
- **§11a operational** → log retention 7d (T7), `Directory.CreateDirectory` race-safe (T7), GUID "D" (T7). ✓
- **§12 security** → T1 accept (CSRF token kept, documented), T2 ACL (optional T8), T3 resolved (no GetBrowserOpenConversation), T4 consult-bus is out-of-binary (documented; A4 roadmap). ✓
- **§13 directives** → E1 first (T1), atomic locator retire (T4), pinned values (header). Order matches §13 except `AgyEnvironment`/`--mcp` (T5) precedes `Launcher` (T6) because `Launcher` references `AgyEnvironment.LogPathVar`/`SessionIdVar`. ✓ (noted)
- **Placeholder scan:** the only live-derived artifacts are the `GetAllCascadeTrajectories.bin` golden (captured in T2) and the E1/E3 doc facts (T1); the golden test asserts structural invariants needing no live literals. No `TBD`/"add error handling"/uncoded steps. ✓
- **Type consistency:** `CascadeConversation(ConversationId, LastModifiedUtc)`, `AgyViewOptions{CliLogPath,BootRaceTimeout,BootRacePollInterval}`, `AgyConversationPendingException`, `AgyEnvironment.{LogPathVar,SessionIdVar,ResolveCliLogPath}`, `LaunchOptions.SessionId`, `LogRetention.{DefaultMaxAge,Prune}` — names identical across all referencing tasks. ✓
