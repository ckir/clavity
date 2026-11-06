// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

namespace Clavity.Ls;

/// <summary>A bounded LS wait timed out and the <see cref="IModalGuard"/> was invoked. Subclasses
/// <see cref="TimeoutException"/> (it IS a timeout) but carries the guard's <see cref="Report"/> so callers can
/// surface a structured "possible modal" signal instead of a bare timeout.</summary>
public sealed class AgyModalHangException : TimeoutException
{
    public ModalGuardReport Report { get; }

    /// <summary>Where agy was when the wait expired (slow tool vs hang) — null when not computed.</summary>
    public TimeoutDiagnostic? Diagnostic { get; }

    /// <summary>ROADMAP section 108: for a DISCIPLINE ask, the path the peer was asked to write its whole reply to. The
    /// peer may have finished after this report, so naming it lets the driver fetch a reply that would otherwise be
    /// orphaned. Null for an ordinary ask or when no workspace root was known. Set by the ask path, not the wait.</summary>
    public string? PeerFile { get; set; }

    public AgyModalHangException(ModalGuardReport report, TimeoutDiagnostic? diagnostic = null) : base(report.Hint)
        => (Report, Diagnostic) = (report, diagnostic);
}
