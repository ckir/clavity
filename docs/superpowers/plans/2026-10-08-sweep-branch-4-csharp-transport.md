# Sweep Branch 4 - C# transport / CLI (§53 wiring, §66, §71, §76) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close four `clavity-dotnet/ROADMAP.md` items on `sweep/branch-4-csharp-transport` (cut from `main` `29e47562`): `agy_ask` tells an agy quota stop from a dropped reply (§66); a rejected `agy_ask` call says why - a wrong argument name, an unavailable model, or any other exception (§71, owner-widened); `PluginInstaller.Clip` never splits a surrogate pair (§76); the materialised pairing-doc path is pinned to reach the agy launch (§53, wiring half).

**Architecture:** All changes are in `clavity-dotnet/` (no classic mirror: `scripts/check-seed-artifacts-synced.sh:32-34` exempts the two transport-twin skills, and the hooks are untouched). §66 reads agy's own per-session log, which `clavity-ls` already opens for port discovery (`AgyViewOptions.CliLogPath`): the quota stop is written there as `RESOURCE_EXHAUSTED (code 429): Individual quota reached. ... Resets in 4h31m14s.` (measured 2026-10-08 in `~/.gemini/antigravity-cli/logs/clavity-*.log`, events of 09-30 and 10-01). The proto route the ROADMAP body sketched (a kind-17 step) is NOT built: no such step is reachable as a fixture - the live LS lists only the current cascade (probe 2026-10-08, 1 cascade, kinds 5/8/14/15/21/101/132), and the ROADMAP rule is fixture first. §71 has two halves: (a) `McpTools.RunAsync` catches the two exception classes it lets escape today; (b) a `CallToolFilter` (SDK 1.4.0 `McpServerOptions.Filters.Request.CallToolFilters`, registered with `WithRequestFilters(...AddCallToolFilter(...))`) checks the call's argument NAMES against the tool's own `InputSchema` BEFORE the SDK binds them, because the SDK's binding failure is swallowed into the generic text inside `McpServerImpl.cs` (v1.4.0, the catch under `BuildFilterPipeline(callToolHandler, ...)`: a non-`McpException` becomes `"An error occurred invoking '{name}'."` and only the LOG sees the cause). Filters run OUTSIDE that catch, so a pre-check is the only place the names are still visible.

**Tech Stack:** .NET 10, xunit, `ModelContextProtocol` 1.4.0 (`McpServerBuilderExtensions.WithRequestFilters`, `McpRequestFilterBuilderExtensions.AddCallToolFilter`, `ModelContextProtocol.Protocol.StreamClientTransport`, `McpServerBuilderExtensions.WithStreamServerTransport`, `McpClient.CreateAsync`), System.IO.Pipelines.

