# clavity Packaging — Implementation Plan (install-architecture + product-structure)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship clavity-dotnet as a one-command Windows install with a real uninstall, restructure the repo into core variants + opt-in add-ons, and move agy-driving-wisdom injection from a skill instruction into the `clavity-ls` binary.

**Architecture:** Three layers — a thin PowerShell chooser → a per-variant Inno Setup installer → an installer-managed native plugin. The `.NET` CLI is renamed `clavity-ls` and grows `install`/`uninstall`/`curate-commit` verbs plus a `Global\ClavityMcpRunning` mutex. Golden-header wisdom lives at the shared `%USERPROFILE%\.clavity\golden-header.md`, written by `curate-commit` and read+prepended by the binary at ask-time. `agy-autotrain` and `commonmemory` become default-off installer checkboxes.

**Tech Stack:** .NET 10 (`Clavity.Cli` → `clavity-ls`), Inno Setup 6 ([Code] Pascal), PowerShell 7 (chooser), GitHub Actions (release), xUnit (tests). Inno/chooser/CI patterns mirror `C:\Users\user\Development\c#\aidesktop`.

**Two coupled specs this plan implements:**
- `docs/superpowers/specs/2026-06-29-clavity-install-architecture-design.md` (installer mechanics)
- `docs/superpowers/specs/2026-06-29-clavity-product-structure-design.md` (core-vs-optional + 5 refactors)

**Plan discipline note:** Phases 0–2 cite code that EXISTS on the `clavity-dotnet` branch and carry exact code. Phase 3 (Inno/PowerShell/CI) is written from the verified `aidesktop` reference files — no line numbers are fabricated for files that do not yet exist; spike-contingent values are flagged `⟦SPIKE n⟧`. The **Rust `clavity` (classic) binary is not on this branch**, so its golden-header injection is an explicit off-branch follow-on (Task 7.3), NOT a line-level task here.

**Sequencing rule:** Phase 0 spikes gate everything. Within build phases, the product-structure refactors (Phase 1) land first (no installer needed), then the `clavity-ls` install surface (Phase 2), then packaging (Phase 3), then data-lifecycle + add-on wiring (Phase 4).

---

## File structure (created / modified)

**Phase 0 — spikes (one doc):**
- Create: `docs/superpowers/spikes/2026-06-29-packaging-spikes.md` — records all four spike findings.

**Phase 1 — core refactors (.NET + skills):**
- Modify: `src/Clavity.Cli/Clavity.Cli.csproj` — `AssemblyName=clavity-ls` + single-file publish props.
- Modify: `src/Clavity.Cli/Program.cs` — usage strings; `curate-commit` verb.
- Create: `src/Clavity.Ls/GoldenHeader.cs` — path resolve / read+cap / apply / atomic commit / hash sidecar.
- Modify: `src/Clavity.Ls/AgyView.cs` — `AgyViewOptions.GoldenHeaderPath`; prepend in `AskAsync`.
- Create: `tests/Clavity.Ls.Tests/GoldenHeaderTests.cs`.
- Modify: `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs` — assert injection on the send path.
- Modify: `plugins/clavity-classic/skills/clavity-driving/SKILL.md` — fold anti-misfire protocol + auto-inject note.
- Create: `plugins/clavity-dotnet/` — bundled plugin (manifests, `.mcp.json`, `skills/clavity-ls-driving`, `skills/clavity-ls-pairing`, README).
- Delete: `plugins/agy-autotrain/skills/driving-agy/` — protocol merged to core.
- Modify: `plugins/agy-autotrain/skills/agy-curate/SKILL.md` — write header via `clavity-ls curate-commit`, not raw file edit; variant-noun ban.
- Modify: `.claude-plugin/marketplace.json` — register `clavity-dotnet`.

**Phase 2 — `clavity-ls` install surface (.NET):**
- Create: `src/Clavity.Ls/Install/AgentDetection.cs`, `src/Clavity.Ls/Install/PluginInstaller.cs`, `src/Clavity.Ls/Install/CliRouter.cs`.
- Modify: `src/Clavity.Cli/Program.cs` — route `install`/`uninstall` verbs; `--mcp` holds the named mutex.
- Create: `tests/Clavity.Ls.Tests/Install/*` (detection + router unit tests against temp/fake dirs).

**Phase 3 — packaging (no existing files):**
- Create: `installer/clavity-dotnet.iss`, `install/clavity-install.ps1`, `.github/workflows/release-clavity-dotnet.yml`.

**Phase 4 — data lifecycle + add-ons:**
- Modify: `src/Clavity.Ls/Install/CliRouter.cs` (purge `~/.clavity`), `installer/clavity-dotnet.iss` (add-on `[Tasks]`, `.backup` rename, upgrade pre-populate).

---

## Phase 0 — Gating spikes (de-risk before building)

Each spike is a short investigation that ENDS by appending a dated finding section to `docs/superpowers/spikes/2026-06-29-packaging-spikes.md` and committing it. No production code changes in Phase 0.

### Task 0.1: Injection-location spike (Refactor 1 — already largely resolved; confirm + record)

**Files:**
- Create: `docs/superpowers/spikes/2026-06-29-packaging-spikes.md`

- [ ] **Step 1: Confirm where injection happens today**

Run (read-only):
```
rg -n "golden-header|prepend|inject" plugins/agy-autotrain/skills/driving-agy/SKILL.md
```
Expected: `driving-agy/SKILL.md` §"ALWAYS auto-prepend the golden header" instructs *Claude* (the LLM) to read `../../knowledge/golden-header.md` and prepend it. **Finding: injection is a SKILL instruction today, NOT in any binary.** Confirm no binary reads `golden-header.md`:
```
rg -n "golden-header|GOLDEN_HEADER|\.clavity" src/
```
Expected: no matches in `src/`.

- [ ] **Step 2: Record the finding**

Write `docs/superpowers/spikes/2026-06-29-packaging-spikes.md` with a `## Spike 0.1 — injection location` section stating: today = skill-instruction prepend from the plugin-relative `knowledge/golden-header.md`; target = the `clavity-ls` binary reading the shared `%USERPROFILE%\.clavity\golden-header.md`. Therefore Refactor 1 is a **MOVE** (skill→binary), and deleting `driving-agy` removes the only current (classic-path) injection mechanism → the binary read-path must exist before the delete on each variant (dotnet here; Rust classic is Task 7.3, off-branch).

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/spikes/2026-06-29-packaging-spikes.md
git commit -m "spike(packaging): injection is skill-based today; Refactor 1 is a move to the binary"
```

### Task 0.2: Plugin-install invocation + copy-vs-reference spike

**Files:**
- Modify: `docs/superpowers/spikes/2026-06-29-packaging-spikes.md`

- [ ] **Step 1: Capture each agent's plugin-install help**

Run:
```
claude plugin --help
claude plugin install --help
agy plugin --help
agy plugin install --help
```
Record the exact non-interactive install/uninstall syntax for both. **Known from prior session:** `claude plugin install` is MARKETPLACE-based (`<plugin>@<marketplace>`, `--scope user` default) and COPIES into `~/.claude/plugins/cache/<marketplace>/<plugin>/`; `agy plugin install` takes a LOCAL PATH (`agy plugin install ./plugins/<name>`). Confirm both still hold.

- [ ] **Step 2: Determine copy-vs-reference for agy**

Install a throwaway copy of an existing local plugin into agy, then inspect the agy plugin store:
```
agy plugin install ./plugins/commonmemory
fd -t d commonmemory ~/.gemini
```
Decide: does agy COPY the dir into its store, or REFERENCE the source path? (Determines whether `{app}\plugin` is canonical or a dead staging dir, and uninstall ordering.) Uninstall the throwaway:
```
agy plugin uninstall commonmemory
```

- [ ] **Step 3: Record + commit**

Append `## Spike 0.2 — plugin-install` with: exact `claude`/`agy` install + uninstall commands, copy-vs-ref verdict per agent, and the implication for `clavity-ls install` (Task 2.2) and uninstall gating (Task 2.3).
```bash
git add docs/superpowers/spikes/2026-06-29-packaging-spikes.md
git commit -m "spike(packaging): plugin-install invocation + copy-vs-reference per agent"
```

