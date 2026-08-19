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
        AgyView view, string message, IProgress<ProgressNotificationValue> progress,
        string? discipline = null, string? expectEcho = null,
        CancellationToken cancellationToken = default)
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
        // THE INJECTION POINT. The caller names its discipline; the driver supplies the token. A caller
        // cannot mistype "[VERDICT:" into a silent opt-out, because it never types it.
        var expectTerminal = DisciplineContract.TerminalTokenFor(discipline);

        // CAPTURED PER CALL, never on the view. An earlier draft parked the evaluated reply on
        // AgyView.LastReply - but Program.cs:44 registers AgyView as a SINGLETON, so concurrent asks
        // would read each other's verdicts. Worse, it was wrong SINGLE-THREADED too: RunAsync converts a
        // failed ask into an error payload, leaving the previous ask's flags in place to be reported
        // against a reply that does not exist. A local stays null on that path, which is the correct
        // answer - no reply, no verdict. (Capstone R1, State Corruptor.)
        AskReply? reply13b = null;
        var json = await RunAsync(async () =>
        {
            var r = await view.AskAsync(message, progress: relay, expectTerminal: expectTerminal, expectEcho: expectEcho, cancellationToken: cancellationToken);
            reply13b = r;
            return r;
        });
        var blocks = new List<ContentBlock> { new TextContentBlock { Text = json } };
        var guidance = view.TryTakeGuidanceBlock();
        if (guidance is not null) blocks.Add(new TextContentBlock { Text = guidance });

        // 13b: the verdicts must REACH the caller. A flag nothing reads cannot stop a truncated review
        // being folded, which is the entire failure this step exists to end.
        //
        // These are if/else-if, not independent blocks. A truncated reply is usually also a small one,
        // and emitting several would make the deterministic verdicts compete with the heuristic for the
        // reader's attention. The deterministic ones win, strongest first.
        if (reply13b is { TerminalTokenMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] TRUNCATED REPLY: the terminal token this discipline requires is missing or "
                     + "not at the end. Treat this consult as INCOMPLETE - do not fold findings from it. "
                     + "Recover with agy_look or re-ask; never read it as 'no findings'."
            });
        }
        else if (reply13b is { EchoMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] ECHO MISSING: the peer did not quote the artifact's last line near its "
                     + "verdict, so it did not reach the end of what it was asked to read - or did not "
                     + "read it. Treat this consult as INCOMPLETE and do not fold findings from it."
            });
        }
        else if (reply13b is { SizeAnomaly: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] SIZE WARNING: this reply is far smaller than this peer's recent replies. "
                     + "That is a HEURISTIC, not proof - a genuine 'no findings' is legitimately short. "
                     + "Confirm the reply is complete before folding or accepting a clean verdict."
            });
        }

        // AN ECHO TARGET THAT CANNOT DISCRIMINATE IS NOT A CHECK. Independent of the verdicts above,
        // because it is a fact about the ASK, not about the reply - the same category as UNCHECKED.
        // (Capstone R1: the last non-blank line of any C# file is "}", which any peer can emit.)
        if (expectEcho is null)
        {
            // FAIL-OPEN, CLOSED. The weak-target check only fired when a target was SUPPLIED, so an ask
            // that simply omitted the parameter bypassed the strongest signal in total silence - the same
            // shape UNCHECKED exists to close for `discipline`. Omission stays LEGAL, because a consult
            // with no primary artifact has nothing to echo; it just stops being invisible. Only a
            // recognised discipline is told, so ordinary questions are not nagged.
            // (Capstone R2, Mechanism Gamer.)
            if (DisciplineContract.TerminalTokenFor(discipline) is not null)
            {
                blocks.Add(new TextContentBlock
                {
                    Text = "[13b] NO ECHO: this consult named a discipline but supplied no echo target, "
                         + "so the strongest completeness check did NOT run - only the terminal token was "
                         + "verified. If the brief named a primary artifact, re-issue with expectEcho set "
                         + "to that file's last substantive line. If it genuinely had no artifact (a "
                         + "design question, a pasted fork), this notice is expected."
                });
            }
        }
        else if (!SemanticEcho.IsUsableExpectation(expectEcho))
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] ECHO WEAK: the supplied echo target cannot prove anything - it carries "
                     + "fewer than " + SemanticEcho.MinSubstantiveChars + " letters or digits, so a peer "
                     + "could emit it without reading the artifact (a bare '}' ends every C# file). The "
                     + "echo check was SKIPPED rather than failed. Use the last non-blank line that "
                     + "carries actual content, or omit expectEcho and rely on the other checks."
            });
        }

        // OMISSION MUST BE LOUD. Without this block a caller that names no discipline gets a completely
        // normal-looking result with no checks run - which is the compliance-theater failure in a
        // different costume: not a check that can be turned off, but one that was never turned on and
        // said nothing about it. This does NOT block the consult; it makes the gap visible.
        if (DisciplineContract.TerminalTokenFor(discipline) is null)
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] UNCHECKED: no known discipline was named on this ask, so the completeness "
                     + "checks did NOT run. If this is a discipline consult, re-issue it with "
                     + "discipline set to one of: " + string.Join(", ", DisciplineContract.KnownDisciplines)
                     + ". If it is an ordinary question, this notice is expected."
            });
        }
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
