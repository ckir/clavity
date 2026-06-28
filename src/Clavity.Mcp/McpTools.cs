using System.ComponentModel;
using System.Text.Json;
using Clavity.Ls;
using ModelContextProtocol.Server;

namespace Clavity.Mcp;

/// <summary>MCP tools exposing a read-only, size-bounded "look" at the live agy session over its Language Server.</summary>
[McpServerToolType]
public class McpTools
{
    [McpServerTool(Name = "agy_look"), Description("Look at the active agy conversation's cascade trajectory as a size-bounded JSON summary (no verbose ids).")]
    public static async Task<string> AgyLook(AgyView view, CancellationToken cancellationToken = default)
    {
        var bounded = await view.LookAsync(cancellationToken: cancellationToken);
        return JsonSerializer.Serialize(bounded);
    }

    [McpServerTool(Name = "agy_status"), Description("Report the active agy conversation's status: cascade id, total steps, and whether the look was truncated.")]
    public static async Task<string> AgyStatus(AgyView view, CancellationToken cancellationToken = default)
    {
        var bounded = await view.LookAsync(cancellationToken: cancellationToken);
        return JsonSerializer.Serialize(new { bounded.CascadeId, bounded.TotalSteps, bounded.Truncated });
    }

    [McpServerTool(Name = "agy_ask"), Description("Send a message to the active agy conversation and return agy's reply (size-bounded JSON) once the conversation goes idle. WRITE: consumes quota and posts a visible message in the user's agy.")]
    public static async Task<string> AgyAsk(AgyView view, string message, CancellationToken cancellationToken = default)
    {
        var bounded = await view.AskAsync(message, cancellationToken: cancellationToken);
        return JsonSerializer.Serialize(bounded);
    }
}
