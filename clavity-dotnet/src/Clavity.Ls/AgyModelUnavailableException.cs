// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

namespace Clavity.Ls;

/// <summary>
/// Thrown when no valid send-model can be resolved: the conversation's last-executed model was deprecated out of
/// the live catalog, or a brand-new conversation has no model and agy reports no default. The message tells the
/// operator how to escape the deadlock (clavity reads the last EXECUTED model, so changing the agy dropdown
/// without sending re-reads the old model).
/// </summary>
public sealed class AgyModelUnavailableException : Exception
{
    public AgyModelUnavailableException(string message) : base(message) { }
    public AgyModelUnavailableException(string message, Exception? inner) : base(message, inner) { }
}
