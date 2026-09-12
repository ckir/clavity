# agy pairing bridge — Implementation Plan (packaging c)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `clavity-ls` reach agy 1.2.2's CSRF-gated Language Server by reading a self-published endpoint file (`~/.clavity/agy-endpoint.json`) for the token+port and sending `x-codeium-csrf-token` on every call; have `clavity start` launch agy so it self-publishes that endpoint; and report a rejected token as `auth_failed`, not `channel_down`.

**Architecture:** agy 1.2.2 gates its LS gRPC API behind `x-codeium-csrf-token`. The token is a random per-session value agy publishes about itself when launched with `-i "Fetch and follow <INSTALL.md>"` (proven live 2026-09-12). `clavity-ls` reads that file, attaches the header via a gRPC client interceptor, and prefers the endpoint's port over cli.log scraping. The existing `ChannelDown` classifier already distinguishes auth failures — the work is to let `Unauthenticated` reach it and to publish/consume the endpoint.

**Tech Stack:** C# / .NET 10, `Grpc.Net.Client` + `Grpc.Core.Interceptors`, xUnit (`dotnet test`), `System.Text.Json`.

**Spec:** `docs/superpowers/specs/2026-09-12-agy-pairing-bridge-design.md`. **Branch:** `agy-pairing-bridge`. **agy fully waived for this plan (owner, 2026-09-12); reviews via subagents.** All build/test commands run from `clavity-dotnet/`.

**Verified against HEAD (`8b3c7ad`):** single LS-construction site `AgyView.cs:460`; boot-race catch `AgyView.cs:488`; idle-probe catch `AgyView.cs:334`; `ChannelDown.Classify` already maps `Unauthenticated`→`AuthFailed` (`ChannelDown.cs:58-59`); `AgyViewOptions` at `AgyView.cs:7-37`; `--mcp` options wiring `Program.cs:8-52`; `Launcher.BuildAgyTabScript` `Launcher.cs:91-101`; xUnit tests in `tests/Clavity.Ls.Tests/` (unit) and `tests/Clavity.Integration.Tests/` (in-proc Kestrel fake gRPC LS). No existing `CallCredentials`/`Interceptor`/`x-codeium` anywhere (net-new).

---

## File Structure

- **Create** `src/Clavity.Ls/AgyEndpoint.cs` — parse `agy-endpoint.json` → `{Csrf, Port}`.
- **Create** `src/Clavity.Ls/CsrfInterceptor.cs` — gRPC interceptor adding `x-codeium-csrf-token`.
- **Modify** `src/Clavity.Ls/LsClient.cs` — optional `csrfToken`; build client through the interceptor; `ConnectToEndpoint` factory.
- **Modify** `src/Clavity.Ls/AgyEnvironment.cs` — endpoint-path env var + resolver.
- **Modify** `src/Clavity.Ls/AgyView.cs` — options field; connect preferring the endpoint; let `Unauthenticated` propagate (two catches).
- **Modify** `src/Clavity.Ls/ChannelDown.cs` — retarget the `AuthFailed` hint at the CSRF/endpoint remedy.
- **Modify** `src/Clavity.Ls/Launcher.cs` — inject `-i "Fetch and follow <INSTALL.md>"`.
- **Modify** `src/Clavity.Cli/Program.cs` — thread endpoint path into `--mcp` options; INSTALL.md path into `start`.
- **Modify** installer (`clavity-dotnet/installer/clavity-dotnet.iss`) — ship `pairing/agy-pairing-INSTALL.md` into the plugin payload.
- **Tests:** new `AgyEndpointTests.cs`; modified `LauncherTests.cs`; new integration tests for the header and the auth_failed diagnostic.

Run unit tests: `dotnet test tests/Clavity.Ls.Tests`. Run integration: `dotnet test tests/Clavity.Integration.Tests`.

---

## Task 1: AgyEndpoint reader

**Files:**
- Create: `src/Clavity.Ls/AgyEndpoint.cs`
- Test: `tests/Clavity.Ls.Tests/AgyEndpointTests.cs`

- [ ] **Step 1: Write the failing tests**

