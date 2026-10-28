// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace Clavity.Ls;

/// <summary>The key of the one-Claude-per-folder lock (ROADMAP section 101): every path that reaches the same folder must give the
/// same key, or a second Claude gets through by a different spelling. The key is the folder's full path with every symbolic
/// link resolved, one hop at a time, for the last component AND every parent. MEASURED 2026-10-27 on Linux:
/// <c>DirectoryInfo.ResolveLinkTarget(true)</c> follows a link at the LAST component only and returns null for
/// <c>/srv/linkdir/repo</c> when <c>linkdir</c> is the link, so it cannot be used for this. Windows junctions are read through
/// the same <c>LinkTarget</c> (measured 2026-10-28: junctions and symlinks resolve; a <c>subst</c> drive and a UNC path do not, ROADMAP
/// section 103). On Windows the walk is therefore followed by the kernel's own answer for the folder (<c>GetFinalPathNameByHandle</c>),
/// after a loopback admin share is mapped back to its drive; case is folded where the filesystem usually does.</summary>
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
        var full = Path.TrimEndingDirectorySeparator(Path.IsPathRooted(folder) ? folder : Path.GetFullPath(folder));
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
        if (false && OperatingSystem.IsWindows())
            path = Path.TrimEndingDirectorySeparator(WindowsFinalPath(path));
        return ignoreCase ? path.ToUpperInvariant() : path;
    }

    private static readonly Regex LoopbackAdminShare = new(
        @"^\\\\(?:localhost|127\.0\.0\.1)\\(?<drive>[A-Za-z])\$(?:\\(?<rest>.*))?$",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    /// <summary>A loopback administrative share (<c>\\localhost\C$\x</c>, <c>\\127.0.0.1\C$\x</c>) is the local drive's own folder, so it is
    /// written back as <c>C:\x</c>; any other path comes back unchanged. Lexical and platform independent. A real network share and
    /// this machine's own host name are NOT recognised (the accepted limit of ROADMAP section 103).</summary>
    public static string RewriteLoopbackAdminShare(string path)
    {
        var match = LoopbackAdminShare.Match(path);
        if (!match.Success)
            return path;
        var rest = match.Groups["rest"].Value;
        return $"{match.Groups["drive"].Value}:\\{rest}";
    }

    /// <summary>The path a <c>GetFinalPathNameByHandle</c> result names, without the <c>\\?\</c> namespace prefix: <c>\\?\C:\x</c> becomes
    /// <c>C:\x</c> and <c>\\?\UNC\srv\share</c> becomes <c>\\srv\share</c>. Any other form (a volume GUID path) is left as it is.</summary>
    public static string StripExtendedPrefix(string path)
    {
        if (path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase))
            return @"\\" + path[8..];
        if (path.StartsWith(@"\\?\", StringComparison.Ordinal) && path.Length >= 6 && char.IsAsciiLetter(path[4]) && path[5] == ':')
            return path[4..];
        return path;
    }

    private const uint FileReadAttributes = 0x0080;
    private const uint ShareAll = 0x7;            // read | write | delete: never the reason another process fails
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;   // required to open a DIRECTORY at all

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(string fileName, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", EntryPoint = "GetFinalPathNameByHandleW", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder buffer, uint size, uint flags);

    /// <summary>Runs a <c>GetFinalPathNameByHandle</c>-shaped <paramref name="query"/> into a buffer of 512 characters, grows it once when the
    /// answer says the path is longer, and returns the result without its <c>\\?\</c> prefix; <paramref name="fallback"/> comes back when the
    /// query reports failure (0) or still does not fit. Split out so the retry and the failure branch can be tested without a Windows handle.</summary>
    public static string FinalPathFromQuery(string fallback, Func<StringBuilder, uint, uint> query)
    {
        var buffer = new StringBuilder(512);
        var length = query(buffer, (uint)buffer.Capacity);
        if (length > buffer.Capacity)
        {
            buffer = new StringBuilder((int)length + 1);
            length = query(buffer, (uint)buffer.Capacity);
        }
        return length == 0 || length > buffer.Capacity ? fallback : StripExtendedPrefix(buffer.ToString());
    }

    /// <summary>The kernel's final path of the folder: a <c>subst</c> drive, an 8.3 short name and every reparse point come back as the
    /// real long path (ROADMAP section 103). FILE_READ_ATTRIBUTES, not GENERIC_READ, so a folder that may be entered but not listed
    /// still opens. ANY failure (folder gone, access denied, no such export) keeps the lexical path: the lock must never stop a launch.</summary>
    private static string WindowsFinalPath(string lexical)
    {
        var path = RewriteLoopbackAdminShare(lexical);
        try
        {
            using var handle = CreateFile(path, FileReadAttributes, ShareAll, IntPtr.Zero, OpenExisting, BackupSemantics, IntPtr.Zero);
            if (handle.IsInvalid)
                return path;
            return FinalPathFromQuery(path, (buffer, size) => GetFinalPathNameByHandle(handle, buffer, size, 0));
        }
        catch (Exception ex) when (ex is DllNotFoundException or EntryPointNotFoundException or ArgumentException or IOException)
        {
            return path;
        }
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
