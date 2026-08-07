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
    /// the operator to inspect a healthy process while the real cause was the response SIZE or a closed
    /// conversation. Each cause names its own remedy.</summary>
    public enum Fault { TransportDown, PayloadTooLarge }

    /// <summary>Classify a diagnosed fault by its gRPC status code.</summary>
    public static Fault Classify(ChannelDiagnostic d) =>
        d.StatusCode == nameof(Grpc.Core.StatusCode.ResourceExhausted)
            ? Fault.PayloadTooLarge
            : Fault.TransportDown;

    /// <summary>The machine-readable status for a fault. MUST track <see cref="Hint"/>: a consumer reading the
    /// status field and a human reading the hint have to reach the same conclusion.</summary>
    public static string StatusFor(ChannelDiagnostic d) => Classify(d) switch
    {
        Fault.PayloadTooLarge => "payload_too_large",
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
            Fault.PayloadTooLarge =>
                prefix + "The peer is NOT down and restarting will not clear it. If the detail above mentions a " +
                "message SIZE, the response was too large for the channel's receive limit — start a fresh " +
                "cascade, or raise MaxReceiveMessageSize in LsChannel.cs (trajectory size, not step count, is " +
                "what crosses it). If it does not, this is upstream quota or rate-limit exhaustion — wait and " +
                "retry, or check quota; raising the receive limit will not help.",
            _ =>
                prefix + "agy's language server appears to have shut down or restarted (it does this " +
                "intermittently). Restart the Claude Code session (or the clavity-ls MCP server) to re-establish " +
                "the channel. agy's own logs are at ~/.gemini/antigravity-cli/ (cli.log + " +
                "logs/clavity-<sessionId>.log) if you need to confirm the shutdown.",
        };
    }
}
