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



using Clavity.Ls.Proto;
using Grpc.Core;
using Grpc.Core.Interceptors;
using Grpc.Net.Client;

namespace Clavity.Ls;

/// <summary>
/// High-level client for agy's Language Server: wraps an h2c <see cref="GrpcChannel"/> and the generated
/// <see cref="LanguageServerService.LanguageServerServiceClient"/>. Construct from a channel (tests) or via
/// <see cref="Connect"/>, which discovers the live LS from cli.log text and dials it over h2c.
/// </summary>
public sealed class LsClient : IDisposable
{
    /// <summary>Defensive client-side deadline for the SHORT unary calls (metadata / trajectory / send / list). A peer
    /// that connects then HANGS must not block a one-shot round-trip forever — without it the <c>AskAsync</c>
    /// <c>finally</c> that clears the in-flight marker would never run, and every later status check would falsely
    /// report "working". NOT applied to the idle-wait RPCs, which are intentionally long and bounded by their OWN
    /// caller deadline (<see cref="ProbeIdleAsync"/>'s 300ms; <c>AgyView.AskAsync</c>'s idle-wait CTS).</summary>
    public const int DefaultCallDeadlineSeconds = 30;

    private readonly GrpcChannel _channel;
    private readonly LanguageServerService.LanguageServerServiceClient _client;
    private readonly TimeSpan _callDeadline;

    public LsClient(GrpcChannel channel, TimeSpan? callDeadline = null, string? csrfToken = null)
    {
        _channel = channel;
        Grpc.Core.CallInvoker invoker = string.IsNullOrEmpty(csrfToken)
            ? channel.CreateCallInvoker()
            : channel.Intercept(new CsrfInterceptor(csrfToken!));
        _client = new LanguageServerService.LanguageServerServiceClient(invoker);
        _callDeadline = callDeadline ?? TimeSpan.FromSeconds(DefaultCallDeadlineSeconds);
    }

    /// <summary>A fresh absolute deadline (UTC) for one unary call, computed at call time. <paramref name="over"/>
    /// lets a CALLER tighten the bound for one call (e.g. the boot race clamps to its remaining budget) without
    /// changing the client-wide default.</summary>
    private DateTime NextCallDeadline(TimeSpan? over = null) => DateTime.UtcNow + (over ?? _callDeadline);

    /// <summary>Discover the active LS from cli.log text (liveness-checked) and open an h2c channel to it.
    /// No CSRF token — the pre-1.2.2 / no-endpoint-file fallback path.</summary>
    public static LsClient Connect(string cliLogText, IListeningPorts listening, TimeSpan? callDeadline = null)
    {
        var endpoint = LsDiscovery.DiscoverActive(cliLogText, listening);
        return new LsClient(LsChannel.ForHttpPort(endpoint.HttpPort), callDeadline);
    }

    /// <summary>Connect to agy's self-published endpoint (port + CSRF token from agy-endpoint.json), sending
    /// the token on every call. The 1.2.2+ path.</summary>
    public static LsClient ConnectToEndpoint(AgyEndpoint endpoint, TimeSpan? callDeadline = null)
        => new LsClient(LsChannel.ForHttpPort(endpoint.Port), callDeadline, endpoint.Csrf);

