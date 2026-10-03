# Sweep Branch 18 - Linux visible agy (ROADMAP sections 60 + 62) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On Linux, `clavity-ls start <folder>` opens agy in a terminal TAB the user can see (or, when no terminal can
be opened, tells them exactly what to run), agy publishes its endpoint from a pairing doc that works under bash, and
nothing on Windows changes.

**Architecture:** `start` keeps the Windows Terminal path untouched. On every other OS it writes a per-session POSIX
script that claims a per-session claim file atomically and then `exec`s agy with the same `--log-file`,
`--dangerously-skip-permissions` and `-i <pairing doc>` as Windows. A terminal ladder (`PosixAgyTab`) opens that
script: `CLAVITY_TERMINAL`, then the terminal the user is running in (parent-process walk, then env markers) as a tab,
then `xdg-terminal-exec`, `x-terminal-emulator -e`, then the other known tab verbs. Success is the claim file
appearing, never an exit code. With no display, or when nothing claims within 5 s, `start` prints a fallback and
exits before Claude starts; the user runs `clavity-ls agy <folder>`, which runs agy in place and prints
`clavity-ls start <folder> --attach <session-id>` for a second terminal.

**Tech Stack:** C# / .NET 10 (`clavity-dotnet/src/Clavity.Ls`, `src/Clavity.Cli`), xUnit (`tests/Clavity.Ls.Tests`),
Pester 6 + Git Bash (`scripts/tests`), POSIX sh.

---

## Provenance (read before executing)

- **Design:** owner-adopted after AGY-FIRST R1-R3 (cascade `f2cdbc7a`): `.clavity/seams/linux-agy-tab.md`, `-r2.md`,
  `-r3.md`, `-r3b.md`; decisions and every measurement below are in `.clavity/scratch/linux-agy-tab/r1-summary.md`.
  No tmux anywhere in clavity-dotnet (owner: tmux/psmux is clavity-classic's transport).
- **Measured on the owner's VM (Ubuntu 26.04 MATE over xrdp, agy 1.2.14), 2026-10-02:**
  - `mate-terminal --tab -e "<script>"` and `x-terminal-emulator -e <script>`: rc 0, the script runs in 80-130 ms
    (monotonic clock, 10 ms resolution, load uncontrolled). A launch whose script does not exist: rc 0 EVERY time and
    nothing runs - so an exit code is not success. No DISPLAY: rc 1 in 30 ms.
  - `( set -C; : > F ) 2>/dev/null` succeeds once and is refused the second time, under dash (`/bin/sh`) and bash.
  - Parent walk from agy inside a mate-terminal tab: `agy -> mate-terminal -> mate-panel -> mate-session`
    (`/proc/<pid>/comm`). The tab's only terminal marker is `VTE_VERSION=8400` (shared by every VTE terminal).
  - E2E with a generated script + mate-terminal tab + `agy -i <draft POSIX doc>`: agy first ran the publish line
    through a third-party MCP shell tool, whose processes lack `ANTIGRAVITY_CSRF_TOKEN` / `ANTIGRAVITY_LS_ADDRESS`,
    and published `{"csrf":"","addr":""}`; it then stopped on a FOLDER-TRUST prompt (despite
    `--dangerously-skip-permissions`); after the owner approved it, agy re-ran the line in its BUILT-IN bash tool and
    published a valid endpoint. So: agy's built-in shell is bash on Linux (settles section 60's open question), the
    publish line must refuse empty values, and pairing on a fresh folder waits for a human in the agy tab.
- **Already correct, no change:** `AgyEndpoint.TryRead` returns null for empty `csrf` / `addr`
  (`clavity-dotnet/src/Clavity.Ls/AgyEndpoint.cs:24`, pinned by
  `AgyEndpointTests.TryRead_returns_null_when_csrf_or_addr_missing_or_portless`). An unpublished endpoint makes
  `AgyView.ConnectPreferringEndpoint` (`AgyView.cs:568-577`) fall back to cli.log discovery with no token, the LS
  refuses, and the user sees the `auth_failed` hint - which Task 7 extends.
- **CI runs every .NET and Pester suite on `windows-latest`** (`.github/workflows/ci-dotnet.yml:16`,
  `ci-scripts.yml:67`). Nothing in CI executes the Linux launch; Task 9 does, on the VM.

## File structure

| File | Responsibility |
|---|---|
| Create `clavity-dotnet/src/Clavity.Ls/SessionPaths.cs` | The per-session file names every verb derives from a session id |
| Create `clavity-dotnet/src/Clavity.Ls/StartArgs.cs` | Parse `start [folder] [--attach <id>] [claude-args...]` |
| Modify `clavity-dotnet/src/Clavity.Ls/Launcher.cs` | Extract `BuildAgyEnv`; add `BuildPosixScript` + `ShQuote` |
| Create `clavity-dotnet/src/Clavity.Ls/PosixAgyTab.cs` | Terminal ladder, parent walk, claim handling, messages, real deps |
| Modify `clavity-dotnet/src/Clavity.Ls/AgyEnvironment.cs` | Gains `TryReadProjectId` (moved from Program.cs) |
| Modify `clavity-dotnet/src/Clavity.Cli/Program.cs` | `start` uses the above; new `agy` verb; usage line |
| Modify `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs` | `auth_failed` hint names a pending prompt in the agy tab |
| Modify `clavity-dotnet/pairing/agy-pairing-INSTALL.md` | pwsh + POSIX publish lines, both refusing empty values |
| Create `scripts/tests/pairing-doc.Tests.ps1` | Runs both publish lines extracted from the doc |
| Tests in `clavity-dotnet/tests/Clavity.Ls.Tests/` | `SessionPathsTests`, `StartArgsTests`, `LauncherTests` (+), `PosixScriptRunTests`, `PosixAgyTabTests`, `ChannelDownTests` (+) |
| Docs | both `plugin/knowledge/agy-assumptions.md`, three `CLAUDE.md`, `clavity-dotnet/README.md`, `clavity-dotnet/ROADMAP.md` |

Commands used throughout (from `clavity-dotnet/`): build `dotnet build`; unit tests
`dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~<Class>"`. **`dotnet test --filter` exits 0 when
nothing matches - read the `Passed:` count every time.**

---

### Task 1: `SessionPaths` - one file layout for every verb

**Files:** Create `clavity-dotnet/src/Clavity.Ls/SessionPaths.cs`; create
`clavity-dotnet/tests/Clavity.Ls.Tests/SessionPathsTests.cs`; modify `clavity-dotnet/src/Clavity.Cli/Program.cs:95-108`.

- [ ] **Step 1: Write the failing tests** - `SessionPathsTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class SessionPathsTests
{
    private const string Sid = "11111111-2222-3333-4444-555555555555";

    [Fact]
    public void For_derives_every_file_from_the_profile_and_the_session_id()
    {
        var home = Path.Combine("x", "home");
        var p = SessionPaths.For(home, Sid);

        Assert.Equal(Sid, p.SessionId);
        // The log and endpoint names are the ones `start` already used before this branch - unchanged on Windows.
        Assert.Equal(Path.Combine(home, ".gemini", "antigravity-cli", "logs", $"clavity-{Sid}.log"), p.AgyLog);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-endpoint.{Sid}.json"), p.Endpoint);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-session.{Sid}.sh"), p.AgyScript);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-session.{Sid}.claim"), p.Claim);
    }

    [Theory]
    [InlineData(Sid, true)]
    [InlineData("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE", true)]
    [InlineData("11111111222233334444555555555555", false)]   // GUID "N" form: not what start prints
    [InlineData("../../etc/passwd", false)]
    [InlineData("", false)]
    [InlineData(null, false)]
    public void IsValidSessionId_accepts_only_the_GUID_D_form(string? id, bool expected)
        => Assert.Equal(expected, SessionPaths.IsValidSessionId(id));
}
```

- [ ] **Step 2: Run, expect a compile failure** - `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~SessionPathsTests"` -> error CS0103 / CS0246 `SessionPaths`.

- [ ] **Step 3: Implement** - `SessionPaths.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>The per-session files every verb that pairs Claude with agy agrees on: <c>start</c> (launches both),
/// <c>start --attach</c> (Claude only) and <c>agy</c> (agy only, Linux/macOS). All of them derive the names from the
/// session id alone, so two commands run in two different terminals still meet (ROADMAP section 62).</summary>
public sealed record SessionPaths(string SessionId, string AgyLog, string Endpoint, string AgyScript, string Claim)
{
    public static SessionPaths For(string userProfileDir, string sessionId)
    {
        var logs = Path.Combine(userProfileDir, ".gemini", "antigravity-cli", "logs");
        var clavity = Path.Combine(userProfileDir, ".clavity");
        return new SessionPaths(
            sessionId,
            AgyLog: Path.Combine(logs, $"clavity-{sessionId}.log"),
            Endpoint: Path.Combine(clavity, $"agy-endpoint.{sessionId}.json"),
            AgyScript: Path.Combine(clavity, $"agy-session.{sessionId}.sh"),
            Claim: Path.Combine(clavity, $"agy-session.{sessionId}.claim"));
    }

    /// <summary>A session id is the GUID "D" form <c>start</c> and <c>agy</c> mint. Anything else is refused before it
    /// becomes part of a file name: an id typed into <c>--attach</c> must not be able to name another path.</summary>
    public static bool IsValidSessionId(string? id) => id is not null && Guid.TryParseExact(id, "D", out _);
}
```

- [ ] **Step 4: Run the tests** - same command -> `Passed: 7` (1 Fact + 6 InlineData rows), `Failed: 0`.

- [ ] **Step 5: Use it in `start` without changing behaviour.** In `Program.cs`, replace lines 95-108 (from
  `var agyHome = Path.Combine(` through the `agyEndpointPath` assignment) with:

```csharp
    var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    var agyHome = Path.Combine(userProfile, ".gemini", "antigravity-cli");

    var sessionId = Guid.NewGuid().ToString("D");
    // Per-session files (SessionPaths): the agy log, and the pairing rendezvous keyed by session so two concurrent
    // clavity sessions cannot clobber one another's endpoint (both the agy side and clavity-ls get this exact path
    // via CLAVITY_AGY_ENDPOINT).
    var paths = SessionPaths.For(userProfile, sessionId);
    var logsDir = Path.GetDirectoryName(paths.AgyLog)!;
    Directory.CreateDirectory(logsDir); // idempotent + concurrency-safe (spec §11a).
    LogRetention.Prune(logsDir, LogRetention.DefaultMaxAge, DateTime.UtcNow);
    var agyLogPath = paths.AgyLog;
    var agyEndpointPath = paths.Endpoint;
```

  Before editing, open `Program.cs:95-108` and confirm it still reads `var agyHome = Path.Combine(` ... `$"agy-endpoint.{sessionId}.json");`.
  If it differs, STOP and report `STATE_MISMATCH`.

- [ ] **Step 6: Build and run the whole unit suite** - `dotnet build` (0 errors) then `dotnet test tests/Clavity.Ls.Tests` -> previous count + 7, `Failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/SessionPaths.cs clavity-dotnet/tests/Clavity.Ls.Tests/SessionPathsTests.cs clavity-dotnet/src/Clavity.Cli/Program.cs
git commit -m "refactor(start): derive every per-session file from SessionPaths (sections 60+62)"
```

---

### Task 2: `StartArgs` - parse `--attach <session-id>`

