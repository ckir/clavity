# ROADMAP §65 (Branch 19): `start --attach` without a session id - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Over ssh (no display), `clavity-ls start <folder> --attach` with NO session id pairs Claude with the one agy
that `clavity-ls agy <folder>` is running, so nobody copies a 36-character GUID between two terminals.

**Architecture:** The `agy` verb writes a per-session `.folder` record. `start --attach` without an id asks a new
`SessionRegistry` for the sessions in that folder that are still usable and untaken, and pairs only when there is
exactly one. "Taken" is an exclusive `FileShare.None` handle on a per-session `.lock` file (`SessionLock`), held by the
attaching `start` until Claude exits; the OS drops it when the process dies. Every attach - with or without an id -
takes the lock, so two Claudes can never share one agy. All wiring goes through the existing `IStartEffects` seam.

**Tech Stack:** .NET 10, C#, xUnit (`clavity-dotnet/tests/Clavity.Ls.Tests`).

**Decided (do not reopen):** owner-approved scope after AGY-FIRST (`.clavity/seams/s65-agy-first.md`) and AGY-NEGOTIATE,
2026-10-03: Fork 1 (a) only. NOT in this branch: a pairing code; retiring agy's `CLAVITY_AGY_ENDPOINT` (Fork 2); a plain
`claude` pairing automatically (Fork 3 - `clavity-ls --mcp` starts with every `claude`, even `claude mcp list`, so it
cannot tell an intent to pair from browsing; a startup lock would take a session meant for `start --attach`, a lock at
first call is a race).

**Measured precondition (2026-10-03, probe `.clavity/scratch/s65-lock/`):** on Windows 11 and on Ubuntu (VM
`192.168.1.8`), a second process's `FileShare.None` open of a held file throws `IOException` ("being used by another
process"); after the holder is killed with `kill -9`, the open succeeds. Controls: with no holder, the open succeeds.
A second exclusive open inside the SAME process also throws `IOException` on both platforms (probe mode `twice`), so the
in-process unit tests below guard on Linux as well as on Windows CI.

**Liveness (panel round 1 fold):** a session counts only while the `clavity-ls agy` process that runs it holds a second
exclusive lock, `.alive`, for agy's whole run. A terminal killed with `kill -9`, or a reboot, skips the exit trap and
leaves no `.exited` file - without `.alive` such a session would read as "starting" forever (and a dead paired one whose
port number was reused would read as alive). The OS releases `.alive` exactly when that process dies.

**Behaviour after this branch:**
- `start <folder> --attach` (no id): exactly one usable untaken session in `<folder>` -> prints
  `clavity: attaching to agy session <id>.` and pairs with it; none at all -> exit 1, says to run `clavity-ls agy
  <folder>` first; none free but some taken -> exit 1, one "already has a Claude" line per taken session (panel round 1:
  "run agy first" would send the user to start a redundant agy); several free -> exit 1, lists one
  `clavity-ls start <folder> --attach <id>` line per FREE session.
- "Usable": its `.folder` record names this folder, its `.alive` lock is HELD (the `clavity-ls agy` running it is alive),
  its own `.lock` is free, it has no `.exited` file, and either it has not published an
  endpoint yet (agy starting, or waiting on a trust prompt) or its published port listens. A published endpoint whose
  port does NOT listen means that agy is gone: skipped.
- `start <folder> --attach <id>` and the no-id form both take the session's lock before anything else; a held lock ->
  exit 1, `clavity: agy session <id> already has a Claude - another \`clavity-ls start --attach\` is using it.`
- After `--attach`: a valid id is the id; an argument SHAPED like an id (only hex digits and dashes, 8+ characters) that
  is not a valid one is refused, exit 2 (a mistyped id must not silently become a prompt); anything else - a `-` option,
  a positional prompt such as `"fix the tests"`, or nothing - means no id, and it reaches Claude (panel round 1). Only a
  valid id ever becomes part of a file name.
- The `agy` verb's hint shows the short command first and the id form for when several agy sessions wait.
- On Windows nothing writes a `.folder` record (`clavity-ls agy` refuses there), so a no-id `--attach` on Windows always
  reports "no agy session is waiting" - accepted: `--attach` exists for sessions `clavity-ls agy` started.
- clavity-classic: NOT mirrored. Its pairing runs over psmux and has no `start --attach` / `agy` verb; the "mirror every
  pair change" rule covers the shared plugin pair (hooks, skills, knowledge), which this branch does not touch.
- Accepted, documented limitation: the per-session files (`.sh`, `.claim`, `.exited`, `.folder`, `.lock`) are not
  pruned; this is true of the first three today. Folder comparison is ordinal after `Path.GetFullPath` and trailing-
  separator trimming (the `agy` verb is Linux/macOS only).

---

## File structure

- Modify `clavity-dotnet/src/Clavity.Ls/SessionPaths.cs` - add `Folder` and `Lock` paths.
- Create `clavity-dotnet/src/Clavity.Ls/SessionLock.cs` - take / probe the exclusive lock.
- Create `clavity-dotnet/src/Clavity.Ls/SessionRegistry.cs` - `WaitingSession` record + `Find`.
- Modify `clavity-dotnet/src/Clavity.Ls/StartArgs.cs` - `Attach` flag; optional id.
- Modify `clavity-dotnet/src/Clavity.Ls/StartFlow.cs` - three new `IStartEffects` members; attach resolution and lock;
  `agy` writes the `.folder` record.
- Modify `clavity-dotnet/src/Clavity.Ls/PosixAgyTab.cs` - `AttachHint` short form.
- Modify `clavity-dotnet/src/Clavity.Cli/RealStartEffects.cs` - implement the three members.
- Tests: modify `SessionPathsTests.cs`, `StartArgsTests.cs`, `StartFlowTests.cs`, `PosixAgyTabTests.cs`; create
  `SessionLockTests.cs`, `SessionRegistryTests.cs` (all under `clavity-dotnet/tests/Clavity.Ls.Tests/`). xUnit discovers
  new test classes; no list to register them in.