```csharp
// tests/Clavity.Ls.Tests/AgyEndpointTests.cs
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class AgyEndpointTests
{
    private static string WriteTemp(string content)
    {
        var path = Path.Combine(Path.GetTempPath(), $"agy-endpoint-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, content);
        return path;
    }

    [Fact]
    public void TryRead_parses_csrf_and_port_from_addr()
    {
        var path = WriteTemp("""{"csrf":"tok-123","addr":"localhost:55056","published":"2026-09-12T20:47:52Z"}""");
        try
        {
            var ep = AgyEndpoint.TryRead(path);
            Assert.NotNull(ep);
            Assert.Equal("tok-123", ep!.Csrf);
            Assert.Equal(55056, ep.Port);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void TryRead_returns_null_when_file_absent()
    {
        Assert.Null(AgyEndpoint.TryRead(Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.json")));
    }

    [Fact]
    public void TryRead_returns_null_on_malformed_json()
    {
        var path = WriteTemp("not json {");
        try { Assert.Null(AgyEndpoint.TryRead(path)); } finally { File.Delete(path); }
    }

    [Fact]
    public void TryRead_returns_null_when_csrf_or_addr_missing_or_portless()
    {
        var noCsrf = WriteTemp("""{"addr":"localhost:1"}""");
        var noPort = WriteTemp("""{"csrf":"t","addr":"localhost"}""");
        var blank = WriteTemp("""{"csrf":"","addr":"localhost:1"}""");
        try
        {
            Assert.Null(AgyEndpoint.TryRead(noCsrf));
            Assert.Null(AgyEndpoint.TryRead(noPort));
            Assert.Null(AgyEndpoint.TryRead(blank));
        }
        finally { File.Delete(noCsrf); File.Delete(noPort); File.Delete(blank); }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/Clavity.Ls.Tests --filter AgyEndpointTests`
Expected: FAIL — `AgyEndpoint` does not exist (compile error).

- [ ] **Step 3: Write the implementation**

```csharp
// src/Clavity.Ls/AgyEndpoint.cs
using System.Text.Json;

namespace Clavity.Ls;

/// <summary>agy's self-published pairing endpoint (written by the pairing INSTALL.md into
/// ~/.clavity/agy-endpoint.json): the per-session CSRF token and the LS port. agy 1.2.2+ mints both on
/// each LS start, so this file is the ONLY external source of the live token.</summary>
public sealed record AgyEndpoint(string Csrf, int Port)
{
    /// <summary>Read + parse the endpoint file. Returns null on any failure (absent, unreadable, malformed,
    /// missing csrf, or an addr without a parseable port) — the caller falls back to cli.log discovery.</summary>
    public static AgyEndpoint? TryRead(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var root = doc.RootElement;
            if (!root.TryGetProperty("csrf", out var csrfEl) || csrfEl.ValueKind != JsonValueKind.String) return null;
            if (!root.TryGetProperty("addr", out var addrEl) || addrEl.ValueKind != JsonValueKind.String) return null;
            var csrf = csrfEl.GetString();
            var addr = addrEl.GetString();
            if (string.IsNullOrEmpty(csrf) || string.IsNullOrEmpty(addr)) return null;
            var colon = addr.LastIndexOf(':');
            if (colon < 0 || !int.TryParse(addr.AsSpan(colon + 1), out var port) || port <= 0) return null;
            return new AgyEndpoint(csrf, port);
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `dotnet test tests/Clavity.Ls.Tests --filter AgyEndpointTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/AgyEndpoint.cs tests/Clavity.Ls.Tests/AgyEndpointTests.cs
git commit -m "feat(ls): AgyEndpoint reader for the self-published agy-endpoint.json"
```

---

## Task 2: CsrfInterceptor + LsClient sends the header

**Files:**
- Create: `src/Clavity.Ls/CsrfInterceptor.cs`
- Modify: `src/Clavity.Ls/LsClient.cs:25-42` (constructor + Connect factory)
- Test: `tests/Clavity.Integration.Tests/CsrfHeaderTests.cs` (new — uses the in-proc fake gRPC LS pattern)

- [ ] **Step 1: Write the interceptor**

```csharp
// src/Clavity.Ls/CsrfInterceptor.cs
using Grpc.Core;
using Grpc.Core.Interceptors;

namespace Clavity.Ls;

/// <summary>Attaches agy's per-session CSRF token as <c>x-codeium-csrf-token</c> metadata on every unary
/// call. agy 1.2.2+ rejects an un-tokened call with <see cref="StatusCode.Unauthenticated"/>. All LS RPCs
/// are async-unary, so overriding <see cref="AsyncUnaryCall"/> covers every call site.</summary>
public sealed class CsrfInterceptor(string token) : Interceptor
{
    public const string HeaderName = "x-codeium-csrf-token";

