using System.Diagnostics;
using Clavity.Ls;
using Clavity.Mcp;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

if (args.Contains("--mcp"))
{
    // Hold a named mutex for the host's lifetime so the installer's PrepareToInstall can detect a live
    // pairing session (Component B/D) without WMI. Local\ scopes it to this logon session (D1).
    using var liveSessionMutex = new System.Threading.Mutex(initiallyOwned: true, @"Local\ClavityMcpRunning", out _);

    var agyDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".gemini", "antigravity-cli");
    var installRoot = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    var manualsDir = Path.Combine(installRoot, "plugins", Clavity.Ls.Install.PluginInstaller.PluginName, "knowledge");
    var options = new AgyViewOptions
    {
        CliLogPath = AgyEnvironment.ResolveCliLogPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.LogPathVar), agyDir),
        GoldenHeaderDir = GoldenHeader.ResolveDir(
            Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
        EscalationIndex = Clavity.Ls.EscalationIndex.Build(manualsDir),   // built ONCE here (R-V2)
        IdleStallWindow = AgyEnvironment.ResolveSeconds(
            Environment.GetEnvironmentVariable(AgyEnvironment.IdleStallSecondsVar),
            AgyView.DefaultIdleWaitTimeout),
        IdleAbsoluteMax = AgyEnvironment.ResolveSeconds(
            Environment.GetEnvironmentVariable(AgyEnvironment.IdleMaxSecondsVar),
            TimeSpan.FromSeconds(600), allowZero: true),
        EndpointPath = AgyEnvironment.ResolveEndpointPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.EndpointPathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
    };

    var ghOverride = Environment.GetEnvironmentVariable(GoldenHeader.PathVar);
    if (!string.IsNullOrWhiteSpace(ghOverride) && (File.Exists(ghOverride) || Path.HasExtension(ghOverride)))
        Console.Error.WriteLine(
            $"clavity: {GoldenHeader.PathVar} now names a DIRECTORY, but '{ghOverride}' looks like a file — " +
            "point it at the .clavity directory instead.");

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
    return 0;
}

// `clavity-ls curate-commit` — atomically write the compiled golden-header (read from stdin) to the shared path.
if (args.Length > 0 && args[0] == "curate-commit")
{
    var dir = GoldenHeader.ResolveDir(
        Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    // The raw STREAM, never Console.In: Console.In decodes via the console's OEM input code page (CP437 on
    // Windows), which silently corrupted the header on the way in. CurateCommit takes a Stream precisely so
    // this call site cannot choose a decoder at all — see its doc comment.
    using var stdin = Console.OpenStandardInput();
    return CliVerbs.CurateCommit(dir, stdin, Console.Error);
}

if (Clavity.Ls.Install.CliRouter.IsInstallerVerb(args))
{
    return Clavity.Ls.Install.CliRouter.Run(args, Console.Out);
}

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

Console.WriteLine("clavity-ls — usage: clavity-ls start [folder] [--attach <session-id>] [claude-args...]   |   clavity-ls agy [folder]   (Linux/macOS: agy in this terminal)   |   clavity-ls --mcp   (MCP stdio server: agy_look / agy_status / agy_ask)");
return 0;