### Task 0.3: Non-extracting single-file publish spike

**Files:**
- Modify: `docs/superpowers/spikes/2026-06-29-packaging-spikes.md`

- [ ] **Step 1: Publish single-file and check for native extraction**

Run:
```
dotnet publish src/Clavity.Cli -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -o ./scratch-publish
```
Then run the produced exe once and check whether anything extracts to `%TEMP%\.net\`:
```
./scratch-publish/clavity-ls.exe   # prints usage and exits
fd . "$env:TEMP/.net" 2>$null
```
**Expected (hypothesis):** because `Grpc.Net.Client` is fully MANAGED (no native lib like the old `Grpc.Core`), no `%TEMP%\.net\` extraction occurs → true single-file is viable. Record the actual result and the exe size.

- [ ] **Step 2: Record + commit**

Append `## Spike 0.3 — single-file publish` with: the exact publish command that worked, whether native extraction happened, the final exe size, and the decision (single-file vs framework-dependent). Delete `./scratch-publish`.
```bash
git add docs/superpowers/spikes/2026-06-29-packaging-spikes.md
git commit -m "spike(packaging): non-extracting single-file publish result for clavity-ls"
```

### Task 0.4: Agent-detection heuristic spike

**Files:**
- Modify: `docs/superpowers/spikes/2026-06-29-packaging-spikes.md`

- [ ] **Step 1: Enumerate the detection signals**

Run:
```
(Get-Command claude).Source
(Get-Command agy).Source
ls ~/.claude ; ls ~/.gemini ; ls ~/.gemini/config
```
**Known from prior session:** `claude` = `~/.local/bin/claude`; `agy` = `~/AppData/Local/agy/bin/agy`; config dirs `~/.claude/` and `~/.gemini/config/` both exist. Confirm and decide the heuristic: an agent is "present" iff (its CLI is on PATH) OR (its config dir exists).

- [ ] **Step 2: Record + commit**

Append `## Spike 0.4 — agent detection` with the exact detection rule per agent (PATH probe + config-dir probe), which `AgentDetection` (Task 2.1) implements.
```bash
git add docs/superpowers/spikes/2026-06-29-packaging-spikes.md
git commit -m "spike(packaging): agent-detection heuristic for clavity-ls install"
```

---

## Phase 1 — Core product-structure refactors

These need no installer and produce a working, testable `clavity-ls` with binary-side golden-header injection and a clean core/optional skill split.

### Task 1.1: Rename `Clavity.Cli` output to `clavity-ls` + single-file publish config

**Files:**
- Modify: `src/Clavity.Cli/Clavity.Cli.csproj`
- Modify: `src/Clavity.Cli/Program.cs:101` (usage string)

- [ ] **Step 1: Add AssemblyName + publish props to the csproj**

In `src/Clavity.Cli/Clavity.Cli.csproj`, extend the existing `<PropertyGroup>` (currently lines 13–18) so it reads:

```xml
  <PropertyGroup>
    <OutputType>Exe</OutputType>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <AssemblyName>clavity-ls</AssemblyName>
    <RuntimeIdentifier>win-x64</RuntimeIdentifier>
    <SelfContained>true</SelfContained>
    <PublishSingleFile>true</PublishSingleFile>
    <IncludeNativeLibrariesForSelfExtract>false</IncludeNativeLibrariesForSelfExtract>
  </PropertyGroup>
```

> Use the exact single-file settings that **Spike 0.3** proved. If Spike 0.3 found native extraction unavoidable, drop `SelfContained`/`PublishSingleFile` here and set them only on the CI `dotnet publish` invocation (Task 3.3) — but keep `<AssemblyName>clavity-ls</AssemblyName>` regardless.

- [ ] **Step 2: Build and confirm the new artifact name**

Run:
```
dotnet build src/Clavity.Cli -c Release
```
Expected: PASS; output dll/exe is `clavity-ls.dll` / `clavity-ls.exe`.

- [ ] **Step 3: Update the usage string**

In `src/Clavity.Cli/Program.cs:101`, change the leading token from `clavity` to `clavity-ls`:
```csharp
Console.WriteLine("clavity-ls — usage: clavity-ls start <folder> [claude-args...]   |   clavity-ls --mcp   (MCP stdio server: agy_look / agy_status / agy_ask)");
```

- [ ] **Step 4: Run the full non-live suite**

