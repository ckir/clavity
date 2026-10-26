// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Security.Cryptography;
using System.Text;

namespace Clavity.Ls;

/// <summary>The key of the one-Claude-per-folder lock (ROADMAP section 101): every path that reaches the same folder must give the
/// same key, or a second Claude gets through by a different spelling. The key is the folder's full path with every symbolic
/// link resolved, one hop at a time, for the last component AND every parent. MEASURED 2026-10-27 on Linux:
/// <c>DirectoryInfo.ResolveLinkTarget(true)</c> follows a link at the LAST component only and returns null for
/// <c>/srv/linkdir/repo</c> when <c>linkdir</c> is the link, so it cannot be used for this. Windows junctions are read through
/// the same <c>LinkTarget</c> but were NOT measured (no Windows machine here); case is folded where the filesystem usually does.</summary>
public static class FolderKey
{
    /// <summary>The kernel's own limit on nested links (ELOOP is 40 on Linux); a loop ends here with the last path seen.</summary>
    private const int MaxLinkHops = 40;

    /// <summary>Windows and macOS filesystems are case-insensitive by default; Linux's are not. A case-SENSITIVE macOS volume
    /// would treat two folders that differ only in case as one - the accepted cost of not asking the volume.</summary>
    public static bool IgnoreCaseHere => OperatingSystem.IsWindows() || OperatingSystem.IsMacOS();

    public static string Canonical(string folder, bool ignoreCase)
    {
        var path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder));
        for (var hop = 0; hop < MaxLinkHops; hop++)
        {
            var resolved = ResolveFirstLink(path);
            if (resolved is null)
                break;
            path = Path.TrimEndingDirectorySeparator(Path.GetFullPath(resolved));
        }
        return ignoreCase ? path.ToUpperInvariant() : path;
    }

    /// <summary>The lock file for <paramref name="folder"/>: <c>~/.clavity/agy-folder.&lt;16 hex&gt;.lock</c>, from the first 8
    /// bytes of the SHA-256 of the canonical path (UTF-8). It lives under the user profile, never inside the project.</summary>
    public static string LockPath(string userProfileDir, string folder, bool ignoreCase)
    {
        var hash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Canonical(folder, ignoreCase))))[..16];
        return Path.Combine(userProfileDir, ".clavity", $"agy-folder.{hash}.lock");
    }

    /// <summary>The path with its FIRST link (walking from the root) replaced by that link's target, or null when no component
    /// is a link. A relative target is relative to the directory the link sits in.</summary>
    private static string? ResolveFirstLink(string full)
    {
        var root = Path.GetPathRoot(full) ?? "";
        var parts = full[root.Length..].Split(
            new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries);
        var current = root;
        for (var i = 0; i < parts.Length; i++)
        {
            current = Path.Combine(current, parts[i]);
            string? target;
            try
            {
                target = new DirectoryInfo(current).LinkTarget;
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                target = null;   // unreadable: treat it as a plain directory rather than fail the launch
            }
            if (target is null)
                continue;
            var resolved = Path.GetFullPath(target, Path.GetDirectoryName(current) ?? root);
            return i + 1 == parts.Length ? resolved : Path.Combine(resolved, Path.Combine(parts[(i + 1)..]));
        }
        return null;
    }
}
