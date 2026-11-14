// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



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
