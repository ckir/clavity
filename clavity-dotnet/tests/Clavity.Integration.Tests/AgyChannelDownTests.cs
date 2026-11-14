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



using System.Text.Json;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Clavity.Mcp;
using ModelContextProtocol;
using ModelContextProtocol.Protocol;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// Channel-diagnosability (§0b): a dead clavity-ls -> agy channel yields a structured channel_down diagnosis,
// never a bare error; agy_status never throws; a real bug is not masked; a caller-cancel is not channel_down.
public class AgyChannelDownTests
{
    // A fake whose channel is "dead": chosen RPCs throw a configurable gRPC status. GetAllCascadeTrajectories
    // succeeds (so ConnectAndResolve returns a client) unless throwOnDiscovery; GetCascadeTrajectory throws the
    // dead status (pre-flight death) unless sendThenThrowOnWait, in which case it succeeds and WaitFor throws.
    private sealed class FakeChannelDownLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly StatusCode _status;
        private readonly string _cascadeId;
        private readonly bool _throwOnDiscovery;
        private readonly bool _sendThenThrowOnWait;
        private readonly List<CascadeStep> _steps = new();

        public FakeChannelDownLs(string cascadeId, StatusCode status, bool throwOnDiscovery = false, bool sendThenThrowOnWait = false)
        { _cascadeId = cascadeId; _status = status; _throwOnDiscovery = throwOnDiscovery; _sendThenThrowOnWait = sendThenThrowOnWait; }

        private RpcException Dead() => new(new Status(_status, "channel dead"));

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            if (_throwOnDiscovery) throw Dead();
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
        {
            if (!_sendThenThrowOnWait) throw Dead(); // pre-flight death: the first ask/look/status RPC throws.
            var traj = new CascadeTrajectory { CascadeId = _cascadeId };
            lock (_steps) traj.Steps.AddRange(_steps);
            return Task.FromResult(new GetCascadeTrajectoryResponse { Trajectory = traj });
        }