    /// <summary>Read a conversation's metadata (workspaces, repo/branch, ids).</summary>
    public async Task<Clavity.Ls.Proto.Metadata> GetConversationMetadataAsync(string conversationId, CancellationToken cancellationToken = default)
    {
        var response = await _client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = conversationId },
            deadline: NextCallDeadline(),
            cancellationToken: cancellationToken);
        return response.Metadata;
    }

    /// <summary>Read a cascade's full trajectory (transcript). The conversation id is accepted as the cascade id.</summary>
    public async Task<CascadeTrajectory> GetCascadeTrajectoryAsync(string cascadeId, CancellationToken cancellationToken = default)
    {
        var response = await _client.GetCascadeTrajectoryAsync(
            new GetCascadeTrajectoryRequest { CascadeId = cascadeId },
            deadline: NextCallDeadline(),
            cancellationToken: cancellationToken);
        return response.Trajectory;
    }

    /// <summary>The deepest legacy fallback model id — used ONLY when the conversation has no prior model AND agy
    /// is too old to serve GetAvailableModels. Named here so the literal 1037 lives in exactly one place.</summary>
    public const int LegacyFallbackModelId = (int)Model.Gemini31ProHigh;

    /// <summary>
    /// Send a user message into the cascade with an explicitly-resolved <paramref name="requestedModel"/>. The
    /// live LS rejects a no-model send and rejects aliases, so the caller resolves a CONCRETE id (the
    /// conversation's own model, agy's default, or the legacy fallback). The response is EMPTY by contract — read
    /// the reply via <see cref="GetCascadeTrajectoryAsync"/> after <see cref="WaitForConversationFullyIdleAsync"/>.
    /// ⚠ LIVE this consumes quota and injects a visible message.
    /// </summary>
    public async Task SendUserCascadeMessageAsync(
        string cascadeId, string text, int requestedModel, CancellationToken cancellationToken = default)
    {
        var request = new SendUserCascadeMessageRequest
        {
            CascadeId = cascadeId,
            CascadeConfig = new CascadeConfig
            {
                PlannerConfig = new CascadePlannerConfig
                {
                    RequestedModel = new ModelOrAlias { Model = requestedModel },
                },
            },
        };
        request.Items.Add(new TextOrScopeItem { Text = text });
        await _client.SendUserCascadeMessageAsync(request, deadline: NextCallDeadline(), cancellationToken: cancellationToken);
    }

    /// <summary>Block until the conversation is fully idle (or the wait times out). Returns true if it timed out.</summary>
    public async Task<bool> WaitForConversationFullyIdleAsync(
        string conversationId,
        int inactivityTimeoutSeconds,
        int stabilizationDurationSeconds,
        CancellationToken cancellationToken = default)
    {
        var response = await _client.WaitForConversationFullyIdleAsync(
            new WaitForConversationFullyIdleRequest
            {
                ConversationId = conversationId,
                InactivityTimeoutSeconds = inactivityTimeoutSeconds,
                StabilizationDurationSeconds = stabilizationDurationSeconds,
            },
            cancellationToken: cancellationToken);
        return response.TimedOut;
    }

    /// <summary>Probe idle/working: wait for full idle with a REALISTIC inactivity window, but bound the CALL with
    /// a short client <paramref name="deadline"/>. Returns "idle" if the wait resolves inside the deadline,
    /// "working" if the deadline cancels it first, "unknown" on any RPC error. (Spec: realistic inactivity, the
    /// deadline is the probe budget — never shrink inactivity, which would falsely read inter-step gaps as idle.)</summary>
    public async Task<string> ProbeIdleAsync(string conversationId, int inactivitySeconds, TimeSpan deadline,
        CancellationToken cancellationToken = default)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(deadline);
        try
        {
            await _client.WaitForConversationFullyIdleAsync(
                new WaitForConversationFullyIdleRequest
                {
                    ConversationId = conversationId,
                    InactivityTimeoutSeconds = inactivitySeconds,
                    StabilizationDurationSeconds = 0,
                },
                cancellationToken: cts.Token);
            return "idle";
        }
        catch (Exception ex) when (cts.IsCancellationRequested && !cancellationToken.IsCancellationRequested
            && ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
        {
            return "working";
        }
        catch (RpcException)
        {
            return "unknown";
        }
    }

    /// <summary>
    /// List the top-level conversations this LS instance knows (map key = conversation id). The multi-session
    /// convId resolver: each agy instance's LS reports only its own conversations. (GetBrowserOpenConversation
    /// is desktop-UI-only and errors on a CLI agy — E2-verified — so it is NOT used.)
    /// </summary>
    public async Task<IReadOnlyList<CascadeConversation>> GetAllCascadeTrajectoriesAsync(
        bool excludeSubtrajectories = true, CancellationToken cancellationToken = default,
        TimeSpan? deadlineOverride = null)
    {
        var response = await _client.GetAllCascadeTrajectoriesAsync(
            new GetAllCascadeTrajectoriesRequest { ExcludeSubtrajectories = excludeSubtrajectories },
            deadline: NextCallDeadline(deadlineOverride),
            cancellationToken: cancellationToken);

        return response.TrajectorySummaries
            .Select(kvp => new CascadeConversation(
                kvp.Key,
                kvp.Value.LastModifiedTime?.ToDateTimeOffset()))
            .ToList();
    }

    /// <summary>The live model catalog, UNWRAPPED from the RPC's wrapper: key → details (concrete id) + the default
    /// key. The renumber authority. The wire nests the catalog at field 1 of <c>GetAvailableModelsResponse</c>
    /// (live-verified, agy 1.0.11) — we hand back the inner catalog so <see cref="SendModelResolver"/> sees a flat
    /// map + default. Defensively deadline-bounded like the other short unary calls (finding (e)).</summary>
    public async Task<Clavity.Ls.Proto.FetchAvailableModelsResponse> GetAvailableModelsAsync(
        CancellationToken cancellationToken = default)
    {
        var response = await _client.GetAvailableModelsAsync(
            new Clavity.Ls.Proto.FetchAvailableModelsRequest(),
            deadline: NextCallDeadline(),
            cancellationToken: cancellationToken);
        return response.AvailableModels ?? new Clavity.Ls.Proto.FetchAvailableModelsResponse();
    }

    public void Dispose() => _channel.Dispose();
}
