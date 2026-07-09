using System.Buffers.Binary;
using System.Net;
using System.Net.Http.Headers;
using Clavity.Ls.Proto;
using Google.Protobuf;
using Grpc.Core;
using Grpc.Net.Client;

namespace Clavity.Integration.Tests;

// T4b — DETERMINISTIC framing-conformance (CI, no network/no live agy). Proves the REAL Grpc.Net.Client
// tolerates agy's SPECIFIC observed h2c framing (docs/agy-ls-assumptions.md §3) — not just generic Kestrel.
// A custom HttpMessageHandler fabricates each framing shape; the real generated client decodes it.
public class LsFramingConformanceTests
{
    // gRPC length-prefixed frame for a message: [0x00 compression flag][big-endian uint32 length][protobuf].
    private static byte[] GrpcFrame(IMessage message)
    {
        var payload = message.ToByteArray();
        var frame = new byte[5 + payload.Length];
        frame[0] = 0; // uncompressed
        BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(1, 4), (uint)payload.Length);
        payload.CopyTo(frame.AsSpan(5));
        return frame;
    }

    // Returns one canned HttpResponseMessage for any request — the fabricated framing under test.
    private sealed class CannedHandler(Func<HttpResponseMessage> make) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
            => Task.FromResult(make());
    }

    private static LanguageServerService.LanguageServerServiceClient ClientOver(Func<HttpResponseMessage> make)
    {
        var channel = GrpcChannel.ForAddress(
            "http://localhost",
            new GrpcChannelOptions { HttpHandler = new CannedHandler(make) });
        return new LanguageServerService.LanguageServerServiceClient(channel);
    }

    private static HttpResponseMessage GrpcResponse(byte[]? body)
    {
        var resp = new HttpResponseMessage(HttpStatusCode.OK) { Version = HttpVersion.Version20 };
        resp.Content = new ByteArrayContent(body ?? Array.Empty<byte>());
        resp.Content.Headers.ContentType = new MediaTypeHeaderValue("application/grpc");
        return resp;
    }

    // Case 1 — status-in-trailer SUCCESS: a message body + grpc-status=0 in TRAILING headers (agy's happy path).
    [Fact]
    public async Task Status_in_trailer_success_is_decoded()
    {
        var msg = new GetConversationMetadataResponse
        {
            Metadata = new Clavity.Ls.Proto.Metadata
            {
                RootConversationId = "conv-1",
                Workspaces = { new Workspace { BranchName = "main", Repository = new Repository { ComputedName = "ckir/clavity" } } },
            },
        };
        var client = ClientOver(() =>
        {
            var r = GrpcResponse(GrpcFrame(msg));
            r.TrailingHeaders.TryAddWithoutValidation("grpc-status", "0");
            return r;
        });

        var resp = await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "conv-1" });

        Assert.Equal("ckir/clavity", Assert.Single(resp.Metadata.Workspaces).Repository.ComputedName);
        Assert.Equal("conv-1", resp.Metadata.RootConversationId);
    }

    // Case 2 — status-in-trailer ERROR: no body + grpc-status=2 (Unknown) + grpc-message in TRAILING headers
    // (agy's error path). Client must surface a clean RpcException carrying the status and detail.
    [Fact]
    public async Task Status_in_trailer_error_with_message_surfaces_RpcException()
    {
        var client = ClientOver(() =>
        {
            var r = GrpcResponse(null);
            r.TrailingHeaders.TryAddWithoutValidation("grpc-status", "2");
            r.TrailingHeaders.TryAddWithoutValidation("grpc-message", "trajectory not found: x");
            return r;
        });

        var ex = await Assert.ThrowsAsync<RpcException>(async () =>
            await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "x" }));

        Assert.Equal(StatusCode.Unknown, ex.StatusCode);
        Assert.Contains("trajectory not found", ex.Status.Detail);
    }

    // Case 3 — trailers-only NEGATIVE: grpc-status in INITIAL headers, no body. agy doesn't do this, but the
    // client must still tolerate it (defensive — proves robustness to the other legal gRPC framing).
    [Fact]
    public async Task Trailers_only_status_is_tolerated()
    {
        var client = ClientOver(() =>
        {
            var r = GrpcResponse(null);
            r.Headers.TryAddWithoutValidation("grpc-status", "5"); // NotFound, in INITIAL headers
            r.Headers.TryAddWithoutValidation("grpc-message", "nope");
            return r;
        });

        var ex = await Assert.ThrowsAsync<RpcException>(async () =>
            await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "x" }));

        Assert.Equal(StatusCode.NotFound, ex.StatusCode);
    }

    // Case 4 — missing-status NEGATIVE: a body but NO grpc-status anywhere. The client must FAIL LOUDLY
    // (RpcException), not hang or silently return — guards against a malformed agy response.
    [Fact]
    public async Task Missing_status_fails_loudly_not_silently()
    {
        var client = ClientOver(() => GrpcResponse(GrpcFrame(new GetConversationMetadataResponse())));

        var ex = await Assert.ThrowsAsync<RpcException>(async () =>
            await client.GetConversationMetadataAsync(new GetConversationMetadataRequest { ConversationId = "x" }));

        Assert.NotEqual(StatusCode.OK, ex.StatusCode);
    }
}