        public override Task<GetAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
            => Task.FromResult(new GetAvailableModelsResponse
            {
                AvailableModels = new FetchAvailableModelsResponse
                {
                    DefaultAgentModelId = "k",
                    Models = { { "k", new ModelDetails { Model = 1042 } } },
                },
            });

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
        {
            lock (_steps)
                _steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = request.Items.Count > 0 ? request.Items[0].Text : "" } });
            return Task.FromResult(new SendUserCascadeMessageResponse());
        }

        public override Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
        {
            if (_sendThenThrowOnWait) throw Dead();
            return Task.FromResult(new WaitForConversationFullyIdleResponse { TimedOut = false });
        }
    }

    // New conversation (empty trajectory -> catalog REQUIRED) whose GetAvailableModels throws a dead-channel status.
    private sealed class FakeNewConvCatalogDownLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly string _cascadeId;
        private readonly StatusCode _status;
        private readonly List<CascadeStep> _steps = new();
        public FakeNewConvCatalogDownLs(string cascadeId, StatusCode status) { _cascadeId = cascadeId; _status = status; }

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
        {
            var traj = new CascadeTrajectory { CascadeId = _cascadeId };
            lock (_steps) traj.Steps.AddRange(_steps); // empty on the first ask -> new-conversation model path
            return Task.FromResult(new GetCascadeTrajectoryResponse { Trajectory = traj });
        }

        public override Task<GetAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
            => throw new RpcException(new Status(_status, "channel dead")); // catalog RPC dies -> wraps it

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
            => Task.FromResult(new SendUserCascadeMessageResponse());

        public override Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
            => Task.FromResult(new WaitForConversationFullyIdleResponse { TimedOut = false });
    }

    private static async Task<WebApplication> StartAsync<T>(T fake) where T : class
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(fake);
        var app = builder.Build();
        app.MapGrpcService<T>();
        await app.StartAsync();
        return app;
    }

    private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

    private static string SetUpAgyDir(int port, out string cliLog)
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-chdown-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return dir;
    }

    private static AgyView ViewFor(string cliLog) => new(new AgyViewOptions { CliLogPath = cliLog });

    [Fact]
    public async Task Dead_channel_agy_ask_returns_channel_down_not_a_bare_error()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var result = await McpTools.AgyAsk(ViewFor(cliLog), "hi", new CollectingProgress<ProgressNotificationValue>());
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
            Assert.Equal("Unavailable", doc.RootElement.GetProperty("diagnostic").GetProperty("StatusCode").GetString());
            Assert.False(string.IsNullOrEmpty(doc.RootElement.GetProperty("hint").GetString()));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Dead_channel_agy_look_returns_channel_down()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var json = await McpTools.AgyLook(ViewFor(cliLog));
            using var doc = JsonDocument.Parse(json);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Mid_ask_channel_death_returns_channel_down()
    {
        // Trajectory + send succeed; the channel dies during WaitFor -> the central catch still yields channel_down.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable, sendThenThrowOnWait: true);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var result = await McpTools.AgyAsk(ViewFor(cliLog), "hi", new CollectingProgress<ProgressNotificationValue>());
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task A_grpc_cancelled_status_is_not_reported_as_channel_down()
    {
        // F6 end-to-end (agy panel round 2, [VERDICT: REJECT] fold): a gRPC call cancelled by the outer token
        // surfaces as RpcException{StatusCode.Cancelled}. It must be EXCLUDED from channel_down and propagate as a
        // cancellation. NOTE the earlier draft pre-cancelled a local token, which threw OperationCanceledException
        // at ConnectAndResolveAsync's ThrowIfCancellationRequested BEFORE any gRPC call — trivially passing without
        // ever exercising the `rpc.StatusCode != StatusCode.Cancelled` guard. Force the guard by having the fake
        // surface a real RpcException{Cancelled} from the first RPC and asserting it propagates (NOT channel_down):
        // if the `!= StatusCode.Cancelled` exclusion were removed, IsChannelDown would return true and this would
        // instead return a channel_down AgyStatus (no throw), failing the assertion.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Cancelled); // GetCascadeTrajectory throws Cancelled
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var ex = await Assert.ThrowsAsync<RpcException>(() => McpTools.AgyStatus(ViewFor(cliLog)));
            Assert.Equal(StatusCode.Cancelled, ex.StatusCode); // propagated as a cancellation, not masked
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Dead_channel_on_a_new_conversation_ask_reports_channel_down_with_the_real_inner_status()
    {
        // F3 regression guard: the dead-channel RpcException wrapped as AgyModelUnavailableException on the
        // new-conversation catalog path must STILL surface as channel_down with the REAL inner status (F4), not
        // a bare error and not "Unknown".
        var fake = new FakeNewConvCatalogDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var result = await McpTools.AgyAsk(ViewFor(cliLog), "hi", new CollectingProgress<ProgressNotificationValue>());
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
            Assert.Equal("Unavailable", doc.RootElement.GetProperty("diagnostic").GetProperty("StatusCode").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Dead_channel_agy_status_returns_the_status_shape_with_channel_down_and_never_throws()
    {
        // Criterion 2 + F7: agy_status reports channel_down in its OWN AgyStatus shape (not the {status:...} error
        // envelope), never throws, and carries the diagnostic + hint.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable); // GetCascadeTrajectory throws
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var json = await McpTools.AgyStatus(ViewFor(cliLog));
            using var doc = JsonDocument.Parse(json);
            // AgyStatus shape has "State"/"Diagnostic"/"Hint"; the error envelope would have a lowercase "status".
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.False(doc.RootElement.TryGetProperty("status", out _));
            Assert.Equal("Unavailable", doc.RootElement.GetProperty("Diagnostic").GetProperty("StatusCode").GetString());
            Assert.False(string.IsNullOrEmpty(doc.RootElement.GetProperty("Hint").GetString()));
        }
        finally { Directory.Delete(dir, true); }
    }

    // Boot-race fake: the LS is reachable-but-EMPTY on the first discovery poll (which latches reachedLsButEmpty in
    // the buggy code), then the channel DIES on every subsequent poll. Drives the capstone-R2 latch regression.
    private sealed class FakeReachedEmptyThenDeadLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _discoveryCalls;

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            // Poll 1: reachable, but no conversation yet (empty map) -> ConnectAndResolve marks reachedLsButEmpty.
            // Poll 2+: the channel is dead. (BootRaceTimeout is generous so discovery succeeds and >=1 death poll
            // follows the empty one before the deadline — the last poll before the deadline is a death.)
            if (System.Threading.Interlocked.Increment(ref _discoveryCalls) == 1)
                return Task.FromResult(new GetAllCascadeTrajectoriesResponse());
            throw new RpcException(new Status(StatusCode.Unavailable, "agy died mid-boot-race"));
        }
    }

    [Fact]
    public async Task Boot_race_reached_empty_then_dead_reports_channel_down_not_waiting_for_human()
    {
        // Capstone R2 regression: reachedLsButEmpty must reflect only the MOST RECENT poll. If the LS is reached
        // empty once and then dies, the boot-race deadline must throw LsDiscoveryException (-> channel_down /
        // "restart the session"), NOT a latched AgyConversationPendingException (-> waiting_for_human), which would
        // trap the operator waiting on a dead server. On the pre-fix (latched) code agy_status returns the
        // waiting_for_human envelope (no "State" property), so GetProperty("State") throws and this test fails.
        var fake = new FakeReachedEmptyThenDeadLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            // Fixed: reachedLsButEmpty reflects only the LAST poll (a death) -> LsDiscoveryException at the deadline
            // -> channel_down AgyStatus (Diagnostic.StatusCode "LsDiscovery"). Buggy (latched): the stale empty-poll
            // flag throws AgyConversationPendingException -> the waiting_for_human envelope (lowercase "status", no
            // "State"), so GetProperty("State") throws and the test fails RED.
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.False(doc.RootElement.TryGetProperty("status", out _)); // NOT the waiting_for_human error envelope
            Assert.Equal("LsDiscovery", doc.RootElement.GetProperty("Diagnostic").GetProperty("StatusCode").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Boot_race_never_reachable_reports_channel_down()
    {
        // Gap-4: discovery (GetAllCascadeTrajectories) NEVER succeeds -- every poll throws the dead status, so
        // ConnectAndResolveAsync never obtains a client and hits the boot-race deadline with sawChannelDeath=true,
        // throwing LsDiscoveryException -> channel_down (NOT waiting_for_human, since reachedLsButEmpty never gets
        // set when every poll dies pre-flight). A SHORT BootRaceTimeout keeps this test fast.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable, throwOnDiscovery: true);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var result = await McpTools.AgyAsk(view, "hi", new CollectingProgress<ProgressNotificationValue>());
            var text = ((TextContentBlock)result.Content[0]).Text;
            using var doc = JsonDocument.Parse(text);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("status").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Boot_race_resolved_but_unanswered_reports_a_busy_peer_with_a_retry_hint()
    {
        // Backlog ls-discovery-misreports-a-busy-peer-as-exited: every poll reaches the LS and gets
        // DeadlineExceeded. The report must say the peer is alive and busy (LsUnanswered), not "starting or exited".
        var fake = new FakeChannelDownLs("conv-1", StatusCode.DeadlineExceeded, throwOnDiscovery: true);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var json = await McpTools.AgyStatus(ViewFor(cliLog));
            using var doc = JsonDocument.Parse(json);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.Equal("LsUnanswered", doc.RootElement.GetProperty("Diagnostic").GetProperty("StatusCode").GetString());
            var hint = doc.RootElement.GetProperty("Hint").GetString()!;
            Assert.Contains("RETRY", hint);
            Assert.DoesNotContain("shut down or restarted", hint);
        }
        finally { Directory.Delete(dir, true); }
    }

    private sealed class FakeDeadThenClampedLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _calls;

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            // Poll 1: a genuine death. Poll 2+: the clamped boot-race budget expires on the wire (DeadlineExceeded),
            // which says nothing about the peer. Deterministic on purpose: the reached-empty-then-dead row above only
            // reaches the DeadlineExceeded arm when its FINAL poll's remaining budget happens to expire before the
            // fake answers (a loopback race), so it pins `!sawChannelDeath` only by timing.
            if (System.Threading.Interlocked.Increment(ref _calls) == 1)
                throw new RpcException(new Status(StatusCode.Unavailable, "agy died mid-boot-race"));
            throw new RpcException(new Status(StatusCode.DeadlineExceeded, "clamped boot-race budget expired"));
        }
    }

    [Fact]
    public async Task Boot_race_death_then_a_clamped_final_poll_still_reports_a_dead_peer_not_a_busy_one()
    {
        // Test-audit Branch C: `else if (!sawChannelDeath) sawUnanswered = true;` in ConnectAndResolveAsync - a
        // DeadlineExceeded AFTER a death must not promote the dead peer to "busy, RETRY" (LsUnanswered), which would
        // send the operator retrying against a server that exited. Under the mutant that drops `!sawChannelDeath`
        // the deadline reports LsUnanswered and this row goes red.
        var fake = new FakeDeadThenClampedLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.Equal("LsDiscovery", doc.RootElement.GetProperty("Diagnostic").GetProperty("StatusCode").GetString());
            Assert.DoesNotContain("RETRY the call", doc.RootElement.GetProperty("Hint").GetString()!);
        }
        finally { Directory.Delete(dir, true); }
    }

    // A listening probe that says "open" for the first N polls and "closed" afterwards: the peer's port vanished
    // mid-boot-race (agy exited; LsDiscovery then throws on every later poll).
    private sealed class PortOpenThenClosed(int openPolls) : IListeningPorts
    {
        private int _calls;
        public bool IsListening(int port) => System.Threading.Interlocked.Increment(ref _calls) <= openPolls;
    }

    [Fact]
    public async Task Boot_race_unanswered_then_port_gone_reports_a_dead_peer_not_a_busy_one()
    {
        // Capstone Branch C R1: poll 1 reaches the LS and times out (DeadlineExceeded -> sawUnanswered), then the port
        // stops listening (agy exited) and every later poll is a discovery miss. The deadline must report the peer as
        // GONE (LsDiscovery), not as busy (LsUnanswered): a discovery miss is conclusive and must clear the stale flag.
        var fake = new FakeChannelDownLs("conv-1", StatusCode.DeadlineExceeded, throwOnDiscovery: true);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            }, new PortOpenThenClosed(1));
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.Equal("LsDiscovery", doc.RootElement.GetProperty("Diagnostic").GetProperty("StatusCode").GetString());
            Assert.DoesNotContain("busy", doc.RootElement.GetProperty("Diagnostic").GetProperty("Detail").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Boot_race_reached_empty_then_port_gone_reports_channel_down_not_waiting_for_human()
    {
        // Capstone Branch C R1 (pre-existing twin of the R2 latch): poll 1 reaches the LS EMPTY (reachedLsButEmpty),
        // then the port stops listening. The deadline must NOT tell the operator to wait for the human on a peer that
        // has exited; a discovery miss after a reach is as conclusive as a death.
        await using var app = await StartAsync(new FakeReachedEmptyForeverLs());
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            }, new PortOpenThenClosed(1));
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            // channel_down AgyStatus shape ("State"); the waiting_for_human envelope has a lowercase "status" instead.
            Assert.Equal("channel_down", doc.RootElement.GetProperty("State").GetString());
            Assert.False(doc.RootElement.TryGetProperty("status", out _));
        }
        finally { Directory.Delete(dir, true); }
    }

    // Boot-race fake: reachable-but-EMPTY, and on its FIRST discovery poll it deletes the cli.log (a rotation, a
    // cleanup, a transient unreadable file). Every later poll is an IOException from ReadCliLogText.
    private sealed class FakeEmptyThenLogVanishesLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _calls;
        public string? CliLogPath { get; set; } // set once the test knows the path (the app starts first)
        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            if (System.Threading.Interlocked.Increment(ref _calls) == 1 && CliLogPath is { } p) File.Delete(p);
            return Task.FromResult(new GetAllCascadeTrajectoriesResponse());
        }
    }

    [Fact]
    public async Task Boot_race_reached_empty_then_cli_log_unreadable_keeps_waiting_for_human()
    {
        // Capstone Branch C R2: a reach is stronger evidence than a later failure to READ the log. The LS was reached
        // (empty) and its port was never seen closed; an IOException from cli.log afterwards must NOT demote that to
        // channel_down ("starting or exited") at the deadline. Only a resolved port that is NOT LISTENING is conclusive.
        var fake = new FakeEmptyThenLogVanishesLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        fake.CliLogPath = cliLog;
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                // Generous on purpose: the fake answers poll 1 at once and deletes the log, so the REACH must not depend on
                // how fast the first gRPC call runs on a loaded runner (a 2s budget failed 2 of 3 under load). The verdict
                // is only issued at the deadline by design, so this costs the test the budget, not the runner's speed.
                BootRaceTimeout = TimeSpan.FromSeconds(10),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            // waiting_for_human envelope (lowercase "status"); channel_down would be the AgyStatus shape with "State".
            Assert.True(doc.RootElement.TryGetProperty("status", out var st), json);
            Assert.Equal("waiting_for_human", st.GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    // Boot-race fake: reachable-but-EMPTY. Poll 1 answers at once (so the reach never depends on runner speed);
    // every later reply takes longer than the budget's final remainder, so the last poll before the deadline is a
    // clamped DeadlineExceeded against a healthy LS (capstone Branch C R3: a slow CI runner must not be able to
    // clamp the FIRST poll and fail the row for a reason unrelated to the behaviour it pins).
    private sealed class FakeSlowEmptyLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _calls;
        public override async Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            if (System.Threading.Interlocked.Increment(ref _calls) > 1) await Task.Delay(400);
            return new GetAllCascadeTrajectoriesResponse();
        }
    }

    [Fact]
    public async Task Boot_race_reached_empty_whose_final_poll_is_clamped_still_reports_waiting_for_human()
    {
        // Capstone Branch C R2 (pins the REJECTED finding R2-1): the final poll of a healthy always-empty LS times out
        // because the remaining budget is clamped to a sliver - that DeadlineExceeded is the clamp expiring, not
        // evidence about the peer, so it must not demote reached-empty to "busy" (LsUnanswered) or channel_down.
        await using var app = await StartAsync(new FakeSlowEmptyLs());
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            Assert.True(doc.RootElement.TryGetProperty("status", out var st), json);
            Assert.Equal("waiting_for_human", st.GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    // Boot-race fake: reachable-but-EMPTY, and on its FIRST discovery poll it TRUNCATES the cli.log to zero bytes (a
    // rotation that recreates the file). Every later poll is an LsDiscoveryException from ParseLatest ("cli.log is
    // empty") with PortNotListening = false - a discovery miss that says nothing about the peer.
    private sealed class FakeEmptyThenLogTruncatedLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _calls;
        public string? CliLogPath { get; set; }
        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            if (System.Threading.Interlocked.Increment(ref _calls) == 1 && CliLogPath is { } p) File.WriteAllText(p, "");
            return Task.FromResult(new GetAllCascadeTrajectoriesResponse());
        }
    }

    [Fact]
    public async Task Boot_race_reached_empty_then_cli_log_truncated_keeps_waiting_for_human()
    {
        // Capstone Branch C R4: pins the CONDITION on the LsDiscoveryException arm. Only PortNotListening may clear an
        // earlier reach; a log that no longer parses (PortNotListening = false) must not. Dropping the condition and
        // clearing unconditionally turns this row into channel_down.
        var fake = new FakeEmptyThenLogTruncatedLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        fake.CliLogPath = cliLog;
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            Assert.True(doc.RootElement.TryGetProperty("status", out var st), json);
            Assert.Equal("waiting_for_human", st.GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    // Boot-race fake: reachable, but no conversation, on every poll.
    private sealed class FakeReachedEmptyForeverLs : LanguageServerService.LanguageServerServiceBase
    {
        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context) =>
            Task.FromResult(new GetAllCascadeTrajectoriesResponse());
    }

    // Boot-race fake: a TRANSIENT death on the first discovery poll (the LS has bound the port but its gRPC
    // service is not ready yet -> Unavailable), then reachable-but-EMPTY forever (the LS is up, waiting for the
    // human to start a conversation). Drives the capstone-R3 "flapping" regression.
    private sealed class FakeTransientThenEmptyLs : LanguageServerService.LanguageServerServiceBase
    {
        private int _discoveryCalls;

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            if (System.Threading.Interlocked.Increment(ref _discoveryCalls) == 1)
                throw new RpcException(new Status(StatusCode.Unavailable, "gRPC service still binding"));
            return Task.FromResult(new GetAllCascadeTrajectoriesResponse()); // reachable but empty -> waiting_for_human
        }
    }

    // Auth-refusal fake: GetAllCascadeTrajectories throws Unauthenticated (a CSRF/auth refusal is definitive, not a
    // transient boot-race miss) so ConnectAndResolveAsync's new Unauthenticated/PermissionDenied catch must
    // propagate it — landing in StatusAsync's ChannelDown catch as "auth_failed", never latched into
    // sawChannelDeath/"channel_down".
    private sealed class UnauthLs : LanguageServerService.LanguageServerServiceBase
    {
        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
            => throw new RpcException(new Status(StatusCode.Unauthenticated, "missing CSRF token"));
    }

    [Fact]
    public async Task Dead_channel_agy_status_reports_auth_failed_not_channel_down_on_unauthenticated()
    {
        var fake = new UnauthLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog); // no endpoint file -> cli.log path, no token.
        try
        {
            var json = await McpTools.AgyStatus(ViewFor(cliLog));
            using var doc = JsonDocument.Parse(json);
            Assert.Equal("auth_failed", doc.RootElement.GetProperty("State").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Boot_race_transient_death_then_reached_empty_reports_waiting_for_human_not_channel_down()
    {
        // Capstone R3 regression: sawChannelDeath must reflect only the MOST RECENT conclusive poll, so a healthy
        // LS whose gRPC service throws a transient Unavailable while still binding (poll 1) and then comes up empty
        // (poll 2+, waiting for the human) must yield waiting_for_human -- NOT a latched channel_down. On the pre-fix
        // code sawChannelDeath latches from poll 1 and never clears, so the deadline throws LsDiscoveryException ->
        // channel_down (an AgyStatus with "State", no lowercase "status"), and GetProperty("status") throws RED.
        var fake = new FakeTransientThenEmptyLs();
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                BootRaceTimeout = TimeSpan.FromSeconds(2),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });
            var json = await McpTools.AgyStatus(view);
            using var doc = JsonDocument.Parse(json);
            // waiting_for_human is the RunAsync error envelope (lowercase "status"); channel_down would be the
            // AgyStatus shape ("State"). Asserting the envelope pins that the transient death did NOT latch.
            Assert.Equal("waiting_for_human", doc.RootElement.GetProperty("status").GetString());
            Assert.False(doc.RootElement.TryGetProperty("State", out _));
        }
        finally { Directory.Delete(dir, true); }
    }

    // AGY-FIRST clavity-ls-logging: a FAULT reply carries the ring, so the failing reply itself says what the server did.
    [Fact]
    public async Task Dead_channel_agy_status_carries_the_ring_ending_in_its_own_fault()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var log = new LsEventLog();
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Events = log });
            var json = await McpTools.AgyStatus(view);

            using var doc = JsonDocument.Parse(json);
            var ring = doc.RootElement.GetProperty("RecentEvents").EnumerateArray()
                .Select(e => JsonDocument.Parse(e.GetString()!).RootElement.Clone()).ToArray();
            Assert.Equal("start", ring[0].GetProperty("phase").GetString());
            Assert.Equal("agy_status", ring[0].GetProperty("tool").GetString());
            // The reply is built inside StatusAsync's catch, before the tool wrapper records its end event, so the view
            // records a `fault` event first: the ring in the reply ends AT the fault, not one step short of it.
            Assert.Equal("fault", ring[^1].GetProperty("phase").GetString());
            Assert.Equal("channel_down", ring[^1].GetProperty("outcome").GetString());
            // ...and the log goes on to close the call with the same outcome.
            var last = JsonDocument.Parse(log.Snapshot()[^1]).RootElement;
            Assert.Equal("end", last.GetProperty("phase").GetString());
            Assert.Equal("channel_down", last.GetProperty("outcome").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Dead_channel_agy_status_names_the_log_file_and_its_call_id()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var logPath = Path.Combine(dir, "events-under-test.log");
            using (var log = new LsEventLog(filePath: logPath))
            {
                var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Events = log });
                var json = await McpTools.AgyStatus(view);

                using var doc = JsonDocument.Parse(json);
                Assert.Equal(logPath, doc.RootElement.GetProperty("LogPath").GetString());
                Assert.False(doc.RootElement.TryGetProperty("LogNote", out _));
                var callId = doc.RootElement.GetProperty("CallId").GetString()!;
                Assert.Matches(@"^p\d+-\d{6}$", callId);
                var fault = JsonDocument.Parse(doc.RootElement.GetProperty("RecentEvents").EnumerateArray().Last().GetString()!).RootElement;
                Assert.Equal("fault", fault.GetProperty("phase").GetString());
                Assert.Equal(callId, fault.GetProperty("call").GetString());
            }
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Dead_channel_agy_status_with_a_memory_only_log_says_so()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Events = new LsEventLog() });
            var json = await McpTools.AgyStatus(view);

            using var doc = JsonDocument.Parse(json);
            Assert.False(doc.RootElement.TryGetProperty("LogPath", out _));
            Assert.Equal(LsEventLog.MemoryOnlyNote, doc.RootElement.GetProperty("LogNote").GetString());
            Assert.True(doc.RootElement.TryGetProperty("CallId", out _));
        }
        finally { Directory.Delete(dir, true); }
    }

    [Fact]
    public async Task Dead_channel_agy_ask_envelope_carries_the_ring_including_its_end_event()
    {
        var fake = new FakeChannelDownLs("conv-1", StatusCode.Unavailable);
        await using var app = await StartAsync(fake);
        var dir = SetUpAgyDir(PortOf(app), out var cliLog);
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog, Events = new LsEventLog() });
            var result = await McpTools.AgyAsk(view, "hi", new CollectingProgress<ProgressNotificationValue>());

            using var doc = JsonDocument.Parse(((TextContentBlock)result.Content[0]).Text);
            var ring = doc.RootElement.GetProperty("recentEvents").EnumerateArray()
                .Select(e => JsonDocument.Parse(e.GetString()!).RootElement.Clone()).ToArray();
            // AGY-TEST-AUDIT GAP-PP1: the ring starts at the call's own start event, so nothing before the last is lost.
            Assert.Equal("start", ring[0].GetProperty("phase").GetString());
            Assert.Equal("agy_ask", ring[0].GetProperty("tool").GetString());
            var last = ring[^1];
            Assert.Equal("end", last.GetProperty("phase").GetString());
            Assert.Equal("agy_ask", last.GetProperty("tool").GetString());
            Assert.Equal("channel_down", last.GetProperty("outcome").GetString());
        }
        finally { Directory.Delete(dir, true); }
    }
}
