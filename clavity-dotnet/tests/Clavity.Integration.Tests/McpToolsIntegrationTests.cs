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
using ModelContextProtocol.Server;
using Grpc.Core;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Clavity.Integration.Tests;

// T4 (integration, CI): the agy_look MCP tool over the in-proc fake LS — proves the tool delegates
// to AgyView and serializes a bounded view. (Full MCP-transport coverage is unnecessary: the tool is a thin
// wrapper; AgyView's own integration test covers discover->connect->read->bound.)
[Collection("McpTools")]
public class McpToolsIntegrationTests
{
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void Init() => McpTools.WarmParameterCache();

    private sealed class FakeLs : LanguageServerService.LanguageServerServiceBase
    {
        private readonly GetCascadeTrajectoryResponse _trajectory;
        private readonly string _cascadeId;
        private int _remainingEmptyPolls;

        public FakeLs(GetCascadeTrajectoryResponse trajectory)
        {
            _trajectory = trajectory;
            _cascadeId = "cascade-1";
        }

        public FakeLs(string cascadeId, int emptyMapPolls = 0)
        {
            _cascadeId = cascadeId;
            _remainingEmptyPolls = emptyMapPolls;
            _trajectory = new GetCascadeTrajectoryResponse { Trajectory = new CascadeTrajectory { CascadeId = cascadeId } };
        }

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            if (_remainingEmptyPolls > 0)
            {
                _remainingEmptyPolls--; // simulate "conversation not created yet" for N polls.
            }
            else
            {
                resp.TrajectorySummaries[_cascadeId] = new CascadeTrajectorySummary
                {
                    LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
                };
            }
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(_trajectory);