**Files:** Create `clavity-dotnet/src/Clavity.Ls/StartArgs.cs`, `clavity-dotnet/tests/Clavity.Ls.Tests/StartArgsTests.cs`.
(Program.cs wiring is Task 5.)

- [ ] **Step 1: Write the failing tests** - `StartArgsTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class StartArgsTests
{
    private const string Sid = "11111111-2222-3333-4444-555555555555";
    private static readonly string Cwd = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "cwd"));
    private static readonly string Repo = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "repo"));

    [Fact]
    public void A_bare_folder_is_the_folder_and_nothing_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo }, Cwd);
        Assert.Equal(Repo, a.Folder);
        Assert.Null(a.AttachSessionId);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Without_a_folder_the_current_directory_is_used_and_dash_args_reach_Claude()
    {
        var a = StartArgs.Parse(new[] { "--model", "opus" }, Cwd);
        Assert.Equal(Cwd, a.Folder);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_directly_after_the_folder_is_consumed_and_the_rest_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", Sid, "--model", "opus" }, Cwd);
        Assert.Equal(Repo, a.Folder);
        Assert.Equal(Sid, a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_without_a_folder_uses_the_current_directory()
    {
        var a = StartArgs.Parse(new[] { "--attach", Sid }, Cwd);
        Assert.Equal(Cwd, a.Folder);
        Assert.Equal(Sid, a.AttachSessionId);
    }

    [Fact]
    public void Attach_after_a_Claude_argument_is_NOT_ours_and_reaches_Claude_untouched()
    {
        var a = StartArgs.Parse(new[] { Repo, "--model", "opus", "--attach", Sid }, Cwd);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus", "--attach", Sid }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_with_no_id_is_refused_naming_the_flag()
    {
        var ex = Assert.Throws<ArgumentException>(() => StartArgs.Parse(new[] { Repo, "--attach" }, Cwd));
        Assert.Contains("--attach", ex.Message);
    }

    [Theory]
    [InlineData("../../etc")]
    [InlineData("11111111222233334444555555555555")]
    [InlineData("--model")]
    public void Attach_with_a_malformed_id_is_refused_quoting_it(string bad)
    {
        var ex = Assert.Throws<ArgumentException>(() => StartArgs.Parse(new[] { Repo, "--attach", bad }, Cwd));
        Assert.Contains($"'{bad}'", ex.Message);
    }
}
```

- [ ] **Step 2: Run, expect a compile failure** - `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~StartArgsTests"`.

- [ ] **Step 3: Implement** - `StartArgs.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>Parsed <c>clavity-ls start [folder] [--attach &lt;session-id&gt;] [claude-args...]</c>.</summary>
public sealed record StartArgs(string Folder, string? AttachSessionId, string[] ClaudeArgs)
{
    public const string AttachFlag = "--attach";

    /// <summary>The folder is the first argument unless it starts with '-'. <c>--attach &lt;id&gt;</c> is ours only
    /// DIRECTLY after it (or first, with no folder), so every later argument still reaches Claude untouched. Throws
    /// <see cref="ArgumentException"/> for a missing or malformed id.</summary>
    public static StartArgs Parse(string[] rest, string currentDirectory)
    {
        var i = 0;
        string folder;
        if (rest.Length > 0 && !rest[0].StartsWith('-'))
        {
            folder = Path.GetFullPath(rest[0]);
            i = 1;
        }
        else
        {
            folder = currentDirectory;
        }

        string? attach = null;
        if (i < rest.Length && rest[i] == AttachFlag)
        {
            if (i + 1 >= rest.Length)
                throw new ArgumentException($"{AttachFlag} needs the session id that `clavity-ls agy` printed.");
            attach = rest[i + 1];
            if (!SessionPaths.IsValidSessionId(attach))
                throw new ArgumentException(
                    $"{AttachFlag} '{attach}' is not a session id - use the one `clavity-ls agy` printed.");
            i += 2;
        }

        return new StartArgs(folder, attach, rest[i..]);
    }
}
```

- [ ] **Step 4: Run** - same command -> `Passed: 9`, `Failed: 0`.

- [ ] **Step 5: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/StartArgs.cs clavity-dotnet/tests/Clavity.Ls.Tests/StartArgsTests.cs
git commit -m "feat(start): parse --attach <session-id> (section 62)"
```

---

### Task 3: `Launcher.BuildPosixScript` - the generated agy script

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/Launcher.cs` (lines 57-66 env build; add methods after
`BuildAgyTabScript`, line 117); tests in `clavity-dotnet/tests/Clavity.Ls.Tests/LauncherTests.cs` and new
`clavity-dotnet/tests/Clavity.Ls.Tests/PosixScriptRunTests.cs`.

**Oracle:** the exact script text below, and the run test - the FIRST run claims and execs agy once, a SECOND run
exits 0 without starting another agy. The existing `LauncherTests` must stay green unchanged (the Windows script is
byte-for-byte what it was).

- [ ] **Step 1: Write the failing tests** - append to `LauncherTests` (inside the class, after the last test):

```csharp
    private static LaunchOptions PosixOpts(string? projectId = "proj-123", string folder = "/home/u/repo") => new()
    {
        Folder = folder,
        SessionId = "11111111-2222-3333-4444-555555555555",
        ProjectId = projectId,
        AgyLogFilePath = "/home/u/.gemini/antigravity-cli/logs/clavity-11111111-2222-3333-4444-555555555555.log",
        AgyEndpointFilePath = "/home/u/.clavity/agy-endpoint.11111111-2222-3333-4444-555555555555.json",
        SkipPermissions = true,
        AgyInstallDocPath = "/home/u/.clavity/agy-pairing-INSTALL.md",
    };

    [Fact]
    public void PosixScript_claims_first_then_exports_the_session_env_and_execs_agy_with_the_pairing_prompt()
    {
        var script = Launcher.BuildPosixScript(PosixOpts(), "/home/u/.clavity/agy-session.S.claim");
        Assert.Equal(
            "#!/bin/sh\n" +
            "# Generated by clavity-ls for session 11111111-2222-3333-4444-555555555555: runs that session's agy.\n" +
            "# Only the copy that creates the claim file runs agy; a second copy (a slower terminal from an earlier\n" +
            "# launch attempt) exits here. The claim file is also what tells clavity-ls the terminal really started.\n" +
            "( set -C; : > '/home/u/.clavity/agy-session.S.claim' ) 2>/dev/null || exit 0\n" +
            "export ANTIGRAVITY_PROJECT_ID='proj-123'\n" +
            "export CLAVITY_AGY_ENDPOINT='/home/u/.clavity/agy-endpoint.11111111-2222-3333-4444-555555555555.json'\n" +
            "cd '/home/u/repo' || { echo 'clavity: cannot enter the session folder.'; sleep 60; exit 1; }\n" +
            "command -v agy >/dev/null 2>&1 || { echo 'clavity: agy is not on PATH in this terminal.'; sleep 60; exit 127; }\n" +
            "exec agy --log-file '/home/u/.gemini/antigravity-cli/logs/clavity-11111111-2222-3333-4444-555555555555.log'" +
            " --dangerously-skip-permissions -i 'Fetch and follow the instructions at /home/u/.clavity/agy-pairing-INSTALL.md'\n",
            script);
    }

    [Fact]
    public void PosixScript_omits_the_project_id_when_absent_and_is_LF_only()
    {
        var script = Launcher.BuildPosixScript(PosixOpts(projectId: null), "/c");
        Assert.DoesNotContain("ANTIGRAVITY_PROJECT_ID", script);
        Assert.DoesNotContain("\r", script);
    }

    [Fact]
    public void ShQuote_escapes_an_embedded_single_quote_the_POSIX_way()
    {
        Assert.Equal("'it'\\''s'", Launcher.ShQuote("it's"));
        Assert.Contains("cd '/home/o'\\''brien' || {", Launcher.BuildPosixScript(PosixOpts(folder: "/home/o'brien"), "/c"));
    }
```

  And create `PosixScriptRunTests.cs`:

```csharp
using System.Diagnostics;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>RUNS the generated script under a real POSIX shell with a fake agy on PATH. On Windows that is Git Bash
/// at its standard path - NOT `bash` from PATH, which resolves to WSL's System32 shim on a dev box and cannot see
/// these Windows paths.</summary>
public sealed class PosixScriptRunTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-posix-" + Guid.NewGuid().ToString("N"));

    public PosixScriptRunTests() => Directory.CreateDirectory(_dir);

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    // Git Bash understands C:/ paths; the generated script quotes whatever the launcher hands it.
    private static string Fwd(string p) => p.Replace('\\', '/');

    private static int RunSh(string script, string binDir)
    {
        ProcessStartInfo psi;
        if (OperatingSystem.IsWindows())
        {
            var bash = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Git", "bin", "bash.exe");
            Assert.True(File.Exists(bash), $"Git Bash is required at {bash}");
            psi = new ProcessStartInfo(bash) { ArgumentList = { "-c", "PATH=\"$(cygpath -u \"$1\"):$PATH\"; exec sh \"$2\"", "_", binDir, Fwd(script) } };
        }
        else
        {
            psi = new ProcessStartInfo("/bin/sh") { ArgumentList = { "-c", "PATH=\"$1:$PATH\"; exec sh \"$2\"", "_", binDir, script } };
        }
        psi.UseShellExecute = false;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        using var p = Process.Start(psi)!;
        p.StandardOutput.ReadToEnd();
        p.StandardError.ReadToEnd();
        Assert.True(p.WaitForExit(30_000), "the script did not finish within 30 s");
        return p.ExitCode;
    }

    [Fact]
    public void The_first_run_claims_and_execs_agy_and_a_second_run_exits_without_starting_another()
    {
        var bin = Directory.CreateDirectory(Path.Combine(_dir, "bin")).FullName;
        var work = Directory.CreateDirectory(Path.Combine(_dir, "work dir")).FullName;   // a space, on purpose
        var record = Fwd(Path.Combine(_dir, "agy-calls.txt"));
        var fakeAgy = Path.Combine(bin, "agy");
        File.WriteAllText(fakeAgy,
            "#!/bin/sh\n" +
            "{ printf 'cwd=%s\\n' \"$PWD\"; for a in \"$@\"; do printf 'arg=%s\\n' \"$a\"; done; " +
            "printf 'endpoint=%s\\n' \"$CLAVITY_AGY_ENDPOINT\"; } >> '" + record + "'\n");
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(fakeAgy, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);

        var claim = Fwd(Path.Combine(_dir, "s.claim"));
        var endpoint = Fwd(Path.Combine(_dir, "ep.json"));
        var doc = Fwd(Path.Combine(_dir, "doc.md"));
        var script = Path.Combine(_dir, "s.sh");
        File.WriteAllText(script, Launcher.BuildPosixScript(new LaunchOptions
        {
            Folder = Fwd(work), SessionId = "sid", AgyLogFilePath = Fwd(Path.Combine(_dir, "agy.log")),
            AgyEndpointFilePath = endpoint, SkipPermissions = true, AgyInstallDocPath = doc,
        }, claim));

        Assert.Equal(0, RunSh(script, bin));
        Assert.Equal(0, RunSh(script, bin));

        var lines = File.ReadAllLines(record);
        // agy started exactly ONCE: the second run lost the claim and exited before exec.
        Assert.Single(lines, l => l.StartsWith("cwd=", StringComparison.Ordinal));
        Assert.EndsWith("/work dir", lines.Single(l => l.StartsWith("cwd=", StringComparison.Ordinal)));
        Assert.Contains("arg=--dangerously-skip-permissions", lines);
        Assert.Contains($"arg=Fetch and follow the instructions at {doc}", lines);
        Assert.Contains($"endpoint={endpoint}", lines);
        Assert.True(File.Exists(claim));
    }
}
```

