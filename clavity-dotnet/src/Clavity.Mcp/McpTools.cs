// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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
    private readonly AgyView _view;

    public McpTools(AgyView view) => _view = view;

    [McpServerTool(Name = "agy_look"), Description("Look at the active agy conversation's cascade trajectory as a size-bounded JSON summary (no verbose ids).")]
    public async Task<string> AgyLook(CancellationToken cancellationToken = default)
        => await RunAsync(() => _view.LookAsync(cancellationToken: cancellationToken));

    [McpServerTool(Name = "agy_status"), Description("Report whether the active agy conversation is idle, working, or unknown (pre-fire check), plus cascade id and step count.")]
    public async Task<string> AgyStatus(CancellationToken cancellationToken = default)
        => await RunAsync(() => _view.StatusAsync(cancellationToken));

    [McpServerTool(Name = "agy_ask"), Description("Send a message to the active agy conversation and return agy's reply (size-bounded JSON) once the conversation goes idle. WRITE: consumes quota and posts a visible message in the user's agy.")]
    public async Task<CallToolResult> AgyAsk(
        string message, IProgress<ProgressNotificationValue> progress,
        string? discipline = null, string? artifactPath = null,
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

        // THE DRIVER READS THE ARTIFACT AND DERIVES THE EXPECTATION ITSELF. The caller names WHICH file
        // was under review; it does not compute, and cannot mistype, the line to be echoed. Two parties
        // applying a counting rule to the same file could pick different lines and red an honest review;
        // one party cannot disagree with itself.
        var expectEcho = SemanticEcho.ExpectedFrom(artifactPath);

        // CAPTURED PER CALL, never on the view. An earlier draft parked the evaluated reply on
        // AgyView.LastReply - but Program.cs:44 registers AgyView as a SINGLETON, so concurrent asks
        // would read each other's verdicts. Worse, it was wrong SINGLE-THREADED too: RunAsync converts a
        // failed ask into an error payload, leaving the previous ask's flags in place to be reported
        // against a reply that does not exist. A local stays null on that path, which is the correct
        // answer - no reply, no verdict. (Capstone R1, State Corruptor.)
        AskReply? reply13b = null;
        var json = await RunAsync(async () =>
        {
            var r = await _view.AskAsync(message, progress: relay, expectTerminal: expectTerminal, expectEcho: expectEcho, cancellationToken: cancellationToken);
            reply13b = r;
            return r;
        });
        var blocks = new List<ContentBlock> { new TextContentBlock { Text = json } };
        var guidance = _view.TryTakeGuidanceBlock();
        if (guidance is not null) blocks.Add(new TextContentBlock { Text = guidance });

        // A reply delivered from a turn that ENDED while the conversation stayed busy. Independent of the 13b verdicts
        // below: those judge the reply, this reports the peer's state - and the caller's next pre-fire agy_status will
        // say "working" for a reason that has nothing to do with this reply.
        if (reply13b is { PeerStillBusy: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[PEER STILL BUSY] agy's turn ended - its final reply step is complete and requests no tools - "
                     + "but the conversation never went fully idle, so this reply was delivered without that signal. "
                     + "The usual cause is background tasks agy started that never exited (e.g. a search command given "
                     + "no path, blocked reading stdin). agy_status reports 'working' until they end, and the next ask "
                     + "will wait on them too: have agy list and kill its running background tasks first."
            });
        }

        // 13b: the verdicts must REACH the caller. A flag nothing reads cannot stop a truncated review
        // being folded, which is the entire failure this step exists to end.
        //
        // These are if/else-if, not independent blocks. A truncated reply is usually also a small one,
        // and emitting several would make the deterministic verdicts compete with the heuristic for the
        // reader's attention. The deterministic ones win, strongest first.
        // Branch 22 adds two arms to the same chain - RESCUED first (it replaces the verdicts it cleared), ANSWER CUT last.
        // Branch 4 (section 66) puts the quota stop SECOND, after RESCUED and before the two incompleteness notices: a peer
        // that wrote its reply file and was then quota-stopped before posting in chat is RESCUED (complete), and the stop is
        // only context; a peer stopped before writing anything is explained by the stop, and the right move (wait for the
        // reset) is the opposite of the re-ask the truncation notices suggest. The block itself is emitted in BOTH cases.
        var quotaBlock = reply13b is { QuotaStop: { } quota }
            ? new TextContentBlock
            {
                Text = "[PEER QUOTA STOP] agy hit its quota during this ask: \"" + quota + "\" (agy's own words, from its log). "
                     + (string.IsNullOrEmpty(reply13b.Answer)
                        ? "The reply is missing because agy could not generate, not because it was dropped. "
                        : "The Answer above was produced before the stop; anything agy meant to add after it is missing. ")
                     + "Wait for the reset, then re-ask; do not resend meanwhile - each failed retry has been observed to push "
                     + "the reset further out."
            }
            : null;
        if (reply13b is { CheckedSource: "peer-file" } rescued)
        {
            // ROADMAP section 74, C-peer-read: complete, but never silently - say which file passed.
            blocks.Add(new TextContentBlock { Text = RecoveryNotice.Rescued(rescued) });
            if (quotaBlock is not null) blocks.Add(quotaBlock);
        }
        else if (quotaBlock is not null)
        {
            blocks.Add(quotaBlock);
        }
        else if (reply13b is { TerminalTokenMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] TRUNCATED REPLY: the terminal token this discipline requires is missing or not at the end"
                     + RecoveryNotice.TerminalDetail(expectTerminal ?? "the discipline's token", reply13b)
                     + (reply13b.TurnEndedOnToolStep ? " (the turn ended on a tool step, so Answer is empty)" : "")
                     + ". Treat this consult as INCOMPLETE - never as 'no findings' - and fold nothing from it until it is recovered. "
                     + RecoveryNotice.Sentence(reply13b)
            });
        }
        else if (reply13b is { EchoMissing: true })
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] ECHO MISSING: the peer did not quote the artifact's last line near its "
                     + "verdict, so it did not reach the end of what it was asked to read - or did not "
                     + "read it. Treat this consult as INCOMPLETE and do not fold findings from it. "
                     + RecoveryNotice.Sentence(reply13b)
            });
        }
        else if (reply13b is { AnswerTruncated: true })
        {
            // C-check: a passing verdict must not hide that Answer is cut (spec panel R1).
            blocks.Add(new TextContentBlock { Text = RecoveryNotice.AnswerCut(reply13b) });
        }
        // AN ECHO TARGET THAT CANNOT DISCRIMINATE IS NOT A CHECK. Independent of the verdicts above,
        // because it is a fact about the ASK, not about the reply - the same category as UNCHECKED.
        // (Capstone R1: the last non-blank line of any C# file is "}", which any peer can emit.)
        if (artifactPath is null)
        {
            // FAIL-OPEN, CLOSED. Omitting the artifact stays LEGAL - a consult with no primary artifact
            // has nothing to echo - it just stops being invisible. Only a recognised discipline is told,
            // so ordinary questions are not nagged. (Capstone R2, Mechanism Gamer.)
            if (expectTerminal is not null)
            {
                blocks.Add(new TextContentBlock
                {
                    Text = "[13b] NO ECHO: this consult named a discipline but no artifact, so the "
                         + "strongest completeness check did NOT run - only the terminal token was "
                         + "verified. If the brief pointed the peer at a file, re-issue with artifactPath "
                         + "set to that file. If it genuinely had no artifact (a design question, a "
                         + "pasted fork), this notice is expected. NOTE: if your instructions still say to "
                         + "pass expectEcho, they predate this driver - the parameter is now artifactPath "
                         + "and you name the FILE, not the line. Re-asking unchanged will not help."
                });
            }
        }
        else if (expectEcho is null)
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] ECHO WEAK: no line in the named artifact can prove anything - none carries "
                     + SemanticEcho.MinSubstantiveChars + " letters or digits, or the file could not be "
                     + "read. A peer could satisfy a punctuation-only target without reading a word (a "
                     + "bare '}' ends every C# file). The echo check was SKIPPED rather than failed - the "
                     + "artifact is the problem, not the peer. Check the path, or rely on the token."
            });
        }

        // OMISSION MUST BE LOUD. Without this block a caller that names no discipline gets a completely
        // normal-looking result with no checks run - which is the compliance-theater failure in a
        // different costume: not a check that can be turned off, but one that was never turned on and
        // said nothing about it. This does NOT block the consult; it makes the gap visible.
        if (expectTerminal is null && _view.TryTakeUncheckedNotice())
        {
            blocks.Add(new TextContentBlock
            {
                Text = "[13b] UNCHECKED: no known discipline was named on this ask, so the completeness "
                     + "checks did NOT run. If this is a discipline consult, re-issue it with "
                     + "discipline set to one of: " + string.Join(", ", DisciplineContract.KnownDisciplines)
                     + ". If it is an ordinary question, this notice is expected. Shown ONCE per session, so it does not become noise you learn to skip."
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
    internal static async Task<string> RunAsync<T>(Func<Task<T>> action)
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
        catch (AgyModelUnavailableException ex)
        {
            // ROADMAP section 71. Thrown by AgyView when the conversation's model is deprecated or unavailable; its
            // message says how to escape. It reaches here only when ChannelDown.IsChannelDown declined it (a wrapped
            // channel-down cause is diagnosed above), so this is the pure model case.
            return JsonSerializer.Serialize(new { status = "model_unavailable", message = ex.Message });
        }
        catch (Exception ex) when (ex is not OperationCanceledException
                                   && ex is not Grpc.Core.RpcException { StatusCode: Grpc.Core.StatusCode.Cancelled })
        {
            // ROADMAP section 71. Anything else used to escape to the SDK, which reports only
            // "An error occurred invoking 'agy_ask'." and keeps the cause for its log. A caller-cancel is left alone:
            // the SDK rethrows it as a cancellation, which is the right answer for a cancelled ask. A gRPC call cancelled by the
            // caller's token is an RpcException{Cancelled}, NOT an OperationCanceledException; ChannelDown.IsChannelDown excludes
            // it on purpose, and the existing AgyChannelDownTests.A_grpc_cancelled_status_is_not_reported_as_channel_down requires
            // it to propagate - a bare `is not OperationCanceledException` filter would turn it into a typed "error" (found by the
            // 2026-10-08 dry run).
            return JsonSerializer.Serialize(new { status = "error", exception = ex.GetType().Name, message = ex.Message });
        }
    }

    // Static wrappers for backward compatibility with tests that call McpTools.Method(view, ...) directly.
    // These are NOT marked with [McpServerTool] so they don't affect schema generation.
    public static async Task<string> AgyLook(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.LookAsync(cancellationToken: cancellationToken));

    public static async Task<string> AgyStatus(AgyView view, CancellationToken cancellationToken = default)
        => await RunAsync(() => view.StatusAsync(cancellationToken));

    public static async Task<CallToolResult> AgyAsk(
        AgyView view, string message, IProgress<ProgressNotificationValue> progress,
        string? discipline = null, string? artifactPath = null,
        CancellationToken cancellationToken = default)
    {
        var tools = new McpTools(view);
        return await tools.AgyAsk(message, progress, discipline, artifactPath, cancellationToken);
    }
}
