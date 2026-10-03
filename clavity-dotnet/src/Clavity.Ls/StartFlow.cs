using System.ComponentModel;

namespace Clavity.Ls;

/// <summary>What <see cref="StartFlow"/> does to the world, behind one seam so the ORDER of the `start` and `agy` verbs
/// and their exit codes are unit-testable (Branch 18 test audit, owner-scoped; AGY-FIRST: extract and inject). The real
/// implementation lives in Clavity.Cli; each member is a thin call into an already-tested building block or the OS.</summary>
public interface IStartEffects
{
    bool IsWindows { get; }
    TextWriter Error { get; }
    string UserProfile { get; }
    string CurrentDirectory { get; }
    string NewSessionId();
    bool DirectoryExists(string path);
    void CreateDirectory(string path);
    /// <summary><see cref="LogRetention.Prune"/> with the default age, now.</summary>
    void PruneLogs(string logsDir);
    string? ReadProjectId(string agyHome);
    /// <summary>True when <paramref name="exe"/> is a file in a PATH directory (<see cref="PosixAgyTab.FindOnPath"/>).</summary>
    bool OnPath(string exe);
    /// <summary>True when a bare-name start of Claude would find it: on Windows `claude.exe` in the order process creation
    /// searches; elsewhere `claude` on PATH.</summary>
    bool ClaudeFindable();
    /// <summary><see cref="PairingDoc.Materialize"/>; throws what it throws.</summary>
    string MaterializePairingDoc(string dir);
    void WriteScript(string path, string content);
    /// <summary>Opens a terminal that runs this session's agy script; false when none started it in time.</summary>
    bool OpenPosixTerminal(SessionPaths paths, string folder);
    /// <summary><see cref="PairingWait.WaitForEndpoint"/> on a real clock; false when agy ended before pairing.</summary>
    bool WaitForPairing(SessionPaths paths);
    /// <summary>Starts <paramref name="cmd"/>; with <paramref name="wait"/> returns its exit code, else 0. Throws
    /// <see cref="Win32Exception"/> when the program cannot be started at all.</summary>
    int Run(LaunchCommand cmd, bool wait);
    bool InputRedirected { get; }
    void WaitForEnter();
    /// <summary>Runs the agy script with `/bin/sh &lt;script&gt; --here` in this terminal and returns its exit code.</summary>
    int RunScriptHere(string scriptPath);
    /// <summary>Writes the `.folder` record that lets `start --attach` without an id find this session (ROADMAP section 65).</summary>
    void WriteSessionFolder(string path, string folder);
    /// <summary><see cref="SessionRegistry.Find"/> over the real files, listening ports and locks; null = every folder.</summary>
    IReadOnlyList<WaitingSession> FindWaitingSessions(string? folder);
    /// <summary>The folder this session's `.folder` record names, or null when it has none (or it cannot be read).</summary>
    string? ReadSessionFolder(SessionPaths paths);
    /// <summary><see cref="SessionLock.TryTake"/> on this session's lock: null when another `start` holds it.</summary>
    IDisposable? TryTakeSession(SessionPaths paths);
    /// <summary>Holds this session's `.alive` lock for as long as `clavity-ls agy` runs it (<see cref="SessionLock.TryTake"/>;
    /// the id is fresh, so nobody else can hold it).</summary>
    IDisposable HoldSessionAlive(SessionPaths paths);
}

/// <summary>The `clavity-ls start` and `clavity-ls agy` verbs. Exit codes: 2 for a bad argument or a missing folder, 1 for a
/// refusal (a program missing, no terminal, agy ended before pairing), otherwise Claude's (or the agy script's) own.</summary>
public static class StartFlow
{
    public const string AgyNotOnPath =
        "clavity: agy is not on PATH - install Antigravity's agy CLI, or add its directory to PATH, then retry.";

    /// <summary>Both verbs' refusal of a folder argument that is not a directory - missing, or a FILE (capstone R8: "does
    /// not exist" was false for a file).</summary>
    public static string MissingFolder(string folder) => $"clavity: {folder} does not exist or is not a folder.";

