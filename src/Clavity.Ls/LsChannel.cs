using Grpc.Net.Client;

namespace Clavity.Ls;

/// <summary>
/// Builds a <see cref="GrpcChannel"/> to agy's Language Server over <b>h2c</b> (gRPC on cleartext
/// HTTP/2). agy's "HTTP" port (the higher of the <see cref="LsEndpoint"/> pair) speaks gRPC without
/// TLS, so the channel must be told to allow unencrypted HTTP/2 and to use the <c>http://</c> scheme.
/// </summary>
/// <remarks>
/// The <c>Http2UnencryptedSupport</c> AppContext switch must be set before the underlying
/// <see cref="SocketsHttpHandler"/> issues its first request; doing it in the static constructor
/// guarantees that, since the switch is set before <see cref="ForHttpPort"/> creates any handler.
/// </remarks>
public static class LsChannel
{
    static LsChannel()
    {
        AppContext.SetSwitch("System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport", true);
    }

    /// <summary>Open an h2c gRPC channel to <c>127.0.0.1:&lt;httpPort&gt;</c> (the LS HTTP/h2c port).</summary>
    public static GrpcChannel ForHttpPort(int httpPort)
    {
        var handler = new SocketsHttpHandler
        {
            // The LS is a long-lived local server; keep the connection warm and allow concurrent calls.
            EnableMultipleHttp2Connections = true,
            PooledConnectionIdleTimeout = Timeout.InfiniteTimeSpan,
            KeepAlivePingDelay = TimeSpan.FromSeconds(30),
            KeepAlivePingTimeout = TimeSpan.FromSeconds(10),
        };

        return GrpcChannel.ForAddress(
            $"http://127.0.0.1:{httpPort}",
            new GrpcChannelOptions { HttpHandler = handler });
    }
}
