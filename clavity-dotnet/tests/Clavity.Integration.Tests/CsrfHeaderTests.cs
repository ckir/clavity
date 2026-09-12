using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;

namespace Clavity.Integration.Tests;

// Drives LsClient's CsrfInterceptor wiring end-to-end against an in-proc fake LS: a client built with a
// token must send it as x-codeium-csrf-token on every unary call; a client built without one must send
// no such header at all (never an empty one).
public class CsrfHeaderTests
{
    private sealed class HeaderCapturingLs : LanguageServerService.LanguageServerServiceBase
    {
        public string? SeenToken;
        public override Task<GetAllCascadeTrajectoriesResponse> GetAllCascadeTrajectories(
            GetAllCascadeTrajectoriesRequest request, ServerCallContext context)
        {
            SeenToken = context.RequestHeaders.GetValue("x-codeium-csrf-token");
            return Task.FromResult(new GetAllCascadeTrajectoriesResponse());
        }
    }

    [Fact]
    public async Task Client_with_token_sends_x_codeium_csrf_token_header()
    {
        var fake = new HeaderCapturingLs();
        await using var app = await FakeLsHost.StartAsync(fake);
        using var client = new LsClient(LsChannel.ForHttpPort(FakeLsHost.PortOf(app)), csrfToken: "tok-abc");
        await client.GetAllCascadeTrajectoriesAsync();
        Assert.Equal("tok-abc", fake.SeenToken);
    }

    [Fact]
    public async Task Client_without_token_sends_no_header()
    {
        var fake = new HeaderCapturingLs();
        await using var app = await FakeLsHost.StartAsync(fake);
        using var client = new LsClient(LsChannel.ForHttpPort(FakeLsHost.PortOf(app)));
        await client.GetAllCascadeTrajectoriesAsync();
        Assert.Null(fake.SeenToken);
    }
}