    public override AsyncUnaryCall<TResponse> AsyncUnaryCall<TRequest, TResponse>(
        TRequest request,
        ClientInterceptorContext<TRequest, TResponse> context,
        AsyncUnaryCallContinuation<TRequest, TResponse> continuation)
    {
        var headers = context.Options.Headers ?? new Metadata();
        if (headers.Get(HeaderName) is null) headers.Add(HeaderName, token);
        var options = context.Options.WithHeaders(headers);
        return continuation(request, new ClientInterceptorContext<TRequest, TResponse>(
            context.Method, context.Host, options));
    }
}
```

- [ ] **Step 2: Modify LsClient to build through the interceptor**

Replace `LsClient.cs:25-42` (constructor + `Connect`) with:

```csharp
    public LsClient(GrpcChannel channel, TimeSpan? callDeadline = null, string? csrfToken = null)
    {
        _channel = channel;
        Grpc.Core.CallInvoker invoker = string.IsNullOrEmpty(csrfToken)
            ? channel.CreateCallInvoker()
            : channel.Intercept(new CsrfInterceptor(csrfToken!));
        _client = new LanguageServerService.LanguageServerServiceClient(invoker);
        _callDeadline = callDeadline ?? TimeSpan.FromSeconds(DefaultCallDeadlineSeconds);
    }

    /// <summary>A fresh absolute deadline (UTC) for one unary call, computed at call time. <paramref name="over"/>
    /// lets a CALLER tighten the bound for one call (e.g. the boot race clamps to its remaining budget) without
    /// changing the client-wide default.</summary>
    private DateTime NextCallDeadline(TimeSpan? over = null) => DateTime.UtcNow + (over ?? _callDeadline);

    /// <summary>Discover the active LS from cli.log text (liveness-checked) and open an h2c channel to it.
    /// No CSRF token — the pre-1.2.2 / no-endpoint-file fallback path.</summary>
    public static LsClient Connect(string cliLogText, IListeningPorts listening, TimeSpan? callDeadline = null)
    {
        var endpoint = LsDiscovery.DiscoverActive(cliLogText, listening);
        return new LsClient(LsChannel.ForHttpPort(endpoint.HttpPort), callDeadline);
    }

    /// <summary>Connect to agy's self-published endpoint (port + CSRF token from agy-endpoint.json), sending
    /// the token on every call. The 1.2.2+ path.</summary>
    public static LsClient ConnectToEndpoint(AgyEndpoint endpoint, TimeSpan? callDeadline = null)
        => new LsClient(LsChannel.ForHttpPort(endpoint.Port), callDeadline, endpoint.Csrf);
```

Add `using Grpc.Core.Interceptors;` to the top of `LsClient.cs` (alongside the existing `using Grpc.Core;`).

- [ ] **Step 3: Write the failing integration test**

The fake LS must read the incoming header. Mirror the in-proc Kestrel pattern in `tests/Clavity.Integration.Tests/AgyViewIntegrationTests.cs` (`StartFakeAsync`/`PortOf`). Reuse its helpers if visible; otherwise this test starts its own fake that records the header from `ServerCallContext.RequestHeaders`.

```csharp
// tests/Clavity.Integration.Tests/CsrfHeaderTests.cs
using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;
// (match the namespace + fake-server harness used by AgyViewIntegrationTests.cs in this project)

public class CsrfHeaderTests
{
    // A fake LS whose GetAllCascadeTrajectories records the x-codeium-csrf-token header it received.
    private sealed class HeaderCapturingLs : LanguageServerService.LanguageServerServiceBase
    {
        public string? SeenToken;
        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            SeenToken = context.RequestHeaders.GetValue("x-codeium-csrf-token");
            return Task.FromResult(new GetAllCascadeTrajectoriesResponse());
        }
    }

    [Fact]
    public async Task Client_with_token_sends_x_codeium_csrf_token_header()
    {
        var fake = new HeaderCapturingLs();
        await using var app = await FakeLsHost.StartAsync(fake);        // harness: see AgyViewIntegrationTests
        using var client = new LsClient(LsChannel.ForHttpPort(FakeLsHost.PortOf(app)), csrfToken: "tok-abc");

        await client.GetAllCascadeTrajectoriesAsync();

        Assert.Equal("tok-abc", fake.SeenToken);
    }

    [Fact]
    public async Task Client_without_token_sends_no_header()
    {
        var fake = new HeaderCapturingLs();
        await using var app = await FakeLsHost.StartAsync(fake);
        using var client = new LsClient(LsChannel.ForHttpPort(FakeLsHost.PortOf(app)));

        await client.GetAllCascadeTrajectoriesAsync();

        Assert.Null(fake.SeenToken);
    }
}
```

> **Implementer note:** `AgyViewIntegrationTests.cs` starts its fake via a private `StartFakeAsync<T>` + `PortOf`. If those aren't reusable across files, lift them into a small shared `FakeLsHost` helper in this test project first (a pure refactor: move the existing `WebApplication.CreateBuilder()` + `ConfigureKestrel(...Http2)` + `UseUrls("http://127.0.0.1:0")` + `MapGrpcService<T>()` block, and `PortOf`, into `FakeLsHost.StartAsync`/`PortOf`), then use it from both files. Do that refactor as Step 3a and re-run the existing AgyView integration tests to confirm no regression before adding the new test.

- [ ] **Step 4: Run to verify fail → implement → pass**

Run: `dotnet test tests/Clavity.Integration.Tests --filter CsrfHeaderTests`
Expected: after Steps 1-2, PASS (2 tests). Before Step 1-2, the token test FAILS (`SeenToken` null).

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/CsrfInterceptor.cs src/Clavity.Ls/LsClient.cs tests/Clavity.Integration.Tests/
git commit -m "feat(ls): send x-codeium-csrf-token via a client interceptor; ConnectToEndpoint"
```

