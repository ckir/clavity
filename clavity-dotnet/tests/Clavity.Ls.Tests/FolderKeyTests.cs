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



using System.Text;
using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>The key of the one-Claude-per-folder lock (ROADMAP section 101): every path that reaches a folder must give the SAME
/// key. Measured 2026-10-27 on Linux: `DirectoryInfo.ResolveLinkTarget(true)` resolves a link at the LAST component only, and
/// returns null for a path whose PARENT is a link, which is why the key walks the components itself.</summary>
public sealed class FolderKeyTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "clavity-fk-" + Guid.NewGuid().ToString("N"));

    public FolderKeyTests() => Directory.CreateDirectory(_root);

    public void Dispose() => Directory.Delete(_root, recursive: true);

    private string Make(params string[] parts)
    {
        var path = Path.Combine(new[] { _root }.Concat(parts).ToArray());
        Directory.CreateDirectory(path);
        return path;
    }

    private string Link(string name, string target)
    {
        var path = Path.Combine(_root, name);
        Directory.CreateSymbolicLink(path, target);
        return path;
    }

    [Fact]
    public void Dot_segments_and_a_trailing_separator_do_not_change_the_key()
    {
        var repo = Make("data", "repo");
        Assert.Equal(
            FolderKey.Canonical(repo, ignoreCase: false),
            FolderKey.Canonical(Path.Combine(_root, "data", "x", "..", "repo") + Path.DirectorySeparatorChar, ignoreCase: false));
    }

    [Fact]
    public void A_link_at_the_last_component_gives_its_targets_key()
    {
        if (OperatingSystem.IsWindows()) return;   // creating links needs a privilege there; junctions are unmeasured
        var repo = Make("data", "repo");
        var link = Link("repolink", repo);
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(link, false));
    }

    [Fact]
    public void A_link_in_a_PARENT_directory_gives_the_real_folders_key()
    {
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("data", "repo");
        var linkdir = Link("linkdir", Path.Combine(_root, "data"));
        var viaLink = Path.Combine(linkdir, "repo");
        Assert.True(Directory.Exists(viaLink));
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(viaLink, false));
    }

    [Fact]
    public void A_chain_of_links_and_a_relative_link_resolve_to_the_real_folder()
    {
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("data", "repo");
        Link("l1", repo);
        var l2 = Link("l2", Path.Combine(_root, "l1"));
        Directory.CreateSymbolicLink(Path.Combine(_root, "rel"), Path.Combine("data", "repo"));   // relative target
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(l2, false));
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(Path.Combine(_root, "rel"), false));
    }

    [Fact]
    public void The_lock_file_is_the_same_for_the_real_folder_and_a_path_through_a_linked_parent()
    {
        // The key above is only half of it: it is the LOCK FILE that two sessions must share.
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("data", "repo");
        var viaLink = Path.Combine(Link("linkdir", Path.Combine(_root, "data")), "repo");
        Assert.Equal(FolderKey.LockPath("/h", repo, false), FolderKey.LockPath("/h", viaLink, false));
    }

    [Fact]
    public void A_chain_of_six_links_still_resolves_to_the_real_folder()
    {
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("data", "repo");
        var previous = repo;
        for (var i = 1; i <= 6; i++)
            previous = Link("c" + i, previous);
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(previous, false));
    }

    [Fact]
    public void A_link_target_that_goes_through_another_link_and_back_out_with_dot_dot_resolves_as_the_kernel_does()
    {
        // Capstone round 1 (set below the floor by the peer, MEASURED real 2026-10-27): l1 -> "l2/../repo" where l2 -> deep/sub.
        // The kernel dereferences l2 FIRST and then applies "..", landing in deep/repo; collapsing "l2/.." as text gives
        // <root>/repo, a different folder, so an alias of deep/repo would get its own lock.
        if (OperatingSystem.IsWindows()) return;
        var deepRepo = Make("deep", "repo");
        Make("deep", "sub");
        Make("repo");
        Link("l2", Path.Combine(_root, "deep", "sub"));
        Directory.CreateSymbolicLink(Path.Combine(_root, "l1"), Path.Combine("l2", "..", "repo"));
        Assert.True(Directory.Exists(Path.Combine(_root, "l1")));
        Assert.Equal(FolderKey.Canonical(deepRepo, false), FolderKey.Canonical(Path.Combine(_root, "l1"), false));
        Assert.NotEqual(FolderKey.Canonical(Path.Combine(_root, "repo"), false), FolderKey.Canonical(Path.Combine(_root, "l1"), false));
    }

    [Fact]
    public void A_link_in_a_folder_nested_deeper_than_the_link_cap_is_still_resolved()
    {
        // The cap is on LINKS followed (the kernel's 40), not on path length: a deep ordinary folder must not stop the walk.
        if (OperatingSystem.IsWindows()) return;
        var deep = Make(Enumerable.Repeat("d", 50).ToArray());
        var real = Path.Combine(deep, "real");
        Directory.CreateDirectory(real);
        var alias = Path.Combine(deep, "alias");
        Directory.CreateSymbolicLink(alias, real);
        Assert.Equal(FolderKey.Canonical(real, false), FolderKey.Canonical(alias, false));
    }

    [Fact]
    public async Task A_link_loop_ends_instead_of_hanging()
    {
        if (OperatingSystem.IsWindows()) return;
        Directory.CreateSymbolicLink(Path.Combine(_root, "a"), Path.Combine(_root, "b"));
        Directory.CreateSymbolicLink(Path.Combine(_root, "b"), Path.Combine(_root, "a"));
        var task = Task.Run(() => FolderKey.Canonical(Path.Combine(_root, "a"), false));
        var completed = await Task.WhenAny(task, Task.Delay(TimeSpan.FromSeconds(10))) == task;
        Assert.True(completed, "a symlink loop must not hang the key");
        // A loop of two links ends on the 41st hop, which is `a` (odd hops are `a`): the last path seen, not an empty or shared key.
        Assert.Equal(Path.Combine(_root, "a"), await task);
    }

    [Fact]
    public void A_chain_of_forty_links_resolves_and_the_forty_first_stops_where_it_stands()
    {
        // The cap is the kernel's 40 LINKS: 40 still reach the real folder, the 41st is treated as a plain directory.
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("data", "repo");
        var previous = repo;
        for (var i = 1; i <= 41; i++)
        {
            previous = Link("c" + i, previous);
            if (i == 40)
                Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(previous, false));
        }
        Assert.Equal(Path.Combine(_root, "c1"), FolderKey.Canonical(previous, false));
    }

    [Fact]
    public void A_link_target_with_dot_segments_a_doubled_separator_or_a_trailing_one_gives_the_real_folders_key()
    {
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("data", "repo");
        Directory.CreateSymbolicLink(Path.Combine(_root, "rel"), "./data//repo/");
        Directory.CreateSymbolicLink(Path.Combine(_root, "self"), ".");
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(Path.Combine(_root, "rel"), false));
        Assert.Equal(FolderKey.Canonical(_root, false), FolderKey.Canonical(Path.Combine(_root, "self"), false));
    }

    [Fact]
    public void A_dot_dot_at_the_root_inside_a_link_target_stays_at_the_root()
    {
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("data", "repo");
        var rootKey = FolderKey.Canonical(Path.GetPathRoot(_root)!, false);
        Directory.CreateSymbolicLink(Path.Combine(_root, "past"), "/../../../../../../../.." + repo);
        Directory.CreateSymbolicLink(Path.Combine(_root, "top"), Path.GetPathRoot(_root)!);
        Directory.CreateSymbolicLink(Path.Combine(_root, "up"), string.Join('/', Enumerable.Repeat("..", 40)));
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(Path.Combine(_root, "past"), false));
        Assert.Equal(rootKey, FolderKey.Canonical(Path.Combine(_root, "top"), false));
        Assert.Equal(rootKey, FolderKey.Canonical(Path.Combine(_root, "up"), false));
    }

    [Fact]
    public void A_dot_dot_in_the_typed_folder_is_collapsed_as_text_before_any_link_is_followed()
    {
        // The comment in Canonical: the typed folder is made absolute lexically, because that is the path Claude is launched in.
        if (OperatingSystem.IsWindows()) return;
        var repo = Make("repo");
        Make("deep", "sub");
        Link("l2", Path.Combine(_root, "deep", "sub"));
        var typed = Path.Combine(_root, "l2", "..", "repo");
        Assert.Equal(FolderKey.Canonical(repo, false), FolderKey.Canonical(typed, false));
        Assert.NotEqual(FolderKey.Canonical(Path.Combine(_root, "deep", "repo"), false), FolderKey.Canonical(typed, false));
    }

    [Fact]
    public void The_case_folding_in_production_follows_the_operating_system()
    {
        // RealStartEffects passes FolderKey.IgnoreCaseHere, which no other test reads: on Windows and macOS two spellings
        // differing only in case are ONE folder, on Linux they are two.
        var lower = FolderKey.LockPath(_root, Path.Combine(_root, "repo"), FolderKey.IgnoreCaseHere);
        var upper = FolderKey.LockPath(_root, Path.Combine(_root, "REPO"), FolderKey.IgnoreCaseHere);
        Assert.Equal(OperatingSystem.IsWindows() || OperatingSystem.IsMacOS(), lower == upper);
    }

    [Fact]
    public void Case_folds_only_where_the_filesystem_does()
    {
        Assert.Equal(FolderKey.Canonical("/a/Repo", true), FolderKey.Canonical("/a/repo", true));
        Assert.NotEqual(FolderKey.Canonical("/a/Repo", false), FolderKey.Canonical("/a/repo", false));
    }

    [Fact]
    public void Different_folders_have_different_keys()
    {
        Assert.NotEqual(FolderKey.LockPath("/h", "/a/repo", false), FolderKey.LockPath("/h", "/a/repo2", false));
    }

    [Fact]
    public void The_lock_file_name_is_pinned_so_a_change_of_key_is_a_decision()
    {
        if (OperatingSystem.IsWindows()) return;   // the same input is "C:\\a\\repo" there; the pin is the Unix spelling
        // sha256 of "/a/repo" and of "/A/REPO" (folded to upper case), first 16 hex digits, computed with python3 hashlib.
        Assert.Equal("/h/.clavity/agy-folder.668405c985a3f02f.lock", FolderKey.LockPath("/h", "/a/repo", ignoreCase: false));
        Assert.Equal("/h/.clavity/agy-folder.53c739e7947b261c.lock", FolderKey.LockPath("/h", "/a/repo", ignoreCase: true));
    }

    [Fact]
    public void The_lock_file_name_has_one_fixed_shape_for_any_folder()
    {
        var name = Path.GetFileName(FolderKey.LockPath("/h", Path.Combine(_root, "any", "folder"), false));
        Assert.Matches("^agy-folder\\.[0-9a-f]{16}\\.lock$", name);
    }

    // ROADMAP section 103: the Windows spellings the link walk cannot see (a subst drive, a loopback admin share). The helpers are
    // pure and run everywhere; the end-to-end rows run only on Windows (windows-latest in CI), where `subst` needs no elevation.

    [Theory]
    [InlineData(@"\\localhost\C$\a\b", @"C:\a\b")]
    [InlineData(@"\\LOCALHOST\d$", @"d:\")]
    [InlineData(@"\\localhost\C$\", @"C:\")]
    [InlineData(@"\\127.0.0.1\C$\x", @"C:\x")]
    public void A_loopback_admin_share_is_written_back_as_its_drive(string share, string expected)
    {
        Assert.Equal(expected, FolderKey.RewriteLoopbackAdminShare(share));
    }

    [Theory]
    [InlineData(@"\\localhost2\C$\x")]      // another host
    [InlineData(@"\\server\C$\x")]          // a real network host
    [InlineData(@"\\127.0.0.10\C$\x")]      // an address that merely starts like the loopback one
    [InlineData(@"\\localhost\share\x")]    // an ordinary share, not an admin share
    [InlineData(@"\\localhost\CC$\x")]      // two letters are not a drive
    [InlineData(@"\\localhost\C$x\y")]      // the $ must end the share name
    [InlineData(@"C:\x")]
    [InlineData("/a/b")]
    public void Any_other_path_is_left_exactly_as_it_is_by_the_loopback_rewrite(string path)
    {
        Assert.Equal(path, FolderKey.RewriteLoopbackAdminShare(path));
    }

    [Theory]
    [InlineData(@"\\?\C:\real\repo", @"C:\real\repo")]
    [InlineData(@"\\?\c:", "c:")]
    [InlineData(@"\\?\UNC\srv\share\x", @"\\srv\share\x")]
    [InlineData(@"\\?\unc\srv\share", @"\\srv\share")]
    public void The_extended_prefix_of_a_final_path_is_removed(string final, string expected)
    {
        Assert.Equal(expected, FolderKey.StripExtendedPrefix(final));
    }

    [Theory]
    [InlineData(@"C:\x")]
    [InlineData(@"\\srv\share\x")]
    [InlineData(@"\\?\Volume{01234567-89ab-cdef-0123-456789abcdef}\x")]   // no drive letter: nothing to name it by
    [InlineData(@"\\?\1:\x")]                                            // a digit is not a drive letter
    [InlineData("/a/b")]
    public void A_path_without_a_removable_prefix_is_left_as_it_is(string path)
    {
        Assert.Equal(path, FolderKey.StripExtendedPrefix(path));
    }

    private static readonly object SubstGate = new();

    private static void Subst(string arguments)
    {
        using var process = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("subst", arguments)
        { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true })!;
        process.WaitForExit();
        Assert.True(process.ExitCode == 0, $"subst {arguments} exited {process.ExitCode}: {process.StandardError.ReadToEnd()}{process.StandardOutput.ReadToEnd()}");
    }

    [Fact]
    public void A_subst_drive_gives_the_same_key_as_the_real_folder()
    {
        if (!OperatingSystem.IsWindows()) return;
        var real = Make("repo");
        Make("other");
        lock (SubstGate)
        {
            var used = DriveInfo.GetDrives().Select(d => char.ToUpperInvariant(d.Name[0])).ToHashSet();
            var letter = "ZYXWVUTSRQPONMLKJIHGFED".First(c => !used.Contains(c));
            Subst($"{letter}: \"{_root}\"");
            try
            {
                Assert.Equal(FolderKey.Canonical(real, true), FolderKey.Canonical($"{letter}:\\repo", true));
                Assert.Equal(FolderKey.Canonical(_root, true), FolderKey.Canonical($"{letter}:\\", true));
                Assert.NotEqual(FolderKey.Canonical(real, true), FolderKey.Canonical($"{letter}:\\other", true));   // distractor: a sibling still differs
                Assert.Equal(FolderKey.LockPath("/h", real, true), FolderKey.LockPath("/h", $"{letter}:\\repo", true));
            }
            finally
            {
                Subst($"{letter}: /D");
            }
        }
    }

    [Fact]
    public void A_loopback_admin_share_gives_the_same_key_as_the_real_folder()
    {
        if (!OperatingSystem.IsWindows()) return;
        var real = Make("repo");
        Make("other");
        var share = $"\\\\localhost\\{real[0]}$\\{real[3..]}";
        Assert.Equal(FolderKey.Canonical(real, true), FolderKey.Canonical(share, true));
        Assert.NotEqual(FolderKey.Canonical(real, true), FolderKey.Canonical(share.Replace("repo", "other"), true));
    }

    [Fact]
    public void A_folder_that_cannot_be_opened_keeps_its_lexical_key_and_does_not_throw()
    {
        if (!OperatingSystem.IsWindows()) return;
        var missing = Path.Combine(_root, "no", "such", "folder");
        Assert.Equal(Path.GetFullPath(missing).ToUpperInvariant(), FolderKey.Canonical(missing, true));
    }

    [Fact]
    public void A_plain_folder_keeps_the_key_it_always_had()
    {
        if (!OperatingSystem.IsWindows()) return;
        // The final-path step must not change the lock file of a folder that needed no resolving: an upgrade would orphan it. The
        // Windows directory, not a temp folder: a CI temp path carries an 8.3 short name (RUNNER~1), which Path.GetFullPath already expands.
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        Assert.Equal(Path.GetFullPath(windows).ToUpperInvariant(), FolderKey.Canonical(windows, true));
    }

    // FinalPathFromQuery: the buffer retry and the failure fallback of the Windows final-path step, run here with a fake query (no handle).
    private static Func<StringBuilder, uint, uint> Answer(List<uint> sizes, string text, uint? first = null)
    {
        return (buffer, size) =>
        {
            sizes.Add(size);
            if (first is { } wrong && sizes.Count == 1)
                return wrong;   // "your buffer is too small, I need this many"
            buffer.Append(text);
            return (uint)text.Length;
        };
    }

    [Fact]
    public void A_final_path_that_fits_is_read_once_and_loses_its_extended_prefix()
    {
        var sizes = new List<uint>();
        Assert.Equal(@"C:\x", FolderKey.FinalPathFromQuery("fallback", Answer(sizes, @"\\?\C:\x")));
        Assert.Equal(new uint[] { 512 }, sizes);
    }

    [Fact]
    public void A_final_path_longer_than_the_buffer_is_asked_for_again_with_a_buffer_one_larger_than_the_answer()
    {
        var sizes = new List<uint>();
        var longPath = @"\\?\C:\" + new string('a', 590);   // 597 chars
        var result = FolderKey.FinalPathFromQuery("fallback", Answer(sizes, longPath, first: 600));
        Assert.Equal(longPath[4..], result);
        Assert.Equal(new uint[] { 512, 601 }, sizes);
    }

    [Fact]
    public void A_query_that_reports_failure_gives_the_fallback()
    {
        var calls = 0;
        Assert.Equal("fallback", FolderKey.FinalPathFromQuery("fallback", (_, _) => { calls++; return 0; }));
        Assert.Equal(1, calls);
    }

    [Fact]
    public void A_query_that_still_does_not_fit_after_the_one_retry_gives_the_fallback_and_is_not_asked_a_third_time()
    {
        var calls = 0;
        Assert.Equal("fallback", FolderKey.FinalPathFromQuery("fallback", (_, _) => { calls++; return calls == 1 ? 700u : 900u; }));
        Assert.Equal(2, calls);
    }

    [System.Runtime.InteropServices.DllImport("kernel32.dll", EntryPoint = "GetShortPathNameW", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern uint GetShortPathName(string longPath, StringBuilder shortPath, uint size);

    [Fact]
    public void An_8_3_short_name_gives_the_same_key_as_the_long_name()
    {
        if (!OperatingSystem.IsWindows()) return;
        var real = Make("a folder with a long name");
        var sibling = Make("another folder with a long name");
        var buffer = new StringBuilder(1024);
        Assert.True(GetShortPathName(real, buffer, (uint)buffer.Capacity) > 0, "GetShortPathName failed");
        var shortName = buffer.ToString();
        // The input must really differ, or this test would pass whatever the code does (8.3 generation off on the volume). Two independent guards give this key (Path.GetFullPath and the final-path step), so only a mutant that disables both turns this row red.
        Assert.NotEqual(real, shortName, StringComparer.OrdinalIgnoreCase);
        Assert.Equal(FolderKey.Canonical(real, true), FolderKey.Canonical(shortName, true));
        Assert.NotEqual(FolderKey.Canonical(real, true), FolderKey.Canonical(GetShort(sibling), true));   // distractor: a sibling's short name still differs
    }

    private static string GetShort(string path)
    {
        var buffer = new StringBuilder(1024);
        Assert.True(GetShortPathName(path, buffer, (uint)buffer.Capacity) > 0, "GetShortPathName failed");
        return buffer.ToString();
    }
}
