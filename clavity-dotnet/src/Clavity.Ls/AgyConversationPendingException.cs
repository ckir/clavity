namespace Clavity.Ls;

/// <summary>
/// Thrown when agy is reachable but has NO conversation yet (E3) after the boot-race bound. This is a
/// SUSPENSION, not a retryable error: the caller must WAIT for the human to start/continue the agy session
/// and must NOT auto-retry in a loop (spec §6, ModalGuard-style).
/// </summary>
public sealed class AgyConversationPendingException : Exception
{
    public AgyConversationPendingException(string message) : base(message) { }
}