---

## Task 3: AgyEnvironment endpoint-path resolver

**Files:**
- Modify: `src/Clavity.Ls/AgyEnvironment.cs` (add after line 23)
- Test: `tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs` (add cases)

- [ ] **Step 1: Write the failing tests** (append to `AgyEnvironmentTests.cs`)

```csharp
    [Fact]
    public void ResolveEndpointPath_defaults_under_clavity_when_unset()
    {
        var expected = Path.Combine("C:\\Users\\x", ".clavity", "agy-endpoint.json");
        Assert.Equal(expected, AgyEnvironment.ResolveEndpointPath(null, "C:\\Users\\x"));
        Assert.Equal(expected, AgyEnvironment.ResolveEndpointPath("", "C:\\Users\\x"));
    }

    [Fact]
    public void ResolveEndpointPath_honors_the_override()
    {
        Assert.Equal("D:\\ep.json", AgyEnvironment.ResolveEndpointPath("D:\\ep.json", "C:\\Users\\x"));
    }
```

- [ ] **Step 2: Run to verify fail**

Run: `dotnet test tests/Clavity.Ls.Tests --filter AgyEnvironmentTests`
Expected: FAIL — `ResolveEndpointPath` not defined.

- [ ] **Step 3: Implement** (add to `AgyEnvironment.cs` after line 23, before `ResolveSeconds`)

```csharp
    /// <summary>Env var overriding where agy's self-published endpoint file is read from.</summary>
    public const string EndpointPathVar = "CLAVITY_AGY_ENDPOINT";

    /// <summary>The endpoint file to read the LS port + CSRF token from: the <paramref name="envPath"/> override
    /// when set and non-empty, else <c>&lt;userProfile&gt;/.clavity/agy-endpoint.json</c> (where the pairing
    /// INSTALL.md tells agy to publish it).</summary>
    public static string ResolveEndpointPath(string? envPath, string userProfileDir)
        => string.IsNullOrEmpty(envPath)
            ? Path.Combine(userProfileDir, ".clavity", "agy-endpoint.json")
            : envPath;
```

- [ ] **Step 4: Run to verify pass**

Run: `dotnet test tests/Clavity.Ls.Tests --filter AgyEnvironmentTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/AgyEnvironment.cs tests/Clavity.Ls.Tests/AgyEnvironmentTests.cs
git commit -m "feat(ls): resolve the agy endpoint-file path (CLAVITY_AGY_ENDPOINT)"
```

---

## Task 4: AgyView prefers the endpoint; lets Unauthenticated reach ChannelDown

**Files:**
- Modify: `src/Clavity.Ls/AgyView.cs:7-37` (add option), `:443-475` (connect), `:334` + `:488` (catches)
- Test: `tests/Clavity.Integration.Tests/AgyChannelDownTests.cs` (add cases) — fake LS returning Unauthenticated

- [ ] **Step 1: Add the option** — in `AgyViewOptions` (after `CliLogPath`, line 10), add:

```csharp
    /// <summary>Path to agy's self-published endpoint file (port + CSRF token). When set and the file is
    /// present + valid + its port is listening, the client connects there and sends the token. Null (tests /
    /// pre-1.2.2 fallback) → cli.log discovery only, no token.</summary>
    public string? EndpointPath { get; init; }
```