**Gates (the repo's, unchanged):** `cd clavity-dotnet && dotnet build && dotnet test tests/Clavity.Ls.Tests` and `dotnet test tests/Clavity.Integration.Tests`. READ THE COUNTS - `dotnet test --filter` exits 0 on no match. Last recorded: Ls 409 / Integration 114 (ROADMAP §74 body); Task 0 re-measures. Never run two test hosts at once.

**Owner rulings carried in (2026-10-08, seam `.clavity/seams/b4-negotiate.md`):** §33 CLOSED, reply-channel stub CLOSED, §53 narrowed to the wiring half (all in `bb670a1c`). §71 widened to "a rejected call says why", with the SDK interception measured first - done above: interception is possible as a pre-check, not as an exception catch. Unknown argument names are REJECTED (fail closed): a mistyped optional (`artifactpath`) would otherwise silently switch off the echo check. If the owner prefers pass-through for unknown-but-complete calls, flip `ArgumentPrecheck.Problem` in Task 4 - the message text is the contract, not the strictness.

**Commit discipline:** stage explicit paths; the LAST commit before the capstone (Task 8) flips the four ROADMAP headers to IMPLEMENTED citing the fix shas; every new test is proven by the named logic mutant BEFORE its commit (apply the mutant with `git stash`-free edits, run the ONE named test, restore with `git checkout -- <file>`, re-run green).

---

### Task 0: Baseline

**Files:** none modified.

- [ ] **Step 1: Confirm the branch and tip**

Run (from the repo root): `git branch --show-current && git log --oneline -1`
Expected: `sweep/branch-4-csharp-transport` and `bb670a1c ...`. Anything else: STOP, report `STATE_MISMATCH`.

- [ ] **Step 2: Measure the two suites**

Run (from `clavity-dotnet/`): `dotnet build 2>&1 | tail -3 && dotnet test tests/Clavity.Ls.Tests 2>&1 | grep -E "Passed!|Failed!|Total tests"` then `dotnet test tests/Clavity.Integration.Tests 2>&1 | grep -E "Passed!|Failed!|Total tests"`
Expected: both `Passed!`, 0 failed. Write both totals into the execution index (`project_branch-4-csharp-transport_execution.md`) as the baseline.

---

### Task 1: §76 - `PluginInstaller.Clip` cuts with `TextCut.Prefix`

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Ls/Install/PluginInstaller.cs:37`
- Create: `clavity-dotnet/tests/Clavity.Ls.Tests/Install/PluginInstallerTests.cs`

Step 0 (state check): open `PluginInstaller.cs`; line 37 must read exactly
`    private static string Clip(string s) => string.IsNullOrEmpty(s) ? "(no output)" : (s.Length > 200 ? s[..200] : s);`
and `Install(Agent agent, string pluginName, string marketplaceRoot, PowerShellStreamer stream)` must exist (line 12). `PowerShellStreamer` is `delegate ProcessOutcome PowerShellStreamer(RegistrarRequest request)` (`Install/RegistrarRequest.cs:7`); `ProcessOutcome` is `readonly record struct ProcessOutcome(int ExitCode, string Output)` (`Install/AgentResult.cs:7`). Otherwise STOP and report `STATE_MISMATCH`.

- [ ] **Step 1: Write the failing tests**

```csharp
using Clavity.Ls.Install;
using Xunit;

namespace Clavity.Ls.Tests.Install;

public sealed class PluginInstallerTests
{
    // U+1F600 is the surrogate pair 😀: two UTF-16 chars, one character.
    private const string Emoji = "\U0001F600";

    private static PowerShellStreamer Returning(int exit, string output) => _ => new ProcessOutcome(exit, output);

    [Fact]
    public void Install_message_never_ends_on_the_high_half_of_a_surrogate_pair()
    {
        // 199 ASCII chars put the pair at [199],[200]: a raw s[..200] keeps only the high half.
        var output = new string('a', 199) + Emoji + "tail that is cut";
        var r = PluginInstaller.Install(Agent.Claude, "clavity", @"C:\mp", Returning(0, output));
        Assert.True(r.Ok);
        Assert.StartsWith("register-plugin.ps1 exit 0: ", r.Message);
        var cut = r.Message["register-plugin.ps1 exit 0: ".Length..];
        Assert.Equal(new string('a', 199), cut);                 // the pair backed off, nothing else lost
        Assert.False(char.IsHighSurrogate(cut[^1]));
        Assert.DoesNotContain("\uFFFD", r.Message);
    }

    [Fact]
    public void Uninstall_message_keeps_at_most_200_chars_of_output()
    {
        var r = PluginInstaller.Uninstall(Agent.Agy, "clavity", Returning(4, new string('b', 300)));
        Assert.True(r.Ok);                                        // exit 4 = agent not detected = fail-open
        Assert.EndsWith(new string('b', 200), r.Message);
        Assert.DoesNotContain(new string('b', 201), r.Message);
    }

    [Fact]
    public void Empty_output_is_named_not_blank()
    {
        var r = PluginInstaller.Install(Agent.Agy, "clavity", @"C:\mp", Returning(3, ""));
        Assert.False(r.Ok);
        Assert.Equal("register-plugin.ps1 exit 3: (no output)", r.Message);
    }
}
```

If `AgentResult`'s members are not `Ok` / `Message` (check `Install/AgentResult.cs` lines 1-9 before writing), use its real names - do NOT rename the record.

- [ ] **Step 2: Run them - the first must FAIL**

Run: `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~PluginInstallerTests" 2>&1 | grep -E "Passed!|Failed!|Total tests|never_ends"`
Expected: `Total tests: 3`, 1 failed (`Install_message_never_ends...`: `Assert.Equal` - the cut has 200 chars, the last is a high surrogate).

- [ ] **Step 3: Fix**

Replace line 37 with:
```csharp
    // Branch 4 (ROADMAP §76): a character-count cut can split a UTF-16 surrogate pair, and STJ then emits U+FFFD in
    // the diagnostic. TextCut.Prefix backs off one char in exactly that case (same fold as Branch 22 BS1/FA1-FA4).
    private static string Clip(string s) => string.IsNullOrEmpty(s) ? "(no output)" : TextCut.Prefix(s, 200);
```

- [ ] **Step 4: Green, then mutant**

Run the filter again. Expected: `Total tests: 3`, all passed.
Mutant: change `TextCut.Prefix(s, 200)` back to `(s.Length > 200 ? s[..200] : s)`; run the filter. Expected: the surrogate row RED, the other two green. Restore: `git checkout -- src/Clavity.Ls/Install/PluginInstaller.cs`, then re-apply Step 3 (or restore from the editor). Re-run: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/Install/PluginInstaller.cs tests/Clavity.Ls.Tests/Install/PluginInstallerTests.cs
git commit -m "fix(install): PluginInstaller.Clip never splits a surrogate pair (section 76)"
```

---

### Task 2: §53 - pin that the materialised pairing doc reaches the agy launch

**Files:**
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/StartFlowTests.cs` (append rows inside the class)

Step 0 (state check): `StartFlow.cs:92-102` reads `if (TryMaterialize(fx, paths) is not { } doc) return 1;` followed by `fx.WriteScript(paths.AgyScript, Launcher.BuildPosixScript(new LaunchOptions { ... AgyInstallDocPath = doc, }, paths.Claim, paths.Exited));` (the `Agy` verb) and `StartFlow.cs:206-220` reads `if (TryMaterialize(fx, paths) is not { } agyInstallDoc) return 1;` ... `AgyInstallDocPath = agyInstallDoc,` (the `Start` verb). `Launcher.cs:192-193` appends ` -i ` + `ShQuote($"Fetch and follow the instructions at {options.AgyInstallDocPath}")` to the agy tab script. On Windows the script travels base64-UTF-16LE as the wt argument after `-EncodedCommand` (`Launcher.cs:96-98`: `"new-tab", "--startingDirectory", options.Folder, options.WindowsShell, "-NoExit", "-EncodedCommand", encodedScript` - index 6). The test `Fake.MaterializePairingDoc` returns `Path.Combine(dir, "agy-pairing-INSTALL.md")` (`StartFlowTests.cs:58-64`) and records scripts in `fx.Scripts` and launches in `fx.Ran` (`:17`, `:38`). No existing row contains `Fetch and follow` (grep). Otherwise STOP and report `STATE_MISMATCH`.

- [ ] **Step 1: Write the failing rows** (append before the class's closing brace)

```csharp
    // ROADMAP section 53 (wiring half). The refusal half is pinned above (A_pairing_doc_that_cannot_be_written_...);
    // this pins the OTHER regression the pairing-doc fix removed: the materialised path must reach agy's `-i` prompt.
    // A StartFlow that passes null compiles, launches, and agy comes up unpaired with every other row green.
    private static string AgyTabScriptOf(Fake fx, bool windows)
    {
        if (!windows) return fx.Scripts.Single().Content;
        var wt = fx.Ran.Single(c => c.FileName == "wt");
        Assert.Equal("-EncodedCommand", wt.Arguments[5]);
        return Encoding.Unicode.GetString(Convert.FromBase64String(wt.Arguments[6]));
    }

    // The `agy` verb is the POSIX tab entry: it writes the script through fx.WriteScript on every platform
    // (StartFlow.cs:94), so it is exercised once, through fx.Scripts, and not under IsWindows.
    [Theory]
    [InlineData(true, false)]
    [InlineData(false, false)]
    [InlineData(false, true)]
    public void The_materialised_pairing_doc_path_reaches_the_agy_tab_as_the_i_prompt(bool windows, bool agyVerb)
    {
        var fx = new Fake { IsWindows = windows };
        var rc = agyVerb ? StartFlow.Agy([Repo], fx) : StartFlow.Start([Repo], fx);
        Assert.Equal(0, rc);
        var script = AgyTabScriptOf(fx, windows && !agyVerb);
        var line = script.Split('\n').Single(l => l.StartsWith("agy --log-file ", StringComparison.Ordinal));
        Assert.Contains(" -i ", line);
        Assert.Contains("Fetch and follow the instructions at ", line);
        Assert.Contains("agy-pairing-INSTALL.md", line);
    }
```

Add `using System.Text;` at the top of the file if it is not already imported.

- [ ] **Step 2: Run - rows must PASS on the unmutated code**

Run: `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~The_materialised_pairing_doc_path" 2>&1 | grep -E "Passed!|Failed!|Total tests"`
Expected: `Total tests: 3`, all passed. (These rows pin EXISTING behaviour; the failing control is the mutant.)

- [ ] **Step 3: Mutants (two, one per verb)**

Mutant A: `StartFlow.cs:220` `AgyInstallDocPath = agyInstallDoc,` -> `AgyInstallDocPath = null,`. Run the filter. Expected: the two `agyVerb: false` rows RED (no ` -i `), the `agyVerb: true` row green. Restore with `git checkout -- src/Clavity.Ls/StartFlow.cs`.
Mutant B: `StartFlow.cs:102` `AgyInstallDocPath = doc,` -> `AgyInstallDocPath = null,`. Expected: the `agyVerb: true` row RED, the other two green. Restore the same way. Re-run: 3 passed. Run the WHOLE Ls suite once: count = baseline + 3 (Task 1 added 3, so baseline + 6 so far).

- [ ] **Step 4: Commit**

```bash
git add tests/Clavity.Ls.Tests/StartFlowTests.cs
git commit -m "test(start): pin that the materialised pairing-doc path reaches agy's -i prompt, both verbs, both platforms (section 53 wiring half)"
```

---

### Task 3: §71a - `RunAsync` returns a typed status for every exception it let escape

**Files:**
- Modify: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:184-215` (`RunAsync`)
- Modify: `clavity-dotnet/src/Clavity.Mcp/Clavity.Mcp.csproj` (InternalsVisibleTo, only if absent)
- Create: `clavity-dotnet/tests/Clavity.Integration.Tests/McpToolsRunAsyncTests.cs`

Step 0 (state check): `RunAsync` is `private static async Task<string> RunAsync<T>(Func<Task<T>> action)` with exactly three catches: `AgyModalHangException`, `AgyConversationPendingException`, `Exception ex when (ChannelDown.IsChannelDown(ex))` (`McpTools.cs:184-215`). `AgyModelUnavailableException : Exception` has ctors `(string message)` and `(string message, Exception? inner)` (`src/Clavity.Ls/AgyModelUnavailableException.cs:9-12`). Run `grep -rn InternalsVisibleTo src/Clavity.Mcp` - note the result. Otherwise STOP and report `STATE_MISMATCH`.

- [ ] **Step 1: Make `RunAsync` reachable from the integration tests**

Change `private static async Task<string> RunAsync<T>` to `internal static async Task<string> RunAsync<T>`. If the grep in Step 0 found nothing, add to `Clavity.Mcp.csproj` inside `<Project>`:
```xml
  <ItemGroup>
    <InternalsVisibleTo Include="Clavity.Integration.Tests" />
  </ItemGroup>
```

- [ ] **Step 2: Write the failing tests**

```csharp
using System.Text.Json;
using Clavity.Ls;
using Clavity.Mcp;
using Xunit;

namespace Clavity.Integration.Tests;

// ROADMAP section 71 (a): the two exception classes RunAsync let escape to the SDK, which turned them into the generic
// "An error occurred invoking 'agy_ask'." with the cause visible only in the server log (observed twice 2026-10-04,
// after a /model switch). Each now comes back as a typed JSON status that carries its message.
public class McpToolsRunAsyncTests
{
    private static JsonElement Run(Exception toThrow)
    {
        var json = McpTools.RunAsync<object>(() => throw toThrow).GetAwaiter().GetResult();
        return JsonDocument.Parse(json).RootElement.Clone();
    }

    [Fact]
    public void A_model_unavailable_exception_is_a_typed_status_carrying_its_hint()
    {
        var root = Run(new AgyModelUnavailableException("model 'gemini-x' is deprecated; run /model in the agy tab"));
        Assert.Equal("model_unavailable", root.GetProperty("status").GetString());
        Assert.Contains("run /model", root.GetProperty("message").GetString());
    }

    [Fact]
    public void Any_other_exception_is_a_typed_error_naming_its_type_and_message()
    {
        var root = Run(new InvalidOperationException("the catalog answered with no models"));
        Assert.Equal("error", root.GetProperty("status").GetString());
        Assert.Equal("InvalidOperationException", root.GetProperty("exception").GetString());
        Assert.Equal("the catalog answered with no models", root.GetProperty("message").GetString());
    }

    [Fact]
    public void A_caller_cancellation_still_propagates()
    {
        // The SDK rethrows a cancellation the client asked for; swallowing it would report "error" on a cancelled ask.
        Assert.ThrowsAny<OperationCanceledException>(() => Run(new OperationCanceledException()));
    }

    [Fact]
    public void A_channel_down_cause_wrapped_in_model_unavailable_stays_channel_down()
    {
        // ChannelDown.IsChannelDown accepts an AgyModelUnavailableException whose INNER cause is channel-down
        // (ChannelDown.cs); the new arm must sit AFTER that catch so the richer diagnosis still wins.
        var inner = new Grpc.Core.RpcException(new Grpc.Core.Status(Grpc.Core.StatusCode.Unavailable, "refused"));
        var root = Run(new AgyModelUnavailableException("model check failed", inner));
        Assert.NotEqual("model_unavailable", root.GetProperty("status").GetString());
        Assert.True(root.TryGetProperty("diagnostic", out _));
    }
}
```

If `ChannelDown.IsChannelDown` does NOT accept a model-unavailable wrapper around an `RpcException` (read `src/Clavity.Ls/ChannelDown.cs`, the method body, before running), delete the fourth row and say so in the commit message - do not bend the production order to make it pass.

- [ ] **Step 3: Run - the first two must FAIL (exception escapes), the third passes, the fourth passes**

Run: `dotnet test tests/Clavity.Integration.Tests --filter "FullyQualifiedName~McpToolsRunAsyncTests" 2>&1 | grep -E "Passed!|Failed!|Total tests"`
Expected: `Total tests: 4`, 2 failed (unhandled `AgyModelUnavailableException` / `InvalidOperationException`).

- [ ] **Step 4: Add the two arms AFTER the channel-down catch**

```csharp
        catch (AgyModelUnavailableException ex)
        {
            // ROADMAP section 71. Thrown by AgyView when the conversation's model is deprecated or unavailable; its
            // message says how to escape. It reaches here only when ChannelDown.IsChannelDown declined it (a wrapped
            // channel-down cause is diagnosed above), so this is the pure model case.
            return JsonSerializer.Serialize(new { status = "model_unavailable", message = ex.Message });
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // ROADMAP section 71. Anything else used to escape to the SDK, which reports only
            // "An error occurred invoking 'agy_ask'." and keeps the cause for its log. A caller-cancel is left alone:
            // the SDK rethrows it as a cancellation, which is the right answer for a cancelled ask.
            return JsonSerializer.Serialize(new { status = "error", exception = ex.GetType().Name, message = ex.Message });
        }
```

- [ ] **Step 5: Green, mutants, commit**

Run the filter: 4 passed. Mutant 1: swap the order so the `model_unavailable` arm precedes the channel-down catch -> row 4 RED. Mutant 2: drop `when (ex is not OperationCanceledException)` -> row 3 RED. Restore (`git checkout -- src/Clavity.Mcp/McpTools.cs` then re-apply Steps 1 and 4). Run the whole Integration suite: count = baseline + 4 (or + 3 if row 4 was deleted).

```bash
git add src/Clavity.Mcp/McpTools.cs src/Clavity.Mcp/Clavity.Mcp.csproj tests/Clavity.Integration.Tests/McpToolsRunAsyncTests.cs
git commit -m "fix(mcp): agy_ask returns a typed model_unavailable / error status instead of the SDK's generic text (section 71a)"
```

---

### Task 4: §71b - a call with a wrong argument NAME is told which names the tool takes

**Files:**
- Create: `clavity-dotnet/src/Clavity.Mcp/ArgumentPrecheck.cs`
- Modify: `clavity-dotnet/src/Clavity.Cli/Program.cs:50-53`
- Create: `clavity-dotnet/tests/Clavity.Integration.Tests/ArgumentPrecheckTests.cs`

Step 0 (state check): `Program.cs:50-53` reads `builder.Services.AddMcpServer().WithStdioServerTransport().WithTools<McpTools>();` (three chained lines). SDK 1.4.0 facts, verified against the package XML docs and the tagged source: `McpServerBuilderExtensions.WithRequestFilters(IMcpServerBuilder, Action<IMcpRequestFilterBuilder>)`; `McpRequestFilterBuilderExtensions.AddCallToolFilter(IMcpRequestFilterBuilder, McpRequestFilter<CallToolRequestParams, CallToolResult>)`; `delegate McpRequestHandler<TParams,TResult> McpRequestFilter<TParams,TResult>(McpRequestHandler<TParams,TResult> next)`; `delegate ValueTask<TResult> McpRequestHandler<TParams,TResult>(RequestContext<TParams> context, CancellationToken ct)`; `RequestContext<T>.Params`, `MessageContext.Server` (`McpServer`), `McpServer.ServerOptions.ToolCollection` (`McpServerPrimitiveCollection<McpServerTool>?`, `TryGetPrimitive(string, out tool)`), `McpServerTool.ProtocolTool.InputSchema` (`JsonElement`, read with `.GetRawText()` in `McpToolsIntegrationTests.cs:233`), `CallToolRequestParams.Arguments` (`IDictionary<string, JsonElement>?`). The generic text comes from `McpServerImpl.cs` (v1.4.0): `Text = e is McpException ? $"An error occurred invoking '{name}': {e.Message}" : $"An error occurred invoking '{name}'."` INSIDE the innermost handler that `BuildFilterPipeline(callToolHandler, options.Filters.Request.CallToolFilters, ...)` wraps - so a filter sees the result, never the exception. If `dotnet build` disagrees with any name above, STOP and report which.

- [ ] **Step 1: Write the round-trip test (the failing control is the SDK's own generic text)**

```csharp
using System.IO.Pipelines;
using System.Text.Json;
using Clavity.Ls;
using Clavity.Mcp;
using Microsoft.Extensions.DependencyInjection;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;
using Xunit;

namespace Clavity.Integration.Tests;

// ROADMAP section 71 (b), owner-widened 2026-10-08: a call whose ARGUMENT NAMES do not match the tool's schema fails
// inside the SDK's binding, which the SDK reports as "An error occurred invoking 'agy_ask'." with the cause in its
// log only (measured 2026-10-08: `payload` instead of `message`, 73 ms, nothing reached agy, read as a dead channel).
// A CallToolFilter checks the names against the tool's own InputSchema before binding and names the mismatch.
public class ArgumentPrecheckTests
{
    private static async Task<(McpClient Client, IAsyncDisposable Server)> ConnectAsync(bool withFilter)
    {
        var clientToServer = new Pipe();
        var serverToClient = new Pipe();
        var services = new ServiceCollection();
        services.AddSingleton(new AgyView(new AgyViewOptions
        {
            CliLogPath = Path.Combine(Path.GetTempPath(), "precheck-unused.log"),
            BootRaceTimeout = TimeSpan.Zero,
        }));
        var b = services.AddMcpServer()
            .WithStreamServerTransport(clientToServer.Reader.AsStream(), serverToClient.Writer.AsStream())
            .WithTools<McpTools>();
        if (withFilter) b.WithRequestFilters(f => f.AddCallToolFilter(ArgumentPrecheck.Filter));
        var sp = services.BuildServiceProvider();
        var server = sp.GetRequiredService<McpServer>();
        var cts = new CancellationTokenSource();
        var run = server.RunAsync(cts.Token);
        var client = await McpClient.CreateAsync(
            new StreamClientTransport(clientToServer.Writer.AsStream(), serverToClient.Reader.AsStream(), loggerFactory: null));
        return (client, new Stopper(cts, run, sp));
    }

    private sealed class Stopper(CancellationTokenSource cts, Task run, ServiceProvider sp) : IAsyncDisposable
    {
        public async ValueTask DisposeAsync()
        {
            cts.Cancel();
            try { await run; } catch (OperationCanceledException) { }
            await sp.DisposeAsync();
        }
    }

    private static string Text(CallToolResult r) => string.Join("\n", r.Content.OfType<TextContentBlock>().Select(c => c.Text));

    [Fact]
    public async Task Without_the_filter_the_SDK_hides_the_cause_in_a_generic_sentence()
    {
        // The CONTROL: this is what main does today, and what the filter must improve on.
        var (client, server) = await ConnectAsync(withFilter: false);
        await using (server)
        {
            var r = await client.CallToolAsync("agy_ask", new Dictionary<string, object?> { ["payload"] = "hi" });
            Assert.True(r.IsError);
            // StartsWith, not Equal: the SDK may append a cause in a later patch; what the control documents is that today
            // NO argument name appears in it. If the SDK starts naming the cause, this row going red is the good news.
            Assert.StartsWith("An error occurred invoking 'agy_ask'", Text(r));
            Assert.DoesNotContain("payload", Text(r));
        }
    }

    [Fact]
    public async Task A_wrong_argument_name_is_rejected_naming_the_missing_and_unknown_names_and_the_real_ones()
    {
        var (client, server) = await ConnectAsync(withFilter: true);
        await using (server)
        {
            var r = await client.CallToolAsync("agy_ask", new Dictionary<string, object?> { ["payload"] = "hi" });
            Assert.True(r.IsError);
            var t = Text(r);
            Assert.Contains("missing required argument 'message'", t);
            Assert.Contains("unknown argument 'payload'", t);
            Assert.Contains("message (required), artifactPath, discipline", t);
        }
    }

    [Fact]
    public async Task A_mistyped_optional_is_rejected_too_rather_than_silently_dropped()
    {
        var (client, server) = await ConnectAsync(withFilter: true);
        await using (server)
        {
            var r = await client.CallToolAsync("agy_ask", new Dictionary<string, object?> { ["message"] = "hi", ["artifactpath"] = "x.md" });
            Assert.True(r.IsError);
            Assert.Contains("unknown argument 'artifactpath'", Text(r));
            Assert.DoesNotContain("missing required", Text(r));
        }
    }

    [Fact]
    public async Task A_well_formed_call_with_arguments_passes_through_to_the_tool()
    {
        // The call CARRIES arguments (message + the optional discipline), so a filter that dropped or corrupted
        // Arguments would change the outcome. No LS runs: the tool answers with its own typed channel fault, which
        // proves the filter called `next` and the SDK still bound the arguments.
        var (client, server) = await ConnectAsync(withFilter: true);
        await using (server)
        {
            var r = await client.CallToolAsync("agy_ask", new Dictionary<string, object?> { ["message"] = "hi", ["discipline"] = "agy-first" });
            var t = Text(r);
            Assert.DoesNotContain("missing required argument", t);
            Assert.DoesNotContain("unknown argument", t);
            Assert.NotEqual("An error occurred invoking 'agy_ask'.", t);   // bound and ran; its own JSON answered
        }
    }

    [Fact]
    public void Problem_is_null_when_every_required_name_is_present_and_nothing_is_unknown()
    {
        using var schema = JsonDocument.Parse("""{"type":"object","properties":{"message":{},"discipline":{},"artifactPath":{}},"required":["message"]}""");
        var args = new Dictionary<string, JsonElement> { ["message"] = JsonDocument.Parse("\"x\"").RootElement };
        Assert.Null(ArgumentPrecheck.Problem("agy_ask", schema.RootElement, args));
        Assert.Null(ArgumentPrecheck.Problem("agy_look", JsonDocument.Parse("""{"type":"object"}""").RootElement, null));
    }
}
```

If `McpClient.CallToolAsync(string, IReadOnlyDictionary<string, object?>, ...)` needs the arguments typed as `IReadOnlyDictionary<string, object?>` exactly, cast the dictionaries; do not change the assertions.

- [ ] **Step 2: Create `ArgumentPrecheck.cs`**

```csharp
using System.Text.Json;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;

namespace Clavity.Mcp;

/// <summary>ROADMAP section 71 (b). The MCP SDK binds a call's arguments by NAME inside the tool handler and turns a
/// binding failure into "An error occurred invoking '&lt;tool&gt;'." - the cause goes to its log only. A request filter
/// runs before that handler, so it is the last place the names are still visible: compare them with the tool's own
/// InputSchema and refuse with a sentence that names the mismatch and the real names. Fail-open on anything it cannot
/// read (no tool found, no schema): the SDK's own answer stands.</summary>
public static class ArgumentPrecheck
{
    public static McpRequestHandler<CallToolRequestParams, CallToolResult> Filter(McpRequestHandler<CallToolRequestParams, CallToolResult> next)
        => async (context, cancellationToken) =>
        {
            var name = context.Params?.Name;
            if (name is not null
                && context.Server.ServerOptions.ToolCollection is { } tools
                && tools.TryGetPrimitive(name, out var tool)
                && Problem(name, tool.ProtocolTool.InputSchema, context.Params!.Arguments) is { } problem)
            {
                return new CallToolResult { IsError = true, Content = [new TextContentBlock { Text = problem }] };
            }
            return await next(context, cancellationToken);
        };

    /// <summary>Null when the call is well-formed; otherwise the refusal text. Unknown names are refused as well as missing
    /// required ones: a mistyped OPTIONAL (artifactpath) would otherwise be dropped silently and switch a check off.</summary>
    public static string? Problem(string toolName, JsonElement inputSchema, IDictionary<string, JsonElement>? arguments)
    {
        if (inputSchema.ValueKind != JsonValueKind.Object) return null;
        var known = new List<string>();
        if (inputSchema.TryGetProperty("properties", out var props) && props.ValueKind == JsonValueKind.Object)
            foreach (var p in props.EnumerateObject()) known.Add(p.Name);
        var required = new List<string>();
        if (inputSchema.TryGetProperty("required", out var req) && req.ValueKind == JsonValueKind.Array)
            foreach (var r in req.EnumerateArray()) if (r.GetString() is { } s) required.Add(s);

        var given = arguments?.Keys.ToList() ?? new List<string>();
        var missing = required.Where(r => !given.Contains(r, StringComparer.Ordinal)).ToList();
        var unknown = given.Where(g => !known.Contains(g, StringComparer.Ordinal)).ToList();
        if (missing.Count == 0 && unknown.Count == 0) return null;

        // The unknown names are the CLIENT's strings: clip them so a garbage key cannot flood the reply.
        var parts = new List<string>();
        if (missing.Count > 0) parts.Add("missing required argument " + string.Join(", ", missing.Select(m => $"'{m}'")));
        if (unknown.Count > 0) parts.Add("unknown argument " + string.Join(", ", unknown.Select(u => $"'{TextCut.Prefix(u, 60)}'")));
        var names = known.Count == 0
            ? "This tool takes no arguments"
            : "The arguments are: " + string.Join(", ", known.OrderBy(k => required.Contains(k) ? 0 : 1).ThenBy(k => k, StringComparer.Ordinal)
                .Select(k => required.Contains(k) ? $"{k} (required)" : k));
        return $"{toolName}: {string.Join("; ", parts)}. {names}. Argument names are case-sensitive.";
    }
}
```
(`TextCut` is `Clavity.Ls.TextCut`; add `using Clavity.Ls;`.) Add this unit row to `ArgumentPrecheckTests`:
```csharp
    [Fact]
    public void A_tool_with_no_arguments_says_so_instead_of_listing_nothing()
    {
        var args = new Dictionary<string, JsonElement> { ["verbose"] = JsonDocument.Parse("true").RootElement };
        var p = ArgumentPrecheck.Problem("agy_look", JsonDocument.Parse("""{"type":"object"}""").RootElement, args);
        Assert.Equal("agy_look: unknown argument 'verbose'. This tool takes no arguments. Argument names are case-sensitive.", p);
    }
```
(Task 4 then has 6 rows, not 5.)

- [ ] **Step 3: Register the filter in `Program.cs`**

Replace the three-line chain with:
```csharp
    builder.Services
        .AddMcpServer()
        .WithStdioServerTransport()
        .WithTools<McpTools>()
        // ROADMAP section 71 (b): refuse a call whose argument names do not match the tool's schema with a sentence that
        // says which, instead of the SDK's generic "An error occurred invoking". Runs before the SDK binds arguments.
        .WithRequestFilters(f => f.AddCallToolFilter(ArgumentPrecheck.Filter));
```

- [ ] **Step 4: Run**

Run: `dotnet build 2>&1 | grep -E "error|Build succeeded" | head -5` then `dotnet test tests/Clavity.Integration.Tests --filter "FullyQualifiedName~ArgumentPrecheckTests" 2>&1 | grep -E "Passed!|Failed!|Total tests"`
Expected: `Total tests: 6`, all passed. If the CONTROL row fails because the SDK's text differs, quote the real text in the control and in the ROADMAP §71 close note - the control documents the SDK, it does not pass judgement on it. If `Pipe` does not resolve, add `<PackageReference Include="System.IO.Pipelines" Version="10.0.0" />` to the test project (it ships in the shared framework on net10 - this is the fallback, not the expectation).

- [ ] **Step 5: Mutants**

Mutant 1: in `Problem`, `return null;` unconditionally at the top -> rows 2 and 3 RED, control and pass-through green. Mutant 2: in `Program.cs` remove the `.WithRequestFilters(...)` line -> nothing in this file reds (the test wires its own filter) - that is the gap `Task 6` closes with a wiring pin; note it. Restore both.

- [ ] **Step 6: Commit**

```bash
git add src/Clavity.Mcp/ArgumentPrecheck.cs src/Clavity.Cli/Program.cs tests/Clavity.Integration.Tests/ArgumentPrecheckTests.cs
git commit -m "feat(mcp): a call with a wrong argument name is refused naming the real names, before the SDK binds (section 71b)"
```

---

### Task 5: §66 - `agy_ask` tells a quota stop from a dropped reply (from agy's own log)

**Files:**
- Create: `clavity-dotnet/src/Clavity.Ls/QuotaStopLog.cs`
- Modify: `clavity-dotnet/src/Clavity.Ls/AskReply.cs` (one new field)
- Modify: `clavity-dotnet/src/Clavity.Ls/AgyView.cs:209-210` and `:248-258` (`AskAsync`)
- Modify: `clavity-dotnet/src/Clavity.Mcp/McpTools.cs:90-92` (the 13b chain)
- Create: `clavity-dotnet/tests/Clavity.Ls.Tests/QuotaStopTests.cs`
- Modify: `clavity-dotnet/tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs:140-160` (the omitted-when-unset field list)
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` (one new row)

**The measured fact this task rests on.** agy writes its quota stop to the log it was launched with (`agy --log-file <paths.AgyLog>`, `Launcher.cs:189`), which is the same file `clavity-ls` reads as `AgyViewOptions.CliLogPath` (`AgyEnvironment.CliLogPath`: the per-session `CLAVITY_AGY_LOG`). Verbatim lines (2026-10-01, `~/.gemini/antigravity-cli/logs/clavity-14a44091-....log`):
```
E1001 21:09:09.415251  308834 errorreport.go:224] agent executor error: generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.
E1001 21:09:09.531891  308834 errorreport.go:224] generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.
```
Two lines per event; the message is the text after `(code 429): `. Detection is BY FILE POSITION, not by timestamp (glog stamps have no year or zone): the log length is read when the ask starts, and only bytes appended after it are scanned - so an older stop in the same file never fires.

Step 0 (state check): `AgyView.cs:209-210` reads `var beforeTrajectory = await client.GetCascadeTrajectoryAsync(conversationId, cancellationToken);` / `var before = beforeTrajectory.Steps.Count;`; `:245` `var projected = BoundedView.ProjectAskReply(full.CascadeId, delta);`; `:249-256` the `Evaluate13b(projected with { ReplyFile = ..., CaptureError = ..., CheckedSource = ..., TurnEndedOnToolStep = endedOnTool, PeerFile = peerFile, PeerFileStatus = peerStatus, }, checkText, expectTerminal, expectEcho)` call; `_options.CliLogPath` is the per-session log path. `McpTools.cs:90` is the comment `// Branch 22 adds two arms to the same chain - RESCUED first ..., ANSWER CUT last.` followed by `if (reply13b is { CheckedSource: "peer-file" } rescued)`. `AskReply.cs:37` is the last record parameter `string? PeerFileStatus = null);`. Otherwise STOP and report `STATE_MISMATCH`.

- [ ] **Step 1: Failing unit tests for the detector**

```csharp
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

// ROADMAP section 66. Fixture = the real two-line event agy wrote on 2026-10-01 (verbatim; only the pid column varies).
public class QuotaStopTests
{
    private const string Event =
        "E1001 21:09:09.415251  308834 errorreport.go:224] agent executor error: generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n" +
        "E1001 21:09:09.531891  308834 errorreport.go:224] generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n";
    private const string Noise = "I1001 21:09:08.000000  308834 ls.go:10] language server listening on 50465\n";

    private static string Tmp(string content)
    {
        var p = Path.Combine(Path.GetTempPath(), "quota-" + Guid.NewGuid().ToString("N") + ".log");
        File.WriteAllText(p, content);
        return p;
    }

    [Fact]
    public void An_event_appended_after_the_mark_is_found_with_its_reset()
    {
        var p = Tmp(Noise);
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, Event);
        var found = QuotaStopLog.FindSince(p, mark);
        Assert.NotNull(found);
        Assert.Equal("Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.", found);
    }

    [Fact]
    public void An_event_before_the_mark_does_not_fire()
    {
        var p = Tmp(Event + Noise);
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, Noise);
        Assert.Null(QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_truncated_or_rotated_log_is_rescanned_from_the_start()
    {
        var p = Tmp(new string('x', 500) + "\n");
        var mark = QuotaStopLog.Mark(p);            // 501
        File.WriteAllText(p, Event);             // shorter than the mark
        Assert.NotNull(QuotaStopLog.FindSince(p, mark));
    }

    [Fact]
    public void A_missing_log_is_no_stop()
    {
        var p = Path.Combine(Path.GetTempPath(), "quota-missing-" + Guid.NewGuid().ToString("N") + ".log");
        Assert.Equal(0, QuotaStopLog.Mark(p));
        Assert.Null(QuotaStopLog.FindSince(p, 0));
        Assert.Null(QuotaStopLog.FindSince(null, 0));
    }

    [Fact]
    public void A_429_that_is_not_a_quota_message_does_not_fire()
    {
        var p = Tmp("");
        var mark = QuotaStopLog.Mark(p);
        File.AppendAllText(p, "E1001 21:09:09.5 1 x.go:1] RESOURCE_EXHAUSTED (code 429): too many requests\n");
        Assert.Null(QuotaStopLog.FindSince(p, mark));
    }
}
```

- [ ] **Step 2: Run - all five FAIL to compile (`QuotaStopLog` undefined)**

Run: `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~QuotaStopTests" 2>&1 | grep -E "error CS|Passed!|Failed!"`

- [ ] **Step 3: Create `QuotaStopLog.cs`**

```csharp
using System.Text;
using System.Text.RegularExpressions;

namespace Clavity.Ls;

/// <summary>ROADMAP section 66. agy reports a quota stop ONLY in its own log and in its terminal; on the wire the turn
/// ends with no assistant text, which agy_ask could not tell from a dropped reply. The log is the file clavity-ls already
/// opens for port discovery (AgyViewOptions.CliLogPath), so: remember its length when an ask starts, and after the wait
/// scan what was APPENDED for the quota event. Position, not time: glog stamps carry no year or zone.</summary>
public static partial class QuotaStopLog   // not `QuotaStop`: that is the AskReply FIELD it fills, and `QuotaStop = QuotaStop.FindSince(...)` reads badly
{
    /// <summary>Only this much of the appended region is scanned, from its END: the event is written as the turn ends,
    /// so it is near the tail, and a chatty log must not make every ask read megabytes.</summary>
    public const long ScanWindow = 1024 * 1024;

    // The two lines agy writes per event both end with this; the capture is the human sentence after the code.
    [GeneratedRegex(@"RESOURCE_EXHAUSTED \(code 429\): (Individual quota reached\.[^\r\n]*?Resets in [^\s.]+\.?)", RegexOptions.CultureInvariant)]
    private static partial Regex EventRegex();

    /// <summary>The log's current length, or 0 when it cannot be read. Never throws.</summary>
    public static long Mark(string? path)
    {
        try { return path is not null && File.Exists(path) ? new FileInfo(path).Length : 0; }
        catch { return 0; }
    }

    /// <summary>The quota message appended after <paramref name="mark"/>, or null. A file shorter than the mark (rotated,
    /// truncated) is scanned from the start. Opened shared: agy holds the file open for writing. Never throws.</summary>
    public static string? FindSince(string? path, long mark)
    {
        try
        {
            if (path is null || !File.Exists(path)) return null;
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var start = mark <= fs.Length ? mark : 0;
            if (fs.Length - start > ScanWindow) start = fs.Length - ScanWindow;
            fs.Position = start;
            using var reader = new StreamReader(fs, Encoding.UTF8, detectEncodingFromByteOrderMarks: false);
            var appended = reader.ReadToEnd();
            string? last = null;
            foreach (Match m in EventRegex().Matches(appended)) last = m.Groups[1].Value;
            return last;
        }
        catch { return null; }
    }
}
```

- [ ] **Step 4: Run - 5 passed.** Mutant: in `FindSince` replace `var start = mark <= fs.Length ? mark : 0;` with `var start = 0L;` -> `An_event_before_the_mark_does_not_fire` RED. Restore.

- [ ] **Step 5: Carry the stop on `AskReply`**

In `AskReply.cs` append a parameter after `PeerFileStatus`:
```csharp
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? PeerFileStatus = null,
    // ROADMAP section 66: agy's own quota-stop sentence, read from its log for THIS ask; null on every ordinary reply.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? QuotaStop = null);
```
Then open `AskReplyProjectionTests.cs:140-160`: the row there enumerates the fields that must be ABSENT from the JSON while unset (a string array containing `"ReplyFile", "CaptureError", "CheckedSource", "TurnEndedOnToolStep"`, ...) and a `with { ... }` object that sets each. Add `"QuotaStop"` to the array and `QuotaStop: "q"` (or `QuotaStop = "q"` in the `with`) to the set case, and `Assert.Contains("\"QuotaStop\":\"q\"", set);` beside the existing Contains. If the row's shape is different from this description, STOP and report `STATE_MISMATCH` with the lines quoted.

- [ ] **Step 6: Wire it in `AgyView.AskAsync`**

After `var before = beforeTrajectory.Steps.Count;` (`:210`) add:
```csharp
            // ROADMAP section 66: where agy's log ends NOW; a quota stop during this ask lands after this point.
            var logMark = QuotaStopLog.Mark(_options.CliLogPath);
```
In the `projected with { ... }` block (`:249-256`) add, after `PeerFileStatus = peerStatus,`:
```csharp
                    QuotaStop = QuotaStopLog.FindSince(_options.CliLogPath, logMark),
```

- [ ] **Step 7: Surface it in `McpTools` as the FIRST arm of the 13b chain**

Replace the comment line at `:90`, the `if (reply13b is { CheckedSource: "peer-file" } rescued)` arm that follows it (its body is the one-line `RecoveryNotice.Rescued` add with its `// ROADMAP section 74` comment), up to but NOT including the `else if (reply13b is { TerminalTokenMissing: true })` arm, with:
```csharp
        // Branch 22 adds two arms to the same chain - RESCUED first (it replaces the verdicts it cleared), ANSWER CUT last.
        // Branch 4 (section 66) puts the quota stop SECOND, after RESCUED and before the two incompleteness notices: a peer
        // that wrote its reply file and was then quota-stopped before posting in chat is RESCUED (complete), and the stop is
        // only context; a peer stopped before writing anything is explained by the stop, and the right move (wait for the
        // reset) is the opposite of the re-ask the truncation notices suggest. The block itself is emitted in BOTH cases.
        var quotaBlock = reply13b is { QuotaStop: { } quota }
            ? new TextContentBlock
            {
                Text = "[PEER QUOTA STOP] agy hit its quota during this ask: \"" + quota + "\" (agy's own words, from its log). "
                     + (string.IsNullOrEmpty(reply13b.Answer)
                        ? "The reply is missing because agy could not generate, not because it was dropped. "
                        : "The Answer above was produced before the stop; anything agy meant to add after it is missing. ")
                     + "Wait for the reset, then re-ask; do not resend meanwhile - each failed retry has been observed to push "
                     + "the reset further out."
            }
            : null;
        if (reply13b is { CheckedSource: "peer-file" } rescued)
        {
            // ROADMAP section 74, C-peer-read: complete, but never silently - say which file passed.
            blocks.Add(new TextContentBlock { Text = RecoveryNotice.Rescued(rescued) });
            if (quotaBlock is not null) blocks.Add(quotaBlock);
        }
        else if (quotaBlock is not null)
        {
            blocks.Add(quotaBlock);
        }
```

- [ ] **Step 8: Integration row - a quota line appended during the ask produces the block and no TRUNCATED notice**

Open `AgyAskIntegrationTests.cs` and find the row at `:1212` (`McpTools.AgyAsk(view, "review it", ...)` under a `FakeLs`-hosted Kestrel server whose `cliLog` file the view reads). Copy its harness shape (the `try { ... } finally { Directory.Delete(dir, true); }` and the `AgyViewOptions { CliLogPath = cliLog, IdleStallWindow = ..., IdleAbsoluteMax = ... }` block) into a new row in the same class:

```csharp
    [Fact]
    public async Task A_quota_stop_written_to_agys_log_during_the_ask_is_named_instead_of_a_truncated_reply()
    {
        // ROADMAP section 66. The fake peer's turn ends with a tool step and no prose (what a quota stop looks like on the
        // wire); the quota sentence is appended to the cli.log AFTER the ask started. Expect [PEER QUOTA STOP] and NO
        // "[13b] TRUNCATED REPLY" even though a discipline was named.
        <same harness as :1212 - a FakeLs whose post-send trajectory appends one step of Kind 90 and nothing else>
        File.AppendAllText(cliLog,
            "E1001 21:09:09.531891  308834 errorreport.go:224] generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n");
        var result = await McpTools.AgyAsk(view, "review it", new CollectingProgress<ProgressNotificationValue>(), discipline: "agy-capstone");
        var texts = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
        var block = Assert.Single(texts, t => t.StartsWith("[PEER QUOTA STOP]"));
        Assert.Contains("Resets in 24m5s", block);
        Assert.DoesNotContain(texts, t => t.StartsWith("[13b] TRUNCATED REPLY"));
        using var doc = JsonDocument.Parse(texts[0]);
        Assert.Equal("Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.", doc.RootElement.GetProperty("QuotaStop").GetString());
    }
```
The angle-bracket line is the ONE thing to author from the neighbouring row. Verified 2026-10-08: the fake that row uses is `FakeAskLs` (`AgyAskIntegrationTests.cs`), constructed as `new FakeAskLs("conv-1", "unused", TimeSpan.Zero, Array.Empty<CascadeStep>(), waitPlan: ...)` with a settable `Action<string>? OnSend` (line 105) that its `SendUserCascadeMessage` override invokes (line 151) - AFTER `AskAsync` has taken the log mark and BEFORE the wait returns. That is the only moment a quota event can be appended and still count, so the row appends it THERE:

```csharp
        var fake = new FakeAskLs("conv-1", "unused", TimeSpan.Zero, new[] { new CascadeStep { Kind = 90, Status = 3 } },
                                 waitPlan: <the same plan the :1196 row uses>);
        await using var app = await StartFakeAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        fake.OnSend = _ => File.AppendAllText(cliLog,
            "E1001 21:09:09.531891  308834 errorreport.go:224] generating and executing: RESOURCE_EXHAUSTED (code 429): Individual quota reached. Please upgrade your subscription to increase your limits. Resets in 24m5s.\n");
```
(Read `FakeAskLs`'s constructor parameters at its definition before writing: the first three arguments above are copied from the `:1196` row; the fourth is the post-send steps and must give a delta that ENDS on the Kind-90 tool step, so `TrailingAnswer` is null and `TerminalTokenMissing` would be true without the quota arm.) A second row proves the position rule through the same seam: an event appended to the log BEFORE `AgyAsk` is called (before the mark) must NOT fire - arrange it with `File.AppendAllText(cliLog, <same line>)` ahead of the call and no `OnSend`, and expect `[13b] TRUNCATED REPLY` and no `[PEER QUOTA STOP]`. State in the commit message that the first row uses `OnSend`.

- [ ] **Step 9: Run both suites; mutants; commit**

Ls: baseline + 7 + 5 (QuotaStop) + 0 (projection row edited, not added). Integration: previous + 1.
Mutant A: in `AgyView`, replace `QuotaStop = QuotaStopLog.FindSince(_options.CliLogPath, logMark),` with `QuotaStop = null,` -> the new integration row RED. Mutant B: in `McpTools`, move the `else if (quotaBlock is not null)` arm to the END of the chain (after ANSWER CUT) -> the row RED on `DoesNotContain("[13b] TRUNCATED REPLY")`. Restore both.

```bash
git add src/Clavity.Ls/QuotaStopLog.cs src/Clavity.Ls/AskReply.cs src/Clavity.Ls/AgyView.cs src/Clavity.Mcp/McpTools.cs tests/Clavity.Ls.Tests/QuotaStopTests.cs tests/Clavity.Ls.Tests/AskReplyProjectionTests.cs tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(ask): agy_ask names an agy quota stop read from agy's own log instead of reporting a truncated reply (section 66)"
```

---

### Task 6: pin the filter's WIRING (closes the Task 4 mutant-2 gap)

**Files:**
- Modify: `clavity-dotnet/tests/Clavity.Integration.Tests/ArgumentPrecheckTests.cs` (one row)

Step 0: `Program.cs` builds its host inside `Main`/top-level statements and is not callable from a test (it starts the stdio transport). The wiring pin is therefore LEXICAL, the same shape the repo already uses for hook messages (`scripts/check-injected-context.ps1`) - weaker than a behavioural pin, and said so in the row.

- [ ] **Step 1: Add the row**

```csharp
    [Fact]
    public void Program_registers_the_precheck_filter()
    {
        // Lexical pin (Program.cs is not callable from a test): the round-trip rows above wire their OWN filter, so a
        // Program.cs that forgot the registration would ship the generic sentence with every row green.
        // Walk UP from the test binary until the repo's Program.cs is found - no fixed depth, so a custom output
        // directory still resolves; a published flat directory has no src/ above it and fails loudly below.
        string? dir = AppContext.BaseDirectory;
        string? program = null;
        while (dir is not null && program is null)
        {
            var candidate = Path.Combine(dir, "src", "Clavity.Cli", "Program.cs");
            if (File.Exists(candidate)) program = candidate;
            dir = Path.GetDirectoryName(dir);
        }
        Assert.True(program is not null, "src/Clavity.Cli/Program.cs not found above " + AppContext.BaseDirectory + " - this pin needs the source tree");
        var src = File.ReadAllText(program!);
        // Comment-proof: drop /* ... */ blocks, refuse any #if (a disabled region), then require the registration at the
        // start of a line (a `//`-commented line does not start with the call).
        src = System.Text.RegularExpressions.Regex.Replace(src, @"/\*.*?\*/", "", System.Text.RegularExpressions.RegexOptions.Singleline);
        Assert.DoesNotContain("#if", src);
        Assert.Matches(new System.Text.RegularExpressions.Regex(@"^[ \t]*\.WithRequestFilters\(f => f\.AddCallToolFilter\(ArgumentPrecheck\.Filter\)\);", System.Text.RegularExpressions.RegexOptions.Multiline), src);
    }
```
Run the row; it walks up from the test binary, so no depth count is involved. Mutants for this row: delete the registration line, comment it with `//`, wrap it in `/* ... */`, wrap it in `#if false` - all four must go red.

- [ ] **Step 2: Run, mutant, commit**

Mutant: delete the `.WithRequestFilters(...)` line in `Program.cs` -> RED. Restore.
```bash
git add tests/Clavity.Integration.Tests/ArgumentPrecheckTests.cs
git commit -m "test(mcp): pin that Program.cs registers the argument precheck filter (section 71b)"
```

---

### Task 7: docs - the two skill/README catalogues name the new results

**Files:**
- Modify: `clavity-dotnet/plugin/skills/ls-driving/SKILL.md:28-40` (section `## Results you must handle`)
- Modify: `clavity-dotnet/plugin/README.md:114-120` (the troubleshooting bullets)
- Modify: `clavity-dotnet/CHANGELOG.md` (top)

Step 0: `SKILL.md:30` starts `- **\`waiting_for_human\`** - agy is up but has no conversation yet.`; `README.md:114` starts `- **\`agy_status\` / \`agy_ask\` returns \`waiting_for_human\`.**`. 🔴 Load the `superpowers:writing-skills` skill BEFORE editing `SKILL.md` (owner rule). The classic twin `clavity-classic/plugin/skills/driving/SKILL.md` is a different transport (CLI, not MCP) and is exempt from the sync check (`scripts/check-seed-artifacts-synced.sh:32-34`); do not mirror these MCP-only results into it.

- [ ] **Step 1: SKILL.md** - insert these bullets immediately BEFORE the `waiting_for_human` bullet:

```markdown
- **`[PEER QUOTA STOP]` block, `QuotaStop` field set** - agy hit its quota during THIS ask (the sentence is agy's
  own, read from its log, with the reset countdown). The reply is incomplete because agy could not generate, not
  because it was dropped: WAIT for the reset, then re-ask. Do not resend meanwhile - each failed retry has been
  observed to push the reset further out. No `[13b]` notice accompanies it; the stop explains the missing token
  (a `[13b] RESCUED FROM PEER FILE` can precede it: then the reply file is complete and the stop is only context).
- **`model_unavailable`** - the conversation's model is deprecated or unavailable; `message` says how to escape
  (switch it in the agy tab). Not a channel fault: `agy_status` still answers.
- **`error`** - any other failure inside the tool, with `exception` (the .NET type name) and `message`. Read the
  message; it used to be hidden behind the SDK's "An error occurred invoking".
- **A refusal naming arguments** (`agy_ask: missing required argument 'message'; unknown argument 'payload'. The
  arguments are: message (required), artifactPath, discipline.`) - the CALL was malformed and nothing reached agy.
  Fix the argument NAMES (they are case-sensitive) and resend; `agy_status`'s step count will not have moved.
```

- [ ] **Step 2: README.md** - insert BEFORE the `waiting_for_human` bullet:

```markdown
- **`agy_ask` returns a `[PEER QUOTA STOP]` block.** agy's quota ran out during that ask (the text is agy's own,
  with its reset countdown). Wait for the reset; retrying earlier has been observed to push it further out.
- **`agy_ask` returns `model_unavailable` or `error`.** The `message` field carries the cause; `error` also names
  the exception type. These replace the generic "An error occurred invoking 'agy_ask'." for faults inside the tool.
- **`agy_ask` is refused with "missing required argument" / "unknown argument".** The call used a wrong argument
  name (names are case-sensitive: `message`, `discipline`, `artifactPath`); nothing reached agy. Fix the name.
```

- [ ] **Step 3: CHANGELOG.md** - if the file has no `## Unreleased` heading above `## 0.10.2 - 2026-10-02`, add one; under it:

```markdown
### Features
- feat(mcp): a call with a wrong argument name is refused naming the real names, before the SDK binds (section 71b)
- feat(ask): agy_ask names an agy quota stop read from agy's own log instead of reporting a truncated reply (section 66)

### Fixes
- fix(mcp): agy_ask returns a typed model_unavailable / error status instead of the SDK's generic text (section 71a)
- fix(install): PluginInstaller.Clip never splits a surrogate pair (section 76)
```

- [ ] **Step 4: Gates that read these files, then commit**

Run from the repo root: `pwsh -NoProfile -File scripts/check-injected-context.ps1` and `bash scripts/check-seed-artifacts-synced.sh` and `pwsh -NoProfile -File scripts/check-user-facing-docs.ps1`; each must end OK (these are the pre-push gates that touched `README`/skills on Branch 21; if one names a different script for skills, run that one too).
```bash
git add clavity-dotnet/plugin/skills/ls-driving/SKILL.md clavity-dotnet/plugin/README.md clavity-dotnet/CHANGELOG.md
git commit -m "docs(plugin): ls-driving and README name the quota stop, model_unavailable, error and the argument refusal"
```

---

### Task 8: ROADMAP headers (the LAST commit before the capstone)

**Files:**
- Modify: `clavity-dotnet/ROADMAP.md` - the headers found by `grep -n '^### §53 \|^### §66 \|^### §71 \|^### §76 ' clavity-dotnet/ROADMAP.md`

- [ ] **Step 1:** For each of the four, replace the trailing `▶ **... not yet planned**` (or `▶ **NARROWED ...**` for §53) status with `✅ **IMPLEMENTED 2026-10-08 on Branch 4 (\`sweep/branch-4-csharp-transport\`; capstone, test-audit and merge pending) - <fix shas from Tasks 1-6> — was: <the previous status text, verbatim>**`. Keep the title text unchanged. For §66 add one sentence to the BODY: `Built from agy's own log (the file clavity-ls already reads for discovery), not from a kind-17 step: no such step was reachable as a fixture on 2026-10-08, and the rule is fixture first.` For §71 add: `Widened 2026-10-08 (owner): a wrong argument NAME is refused by a CallToolFilter before the SDK binds; the SDK itself (1.4.0, McpServerImpl) swallows the binding exception into the generic sentence, so only a pre-check can name it.`

- [ ] **Step 2:** `pwsh -NoProfile -File scripts/check-roadmap-claims.ps1` -> OK. Commit:
```bash
git add clavity-dotnet/ROADMAP.md
git commit -m "docs(roadmap): Branch 4 - sections 53 (wiring), 66, 71, 76 IMPLEMENTED, citing the fix commits"
```

- [ ] **Step 3:** Update the execution index (`project_branch-4-csharp-transport_execution.md`): every sha, final counts, resume point = AGY-CAPSTONE over `29e47562..HEAD`.

---

## Self-review (run by the author, 2026-10-08)

- **Spec coverage.** §76 -> Task 1. §53 wiring -> Task 2 (both verbs, both platforms, two mutants). §71a (model-unavailable typed, any other exception typed, each pinned) -> Task 3. §71b owner-widened (rejected call says why, SDK interception measured) -> Tasks 4 and 6. §66 (distinct status with the message and reset time, not `[13b]`) -> Task 5; the ROADMAP's "fixture first" rule is honoured by changing the SOURCE of the fixture (the log, which exists) rather than inventing a proto shape. Docs catalogue -> Task 7. Header close -> Task 8.
- **Not built, and said so:** the kind-17 proto route (§66 body); a QuotaStop surface on `agy_status` (out of §66's scope - it names `agy_ask`); the classic `driving` skill (different transport, sync-exempt).
- **Placeholders:** Task 5 Step 8 carries one authored-from-neighbour line (the FakeLs construction) with its shape stated and a STATE check; Task 1 names the two `AgentResult` member names to verify. No TBDs.
- **Type consistency:** `QuotaStopLog.Mark(string?) : long`, `QuotaStopLog.FindSince(string?, long) : string?`, `AskReply.QuotaStop : string?`, `ArgumentPrecheck.Problem(string, JsonElement, IDictionary<string, JsonElement>?) : string?`, `ArgumentPrecheck.Filter : McpRequestFilter<CallToolRequestParams, CallToolResult>` - used identically in every task.
- **Known weak pin:** Task 6 is lexical. A behavioural alternative needs `Program.cs`'s host factored into a callable method - a source change outside this branch's four items; raise it at the capstone if the peer wants it.
- **Decision left to the owner, defaulted:** unknown argument names are refused (fail closed). Flip = one line in `Problem` plus the two rows that assert it.

## Stand-downs (adversarial-panel-review, round 1 solo panel, 2026-10-08)

- `REJECTED`: "a quota stop during a long wait surfaces as `possible_modal`, which Task 5 never annotates" - the stop ENDS agy's turn, so the idle-wait returns normally; the §66 observation itself came back as a normal reply (`[13b] TRUNCATED REPLY`, `PeerStillBusy` false), not as a modal (ROADMAP §66 body).
- `DISCARDED-BELOW-FLOOR`: "two asks in flight could share one log mark" - `AgyView.AskAsync` is serialized by the doorbell idle-gate and the mark is a local of the call (`AgyView.cs:205-262`, the `using (client)` block).
- Solo-panel folds (round 1): quota block emitted after RESCUED and in both the answered and unanswered cases, with wording that does not call a rescued reply incomplete; log scan capped to the last 1 MiB of the appended region; `QuotaStop` class renamed `QuotaStopLog` (it fills the `AskReply.QuotaStop` field); the `agy` verb pinned once (it is POSIX-script on every platform, `StartFlow.cs:94`); a tool with no properties says "takes no arguments"; client-supplied unknown names clipped to 60 chars; the Task 6 lexical pin anchored to line start so a commented-out registration fails it; "measured" -> "observed" for the reset-pushback claim (the source is driver guidance, not a measurement).

### Round 1 agy escalation (cascade fbf2f9db, 2026-10-08) - dispositions
- `FOLDED` AB-1 / LI-1 (Task 5 Step 8 contradicted itself: the mark is taken inside `AskAsync`, so an event appended before the call cannot count): the rows now append from `FakeAskLs.OnSend` (exists, `AgyAskIntegrationTests.cs:105,151`); the "append before the call and still pass" fallback is deleted; a second row pins that a pre-mark event does not fire.
- `REJECTED` PP-1 (`context.Request` / `tool.Tool` do not exist): SDK v1.4.0 `RequestContext.cs:43` declares `public TParams Params { get; set; }`; `McpToolsIntegrationTests.cs:233-234` already uses `tool.ProtocolTool`. The peer's census lists neither the SDK source nor the package XML among the files it opened.
- `FOLDED` MG-1 (pass-through row used an argument-less tool): it now calls `agy_ask` with `message` + `discipline` and asserts the SDK bound them.
- `FOLDED` MG-2 (lexical pin survives `/* */` and `#if false`): block comments are stripped, `#if` is refused, and the four mutants are listed.
- `FOLDED` DC-1 (fixed-depth path): walk-up search for `src/Clavity.Cli/Program.cs` with a loud failure message.
- `FOLDED` DC-2 (control pinned the SDK's exact sentence): `StartsWith` plus "names no argument".
- OPEN, owner decision (peer open question b): a CORRECT name with the WRONG JSON TYPE (an array for `message`) would still bind-fail into the generic sentence. Not folded: unmeasured, and a type check against `InputSchema` has its own edges (`["string","null"]`, integer vs number). Options: (A) add a type check to `Problem` after a measured control row; (B) defer to the anomalies conveyor as a section 71 follow-up. Recommendation: B, unless the owner wants the stricter contract in this branch.
