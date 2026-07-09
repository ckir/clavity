using Clavity.Ls;
using Clavity.Ls.Proto;
using Grpc.Core;
using Xunit.Abstractions;

namespace Clavity.Live.Acceptance;

// Tier B — live acceptance (plan §4 / task T4a "A-lite"). Touches a REAL logged-in agy LS over h2c with
// the REAL LsChannel + generated client, and RECORDS agy's actual gRPC trailer shape — the oracle the
// deterministic T4b conformance test reproduces in CI. Gated: excluded from CI by the "LiveAgy" trait
// (`dotnet test --filter "Category!=LiveAgy"`) and Skip unless run deliberately with CLAVITY_LIVE_AGY=1.
public class LsFramingLiveTests
{
    private readonly ITestOutputHelper _out;
    public LsFramingLiveTests(ITestOutputHelper output) => _out = output;

    private static bool LiveAgyEnabled => Environment.GetEnvironmentVariable("CLAVITY_LIVE_AGY") == "1";

    private static string CliLogPath =>
        Environment.GetEnvironmentVariable("CLAVITY_LIVE_CLILOG")
        ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".gemini", "antigravity-cli", "cli.log");

    // Captures the live HttpResponseMessage so the test can inspect trailer placement AFTER the gRPC call
    // has drained the response stream — HttpResponseMessage.TrailingHeaders are only populated by then.
    private sealed class CapturingHandler : DelegatingHandler
    {
        public HttpResponseMessage? Last { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Last = await base.SendAsync(request, cancellationToken);
            return Last;
        }
    }

    private static string KeysOf(System.Net.Http.Headers.HttpHeaders headers) =>
        string.Join(", ", headers.Select(h => h.Key));

    // Happy path: a valid conversation id -> OK + a response body, so gRPC status MUST ride in the trailing
    // HEADERS frame (status-in-trailer). That Grpc.Net.Client (which strictly requires that placement)
    // returns OK is the BY-CONSTRUCTION proof that agy's framing is client-compatible.
    [Fact(Skip = "Live: set CLAVITY_LIVE_AGY=1 + CLAVITY_LIVE_CONV_ID, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Real_agy_LS_completes_GetConversationMetadata_with_status_in_trailer()
    {
        Assert.True(LiveAgyEnabled);
        var convId = Environment.GetEnvironmentVariable("CLAVITY_LIVE_CONV_ID");
        Assert.False(string.IsNullOrWhiteSpace(convId), "set CLAVITY_LIVE_CONV_ID to a live conversation uuid");

        var endpoint = LsDiscovery.DiscoverActive(LsDiscovery.ReadCliLogText(CliLogPath), new SystemListeningPorts());
        _out.WriteLine($"discovered LS http port: {endpoint.HttpPort} (pid {endpoint.Pid})");

        var capture = new CapturingHandler();
        using var channel = LsChannel.ForHttpPort(endpoint.HttpPort, capture);
        var client = new LanguageServerService.LanguageServerServiceClient(channel);

        var call = client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = convId });
        var resp = await call;

        Assert.NotNull(resp.Metadata);
        Assert.NotEmpty(resp.Metadata.Workspaces);
        Assert.Equal(StatusCode.OK, call.GetStatus().StatusCode);

        var http = capture.Last!;
        bool grpcStatusInInitialHeaders = http.Headers.TryGetValues("grpc-status", out _);   // true => trailers-only
        bool grpcStatusInTrailers = http.TrailingHeaders.TryGetValues("grpc-status", out _); // true => status-in-trailer

        _out.WriteLine($"http version: {http.Version}");
        _out.WriteLine($"initial header keys: {KeysOf(http.Headers)}");
        _out.WriteLine($"trailing header keys: {KeysOf(http.TrailingHeaders)}");
        _out.WriteLine($"grpc-status in initial headers (trailers-only): {grpcStatusInInitialHeaders}");
        _out.WriteLine($"grpc-status in trailing headers (status-in-trailer): {grpcStatusInTrailers}");

        // The recorded fact: agy returns a body for a valid id, so status rides in the trailing HEADERS.
        Assert.True(grpcStatusInTrailers, "expected grpc-status in trailing headers (status-in-trailer)");
        Assert.False(grpcStatusInInitialHeaders, "did not expect trailers-only framing on the happy path");
    }

    // Negative path (observed live: agy returns gRPC `code = Unknown desc = trajectory not found` for an
    // unknown id). The client must surface that as an RpcException cleanly — no hang, no wrong-reason fault.
    // The error has no body, so this is the case where agy may use trailers-only framing; we RECORD which.
    [Fact(Skip = "Live: set CLAVITY_LIVE_AGY=1, run --filter Category=LiveAgy")]
    [Trait("Category", "LiveAgy")]
    public async Task Real_agy_LS_surfaces_grpc_error_for_unknown_conversation_id()
    {
        Assert.True(LiveAgyEnabled);

        var endpoint = LsDiscovery.DiscoverActive(LsDiscovery.ReadCliLogText(CliLogPath), new SystemListeningPorts());

        var capture = new CapturingHandler();
        using var channel = LsChannel.ForHttpPort(endpoint.HttpPort, capture);
        var client = new LanguageServerService.LanguageServerServiceClient(channel);

        var call = client.GetConversationMetadataAsync(
            new GetConversationMetadataRequest { ConversationId = "00000000-0000-0000-0000-000000000000" });

        var ex = await Assert.ThrowsAsync<RpcException>(async () => await call);
        Assert.NotEqual(StatusCode.OK, ex.StatusCode);
        _out.WriteLine($"error status: {ex.StatusCode}");
        _out.WriteLine($"error detail: {ex.Status.Detail}");

        var http = capture.Last;
        if (http is not null)
        {
            bool grpcStatusInInitialHeaders = http.Headers.TryGetValues("grpc-status", out _);
            _out.WriteLine($"initial header keys: {KeysOf(http.Headers)}");
            _out.WriteLine($"trailing header keys: {KeysOf(http.TrailingHeaders)}");
            _out.WriteLine($"error framing trailers-only: {grpcStatusInInitialHeaders}");
        }
    }
}