- [ ] **Step 2: Run, expect compile failures** - `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~LauncherTests|FullyQualifiedName~PosixScriptRunTests"`.

- [ ] **Step 3: Implement.** In `Launcher.cs`, replace the env block at lines 57-63 (from the `// Deterministic order` comment
  through `agyEnv[AgyEnvironment.EndpointPathVar] = options.AgyEndpointFilePath;`) with `var agyEnv = BuildAgyEnv(options);`,
  and add after `BuildAgyTabScript` (before `PwshSingleQuote`):

```csharp
    // Deterministic order (Ordinal) so the emitted scripts are stable for unit tests.
    private static SortedDictionary<string, string> BuildAgyEnv(LaunchOptions options)
    {
        var agyEnv = new SortedDictionary<string, string>(StringComparer.Ordinal);
        if (options.ProjectId is { Length: > 0 } projectId)
            agyEnv["ANTIGRAVITY_PROJECT_ID"] = projectId;
        // agy self-publishes its endpoint HERE (the pairing doc writes to CLAVITY_AGY_ENDPOINT). Per-session, so a
        // second clavity session's agy cannot clobber this one's rendezvous file.
        agyEnv[AgyEnvironment.EndpointPathVar] = options.AgyEndpointFilePath;
        return agyEnv;
    }

    /// <summary>The agy script for Linux/macOS (ROADMAP sections 60 + 62), run by a terminal the ladder opens
    /// (<see cref="PosixAgyTab"/>) or by <c>clavity-ls agy</c>. It first CLAIMS <paramref name="claimPath"/> with
    /// <c>set -C</c> (O_EXCL; measured atomic under dash and bash): only one copy can ever run agy, and the claim
    /// file is the launcher's proof that a terminal really started - an exit code is not (a terminal returns 0 even
    /// when the command it was given does not exist).</summary>
    public static string BuildPosixScript(LaunchOptions options, string claimPath)
    {
        var sb = new StringBuilder();
        sb.Append("#!/bin/sh\n");
        sb.Append("# Generated by clavity-ls for session ").Append(options.SessionId).Append(": runs that session's agy.\n");
        sb.Append("# Only the copy that creates the claim file runs agy; a second copy (a slower terminal from an earlier\n");
        sb.Append("# launch attempt) exits here. The claim file is also what tells clavity-ls the terminal really started.\n");
        sb.Append("( set -C; : > ").Append(ShQuote(claimPath)).Append(" ) 2>/dev/null || exit 0\n");
        foreach (var (key, value) in BuildAgyEnv(options))
            sb.Append("export ").Append(key).Append('=').Append(ShQuote(value)).Append('\n');
        // A failed cd happens AFTER the claim, so clavity-ls already reported success: hold the tab open long enough to
        // read why, instead of closing it in a flash.
        sb.Append("cd ").Append(ShQuote(options.Folder))
          .Append(" || { echo 'clavity: cannot enter the session folder.'; sleep 60; exit 1; }\n");
        sb.Append("command -v agy >/dev/null 2>&1 || { echo 'clavity: agy is not on PATH in this terminal.'; sleep 60; exit 127; }\n");
        sb.Append("exec agy --log-file ").Append(ShQuote(options.AgyLogFilePath));
        if (options.SkipPermissions)
            sb.Append(" --dangerously-skip-permissions");
        if (!string.IsNullOrEmpty(options.AgyInstallDocPath))
            sb.Append(" -i ").Append(ShQuote($"Fetch and follow the instructions at {options.AgyInstallDocPath}"));
        sb.Append('\n');
        return sb.ToString();
    }

    /// <summary>Single-quote a value for a POSIX shell: close the quote, emit an escaped quote, reopen.</summary>
    public static string ShQuote(string value) => "'" + value.Replace("'", "'\\''") + "'";
```

- [ ] **Step 4: Run** - same command -> every `LauncherTests` row green including the 9 existing ones (12 total), and
  `PosixScriptRunTests` 1 passed.

- [ ] **Step 5: Prove the run test is not vacuous.** `git add` the work, then delete the claim line
  (`sb.Append("( set -C; ...`) -> `PosixScriptRunTests` must go RED on the `Assert.Single` (agy started twice) and
  the exact-text Fact must go red; restore with `git checkout -- clavity-dotnet/src/Clavity.Ls/Launcher.cs`, rerun green.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/Launcher.cs clavity-dotnet/tests/Clavity.Ls.Tests/LauncherTests.cs clavity-dotnet/tests/Clavity.Ls.Tests/PosixScriptRunTests.cs
git commit -m "feat(launcher): BuildPosixScript - claim-once POSIX agy script with the pairing prompt (sections 60+62)"
```

---

### Task 4: `PosixAgyTab` - the terminal ladder

**Files:** Create `clavity-dotnet/src/Clavity.Ls/PosixAgyTab.cs`, `clavity-dotnet/tests/Clavity.Ls.Tests/PosixAgyTabTests.cs`.

**Contract (owner-adopted order):** no `DISPLAY` and no `WAYLAND_DISPLAY` -> no candidates. Otherwise:
`CLAVITY_TERMINAL` (run as `/bin/sh -c '<value> "$1"' clavity-terminal <script>`, so it may quote arguments) -> the DETECTED terminal's
tab verb (nearest ancestor whose `comm` starts with a known prefix; else the first known terminal whose env marker is
set) -> `xdg-terminal-exec <script>` -> `x-terminal-emulator -e <script>` -> the remaining known tab terminals in
table order. Each candidate: start it; success = the claim file exists; a non-zero exit -> next candidate at once; 5 s
with no claim -> kill the launcher if it is still running, next candidate. After the last candidate, create the claim
exclusively: created -> return null (caller prints the fallback); already existed -> a late script won -> success.

- [ ] **Step 1: Write the failing tests** - `PosixAgyTabTests.cs`:

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class PosixAgyTabTests
{
    private static readonly SessionPaths P = SessionPaths.For("/home/u", "11111111-2222-3333-4444-555555555555");
    private static Func<string, string?> Env(params (string K, string V)[] vars) =>
        k => vars.FirstOrDefault(v => v.K == k).V;
    private static string[] Names(IEnumerable<TerminalCandidate> c) => c.Select(x => x.Name).ToArray();

    [Fact]
    public void No_display_means_no_candidates_at_all()
        => Assert.Empty(PosixAgyTab.Candidates(Env(), new[] { "mate-terminal" }));

    [Fact]
    public void Wayland_alone_counts_as_a_display()
        => Assert.NotEmpty(PosixAgyTab.Candidates(Env(("WAYLAND_DISPLAY", "wayland-0")), Array.Empty<string>()));

    [Fact]
    public void Order_is_override_then_detected_tab_then_xdg_then_x_terminal_emulator_then_the_rest()
    {
        var c = PosixAgyTab.Candidates(
            Env(("DISPLAY", ":10.0"), (PosixAgyTab.TerminalVar, "kitty --single-instance")),
            new[] { "bash", "mate-terminal", "mate-panel" });
        Assert.Equal(
            new[] { "CLAVITY_TERMINAL", "mate-terminal", "xdg-terminal-exec", "x-terminal-emulator", "gnome-terminal", "konsole", "xfce4-terminal" },
            Names(c));
        // The override is run by /bin/sh with the script as "$1", so quoting in it works as at a prompt.
        Assert.Equal("/bin/sh", c[0].FileName);
        Assert.Equal(new[] { "-c", "kitty --single-instance \"$1\"", "clavity-terminal", "/s/a.sh" },
            PosixAgyTab.ArgumentsFor(c[0], "/s/a.sh"));
    }

    [Fact]
    public void The_NEAREST_matching_ancestor_wins_and_comm_matches_by_prefix()
    {
        // gnome-terminal-server's comm is truncated by the kernel to 15 bytes: "gnome-terminal-".
        var c = PosixAgyTab.Candidates(Env(("DISPLAY", ":0")), new[] { "bash", "gnome-terminal-", "konsole" });
        Assert.Equal("gnome-terminal", c[0].Name);
    }

    [Fact]
    public void With_no_matching_ancestor_an_env_marker_picks_the_tab_terminal()
    {
        var c = PosixAgyTab.Candidates(Env(("DISPLAY", ":0"), ("KONSOLE_VERSION", "230802")), new[] { "tmux: server" });
        Assert.Equal(new[] { "konsole", "xdg-terminal-exec", "x-terminal-emulator", "mate-terminal", "gnome-terminal", "xfce4-terminal" }, Names(c));
    }

    [Fact]
    public void With_nothing_detected_the_order_is_the_round_2_order()
    {
        var c = PosixAgyTab.Candidates(Env(("DISPLAY", ":0")), new[] { "sshd" });
        Assert.Equal(new[] { "xdg-terminal-exec", "x-terminal-emulator", "mate-terminal", "gnome-terminal", "konsole", "xfce4-terminal" }, Names(c));
    }

    [Fact]
    public void A_blank_override_is_ignored()
        => Assert.DoesNotContain("CLAVITY_TERMINAL", Names(PosixAgyTab.Candidates(Env(("DISPLAY", ":0"), (PosixAgyTab.TerminalVar, "   ")), Array.Empty<string>())));

    [Fact]
    public void Mate_terminal_gets_the_script_as_ONE_quoted_string_and_the_others_as_a_last_argument()
    {
        var all = PosixAgyTab.Candidates(Env(("DISPLAY", ":0")), Array.Empty<string>());
        Assert.Equal(new[] { "--tab", "-e", "'/s p/a.sh'" }, PosixAgyTab.ArgumentsFor(all.Single(c => c.Name == "mate-terminal"), "/s p/a.sh"));
        Assert.Equal(new[] { "-e", "/s p/a.sh" }, PosixAgyTab.ArgumentsFor(all.Single(c => c.Name == "x-terminal-emulator"), "/s p/a.sh"));
    }

    // ---- TryOpen, against fakes -------------------------------------------------------------------------------

    private sealed class FakeProc(bool exited, int code) : IStartedProcess
    {
        public bool HasExited { get; set; } = exited;
        public int ExitCode => code;
        public bool Killed { get; private set; }
        public void Kill() { Killed = true; HasExited = true; }
    }

    private sealed class World
    {
        public long Now;
        public readonly HashSet<string> Files = new();
        public readonly List<string> Started = new();
        public bool ExclusiveCreated;
        public Func<LaunchCommand, IStartedProcess> OnStart = _ => new FakeProc(true, 0);

        public PosixAgyTabDeps Deps(params (string K, string V)[] env) => new()
        {
            GetEnv = Env(env.Length == 0 ? new[] { ("DISPLAY", ":0") } : env),
            ParentComms = () => new[] { "sshd" },   // nothing detected: the round-2 order
            Start = cmd => { Started.Add(cmd.FileName); return OnStart(cmd); },
            FileExists = Files.Contains,
            TryCreateExclusive = path => { if (!Files.Add(path)) return false; ExclusiveCreated = true; return true; },
            NowMs = () => Now,
            Sleep = t => Now += (long)t.TotalMilliseconds,
        };
    }

    [Fact]
    public void The_first_terminal_whose_script_claims_wins_and_no_other_is_started()
    {
        var w = new World();
        w.OnStart = cmd => { w.Files.Add(P.Claim); return new FakeProc(true, 0); };
        Assert.Equal("xdg-terminal-exec", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.Equal(new[] { "xdg-terminal-exec" }, w.Started);
    }

    [Fact]
    public void A_terminal_that_is_not_installed_is_skipped()
    {
        var w = new World();
        w.OnStart = cmd => cmd.FileName == "xdg-terminal-exec"
            ? throw new System.ComponentModel.Win32Exception(2)
            : Claim(w);
        Assert.Equal("x-terminal-emulator", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
    }

    private static IStartedProcess Claim(World w) { w.Files.Add(P.Claim); return new FakeProc(true, 0); }

    [Fact]
    public void A_non_zero_exit_moves_on_at_once_without_waiting_out_the_timeout()
    {
        var w = new World();
        w.OnStart = cmd => cmd.FileName == "xdg-terminal-exec" ? new FakeProc(true, 1) : Claim(w);
        Assert.Equal("x-terminal-emulator", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.True(w.Now < 1000, $"waited {w.Now} ms on a launcher that had already failed");
    }

    [Fact]
    public void Exit_zero_without_a_claim_waits_the_timeout_and_a_still_running_launcher_is_killed()
    {
        var w = new World();
        var hung = new FakeProc(false, 0);
        w.OnStart = cmd => cmd.FileName == "xdg-terminal-exec" ? hung : Claim(w);
        Assert.Equal("x-terminal-emulator", PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.True(hung.Killed);
        Assert.True(w.Now >= 5000);
    }

    [Fact]
    public void When_nothing_claims_the_launcher_takes_the_claim_itself_and_reports_failure()
    {
        var w = new World();
        Assert.Null(PosixAgyTab.TryOpen(P, "/repo", w.Deps(), PosixAgyTab.ReadyTimeout));
        Assert.True(w.ExclusiveCreated, "a terminal that opens later must find the claim taken and exit");
        Assert.Equal(6, w.Started.Count);   // every candidate was tried
    }

    [Fact]
    public void A_script_that_claims_after_the_last_timeout_still_counts_as_success()
    {
        var w = new World();
        var deps = w.Deps();
        var lateDeps = new PosixAgyTabDeps
        {
            GetEnv = deps.GetEnv, ParentComms = deps.ParentComms, Start = deps.Start, FileExists = deps.FileExists,
            NowMs = deps.NowMs, Sleep = deps.Sleep,
            TryCreateExclusive = _ => false,   // a late script won the race
        };
        Assert.NotNull(PosixAgyTab.TryOpen(P, "/repo", lateDeps, PosixAgyTab.ReadyTimeout));
    }

    [Fact]
    public void No_display_tries_nothing_and_reports_failure()
    {
        var w = new World();
        Assert.Null(PosixAgyTab.TryOpen(P, "/repo", w.Deps(("HOME", "/home/u")), PosixAgyTab.ReadyTimeout));
        Assert.Empty(w.Started);
    }

    // ---- parent walk, PATH lookup, messages ----------------------------------------------------------------------

    [Theory]
    [InlineData("123 (mate-terminal) S 456 789", 456)]
    [InlineData("123 (a) b) S 9 1", 9)]          // comm may itself contain ") " - count from the LAST ')'
    [InlineData("garbage", null)]
    [InlineData(null, null)]
    public void ParseStatPpid_reads_the_field_after_the_state(string? stat, int? expected)
        => Assert.Equal(expected, PosixAgyTab.ParseStatPpid(stat));

    [Fact]
    public void ReadParentComms_walks_up_to_pid_1_nearest_first()
    {
        var stat = new Dictionary<int, string> { [50] = "50 (clavity-ls) S 40", [40] = "40 (bash) S 30", [30] = "30 (mate-terminal) S 1" };
        var comm = new Dictionary<int, string> { [40] = "bash\n", [30] = "mate-terminal\n" };
        Assert.Equal(new[] { "bash", "mate-terminal" },
            PosixAgyTab.ReadParentComms(50, p => comm.GetValueOrDefault(p), p => stat.GetValueOrDefault(p)));
    }

    [Fact]
    public void ReadParentComms_stops_after_ten_levels()
    {
        // A cycle cannot happen on a real /proc, but a bound must hold anyway.
        Assert.Equal(10, PosixAgyTab.ReadParentComms(7, _ => "x", p => $"{p} (x) S {p}").Count);
    }

    [Fact]
    public void FindOnPath_finds_a_file_in_a_PATH_directory()
    {
        var dir = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "clavity-path-" + Guid.NewGuid().ToString("N"))).FullName;
        try
        {
            File.WriteAllText(Path.Combine(dir, "agy"), "");
            Assert.Equal(Path.Combine(dir, "agy"), PosixAgyTab.FindOnPath("agy", "/nope" + Path.PathSeparator + dir));
            Assert.Null(PosixAgyTab.FindOnPath("agy", "/nope"));
            Assert.Null(PosixAgyTab.FindOnPath("agy", null));
        }
        finally { Directory.Delete(dir, recursive: true); }
    }

    [Fact]
    public void FallbackMessage_says_Claude_did_not_start_and_names_the_exact_command()
    {
        var m = PosixAgyTab.FallbackMessage("/home/o'brien/repo");
        Assert.Contains("Claude was NOT started", m);
        Assert.Contains("    clavity-ls agy '/home/o'\\''brien/repo'\n", m);
        Assert.Contains("CLAVITY_TERMINAL", m);
    }

    [Fact]
    public void AttachHint_names_the_session_and_the_start_command()
    {
        var m = PosixAgyTab.AttachHint("/repo", "11111111-2222-3333-4444-555555555555");
        Assert.Contains("    clavity-ls start '/repo' --attach 11111111-2222-3333-4444-555555555555\n", m);
    }
}
```

