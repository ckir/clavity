// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Diagnostics;
using Clavity.Ls;
using Clavity.Mcp;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

// `--mcp` is the sole argument the plugin's .mcp.json passes; testing only the first keeps a `start ... --mcp` (a Claude
// pass-through argument) from turning the CLI into the MCP host.
if (args.Length > 0 && args[0] == "--mcp")
{
    // Hold a named mutex for the host's lifetime so the installer's PrepareToInstall can detect a live
    // pairing session (Component B/D) without WMI. Local\ scopes it to this logon session (D1).
    using var liveSessionMutex = new System.Threading.Mutex(initiallyOwned: true, @"Local\ClavityMcpRunning", out _);

    var agyDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".gemini", "antigravity-cli");
    var installRoot = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    var manualsDir = EscalationIndex.ResolveManualsDir(
        Environment.GetEnvironmentVariable(EscalationIndex.PluginRootVar), installRoot);
    var userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
    if (!string.IsNullOrWhiteSpace(userProfile))
    {
        try { LogRetention.Prune(Path.Combine(userProfile, ".clavity", "logs"), LogRetention.DefaultMaxAge, DateTime.UtcNow); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { /* an unreadable dir must not stop the server */ }
    }
    var events = new LsEventLog(
        Console.Error,
        LsEventLog.ResolveSink(
            Environment.GetEnvironmentVariable(LsEventLog.LogVar),
            userProfile,
            Environment.GetEnvironmentVariable(AgyEnvironment.SessionIdVar),
            Environment.ProcessId));
    var options = new AgyViewOptions
    {
        Events = events,
        CliLogPath = AgyEnvironment.ResolveCliLogPath(
            Environment.GetEnvironmentVariable(AgyEnvironment.LogPathVar), agyDir),
        GoldenHeaderDir = GoldenHeader.ResolveDir(
            Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)),
        EscalationIndex = Clavity.Ls.EscalationIndex.Build(manualsDir),   // built ONCE here (R-V2)
        IdleStallWindow = AgyEnvironment.ResolveSeconds(
            Environment.GetEnvironmentVariable(AgyEnvironment.IdleStallSecondsVar),
            AgyView.DefaultIdleWaitTimeout),
        GenerationCap = AgyEnvironment.ResolveSeconds(
            Environment.GetEnvironmentVariable(AgyEnvironment.GenerationCapSecondsVar),
            TimeSpan.FromSeconds(600), allowZero: true),
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
    McpTools.WarmParameterCache();
    builder.Services
        .AddMcpServer()
        .WithStdioServerTransport()
        .WithTools<McpTools>()
        // ROADMAP section 71 (b): refuse a call whose argument names do not match the tool's schema with a sentence that
        // says which, instead of the SDK's generic "An error occurred invoking". Runs before the SDK binds arguments.
        .WithRequestFilters(f => f.AddCallToolFilter(ArgumentPrecheck.For(events)));

    await builder.Build().RunAsync();
    return 0;
}

// `clavity-ls --version` - which build is installed (a stale client was once blamed on a healthy peer).
if (args.Length == 1 && args[0] is "--version" or "-V")
{
    Console.WriteLine(CliVerbs.VersionLine());
    return 0;
}

// `clavity-ls --help` / `<verb> --help` - BEFORE any verb dispatch, so `install --help` prints help instead of installing.
if (CliVerbs.IsHelpRequest(args))
{
    Console.WriteLine(CliVerbs.HelpText());
    return 0;
}

// `clavity-ls curate-commit [--cheatsheet]` — atomically write a compiled region (read from stdin) to the shared path.
if (args.Length > 0 && args[0] == "curate-commit")
{
    if (!CliVerbs.TryParseCurateCommitArgs(args, out var cheatsheet, out var argError))
    {
        Console.Error.WriteLine(argError);
        return 2;
    }
    var dir = GoldenHeader.ResolveDir(
        Environment.GetEnvironmentVariable(GoldenHeader.PathVar),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
    // The raw STREAM, never Console.In: Console.In decodes via the console's OEM input code page (CP437 on
    // Windows), which silently corrupted the header on the way in. CurateCommit takes a Stream precisely so
    // this call site cannot choose a decoder at all — see its doc comment.
    using var stdin = Console.OpenStandardInput();
    return CliVerbs.CurateCommit(dir, stdin, Console.Error, cheatsheet);
}

if (Clavity.Ls.Install.CliRouter.IsInstallerVerb(args))
{
    return Clavity.Ls.Install.CliRouter.Run(args, Console.Out);
}

// `clavity-ls agy [folder]` (Linux/macOS) - run a new session's agy in THIS terminal, for when `start` cannot open
// one (no display, or no terminal it knows). It prints the `start --attach` command for a second terminal.
if (args.Length > 0 && args[0] == "agy")
    return StartFlow.Agy(args.Skip(1).ToArray(), new Clavity.Cli.RealStartEffects());

// `clavity start [folder] [--attach <session-id>] [--profile <name>] [claude-args...]` - open a visible human-owned agy tab (per-session
// LS log) + launch Claude. With --attach, launch Claude only, paired with the agy `clavity-ls agy` started. The order and
// the exit codes live in StartFlow (unit-tested); RealStartEffects is the thin OS side.
if (args.Length > 0 && args[0] == "start")
    return StartFlow.Start(args.Skip(1).ToArray(), new Clavity.Cli.RealStartEffects());

Console.WriteLine(CliVerbs.HelpText());
return 0;