    /// <summary>`start --attach` refusing a session another `start` already paired with (ROADMAP section 65).</summary>
    public static string AlreadyTaken(string sessionId) =>
        $"clavity: agy session {sessionId} already has a Claude - another `clavity-ls start --attach` is using it.";

    /// <summary>`clavity-ls agy [folder]` (Linux/macOS) - run a new session's agy in THIS terminal, for when `start` cannot
    /// open one (no display, or no terminal it knows). It prints the `start --attach` command for a second terminal.
    /// <paramref name="args"/> are the arguments after the verb.</summary>
    public static int Agy(string[] args, IStartEffects fx)
    {
        if (fx.IsWindows)
        {
            fx.Error.WriteLine("clavity: `clavity-ls agy` is for Linux and macOS - on Windows, `clavity-ls start` opens agy in a Windows Terminal tab.");
            return 2;
        }
        var folder = args.Length > 0 ? Path.GetFullPath(args[0], fx.CurrentDirectory) : fx.CurrentDirectory;
        if (!fx.DirectoryExists(folder))
        {
            fx.Error.WriteLine(MissingFolder(folder));
            return 2;
        }
        var home = fx.UserProfile;
        var session = fx.NewSessionId();
        var paths = SessionPaths.For(home, session);
        fx.CreateDirectory(Path.GetDirectoryName(paths.AgyLog)!);
        if (!fx.OnPath("agy"))
        {
            fx.Error.WriteLine(AgyNotOnPath);
            return 1;
        }
        if (TryMaterialize(fx, paths) is not { } doc)
            return 1;
        fx.WriteScript(paths.AgyScript, Launcher.BuildPosixScript(new LaunchOptions
        {
            Folder = folder,
            SessionId = session,
            ProjectId = fx.ReadProjectId(Path.Combine(home, ".gemini", "antigravity-cli")),
            AgyLogFilePath = paths.AgyLog,
            AgyEndpointFilePath = paths.Endpoint,
            SkipPermissions = true,
            AgyInstallDocPath = doc,
        }, paths.Claim, paths.Exited));
        // `start --attach` without an id finds this session through its folder record, and counts it only while this
        // process holds .alive - taken FIRST, so a record never exists without a live holder (ROADMAP section 65).
        using var alive = fx.HoldSessionAlive(paths);
        fx.WriteSessionFolder(paths.Folder, folder);

        // agy's full-screen interface takes this terminal over, so the command must be read BEFORE it starts.
        fx.Error.Write(PosixAgyTab.AttachHint(folder, session));
        if (!fx.InputRedirected)
        {
            fx.Error.Write("  Press Enter to start agy here.");
            fx.WaitForEnter();
        }
        return fx.RunScriptHere(paths.AgyScript);
    }