- [ ] **Step 2: Prefer the endpoint at the single construction site** — replace `AgyView.cs:460`
  (`client = LsClient.Connect(LsDiscovery.ReadCliLogText(_options.CliLogPath), _listening);`) with:

```csharp
                client = ConnectPreferringEndpoint();
```

And add this private helper to `AgyView` (near `ConnectAndResolveAsync`):

```csharp
    /// <summary>Prefer agy's self-published endpoint (port + CSRF token, 1.2.2+): use it when the file is present,
    /// valid, and its port is currently listening. Otherwise fall back to cli.log discovery with no token
    /// (pre-1.2.2 / not-yet-published). The listening check keeps a STALE endpoint (LS restarted → old port dead)
    /// from being dialed; a fresh publish or a relaunch refreshes it.</summary>
    private LsClient ConnectPreferringEndpoint()
    {
        if (_options.EndpointPath is { Length: > 0 } epPath
            && AgyEndpoint.TryRead(epPath) is { } ep
            && _listening.IsListening(ep.Port))
        {
            return LsClient.ConnectToEndpoint(ep);
        }
        return LsClient.Connect(LsDiscovery.ReadCliLogText(_options.CliLogPath), _listening);
    }
```

- [ ] **Step 3: Let Unauthenticated propagate (two catches).**

In `ConnectAndResolveAsync`, **before** the existing catch at `AgyView.cs:488`
(`catch (RpcException ex) when (ex.StatusCode != StatusCode.Cancelled)`), insert:

```csharp
            // A CSRF/auth refusal is DEFINITIVE, not a transient boot-race miss: retrying every poll until the
            // deadline only delays a wrong "not reachable" verdict, and folding it into sawChannelDeath hides the
            // real status. Let it propagate so ChannelDown reports auth_failed (endpoint stale/missing), not
            // channel_down.
            catch (RpcException ex) when (ex.StatusCode is StatusCode.Unauthenticated or StatusCode.PermissionDenied)
            {
                throw;
            }
```

In `WaitForIdleWithProgressAsync`, **before** the blanket probe catch at `AgyView.cs:334`
(`catch (RpcException) when (!cancellationToken.IsCancellationRequested)`), insert:

```csharp
            catch (RpcException ex) when (ex.StatusCode is StatusCode.Unauthenticated or StatusCode.PermissionDenied)
            {
                throw;   // an auth refusal mid-wait (LS rotated the token) is not a hang; let ChannelDown classify it.
            }
```

- [ ] **Step 4: Write the failing integration test** (add to `AgyChannelDownTests.cs`, matching its fake-LS + AgyView harness)

```csharp
    // Fake LS that fails every call with Unauthenticated (agy 1.2.2 with no/stale token).
    private sealed class UnauthLs : LanguageServerService.LanguageServerServiceBase
    {
        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
            => throw new RpcException(new Status(StatusCode.Unauthenticated, "missing CSRF token"));
    }

    [Fact]
    public async Task Unauthenticated_from_the_LS_reports_auth_failed_not_channel_down()
    {
        var fake = new UnauthLs();
        await using var app = await FakeLsHost.StartAsync(fake);
        var cliLog = FakeLsHost.WriteCliLog(FakeLsHost.PortOf(app));   // no endpoint file → cli.log path, no token
        var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });

        // StatusAsync's `catch when ChannelDown.IsChannelDown` returns AgyStatus with
        // State = ChannelDown.StatusFor(diag); Unauthenticated => "auth_failed" (verified: AgyView.cs:172,
        // AskReply.cs:39 `record AgyStatus(string CascadeId, int TotalSteps, string State, int LastStepKind, ...)`).
        var status = await view.StatusAsync();
        Assert.Equal("auth_failed", status.State);
        Assert.NotNull(status.Diagnostic);
        Assert.Equal(nameof(Grpc.Core.StatusCode.Unauthenticated), status.Diagnostic!.StatusCode);
    }
```

> **Verified shape (HEAD `8b3c7ad`):** `AgyStatus.State` carries the status string; the channel-down catch at `AgyView.cs:162-172` sets it from `ChannelDown.StatusFor`. Before Task 4's boot-race rethrow, an `Unauthenticated` is folded into `LsDiscoveryException` → `State == "channel_down"` (test fails); after, it reaches the catch as the real `Unauthenticated` → `State == "auth_failed"` (test passes). Confirm `ChannelDiagnostic.StatusCode` is the property name against its definition (used in `ChannelDown.cs:26`).

- [ ] **Step 5: Run fail → implement → pass**