- Docs: `clavity-dotnet/README.md` (lines 70-83), `clavity-dotnet/ROADMAP.md` (`### §65`, line 3712).

Build/test commands (run from `clavity-dotnet/`): `dotnet build` and `dotnet test tests/Clavity.Ls.Tests` (expected
pass line: `Passed!  - Failed:     0, Passed:   N`); integration: `dotnet test tests/Clavity.Integration.Tests`.
🔴 `dotnet test --filter` exits 0 when NOTHING matches - always read the `Total:` count.

---

### Task 1: `SessionPaths` gains `Folder` and `Lock`

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/SessionPaths.cs:6-20`; Test `clavity-dotnet/tests/Clavity.Ls.Tests/SessionPathsTests.cs:9-22`

- [ ] **Step 1: Extend the test.** In `For_derives_every_file_from_the_profile_and_the_session_id`, after the `Exited`
  assertion (line 21), add:

```csharp
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-session.{Sid}.folder"), p.Folder);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-session.{Sid}.lock"), p.Lock);
        Assert.Equal(Path.Combine(home, ".clavity", $"agy-session.{Sid}.alive"), p.Alive);
```

- [ ] **Step 2: Run it - expect a COMPILE failure** (`'SessionPaths' does not contain a definition for 'Folder'`):
  `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~SessionPathsTests"`

- [ ] **Step 3: Implement.** Replace the record header and `For` (lines 6-20) with:

```csharp
public sealed record SessionPaths(string SessionId, string AgyLog, string Endpoint, string AgyScript, string Claim, string Exited,
    string Folder, string Lock, string Alive)
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
            Claim: Path.Combine(clavity, $"agy-session.{sessionId}.claim"),
            // Written by the agy script (trap / finally) with agy's exit code, so a waiting start stops waiting.
            Exited: Path.Combine(clavity, $"agy-session.{sessionId}.exited"),
            // Written by `clavity-ls agy`: the folder this session runs in, so `start --attach` without an id finds it
            // (ROADMAP section 65).
            Folder: Path.Combine(clavity, $"agy-session.{sessionId}.folder"),
            // Held exclusively by the `start --attach` that paired with this session, for as long as it runs (SessionLock).
            Lock: Path.Combine(clavity, $"agy-session.{sessionId}.lock"),
            // Held exclusively by the `clavity-ls agy` that runs this session, for agy's whole run: a session counts as
            // waiting only while it is held, so a terminal killed -9 (no exit trap) or a reboot leaves no stale session.
            Alive: Path.Combine(clavity, $"agy-session.{sessionId}.alive"));
    }
```

- [ ] **Step 4: Run** the same filter. Expected: `Passed!`, Total 7.
- [ ] **Step 5: Commit** `git add clavity-dotnet/src/Clavity.Ls/SessionPaths.cs clavity-dotnet/tests/Clavity.Ls.Tests/SessionPathsTests.cs`
  `git commit -m "feat(start): per-session folder record and lock paths (section 65)"`

### Task 2: `SessionLock`

**Files:** Create `clavity-dotnet/src/Clavity.Ls/SessionLock.cs`; Create `clavity-dotnet/tests/Clavity.Ls.Tests/SessionLockTests.cs`

- [ ] **Step 1: Write the tests** (`SessionLockTests.cs`):

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>The "a Claude has this agy session" marker. Cross-process behaviour (a held lock blocks ANOTHER process and
/// is released when the holder is killed -9) was measured on Windows and Linux with .clavity/scratch/s65-lock; these rows
/// pin the same contract inside one process, where a second exclusive open conflicts the same way.</summary>
public sealed class SessionLockTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-lock-" + Guid.NewGuid().ToString("N"));
    private string LockPath => Path.Combine(_dir, "sub", "s.lock");

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    [Fact]
    public void A_lock_nobody_holds_is_taken_and_a_second_taker_is_refused_until_it_is_released()
    {
        Assert.False(SessionLock.IsTaken(LockPath));            // missing file: not taken
        using (var first = SessionLock.TryTake(LockPath))        // creates the directory and the file
        {
            Assert.NotNull(first);
            Assert.True(SessionLock.IsTaken(LockPath));
            Assert.Null(SessionLock.TryTake(LockPath));
        }
        Assert.False(SessionLock.IsTaken(LockPath));            // released: free again, the file still exists
        Assert.True(File.Exists(LockPath));
        using var again = SessionLock.TryTake(LockPath);
        Assert.NotNull(again);
    }

    [Fact]
    public void Probing_a_free_lock_does_not_take_it()
    {
        using (SessionLock.TryTake(LockPath)) { }               // leave the file behind, unheld
        Assert.False(SessionLock.IsTaken(LockPath));
        using var taken = SessionLock.TryTake(LockPath);         // the probe released its handle
        Assert.NotNull(taken);
    }
}
```

- [ ] **Step 2: Run - expect a COMPILE failure** (`The name 'SessionLock' does not exist`):
  `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~SessionLockTests"`

- [ ] **Step 3: Implement** `SessionLock.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>The "a Claude has this agy session" marker (ROADMAP section 65): an exclusive handle on the session's `.lock`
/// file, held by the `start --attach` that paired, for as long as it runs. The OS drops it when that process ends, even
/// when it is killed - MEASURED 2026-10-03 on Windows 11 and Ubuntu: a second process's exclusive open fails with
/// IOException while it is held, and succeeds after the holder is killed -9.</summary>
public static class SessionLock
{
    /// <summary>The held lock, or null when another holder has it. Dispose it to release.</summary>
    public static IDisposable? TryTake(string lockPath)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lockPath)!);
        try
        {
            return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException)
        {
            return null;
        }
    }

    /// <summary>True while another holder has <paramref name="lockPath"/>. A missing file is not taken; the probe holds
    /// nothing afterwards.</summary>
    public static bool IsTaken(string lockPath)
    {
        if (!File.Exists(lockPath))
            return false;
        try
        {
            using var probe = new FileStream(lockPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            return false;
        }
        catch (FileNotFoundException)
        {
            return false;   // removed between the check and the open
        }
        catch (IOException)
        {
            return true;
        }
    }
}
```

