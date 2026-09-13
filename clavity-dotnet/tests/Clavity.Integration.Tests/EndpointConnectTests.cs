using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;

namespace Clavity.Integration.Tests;

// T4 addendum: AgyViewIntegrationTests exercises cli.log discovery (no token), and CsrfHeaderTests
// proves LsClient's interceptor wiring in isolation — but nothing previously drove AgyView all the way
// through ConnectPreferringEndpoint's endpoint-file branch. This proves that happy path end-to-end: the
// endpoint file is read, its port is confirmed listening, the connection is made via ConnectToEndpoint,
// and the token rides on the wire.
public class EndpointConnectTests
{
    private sealed class TokenAndConvLs : LanguageServerService.LanguageServerServiceBase
    {
        public string? SeenToken;

        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            SeenToken ??= context.RequestHeaders.GetValue("x-codeium-csrf-token");
            var resp = new GetAllCascadeTrajectoriesResponse();
            resp.TrajectorySummaries["conv-1"] = new CascadeTrajectorySummary
            {
                LastModifiedTime = Google.Protobuf.WellKnownTypes.Timestamp.FromDateTimeOffset(DateTimeOffset.UtcNow),
            };
            return Task.FromResult(resp);
        }

        public override Task<GetCascadeTrajectoryResponse> GetCascadeTrajectory(
            GetCascadeTrajectoryRequest request, ServerCallContext context)
            => Task.FromResult(new GetCascadeTrajectoryResponse
            {
                NumTotalSteps = 2,
                Trajectory = new CascadeTrajectory
                {
                    CascadeId = "conv-1",
                    Steps =
                    {
                        new CascadeStep { Kind = 14, UserInput = new CascadeUserInput { Text = "first" } },
                        new CascadeStep { Kind = 15 },
                    },
                },
            });
    }

    [Fact]
    public async Task AgyView_connects_via_the_endpoint_file_and_sends_the_token()
    {
        var fake = new TokenAndConvLs();
        await using var app = await FakeLsHost.StartAsync(fake);
        var port = FakeLsHost.PortOf(app);

        var epFile = Path.Combine(Path.GetTempPath(), $"agy-endpoint-{Guid.NewGuid():N}.json");
        await File.WriteAllTextAsync(epFile, $$"""{"csrf":"tok-xyz","addr":"localhost:{{port}}","published":"x"}""");
        try
        {
            // CliLogPath deliberately points at a nonexistent file: if ConnectPreferringEndpoint did NOT take
            // the endpoint-file branch, the cli.log fallback would throw (no such file) and this test would
            // fail — so success here proves the endpoint branch is what actually ran.
            var view = new AgyView(new AgyViewOptions { CliLogPath = @"C:\nonexistent\cli.log", EndpointPath = epFile });
            var bounded = await view.LookAsync();

            Assert.Equal("tok-xyz", fake.SeenToken);
            Assert.Equal("conv-1", bounded.CascadeId);
        }
        finally
        {
            File.Delete(epFile);
        }
    }
}
