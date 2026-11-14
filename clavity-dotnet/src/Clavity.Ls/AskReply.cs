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



using System.Text.Json.Serialization;

namespace Clavity.Ls;

/// <summary>The typed reply from agy_ask. Answer = the trailing assistant prose (null if the delta ended on a
/// non-assistant step — read Activity). Activity = the COMPLETE step record (nothing dropped), head-truncated.</summary>
public sealed record AskReply(
    string CascadeId,
    string? Answer,
    IReadOnlyList<ActivityItem> Activity,
    bool AnswerTruncated,
    bool ActivityTruncated,
    // 13b. Both default to false so every existing construction site and test is unaffected. Both are
    // DETERMINISTIC verdicts about the reply's structure - there is no statistical flag here any more.
    // There was briefly a third, heuristic flag here; it and the archive behind it were removed.
    bool TerminalTokenMissing = false,
    // The peer did not quote the artifact's last substantive line near its verdict: it never reached the
    // end, or never read the artifact at all.
    bool EchoMissing = false,
    // agy's turn ENDED (its last step is a DONE planner response requesting no tools) but the conversation never
    // went fully idle - background tasks, typically shell commands that never exited, were still running. The
    // reply is delivered anyway instead of a possible_modal that strands it (live 2026-09-17). NOT a 13b verdict:
    // it is a fact about the peer's state, so agy_status keeps saying "working" until those tasks end.
    bool PeerStillBusy = false,
    // ROADMAP section 74 (Branch 22). Every field below is omitted from the JSON while unset, and the driver's context
    // is what that protects. ReplyFile: the server's capture of every assistant step of this ask (C-capture), null when
    // the capture is off or failed - then CaptureError says why. CheckedSource: "chat" or "peer-file" - which text
    // passed or failed the [13b] checks; null when no discipline was named. TurnEndedOnToolStep: the delta ended on a
    // tool step, so Answer is null by design. PeerFile: the reply file the peer was asked to write (C-request).
    // PeerFileStatus: why no peer file was requested, or why the requested one was not used.
    // COST (measured, real paths): an ORDINARY ask carries ReplyFile, +98 characters - no check runs there, so nothing
    // else could flag a displaced report. A HEALTHY discipline ask drops ReplyFile, PeerFile and PeerFileStatus
    // (AgyView.DropFilePointersWhenHealthy, owner ruling, capstone R2 CA1) and costs +23. A flagged ask keeps them all.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? ReplyFile = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? CaptureError = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? CheckedSource = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool TurnEndedOnToolStep = false,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? PeerFile = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? PeerFileStatus = null,
    // ROADMAP section 66: agy's own quota-stop sentence, read from its log for THIS ask; null on every ordinary reply.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? QuotaStop = null);

/// <summary>One summarized step of the reply delta. Summary = bounded prose for assistant/user steps, else null.</summary>
public sealed record ActivityItem(int Kind, string Label, string? Summary);

/// <summary>On agy_ask timeout: where agy was. NewAgySteps discounts the injected user step; LastStepClass splits
/// a slow tool (don't abandon) from a true hang.</summary>
public sealed record TimeoutDiagnostic(
    int TotalSteps, int NewAgySteps, int LastStepKind, string LastStepClass, string? LastStepSummary,
    int? LastStepStatus = null, int? LastStepTextLength = null);

/// <summary>On a dead/failed clavity-ls -> agy channel: the underlying gRPC failure. StatusCode = the gRPC
/// StatusCode name (e.g. "Unavailable"), or the concrete exception type name ("ObjectDisposed"/"LsDiscovery")
/// when no RpcException is available; Detail = the failure detail/message. Never "Unknown" while a real cause
/// exists (F4).</summary>
public sealed record ChannelDiagnostic(string StatusCode, string Detail);

/// <summary>agy_status result. State = idle | working | unknown, or one of the FAULT states
/// channel_down | resource_exhausted | auth_failed | invalid_request (see <see cref="ChannelDown.StatusFor"/>, which is
/// the single source of truth — add a state there and here together). Diagnostic + Hint are populated on every FAULT
/// state alike (they all come from the same catch, which carries the diagnostic) and are null on every healthy state;
/// additive, so existing consumers are unaffected — F7. Consumers must treat "State names a fault" rather than
/// "State == channel_down" as the test for a populated Diagnostic. RecentEvents (the event log's ring, oldest first) rides
/// the same fault path and is OMITTED from the JSON on every healthy state (unlike Diagnostic and Hint, which are written as
/// null), so a routine pre-fire poll is byte-for-byte what it was before the event log existed. LogPath (the live log
/// file) or LogNote (the file is off or dropped; never both) and CallId ride the fault path the same way.</summary>
public sealed record AgyStatus(
    string CascadeId, int TotalSteps, string State, int LastStepKind,
    ChannelDiagnostic? Diagnostic = null, string? Hint = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? RecentEvents = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? LogPath = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? LogNote = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? CallId = null);

/// <summary>Maps agy step kinds to a label + a coarse class. 14=user, 15=assistant, everything else = tool
/// (the spec's "tool" + "unknown" both fail-safe to slow). Built from the captured trajectory golden.</summary>
public static class StepKind
{
    public const int UserKind = 14;
    public const int AssistantKind = 15;

    /// <summary>CascadeStep.status value of a finished step (clavity.proto field 4, wire-verified 2026-09-17).</summary>
    public const int DoneStatus = 3;

    /// <summary>CascadeStep.status value of a kind-15 assistant step that is still being GENERATED. Measured by a read-only
    /// probe on 2026-11-06 (ROADMAP section 108): 8 from the step's first appearance (with EMPTY text for about 60 s while
    /// the model thinks), the text then streaming while the step COUNT stays flat, flipping to 3 when done. It is the one
    /// verified non-done value for an assistant step, so it is matched exactly, never as "any non-3".</summary>
    public const int GeneratingStatus = 8;

    public static string Class(int kind) => kind switch
    {
        UserKind => "user",
        AssistantKind => "assistant",
        _ => "tool",
    };

    public static string Label(int kind) => kind switch
    {
        UserKind => "user",
        AssistantKind => "assistant",
        _ => $"step {kind}",
    };
}