- [ ] **Step 4: Run** the same filter. Expected: `Passed!`, Total 2.
- [ ] **Step 5: Logic mutants (driver applies each with a script that asserts exactly one match; `git diff` must be
  non-empty; restore after):** (a) `IsTaken` returns `false` in the `IOException` catch -> row 1 red; (b) `TryTake`
  uses `FileShare.ReadWrite` -> row 1 red.
- [ ] **Step 6: Commit** `git add clavity-dotnet/src/Clavity.Ls/SessionLock.cs clavity-dotnet/tests/Clavity.Ls.Tests/SessionLockTests.cs`
  `git commit -m "feat(start): SessionLock - an exclusive per-session lock as the 'taken' marker (section 65)"`

### Task 3: `SessionRegistry`

**Files:** Create `clavity-dotnet/src/Clavity.Ls/SessionRegistry.cs`; Create `clavity-dotnet/tests/Clavity.Ls.Tests/SessionRegistryTests.cs`

- [ ] **Step 1: Write the tests** (`SessionRegistryTests.cs`):

```csharp
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class SessionRegistryTests : IDisposable
{
    private readonly string _home = Path.Combine(Path.GetTempPath(), "clavity-reg-" + Guid.NewGuid().ToString("N"));
    private readonly string _repo;
    private const string A = "aaaaaaaa-0000-0000-0000-000000000001";
    private const string B = "bbbbbbbb-0000-0000-0000-000000000002";

    public SessionRegistryTests()
    {
        Directory.CreateDirectory(Path.Combine(_home, ".clavity"));
        _repo = Directory.CreateDirectory(Path.Combine(_home, "repo")).FullName;
    }

    public void Dispose()
    {
        if (Directory.Exists(_home))
            Directory.Delete(_home, recursive: true);
    }

    private sealed class Ports(params int[] open) : IListeningPorts
    {
        public bool IsListening(int port) => open.Contains(port);
    }

    private SessionPaths Record(string id, string folder, DateTime? at = null)
    {
        var p = SessionPaths.For(_home, id);
        File.WriteAllText(p.Folder, folder + "\n");
        if (at is { } t)
            File.SetLastWriteTimeUtc(p.Folder, t);
        return p;
    }

    private static void Publish(SessionPaths p, int port) =>
        File.WriteAllText(p.Endpoint, $$"""{"csrf":"t","addr":"127.0.0.1:{{port}}","published":"x"}""");

    // Default: every session's `clavity-ls agy` is alive (its .alive held) and no `start` holds its .lock.
    private static bool AliveOnly(string path) => path.EndsWith(".alive", StringComparison.Ordinal);

    private IReadOnlyList<WaitingSession> Find(IListeningPorts? ports = null, Func<string, bool>? held = null) =>
        SessionRegistry.Find(_home, _repo, ports ?? new Ports(), held ?? AliveOnly);

    [Fact]
    public void A_session_whose_agy_process_is_gone_is_skipped_even_without_an_exited_file()
    {
        Record(A, _repo);                                       // killed -9 or rebooted: no .exited, .alive released
        Assert.Empty(Find(held: _ => false));
        Assert.Single(Find());                                  // control: the same record while .alive is held
    }

    [Fact]
    public void A_session_that_has_not_published_yet_is_waiting_unpaired()
    {
        Record(A, _repo);
        var s = Assert.Single(Find());
        Assert.Equal(A, s.SessionId);
        Assert.False(s.Paired);
    }

    [Fact]
    public void A_published_session_counts_only_while_its_port_listens()
    {
        Publish(Record(A, _repo), 4242);
        Assert.True(Assert.Single(Find(new Ports(4242))).Paired);
        Assert.Empty(Find(new Ports(1)));                       // published, nothing listens: that agy is gone
    }

    [Fact]
    public void An_ended_session_and_another_folders_session_are_skipped()
    {
        var ended = Record(A, _repo);
        File.WriteAllText(ended.Exited, "0\n");
        Record(B, _repo);
        Record("cccccccc-0000-0000-0000-000000000003", Path.Combine(_home, "other"));
        Assert.Equal(B, Assert.Single(Find()).SessionId);
    }

    [Fact]
    public void A_session_another_start_holds_comes_back_marked_taken()
    {
        var held = Record(A, _repo);
        Assert.True(Assert.Single(Find(held: path => AliveOnly(path) || path == held.Lock)).Taken);
        Assert.False(Assert.Single(Find()).Taken);              // control: free lock
    }

    [Fact]
    public void A_trailing_separator_in_the_record_still_matches_and_a_malformed_name_is_ignored()
    {
        Record(A, _repo + Path.DirectorySeparatorChar);
        File.WriteAllText(Path.Combine(_home, ".clavity", "agy-session.not-a-guid.folder"), _repo + "\n");
        Assert.Equal(A, Assert.Single(Find()).SessionId);
    }

    [Fact]
    public void Several_waiting_sessions_come_back_oldest_first()
    {
        Record(B, _repo, new DateTime(2026, 10, 3, 10, 0, 0, DateTimeKind.Utc));
        Record(A, _repo, new DateTime(2026, 10, 3, 11, 0, 0, DateTimeKind.Utc));
        Assert.Equal([B, A], Find().Select(s => s.SessionId));
    }

    [Fact]
    public void No_clavity_directory_means_no_sessions()
        => Assert.Empty(SessionRegistry.Find(Path.Combine(_home, "nobody"), _repo, new Ports(), AliveOnly));
}
```

