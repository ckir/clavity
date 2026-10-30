// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

// clavity-dotnet/src/Clavity.Ls/EscalationIndex.cs
namespace Clavity.Ls;

/// <summary>
/// CF1 Option C: builds the consumer-facing escalation index appended to the injected golden-header at inject
/// time. It points the consumer at the shipped-but-NOT-injected canonical manuals via their literal ABSOLUTE
/// paths (Read/view_file cannot expand env-vars or relative paths), so the consumer can Read a deeper manual on
/// demand. No token lives in the shared seed — the dotnet injector generates this from its own install dir; the
/// classic injector simply omits it (graceful degradation).
/// </summary>
public static class EscalationIndex
{
    public const string PluginRootVar = "CLAUDE_PLUGIN_ROOT";

    // The non-injected manuals, in the order they are listed. Filename → one-line "what it covers".
    private static readonly (string File, string Covers)[] Manuals =
    {
        ("agy-assumptions.md",  "load-bearing agy assumptions (footer markers, shell, caching, bus, auth)"),
        ("agy-capabilities.md", "agy capabilities + how to verify/re-verify each"),
    };

    /// <summary>Resolve the manuals directory from <paramref name="pluginRoot"/> (<c>${CLAUDE_PLUGIN_ROOT}/knowledge</c>
    /// under <c>claude plugin</c> installs, where the binary lives in <c>${CLAUDE_PLUGIN_DATA}/bin</c>) with fallback
    /// to <c>&lt;installRoot&gt;/plugins/clavity/knowledge</c>.</summary>
    public static string ResolveManualsDir(string? pluginRoot, string installRoot)
    {
        if (!string.IsNullOrWhiteSpace(pluginRoot))
        {
            var candidate = Path.Combine(pluginRoot.Trim(), "knowledge");
            if (Directory.Exists(candidate)) return candidate;
        }
        var trimmedInstall = installRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        return Path.Combine(trimmedInstall, "plugins", Install.PluginInstaller.PluginName, "knowledge");
    }

    /// <summary>The index block for <paramref name="manualsDir"/>, or null if the dir is null/missing or holds
    /// none of the known manuals.</summary>
    public static string? Build(string? manualsDir)
    {
        if (string.IsNullOrWhiteSpace(manualsDir) || !Directory.Exists(manualsDir)) return null;

        var lines = new List<string>();
        foreach (var (file, covers) in Manuals)
        {
            var abs = Path.Combine(manualsDir, file);
            if (File.Exists(abs)) lines.Add($"- `{abs}` — {covers}");
        }
        if (lines.Count == 0) return null;

        return "## agy knowledge — escalation index\n"
             + "Deeper detail lives in these shipped-but-not-injected manuals; `Read` one on demand:\n"
             + string.Join("\n", lines);
    }
}
