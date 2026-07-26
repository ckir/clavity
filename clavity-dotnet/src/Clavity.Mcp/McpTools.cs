using System.Collections.Generic;
using System.ComponentModel;
using System.Text.Json;
using Clavity.Ls;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;

namespace Clavity.Mcp;

/// <summary>MCP tools exposing a read-only, size-bounded "look" + an "ask" over agy's Language Server.</summary>
[McpServerToolType]
public class McpTools
{
    [McpServerTool(Name = "agy_look"), Description("Look at the active agy conversation's cascade trajectory as a size-bounded JSON summary (no verbose ids).")]
    public static async Task<string> AgyLook(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.LookAsync(cancellationToken: cancellationToken));

    [McpServerTool(Name = "agy_status"), Description("Report whether the active agy conversation is idle, working, or unknown (pre-fire check), plus cascade id and step count.")]
    public static async Task<string> AgyStatus(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.StatusAsync(cancellationToken));

    [McpServerTool(Name = "agy_ask"), Description("Send a message to the active agy conversation and return agy's reply (size-bounded JSON) once the conversation goes idle. WRITE: consumes quota and posts a visible message in the user's agy.")]
    public static async Task<CallToolResult> AgyAsk(AgyView view, string message, CancellationToken cancellationToken = default)
    {
        var json = await RunAsync(() => view.AskAsync(message, cancellationToken: cancellationToken));
        var blocks = new List<ContentBlock> { new TextContentBlock { Text = json } };
        var guidance = view.TryTakeGuidanceBlock();
        if (guidance is not null) blocks.Add(new TextContentBlock { Text = guidance });
        return new CallToolResult { Content = blocks };
    }

    // Serialize the result, or — when agy has no conversation yet — a typed "waiting" object that tells Claude to
    // wait for the human and NOT auto-retry (spec §6).
    private static async Task<string> RunAsync<T>(Func<Task<T>> action)
    {
        try
        {
            return JsonSerializer.Serialize(await action());
        }
        catch (AgyModalHangException ex)
        {
            return JsonSerializer.Serialize(new
            {
                status = "possible_modal",
                operation = ex.Report.Operation,
                elapsedSeconds = ex.Report.Elapsed.TotalSeconds,
                limit = ex.Report.Limit,
                hint = ex.Report.Hint,
                diagnostic = ex.Diagnostic,   // where agy stopped: slow tool vs hang (null if not computed).
            });
        }
        catch (AgyConversationPendingException ex)
        {
            return JsonSerializer.Serialize(new { status = "waiting_for_human", message = ex.Message });
        }
    }
}