Run: `dotnet test tests/Clavity.Integration.Tests --filter AgyChannelDownTests`
Expected: the new test FAILS before Step 2-3 (reports `channel_down` via the generic `LsDiscoveryException`), PASSES after.

- [ ] **Step 6: Full Ls + Integration suites green**

Run: `dotnet test tests/Clavity.Ls.Tests` then `dotnet test tests/Clavity.Integration.Tests`
Expected: all pass (no regression in the existing boot-race/idle tests).

- [ ] **Step 7: Commit**

```bash
git add src/Clavity.Ls/AgyView.cs tests/Clavity.Integration.Tests/
git commit -m "fix(ls): connect via the published endpoint; surface Unauthenticated as auth_failed"
```

---

## Task 5: Retarget the AuthFailed hint at the CSRF/endpoint remedy

**Files:**
- Modify: `src/Clavity.Ls/ChannelDown.cs:96-98`
- Test: `tests/Clavity.Ls.Tests/ChannelDownTests.cs` (add a case; create the file if none exists)

- [ ] **Step 1: Write the failing test**

```csharp
// tests/Clavity.Ls.Tests/ChannelDownTests.cs  (add to existing file, or create with this content)
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ChannelDownAuthHintTests
{
    [Fact]
    public void AuthFailed_hint_names_the_endpoint_refresh_remedy_and_not_the_keyring()
    {
        var d = new ChannelDiagnostic(nameof(Grpc.Core.StatusCode.Unauthenticated), "missing CSRF token");
        Assert.Equal("auth_failed", ChannelDown.StatusFor(d));
        var hint = ChannelDown.Hint(d);
        Assert.Contains("agy-endpoint.json", hint);
        Assert.Contains("relaunch", hint, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("keyring", hint, StringComparison.OrdinalIgnoreCase);
    }
}
```

> **Implementer note:** confirm the `ChannelDiagnostic` constructor arity/param names against its definition (referenced throughout `ChannelDown.cs`) before running; adjust the `new ChannelDiagnostic(...)` call to match.

- [ ] **Step 2: Run to verify fail**

Run: `dotnet test tests/Clavity.Ls.Tests --filter ChannelDownAuthHintTests`
Expected: FAIL — current hint mentions "keyring", not "agy-endpoint.json".

- [ ] **Step 3: Replace the `Fault.AuthFailed` arm** at `ChannelDown.cs:96-98` with:

```csharp
            Fault.AuthFailed =>
                prefix + "The channel is UP and agy answered — it REFUSED the credential (CSRF token). agy 1.2.2+ " +
                "mints a new per-session token on each Language Server (re)start, so a published endpoint goes " +
                "stale; the token in ~/.clavity/agy-endpoint.json is stale or the file is missing. Relaunch agy " +
                "(clavity start) so it republishes its endpoint, then retry. Restarting the Claude session alone " +
                "will NOT fix a token refusal.",
```

- [ ] **Step 4: Run to verify pass**

Run: `dotnet test tests/Clavity.Ls.Tests --filter ChannelDownAuthHintTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/ChannelDown.cs tests/Clavity.Ls.Tests/ChannelDownTests.cs
git commit -m "fix(ls): auth_failed hint points at the stale endpoint + relaunch, not the keyring"
```

---

## Task 6: Launcher injects the `-i` acquire prompt

**Files:**
- Modify: `src/Clavity.Ls/Launcher.cs:17-32` (LaunchOptions), `:46-56` + `:91-101` (Build / BuildAgyTabScript)
- Test: `tests/Clavity.Ls.Tests/LauncherTests.cs`

- [ ] **Step 1: Write the failing test** (add to `LauncherTests.cs`)

```csharp
    [Fact]
    public void AgyTab_script_injects_the_fetch_and_follow_prompt_when_an_install_doc_is_given()
    {
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj",
            SessionId = "sid",
            AgyLogFilePath = "C:\\logs\\agy.log",
            SkipPermissions = true,
            AgyInstallDocPath = "C:\\install\\agy-pairing-INSTALL.md",
        });

        var encoded = plan.AgyTab.Arguments[^1];
        var script = System.Text.Encoding.Unicode.GetString(Convert.FromBase64String(encoded));

        Assert.Contains("--dangerously-skip-permissions", script);
        Assert.Contains("-i 'Fetch and follow the instructions at C:\\install\\agy-pairing-INSTALL.md'", script);
        // order: the -i prompt comes AFTER the agy invocation + skip-permissions
        Assert.True(script.IndexOf("--dangerously-skip-permissions", StringComparison.Ordinal)
                    < script.IndexOf(" -i '", StringComparison.Ordinal));
    }

    [Fact]
    public void AgyTab_script_omits_the_prompt_when_no_install_doc_is_given()
    {
        var plan = Launcher.Build(new LaunchOptions
        {
            Folder = "C:\\proj", SessionId = "sid", AgyLogFilePath = "C:\\logs\\agy.log", SkipPermissions = true,
        });
        var script = System.Text.Encoding.Unicode.GetString(Convert.FromBase64String(plan.AgyTab.Arguments[^1]));
        Assert.DoesNotContain(" -i '", script);
    }
```

