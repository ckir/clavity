using System.ComponentModel;
using System.Text.Json;
using Clavity.Ls;
using ModelContextProtocol.Server;

namespace Clavity.Mcp;

/// <summary>MCP tools exposing a read-only, size-bounded "look" + an "ask" over agy's Language Server.</summary>
[McpServerToolType]
public class McpTools
{
    [McpServerTool(Name = "agy_look"), Description("Look at the active agy conversation's cascade trajectory as a size-bounded JSON summary (no verbose ids).")]
    public static async Task<string> AgyLook(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.LookAsync(cancellationToken: cancellationToken));

    [McpServerTool(Name = "agy_status"), Description("Report the active agy conversation's status: cascade id, total steps, and whether the look was truncated.")]
    public static async Task<string> AgyStatus(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(async () =>
        {
            var bounded = await view.LookAsync(cancellationToken: cancellationToken);
            return (object)new { bounded.CascadeId, bounded.TotalSteps, bounded.Truncated };
        });

    [McpServerTool(Name = "agy_ask"), Description("Send a message to the active agy conversation and return agy's reply (size-bounded JSON) once the conversation goes idle. WRITE: consumes quota and posts a visible message in the user's agy.")]
    public static async Task<string> AgyAsk(AgyView view, string message, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.AskAsync(message, cancellationToken: cancellationToken));

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
