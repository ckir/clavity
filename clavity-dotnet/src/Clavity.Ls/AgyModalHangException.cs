namespace Clavity.Ls;

/// <summary>A bounded LS wait timed out and the <see cref="IModalGuard"/> was invoked. Subclasses
/// <see cref="TimeoutException"/> (it IS a timeout) but carries the guard's <see cref="Report"/> so callers can
/// surface a structured "possible modal" signal instead of a bare timeout.</summary>
public sealed class AgyModalHangException : TimeoutException
{
    public ModalGuardReport Report { get; }

    /// <summary>Where agy was when the wait expired (slow tool vs hang) — null when not computed.</summary>
    public TimeoutDiagnostic? Diagnostic { get; }

    public AgyModalHangException(ModalGuardReport report, TimeoutDiagnostic? diagnostic = null) : base(report.Hint)
        => (Report, Diagnostic) = (report, diagnostic);
}
