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
/// guarantees that, since the switch is set before <see cref="ForHttpPort(int)"/> creates any handler.
/// </remarks>
public static class LsChannel
{
    static LsChannel()
    {
        AppContext.SetSwitch("System.Net.Http.SocketsHttpHandler.Http2UnencryptedSupport", true);
    }

    /// <summary>Open an h2c gRPC channel to <c>127.0.0.1:&lt;httpPort&gt;</c> (the LS HTTP/h2c port).</summary>
    public static GrpcChannel ForHttpPort(int httpPort) => ForHttpPort(httpPort, null);

    /// <summary>
    /// Overload that lets a caller wrap the h2c handler with a <see cref="DelegatingHandler"/> (e.g. a
    /// trailer-observing handler in live acceptance tests). The h2c configuration is identical to the
    /// one-arg overload, so the channel's wire setup stays a single source of truth.
    /// </summary>
    public static GrpcChannel ForHttpPort(int httpPort, DelegatingHandler? observer)
    {
        var handler = new SocketsHttpHandler
        {
            // The LS is a long-lived local server; keep the connection warm and allow concurrent calls.
            EnableMultipleHttp2Connections = true,
            PooledConnectionIdleTimeout = Timeout.InfiniteTimeSpan,
            KeepAlivePingDelay = TimeSpan.FromSeconds(30),
            KeepAlivePingTimeout = TimeSpan.FromSeconds(10),
        };

        HttpMessageHandler effective = handler;
        if (observer is not null)
        {
            observer.InnerHandler = handler;
            effective = observer;
        }

        return GrpcChannel.ForAddress(
            $"http://127.0.0.1:{httpPort}",
            new GrpcChannelOptions
            {
                HttpHandler = effective,
                // A cascade's trajectory grows without bound, and gRPC's 4 MB DEFAULT was being inherited by
                // accident — every readback past it died ResourceExhausted while the peer was healthy. 64 MB is a
                // deliberate ceiling well above the largest realistic trajectory; null (unbounded) was rejected so
                // a runaway response still fails loudly instead of exhausting memory.
                MaxReceiveMessageSize = 64 * 1024 * 1024,
            });
    }
}
