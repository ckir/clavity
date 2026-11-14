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



using Grpc.Core;

namespace Clavity.Ls;

/// <summary>The shared diagnosis for a dead clavity-ls -> agy channel: decides whether a caught exception is a
/// channel death (<see cref="IsChannelDown"/>), unwraps the underlying gRPC cause (<see cref="Diagnose"/> — never
/// emits "Unknown" while a real RpcException is available, F4), and produces the actionable hint. Shared by
/// McpTools' central RunAsync catch and AgyView.StatusAsync so both surfaces agree.</summary>
public static class ChannelDown
{
    public const string Status = "channel_down";

    /// <summary>Diagnostic code for "the endpoint resolved but the peer did not answer in time" (a busy peer).
    /// It keeps the channel_down status (compatibility) but gets its own hint: retry, do not restart.</summary>
    public const string LsUnanswered = "LsUnanswered";

    /// <summary>Diagnostic code for "discovery failed AND a published endpoint file named a dead port". Keeps the
    /// channel_down status; the hint says relaunch agy, because only a new agy republishes its endpoint.</summary>
    public const string LsEndpointStale = "LsEndpointStale";

    /// <summary>True if the exception is a channel death we should diagnose. Excludes a caller-cancel
    /// (RpcException StatusCode.Cancelled — F6). The AgyModelUnavailableException-wrapper clause is added in the
    /// F3 fold.</summary>
    public static bool IsChannelDown(Exception ex) =>
        (ex is RpcException rpc && rpc.StatusCode != StatusCode.Cancelled)
        || ex is ObjectDisposedException or LsDiscoveryException
        || (ex is AgyModelUnavailableException && ex.InnerException is
            (RpcException { StatusCode: not StatusCode.Cancelled }) or ObjectDisposedException or LsDiscoveryException);

    /// <summary>Extract the diagnostic per the F4 unwrap rule: the RpcException's status; else an inner
    /// RpcException's status; else the concrete exception type name — never a bare "Unknown".</summary>
    public static ChannelDiagnostic Diagnose(Exception ex) => ex switch
    {
        RpcException rpc => new ChannelDiagnostic(rpc.StatusCode.ToString(), DetailOf(rpc)),
        { InnerException: RpcException rpc } => new ChannelDiagnostic(rpc.StatusCode.ToString(), DetailOf(rpc)),
        ObjectDisposedException => new ChannelDiagnostic("ObjectDisposed", ex.Message),
        LsDiscoveryException { PeerReachedButUnanswered: true } => new ChannelDiagnostic(LsUnanswered, ex.Message),
        LsDiscoveryException { StaleEndpointNote: not null } => new ChannelDiagnostic(LsEndpointStale, ex.Message),
        LsDiscoveryException => new ChannelDiagnostic("LsDiscovery", ex.Message),
        _ => new ChannelDiagnostic(ex.GetType().Name, ex.Message),
    };

    // Real gRPC uses an EMPTY (not null) Status.Detail on many failures, so `?? Message` would not fire; fall back
    // to the exception Message whenever Detail is null OR empty, to keep the diagnostic from reading "[Unavailable] ".
    private static string DetailOf(RpcException rpc) =>
        string.IsNullOrEmpty(rpc.Status.Detail) ? rpc.Message : rpc.Status.Detail;

    /// <summary>Why the channel call failed. The bridge used to report every fault as a peer shutdown, which sent
    /// the operator to inspect a healthy process while the real cause was the response SIZE, a refused
    /// credential, or a bad request. Each cause names its own remedy.
    /// <para>The load-bearing distinction: a gRPC status code that is NOT a transport failure PROVES the channel
    /// reached the peer and the peer answered with a structured error frame — a dead transport cannot produce
    /// one. Reporting those as "the language server shut down" is factually false and sends the operator into a
    /// restart loop that can never clear the condition.</para></summary>
    public enum Fault { TransportDown, ResourceExhausted, AuthFailed, InvalidRequest }

    /// <summary>Classify a diagnosed fault by its gRPC status code. Anything not named here — including the
    /// non-gRPC "ObjectDisposed"/"LsDiscovery" diagnostics and a genuine <c>Unavailable</c> — is a transport
    /// death, which is the correct default: it is the only class a restart can fix.</summary>
    public static Fault Classify(ChannelDiagnostic d) => d.StatusCode switch
    {
        // Deliberately NOT split by detail text. Discriminating "too large" from "quota" would have to match
        // Grpc.Net.Client's own message string, which is not a contract and can change with the library
        // version or localization. The status therefore asserts only what gRPC asserted, and Hint explains
        // the two possible causes. (Owner ruling, 2026-08-07, converged with the review peer.)
        nameof(Grpc.Core.StatusCode.ResourceExhausted) => Fault.ResourceExhausted,

        nameof(Grpc.Core.StatusCode.Unauthenticated) or
        nameof(Grpc.Core.StatusCode.PermissionDenied) => Fault.AuthFailed,

        nameof(Grpc.Core.StatusCode.NotFound) or
        nameof(Grpc.Core.StatusCode.InvalidArgument) or
        nameof(Grpc.Core.StatusCode.FailedPrecondition) => Fault.InvalidRequest,

        _ => Fault.TransportDown,
    };

