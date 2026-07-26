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

    public static string Hint(ChannelDiagnostic d) =>
        $"clavity-ls -> agy channel is down ([{d.StatusCode}] {d.Detail}). agy's language server appears to have " +
        "shut down or restarted (it does this intermittently). Restart the Claude Code session (or the clavity-ls " +
        "MCP server) to re-establish the channel. agy's own logs are at ~/.gemini/antigravity-cli/ (cli.log + " +
        "logs/clavity-<sessionId>.log) if you need to confirm the shutdown.";
}