Run:
```
dotnet test --filter "Category!=LiveAgy"
```
Expected: PASS (Ls.Tests=26, Integration.Tests=15 baseline).

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Cli/Clavity.Cli.csproj src/Clavity.Cli/Program.cs
git commit -m "refactor(clavity-dotnet): rename CLI output to clavity-ls + single-file publish config"
```

### Task 1.2: Golden-header read + inject primitive in the binary

**Files:**
- Create: `src/Clavity.Ls/GoldenHeader.cs`
- Test: `tests/Clavity.Ls.Tests/GoldenHeaderTests.cs`

- [ ] **Step 1: Write the failing tests**

Create `tests/Clavity.Ls.Tests/GoldenHeaderTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class GoldenHeaderTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-gh-" + Guid.NewGuid().ToString("N"));

    public GoldenHeaderTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, recursive: true); } catch { } }

    [Fact]
    public void ResolvePath_uses_env_override_when_set()
    {
        Assert.Equal(@"C:\custom\h.md", GoldenHeader.ResolvePath(@"C:\custom\h.md", @"C:\Users\u"));
    }

    [Fact]
    public void ResolvePath_falls_back_to_userprofile_dot_clavity_when_env_blank()
    {
        Assert.Equal(
            Path.Combine(@"C:\Users\u", ".clavity", "golden-header.md"),
            GoldenHeader.ResolvePath("   ", @"C:\Users\u"));
    }

    [Fact]
    public void TryRead_returns_null_when_absent()
        => Assert.Null(GoldenHeader.TryRead(Path.Combine(_dir, "nope.md")));

    [Fact]
    public void TryRead_returns_null_when_empty_or_whitespace()
    {
        var p = Path.Combine(_dir, "h.md");
        File.WriteAllText(p, "   \n  ");
        Assert.Null(GoldenHeader.TryRead(p));
    }

    [Fact]
    public void TryRead_returns_content_when_present()
    {
        var p = Path.Combine(_dir, "h.md");
        File.WriteAllText(p, "RULE: be precise");
        Assert.Equal("RULE: be precise", GoldenHeader.TryRead(p));
    }

    [Fact]
    public void TryRead_returns_null_when_over_cap()
    {
        var p = Path.Combine(_dir, "h.md");
        File.WriteAllText(p, new string('x', GoldenHeader.MaxBytes + 1));
        Assert.Null(GoldenHeader.TryRead(p));
    }

    [Fact]
    public void Apply_prepends_with_blank_line_when_header_present()
        => Assert.Equal("HDR\n\nmsg", GoldenHeader.Apply("HDR\n", "msg"));

    [Fact]
    public void Apply_returns_message_unchanged_when_header_null_or_empty()
    {
        Assert.Equal("msg", GoldenHeader.Apply(null, "msg"));
        Assert.Equal("msg", GoldenHeader.Apply("", "msg"));
    }

    [Fact]
    public void Commit_writes_content_atomically_and_is_readable_back()
    {
        var p = Path.Combine(_dir, "sub", "golden-header.md");
        GoldenHeader.Commit(p, "compiled wisdom");
        Assert.Equal("compiled wisdom", GoldenHeader.TryRead(p));
    }

    [Fact]
    public void Commit_throws_when_content_exceeds_cap()
    {
        var p = Path.Combine(_dir, "h.md");
        Assert.Throws<InvalidOperationException>(() => GoldenHeader.Commit(p, new string('x', GoldenHeader.MaxBytes + 1)));
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~GoldenHeaderTests"`
Expected: FAIL (type `GoldenHeader` does not exist).

- [ ] **Step 3: Implement `GoldenHeader`**

Create `src/Clavity.Ls/GoldenHeader.cs`:

```csharp
using System.Security.Cryptography;
using System.Text;

namespace Clavity.Ls;

/// <summary>
/// The shared, variant-agnostic golden-header (accumulated agy-driving wisdom). Read+prepended to every ask by
/// the binary, written only by `clavity-ls curate-commit`. Path = %USERPROFILE%\.clavity\golden-header.md,
/// overridable via CLAVITY_GOLDEN_HEADER. Reads NO-OP cleanly when the file is absent, empty, or over the size
/// cap — that is what makes the agy-autotrain add-on optional.
/// </summary>
public static class GoldenHeader
{
    public const string PathVar = "CLAVITY_GOLDEN_HEADER";

    /// <summary>Strict byte cap (security §size-cap): over-cap content is refused, not injected.</summary>
    public const int MaxBytes = 16 * 1024;

    /// <summary>CLAVITY_GOLDEN_HEADER if set+non-blank, else %USERPROFILE%\.clavity\golden-header.md.</summary>
    public static string ResolvePath(string? envOverride, string userProfileDir) =>
        string.IsNullOrWhiteSpace(envOverride)
            ? Path.Combine(userProfileDir, ".clavity", "golden-header.md")
            : envOverride;

    /// <summary>Content to inject, or null when absent / empty / over-cap. Never throws on IO.</summary>
    public static string? TryRead(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var len = new FileInfo(path).Length;
            if (len == 0 || len > MaxBytes) return null;
            var text = File.ReadAllText(path);
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// <summary>Prepend the header (blank-line separated) when present; otherwise return the message unchanged.</summary>
    public static string Apply(string? header, string message) =>
        string.IsNullOrEmpty(header) ? message : header.TrimEnd() + "\n\n" + message;

    /// <summary>Atomic write of curated content to the resolved path (+ a .sha256 sidecar for tamper detection).
    /// Enforces the size cap. Used by `clavity-ls curate-commit`; agy-curate INVOKES it (never raw-edits).</summary>
    public static void Commit(string path, string content)
    {
        var bytes = Encoding.UTF8.GetByteCount(content);
        if (bytes > MaxBytes)
            throw new InvalidOperationException($"golden-header content {bytes}B exceeds {MaxBytes}B cap");

        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var tmp = path + ".tmp";
        File.WriteAllText(tmp, content);
        File.Move(tmp, path, overwrite: true);
        File.WriteAllText(path + ".sha256", Sha256Hex(content));
    }

    internal static string Sha256Hex(string content) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(content)));
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~GoldenHeaderTests"`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/GoldenHeader.cs tests/Clavity.Ls.Tests/GoldenHeaderTests.cs
git commit -m "feat(clavity-dotnet): GoldenHeader read/cap/apply/commit (binary-side injection primitive)"
```

### Task 1.3: Wire injection into `AgyView.AskAsync` + the `--mcp` host

**Files:**
- Modify: `src/Clavity.Ls/AgyView.cs` (AgyViewOptions + AskAsync send path)
- Modify: `src/Clavity.Cli/Program.cs:12-16` (--mcp options)
- Test: `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`

- [ ] **Step 1: Write the failing integration assertion**

In `tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs`, add a test that the outgoing message is prefixed with the golden-header when `GoldenHeaderPath` points at a populated file. Mirror the existing fake-LS happy-path test, but have the fake capture the `SendUserCascadeMessage` text and assert it starts with the header. (Use the existing fake's send-capture hook; if none exists, add a `LastSentText` field to the fake LS and assert on it.)

```csharp
[Fact]
public async Task AskAsync_prepends_golden_header_to_the_sent_message()
{
    using var tmp = new TempDir();
    var headerPath = Path.Combine(tmp.Path, "golden-header.md");
    File.WriteAllText(headerPath, "DRIVING RULE: scope to judgment");

    await using var fake = await FakeLanguageServer.StartBusyThenIdleAsync();   // existing helper
    var view = new AgyView(new AgyViewOptions
    {
        CliLogPath = fake.CliLogPath,
        GoldenHeaderPath = headerPath,
    }, fake.ListeningPorts);

    await view.AskAsync("please review", timeout: TimeSpan.FromSeconds(5));

    Assert.StartsWith("DRIVING RULE: scope to judgment", fake.LastSentText);
    Assert.Contains("please review", fake.LastSentText);
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/Clavity.Integration.Tests --filter "FullyQualifiedName~AskAsync_prepends_golden_header"`
Expected: FAIL (`AgyViewOptions` has no `GoldenHeaderPath`; message not prefixed).

- [ ] **Step 3: Add the option + inject before send**

In `src/Clavity.Ls/AgyView.cs`, add to `AgyViewOptions` (after `BootRacePollInterval`, line 16):
```csharp
    /// <summary>Resolved golden-header path to read+prepend per ask; null disables injection (tests / no add-on).</summary>
    public string? GoldenHeaderPath { get; init; }
```

In `AskAsync`, replace the send line (currently `src/Clavity.Ls/AgyView.cs:72`):
```csharp
            await client.SendUserCascadeMessageAsync(conversationId, message, cancellationToken);
```
with:
```csharp
            var header = _options.GoldenHeaderPath is null ? null : GoldenHeader.TryRead(_options.GoldenHeaderPath);
            var outgoing = GoldenHeader.Apply(header, message);
            await client.SendUserCascadeMessageAsync(conversationId, outgoing, cancellationToken);
```

- [ ] **Step 4: Wire the real path in the `--mcp` host**

In `src/Clavity.Cli/Program.cs`, extend the `AgyViewOptions` initializer in the `--mcp` block (lines 12–16) to set the golden-header path:
```csharp
    var options = new AgyViewOptions
    {
        CliLogPath = AgyEnvironment.ResolveCliLogPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.LogPathVar), agyDir),
        GoldenHeaderPath = GoldenHeader.ResolvePath(
            Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
    };
```

- [ ] **Step 5: Run tests**

Run: `dotnet test --filter "Category!=LiveAgy"`
Expected: PASS (new injection test green; existing tests unaffected since they leave `GoldenHeaderPath` null).

- [ ] **Step 6: Commit**

```bash
git add src/Clavity.Ls/AgyView.cs src/Clavity.Cli/Program.cs tests/Clavity.Integration.Tests/AgyAskIntegrationTests.cs
git commit -m "feat(clavity-dotnet): inject golden-header into AgyView.AskAsync before the LS send"
```

### Task 1.4: `clavity-ls curate-commit` verb

**Files:**
- Create: `src/Clavity.Ls/CliVerbs.cs`
- Modify: `src/Clavity.Cli/Program.cs` (new verb branch, after the `--mcp` block)
- Test: `tests/Clavity.Integration.Tests/CurateCommitTests.cs` (new)

- [ ] **Step 1: Write the failing test**

Create `tests/Clavity.Integration.Tests/CurateCommitTests.cs` against a testable static verb helper (top-level `Program.cs` is awkward to invoke in-process, so the verb body lives in `CliVerbs`):

```csharp
using Clavity.Ls;

namespace Clavity.Integration.Tests;

public sealed class CurateCommitTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-cc-" + Guid.NewGuid().ToString("N"));
    public CurateCommitTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, recursive: true); } catch { } }

    [Fact]
    public void CurateCommit_writes_resolved_path_from_content_arg()
    {
        var path = Path.Combine(_dir, "golden-header.md");
        Environment.SetEnvironmentVariable(GoldenHeader.PathVar, path);
        try
        {
            var rc = CliVerbs.CurateCommit(new[] { "curate-commit", "compiled rules" }, () => "");
            Assert.Equal(0, rc);
            Assert.Equal("compiled rules", GoldenHeader.TryRead(path));
        }
        finally { Environment.SetEnvironmentVariable(GoldenHeader.PathVar, null); }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `dotnet test tests/Clavity.Integration.Tests --filter "FullyQualifiedName~CurateCommit"`
Expected: FAIL (`CliVerbs` does not exist).

- [ ] **Step 3: Implement the verb helper + route it**

Create `src/Clavity.Ls/CliVerbs.cs`:
```csharp
namespace Clavity.Ls;

/// <summary>Testable bodies for the non-host CLI verbs (kept out of Program.cs top-level for unit testing).</summary>
public static class CliVerbs
{
    /// <summary>`curate-commit &lt;content&gt;` — content from arg[1] or, if absent, stdin. Atomic write via GoldenHeader.</summary>
    public static int CurateCommit(string[] args, Func<string> readStdin)
    {
        var content = args.Length > 1 ? args[1] : readStdin();
        var path = GoldenHeader.ResolvePath(
            Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
        GoldenHeader.Commit(path, content);
        return 0;
    }
}
```

In `src/Clavity.Cli/Program.cs`, add a branch AFTER the `--mcp` block (~line 31, before the `start` block):
```csharp
if (args.Length > 0 && args[0] == "curate-commit")
{
    return Clavity.Ls.CliVerbs.CurateCommit(args, Console.In.ReadToEnd);
}
```
> Returning an `int` here makes the implicit `Main` `int`-returning. A top-level program may mix `return;` and `return <int>;`; if the compiler objects, change the file's trailing `Console.WriteLine(...)` to be followed by `return 0;` and convert the bare `return;` statements to `return 0;`.

- [ ] **Step 4: Run tests**

Run: `dotnet test --filter "Category!=LiveAgy"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/Clavity.Ls/CliVerbs.cs src/Clavity.Cli/Program.cs tests/Clavity.Integration.Tests/CurateCommitTests.cs
git commit -m "feat(clavity-dotnet): clavity-ls curate-commit verb (atomic golden-header write)"
```

### Task 1.5: Merge anti-misfire protocol into core driving skills; create `clavity-ls-driving`; delete `driving-agy`

This is **variant-simultaneous** (spec Refactor 2): update BOTH core driving skills BEFORE deleting `driving-agy`, so classic never loses the protocol.

**Files:**
- Modify: `plugins/clavity-classic/skills/clavity-driving/SKILL.md`
- Create: `plugins/clavity-dotnet/skills/clavity-ls-driving/SKILL.md`
- Delete: `plugins/agy-autotrain/skills/driving-agy/SKILL.md` (+ the now-empty dir)

- [ ] **Step 1: Fold the anti-misfire protocol into classic `clavity-driving`**

Insert a new section into `plugins/clavity-classic/skills/clavity-driving/SKILL.md` (before "## 6. Clarify / cancel / recover"), copied VERBATIM from the deleted `driving-agy` "Task-assignment protocol (this is what stops agy misfiring)" block, plus an auto-injection note:

```markdown
## Task-assignment protocol — what stops agy misfiring

agy is bold and acts on what you give it. Frame the task precisely:

- **Review / red-team / consult → loud REVIEW-ONLY banner.** Open the payload with a 🛑 banner that
  forbids edits/commits and **enumerates** the forbidden actions (no file writes, no git, no bridge
  task). Without it, agy will *execute* a task you meant as a review. End with explicit permission to
  return "no blockers."
- **Phase isolation.** Never mix research and implementation in one payload. Tag
  `[PHASE: EXPLORATION]` (gather/opine, no build) **or** `[PHASE: EXECUTION]` (build to a spec) — mixing
  fills agy's context with raw search output and degrades the build.
- **Mandatory checkpoint for mutating delegations.** If you delegate a task that changes files, the
  payload must instruct agy to make a recoverable checkpoint (`git stash` / temp branch) **before**
  touching the tree.
- **Delegated implementation → name the oracle + the done-condition + "no scope creep."** Seed the
  exact invariants/tests that define correct; tell it to STOP and report rather than adapt on a mismatch.
- **Seed invariants, don't ask it to "find bugs."** agy verifies far better than it discovers; give it
  the specific things to confirm/refute and permission that "no must-fix is valid."

<!-- KEEP IN SYNC WITH clavity-ls-driving (plugins/clavity-dotnet/skills/clavity-ls-driving/SKILL.md) -->

## Injection is automatic — do NOT prepend the golden header yourself

The clavity binary reads `%USERPROFILE%\.clavity\golden-header.md` (if the agy-autotrain add-on is
installed) and prepends it to every ask for you. Do NOT read or prepend it manually. If the file is
absent (add-on not installed), the binary simply skips it — you drive with this baseline protocol.
```

- [ ] **Step 2: Create the dotnet `clavity-ls-driving` skill**

Create `plugins/clavity-dotnet/skills/clavity-ls-driving/SKILL.md` — the MCP-tool variant (uses `agy_look`/`agy_status`/`agy_ask`, not `clavity ask`), carrying the SAME anti-misfire protocol block (with the reverse keep-in-sync marker) + dotnet-specific tool notes:

```markdown
---
name: clavity-ls-driving
description: Use to drive a paired agy peer via the clavity-ls MCP tools (agy_look / agy_status / agy_ask) — when to look vs ask, write/quota semantics, and handling waiting/modal results.
---

# Driving agy with clavity-ls (MCP)

You (Claude) drive a paired agy over its Language Server via three MCP tools:
- **`agy_look`** — read the active conversation's bounded trajectory (no quota).
- **`agy_status`** — lightweight liveness/step count.
- **`agy_ask`** — send a message and return agy's reply. **This is a quota-consuming WRITE** that posts a
  human-visible message in agy's tab. Use it for an independent second-model review / design partner, not
  for chatter.

## Results you must handle
- `waiting_for_human` — agy is up but has no conversation yet. STOP and wait for the human; do NOT loop-retry.
- `possible_modal` — the idle-wait hit the client timeout; agy may have a blocking modal open. Surface it to
  the human; do not assume a silent failure.

## Task-assignment protocol — what stops agy misfiring
<!-- KEEP IN SYNC WITH clavity-driving (plugins/clavity-classic/skills/clavity-driving/SKILL.md) -->
(… paste the IDENTICAL protocol block from clavity-driving here, in full — no ellipsis …)

## Injection is automatic — do NOT prepend the golden header yourself
`clavity-ls` reads `%USERPROFILE%\.clavity\golden-header.md` (if agy-autotrain is installed) and prepends it
to every `agy_ask` for you. Do NOT prepend it manually; absent file = baseline protocol.
```
> When authoring, paste the protocol block in full — the ellipsis above is a plan placeholder only.

- [ ] **Step 3: Delete `driving-agy`**

```bash
git rm -r plugins/agy-autotrain/skills/driving-agy
```

- [ ] **Step 4: Verify no driving content remains in autotrain**

Run:
```
rg -n "task-assignment|REVIEW-ONLY|PHASE: EXECUTION|front door" plugins/agy-autotrain/skills
```
Expected: no matches (driving content fully moved). `agy-learn` / `agy-curate` skills remain (knowledge-only).

- [ ] **Step 5: Commit**

```bash
git add plugins/clavity-classic/skills/clavity-driving/SKILL.md plugins/clavity-dotnet/skills/clavity-ls-driving/SKILL.md
git commit -m "refactor(plugins): merge anti-misfire protocol into core driving skills; delete driving-agy"
```

### Task 1.6: Repoint `agy-curate` to write via `curate-commit`; ban variant nouns

**Files:**
- Modify: `plugins/agy-autotrain/skills/agy-curate/SKILL.md`

- [ ] **Step 1: Replace the raw-file-write instruction**

In `plugins/agy-autotrain/skills/agy-curate/SKILL.md`, the section that says "Rewrite `../../knowledge/golden-header.md` …" MUST change to: compile the dense header text, then **write it by invoking the binary** — `clavity-ls curate-commit "<content>"` (or `clavity curate-commit` for the classic variant) — never raw-edit a file, because only the binary knows `CLAVITY_GOLDEN_HEADER` and does the atomic write + hash sidecar. Add the **variant-noun ban**: the header holds variant-AGNOSTIC agy reasoning wisdom only (no `agy_ask`/`clavity ask`-specific mechanics — those live in the per-variant core driving skill).

```markdown
## Compile + commit the golden header (via the binary, never a raw edit)

Compile the dense, payload-ready header from the now-current canonical docs, then COMMIT it through the
binary so it lands at the resolved shared path with an atomic write + tamper hash:

    clavity-ls curate-commit "<compiled header text>"      # dotnet variant
    clavity curate-commit "<compiled header text>"         # classic variant

Do NOT edit `golden-header.md` directly — only the binary knows `CLAVITY_GOLDEN_HEADER` and writes the
.sha256 sidecar. Keep it short (prepended to every ask) and **variant-agnostic**: forbid project nouns
AND variant-specific driving mechanics (e.g. `agy_ask` argument shaping) — those belong in the
per-variant core driving skill, not the shared header.
```

- [ ] **Step 2: Add the anti-poisoning circuit-breaker instruction (security §poisoning)**

Add a sentence instructing the curator (Claude) to critically evaluate and REJECT bad heuristics rather than blindly compiling agy's self-reported learnings into laws.

- [ ] **Step 3: Commit**

```bash
git add plugins/agy-autotrain/skills/agy-curate/SKILL.md
git commit -m "refactor(agy-autotrain): curate writes the golden-header via curate-commit; variant-noun ban + circuit-breaker"
```

### Task 1.7: Create the bundled `clavity-dotnet` plugin (Component C) + register it

**Files:**
- Create: `plugins/clavity-dotnet/.claude-plugin/plugin.json`, `plugins/clavity-dotnet/plugin.json`, `plugins/clavity-dotnet/.mcp.json`, `plugins/clavity-dotnet/skills/clavity-ls-pairing/SKILL.md`, `plugins/clavity-dotnet/README.md`
- Modify: `.claude-plugin/marketplace.json`

> `skills/clavity-ls-driving/SKILL.md` was created in Task 1.5.

- [ ] **Step 1: Write the manifests**

`plugins/clavity-dotnet/.claude-plugin/plugin.json` and `plugins/clavity-dotnet/plugin.json` (mirror the agy-autotrain manifest shape):
```json
{
  "name": "clavity-dotnet",
  "version": "0.1.0",
  "description": "Pair Claude with a live agy peer via the clavity-ls Language-Server bridge: drive agy with the agy_look / agy_status / agy_ask MCP tools, and (for agy) a tempered LS-pairing etiquette skill."
}
```

- [ ] **Step 2: Write `.mcp.json` (Claude registers the stdio server)**

```json
{
  "mcpServers": {
    "clavity-ls": { "command": "clavity-ls", "args": ["--mcp"] }
  }
}
```

- [ ] **Step 3: Write the agy-side pairing skill**

`plugins/clavity-dotnet/skills/clavity-ls-pairing/SKILL.md` — tempered orientation (spec Component C): you are LS-driven by a paired Claude; keep ONE active conversation; don't leave blocking modals open; prefer precise/parseable output (exact paths, error codes) while staying human-readable.

- [ ] **Step 4: Register in the marketplace**

In `.claude-plugin/marketplace.json`, add to `plugins`:
```json
    {
      "name": "clavity-dotnet",
      "source": "./plugins/clavity-dotnet",
      "description": "Pair Claude with a live agy peer via the clavity-ls Language-Server bridge (agy_look / agy_status / agy_ask)."
    }
```

- [ ] **Step 5: Commit**

```bash
git add plugins/clavity-dotnet .claude-plugin/marketplace.json
git commit -m "feat(plugins): bundled clavity-dotnet plugin (manifests, .mcp.json, pairing skill) + marketplace entry"
```

---

## Phase 2 — `clavity-ls install` / `uninstall` surface

Gated on **Spike 0.2** (exact plugin invocation + copy-vs-ref) and **Spike 0.4** (detection rule). Mirrors `aidesktop`'s `CliRouter` structure (`C:\Users\user\Development\c#\aidesktop\src\FlaUI.Mcp.Server\Install\CliRouter.cs`) but installs a PLUGIN via each agent's native command instead of writing raw MCP JSON.

### Task 2.1: Agent detection

**Files:**
- Create: `src/Clavity.Ls/Install/AgentDetection.cs`
- Test: `tests/Clavity.Ls.Tests/Install/AgentDetectionTests.cs`

- [ ] **Step 1: Write the failing tests**

Test the detection rule from Spike 0.4 against an injectable probe (PATH-presence func + config-dir existence), so tests never depend on the real machine:

```csharp
using Clavity.Ls.Install;

namespace Clavity.Ls.Tests.Install;

public sealed class AgentDetectionTests
{
    [Fact]
    public void Detects_claude_when_cli_on_path()
    {
        var d = new AgentDetection(onPath: n => n == "claude", dirExists: _ => false);
        Assert.True(d.IsPresent(Agent.Claude));
        Assert.False(d.IsPresent(Agent.Agy));
    }

    [Fact]
    public void Detects_agy_when_config_dir_exists()
    {
        var d = new AgentDetection(onPath: _ => false, dirExists: p => p.Contains(".gemini"));
        Assert.True(d.IsPresent(Agent.Agy));
    }

    [Fact]
    public void DetectsNone_when_neither_signal()
    {
        var d = new AgentDetection(onPath: _ => false, dirExists: _ => false);
        Assert.Empty(d.Present());
    }
}
```

- [ ] **Step 2: Run to verify fail** — `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~AgentDetection"` → FAIL.

- [ ] **Step 3: Implement `AgentDetection`** using the EXACT rule Spike 0.4 recorded (PATH probe + config-dir probe per agent). Enum `Agent { Claude, Agy }`; ctor takes `Func<string,bool> onPath` + `Func<string,bool> dirExists` (default to a real `where`/`Directory.Exists`); `IsPresent(Agent)` and `Present()` returning the detected set.

- [ ] **Step 4: Run tests** → PASS.

- [ ] **Step 5: Commit** — `feat(clavity-dotnet): agent detection for clavity-ls install`.

### Task 2.2: `install --agent all --plugin <dir>` (native plugin install + zero-agent guard)

**Files:**
- Create: `src/Clavity.Ls/Install/PluginInstaller.cs`, `src/Clavity.Ls/Install/CliRouter.cs`, `src/Clavity.Ls/Install/AgentResult.cs`
- Test: `tests/Clavity.Ls.Tests/Install/CliRouterTests.cs`
- Modify: `src/Clavity.Cli/Program.cs` (route `install`/`uninstall`)

- [ ] **Step 1: Write the failing router tests** (against an injected fake process-runner so no real agent is invoked): for each detected agent the EXACT command from Spike 0.2 is run; a missing optional agent is reported but does not fail the whole install; and the **zero-agent guard** returns non-zero with the *"No compatible agent (Claude Code / agy) found"* message (spec UX "zero-agent guard").

- [ ] **Step 2: Run to verify fail.**

- [ ] **Step 3: Implement `PluginInstaller` + `CliRouter`.** `PluginInstaller.Install(Agent, pluginDir, runner)` shells the native command Spike 0.2 pinned ⟦SPIKE 0.2⟧ — known shapes: Claude = `claude plugin marketplace add <repoRoot>` then `claude plugin install clavity-dotnet@clavity --scope user`; agy = `agy plugin install <pluginDir>`. `CliRouter.Run(args, TextWriter)` parses `install`/`uninstall`, `--agent`, `--plugin`, `--purge-data`, calls `AgentDetection.Present()`, writes per-agent `AgentResult` lines; **non-zero exit if zero agents present**. `IsInstallerVerb(args)` mirrors aidesktop.

- [ ] **Step 4: Route the verbs in `Program.cs`** (after the `curate-commit` branch, before `start`):
```csharp
if (Clavity.Ls.Install.CliRouter.IsInstallerVerb(args))
{
    return Clavity.Ls.Install.CliRouter.Run(args, Console.Out);
}
```

- [ ] **Step 5: Run tests** → PASS. **Step 6: Commit** — `feat(clavity-dotnet): clavity-ls install --agent all (native plugin install + zero-agent guard)`.

### Task 2.3: `uninstall --agent all [--purge-data]` (non-zero on failure; gate-ready)

**Files:**
- Modify: `src/Clavity.Ls/Install/CliRouter.cs`, `src/Clavity.Ls/Install/PluginInstaller.cs`
- Test: `tests/Clavity.Ls.Tests/Install/CliRouterTests.cs`

- [ ] **Step 1: Write failing tests** — `uninstall` runs the native `plugin uninstall` per detected agent ⟦SPIKE 0.2⟧; returns **non-zero if ANY agent's removal fails** (the Inno `InitializeUninstall` gate, Task 3.1, depends on this); `--purge-data` deletes `logs/` (the `.clavity` purge is added in Task 4.1).

- [ ] **Step 2–4:** implement, run (PASS), commit — `feat(clavity-dotnet): clavity-ls uninstall --agent all (non-zero on failure for uninstall gate)`.

### Task 2.4: `--mcp` holds `Global\ClavityMcpRunning` mutex

**Files:**
- Modify: `src/Clavity.Cli/Program.cs` (--mcp block)

- [ ] **Step 1: Hold the named mutex for the host lifetime.** At the top of the `--mcp` block, before building the host:
```csharp
    using var liveSessionMutex = new System.Threading.Mutex(initiallyOwned: true, @"Local\ClavityMcpRunning", out _);
```
(The installer's `PrepareToInstall` detects this held mutex — Component B/D — without WMI.)

- [ ] **Step 2: Build + smoke** — `dotnet build -c Release`; manually run `clavity-ls --mcp` and confirm a second `Mutex.OpenExisting(@"Global\ClavityMcpRunning")` from another shell succeeds. Document in the spike doc; no automated test (cross-process).

- [ ] **Step 3: Commit** — `feat(clavity-dotnet): --mcp holds Global\ClavityMcpRunning for installer live-session detection`.

---

## Phase 3 — Packaging (Inno installer + chooser + CI release)

No target files exist yet; authored from the verified `aidesktop` references. Spike-contingent values are flagged. Inno/PowerShell are smoke-tested in CI (Task 3.4), not unit-TDD'd.

### Task 3.1: `installer/clavity-dotnet.iss`

**Files:**
- Create: `installer/clavity-dotnet.iss`

- [ ] **Step 1: Author the script** modeled on `aidesktop/installer/flaui-mcp.iss`, with clavity-specific `[Code]`:
  - `[Setup]`: `AppName=clavity-dotnet`, dedicated `AppId={{<NEW-GUID>}}`, `DefaultDirName={localappdata}\Programs\clavity-dotnet`, `PrivilegesRequired=lowest`, `ArchitecturesAllowed=x64compatible`, `OutputDir=..\dist`, `OutputBaseFilename=clavity-dotnet-setup`, `ChangesEnvironment=yes`, **`SetupMutex=ClavitySetupMutex`** (identical in the classic .iss — blocks concurrent installers).
  - `[Files]`: `..\publish\clavity-ls.exe` → `{app}`; the bundled `..\plugins\clavity-dotnet\*` → `{app}\plugin\` (recursesubdirs); the optional plugins `..\plugins\agy-autotrain\*` and `..\plugins\commonmemory\*` → `{app}\optional-plugins\<name>\` (Phase 4 ticks install them).
  - `[Tasks]`: `addtopath` (checkedonce); Phase 4 adds `install-agy-autotrain` + `install-commonmemory` (default off).
  - `[Registry]`: per-user PATH **append** via `NeedsAddPath` (verbatim from flaui-mcp.iss) — append, never prepend (security §PATH).
  - `[Run]` + exit-code check: run `{app}\clavity-ls.exe install --agent all --plugin "{app}\plugin"` and **check its exit code in `[Code]` via `Exec`** (UX "visible install-step failure"), not fire-and-forget, so a failed plugin/MCP registration shows an error + log path rather than false "Success".
  - `[Code]`:
    - `InitializeSetup()` — mutual-exclusion refusal (Component E): detect (a) the OTHER variant's `HKCU\…\Uninstall\clavity-classic` key AND (b) a cargo-classic `clavity.exe` on PATH distinct from `clavity-ls` and/or classic skills in the agent dirs. On hit: `MsgBox` printing the **exact path** of the offending binary + how to remove it (UX "actionable exclusion message"), then `Result := False`.
    - `PrepareToInstall()` — if `Local\ClavityMcpRunning` is held, abort with *"close your active Claude pairing session first."* Do NOT taskkill a live `--mcp`.
    - `InitializeUninstall()` — run `clavity-ls uninstall --agent all` via `Exec`; **if non-zero, `Result := False`** to cancel before any file deletion (Component B; `[UninstallRun]` cannot abort). `--force`/second-confirm escape. Host the purge prompt.
    - `CurUninstallStepChanged(usPostUninstall)` — `RemoveFromUserPath('{app}')` (verbatim from flaui-mcp.iss).
  - `InfoAfterFile` / final message: *"Open a terminal and run `clavity-ls start C:\path\to\project`."* (UX "next-step prompt").

- [ ] **Step 2: Build locally if ISCC present**

Run (if Inno installed): `ISCC.exe installer/clavity-dotnet.iss` → produces `dist/clavity-dotnet-setup.exe`. Otherwise rely on CI (Task 3.4).

- [ ] **Step 3: Commit** — `feat(packaging): clavity-dotnet Inno Setup installer`.

### Task 3.2: `install/clavity-install.ps1` (thin chooser)

**Files:**
- Create: `install/clavity-install.ps1`, `install/clavity-install.Tests.ps1`

- [ ] **Step 1: Author the chooser** modeled on `aidesktop/dist/install.ps1`, adding:
  - Prompt `classic` / `dotnet`.
  - **Dual mutual-exclusion pre-check** (Component A/E): read `HKCU\…\Uninstall\clavity-classic` / `…\clavity-dotnet` AND probe for a cargo `clavity.exe`; warn+exit before download if the other variant is present.
  - Resolve the GitHub Release (`-Version latest` default; pinned tag otherwise), find asset `clavity-<variant>-setup.exe`.
  - **SHA-256 verification (security §release-asset integrity — D2 RESOLVED: companion-asset):** download the CI-published companion `clavity-<variant>-setup.exe.sha256` from the SAME release, then download the exe, `Get-FileHash -Algorithm SHA256`, **abort on mismatch before running**. (Threat model: guards partial/corrupt downloads + a single swapped asset; a fully compromised Release could rewrite both, so integrity ultimately rests on the immutable pinned tag + GitHub/TLS trust — documented, accepted.) ⇒ Task 3.3 CI MUST emit the `.sha256` companion asset.
  - Run interactive by default; `-Silent` → `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART`.
  - Docs note: "run in **PowerShell**, not cmd.exe" (UX "two entry paths").

- [ ] **Step 2: Pester-test the registry pre-check + asset resolution** (mock the GitHub API + registry), per spec Testing. Run: `Invoke-Pester install/clavity-install.Tests.ps1`.

- [ ] **Step 3: Commit** — `feat(packaging): thin chooser one-liner with dual exclusion pre-check + SHA-256 verify`.

### Task 3.3: GitHub Release CI workflow

**Files:**
- Create: `.github/workflows/release-clavity-dotnet.yml`

- [ ] **Step 1: Author the workflow** (windows runner): on a version tag — `dotnet publish src/Clavity.Cli -c Release -r win-x64` with the single-file flags Spike 0.3 confirmed → `publish/clavity-ls.exe`; `ISCC.exe installer/clavity-dotnet.iss` → `dist/clavity-dotnet-setup.exe`; compute its SHA-256 and write it to `dist/clavity-dotnet-setup.exe.sha256`; **publish BOTH the setup exe AND the `.sha256` companion as Release assets** (D2 — `install.ps1` downloads+verifies the companion). **No signing** (owner decision — ship unsigned).

- [ ] **Step 2: Commit** — `ci(packaging): build + publish clavity-dotnet-setup.exe as a Release asset`.

### Task 3.4: Inno silent install/uninstall smoke in CI

**Files:**
- Modify: `.github/workflows/release-clavity-dotnet.yml` (or a separate `ci-installer.yml`)

- [ ] **Step 1: Add a CI job** that, on a Windows runner, builds the .iss, runs `/VERYSILENT` install then uninstall, and asserts (spec Testing): files placed under `{app}`, PATH entry added then removed, Add/Remove Programs key present then gone, and mutual-exclusion refusal when a fake "other variant" uninstall key is seeded in `HKCU`.

- [ ] **Step 2: Commit** — `ci(packaging): silent install/uninstall smoke + exclusion-refusal assertion`.

---

## Phase 4 — Data lifecycle + optional add-on wiring

### Task 4.1: Extend `--purge-data` to delete `%USERPROFILE%\.clavity`

**Files:**
- Modify: `src/Clavity.Ls/Install/CliRouter.cs`
- Test: `tests/Clavity.Ls.Tests/Install/CliRouterTests.cs`

- [ ] **Step 1: Failing test** — `uninstall --purge-data` deletes BOTH `logs/` and `%USERPROFILE%\.clavity` (golden-header data); plain `uninstall` PRESERVES `.clavity` (spec data-lifecycle: "Normal uninstall PRESERVES it"). Use a `CLAVITY_DATA_DIR`-style override so the test never touches the real profile (mirror aidesktop's `FLAUI_MCP_DATA_DIR`).
- [ ] **Step 2–4:** implement, run (PASS), commit — `feat(clavity-dotnet): --purge-data also removes ~/.clavity (golden-header data)`.

### Task 4.2: Add-on `[Tasks]` checkboxes + install-from-staging + `.backup` rename + upgrade pre-populate

**Files:**
- Modify: `installer/clavity-dotnet.iss`

- [ ] **Step 1: Add two default-OFF `[Tasks]`** with plain-English value-driven labels (spec UX): `install-agy-autotrain` — *"Install agy-autotrain — lets the AI permanently learn your project's rules and stop repeating mistakes"*; `install-commonmemory` — *"Install commonmemory — a shared notebook so Claude and agy share facts."*

- [ ] **Step 2: Ticked task installs the bundled plugin from `{app}\optional-plugins\<name>`** via the post-install step (extend the `[Run]`/`Exec` to pass the selected optional plugins to `clavity-ls install`). Uninstall removes any installed add-on.

- [ ] **Step 3: Uninstalling the autotrain add-on RENAMES `golden-header.md` → `golden-header.md.backup`** (spec data-lifecycle "zombie header" fix) so the binary stops injecting frozen wisdom; `.backup` does NOT auto-restore on reinstall (security §.backup). Implement in `[Code]` (or a small `clavity-ls` helper verb if cleaner) at add-on-uninstall time.

- [ ] **Step 4: Upgrade pre-populates the add-on checkboxes from DETECTED state** (spec data-lifecycle): on re-run, default each `[Tasks]` checkbox to checked iff that add-on is already installed, so a naive "Next" does not silently uninstall it. Use `[Code]` (`InitializeWizard` + a `Check:` reading the installed-plugin state).

- [ ] **Step 5: Commit** — `feat(packaging): opt-in add-on checkboxes + .backup rename + upgrade-state pre-populate`.

### Task 4.3: Final full-suite gate + holistic review

- [ ] **Step 1:** `dotnet build -c Release` (expect 8 projects, 0/0); `dotnet test --filter "Category!=LiveAgy"` (all green); working tree clean.
- [ ] **Step 2:** Confirm spec coverage: injection both-halves (binary read + curate-commit write), driving merge (no driving content left in autotrain), optionality (opt-out = working core), data lifecycle. Record completion in the durable execution index.

---

## Defined follow-ons (NOT built in this plan)

- **Task 7.1 — clavity-classic Inno installer** (the 7-step setup wrapped into `[Run]`: agentmemory MCP, `GEMINI.md` doorbell rule, `tmux.conf`). Slots into the same chooser. Defined in install-arch spec "Follow-on."
- **Task 7.2 — `clavity-classic-setup.exe` Release CI.**
- **Task 7.3 — Rust `clavity` binary golden-header injection (classic).** The Rust source is **off this branch**; mirror `GoldenHeader` (resolve `%USERPROFILE%\.clavity\golden-header.md` via `dirs::home_dir`, read+cap+prepend in `clavity ask`, `clavity curate-commit`). MUST land before classic ships via installer, else classic loses injection when `driving-agy` is gone.
- **Task 7.4 — Tamper-detection warning** (compare `golden-header.md` hash to the `.sha256` sidecar at read-time; LOUD plain-English warning on external change; subtle active-marker otherwise). Security §HIGH; staged after the injection MVP.
- **Task 7.5 — Per-agent skill scoping VERIFY** (whether the dual-plugin format scopes `clavity-ls-driving` to Claude and `clavity-ls-pairing` to agy; else rely on contextual invocation + document). UX §MEDIUM-VERIFY.
- **Task 7.6 — Agent plugin auto-update skew VERIFY** (confirm Claude/agy do not auto-update a locally path-installed plugin away from the version-pinned `{app}` exe). install-arch Risks.
- **NativeAOT** — stretch goal only; ruled infeasible for now by the gRPC/protobuf/MCP reflection stack (feasibility round 5).

**Out of scope (decided 2026-06-29):** a continuous .NET **build/test** CI workflow for this branch. CI here is
**release-only** (Tasks 3.3/3.4 build + publish the version-pinned artifacts). The .NET build/test gate stays
LOCAL (`dotnet build -c Release` + `dotnet test --filter "Category!=LiveAgy"`), matching how this increment has
been validated; the existing `.github/workflows/ci.yml` remains Rust/`main`-only. (User decision — do NOT add a
`ci-dotnet.yml`.)

---

## Review fixes — folded from agy 3-lens audit (2026-06-29)

Three rotating-lens AGY-AFTER rounds (correctness req-djld9dcdoxa0 · feasibility req-djldawg5j278 ·
security req-djldcby46ckk). All 15 findings were assessed (not rubber-stamped); the clean fixes below are
BINDING on the cited task. Two spec-touching items are PENDING USER (see end).

**Correctness / sequencing (round 1):**
- **F1 (Task 1.5) — classic injection regression.** Do NOT add the "injection is automatic — do not prepend"
  note to the **classic** `clavity-driving` in this plan: classic's binary injection is the off-branch
  Task 7.3, so the note would strand classic with no injection. In Phase 1, the auto-inject note + the
  curate-commit repoint are **dotnet-only**; classic keeps its current manual-prepend skill instruction
  until Task 7.3 lands. The anti-misfire protocol MERGE (pure markdown) still applies to BOTH variants.
- **F2 (Task 1.6) — classic curate-commit not yet real.** The `clavity curate-commit` (Rust) verb does not
  exist until Task 7.3. So Task 1.6 repoints `agy-curate` to `clavity-ls curate-commit` for the **dotnet**
  variant only; the classic branch of agy-curate keeps the raw-file-write instruction as a bridge until 7.3.
- **F4 (Task 1.5) — opt-out UX fallback (spec UX §graceful-opt-out).** BOTH core driving skills MUST include:
  *"Permanent learning needs the agy-autotrain add-on — re-run the clavity installer and tick it,"* shown when
  the user asks Claude to permanently remember a rule and no `agy-curate` is present.
- **F5 (Tasks 1.4/1.6) — curate-commit must NOT take content as a shell arg.** A multi-line markdown header
  blows past shell quoting + command-line length limits. `curate-commit` reads content from **stdin** (or a
  `--file <path>` arg); agy-curate PIPES the compiled header via stdin. The `args[1]` content form is dropped.

**Feasibility / Windows / test-realism (round 2):**
- **F7 (Task 1.2) — sidecar non-atomicity.** Write the `.sha256` sidecar BEFORE moving the header into place,
  and (Task 7.4) treat a missing/mismatched sidecar conservatively (recompute, do not alarm) so a crash
  mid-commit can't manufacture a false tamper alert.
- **F8 (Task 1.4) — no process-wide env mutation in tests.** `CliVerbs.CurateCommit` takes the **resolved
  path** (or a path-resolver `Func`) as a parameter; `Program.cs` resolves it from `CLAVITY_GOLDEN_HEADER`.
  Tests pass the path directly — they never call `Environment.SetEnvironmentVariable` (xUnit parallel-safe).
- **F9 (Task 4.2 + Task 2.2) — Inno cannot know real install state.** `{app}\optional-plugins` existence is a
  false proxy (it is always present — staging). Add a `clavity-ls is-installed <plugin>` verb (Task 2.2) that
  queries the agent; Inno `InitializeWizard` `Exec`s it and reads the exit code to set the upgrade checkbox.
- **F10 (Task 1.4) — top-level return.** MANDATORY (not "if the compiler objects"): convert every bare
  `return;` in `Program.cs` to `return 0;` and end the file with `return 0;`, so `Main` infers `int`.

**Security / supply-chain / contract (round 3):**
- **F12 (Task 1.4) — bounded stdin read.** Read stdin with a hard 16 KB ceiling (reject on overflow); never
  `ReadToEnd()` unbounded (OOM DoS).
- **F13 (Task 1.2) — over-cap is LOUD, absent is SILENT.** `TryRead` must distinguish: absent/empty → silent
  no-op; over-cap (or, in 7.4, tamper-mismatch) → return null AND emit a visible warning, so a user whose
  17 KB hand-edit deactivated injection is told why. (Split the return into a small result or a caller-side
  warn hook; the size-cap semantics then MATCH the producer, which throws on over-cap commit.)
- **F14 (Task 7.4) — state the sidecar's real strength.** The `.sha256` sidecar (same dir, same perms) defends
  against accidental corruption / naive hand-edits ONLY — a same-user adversary rewrites both. This is
  CONSISTENT with the spec's accepted "same-user execution = game over" model; Task 7.4 must SAY so and not
  oversell tamper resistance (DPAPI/signing is out of scope for the accepted threat model). The "subtle active
  marker" (spec security) lives here too — a small prefix, NOT a per-ask banner.
- **F15 (Task 3.1) — uninstaller must not brick.** `InitializeUninstall` checks
  `FileExists({app}\clavity-ls.exe)` FIRST; if the exe is gone (AV/manual delete), fail-OPEN (`Result := True`)
  so Add/Remove Programs can still clean the directory — only run the abort-on-nonzero `Exec` gate when the
  exe exists.

**RESOLVED USER decisions (2026-06-29):**
- **D1 — mutex scope = `Local\ClavityMcpRunning`** (deviation from install-arch Component B/D's `Global\`,
  user-approved). Better-scoped to the user logon session under `PrivilegesRequired=lowest`; avoids any
  cross-session ACL risk. Folded into Task 2.4 + Task 3.1 `PrepareToInstall`.
- **D2 — release-hash pin = companion `.sha256` asset** (resolves the spec's impossible "hard-code the hash at
  the tag" — CI computes the hash after tagging). CI emits `clavity-<variant>-setup.exe.sha256`; `install.ps1`
  downloads + verifies it. Accepted threat-model limit: a fully compromised Release rewrites both → integrity
  rests on the immutable pinned tag + GitHub/TLS trust (documented). Folded into Tasks 3.2 + 3.3.

## Self-review notes (author)

- **Spec coverage:** install-arch Components A–E → Tasks 3.2, 3.1, 1.7, 2.2/2.3, 3.1(InitializeSetup). product-structure Refactors 1–5 → Tasks 1.2/1.3/1.4 (injection+curate-commit), 1.5 (driving merge), 1.6 (strip autotrain), 4.2 (checkboxes), 1.3 (dotnet injection point). Security/UX/data-lifecycle → Tasks 1.2 (cap), 3.1/3.2 (signing-unsigned, SHA-256, exclusion message, visible failure), 4.1/4.2 (purge, .backup, upgrade). Tamper-detection deferred to 7.4 (explicit).
- **Type consistency:** `GoldenHeader.{ResolvePath,TryRead,Apply,Commit,MaxBytes,PathVar}` and `AgyViewOptions.GoldenHeaderPath` are used identically across Tasks 1.2/1.3/1.4/1.6. `CliRouter.{IsInstallerVerb,Run}` matches the aidesktop signature reused in Tasks 2.2/2.3/4.1.
- **Plan-discipline:** every Phase 0–2 code block cites a verified file; Phase 3 carries no fabricated line numbers (new files, aidesktop-patterned); `⟦SPIKE n⟧` marks the values that the gating spikes must supply before that step is executable.
