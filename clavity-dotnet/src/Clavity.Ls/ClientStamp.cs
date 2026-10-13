using System.Reflection;

namespace Clavity.Ls;

/// <summary>The running client's build provenance, so a transport failure can say WHICH clavity-ls it came from. A stale installed
/// client used to be diagnosed as a peer fault (an hour lost on a healthy peer, 2026-08-09) because nothing in the error named the
/// build. The release workflow sets <c>-p:Version</c> to the plugin version and the .NET SDK appends the commit
/// (<c>0.11.0+1f601d11…</c>) to <see cref="AssemblyInformationalVersionAttribute"/>; the attribute is read, never a file path or a
/// build date, because a single-file publish has no assembly location to stat.</summary>
public static class ClientStamp
{
    public const string Unknown = "unknown (no build stamp)";

    /// <summary>"&lt;version&gt;+&lt;first 8 of the commit&gt;" for THIS assembly, or <see cref="Unknown"/>.</summary>
    public static string Value { get; } =
        Format(typeof(ClientStamp).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion);

    /// <summary>Shorten the SDK's full-commit build metadata to 8 characters; a version with no metadata is kept as is.</summary>
    public static string Format(string? informational)
    {
        if (string.IsNullOrWhiteSpace(informational)) return Unknown;
        var s = informational.Trim();
        var plus = s.IndexOf('+');
        if (plus < 0) return s;
        var version = s[..plus];
        var revision = s[(plus + 1)..];
        if (version.Length == 0) return Unknown;
        if (revision.Length == 0) return version;
        return $"{version}+{(revision.Length > 8 ? revision[..8] : revision)}";
    }
}