> **Implementer note:** the existing `LauncherTests.cs:52,64` assertions build a decoded script and assert `StartsWith("$env:ANTIGRAVITY_CSRF_TOKEN='clavity'; agy --log-file ", …)`. Those stay valid (the `-i` is appended, not prepended) — confirm they still pass; if a test constructs `LaunchOptions` without `AgyInstallDocPath`, no `-i` is emitted.

- [ ] **Step 2: Run to verify fail**

Run: `dotnet test tests/Clavity.Ls.Tests --filter LauncherTests`
Expected: FAIL — `AgyInstallDocPath` not a member of `LaunchOptions`.

- [ ] **Step 3: Implement.**

Add to `LaunchOptions` (after `SkipPermissions`, line 31):

```csharp
    /// <summary>If set, agy is launched with <c>-i "Fetch and follow the instructions at &lt;path&gt;"</c> so it
    /// self-publishes its LS endpoint (port + CSRF token) at session start. Null → no acquire prompt.</summary>
    public string? AgyInstallDocPath { get; init; }
```

Change `Build` (line 56) to thread it:

```csharp
        var script = BuildAgyTabScript(agyEnv, options.AgyLogFilePath, options.SkipPermissions, options.AgyInstallDocPath);
```

Change `BuildAgyTabScript` (lines 91-101) to:

```csharp
    private static string BuildAgyTabScript(
        IReadOnlyDictionary<string, string> env, string logFilePath, bool skipPermissions, string? installDocPath)
    {
        var sb = new StringBuilder();
        foreach (var (key, value) in env)
            sb.Append("$env:").Append(key).Append('=').Append(PwshSingleQuote(value)).Append("; ");
        sb.Append("agy --log-file ").Append(PwshSingleQuote(logFilePath));
        if (skipPermissions)
            sb.Append(" --dangerously-skip-permissions");
        if (!string.IsNullOrEmpty(installDocPath))
            sb.Append(" -i ").Append(PwshSingleQuote($"Fetch and follow the instructions at {installDocPath}"));
        return sb.ToString();
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `dotnet test tests/Clavity.Ls.Tests --filter LauncherTests`
Expected: PASS (new + existing).

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/Launcher.cs tests/Clavity.Ls.Tests/LauncherTests.cs
git commit -m "feat(launcher): inject -i 'Fetch and follow <INSTALL.md>' so agy self-publishes its endpoint"
```

---

## Task 7: Program.cs wiring (both branches)

**Files:**
- Modify: `src/Clavity.Cli/Program.cs:8-52` (`--mcp`: set `EndpointPath`) and the `start` branch (~line 101, set `AgyInstallDocPath`)

- [ ] **Step 1: `--mcp` — set `EndpointPath`.** In the `AgyViewOptions` initializer (`Program.cs:17-32`), add:

```csharp
        EndpointPath = AgyEnvironment.ResolveEndpointPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.EndpointPathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
```

- [ ] **Step 2: `start` — pass the shipped INSTALL.md path.** In the `start` branch where `Launcher.Build(new LaunchOptions { … })` is called (~line 101), add to the `LaunchOptions` initializer:

```csharp
        AgyInstallDocPath = Path.Combine(
            AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar),
            "plugins", Clavity.Ls.Install.PluginInstaller.PluginName, "pairing", "agy-pairing-INSTALL.md"),
```

> **Implementer note:** verify the `start` branch's `LaunchOptions` construction site and the exact `PluginInstaller.PluginName`/manuals-dir idiom (the `--mcp` branch uses `Path.Combine(installRoot, "plugins", PluginInstaller.PluginName, "knowledge")` at `Program.cs:18`). Mirror that path shape so the pairing doc resolves under the installed plugin. If the `start` branch does not yet compute an `installRoot`, reuse the same `AppContext.BaseDirectory` idiom shown above.

- [ ] **Step 3: Build + smoke.**