- [ ] **Step 2: Run - expect a COMPILE failure:** `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~SessionRegistryTests"`

- [ ] **Step 3: Implement** `SessionRegistry.cs`:

```csharp
namespace Clavity.Ls;

/// <summary>An agy session started by `clavity-ls agy` that `start --attach` without an id may pair with. <see
/// cref="Paired"/>: agy has published an endpoint whose port listens; false while agy is still starting (or waiting on a
/// trust prompt). <see cref="Taken"/>: another `start` holds its lock - returned, not dropped, so the caller can say
/// "already has a Claude" instead of "run agy first" (panel round 1).</summary>
public sealed record WaitingSession(string SessionId, bool Paired, DateTime StartedUtc, bool Taken = false);

/// <summary>Finds the agy sessions in a folder that `start --attach` without an id may pair with (ROADMAP section 65). A
/// session counts when its `.folder` record names the folder, the `clavity-ls agy` running it still holds its `.alive`
/// lock, it has no `.exited` file, and its published endpoint (if any) still listens; a session another `start` holds is
/// returned with <see cref="WaitingSession.Taken"/> set. <paramref name="isHeld"/> answers "does some process hold this
/// lock file?" (<see cref="SessionLock.IsTaken"/>).</summary>
public static class SessionRegistry
{
    private const string Prefix = "agy-session.";
    private const string Suffix = ".folder";

    public static IReadOnlyList<WaitingSession> Find(string userProfileDir, string folder, IListeningPorts listening,
        Func<string, bool> isHeld)
    {
        var dir = Path.Combine(userProfileDir, ".clavity");
        if (!Directory.Exists(dir))
            return [];
        var want = Normalize(folder);
        var found = new List<WaitingSession>();
        foreach (var record in Directory.EnumerateFiles(dir, Prefix + "*" + Suffix))
        {
            var name = Path.GetFileName(record);
            var id = name[Prefix.Length..^Suffix.Length];
            if (!SessionPaths.IsValidSessionId(id))
                continue;
            string recorded;
            try
            {
                recorded = File.ReadAllText(record).Trim();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            if (recorded.Length == 0 || Normalize(recorded) != want)
                continue;
            var paths = SessionPaths.For(userProfileDir, id);
            if (!isHeld(paths.Alive))
                continue;   // its `clavity-ls agy` is gone - killed, or the machine rebooted - even if no .exited exists
            if (File.Exists(paths.Exited))
                continue;
            var paired = false;
            if (AgyEndpoint.TryRead(paths.Endpoint) is { } ep)
            {
                if (!listening.IsListening(ep.Port))
                    continue;   // published, but nothing listens: that agy is gone
                paired = true;
            }
            found.Add(new WaitingSession(id, paired, File.GetLastWriteTimeUtc(record), Taken: isHeld(paths.Lock)));
        }
        return found.OrderBy(s => s.StartedUtc).ThenBy(s => s.SessionId, StringComparer.Ordinal).ToList();
    }

    // Ordinal: the `agy` verb that writes the record runs on Linux / macOS, and both sides come from Path.GetFullPath.
    private static string Normalize(string path) => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
}
```

- [ ] **Step 4: Run** the same filter. Expected: `Passed!`, Total 8.
- [ ] **Step 5: Logic mutants (script-applied, one match asserted, non-empty diff, restore), by row NAME:** (0) drop
  the `.alive` skip -> `A_session_whose_agy_process_is_gone...` red; (a) drop the `Exited` skip ->
  `An_ended_session_and_another_folders_session_are_skipped` red; (b) `Taken: isHeld(paths.Lock)` -> `Taken: false` ->
  `A_session_another_start_holds_comes_back_marked_taken` red; (c) `continue` -> fall through when the port does not
  listen -> `A_published_session_counts_only_while_its_port_listens` red; (d) drop `TrimEndingDirectorySeparator` ->
  `A_trailing_separator...` red; (e) drop the `OrderBy` -> `Several_waiting_sessions_come_back_oldest_first` red (if
  enumeration order happens to match, also swap the two record times in a second run to confirm).
- [ ] **Step 6: Commit** `git add clavity-dotnet/src/Clavity.Ls/SessionRegistry.cs clavity-dotnet/tests/Clavity.Ls.Tests/SessionRegistryTests.cs`
  `git commit -m "feat(start): SessionRegistry - the usable, untaken agy sessions in a folder (section 65)"`

### Task 4: `StartArgs` - `--attach` with an optional id

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/StartArgs.cs:3-38`; Test `clavity-dotnet/tests/Clavity.Ls.Tests/StartArgsTests.cs:53-68`

- [ ] **Step 1: Change the tests.** Replace `Attach_with_no_id_is_refused_naming_the_flag` (lines 53-58) and the
  `[InlineData("--model")]` row of `Attach_with_a_malformed_id_is_refused_quoting_it` (line 63) with:

```csharp
    [Fact]
    public void Attach_with_nothing_after_it_has_no_id()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Attach_followed_by_a_dash_argument_has_no_id_and_the_argument_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "--model", "opus" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Without_attach_Attach_is_false()
        => Assert.False(StartArgs.Parse(new[] { Repo }, Cwd).Attach);
```

  Also add:

```csharp
    [Fact]
    public void Attach_followed_by_a_positional_prompt_has_no_id_and_the_prompt_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "fix the tests" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "fix the tests" }, a.ClaudeArgs);
    }

    [Fact]
    public void A_path_after_attach_is_not_an_id_and_never_becomes_a_file_name()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "../../etc" }, Cwd);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "../../etc" }, a.ClaudeArgs);
    }
```

  Replace the theory's rows with id-SHAPED near-misses (each must still be refused, quoting it):
  `[InlineData("11111111222233334444555555555555")]` (GUID "N" form), `[InlineData("11111111-2222-3333-4444-55555555555")]`
  (one digit short), `[InlineData("deadbeef")]` (8 hex). In the two existing tests that pass an id (lines 29-43) add
  `Assert.True(a.Attach);`.

- [ ] **Step 2: Run - expect a COMPILE failure** (`'StartArgs' does not contain a definition for 'Attach'`):
  `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~StartArgsTests"`