    /// <summary>`clavity-ls start [folder] [--attach [&lt;session-id&gt;]] [claude-args...]` - open a visible human-owned agy tab
    /// (per-session LS log) + launch Claude. With --attach, launch Claude only, paired with the agy `clavity-ls agy`
    /// started - without an id, the one waiting in the folder. <paramref name="args"/> are the arguments after the verb.</summary>
    public static int Start(string[] args, IStartEffects fx)
    {
        StartArgs start;
        try
        {
            start = StartArgs.Parse(args, fx.CurrentDirectory);
        }
        catch (ArgumentException ex)
        {
            fx.Error.WriteLine($"clavity: {ex.Message}");
            return 2;
        }
        var folder = start.Folder;
        // Before anything else, on every platform and for --attach (capstone R7): Windows used to go on and fail at the
        // tab's working directory with "cannot start Windows Terminal ... winget install", and --attach waited for a
        // pairing only to fail starting Claude there. On Linux the script's `cd` runs after its claim, so a missing
        // folder would also look like success.
        if (!fx.DirectoryExists(folder))
        {
            fx.Error.WriteLine(MissingFolder(folder));
            return 2;
        }

        // An explicit id may name an agy in ANOTHER folder (or this one by another path). Claude in one folder and agy in
        // another is a split brain, so Claude starts where agy runs (capstone R1, AGY-FIRST, owner-approved) - decided
        // here, before the git-repository warning, so the warning checks the folder Claude really uses (capstone R2).
        if (start.AttachSessionId is { } givenId
            && fx.ReadSessionFolder(SessionPaths.For(fx.UserProfile, givenId)) is { } agyFolder
            && !SessionRegistry.SameFolder(agyFolder, folder))
        {
            if (!fx.DirectoryExists(agyFolder))
            {
                fx.Error.WriteLine(MissingFolder(agyFolder));
                return 2;
            }
            fx.Error.WriteLine($"clavity: agy session {givenId} runs in {agyFolder} - starting Claude there, not in {folder}.");
            folder = agyFolder;
        }

        if (!fx.DirectoryExists(Path.Combine(folder, ".git")))
            fx.Error.WriteLine($"clavity: warning — {folder} is not a git repository.");

        var agyHome = Path.Combine(fx.UserProfile, ".gemini", "antigravity-cli");
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

        // The pairing doc is embedded in this binary and written out on every start (PairingDoc). Without it agy gets
        // no -i prompt, never publishes its endpoint, and the pairing is dead on arrival - so refuse, loudly, rather
        // than launch a half-working session (the old install-root lookup failed SILENTLY on every non-Inno install).
        if (TryMaterialize(fx, paths) is not { } agyInstallDoc)
            return 1;

        var options = new LaunchOptions
        {
            Folder = folder,
            SessionId = sessionId,
            ClaudeArgs = start.ClaudeArgs,
            ProjectId = fx.ReadProjectId(agyHome),
            AgyLogFilePath = paths.AgyLog,
            AgyEndpointFilePath = paths.Endpoint,
            // User decision 2026-06-30: agy ALWAYS launches with --dangerously-skip-permissions so unattended
            // bus/LS consults never stall on per-tool approval prompts. (Supersedes spec §4 "NOT default".)
            SkipPermissions = true,
            AgyInstallDocPath = agyInstallDoc,
            AgyExitedFilePath = paths.Exited,
            WindowsShell = Launcher.PickWindowsShell(fx.OnPath),
        };
        var plan = Launcher.Build(options);

        if (fx.IsWindows)
        {
            if (!ClaudeIsStartable(fx))            // before the tab: a missing claude must not leave an agy behind
                return 1;
            if (Spawn(fx, plan.AgyTab, wait: false) is null)  // agy tab boots asynchronously; human owns it.
                return 1;
            if (!fx.WaitForPairing(paths))          // Claude starts only once agy has published its endpoint.
                return 1;
            return RunClaude(fx, plan.ClaudeLaunch);  // Claude runs in the foreground.
        }

        // Linux / macOS (ROADMAP sections 60 + 62): there is no `wt`. Open agy from a generated POSIX script in a terminal
        // the user can see, and start Claude only once a terminal really ran it - otherwise Claude's full-screen interface
        // would hide the reason pairing never happens.
        // Check BOTH programs before opening anything: a missing `claude` found only after agy's tab is up would leave
        // an orphaned agy behind.
        if (!fx.OnPath("agy"))
        {
            fx.Error.WriteLine(AgyNotOnPath);
            return 1;
        }
        if (!ClaudeIsStartable(fx))
            return 1;
        fx.WriteScript(paths.AgyScript, Launcher.BuildPosixScript(options, paths.Claim, paths.Exited));
        if (!fx.OpenPosixTerminal(paths, folder))
        {
            fx.Error.Write(PosixAgyTab.FallbackMessage(folder));
            return 1;
        }
        // Owner request 2026-10-03: the user sees agy - and any prompt it waits on - before Claude takes the terminal.
        if (!fx.WaitForPairing(paths))
            return 1;
        return RunClaude(fx, plan.ClaudeLaunch);
    }

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
            // Every agy in this folder already has a Claude. Say so first ("run agy first" alone would hide that), then
            // what to do for ANOTHER Claude.
            foreach (var s in all)
                fx.Error.WriteLine(AlreadyTaken(s.SessionId));
            fx.Error.WriteLine($"clavity: for another Claude in this folder, run `clavity-ls agy {Launcher.ShQuote(folder)}` in a new terminal first.");
            return null;
        }
        if (waiting.Count == 0)
        {
            // Nothing here - but the same folder reached through a symlink does not compare equal (capstone R1, measured),
            // so before saying "run agy first", list what waits ANYWHERE, with commands that work as they are.
            var elsewhere = fx.FindWaitingSessions(null).Where(s => !s.Taken).ToList();
            if (elsewhere.Count > 0)
            {
                var folders = elsewhere.Select(s => s.Folder).Distinct(StringComparer.Ordinal).Count();
                fx.Error.WriteLine($"clavity: no agy session is waiting in {folder}, but {elsewhere.Count} " +
                                   $"{(elsewhere.Count == 1 ? "is" : "are")} waiting in {(folders == 1 ? "another folder" : "other folders")} " +
                                   "(the same folder through a symlink shows up here too):");
                foreach (var s in elsewhere)
                    fx.Error.WriteLine(ChoiceLine(s.Folder, s));
                return null;
            }
            fx.Error.WriteLine($"clavity: no agy session is waiting in {folder}. Run `clavity-ls agy {Launcher.ShQuote(folder)}` in another terminal first.");
            return null;
        }
        fx.Error.WriteLine($"clavity: {waiting.Count} agy sessions are waiting in {folder} - choose one:");
        foreach (var s in waiting)
            fx.Error.WriteLine(ChoiceLine(folder, s));
        return null;
    }

    // One pasteable command per session; its state is a shell COMMENT, so a whole copied line runs as just the command
    // (capstone R1: a trailing "(paired, ...)" was copied along with it).
    private static string ChoiceLine(string folder, WaitingSession s) =>
        $"    clavity-ls start {Launcher.ShQuote(folder)} --attach {s.SessionId}   " +
        $"# {(s.Paired ? "paired" : "starting")}, since {s.StartedUtc:yyyy-MM-dd HH:mm:ss} UTC";

    private static string? TryMaterialize(IStartEffects fx, SessionPaths paths)
    {
        try
        {
            return fx.MaterializePairingDoc(Path.GetDirectoryName(paths.Endpoint)!);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            fx.Error.WriteLine($"clavity: cannot write the agy pairing instructions ({ex.Message}) - not launching.");
            return null;
        }
    }

    // Mirrors what Spawn can start (see IStartEffects.ClaudeFindable).
    private static bool ClaudeIsStartable(IStartEffects fx)
    {
        if (fx.ClaudeFindable())
            return true;
        var exe = fx.IsWindows ? "claude.exe" : "claude";
        fx.Error.WriteLine(Launcher.CannotStartMessage("claude", $"{exe} is not on PATH"));
        return false;
    }

    // Claude, after agy is already up: `start` exits with Claude's own exit code (capstone R5); if Claude cannot start
    // after all, say that agy is still running.
    private static int RunClaude(IStartEffects fx, LaunchCommand claude)
    {
        if (Spawn(fx, claude, wait: true) is { } exitCode)
            return exitCode;
        fx.Error.WriteLine("clavity: agy is still running - close its tab (or press Ctrl+C in its terminal).");
        return 1;
    }

    // Null, with the reason printed, when the program cannot be started at all (not installed / not on PATH);
    // otherwise its exit code when waited for, else 0.
    private static int? Spawn(IStartEffects fx, LaunchCommand cmd, bool wait)
    {
        try
        {
            return fx.Run(cmd, wait);
        }
        catch (Win32Exception ex)
        {
            fx.Error.WriteLine(Launcher.CannotStartMessage(cmd.FileName, ex.Message));
            return null;
        }
    }
}