- [ ] **Step 2: Run, expect compile failures** - `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~PosixAgyTabTests"`.

- [ ] **Step 3: Implement** - `PosixAgyTab.cs`:

```csharp
using System.Diagnostics;
using System.Globalization;
using System.Text;

namespace Clavity.Ls;

/// <summary>A launcher process the ladder started and may have to abandon.</summary>
public interface IStartedProcess
{
    bool HasExited { get; }
    int ExitCode { get; }
    void Kill();
}

/// <summary>A terminal the ladder can open agy in. <see cref="Prefix"/> precedes the script path.
/// <see cref="ScriptAsOneArgument"/>: the terminal parses the command from ONE string (mate-terminal's <c>-e</c>), so
/// the path is shell-quoted. <see cref="ProcessNamePrefix"/> matches <c>/proc/&lt;pid&gt;/comm</c> by PREFIX, because
/// the kernel truncates comm to 15 bytes (gnome-terminal-server reads <c>gnome-terminal-</c>).</summary>
public sealed record TerminalCandidate(
    string Name, string FileName, IReadOnlyList<string> Prefix, bool ScriptAsOneArgument,
    string? ProcessNamePrefix = null, string? EnvMarker = null);

/// <summary>Everything <see cref="PosixAgyTab.TryOpen"/> touches, so the ladder is testable without a desktop.</summary>
public sealed class PosixAgyTabDeps
{
    public required Func<string, string?> GetEnv { get; init; }
    /// <summary>The comm names of this process's ancestors, nearest first; empty when unknown (macOS, no /proc).</summary>
    public required Func<IReadOnlyList<string>> ParentComms { get; init; }
    /// <summary>Start without waiting. Throws when the command cannot be started (not installed).</summary>
    public required Func<LaunchCommand, IStartedProcess> Start { get; init; }
    public required Func<string, bool> FileExists { get; init; }
    /// <summary>Create the file only if it does not exist (O_EXCL); false when it already did.</summary>
    public required Func<string, bool> TryCreateExclusive { get; init; }
    public required Func<long> NowMs { get; init; }
    public required Action<TimeSpan> Sleep { get; init; }
}

/// <summary>
/// Opens this session's agy in a terminal the user can SEE on Linux (ROADMAP section 62). Windows keeps its Windows
/// Terminal tab (<see cref="Launcher.Build"/>); this class is never used there. Order (owner-adopted after AGY-FIRST
/// R1-R3, notes in .clavity/scratch/linux-agy-tab/r1-summary.md): CLAVITY_TERMINAL, then the terminal the user is
/// running in as a TAB, then xdg-terminal-exec, x-terminal-emulator, then the other known tab terminals.
/// </summary>
public static class PosixAgyTab
{
    public const string TerminalVar = "CLAVITY_TERMINAL";
    public static readonly TimeSpan ReadyTimeout = TimeSpan.FromSeconds(5);
    public static readonly TimeSpan PollInterval = TimeSpan.FromMilliseconds(50);
    private const int MaxParentDepth = 10;

    /// <summary>Known tab-capable terminals, in fallback order. mate-terminal is MEASURED (Ubuntu 26.04 MATE,
    /// 2026-10-02: <c>--tab -e "&lt;cmd&gt;"</c> opens a tab in the running window, passes env and cwd, script running in
    /// 80-130 ms). gnome-terminal, konsole and xfce4-terminal are UNMEASURED: a wrong verb costs one
    /// <see cref="ReadyTimeout"/> and the ladder moves on, because success is the claim file, never an exit code.</summary>
    public static readonly IReadOnlyList<TerminalCandidate> TabTerminals = new[]
    {
        new TerminalCandidate("mate-terminal", "mate-terminal", new[] { "--tab", "-e" }, ScriptAsOneArgument: true,
            ProcessNamePrefix: "mate-terminal"),
        new TerminalCandidate("gnome-terminal", "gnome-terminal", new[] { "--tab", "--" }, ScriptAsOneArgument: false,
            ProcessNamePrefix: "gnome-terminal-", EnvMarker: "GNOME_TERMINAL_SCREEN"),
        new TerminalCandidate("konsole", "konsole", new[] { "--new-tab", "-e" }, ScriptAsOneArgument: false,
            ProcessNamePrefix: "konsole", EnvMarker: "KONSOLE_VERSION"),
        new TerminalCandidate("xfce4-terminal", "xfce4-terminal", new[] { "--tab", "-x" }, ScriptAsOneArgument: false,
            ProcessNamePrefix: "xfce4-terminal"),
    };

    public static IReadOnlyList<TerminalCandidate> Candidates(Func<string, string?> env, IReadOnlyList<string> parentComms)
    {
        var list = new List<TerminalCandidate>();
        // Over ssh or on a text console no terminal can open: go straight to the fallback (measured: rc 1 in 30 ms).
        if (string.IsNullOrWhiteSpace(env("DISPLAY")) && string.IsNullOrWhiteSpace(env("WAYLAND_DISPLAY")))
            return list;

        // The override runs through /bin/sh, so it may quote arguments exactly as at a prompt
        // (gnome-terminal --profile 'My Profile' --tab --); the script path arrives as "$1".
        if (env(TerminalVar) is { } custom && !string.IsNullOrWhiteSpace(custom))
            list.Add(new TerminalCandidate(TerminalVar, "/bin/sh",
                new[] { "-c", custom.Trim() + " \"$1\"", "clavity-terminal" }, ScriptAsOneArgument: false));

        // The terminal the user is IN: the nearest ancestor that is a known terminal. Under tmux or ssh the chain does
        // not reach it, so fall back to the env markers that do name one terminal (VTE_VERSION does not - every VTE
        // terminal sets it).
        TerminalCandidate? detected = null;
        foreach (var comm in parentComms)
        {
            detected = TabTerminals.FirstOrDefault(t => comm.StartsWith(t.ProcessNamePrefix!, StringComparison.Ordinal));
            if (detected is not null)
                break;
        }
        detected ??= TabTerminals.FirstOrDefault(t => t.EnvMarker is { } m && !string.IsNullOrEmpty(env(m)));
        if (detected is not null)
            list.Add(detected);

        list.Add(new TerminalCandidate("xdg-terminal-exec", "xdg-terminal-exec", Array.Empty<string>(), ScriptAsOneArgument: false));
        list.Add(new TerminalCandidate("x-terminal-emulator", "x-terminal-emulator", new[] { "-e" }, ScriptAsOneArgument: false));
        list.AddRange(TabTerminals.Where(t => !ReferenceEquals(t, detected)));
        return list;
    }

    public static IReadOnlyList<string> ArgumentsFor(TerminalCandidate c, string scriptPath)
        => c.Prefix.Append(c.ScriptAsOneArgument ? Launcher.ShQuote(scriptPath) : scriptPath).ToArray();

    /// <summary>Try each candidate until the session's script claims <see cref="SessionPaths.Claim"/>. Returns the
    /// winning candidate's name, or null when nothing did (the caller prints <see cref="FallbackMessage"/>).</summary>
    public static string? TryOpen(SessionPaths paths, string folder, PosixAgyTabDeps deps, TimeSpan readyTimeout)
    {
        foreach (var c in Candidates(deps.GetEnv, deps.ParentComms()))
        {
            IStartedProcess launcher;
            try
            {
                launcher = deps.Start(new LaunchCommand(c.FileName, ArgumentsFor(c, paths.AgyScript), folder,
                    new Dictionary<string, string>()));
            }
            catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
            {
                continue;   // not installed
            }

            var started = deps.NowMs();
            while (true)
            {
                if (deps.FileExists(paths.Claim))
                    return c.Name;
                if (launcher.HasExited && launcher.ExitCode != 0)
                    break;
                if (deps.NowMs() - started >= (long)readyTimeout.TotalMilliseconds)
                {
                    // Some terminals (xterm) do not fork, so their launcher never exits; close it rather than leave an
                    // empty window. Its script, if it ever runs, finds the claim taken and exits.
                    if (!launcher.HasExited)
                        launcher.Kill();
                    break;
                }
                deps.Sleep(PollInterval);
            }
        }

        // Nothing claimed in time. Take the claim ourselves so a terminal that opens LATER exits instead of starting an
        // agy that no Claude pairs with. If a script got there first after all, that agy is real: use it.
        return deps.TryCreateExclusive(paths.Claim) ? null : "late";
    }

    public static IReadOnlyList<string> ReadParentComms(int pid, Func<int, string?> readComm, Func<int, string?> readStat)
    {
        var names = new List<string>();
        var current = ParseStatPpid(readStat(pid));
        while (current is > 1 && names.Count < MaxParentDepth)
        {
            if (readComm(current.Value) is not { } comm)
                break;
            names.Add(comm.Trim());
            current = ParseStatPpid(readStat(current.Value));
        }
        return names;
    }

    /// <summary>The ppid field of <c>/proc/&lt;pid&gt;/stat</c>. comm (field 2) is in parentheses and may itself contain
    /// spaces or ')', so the fields are counted from the LAST ')'.</summary>
    public static int? ParseStatPpid(string? stat)
    {
        if (stat is null)
            return null;
        var close = stat.LastIndexOf(')');
        if (close < 0)
            return null;
        var fields = stat[(close + 1)..].Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return fields.Length > 1 && int.TryParse(fields[1], NumberStyles.None, CultureInfo.InvariantCulture, out var ppid)
            ? ppid
            : null;
    }

    public static string? FindOnPath(string name, string? pathVar)
    {
        if (string.IsNullOrEmpty(pathVar))
            return null;
        foreach (var dir in pathVar.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(dir, name);
            if (File.Exists(candidate))
                return candidate;
        }
        return null;
    }

    /// <summary>Write the generated script owner-only and executable (it names this session's endpoint file).</summary>
    public static void WriteScript(string path, string content)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, content, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
    }

    public static string FallbackMessage(string folder) =>
        "clavity: could not open a terminal for agy - there is no display (DISPLAY / WAYLAND_DISPLAY unset), or no\n" +
        $"  terminal started it within {ReadyTimeout.TotalSeconds:0} s. Claude was NOT started. Run agy yourself, in a terminal you can see:\n" +
        $"    clavity-ls agy {Launcher.ShQuote(folder)}\n" +
        "  It prints the command that starts Claude paired with that agy. To choose the terminal instead, set\n" +
        $"  {TerminalVar} to a command that runs its last argument, for example \"gnome-terminal --tab --\".\n";

    public static string AttachHint(string folder, string sessionId) =>
        $"clavity: this terminal runs agy for session {sessionId}.\n" +
        "  In ANOTHER terminal, start Claude paired with it:\n" +
        $"    clavity-ls start {Launcher.ShQuote(folder)} --attach {sessionId}\n";

    public static PosixAgyTabDeps RealDeps()
    {
        var clock = Stopwatch.StartNew();
        return new PosixAgyTabDeps
        {
            GetEnv = Environment.GetEnvironmentVariable,
            ParentComms = () => ReadParentComms(Environment.ProcessId,
                p => TryReadText($"/proc/{p}/comm"), p => TryReadText($"/proc/{p}/stat")),
            Start = cmd => new StartedProcess(StartProcess(cmd)),
            FileExists = File.Exists,
            TryCreateExclusive = path =>
            {
                try
                {
                    using var _ = new FileStream(path, FileMode.CreateNew, FileAccess.Write);
                    return true;
                }
                catch (IOException) when (File.Exists(path))
                {
                    return false;
                }
            },
            NowMs = () => clock.ElapsedMilliseconds,
            Sleep = t => Thread.Sleep(t),
        };
    }

    private static string? TryReadText(string path)
    {
        try { return File.ReadAllText(path); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return null; }
    }

    private static Process StartProcess(LaunchCommand cmd)
    {
        var psi = new ProcessStartInfo(cmd.FileName) { WorkingDirectory = cmd.WorkingDirectory, UseShellExecute = false };
        foreach (var arg in cmd.Arguments)
            psi.ArgumentList.Add(arg);
        return Process.Start(psi) ?? throw new InvalidOperationException($"{cmd.FileName} did not start");
    }

    private sealed class StartedProcess(Process process) : IStartedProcess
    {
        public bool HasExited => process.HasExited;
        public int ExitCode => process.ExitCode;
        public void Kill()
        {
            try { process.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { /* already gone */ }
        }
    }
}
```