        public override Task<GetAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
            => Task.FromResult(new GetAvailableModelsResponse
            {
                AvailableModels = new FetchAvailableModelsResponse
                {
                    DefaultAgentModelId = "key1",
                    Models = { { "key1", new ModelDetails { Model = 1 } } }
                }
            });

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
        {
            var text = request.Items.Count > 0 ? request.Items[0].Text : "";
            _trajectory.Trajectory.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = text } });
            _trajectory.Trajectory.Steps.Add(new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "{\"status\": \"idle\"}" } });
            return Task.FromResult(new SendUserCascadeMessageResponse());
        }

        public override Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
            => Task.FromResult(new WaitForConversationFullyIdleResponse());
    }

    private static async Task<WebApplication> StartFakeAsync(GetCascadeTrajectoryResponse traj)
        => await StartFakeAsync(new FakeLs(traj));

    private static async Task<WebApplication> StartFakeAsync(FakeLs fake)
    {
        var builder = WebApplication.CreateBuilder();
        builder.WebHost.ConfigureKestrel(o => o.ConfigureEndpointDefaults(lo => lo.Protocols = HttpProtocols.Http2));
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Services.AddGrpc();
        builder.Services.AddSingleton(fake);
        var app = builder.Build();
        app.MapGrpcService<FakeLs>();
        await app.StartAsync();
        return app;
    }

    private static int PortOf(WebApplication app) => new Uri(app.Urls.Single()).Port;

    private static string WriteCliLog(int port)
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-mcptool-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var cliLog = Path.Combine(dir, "cli.log");
        File.WriteAllText(cliLog,
            $"I0628 09:29:34.284332 16268 server.go:517] Language server listening on random port at {port - 1} for HTTPS (gRPC)\n" +
            $"I0628 09:29:34.290337 16268 server.go:525] Language server listening on random port at {port} for HTTP\n");
        return cliLog;
    }

    [Fact]
    public async Task Agy_look_tool_returns_bounded_view_json()
    {
        var traj = new GetCascadeTrajectoryResponse
        {
            NumTotalSteps = 1,
            Trajectory = new CascadeTrajectory
            {
                CascadeId = "cascade-1",
                Steps = { new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "hi" } } },
            },
        };

        await using var app = await StartFakeAsync(traj);
        var cliLog = WriteCliLog(PortOf(app));

        var dir = Path.GetDirectoryName(cliLog)!;
        try
        {
            var view = new AgyView(new AgyViewOptions { CliLogPath = cliLog });
            var json = await McpTools.AgyLook(view);

            using var doc = JsonDocument.Parse(json);
            Assert.Equal("cascade-1", doc.RootElement.GetProperty("CascadeId").GetString());
            Assert.Equal(1, doc.RootElement.GetProperty("TotalSteps").GetInt32());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task Agy_look_tool_returns_waiting_json_when_no_conversation()
    {
        var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: int.MaxValue);
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));

        var dir = Path.GetDirectoryName(cliLog)!;
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                // Realistic budget (finding B): the boot call is now deadline-bounded, so a small budget would
                // deadline-kill the cold first call before the empty map returns. 5s lets the LS prove reachable.
                BootRaceTimeout = TimeSpan.FromSeconds(5),
                BootRacePollInterval = TimeSpan.FromMilliseconds(50),
            });

            var json = await McpTools.AgyLook(view);

            using var doc = JsonDocument.Parse(json);
            Assert.Equal("waiting_for_human", doc.RootElement.GetProperty("status").GetString());
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public async Task AgyAsk_first_call_appends_driver_guidance_block_then_omits_it()
    {
        var fake = new FakeLs(cascadeId: "cascade-1", emptyMapPolls: 0);
        await using var app = await StartFakeAsync(fake);
        var cliLog = WriteCliLog(PortOf(app));
        var dir = Path.GetDirectoryName(cliLog)!;

        var cheatDir = Path.Combine(Path.GetTempPath(), "clavity-dg-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(cheatDir);
        try
        {
            var view = new AgyView(new AgyViewOptions
            {
                CliLogPath = cliLog,
                GoldenHeaderDir = cheatDir
            });

            // ASSERT WHICH BLOCK, NOT HOW MANY. This row is about ONE property - the driver guidance is
            // appended exactly once per session - and it used to pin the total block count to enforce it.
            // 13b appends its own notices, so a count assertion here now reds on a change that has
            // nothing to do with guidance. Identify the guidance block by its label instead.
            var first = await McpTools.AgyAsk(view, "hello", new CollectingProgress<ProgressNotificationValue>());
            var firstTexts = first.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains("\"Answer\"", firstTexts[0]);                          // block 0 is the AskReply JSON
            var guidance = Assert.Single(firstTexts, t => t.StartsWith(DriverCheatsheet.Label));
            Assert.Contains("Verify what it volunteers", guidance);               // baseline-floor content

            // Second ask: no guidance (once per session).
            var second = await McpTools.AgyAsk(view, "again", new CollectingProgress<ProgressNotificationValue>());
            var secondTexts = second.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            Assert.Contains("\"Answer\"", secondTexts[0]);
            Assert.DoesNotContain(secondTexts, t => t.StartsWith(DriverCheatsheet.Label));
        }
        finally
        {
            Directory.Delete(dir, true);
            Directory.Delete(cheatDir, true);
        }
    }
    [Fact]
    public void AgyAsk_input_schema_exposes_only_message_and_stays_backward_compatible()
    {
        // The progress reporter was added to AgyAsk as an SDK-INJECTED parameter, on the claim that it costs no
        // contract change. This pins that claim to the GENERATED schema rather than to the claim itself: if
        // IProgress<> ever started surfacing as a tool input, every existing caller's payload would become invalid
        // and nothing else in this suite would notice. The DI'd AgyView and the CancellationToken are pinned for the
        // same reason - all three are parameters the model must never be asked to supply.
        var services = new ServiceCollection();
        services.AddSingleton(new AgyView(new AgyViewOptions { CliLogPath = Path.Combine(Path.GetTempPath(), "schema-pin-unused.log") }));
        services.AddMcpServer().WithTools<McpTools>();
        using var sp = services.BuildServiceProvider();

        var tool = sp.GetServices<McpServerTool>().Single(t => t.ProtocolTool.Name == "agy_ask");
        using var schema = JsonDocument.Parse(tool.ProtocolTool.InputSchema.GetRawText());
        var root = schema.RootElement;

        // ASSERT WHAT THE COMMENT ABOVE ACTUALLY CLAIMS: the three INJECTED parameters never surface as
        // model-supplied inputs. The old form of this row froze the property list to exactly ["message"],
        // which pins something stronger and less meaningful - it reds the moment any deliberate optional
        // input is added (13b added two), while saying nothing extra about the injected three.
        var props = root.GetProperty("properties").EnumerateObject().Select(p => p.Name).ToArray();
        Assert.DoesNotContain("view", props);
        Assert.DoesNotContain("progress", props);
        Assert.DoesNotContain("cancellationToken", props);

        // BACKWARD COMPATIBILITY IS THE `required` SET, NOT THE PROPERTY SET. An existing caller sending
        // only {"message": ...} stays valid exactly as long as nothing else is required.
        var required = root.GetProperty("required").EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.Equal(new[] { "message" }, required);
    }

    [Fact]
    public void AgyAsk_13b_parameters_are_present_and_OPTIONAL_in_the_generated_schema()
    {
        // 13b adds two parameters. If either landed in `required`, every existing agy_ask caller would
        // break - and it would break silently at the protocol layer, not in any C# test. Pin optionality,
        // not just presence.
        //
        // The parameters are `discipline` and `artifactPath`. Neither is a value the caller computes:
        // the driver owns the token table AND now reads the artifact to derive the echo target itself.
        // This row has been re-pointed twice as that surface settled - first off `expectTerminal` when
        // the owner ruled the driver owns the tokens, then off `expectEcho` when the R8 trim moved the
        // echo derivation into the driver. Each time the old name would have pinned a parameter that no
        // longer exists, which is why the row asserts by NAME and not by count.
        var services = new ServiceCollection();
        services.AddSingleton(new AgyView(new AgyViewOptions { CliLogPath = Path.Combine(Path.GetTempPath(), "schema-pin-13b-unused.log") }));
        services.AddMcpServer().WithTools<McpTools>();
        using var sp = services.BuildServiceProvider();

        var tool = sp.GetServices<McpServerTool>().Single(t => t.ProtocolTool.Name == "agy_ask");
        using var schema = JsonDocument.Parse(tool.ProtocolTool.InputSchema.GetRawText());
        var root = schema.RootElement;

        var props = root.GetProperty("properties");
        Assert.True(props.TryGetProperty("discipline", out _));
        Assert.True(props.TryGetProperty("artifactPath", out _));

        var required = root.GetProperty("required").EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.DoesNotContain("discipline", required);
        Assert.DoesNotContain("artifactPath", required);
    }

    [Fact]
    public void AgyAsk_input_schema_never_leaks_progress_under_concurrent_cold_registration()
    {
        // Regression test for the RuntimeMethodInfo.m_parameters race in Microsoft.Extensions.AI's
        // ReflectionAIFunctionDescriptor..ctor: when two threads call WithTools<McpTools>() simultaneously
        // on a cold MethodInfo, concurrent GetParameters() allocations cause Dictionary<ParameterInfo, ...>
        // reference-equality lookups to miss ExcludeFromSchema=true for IProgress<ProgressNotificationValue>.
        var method = typeof(McpTools).GetMethods().Single(m => m.Name == nameof(McpTools.AgyAsk) && !m.IsStatic);
        var paramCacheField = method.GetType().GetField("m_parameters",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic);
        Assert.NotNull(paramCacheField);

        try
        {
            for (var round = 0; round < 20; round++)
            {
                paramCacheField!.SetValue(method, null);
                McpTools.WarmParameterCache();

                using var barrier = new System.Threading.Barrier(4);
                var leaked = new System.Collections.Concurrent.ConcurrentBag<string[]>();
                Parallel.For(0, 4, _ =>
                {
                    var services = new ServiceCollection();
                    services.AddSingleton(new AgyView(new AgyViewOptions
                    {
                        CliLogPath = Path.Combine(Path.GetTempPath(), "schema-race-unused.log")
                    }));
                    services.AddMcpServer().WithTools<McpTools>();
                    using var sp = services.BuildServiceProvider();
                    barrier.SignalAndWait();
                    var tool = sp.GetServices<McpServerTool>().Single(t => t.ProtocolTool.Name == "agy_ask");
                    using var schema = JsonDocument.Parse(tool.ProtocolTool.InputSchema.GetRawText());
                    var props = schema.RootElement.GetProperty("properties").EnumerateObject().Select(p => p.Name).ToArray();
                    if (props.Contains("progress"))
                        leaked.Add(props);
                });
                Assert.Empty(leaked);
            }
        }
        finally
        {
            McpTools.WarmParameterCache();
        }
    }

    // ---- conversation-switch notice (backlog item ask-silently-follows-conversation-switch) ----

    // Serves several conversations. Each map KEY (the conversation id) maps to a trajectory whose own CascadeId is a
    // DIFFERENT string, as real agy does (ROADMAP.md section 20, T1 measurement), so a conversation-id key and a CascadeId
    // key are distinguishable in a test. MakeMostRecent moves the "most recently active" pointer between asks;
    // RenewTrajectory changes a conversation's trajectory id while its key stays; FailNextSendTo makes the next send throw.
    private sealed class SwitchableLs : LanguageServerService.LanguageServerServiceBase
    {
        private sealed class Conv
        {
            public string TrajectoryId { get; set; } = "";
            public List<CascadeStep> Steps { get; } = new();
            public DateTimeOffset LastModified { get; set; }
        }

        private static readonly DateTimeOffset Base = new(2026, 1, 1, 0, 0, 0, TimeSpan.Zero);
        private readonly object _gate = new();
        private readonly Dictionary<string, Conv> _convs = new(StringComparer.Ordinal);
        private readonly HashSet<string> _failNext = new(StringComparer.Ordinal);
        private int _tick;
        private TaskCompletionSource? _waitEntered;

        /// <summary>While true, WaitForConversationFullyIdle blocks until the caller's window or token cancels it, so the
        /// ask is still inside its wait (stalled, cancelled or timed out), never delivered.</summary>
        public volatile bool HangWaits;

        /// <summary>While true, appended assistant steps carry the DONE status, so a hung wait ends the TURN and the
        /// reply is delivered as PeerStillBusy instead of stalling.</summary>
        public volatile bool AssistantDone;

        // Armed by the test, completed when a wait begins: lets a test cancel an ask that is PROVABLY inside its wait.
        public Task ArmWaitSignal()
        {
            var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            lock (_gate) _waitEntered = tcs;
            return tcs.Task;
        }

        public SwitchableLs(params (string Key, string TrajectoryId)[] conversations)
        {
            foreach (var (key, trajectoryId) in conversations)
                _convs[key] = new Conv { TrajectoryId = trajectoryId, LastModified = Base };
            MakeMostRecent(conversations[0].Key);
        }

        // A strictly increasing time, so no two conversations ever tie (DateTimeOffset.UtcNow could).
        public void MakeMostRecent(string key)
        {
            lock (_gate) _convs[key].LastModified = Base.AddMinutes(++_tick);
        }

        public void RenewTrajectory(string key, string newTrajectoryId)
        {
            lock (_gate) _convs[key].TrajectoryId = newTrajectoryId;
        }

        public void FailNextSendTo(string key)
        {
            lock (_gate) _failNext.Add(key);
        }

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            var resp = new GetAllCascadeTrajectoriesResponse();
            lock (_gate)
                foreach (var (key, conv) in _convs)
                    resp.TrajectorySummaries[key] = new CascadeTrajectorySummary
                    {
                        LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(conv.LastModified),
                    };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
        {
            lock (_gate)
            {
                var conv = _convs[request.CascadeId];   // the request carries the conversation KEY
                var trajectory = new CascadeTrajectory { CascadeId = conv.TrajectoryId };
                trajectory.Steps.AddRange(conv.Steps);
                return Task.FromResult(new GetCascadeTrajectoryResponse { NumTotalSteps = (uint)conv.Steps.Count, Trajectory = trajectory });
            }
        }

        public override Task<GetAvailableModelsResponse> GetAvailableModels(
            FetchAvailableModelsRequest request, ServerCallContext context)
            => Task.FromResult(new GetAvailableModelsResponse
            {
                AvailableModels = new FetchAvailableModelsResponse
                {
                    DefaultAgentModelId = "key1",
                    Models = { { "key1", new ModelDetails { Model = 1 } } }
                }
            });

        public override Task<SendUserCascadeMessageResponse> SendUserCascadeMessage(
            SendUserCascadeMessageRequest request, ServerCallContext context)
        {
            lock (_gate)
            {
                if (_failNext.Remove(request.CascadeId))
                    throw new RpcException(new Status(StatusCode.Internal, "boom"));
                var conv = _convs[request.CascadeId];
                var text = request.Items.Count > 0 ? request.Items[0].Text : "";
                conv.Steps.Add(new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = text } });
                var reply = new CascadeStep { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = "ok" } };
                if (AssistantDone) reply.Status = StepKind.DoneStatus;
                conv.Steps.Add(reply);
            }
            return Task.FromResult(new SendUserCascadeMessageResponse());
        }

        public override async Task<WaitForConversationFullyIdleResponse> WaitForConversationFullyIdle(
            WaitForConversationFullyIdleRequest request, ServerCallContext context)
        {
            TaskCompletionSource? signal;
            lock (_gate) { signal = _waitEntered; _waitEntered = null; }
            signal?.TrySetResult();
            if (HangWaits) await Task.Delay(Timeout.Infinite, context.CancellationToken);   // ends when the client cancels
            return new WaitForConversationFullyIdleResponse();
        }
    }

    // A fake LS plus a real AgyView pointed at it. AskAsync never assumes the ask succeeded: a failed ask comes back as the
    // server's error payload in block 0, which is what a driver would see.
    private sealed class SwitchRig : IAsyncDisposable
    {
        private readonly WebApplication _app;
        private readonly string _dir;
        public SwitchableLs Fake { get; }
        public AgyView View { get; }
        /// <summary>A file with a substantive last line, for a discipline ask's echo check.</summary>
        public string ArtifactPath { get; }

        private SwitchRig(WebApplication app, string dir, SwitchableLs fake, AgyView view)
        {
            _app = app;
            _dir = dir;
            Fake = fake;
            View = view;
            ArtifactPath = Path.Combine(dir, "artifact.md");
            File.WriteAllText(ArtifactPath, "# artifact\nthe last substantive line of the artifact under review\n");
        }

        public static Task<SwitchRig> StartAsync(params (string Key, string TrajectoryId)[] conversations)
            => StartCoreAsync(null, conversations);

        /// <summary>A short idle-stall window, so an ask whose wait hangs ends in a stall (or, with a DONE reply, a
        /// PeerStillBusy delivery) in well under a second.</summary>
        public static Task<SwitchRig> StartWithStallWindowAsync(TimeSpan stallWindow, params (string Key, string TrajectoryId)[] conversations)
            => StartCoreAsync(stallWindow, conversations);

        private static async Task<SwitchRig> StartCoreAsync(TimeSpan? stallWindow, (string Key, string TrajectoryId)[] conversations)
        {
            var fake = new SwitchableLs(conversations);
            var app = await FakeLsHost.StartAsync(fake);
            var cliLog = WriteCliLog(PortOf(app));
            var options = new AgyViewOptions { CliLogPath = cliLog };
            if (stallWindow is { } w) options = new AgyViewOptions { CliLogPath = cliLog, IdleStallWindow = w, IdleAbsoluteMax = TimeSpan.Zero };
            return new SwitchRig(app, Path.GetDirectoryName(cliLog)!, fake, new AgyView(options));
        }

        public async Task<(string Json, List<string> Blocks)> AskAsync(
            string message = "q", string? discipline = null, string? artifactPath = null, CancellationToken cancellationToken = default)
        {
            var result = await McpTools.AgyAsk(View, message, new CollectingProgress<ProgressNotificationValue>(),
                discipline, artifactPath, cancellationToken);
            var blocks = result.Content.OfType<TextContentBlock>().Select(b => b.Text).ToList();
            return (blocks[0], blocks);
        }

        public async ValueTask DisposeAsync()
        {
            await _app.DisposeAsync();
            try { Directory.Delete(_dir, true); } catch (IOException) { /* a late log flush; the temp dir is disposable */ }
        }
    }

    private static string? PreviousOf(string json)
        => JsonDocument.Parse(json).RootElement.TryGetProperty("PreviousCascadeId", out var p) ? p.GetString() : null;

    private static string CascadeIdOf(string json)
        => JsonDocument.Parse(json).RootElement.GetProperty("CascadeId").GetString()!;

    // Parse, do not substring-match: the event log's default JSON encoder writes '>' as > (LsEventLog.cs, Json options).
    private static List<JsonElement> SwitchEvents(AgyView view)
        => view.Events.Snapshot()
            .Select(line => JsonDocument.Parse(line).RootElement)
            .Where(e => e.GetProperty("phase").GetString() == "conv_switch")
            .ToList();

    [Fact]
    public async Task First_ask_has_no_PreviousCascadeId()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        var first = await rig.AskAsync();
        Assert.DoesNotContain("PreviousCascadeId", first.Json);
        Assert.Equal("traj-A", CascadeIdOf(first.Json));
    }

    [Fact]
    public async Task Control_same_conversation_twice_has_no_PreviousCascadeId_and_no_event()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        var first = await rig.AskAsync();
        var second = await rig.AskAsync();
        Assert.DoesNotContain("PreviousCascadeId", first.Json);
        Assert.DoesNotContain("PreviousCascadeId", second.Json);
        Assert.Equal("traj-A", CascadeIdOf(second.Json));
        Assert.Empty(SwitchEvents(rig.View));
    }

    [Fact]
    public async Task Switch_sets_PreviousCascadeId_once_and_the_next_ask_in_the_same_conversation_has_none()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-B");
        var second = await rig.AskAsync();
        Assert.Equal("traj-A", PreviousOf(second.Json));
        Assert.Equal("traj-B", CascadeIdOf(second.Json));

        var third = await rig.AskAsync();   // still conv-B: the switch was already reported
        Assert.DoesNotContain("PreviousCascadeId", third.Json);
        Assert.Equal("traj-B", CascadeIdOf(third.Json));
    }

    [Fact]
    public async Task Renewed_trajectory_id_in_the_same_conversation_is_not_a_switch()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.RenewTrajectory("conv-A", "traj-A2");   // same conversation key, new trajectory id
        var second = await rig.AskAsync();
        Assert.DoesNotContain("PreviousCascadeId", second.Json);
        Assert.Equal("traj-A2", CascadeIdOf(second.Json));
        Assert.Empty(SwitchEvents(rig.View));
    }

    [Fact]
    public async Task Switching_back_reports_each_switch_with_the_last_delivered_id_as_previous()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-B");
        var toB = await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-A");
        var backToA = await rig.AskAsync();
        Assert.Equal("traj-A", PreviousOf(toB.Json));
        Assert.Equal("traj-B", PreviousOf(backToA.Json));
        Assert.Equal("traj-A", CascadeIdOf(backToA.Json));
    }

    [Fact]
    public async Task Failed_ask_does_not_advance_the_switch_state()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();                       // delivered in A
        rig.Fake.MakeMostRecent("conv-B");
        rig.Fake.FailNextSendTo("conv-B");
        await rig.AskAsync();                       // goes to B and fails: nothing is delivered
        var third = await rig.AskAsync();           // B again, now delivered
        Assert.Equal("traj-A", PreviousOf(third.Json));   // the last DELIVERED reply was A's, not the failed B ask
        Assert.Equal("traj-B", CascadeIdOf(third.Json));
    }

    [Fact]
    public async Task Switch_records_one_conv_switch_event()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-B");
        await rig.AskAsync();
        var events = SwitchEvents(rig.View);
        var only = Assert.Single(events);
        Assert.Equal("traj-A->traj-B", only.GetProperty("outcome").GetString());
        Assert.Equal("agy_ask", only.GetProperty("tool").GetString());
    }

    private static List<string> ConvBlocks(List<string> blocks)
        => blocks.Where(b => b.StartsWith("[conv]", StringComparison.Ordinal)).ToList();

    [Fact]
    public async Task Switch_appends_a_directed_conv_block_naming_both_trajectory_ids()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-B");
        var second = await rig.AskAsync();
        var block = Assert.Single(ConvBlocks(second.Blocks));
        // One substring, so a notice with the two ids swapped cannot pass.
        Assert.Contains("[conv] CONVERSATION CHANGED: traj-A -> traj-B;", block);
        Assert.Contains("may lack the earlier rounds", block);
        Assert.Contains("treat it as a first brief unless you know they are in this conversation.", block);

        var third = await rig.AskAsync();   // same conversation again: the switch was already reported
        Assert.Empty(ConvBlocks(third.Blocks));
    }

    [Fact]
    public async Task Switching_back_names_the_last_delivered_id_in_the_conv_block()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-B");
        var toB = await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-A");
        var backToA = await rig.AskAsync();
        // Index by prefix, not position: block positions differ from ask to ask.
        Assert.Contains("[conv] CONVERSATION CHANGED: traj-A -> traj-B;", Assert.Single(ConvBlocks(toB.Blocks)));
        Assert.Contains("[conv] CONVERSATION CHANGED: traj-B -> traj-A;", Assert.Single(ConvBlocks(backToA.Blocks)));
    }

    [Fact]
    public async Task No_conv_block_on_first_ask_control_or_renewal()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        var first = await rig.AskAsync();
        var control = await rig.AskAsync();
        rig.Fake.RenewTrajectory("conv-A", "traj-A2");
        var renewed = await rig.AskAsync();
        Assert.Empty(ConvBlocks(first.Blocks));
        Assert.Empty(ConvBlocks(control.Blocks));
        Assert.Empty(ConvBlocks(renewed.Blocks));
    }

    // ---- test-audit gaps G1-G3 (2026-11-18) ----

    [Fact]
    public async Task Switch_after_in_conversation_renewal_reports_the_renewed_id_as_previous()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.RenewTrajectory("conv-A", "traj-A2");
        await rig.AskAsync();                       // same conversation: not a switch, but its reply carried traj-A2
        rig.Fake.MakeMostRecent("conv-B");
        var toB = await rig.AskAsync();
        // The id the driver last RECEIVED is traj-A2; a stored id refreshed only on a switch would still say traj-A.
        Assert.Equal("traj-A2", PreviousOf(toB.Json));
        Assert.Contains("[conv] CONVERSATION CHANGED: traj-A2 -> traj-B;", Assert.Single(ConvBlocks(toB.Blocks)));
    }

    [Fact]
    public async Task Stalled_ask_does_not_advance_the_switch_state()
    {
        await using var rig = await SwitchRig.StartWithStallWindowAsync(TimeSpan.FromMilliseconds(150),
            ("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();                       // delivered in A
        rig.Fake.MakeMostRecent("conv-B");
        rig.Fake.HangWaits = true;
        var stalled = await rig.AskAsync();         // goes to B, its wait stalls: nothing is delivered
        Assert.DoesNotContain("\"Answer\"", stalled.Json);
        rig.Fake.HangWaits = false;
        var third = await rig.AskAsync();           // B again, now delivered
        Assert.Equal("traj-A", PreviousOf(third.Json));   // the last DELIVERED reply was A's, not the stalled B ask
    }

    [Fact]
    public async Task Cancelled_ask_does_not_advance_the_switch_state()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();                       // delivered in A
        rig.Fake.MakeMostRecent("conv-B");
        rig.Fake.HangWaits = true;
        var inWait = rig.Fake.ArmWaitSignal();
        using var cts = new CancellationTokenSource();
        var pending = rig.AskAsync(cancellationToken: cts.Token);
        await inWait.WaitAsync(TimeSpan.FromSeconds(30));   // the ask is PROVABLY inside its wait, after the send
        cts.Cancel();
        try { await pending; }
        catch (Exception ex) when (ex is OperationCanceledException or RpcException { StatusCode: StatusCode.Cancelled })
        {
            // A caller cancel surfaces as the cancellation itself or as the gRPC Cancelled status (measured: the latter).
        }
        rig.Fake.HangWaits = false;
        var third = await rig.AskAsync();           // B again, now delivered
        Assert.Equal("traj-A", PreviousOf(third.Json));
    }

    [Fact]
    public async Task Conv_block_coexists_with_a_13b_truncated_reply_notice()
    {
        await using var rig = await SwitchRig.StartAsync(("conv-A", "traj-A"), ("conv-B", "traj-B"));
        await rig.AskAsync();
        rig.Fake.MakeMostRecent("conv-B");
        // A discipline ask whose reply ("ok") lacks the terminal token: the [13b] chain emits TRUNCATED REPLY.
        var second = await rig.AskAsync("q", discipline: "agy-first", artifactPath: rig.ArtifactPath);
        Assert.Contains(second.Blocks, b => b.StartsWith("[13b] TRUNCATED REPLY", StringComparison.Ordinal));
        Assert.Contains("[conv] CONVERSATION CHANGED: traj-A -> traj-B;", Assert.Single(ConvBlocks(second.Blocks)));
    }

    [Fact]
    public async Task Conv_block_coexists_with_a_peer_still_busy_notice()
    {
        await using var rig = await SwitchRig.StartWithStallWindowAsync(TimeSpan.FromMilliseconds(150),
            ("conv-A", "traj-A"), ("conv-B", "traj-B"));
        rig.Fake.AssistantDone = true;
        rig.Fake.HangWaits = true;                  // the turn ends but the conversation never goes idle
        await rig.AskAsync();                       // delivered in A, flagged busy
        rig.Fake.MakeMostRecent("conv-B");
        var second = await rig.AskAsync();
        Assert.Contains(second.Blocks, b => b.StartsWith("[PEER STILL BUSY]", StringComparison.Ordinal));
        Assert.Contains("[conv] CONVERSATION CHANGED: traj-A -> traj-B;", Assert.Single(ConvBlocks(second.Blocks)));
    }
}