- [ ] **Step 3: Implement.** Replace lines 3-38 with:

```csharp
/// <summary>Parsed <c>clavity-ls start [folder] [--attach [&lt;session-id&gt;]] [claude-args...]</c>.</summary>
public sealed record StartArgs(string Folder, bool Attach, string? AttachSessionId, string[] ClaudeArgs)
{
    public const string AttachFlag = "--attach";

    /// <summary>The folder is the first argument unless it starts with '-'. <c>--attach</c> is ours only DIRECTLY after
    /// it (or first, with no folder), so every later argument still reaches Claude untouched. Its id is optional (ROADMAP
    /// section 65: with none, `start` pairs with the one agy session waiting in the folder): a valid id is consumed; an
    /// argument SHAPED like an id but invalid throws <see cref="ArgumentException"/> (a mistyped id must not silently
    /// become a prompt); anything else is Claude's. Only a valid id ever becomes part of a file name.</summary>
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

        var attach = false;
        string? id = null;
        if (i < rest.Length && rest[i] == AttachFlag)
        {
            attach = true;
            i++;
            if (i < rest.Length && SessionPaths.IsValidSessionId(rest[i]))
            {
                id = rest[i];
                i++;
            }
            else if (i < rest.Length && LooksLikeAnId(rest[i]))
            {
                throw new ArgumentException(
                    $"{AttachFlag} '{rest[i]}' is not a session id - use the one `clavity-ls agy` printed, or none.");
            }
        }

        return new StartArgs(folder, attach, id, rest[i..]);
    }

    // Hex digits and dashes only, 8 or more: what a mistyped or truncated session id looks like.
    private static bool LooksLikeAnId(string s) => s.Length >= 8 && s.All(c => c == '-' || char.IsAsciiHexDigit(c));
}
```

- [ ] **Step 4: Build** - `dotnet build` FAILS in `StartFlow.cs` only if it constructs `StartArgs`; it does not (it
  calls `Parse`), so expect success. Run the filter: `Passed!`, Total 13 (5 kept facts + 5 new facts + 3 theory rows).
- [ ] **Step 4b: Logic mutants (script-applied, one match, non-empty diff, restore):** (a) drop the `LooksLikeAnId`
  branch -> the theory rows red; (b) `s.Length >= 8` -> `>= 40` -> the theory rows red; (c) consume ANY non-dash
  argument as the id -> `Attach_followed_by_a_positional_prompt...` red.
- [ ] **Step 5: Commit** `git add clavity-dotnet/src/Clavity.Ls/StartArgs.cs clavity-dotnet/tests/Clavity.Ls.Tests/StartArgsTests.cs`
  `git commit -m "feat(start): --attach takes an optional session id (section 65)"`

### Task 5: `StartFlow` - resolve the session, take the lock; `agy` writes the folder record

**Files:** Modify `clavity-dotnet/src/Clavity.Ls/StartFlow.cs` (interface lines 8-39; `Agy` lines 79-97; `Start` lines
129-155); Modify `clavity-dotnet/src/Clavity.Ls/PosixAgyTab.cs:202-205`; Modify
`clavity-dotnet/src/Clavity.Cli/RealStartEffects.cs`; Tests `StartFlowTests.cs`, `PosixAgyTabTests.cs:252-257`.

- [ ] **Step 1: Extend the fake** in `StartFlowTests.cs` (class `Fake`, lines 14-90). Add:

```csharp
        public List<WaitingSession> Waiting { get; init; } = new();
        public bool TakeSucceeds { get; init; } = true;
        public readonly List<(string Path, string Folder)> FolderRecords = new();

        public void WriteSessionFolder(string path, string folder)
        {
            Calls.Add("folder");
            FolderRecords.Add((path, folder));
        }
        public IReadOnlyList<WaitingSession> FindWaitingSessions(string folder)
        {
            Calls.Add("find");
            return Waiting;
        }
        public IDisposable? TryTakeSession(SessionPaths paths)
        {
            Calls.Add("take");
            return TakeSucceeds ? new Release(Calls, "release") : null;
        }
        public IDisposable HoldSessionAlive(SessionPaths paths)
        {
            Calls.Add("alive");
            return new Release(Calls, "alive-release");
        }
        private sealed class Release(List<string> calls, string name) : IDisposable
        {
            public void Dispose() => calls.Add(name);
        }
```

- [ ] **Step 2: Update the existing rows** - located by TEST NAME (Step 1 shifted the line numbers; at `c02cbe8f`-era
  HEAD they were 221, 235, 244, 248-253, 361-362, 370). Each change is forced by the new behaviour:
  - `A_bad_argument_exits_2_before_anything_happens`: `[Repo, "--attach"]` is now valid; use the id-shaped near-miss
    `[Repo, "--attach", "11111111-2222-3333-4444-55555555555"]` and
    `Assert.StartsWith("clavity: --attach '11111111-2222-3333-4444-55555555555' is not a session id", ...)`.
  - `Attach_checks_claude_then_waits_then_runs_only_Claude`: `L("mkdir", "prune", "take", "claude?", "wait", "run:claude:wait", "release")`.
  - `Attach_with_claude_missing_does_not_wait`: `L("mkdir", "prune", "take", "claude?", "release")`.
  - `Attach_whose_agy_ends_before_pairing_never_starts_Claude`: replace `Assert.Equal("wait", fx.Calls[^1]);` with
    `Assert.Equal(["wait", "release"], fx.Calls[^2..]);`.
  - `Agy_prints_the_attach_command_waits_for_Enter_then_returns_the_scripts_code`: the `L(...)` becomes
    `L("mkdir", "onpath:agy", "doc", "script", "alive", "folder", "enter", "here", "alive-release")`, and its
    `--attach 1111...` assertion becomes
    `Assert.Contains($"    clavity-ls start {Launcher.ShQuote(Repo)} --attach\n", fx.Err.ToString());`.
  - `Agy_with_redirected_input_does_not_wait_for_Enter`:
    `L("mkdir", "onpath:agy", "doc", "script", "alive", "folder", "here", "alive-release")`.
  - (`.alive` is taken BEFORE the `.folder` record is written, so a record never exists without a live holder, and it
    is released only after agy has ended.)