- [ ] **Step 4: Run** - same command -> `Passed: 24` (20 Facts + the 4 rows of the `ParseStatPpid` Theory), `Failed: 0`.

- [ ] **Step 5: Mutants (each must redden exactly the named row; `git add` first, `git checkout --` the source after each):**
  - `detected` loop: take the LAST matching ancestor instead of the first -> `The_NEAREST_matching_ancestor_wins...` red.
  - drop `&& launcher.ExitCode != 0` (break on any exit) -> `Exit_zero_without_a_claim_waits...` red.
  - return `null` unconditionally at the end -> `A_script_that_claims_after_the_last_timeout...` red.
  - remove the `if (!launcher.HasExited) launcher.Kill();` -> `...still_running_launcher_is_killed` red.
  - drop the `" \"$1\""` from the override's `-c` string -> `Order_is_override_then_detected_tab...` red.

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Ls/PosixAgyTab.cs clavity-dotnet/tests/Clavity.Ls.Tests/PosixAgyTabTests.cs
git commit -m "feat(ls): PosixAgyTab - open agy in the user's terminal tab, claim-file readiness, fallback text (section 62)"
```

---

### Task 5: wire `start` and the new `agy` verb in `Program.cs`

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/AgyEnvironment.cs` (add `TryReadProjectId`),
`clavity-dotnet/src/Clavity.Cli/Program.cs` (the `start` block, from its comment at line 75 to the closing `}` after
`TryReadProjectId`; the usage line, line 168 - all before Task 1, which leaves the line count unchanged).

Program.cs has no unit tests (top-level statements; ROADMAP section 53 records that `start` is untested). Every
decision it makes is in the classes Tasks 1-4 tested; Task 9 runs it on the VM.

- [ ] **Step 1: Move `TryReadProjectId`.** Add to `AgyEnvironment` (after `ResolveEndpointPath`):

```csharp
    /// <summary>agy's default project id (<c>&lt;agyHome&gt;/cache/default_project_id.txt</c>), exported to the agy it
    /// launches as ANTIGRAVITY_PROJECT_ID; null when absent or empty.</summary>
    public static string? TryReadProjectId(string agyHomeDir)
    {
        var path = Path.Combine(agyHomeDir, "cache", "default_project_id.txt");
        if (!File.Exists(path))
            return null;
        var id = File.ReadAllText(path).Trim();
        return id.Length > 0 ? id : null;
    }
```

  and delete the local `static string? TryReadProjectId(string agyHome) { ... }` from Program.cs, changing its call
  to `AgyEnvironment.TryReadProjectId(agyHome)`.

- [ ] **Step 2: Replace the whole `start` block** (from the `// \`clavity start <folder> [claude-args...]\`` comment to
  the closing `}` after the `Spawn` local function) with:

