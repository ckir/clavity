using System.Diagnostics;
using Clavity.Ls;
using Clavity.Mcp;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

if (args.Contains("--mcp"))
{
    var agyDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".gemini", "antigravity-cli");
    var options = new AgyViewOptions
    {
        CliLogPath = Path.Combine(agyDir, "cli.log"),
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
    return;
}

// `clavity start <folder> [claude-args...]` — open a visible human-owned agy tab + launch Claude in <folder>.
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

    var plan = Launcher.Build(new LaunchOptions
    {
        Folder = folder,
        ClaudeArgs = claudeArgs,
        ProjectId = TryReadProjectId(agyHome),
        AgyLogFilePath = Path.Combine(agyHome, "cli.log"),
        SkipPermissions = false,
    });

    Spawn(plan.AgyTab, wait: false);    // agy tab boots asynchronously; human owns it.
    Spawn(plan.ClaudeLaunch, wait: true); // Claude runs in the foreground.
    return;

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

Console.WriteLine("clavity — usage: clavity start <folder> [claude-args...]   |   clavity --mcp   (MCP stdio server: agy_look / agy_status / agy_ask)");