    /// <summary>The machine-readable status for a fault. MUST track <see cref="Hint"/>: a consumer reading the
    /// status field and a human reading the hint have to reach the same conclusion. Every arm added to
    /// <see cref="Classify"/> MUST be added here too — the fallback silently reports a fault as a dead channel.</summary>
    public static string StatusFor(ChannelDiagnostic d) => Classify(d) switch
    {
        Fault.ResourceExhausted => "resource_exhausted",
        Fault.AuthFailed => "auth_failed",
        Fault.InvalidRequest => "invalid_request",
        _ => Status,
    };

    /// <summary>Names the running build on the two faults a STALE installed client can cause (a transport death and a size/quota
    /// refusal), so "the peer is down" is not the only hypothesis offered. Deliberately NOT on the busy-peer, stale-endpoint, auth
    /// and bad-request hints: a newer client does not cure those, and a version in every error is noise (ROADMAP: stale client).</summary>
    private static string StaleClientNote =>
        $" Running client: clavity-ls {ClientStamp.Value}. If the cause above is already fixed in your source tree, this INSTALLED " +
        "binary is stale: update the clavity plugin, then restart the session.";

    public static string Hint(ChannelDiagnostic d)
    {
        var prefix = $"clavity-ls -> agy channel call failed ([{d.StatusCode}] {d.Detail}). ";
        if (d.StatusCode == LsUnanswered)
            return prefix + "agy's language server was reached but did not answer inside the budget: it is most " +
                "likely BUSY mid-turn, not down. RETRY the call - the endpoint is re-resolved on every call, so " +
                "there is nothing to reconnect. Only if repeated retries keep failing should you restart the " +
                "Claude Code session (or the clavity-ls MCP server).";
        if (d.StatusCode == LsEndpointStale)
            return prefix + "Neither discovery path reaches a live agy: the published endpoint file is stale (see " +
                "above) and so is the cli.log session. Restarting the Claude Code session will NOT clear this. " +
                "Relaunch agy through clavity-ls (clavity-ls agy, or clavity start) so it gets its own log and " +
                "republishes its endpoint, or have the running agy re-run the pairing Step 1 with its built-in shell tool.";
        return Classify(d) switch
        {
            // ResourceExhausted covers TWO causes and the code cannot tell them apart from the status alone:
            // the channel's own receive limit, and upstream quota / rate-limiting. Naming only the first
            // would send an operator to edit a message-size limit during a quota event — the same
            // "confidently name the wrong remedy" defect this classifier exists to remove. So the hint names
            // both and points at the detail (echoed in the prefix above) as the discriminator.
            Fault.ResourceExhausted =>
                prefix + "The peer is NOT down and restarting will not clear it. If the detail above mentions a " +
                "message SIZE, the response was too large for the channel's receive limit — start a fresh " +
                "cascade, or raise MaxReceiveMessageSize in LsChannel.cs (trajectory size, not step count, is " +
                "what crosses it). If it does not, this is upstream quota or rate-limit exhaustion — wait and " +
                "retry, or check quota; raising the receive limit will not help." + StaleClientNote,

            Fault.AuthFailed =>
                prefix + "The channel is UP and agy answered — it REFUSED the credential (CSRF token). agy 1.2.2+ " +
                "mints a new per-session token on each Language Server (re)start, so a published endpoint goes " +
                "stale; the token in ~/.clavity/agy-endpoint.json is stale or the file is missing. Relaunch agy " +
                "(clavity start) so it republishes its endpoint, then retry. Restarting the Claude session alone " +
                "will NOT fix a token refusal. If this session's agy only just started, look at its terminal first: a " +
                "new agy may be waiting for you to approve a prompt in its tab (folder trust, for example), and it " +
                "publishes its endpoint only after you answer.",

            Fault.InvalidRequest =>
                prefix + "The channel is UP and agy answered — it rejected the REQUEST, not the connection. " +
                "Restarting will not help. The usual cause is a stale or closed conversation id; re-resolve the " +
                "active cascade, or start a fresh one.",
            _ =>
                prefix + "agy's language server appears to have shut down or restarted (it does this " +
                "intermittently). Restart the Claude Code session (or the clavity-ls MCP server) to re-establish " +
                "the channel. agy's own logs are at ~/.gemini/antigravity-cli/ (cli.log + " +
                "logs/clavity-<sessionId>.log) if you need to confirm the shutdown." + StaleClientNote,
        };
    }
}
