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
        ConversationsDir = Path.Combine(agyDir, "conversations"),
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

Console.WriteLine("clavity — usage: clavity --mcp   (MCP stdio server exposing agy_look / agy_status)");