- [ ] **Step 3: Add the new rows** (in the `// ---- start --attach ----` section):

```csharp
    private static WaitingSession W(string id, bool paired = true, bool taken = false) =>
        new(id, paired, new DateTime(2026, 10, 3, 9, 0, 0, DateTimeKind.Utc), taken);

    [Fact]
    public void Attach_without_an_id_whose_only_session_is_taken_says_so_instead_of_run_agy_first()
    {
        var fx = new Fake { Waiting = [W(Attached, taken: true)] };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find"), fx.Calls);
        Assert.Equal($"clavity: agy session {Attached} already has a Claude - another `clavity-ls start --attach` is using it.{Environment.NewLine}",
            fx.Err.ToString());
    }

    [Fact]
    public void A_taken_session_is_not_one_of_the_choices()
    {
        const string free = "cccccccc-0000-0000-0000-000000000003";
        var fx = new Fake { Waiting = [W(Attached, taken: true), W(free)] };
        Assert.Equal(0, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(free, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
    }

    [Fact]
    public void Attach_without_an_id_pairs_with_the_one_waiting_session_and_holds_its_lock_until_Claude_ends()
    {
        var fx = new Fake { Waiting = [W(Attached)], Exit = new() { ["claude"] = 6 } };
        Assert.Equal(6, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find", "mkdir", "prune", "take", "claude?", "wait", "run:claude:wait", "release"), fx.Calls);
        Assert.Equal(Attached, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
        Assert.Contains($"clavity: attaching to agy session {Attached}.", fx.Err.ToString());
    }

    [Fact]
    public void Attach_without_an_id_and_no_waiting_session_says_to_run_agy_first()
    {
        var fx = new Fake();
        Assert.Equal(1, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find"), fx.Calls);
        Assert.Equal($"clavity: no agy session is waiting in {Repo}. Run `clavity-ls agy {Launcher.ShQuote(Repo)}` in another terminal first.{Environment.NewLine}",
            fx.Err.ToString());
    }

    [Fact]
    public void Attach_without_an_id_and_several_waiting_sessions_lists_one_command_per_session()
    {
        const string other = "cccccccc-0000-0000-0000-000000000003";
        var fx = new Fake { Waiting = [W(Attached), W(other, paired: false)] };
        Assert.Equal(1, StartFlow.Start([Repo, "--attach"], fx));
        Assert.Equal(L("find"), fx.Calls);
        var err = fx.Err.ToString();
        Assert.Contains($"clavity: 2 agy sessions are waiting in {Repo} - choose one:", err);
        Assert.Contains($"    clavity-ls start {Launcher.ShQuote(Repo)} --attach {Attached}   (paired, since 2026-10-03 09:00:00 UTC)", err);
        Assert.Contains($"    clavity-ls start {Launcher.ShQuote(Repo)} --attach {other}   (starting, since 2026-10-03 09:00:00 UTC)", err);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void Attach_to_a_session_another_start_holds_is_refused_before_anything_else(bool withId)
    {
        var fx = new Fake { Waiting = [W(Attached)], TakeSucceeds = false };
        Assert.Equal(1, StartFlow.Start(withId ? [Repo, "--attach", Attached] : [Repo, "--attach"], fx));
        Assert.Equal("take", fx.Calls[^1]);
        Assert.Contains($"clavity: agy session {Attached} already has a Claude - another `clavity-ls start --attach` is using it.",
            fx.Err.ToString());
    }

    [Fact]
    public void Attach_with_an_id_does_not_search()
    {
        var fx = new Fake { Waiting = [W("cccccccc-0000-0000-0000-000000000003")] };
        StartFlow.Start([Repo, "--attach", Attached], fx);
        Assert.DoesNotContain("find", fx.Calls);
        Assert.Equal(Attached, fx.Ran.Single().Environment[AgyEnvironment.SessionIdVar]);
    }

    [Fact]
    public void A_plain_start_takes_no_lock_and_does_not_search()
    {
        var fx = new Fake { IsWindows = true };
        StartFlow.Start([Repo], fx);
        Assert.DoesNotContain("take", fx.Calls);
        Assert.DoesNotContain("find", fx.Calls);
    }
```

  And in the `// ---- agy ----` section:

```csharp
    [Fact]
    public void Agy_records_its_folder_so_attach_without_an_id_can_find_it()
    {
        var fx = new Fake { InputRedirected = true };
        StartFlow.Agy([Repo], fx);
        var (path, folder) = Assert.Single(fx.FolderRecords);
        Assert.Equal(SessionPaths.For(fx.UserProfile, fx.NewSessionId()).Folder, path);
        Assert.Equal(Repo, folder);
    }
```

- [ ] **Step 4: Run - expect RUNTIME failures, not a compile error** (extra members on the fake compile fine; Tasks 1-4
  supply `WaitingSession`): `dotnet test tests/Clavity.Ls.Tests --filter "FullyQualifiedName~StartFlowTests"`. Exactly the
  rows changed in Step 2 and the rows added in Step 3 fail; any OTHER failing row means Step 1 or 2 went wrong - stop.

- [ ] **Step 5: Implement - the interface.** Append to `IStartEffects` (after `RunScriptHere`, line 38):

