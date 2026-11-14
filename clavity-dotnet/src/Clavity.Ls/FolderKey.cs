// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/
// > **This file holds the PolyForm Noncommercial 1.0.0 text followed by the additional terms:
// > an evaluation grant and an anti-circumvention everything in this repo is source-available software. It is not open source.
//
// # PolyForm Noncommercial License 1.0.0
//
// <https://polyformproject.org/licenses/noncommercial/1.0.0>
//
// ## Acceptance
//
// In order to get any license under these terms, you must agree
// to them as both strict obligations and conditions to all
// your licenses.
//
// ## Copyright License
//
// The licensor grants you a copyright license for the
// software to do everything you might do with the software
// that would otherwise infringe the licensor's copyright
// in it for any permitted purpose.  However, you may
// only distribute the software according to [Distribution
// License](#distribution-license) and make changes or new works
// based on the software according to [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Distribution License
//
// The licensor grants you an additional copyright license
// to distribute copies of the software.  Your license
// to distribute covers distributing the software with
// changes and new works permitted by [Changes and New Works
// License](#changes-and-new-works-license).
//
// ## Notices
//
// You must ensure that anyone who gets a copy of any part of
// the software from you also gets a copy of these terms or the
// URL for them above, as well as copies of any plain-text lines
// beginning with `Required Notice:` that the licensor provided
// with the software.  For example:
//
// > Required Notice: Copyright Yoyodyne, Inc. (http://example.com)
//
// ## Changes and New Works License
//
// The licensor grants you an additional copyright license to
// make changes and new works based on the software for any
// permitted purpose.
//
// ## Patent License
//
// The licensor grants you a patent license for the software that
// covers patent claims the licensor can license, or becomes able
// to license, that you would infringe by using the software.
//
// ## Noncommercial Purposes
//
// Any noncommercial purpose is a permitted purpose.
//
// ## Personal Uses
//
// Personal use for research, experiment, and testing for
// the benefit of public knowledge, personal study, private
// entertainment, hobby projects, amateur pursuits, or religious
// observance, without any anticipated commercial application,
// is use for a permitted purpose.
//
// ## Noncommercial Organizations
//
// Use by any charitable organization, educational institution,
// public research organization, public safety or health
// organization, environmental protection organization,
// or government institution is use for a permitted purpose
// regardless of the source of funding or obligations resulting
// from the funding.
//
// ## Fair Use
//
// You may have "fair use" rights for the software under the
// law. These terms do not limit them.
//
// ## No Other Rights
//
// These terms do not allow you to sublicense or transfer any of
// your licenses to anyone else, or prevent the licensor from
// granting licenses to anyone else.  These terms do not imply
// any other licenses.
//
// ## Patent Defense
//
// If you make any written claim that the software infringes or
// contributes to infringement of any patent, your patent license
// for the software granted under these terms ends immediately. If
// your company makes such a claim, your patent license ends
// immediately for work on behalf of your company.
//
// ## Violations
//
// The first time you are notified in writing that you have
// violated any of these terms, or done anything with the software
// not covered by your licenses, your licenses can nonetheless
// continue if you come into full compliance with these terms,
// and take practical steps to correct past violations, within
// 32 days of receiving notice.  Otherwise, all your licenses
// end immediately.
//
// ## No Liability
//
// ***As far as the law allows, the software comes as is, without
// any warranty or condition, and the licensor will not be liable
// to you for any damages arising out of these terms or the use
// or nature of the software, under any kind of legal claim.***
//
// ## Definitions
//
// The **licensor** is the individual or entity offering these
// terms, and the **software** is the software the licensor makes
// available under these terms.
//
// **You** refers to the individual or entity agreeing to these
// terms.
//
// **Your company** is any legal entity, sole proprietorship,
// or other kind of organization that you work for, plus all
// organizations that have control over, are under the control of,
// or are under common control with that organization.  **Control**
// means ownership of substantially all the assets of an entity,
// or the power to direct its management and policies by vote,
// contract, or otherwise.  Control can be direct or indirect.
//
// **Your licenses** are all the licenses granted to you for the
// software under these terms.
//
// **Use** means anything you do with the software requiring one
// of your licenses.
//
// ---
//
// # ADDITIONAL TERMS (not part of PolyForm Noncommercial 1.0.0)
//
// ## Commercial Evaluation Grant
//
// Any organisation, including one that is not a Noncommercial Organization, may use the software
// for internal testing and evaluation for 30 days from first use, royalty-free. Use beyond that
// period, and any production or other commercial use, requires a paid licence key from the
// licensor.
//
// ## Anti-Circumvention
//
// You may not move, change, disable, or circumvent the licence key functionality in the software,
// and you may not remove or obscure any functionality protected by the licence key or any licence
// notices.



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
        if (OperatingSystem.IsWindows())
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

    /// <summary>The kernel's final path of the folder: a <c>subst</c> drive and every reparse point (and an 8.3 short name, which <c>Path.GetFullPath</c> already expands) come back as the
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