```csharp
// `clavity-ls agy [folder]` (Linux/macOS) - run a new session's agy in THIS terminal, for when `start` cannot open
// one (no display, or no terminal it knows). It prints the `start --attach` command for a second terminal.
if (args.Length > 0 && args[0] == "agy")
{
    if (OperatingSystem.IsWindows())
    {
        Console.Error.WriteLine("clavity: `clavity-ls agy` is for Linux and macOS - on Windows, `clavity-ls start` opens agy in a Windows Terminal tab.");
        return 2;
    }
    var agyFolder = args.Length > 1 ? Path.GetFullPath(args[1]) : Directory.GetCurrentDirectory();
    if (!Directory.Exists(agyFolder))
    {
        Console.Error.WriteLine($"clavity: {agyFolder} does not exist.");
        return 2;
    }
    var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    var agySession = Guid.NewGuid().ToString("D");
    var agyPaths = SessionPaths.For(home, agySession);
    Directory.CreateDirectory(Path.GetDirectoryName(agyPaths.AgyLog)!);
    if (PosixAgyTab.FindOnPath("agy", Environment.GetEnvironmentVariable("PATH")) is null)
    {
        Console.Error.WriteLine("clavity: agy is not on PATH - install Antigravity's agy CLI, or add its directory to PATH, then retry.");
        return 1;
    }
    string agyDoc;
    try
    {
        agyDoc = PairingDoc.Materialize(Path.GetDirectoryName(agyPaths.Endpoint)!);
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
    {
        Console.Error.WriteLine($"clavity: cannot write the agy pairing instructions ({ex.Message}) - not launching.");
        return 1;
    }
    PosixAgyTab.WriteScript(agyPaths.AgyScript, Launcher.BuildPosixScript(new LaunchOptions
    {
        Folder = agyFolder,
        SessionId = agySession,
        ProjectId = AgyEnvironment.TryReadProjectId(Path.Combine(home, ".gemini", "antigravity-cli")),
        AgyLogFilePath = agyPaths.AgyLog,
        AgyEndpointFilePath = agyPaths.Endpoint,
        SkipPermissions = true,
        AgyInstallDocPath = agyDoc,
    }, agyPaths.Claim));

    // agy's full-screen interface takes this terminal over, so the command must be read BEFORE it starts.
    Console.Error.Write(PosixAgyTab.AttachHint(agyFolder, agySession));
    if (!Console.IsInputRedirected)
    {
        Console.Error.Write("  Press Enter to start agy here.");
        Console.ReadLine();
    }
    using var agyProcess = Process.Start(new ProcessStartInfo("/bin/sh") { ArgumentList = { agyPaths.AgyScript }, UseShellExecute = false })!;
    agyProcess.WaitForExit();
    return agyProcess.ExitCode;
}

// `clavity start [folder] [--attach <session-id>] [claude-args...]` - open a visible human-owned agy tab (per-session
// LS log) + launch Claude. With --attach, launch Claude only, paired with the agy `clavity-ls agy` started.
if (args.Length > 0 && args[0] == "start")
{
    StartArgs start;
    try
    {
        start = StartArgs.Parse(args.Skip(1).ToArray(), Directory.GetCurrentDirectory());
    }
    catch (ArgumentException ex)
    {
        Console.Error.WriteLine($"clavity: {ex.Message}");
        return 2;
    }
    var folder = start.Folder;

    if (!Directory.Exists(Path.Combine(folder, ".git")))
        Console.Error.WriteLine($"clavity: warning — {folder} is not a git repository.");

    var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    var agyHome = Path.Combine(userProfile, ".gemini", "antigravity-cli");

    var sessionId = start.AttachSessionId ?? Guid.NewGuid().ToString("D");
    // Per-session files (SessionPaths): the agy log, and the pairing rendezvous keyed by session so two concurrent
    // clavity sessions cannot clobber one another's endpoint (both the agy side and clavity-ls get this exact path
    // via CLAVITY_AGY_ENDPOINT).
    var paths = SessionPaths.For(userProfile, sessionId);
    var logsDir = Path.GetDirectoryName(paths.AgyLog)!;
    Directory.CreateDirectory(logsDir); // idempotent + concurrency-safe (spec §11a).
    LogRetention.Prune(logsDir, LogRetention.DefaultMaxAge, DateTime.UtcNow);

    if (start.AttachSessionId is not null)
    {
        // agy already runs in another terminal (`clavity-ls agy`) and publishes to this session's endpoint.
        var attached = Launcher.Build(new LaunchOptions
        {
            Folder = folder,
            SessionId = sessionId,
            ClaudeArgs = start.ClaudeArgs,
            AgyLogFilePath = paths.AgyLog,
            AgyEndpointFilePath = paths.Endpoint,
        });
        Spawn(attached.ClaudeLaunch, wait: true);
        return 0;
    }

    // The pairing doc is embedded in this binary and written out on every start (PairingDoc). Without it agy gets
    // no -i prompt, never publishes its endpoint, and the pairing is dead on arrival - so refuse, loudly, rather
    // than launch a half-working session (the old install-root lookup failed SILENTLY on every non-Inno install).
    string agyInstallDoc;
    try
    {
        agyInstallDoc = PairingDoc.Materialize(Path.GetDirectoryName(paths.Endpoint)!);
    }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
    {
        Console.Error.WriteLine($"clavity: cannot write the agy pairing instructions ({ex.Message}) - not launching.");
        return 1;
    }

    var options = new LaunchOptions
    {
        Folder = folder,
        SessionId = sessionId,
        ClaudeArgs = start.ClaudeArgs,
        ProjectId = AgyEnvironment.TryReadProjectId(agyHome),
        AgyLogFilePath = paths.AgyLog,
        AgyEndpointFilePath = paths.Endpoint,
        // User decision 2026-06-30: agy ALWAYS launches with --dangerously-skip-permissions so unattended
        // bus/LS consults never stall on per-tool approval prompts. (Supersedes spec §4 "NOT default".)
        SkipPermissions = true,
        AgyInstallDocPath = agyInstallDoc,
    };
    var plan = Launcher.Build(options);

    if (OperatingSystem.IsWindows())
    {
        Spawn(plan.AgyTab, wait: false);    // agy tab boots asynchronously; human owns it.
        Spawn(plan.ClaudeLaunch, wait: true); // Claude runs in the foreground.
        return 0;
    }

    // Linux / macOS (ROADMAP sections 60 + 62): there is no `wt`. Open agy from a generated POSIX script in a terminal
    // the user can see, and start Claude only once a terminal really ran it - otherwise Claude's full-screen interface
    // would hide the reason pairing never happens.
    // The script's `cd` runs after its claim, so a missing folder would look like success here: refuse it first.
    if (!Directory.Exists(folder))
    {
        Console.Error.WriteLine($"clavity: {folder} does not exist.");
        return 2;
    }
    // Check BOTH programs before opening anything: a missing `claude` found only after agy's tab is up would leave
    // an orphaned agy behind an unhandled exception.
    var pathVar = Environment.GetEnvironmentVariable("PATH");
    foreach (var (exe, what) in new[] { ("agy", "Antigravity's agy CLI"), ("claude", "Claude Code") })
    {
        if (PosixAgyTab.FindOnPath(exe, pathVar) is null)
        {
            Console.Error.WriteLine($"clavity: {exe} is not on PATH - install {what}, or add its directory to PATH, then retry.");
            return 1;
        }
    }
    PosixAgyTab.WriteScript(paths.AgyScript, Launcher.BuildPosixScript(options, paths.Claim));
    if (PosixAgyTab.TryOpen(paths, folder, PosixAgyTab.RealDeps(), PosixAgyTab.ReadyTimeout) is null)
    {
        Console.Error.Write(PosixAgyTab.FallbackMessage(folder));
        return 1;
    }
    Spawn(plan.ClaudeLaunch, wait: true);
    return 0;

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
}
```

- [ ] **Step 3: Usage line.** Replace the last `Console.WriteLine(...)` with:

```csharp
Console.WriteLine("clavity-ls — usage: clavity-ls start [folder] [--attach <session-id>] [claude-args...]   |   clavity-ls agy [folder]   (Linux/macOS: agy in this terminal)   |   clavity-ls --mcp   (MCP stdio server: agy_look / agy_status / agy_ask)");
```

- [ ] **Step 4: Build + full unit suite** - `dotnet build` (0 errors, and no NEW warnings vs `git stash`-free baseline:
  run `dotnet build` on the parent commit first and compare the warning count) then `dotnet test tests/Clavity.Ls.Tests`
  -> `Failed: 0`.

- [ ] **Step 5: Windows smoke (behaviour unchanged).** `dotnet run --project src/Clavity.Cli -- start --attach not-a-guid`
  -> stderr `clavity: --attach 'not-a-guid' is not a session id ...`, exit 2. `dotnet run --project src/Clavity.Cli -- agy`
  -> the Windows refusal, exit 2. Do NOT run a real `start` (it would open a wt tab and a Claude session).

- [ ] **Step 6: Commit**

```bash
git add clavity-dotnet/src/Clavity.Cli/Program.cs clavity-dotnet/src/Clavity.Ls/AgyEnvironment.cs
git commit -m "feat(start): Linux opens agy via PosixAgyTab; new 'agy' verb and 'start --attach' (sections 60+62)"
```

---

### Task 6: the pairing doc works under bash and refuses empty values

**Files:** Modify `clavity-dotnet/pairing/agy-pairing-INSTALL.md` (Step 1 section, lines 14-26); create
`scripts/tests/pairing-doc.Tests.ps1`; register it in `justfile` (`test-scripts-slow` list) and add its row to
`scripts/tests/_partition.md`.

**Oracle:** the Pester rows below EXECUTE each command exactly as the doc states it.
`PairingDocTests.Embedded_doc_is_byte_identical_to_the_source_doc` keeps the embedded copy in step automatically.

- [ ] **Step 1: Write the failing suite** - `scripts/tests/pairing-doc.Tests.ps1`:

```powershell
# ROADMAP sections 60 + 62. clavity-dotnet/pairing/agy-pairing-INSTALL.md is what agy runs to publish its endpoint.
# Each shell's command is EXTRACTED from the doc and RUN, so these rows test the text agy actually reads. MEASURED
# 2026-10-02: agy ran the line through an MCP shell tool whose processes lack the ANTIGRAVITY_* variables and published
# empty values - so both lines must refuse, not publish, when either is empty.
BeforeAll {
    . (Join-Path $PSScriptRoot 'BashHookHelpers.ps1')
    $script:Bash = Get-GitBashOrThrow
    $doc = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot '../../clavity-dotnet/pairing/agy-pairing-INSTALL.md')
    $sh = [regex]::Matches($doc, '(?s)```sh\r?\n(.+?)\r?\n```')
    $ps = [regex]::Matches($doc, '(?s)```powershell\r?\n(.+?)\r?\n```')
    # Guarded: a doc with no such block must fail the ROWS below, not abort the container in BeforeAll.
    $script:Cmd = @{ sh = $(if ($sh.Count) { $sh[0].Groups[1].Value } else { '' }); pwsh = $(if ($ps.Count) { $ps[0].Groups[1].Value } else { '' }) }
    $script:BlockCounts = @{ sh = $sh.Count; pwsh = $ps.Count }

    function Invoke-Publish([string]$Shell, [hashtable]$Vars) {
        # The three pairing variables are SET or REMOVED exactly as given; HOME / USERPROFILE only when given.
        $names = @('CLAVITY_AGY_ENDPOINT', 'ANTIGRAVITY_CSRF_TOKEN', 'ANTIGRAVITY_LS_ADDRESS', 'HOME', 'USERPROFILE')
        $saved = @{}; foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
        try {
            foreach ($n in $names[0..2]) { [Environment]::SetEnvironmentVariable($n, $(if ($Vars.ContainsKey($n)) { $Vars[$n] } else { $null })) }
            foreach ($n in $names[3..4]) { if ($Vars.ContainsKey($n)) { [Environment]::SetEnvironmentVariable($n, $Vars[$n]) } }
            $out = if ($Shell -eq 'sh') { & $script:Bash -c $script:Cmd.sh 2>&1 | Out-String }
                   else { & pwsh -NoProfile -NonInteractive -Command $script:Cmd.pwsh 2>&1 | Out-String }
            [pscustomobject]@{ ExitCode = $LASTEXITCODE; Out = $out }
        } finally {
            foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
        }
    }
    function New-Tmp { (New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ("pd-" + [guid]::NewGuid().ToString('N')))).FullName }
}

Describe 'agy-pairing-INSTALL.md - the publish step' {
    It 'states exactly one POSIX and one PowerShell command' {
        $script:BlockCounts.sh | Should -Be 1
        $script:BlockCounts.pwsh | Should -Be 1
    }

    It '<Shell>: writes csrf, addr and a UTC timestamp to CLAVITY_AGY_ENDPOINT and prints the same line' -ForEach @(@{ Shell = 'sh' }, @{ Shell = 'pwsh' }) {
        $tmp = New-Tmp
        try {
            $ep = (Join-Path $tmp 'sub/agy-endpoint.sid.json') -replace '\\', '/'
            $res = Invoke-Publish $Shell @{ CLAVITY_AGY_ENDPOINT = $ep; ANTIGRAVITY_CSRF_TOKEN = 'tok-1'; ANTIGRAVITY_LS_ADDRESS = 'localhost:4242' }
            $res.ExitCode | Should -Be 0 -Because $res.Out
            $raw = Get-Content -Raw -LiteralPath $ep
            $raw | Should -Match '"csrf":\s*"tok-1"'
            $raw | Should -Match '"addr":\s*"localhost:4242"'
            $raw | Should -Match '"published":\s*"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(\.\d+)?Z"'
            $res.Out | Should -Match 'tok-1'
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '<Shell>: with CLAVITY_AGY_ENDPOINT unset, writes .clavity/agy-endpoint.json under the home directory' -ForEach @(@{ Shell = 'sh' }, @{ Shell = 'pwsh' }) {
        $tmp = New-Tmp
        try {
            $res = Invoke-Publish $Shell @{ HOME = ($tmp -replace '\\', '/'); USERPROFILE = $tmp; ANTIGRAVITY_CSRF_TOKEN = 'tok-2'; ANTIGRAVITY_LS_ADDRESS = 'localhost:1' }
            $res.ExitCode | Should -Be 0 -Because $res.Out
            Get-Content -Raw -LiteralPath (Join-Path $tmp '.clavity/agy-endpoint.json') | Should -Match '"csrf":\s*"tok-2"'
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    It '<Shell>: REFUSES and writes nothing when <Missing> is empty, naming the built-in shell tool' -ForEach @(
        @{ Shell = 'sh'; Missing = 'ANTIGRAVITY_CSRF_TOKEN' }, @{ Shell = 'sh'; Missing = 'ANTIGRAVITY_LS_ADDRESS' },
        @{ Shell = 'pwsh'; Missing = 'ANTIGRAVITY_CSRF_TOKEN' }, @{ Shell = 'pwsh'; Missing = 'ANTIGRAVITY_LS_ADDRESS' }) {
        $tmp = New-Tmp
        try {
            $ep = (Join-Path $tmp 'agy-endpoint.sid.json') -replace '\\', '/'
            $vars = @{ CLAVITY_AGY_ENDPOINT = $ep; ANTIGRAVITY_CSRF_TOKEN = 'tok-3'; ANTIGRAVITY_LS_ADDRESS = 'localhost:2' }
            $vars.Remove($Missing)
            $res = Invoke-Publish $Shell $vars
            $res.ExitCode | Should -Not -Be 0
            $res.Out | Should -Match 'BUILT-IN shell tool'
            Test-Path -LiteralPath $ep | Should -BeFalse
        } finally { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
```

