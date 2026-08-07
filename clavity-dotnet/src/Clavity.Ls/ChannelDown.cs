using Grpc.Core;

namespace Clavity.Ls;

/// <summary>The shared diagnosis for a dead clavity-ls -> agy channel: decides whether a caught exception is a
/// channel death (<see cref="IsChannelDown"/>), unwraps the underlying gRPC cause (<see cref="Diagnose"/> — never
/// emits "Unknown" while a real RpcException is available, F4), and produces the actionable hint. Shared by
/// McpTools' central RunAsync catch and AgyView.StatusAsync so both surfaces agree.</summary>
public static class ChannelDown
{
    public const string Status = "channel_down";

    /// <summary>True if the exception is a channel death we should diagnose. Excludes a caller-cancel
    /// (RpcException StatusCode.Cancelled — F6). The AgyModelUnavailableException-wrapper clause is added in the
    /// F3 fold.</summary>
    public static bool IsChannelDown(Exception ex) =>
        (ex is RpcException rpc && rpc.StatusCode != StatusCode.Cancelled)
        || ex is ObjectDisposedException or LsDiscoveryException
        || (ex is AgyModelUnavailableException && ex.InnerException is
            (RpcException { StatusCode: not StatusCode.Cancelled }) or ObjectDisposedException or LsDiscoveryException);

    /// <summary>Extract the diagnostic per the F4 unwrap rule: the RpcException's status; else an inner
    /// RpcException's status; else the concrete exception type name — never a bare "Unknown".</summary>
    public static ChannelDiagnostic Diagnose(Exception ex) => ex switch
    {
        RpcException rpc => new ChannelDiagnostic(rpc.StatusCode.ToString(), DetailOf(rpc)),
        { InnerException: RpcException rpc } => new ChannelDiagnostic(rpc.StatusCode.ToString(), DetailOf(rpc)),
        ObjectDisposedException => new ChannelDiagnostic("ObjectDisposed", ex.Message),
        LsDiscoveryException => new ChannelDiagnostic("LsDiscovery", ex.Message),
        _ => new ChannelDiagnostic(ex.GetType().Name, ex.Message),
    };

    // Real gRPC uses an EMPTY (not null) Status.Detail on many failures, so `?? Message` would not fire; fall back
    // to the exception Message whenever Detail is null OR empty, to keep the diagnostic from reading "[Unavailable] ".
    private static string DetailOf(RpcException rpc) =>
        string.IsNullOrEmpty(rpc.Status.Detail) ? rpc.Message : rpc.Status.Detail;

    /// <summary>Why the channel call failed. The bridge used to report every fault as a peer shutdown, which sent
    /// the operator to inspect a healthy process while the real cause was the response SIZE, a refused
    /// credential, or a bad request. Each cause names its own remedy.
    /// <para>The load-bearing distinction: a gRPC status code that is NOT a transport failure PROVES the channel
    /// reached the peer and the peer answered with a structured error frame — a dead transport cannot produce
    /// one. Reporting those as "the language server shut down" is factually false and sends the operator into a
    /// restart loop that can never clear the condition.</para></summary>
    public enum Fault { TransportDown, ResourceExhausted, AuthFailed, InvalidRequest }

    /// <summary>Classify a diagnosed fault by its gRPC status code. Anything not named here — including the
    /// non-gRPC "ObjectDisposed"/"LsDiscovery" diagnostics and a genuine <c>Unavailable</c> — is a transport
    /// death, which is the correct default: it is the only class a restart can fix.</summary>
    public static Fault Classify(ChannelDiagnostic d) => d.StatusCode switch
    {
        // Deliberately NOT split by detail text. Discriminating "too large" from "quota" would have to match
        // Grpc.Net.Client's own message string, which is not a contract and can change with the library
        // version or localization. The status therefore asserts only what gRPC asserted, and Hint explains
        // the two possible causes. (Owner ruling, 2026-08-07, converged with the review peer.)
        nameof(Grpc.Core.StatusCode.ResourceExhausted) => Fault.ResourceExhausted,

        nameof(Grpc.Core.StatusCode.Unauthenticated) or
        nameof(Grpc.Core.StatusCode.PermissionDenied) => Fault.AuthFailed,

        nameof(Grpc.Core.StatusCode.NotFound) or
        nameof(Grpc.Core.StatusCode.InvalidArgument) or
        nameof(Grpc.Core.StatusCode.FailedPrecondition) => Fault.InvalidRequest,

        _ => Fault.TransportDown,
    };

    /// <summary>The machine-readable status for a fault. MUST track <see cref="Hint"/>: a consumer reading the
    /// status field and a human reading the hint have to reach the same conclusion. Every arm added to
    /// <see cref="Classify"/> MUST be added here too — the fallback silently reports a fault as a dead channel.</summary>
    public static string StatusFor(ChannelDiagnostic d) => Classify(d) switch
    {
        Fault.ResourceExhausted => "resource_exhausted",
        Fault.AuthFailed => "auth_failed",
        Fault.InvalidRequest => "invalid_request",
        _ => Status,
    };

    public static string Hint(ChannelDiagnostic d)
    {
        var prefix = $"clavity-ls -> agy channel call failed ([{d.StatusCode}] {d.Detail}). ";
        return Classify(d) switch
        {
            // ResourceExhausted covers TWO causes and the code cannot tell them apart from the status alone:
            // the channel's own receive limit, and upstream quota / rate-limiting. Naming only the first
            // would send an operator to edit a message-size limit during a quota event — the same
            // "confidently name the wrong remedy" defect this classifier exists to remove. So the hint names
            // both and points at the detail (echoed in the prefix above) as the discriminator.
            Fault.ResourceExhausted =>
                prefix + "The peer is NOT down and restarting will not clear it. If the detail above mentions a " +
                "message SIZE, the response was too large for the channel's receive limit — start a fresh " +
                "cascade, or raise MaxReceiveMessageSize in LsChannel.cs (trajectory size, not step count, is " +
                "what crosses it). If it does not, this is upstream quota or rate-limit exhaustion — wait and " +
                "retry, or check quota; raising the receive limit will not help.",

            Fault.AuthFailed =>
                prefix + "The channel is UP and agy answered — it refused the credentials. Restarting the session " +
                "will NOT fix an auth refusal. Check the keyring entry and agy's authentication state, then retry.",

            Fault.InvalidRequest =>
                prefix + "The channel is UP and agy answered — it rejected the REQUEST, not the connection. " +
                "Restarting will not help. The usual cause is a stale or closed conversation id; re-resolve the " +
                "active cascade, or start a fresh one.",
            _ =>
                prefix + "agy's language server appears to have shut down or restarted (it does this " +
                "intermittently). Restart the Claude Code session (or the clavity-ls MCP server) to re-establish " +
                "the channel. agy's own logs are at ~/.gemini/antigravity-cli/ (cli.log + " +
                "logs/clavity-<sessionId>.log) if you need to confirm the shutdown.",
        };
    }
}
