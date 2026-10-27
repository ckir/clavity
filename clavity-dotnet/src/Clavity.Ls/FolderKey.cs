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
        // Like realpath(3): the path already resolved is always link-free, the segments still to apply wait in a list, and
        // a link's target is spliced IN FRONT of them. A ".." therefore applies to the real directory its left side
        // resolved to, not to the text: l1 -> "l2/../repo" with l2 -> deep/sub lands in deep/repo, as the kernel does
        // (collapsing "l2/.." as text gave <root>/repo, a different folder). The typed folder is first made absolute
        // lexically, on purpose: that is the path Claude is launched in.
        var full = Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder));
        var root = Path.GetPathRoot(full) ?? "";
        var pending = new LinkedList<string>(Segments(full[root.Length..]));
        var resolved = root;
        var hops = 0;
        while (pending.First is { } head)
        {
            var segment = head.Value;
            pending.RemoveFirst();
            if (segment == ".")
                continue;
            if (segment == "..")
            {
                resolved = resolved == root ? root : Path.GetDirectoryName(resolved) ?? root;
                continue;
            }
            var next = Path.Combine(resolved, segment);
            var target = LinkTargetOf(next);
            if (target is not null && ++hops > MaxLinkHops)
                target = null;   // past the cap a link is treated as a plain directory, so a loop ends
            if (target is null)
            {
                resolved = next;
                continue;
            }
            if (Path.IsPathRooted(target))
            {
                var targetRoot = Path.GetPathRoot(target) ?? "";
                resolved = targetRoot;
                target = target[targetRoot.Length..];
            }
            foreach (var part in Segments(target).Reverse())
                pending.AddFirst(part);
        }
        var path = Path.TrimEndingDirectorySeparator(resolved);
        return ignoreCase ? path.ToUpperInvariant() : path;
    }

    /// <summary>The lock file for <paramref name="folder"/>: <c>~/.clavity/agy-folder.&lt;16 hex&gt;.lock</c>, from the first 8
    /// bytes of the SHA-256 of the canonical path (UTF-8). It lives under the user profile, never inside the project.</summary>
    public static string LockPath(string userProfileDir, string folder, bool ignoreCase)
    {
        var hash = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(Canonical(folder, ignoreCase))))[..16];
        return Path.Combine(userProfileDir, ".clavity", $"agy-folder.{hash}.lock");
    }

    private static string[] Segments(string path) =>
        path.Split(new[] { Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar }, StringSplitOptions.RemoveEmptyEntries);

    /// <summary>The target of <paramref name="path"/> when it is a link (one hop, as written), else null. An unreadable
    /// entry counts as a plain directory rather than failing the launch.</summary>
    private static string? LinkTargetOf(string path)
    {
        try
        {
            return new DirectoryInfo(path).LinkTarget;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }
}