- [ ] **Step 2: Run it, expect failures** - `pwsh -NoProfile -c "Invoke-Pester scripts/tests/pairing-doc.Tests.ps1 -Output Detailed"`
  -> the block-count row and every `sh` row fail, and the `pwsh` refusal rows fail (today's line has no refusal).
  Read `Tests Passed:` - no such line means an ABORTED run, not a pass.

- [ ] **Step 3: Rewrite Step 1 of the doc.** Replace lines 14-26 of `clavity-dotnet/pairing/agy-pairing-INSTALL.md`
  (from `## Step 1 — Publish your endpoint` up to, not including, `## Step 2 — Confirm`) with:

````markdown
## Step 1 — Publish your endpoint

Run **exactly one** of these two lines with your **built-in shell tool** - not an MCP or plugin tool: only the
built-in tool's shell carries the two `ANTIGRAVITY_*` values the line publishes. Use the PowerShell line if that tool's
shell is PowerShell (Windows), the POSIX line if it is bash, zsh or sh (Linux, macOS). Then report the line it prints.

**PowerShell:**

```powershell
$dest = if ($env:CLAVITY_AGY_ENDPOINT) { $env:CLAVITY_AGY_ENDPOINT } else { Join-Path $(if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }) '.clavity/agy-endpoint.json' }; if (-not $env:ANTIGRAVITY_CSRF_TOKEN -or -not $env:ANTIGRAVITY_LS_ADDRESS) { throw 'clavity: ANTIGRAVITY_CSRF_TOKEN or ANTIGRAVITY_LS_ADDRESS is empty in this shell - run this line with your BUILT-IN shell tool, not an MCP or plugin tool' }; New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null; ([ordered]@{ csrf = $env:ANTIGRAVITY_CSRF_TOKEN; addr = $env:ANTIGRAVITY_LS_ADDRESS; published = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json -Compress) | Tee-Object -FilePath $dest
```

**POSIX shell:**

```sh
dest="${CLAVITY_AGY_ENDPOINT:-$HOME/.clavity/agy-endpoint.json}"; if [ -z "$ANTIGRAVITY_CSRF_TOKEN" ] || [ -z "$ANTIGRAVITY_LS_ADDRESS" ]; then echo "clavity: ANTIGRAVITY_CSRF_TOKEN or ANTIGRAVITY_LS_ADDRESS is empty in this shell - run this line with your BUILT-IN shell tool, not an MCP or plugin tool" >&2; false; else mkdir -p "$(dirname "$dest")" && printf '{"csrf":"%s","addr":"%s","published":"%s"}\n' "$ANTIGRAVITY_CSRF_TOKEN" "$ANTIGRAVITY_LS_ADDRESS" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee "$dest"; fi
```

Either line writes your peer's endpoint file (its path is `CLAVITY_AGY_ENDPOINT` when your session set it — a
per-session file so parallel sessions never overwrite each other — otherwise `.clavity/agy-endpoint.json` in your
home directory) and prints the same JSON so you can confirm. Your peer reads that same path. If the line says a value
is empty, you ran it in the wrong tool: run it again with your built-in shell tool.

````

  The POSIX line uses `false` rather than `exit` so it cannot end a shell session it shares; `printf` writes the two
  values unescaped, which is safe because the CSRF token is a UUID and the address is `host:port` (both measured on the
  VM endpoint, `.clavity/scratch/linux-agy-tab/r1-summary.md`).

- [ ] **Step 4: Run** - same command -> `Tests Passed: 9, Failed: 0` (1 + 2 + 2 + 4).

- [ ] **Step 5: Mutant** - `git add` first; delete `if [ -z "$ANTIGRAVITY_CSRF_TOKEN" ] || [ -z "$ANTIGRAVITY_LS_ADDRESS" ]; then ... false; else` and
  the trailing `; fi` from the POSIX line -> exactly the two `sh` refusal rows go red. Restore with `git checkout --`.

- [ ] **Step 6: Embedded copy** - `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~PairingDocTests"` -> `Passed: 7`.

- [ ] **Step 7: Register the suite.** Add `'scripts/tests/pairing-doc.Tests.ps1'` to the `test-scripts-slow` array in
  `justfile` (keep the list alphabetical). Measure the suite twice, backgrounded and idle (global TIMING discipline),
  and add a row to `scripts/tests/_partition.md` in the same format as its neighbours:
  `pairing-doc.Tests.ps1   <warm>s   9 tests   <- SLOW, NEW 2026-10-0x (Branch 18, ROADMAP sections 60+62; <runs>, box load uncontrolled)`.
  Then run `scripts/tests/test-suite-registration.Tests.ps1` -> green.

- [ ] **Step 8: Commit**

```bash
git add clavity-dotnet/pairing/agy-pairing-INSTALL.md scripts/tests/pairing-doc.Tests.ps1 justfile scripts/tests/_partition.md
git commit -m "fix(pairing): POSIX publish line; both lines refuse empty ANTIGRAVITY_* values (section 60)"
```

---

### Task 7: the `auth_failed` hint points at the agy tab

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/ChannelDown.cs:96-101`; test in `clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs`.

- [ ] **Step 1: Failing test** - append to `ChannelDownTests`:

```csharp
    [Fact]
    public void Only_the_auth_hint_tells_the_user_to_look_for_a_pending_prompt_in_the_agy_tab()
    {
        // MEASURED 2026-10-02 (Linux VM): a NEW agy on a new folder stopped on a folder-trust prompt and published its
        // endpoint only after the user approved it; until then every call is an auth refusal.
        foreach (var f in Enum.GetValues<ChannelDown.Fault>())
        {
            var hint = ChannelDown.Hint(RepresentativeDiagnosticFor(f));
            if (f == ChannelDown.Fault.AuthFailed)
                Assert.Contains("approve a prompt in its tab", hint);
            else
                Assert.DoesNotContain("approve a prompt in its tab", hint);
        }
    }
```

- [ ] **Step 2: Run** `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~ChannelDownTests"` -> the new row fails.

- [ ] **Step 3: Implement** - in the `Fault.AuthFailed` arm, change the last string piece from
  `"will NOT fix a token refusal.",` to:

```csharp
                "will NOT fix a token refusal. If this session's agy only just started, look at its terminal first: a " +
                "new agy may be waiting for you to approve a prompt in its tab (folder trust, for example), and it " +
                "publishes its endpoint only after you answer.",
```

- [ ] **Step 4: Run** -> all `ChannelDownTests` green. **Step 5: Commit**
  `git add clavity-dotnet/src/Clavity.Ls/ChannelDown.cs clavity-dotnet/tests/Clavity.Ls.Tests/ChannelDownTests.cs`;
  `git commit -m "fix(hint): auth_failed points at a pending prompt in the agy tab (section 62)"`.

---

### Task 8: the knowledge manuals and the docs

**Files:** `clavity-dotnet/plugin/knowledge/agy-assumptions.md:26-29` and the identical
`clavity-classic/plugin/knowledge/agy-assumptions.md:26-29`; `CLAUDE.md:18`, `clavity-dotnet/CLAUDE.md:15`,
`clavity-classic/CLAUDE.md:9`; `clavity-dotnet/README.md` (First run, Command reference, Configuration).
`clavity-classic/plugin/README.md:154` already says "On Windows ... (agy's shell is pwsh)" - correct, unchanged.

- [ ] **Step 1: The shell assumption (60a)** - replace the four-line bullet starting `- **agy's shell tool is PowerShell (pwsh), not bash**`
  in BOTH copies with (ASCII only):

```markdown
- **agy's BUILT-IN shell tool runs the host's shell: PowerShell (pwsh) on Windows, the user's `$SHELL` (bash) on
  Linux** - even where pwsh is installed (measured on Ubuntu 2026-10-02: a pwsh snippet failed with exit 2, the bash
  form published). Hand agy shell snippets in the host's syntax, or one per shell and let it pick. agy may ALSO run a
  "run this in your shell" instruction through a third-party MCP shell tool it has installed; that tool's processes
  do not inherit the `ANTIGRAVITY_*` variables agy injects into its own shell, so a snippet that reads them must name
  the built-in tool and refuse empty values. **Re-verify:** ask agy to run a pwsh-only construct and a bash-only
  construct in the same turn and observe which succeeds, or check agy's own logs for the shell it actually invoked.
```

  Then `diff` the two files' bullets - identical.

- [ ] **Step 2: Three CLAUDE.md summaries** - in each, replace `agy's pwsh shell` with `agy's shell (pwsh on Windows, bash on Linux)`.
  Grep afterwards, case-insensitive, for every wording: `rg -i "pwsh shell|shell is pwsh|shell tool is powershell" -g "*.md"`
  - every remaining hit must be explicitly Windows-scoped.

- [ ] **Step 3: README** - in `clavity-dotnet/README.md`:
  - after the First-run paragraph ("Opens a visible `agy` tab ... `clavity@clavity`."), add:

