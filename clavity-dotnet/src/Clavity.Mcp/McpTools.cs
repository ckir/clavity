using System.Collections.Generic;
using System.ComponentModel;
using System.Text.Json;
using Clavity.Ls;
using ModelContextProtocol;
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
    public static async Task<CallToolResult> AgyAsk(
        AgyView view, string message, IProgress<ProgressNotificationValue> progress, CancellationToken cancellationToken = default)
    {
        // `progress` is SDK-INJECTED and does NOT appear in the tool's input schema — verified against the generated
        // InputSchema, which stays {"properties":{"message":...},"required":["message"]}. So this costs no contract
        // change, exactly like the DI-injected `view` and the `cancellationToken` beside it. When the client sends no
        // progressToken the SDK's reporter is a no-op, so an ask is never worse off for reporting.
        //
        // Progress carries `window`, NOT a step count: the MCP contract requires the reported value to increase with
        // every notification, and a window that elapses while agy produced nothing leaves the step count unchanged.
        // The step counts go in the message, where they are informative without having to be monotonic.
        var relay = new RelayProgress(p => progress.Report(new ProgressNotificationValue
        {
            Progress = p.Window,
            Message = $"agy working — {p.NewSteps} new step(s), {p.TotalSteps} total, {p.Elapsed.TotalSeconds:F0}s elapsed",
        }));
        var json = await RunAsync(() => view.AskAsync(message, progress: relay, cancellationToken: cancellationToken));
        var blocks = new List<ContentBlock> { new TextContentBlock { Text = json } };
        var guidance = view.TryTakeGuidanceBlock();
        if (guidance is not null) blocks.Add(new TextContentBlock { Text = guidance });
        return new CallToolResult { Content = blocks };
    }

    /// <summary>Relays <see cref="AgyWaitProgress"/> synchronously. Deliberately NOT <see cref="Progress{T}"/>:
    /// with no SynchronizationContext (which is the case in this stdio host) <c>Progress&lt;T&gt;</c> queues each
    /// callback to the thread pool, so reports can be delivered OUT OF ORDER — and a progress sequence whose values
    /// must increase is precisely the thing that must not be reordered. A direct synchronous call preserves the
    /// order the wait loop produced them in.</summary>
    private sealed class RelayProgress(Action<AgyWaitProgress> onReport) : IProgress<AgyWaitProgress>
    {
        public void Report(AgyWaitProgress value) => onReport(value);
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
        catch (Exception ex) when (ChannelDown.IsChannelDown(ex))
        {
            var diag = ChannelDown.Diagnose(ex);
            return JsonSerializer.Serialize(new
            {
                status = ChannelDown.StatusFor(diag),
                diagnostic = diag,
                hint = ChannelDown.Hint(diag),
            });
        }
    }
}
