// src/Clavity.Ls/AgyEndpoint.cs
using System.Text.Json;

namespace Clavity.Ls;

/// <summary>agy's self-published pairing endpoint (written by the pairing INSTALL.md into
/// ~/.clavity/agy-endpoint.json): the per-session CSRF token and the LS port. agy 1.2.2+ mints both on
/// each LS start, so this file is the ONLY external source of the live token.</summary>
public sealed record AgyEndpoint(string Csrf, int Port)
{
    /// <summary>Read + parse the endpoint file. Returns null on any failure (absent, unreadable, malformed,
    /// missing csrf, or an addr without a parseable port) — the caller falls back to cli.log discovery.</summary>
    public static AgyEndpoint? TryRead(string path)
    {
        try
        {
            if (!File.Exists(path)) return null;
            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            var root = doc.RootElement;
            if (!root.TryGetProperty("csrf", out var csrfEl) || csrfEl.ValueKind != JsonValueKind.String) return null;
            if (!root.TryGetProperty("addr", out var addrEl) || addrEl.ValueKind != JsonValueKind.String) return null;
            var csrf = csrfEl.GetString();
            var addr = addrEl.GetString();
            if (string.IsNullOrEmpty(csrf) || string.IsNullOrEmpty(addr)) return null;
            var colon = addr.LastIndexOf(':');
            if (colon < 0 || !int.TryParse(addr.AsSpan(colon + 1), out var port) || port <= 0) return null;
            return new AgyEndpoint(csrf, port);
        }
        catch (Exception ex) when (ex is IOException or JsonException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