```markdown
On Linux, `start` opens agy as a new tab in the terminal you ran it from (mate-terminal, gnome-terminal, konsole or
xfce4-terminal), otherwise in `xdg-terminal-exec` or `x-terminal-emulator`; set `CLAVITY_TERMINAL` to choose one. With
no display (over ssh, say) it starts nothing and tells you to run `clavity-ls agy <folder>` instead, which runs agy in
that terminal and prints the `clavity-ls start <folder> --attach <session-id>` to run in a second one. A new agy may
ask you to trust the folder before it pairs - answer it in agy's tab.
```

  - in Command reference, change the `start` bullet to
    `` - `clavity-ls start <folder> [--attach <session-id>] [claude-args...]` — launch a visible agy tab + Claude Code in `<folder>` ``
    `` (per-session log; defaults to the current directory). `--attach` starts Claude only, paired with the agy that `clavity-ls agy` started. ``
    and add `` - `clavity-ls agy [folder]` — Linux/macOS: run a new session's agy in this terminal and print the `start --attach` command for another. ``
  - in Configuration add `` - `CLAVITY_TERMINAL` — Linux: the terminal command `start` opens agy with, run by `/bin/sh` with the script path appended as its last argument, so shell quoting works (e.g. `gnome-terminal --tab --`). ``

- [ ] **Step 4: Gate the shipped manual** - `pwsh -NoProfile -File scripts/check-injected-context.ps1` -> `check-injected-context: OK`
  (the manuals ship in the plugin payload; the new bullet must stay ASCII and inside any budget the gate applies).

- [ ] **Step 5: Commit** - stage the 6 files explicitly;
  `git commit -m "docs: agy's shell is per-platform; Linux start/agy/--attach in the README (sections 60+62)"`.

---

### Task 9: run it on the VM (driver, over ssh)

Nothing in CI executes this path. The VM is `ssh user@169.58.38.179` (Ubuntu 26.04 MATE, desktop session `:10.0`; agy in
`~/.local/bin`; `/tmp/clv-e2e/ws` is already folder-trusted by agy).

- [ ] **Step 1: Publish linux-x64** - `cd clavity-dotnet && dotnet publish src/Clavity.Cli -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=false -o ../.clavity/scratch/linux-agy-tab/publish`,
  then `scp` the `clavity-ls` binary to `/tmp/clv-b18/clavity-ls` and `chmod +x`.
- [ ] **Step 2: No display** - over plain ssh (no DISPLAY): `/tmp/clv-b18/clavity-ls start /tmp/clv-e2e/ws` -> exit 1,
  stderr is `FallbackMessage` (quote it), `~/.clavity/agy-session.*.claim` exists for that session, no agy process started.
- [ ] **Step 3: Desktop, no detection** - borrow DISPLAY / DBUS from `mate-session` (as
  `.clavity/scratch/linux-agy-tab/probe-ready.sh` does), put `~/.local/bin` and a fake `claude` (writes its env to
  `/tmp/clv-b18/claude-env.txt`, exits 0) first on PATH, run `start /tmp/clv-e2e/ws` -> exit 0; the fake claude's env
  carries `CLAVITY_AGY_ENDPOINT` = this session's endpoint; within 120 s that endpoint holds a non-empty csrf and an
  addr whose port is in this session's agy log. Over ssh the parent walk finds `sshd`, so expect `x-terminal-emulator`
  (a window) - record which terminal opened.
- [ ] **Step 4: Owner-run, from a mate-terminal tab on the VM** - ask the owner to run
  `/tmp/clv-b18/clavity-ls start /tmp/clv-e2e/ws` and confirm agy opened as a TAB in that window and Claude paired
  (`agy_status` idle). Then `clavity-ls agy /tmp/clv-e2e/ws` in one tab and the printed `start ... --attach` in another.
- [ ] **Step 5: Record** the outcomes in `.clavity/scratch/linux-agy-tab/r1-summary.md` (not committed) and the
  execution memory.

---

### Task 10: close the sections and run the gates

- [ ] **Step 1: ROADMAP** - in `clavity-dotnet/ROADMAP.md`, append to the §60 and §62 headers
  ` · ✅ **FIXED on sweep Branch 18 (<range>)** - <one line each>`, naming the suites (`SessionPathsTests`,
  `StartArgsTests`, `PosixScriptRunTests`, `PosixAgyTabTests`, `pairing-doc.Tests.ps1`) and the VM run. Commit.
- [ ] **Step 2: Full gates, backgrounded** - `lefthook run pre-push --all-files` and the full `scripts/tests` Pester run,
  never two Pester suites at once; plus `cd clavity-dotnet && dotnet test tests/Clavity.Ls.Tests` and
  `dotnet test tests/Clavity.Integration.Tests` (CI runs both). Quote `Tests Passed:` and both `Passed:` counts.
- [ ] **Step 3: AGY-CAPSTONE, then AGY-TEST-AUDIT** over the branch range.

---

## Self-review (done at authoring)

- **Spec coverage.** Section 62: Linux crash (Task 5 - no `wt` on non-Windows), visible tab (Task 4 + 5), readiness
  by claim file (3, 4), no-display fallback + `agy` verb + `--attach` (2, 4, 5), Windows unchanged (Task 5 keeps the
  `wt` branch byte-for-byte; `LauncherTests` unchanged). Section 60: 60a manual + three summaries (Task 8), 60b POSIX
  doc + `$HOME` default + both forms pinned by EXECUTION (Task 6); the empty-values refusal and the built-in-tool
  wording come from the E2E measurement. New: the `auth_failed` hint (Task 7).
- **Not in scope, stated:** macOS terminals (`open -a Terminal`) - unmeasured; on macOS there is normally no DISPLAY,
  so `start` prints the fallback and `clavity-ls agy` works. `xdg-terminal-exec`, gnome-terminal, konsole and
  xfce4-terminal verbs are unmeasured; a wrong one costs one 5 s timeout. Old `agy-session.*.sh` / `.claim` files are
  not pruned (they are small; endpoint files already accumulate the same way).
- **Placeholders:** none in code steps. Task 6 Step 7's timing figure and Task 10's range are filled in at execution by
  measurement - they cannot be known before.
- **Type consistency:** `SessionPaths(SessionId, AgyLog, Endpoint, AgyScript, Claim)`, `StartArgs(Folder,
  AttachSessionId, ClaudeArgs)`, `PosixAgyTab.{Candidates, ArgumentsFor, TryOpen, ReadParentComms, ParseStatPpid,
  FindOnPath, WriteScript, FallbackMessage, AttachHint, RealDeps, TerminalVar, ReadyTimeout}`, `Launcher.{BuildPosixScript,
  ShQuote}`, `AgyEnvironment.TryReadProjectId` - used identically in every task.

## Panel ledger (AGY-AFTER)
- Solo R1 (driver): F1 Linux `start` spawned `claude` unchecked after agy's tab opened -> FOLDED (Task 5 checks `agy`
  AND `claude` on PATH before opening anything). F2 Task 8 edited a shipped manual with no gate -> FOLDED (Task 8 Step 4
  runs `check-injected-context.ps1`). Activation: `agy` is not an installer verb (`CliRouter.cs:10-11`:
  install / uninstall / is-installed) - no finding.
- agy R1 (cascade `f2cdbc7a`; reply flagged `[13b] TRUNCATED` because the BRIEF asked for a `[VERDICT]` token after the
  `PANEL VERDICT` line - driver's contract error, content complete, every claim measured):
  - Cascade: a failing `cd` in the script runs after the claim, so `start` reported success and the tab closed in a flash
    -> FOLDED (Task 5: `start` and `agy` refuse a missing folder; Task 3: the script's `cd` failure prints and holds 60 s).
  - Mechanism Gamer: the prefix row passes with `StartsWith` -> `==` -> DISCARDED-BELOW-FLOOR: an equivalent mutant on
    every reachable input - the kernel caps comm at 15 bytes (TASK_COMM_LEN 16) and every `ProcessNamePrefix` is a full
    comm of <= 15 bytes (`gnome-terminal-` is the truncated gnome-terminal-server).
  - Q1 (a D-Bus terminal slower than 5 s) -> DISCARDED-BELOW-FLOOR: measured 80-130 ms (Provenance), ~40x margin.
  - Q2 (`xdg-terminal-exec` ignoring `-e`) -> REJECTED: the plan passes it no `-e` (empty Prefix, Task 4 `Candidates`).

- agy R2 (flagged `[13b] ECHO MISSING`: it quoted the plan's last line with the backticks stripped - a near-miss; its
  `[VERIFIED]` named only the brief and the plan, and its quote of the split line was NOT the plan's text):
  - Boundary Smuggler: `CLAVITY_TERMINAL` split on whitespace breaks a quoted argument - REAL against the plan's actual
    `Split(' ', ...)` line -> FOLDED: the override now runs as `/bin/sh -c '<value> "$1"' clavity-terminal <script>`
    (Task 4 code, test, mutant; Task 8 README wording).
  - Fold Auditor, Blindspot, Dependency Cynic: no findings (Dependency Cynic opened no source file - not a coverage claim).

  - Driver MEASURED the fold on the VM (`.clavity/scratch/linux-agy-tab/probe-override.sh`): `/bin/sh -c '<value> "$1"'
    clavity-terminal <script>` with `mate-terminal --title 'two words' --tab -x` ran a script whose path has a SPACE -
    quoting works. Same probe: `x-terminal-emulator -e <path with a space>` returned rc 0 and the script NEVER ran (the
    MATE wrapper re-splits `-e`) - see Stand-downs.

- agy R3 (Fold Auditor, Resource Vampire, First Reader; echo correct; `[VERIFIED]` again named only the brief and the plan):
  - First Reader "BLOCKING: `Invoke-Publish` never closes `try` and has no `finally`" -> REJECTED: the plan's Task 6 block
    closes it (`} finally {` / `foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }` / `}`);
    the peer's quote OMITTED exactly those lines.
  - Resource Vampire: launcher `Process` objects are never disposed -> DISCARDED-BELOW-FLOOR (see Stand-downs).
  - Fold Auditor: no findings. PANEL VERDICT (driver): no live challenge -> GREEN after solo R1 + agy R1-R3.

## Execution notes
- Task 4: the plan's mutant "drop `&& launcher.ExitCode != 0`" left ALL 24 rows green - the row it named uses a launcher
  that never exits, and no row had a launcher that exits 0 BEFORE its script claims, which is exactly the measured
  mate-terminal shape (client exits 0 at ~60 ms, script claims at ~100 ms). Added
  `A_launcher_that_exits_0_BEFORE_its_script_claims_is_still_waited_for` (fake clock, claim at 100 ms); that mutant now
  reddens exactly it. 25 rows; all five mutants redden their intended rows.

## Stand-downs
- DISCARDED-BELOW-FLOOR: `StartsWith` vs `==` in terminal detection - equivalent on every reachable comm (<= 15 bytes).
- DISCARDED-BELOW-FLOOR: a terminal slower than `ReadyTimeout` (5 s) - measured 80-130 ms.
- DISCARDED-BELOW-FLOOR: `x-terminal-emulator -e` cannot run a script path containing a space (measured rc 0, script never
  ran) - reachable only when `$HOME` itself contains a space, and then the claim file never appears so the ladder moves on
  (Task 4 `TryOpen`); quoting the path for every x-terminal-emulator would break terminals whose `-e` takes argv (xterm).
- DISCARDED-BELOW-FLOOR: the ladder's launcher `Process` handles are not disposed - bounded by the candidate list (at most 7
  per `start`, Task 4 `Candidates`), each released when its process exits; no loop re-creates them.
