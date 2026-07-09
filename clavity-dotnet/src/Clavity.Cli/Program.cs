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
    var options = new AgyViewOptions
    {
        CliLogPath = AgyEnvironment.ResolveCliLogPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.LogPathVar), agyDir),
        GoldenHeaderPath = GoldenHeader.ResolvePath(
            Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
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
    return 0;
}

// `clavity-ls curate-commit` — atomically write the compiled golden-header (read from stdin) to the shared path.
if (args.Length > 0 && args[0] == "curate-commit")
{
    var headerPath = GoldenHeader.ResolvePath(
        Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    return CliVerbs.CurateCommit(headerPath, Console.In, Console.Error);
}

if (Clavity.Ls.Install.CliRouter.IsInstallerVerb(args))
{
    return Clavity.Ls.Install.CliRouter.Run(args, Console.Out);
}

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
        // User decision 2026-06-30: agy ALWAYS launches with --dangerously-skip-permissions so unattended
        // bus/LS consults never stall on per-tool approval prompts. (Supersedes spec §4 "NOT default".)
        SkipPermissions = true,
    });

    Spawn(plan.AgyTab, wait: false);    // agy tab boots asynchronously; human owns it.
    Spawn(plan.ClaudeLaunch, wait: true); // Claude runs in the foreground.
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

    static string? TryReadProjectId(string agyHome)
    {
        var path = Path.Combine(agyHome, "cache", "default_project_id.txt");
        if (!File.Exists(path))
            return null;
        var id = File.ReadAllText(path).Trim();
        return id.Length > 0 ? id : null;
    }
}

Console.WriteLine("clavity-ls — usage: clavity-ls start <folder> [claude-args...]   |   clavity-ls --mcp   (MCP stdio server: agy_look / agy_status / agy_ask)");
return 0;
