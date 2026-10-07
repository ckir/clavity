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
        ReplyCaptureDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".clavity", "agy-replies"),
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
    return StartFlow.Agy(args.Skip(1).ToArray(), new Clavity.Cli.RealStartEffects());

// `clavity start [folder] [--attach <session-id>] [claude-args...]` - open a visible human-owned agy tab (per-session
// LS log) + launch Claude. With --attach, launch Claude only, paired with the agy `clavity-ls agy` started. The order and
// the exit codes live in StartFlow (unit-tested); RealStartEffects is the thin OS side.
if (args.Length > 0 && args[0] == "start")
    return StartFlow.Start(args.Skip(1).ToArray(), new Clavity.Cli.RealStartEffects());

Console.WriteLine("clavity-ls — usage: clavity-ls start [folder] [--attach <session-id>] [claude-args...]   |   clavity-ls agy [folder]   (Linux/macOS: agy in this terminal)   |   clavity-ls --mcp   (MCP stdio server: agy_look / agy_status / agy_ask)");
return 0;