Run: `dotnet build`
Expected: builds clean (no test for `Program.cs` wiring — it's composition; the units it wires are tested in Tasks 3/6).

- [ ] **Step 4: Commit**

```bash
git add src/Clavity.Cli/Program.cs
git commit -m "feat(cli): wire the endpoint path (--mcp) and the pairing INSTALL.md (start)"
```

---

## Task 8: Ship the INSTALL.md in the installer payload

**Files:**
- Modify: `clavity-dotnet/installer/clavity-dotnet.iss` ([Files] section)

- [ ] **Step 1: Verify the current [Files] layout.** Read `clavity-dotnet/installer/clavity-dotnet.iss` `[Files]` section (the plan for it: it already ships `..\plugin\*` into `{app}\plugins\clavity` and `..\..\seed\golden-header.md` into `{app}\seed`). Confirm how the plugin dir + `PluginInstaller.PluginName` map to the installed `plugins\<name>` path that `Program.cs` Step 2 references.

- [ ] **Step 2: Add a [Files] line** shipping the pairing doc to `{app}\plugins\<PluginName>\pairing\agy-pairing-INSTALL.md`. Exact source/dest mirrors the existing plugin/seed lines — e.g.:

```
Source: "..\pairing\agy-pairing-INSTALL.md"; DestDir: "{app}\plugins\clavity\pairing"; Flags: ignoreversion
```

(Match the real `{app}\plugins\<name>` used by the existing `..\plugin\*` line and the `PluginName` constant.)

- [ ] **Step 3: Compile the installer** (per the standing "compile every .iss" rule).

Run (from repo root): `ISCC.exe clavity-dotnet/installer/clavity-dotnet.iss` (or the repo's `just` recipe if one exists)
Expected: compiles with no error; the output setup includes the pairing doc.

- [ ] **Step 4: Commit**

```bash
git add clavity-dotnet/installer/clavity-dotnet.iss
git commit -m "build(installer): ship the agy pairing INSTALL.md into the plugin payload"
```

---

## Task 9: End-to-end verification (manual, live agy)

**Not a unit test — a documented manual check, since it needs a live agy 1.2.2.**

- [ ] **Step 1:** Build + install the updated clavity-dotnet (or run `clavity start` from the build output).
- [ ] **Step 2:** Confirm the launched agy tab's command contains `-i 'Fetch and follow the instructions at …agy-pairing-INSTALL.md'` and that `~/.clavity/agy-endpoint.json` appears with a `csrf`+`addr` within ~15s of launch (matches the 2026-09-12 live validation).
- [ ] **Step 3:** In the paired Claude session, call `agy_status` — expect a real status (not `channel_down`, not `auth_failed`). Then call `agy_ask` with a trivial prompt and confirm a reply round-trips.
- [ ] **Step 4:** Negative: delete `~/.clavity/agy-endpoint.json`, call `agy_status` — expect `auth_failed` (or the cli.log fallback if agy < 1.2.2) with the endpoint-refresh hint, NOT `channel_down`.
- [ ] **Step 5:** Record the outcome in `plugin/knowledge/agy-assumptions.md` (agy 1.2.2 CSRF + the endpoint-publish bridge), per the "re-verify on agy updates" discipline.

---

## Review (subagents, agy fully waived)

Per the owner ruling, no agy consult / capstone / panel. Instead:
- After each task, a fresh subagent reviews the diff against this plan's step (subagent-driven-development's two-stage review).
- After Task 8, dispatch a **verification subagent** to run both suites (`dotnet test tests/Clavity.Ls.Tests` and `dotnet test tests/Clavity.Integration.Tests`) and report the pass lines, and to grep the diff for the Unauthenticated-handling and header-attachment sites actually landing where the plan says.

## Open items carried from the spec (not resolved by this plan)

1. **INSTALL.md hosting** — this plan ships it **locally** (installer payload) and uses a local path in the `-i` prompt. A hosted raw URL ("Fetch and follow https://…") is a later option; the doc content is identical.
2. **Mid-session recovery after a spontaneous LS flap** — the endpoint goes stale and the fix is a **relaunch** (a running clavity-ls cannot ask agy to republish over the LS that just rejected it). This plan surfaces it clearly (`auth_failed` + hint) but does not auto-recover. Auto-recovery / the token-free bus bridge (Plan B) is out of scope here.
3. **The now-inert `Launcher.CsrfToken = "clavity"`** env line stays (harmless; agy overrides it). Left as-is to avoid churn; a later cleanup can drop it.
