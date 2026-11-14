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
}