```csharp
    /// <summary>Writes the `.folder` record that lets `start --attach` without an id find this session (ROADMAP section 65).</summary>
    void WriteSessionFolder(string path, string folder);
    /// <summary><see cref="SessionRegistry.Find"/> over the real files, listening ports and locks.</summary>
    IReadOnlyList<WaitingSession> FindWaitingSessions(string folder);
    /// <summary><see cref="SessionLock.TryTake"/> on this session's lock: null when another `start` holds it.</summary>
    IDisposable? TryTakeSession(SessionPaths paths);
    /// <summary>Holds this session's `.alive` lock for as long as `clavity-ls agy` runs it (<see cref="SessionLock.TryTake"/>;
    /// the id is fresh, so nobody else can hold it).</summary>
    IDisposable HoldSessionAlive(SessionPaths paths);
```

- [ ] **Step 6: Implement - `Agy`.** After the `fx.WriteScript(...)` statement (ends line 88), add:

```csharp
        // `start --attach` without an id finds this session through its folder record, and counts it only while this
        // process holds .alive - taken FIRST, so a record never exists without a live holder (ROADMAP section 65).
        using var alive = fx.HoldSessionAlive(paths);
        fx.WriteSessionFolder(paths.Folder, folder);
```

  (`using var` keeps it held through `fx.RunScriptHere(...)` at the end of the method.)

- [ ] **Step 7: Implement - `Start`.** Replace lines 130-155 (from `var sessionId = ...` to the end of the
  `if (start.AttachSessionId is not null) { ... }` block) with:

```csharp
        string sessionId;
        if (!start.Attach)
            sessionId = fx.NewSessionId();
        else if (start.AttachSessionId is { } given)
            sessionId = given;
        else if (PickWaitingSession(fx, folder) is { } picked)
            sessionId = picked;
        else
            return 1;
        // Per-session files (SessionPaths): the agy log, and the pairing rendezvous keyed by session so two concurrent
        // clavity sessions cannot clobber one another's endpoint (both the agy side and clavity-ls get this exact path
        // via CLAVITY_AGY_ENDPOINT).
        var paths = SessionPaths.For(fx.UserProfile, sessionId);
        var logsDir = Path.GetDirectoryName(paths.AgyLog)!;
        fx.CreateDirectory(logsDir); // idempotent + concurrency-safe (spec §11a).
        fx.PruneLogs(logsDir);

        if (start.Attach)
        {
            // agy already runs in another terminal (`clavity-ls agy`) and publishes to this session's endpoint. One Claude
            // per agy (ROADMAP section 65): the lock is held until Claude ends, and the OS drops it if this process dies.
            using var taken = fx.TryTakeSession(paths);
            if (taken is null)
            {
                fx.Error.WriteLine(AlreadyTaken(sessionId));
                return 1;
            }
            var attached = Launcher.Build(new LaunchOptions
            {
                Folder = folder,
                SessionId = sessionId,
                ClaudeArgs = start.ClaudeArgs,
                AgyLogFilePath = paths.AgyLog,
                AgyEndpointFilePath = paths.Endpoint,
            });
            if (!ClaudeIsStartable(fx))    // refuse before a wait that would end in a failed start anyway
                return 1;
            if (!fx.WaitForPairing(paths))
                return 1;
            return RunClaude(fx, attached.ClaudeLaunch);
        }
```

  (The replaced range already holds the old `paths` / `logsDir` / `CreateDirectory` / `PruneLogs` lines; the block above
  re-states them after the session is resolved, so each runs once. Line 129, `var agyHome = ...`, stays.)

  Add, next to `TryMaterialize`:

```csharp
    // `start --attach` without an id (ROADMAP section 65): the ONE usable, untaken agy session `clavity-ls agy` started in
    // this folder. None or several: say so, list them, and pair with nothing.
    private static string? PickWaitingSession(IStartEffects fx, string folder)
    {
        var all = fx.FindWaitingSessions(folder);
        var waiting = all.Where(s => !s.Taken).ToList();
        if (waiting.Count == 1)
        {
            fx.Error.WriteLine($"clavity: attaching to agy session {waiting[0].SessionId}.");
            return waiting[0].SessionId;
        }
        if (waiting.Count == 0 && all.Count > 0)
        {
            // Every agy in this folder already has a Claude: saying "run agy first" would start a redundant one.
            foreach (var s in all)
                fx.Error.WriteLine(AlreadyTaken(s.SessionId));
            return null;
        }
        if (waiting.Count == 0)
        {
            fx.Error.WriteLine($"clavity: no agy session is waiting in {folder}. Run `clavity-ls agy {Launcher.ShQuote(folder)}` in another terminal first.");
            return null;
        }
        fx.Error.WriteLine($"clavity: {waiting.Count} agy sessions are waiting in {folder} - choose one:");
        foreach (var s in waiting)
            fx.Error.WriteLine($"    clavity-ls start {Launcher.ShQuote(folder)} --attach {s.SessionId}   " +
                               $"({(s.Paired ? "paired" : "starting")}, since {s.StartedUtc:yyyy-MM-dd HH:mm:ss} UTC)");
        return null;
    }
```

  And, next to `MissingFolder` (line 50):

```csharp
    /// <summary>`start --attach` refusing a session another `start` already paired with (ROADMAP section 65).</summary>
    public static string AlreadyTaken(string sessionId) =>
        $"clavity: agy session {sessionId} already has a Claude - another `clavity-ls start --attach` is using it.";
```

  Also update the `Start` doc comment (line 100) to `[--attach [&lt;session-id&gt;]]`.

- [ ] **Step 8: Implement - `AttachHint`** (`PosixAgyTab.cs:202-205`):

```csharp
    public static string AttachHint(string folder, string sessionId) =>
        $"clavity: this terminal runs agy for session {sessionId}.\n" +
        "  In ANOTHER terminal, start Claude paired with it:\n" +
        $"    clavity-ls start {Launcher.ShQuote(folder)} --attach\n" +
        $"  (if more than one agy is waiting in that folder: --attach {sessionId})\n";
```

  and change `AttachHint_names_the_session_and_the_start_command` (`PosixAgyTabTests.cs:252-257`) to assert both
  `"    clavity-ls start '/repo' --attach\n"` and `"  (if more than one agy is waiting in that folder: --attach 11111111-2222-3333-4444-555555555555)\n"`.

