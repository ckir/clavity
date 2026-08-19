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
public class McpToolsIntegrationTests
{
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
        // The parameter is `discipline`, NOT `expectTerminal`: the owner ruled that the driver owns the
        // token literals and the caller names only its discipline (DisciplineContract). The plan's own
        // draft of this row still named expectTerminal and would have pinned a parameter that no longer
        // exists.
        var services = new ServiceCollection();
        services.AddSingleton(new AgyView(new AgyViewOptions { CliLogPath = Path.Combine(Path.GetTempPath(), "schema-pin-13b-unused.log") }));
        services.AddMcpServer().WithTools<McpTools>();
        using var sp = services.BuildServiceProvider();

        var tool = sp.GetServices<McpServerTool>().Single(t => t.ProtocolTool.Name == "agy_ask");
        using var schema = JsonDocument.Parse(tool.ProtocolTool.InputSchema.GetRawText());
        var root = schema.RootElement;

        var props = root.GetProperty("properties");
        Assert.True(props.TryGetProperty("discipline", out _));
        Assert.True(props.TryGetProperty("expectEcho", out _));

        var required = root.GetProperty("required").EnumerateArray().Select(e => e.GetString()).ToArray();
        Assert.DoesNotContain("discipline", required);
        Assert.DoesNotContain("expectEcho", required);
    }
}