- [ ] **Step 9: Implement - `RealStartEffects`** (`clavity-dotnet/src/Clavity.Cli/RealStartEffects.cs`), add:

```csharp
    public void WriteSessionFolder(string path, string folder) =>
        File.WriteAllText(path, folder + "\n", new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: false));

    public IReadOnlyList<WaitingSession> FindWaitingSessions(string folder) =>
        SessionRegistry.Find(UserProfile, folder, new SystemListeningPorts(), SessionLock.IsTaken);

    public IDisposable? TryTakeSession(SessionPaths paths) => SessionLock.TryTake(paths.Lock);

    public IDisposable HoldSessionAlive(SessionPaths paths) =>
        SessionLock.TryTake(paths.Alive) ?? throw new IOException($"cannot hold {paths.Alive}: another process holds it.");
```

- [ ] **Step 10: Run** `dotnet test tests/Clavity.Ls.Tests` - expected `Passed!`, Failed 0.
- [ ] **Step 11: Logic mutants (script-applied, one match, non-empty diff, restore), each must turn its named row red:**
  (a) `waiting.Count == 1` -> `waiting.Count >= 1` -> the several-sessions row; (a2) `all.Where(s => !s.Taken)` ->
  `all` -> `A_taken_session_is_not_one_of_the_choices`; (a3) drop the `all.Count > 0` branch ->
  `Attach_without_an_id_whose_only_session_is_taken...`; (b) remove `using` from `using var
  taken` (lock never released) -> the no-id row (`release` missing); (c) skip the `taken is null` check -> the
  held-lock theory; (d) `if (!start.Attach)` -> `if (start.AttachSessionId is null)` -> the no-id row; (e) drop
  `fx.WriteSessionFolder(...)` -> `Agy_records_its_folder...`; (f) the folder record written with `fx.CurrentDirectory`
  instead of `folder` -> the same row; (g) drop `using` from `using var alive` -> the two `Agy_...` order rows
  (`alive-release` missing); (h) move `HoldSessionAlive` after `WriteSessionFolder` -> the same rows.
- [ ] **Step 12: Commit** `git add` the six files; `git commit -m "feat(start): --attach without an id pairs with the one waiting agy; one Claude per agy (section 65)"`

### Task 6: README and ROADMAP

**Files:** `clavity-dotnet/README.md:70-83`; `clavity-dotnet/ROADMAP.md` (`### §65`, line 3712).

- [ ] **Step 1: README.** Replace the sentence at lines 72-73 (`... which runs agy in that terminal and prints the
  \`clavity-ls start <folder> --attach <session-id>\` to run in a second one.`) with:
  `... which runs agy in that terminal; in a second one, \`clavity-ls start <folder> --attach\` pairs Claude with it
  (add the session id agy's terminal prints if more than one agy is waiting in that folder). Over \`ssh -X\` (X11
  forwarding) DISPLAY is set, so \`start\` opens agy's terminal window on your own machine instead.`
  In the command reference (line 79) write `[--attach [<session-id>]]` and extend line 80-81: `--attach` starts Claude
  only, paired with the agy that \`clavity-ls agy\` started; without an id it picks the one agy waiting in that folder.
- [ ] **Step 2: ROADMAP §65.** Change the header status to `✅ **Fork 1 SHIPPED on Branch 19** (owner-approved scope,
  2026-10-03)` and append a `**Decision (2026-10-03):**` paragraph: Fork 1 (a) shipped as above; pairing code not
  built; Fork 2 deferred (the variable already survives a Language Server restart in agy's own environment, and the
  Windows `$env:` baking stays for `ANTIGRAVITY_PROJECT_ID` anyway); Fork 3 deferred (the `--mcp` intent problem, as in
  the plan's "Decided" block).
- [ ] **Step 3: Commit** `git add clavity-dotnet/README.md clavity-dotnet/ROADMAP.md` -
  `git commit -m "docs(start): --attach without an id; ssh -X; section 65 decision"`

### Task 7: Gates and the built binary over ssh

- [ ] **Step 1:** `dotnet build` (0 errors) · `dotnet test tests/Clavity.Ls.Tests` · `dotnet test tests/Clavity.Integration.Tests`
  (read both `Total:` lines) · `lefthook run pre-commit --all-files` from the repo root.
- [ ] **Step 2: VM E2E** (Ubuntu `192.168.1.8`, published `linux-x64` single-file at `/tmp/clv-b18/clavity-ls`). A
  stand-in `agy` on PATH writes `{"csrf":"t","addr":"127.0.0.1:47123"}` to `$CLAVITY_AGY_ENDPOINT` and serves port 47123
  (`python3 -m http.server 47123 --bind 127.0.0.1`); a stand-in `claude` prints `$CLAVITY_SESSION_ID` and sleeps 5 s.
  Measure, each with its exit code: (1) `clavity-ls agy ws </dev/null &` then `clavity-ls start ws --attach` -> pairs
  with that session, prints its id, Claude sees it; (2) a second `start ws --attach` while (1)'s Claude runs ->
  "already has a Claude", exit 1; (3) after agy is stopped (`.exited` written) -> "no agy session is waiting", exit 1;
  (4) two `clavity-ls agy ws` -> the list of two, exit 1; (5) `kill -9` the `clavity-ls agy` process (its stand-in
  agy may live on) -> "no agy session is waiting", exit 1 - the `.alive` lock went with it. First check
  `command -v python3` on the VM; if absent, serve the port with `nc -l 47123` (or whatever listener exists - name it in
  the run report). Write the script as a FILE (Write tool), never a here-doc.
- [ ] **Step 3:** Update the execution index (memory) with every commit sha.
