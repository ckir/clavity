// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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
    public void A_link_loop_ends_instead_of_hanging()
    {
        if (OperatingSystem.IsWindows()) return;
        Directory.CreateSymbolicLink(Path.Combine(_root, "a"), Path.Combine(_root, "b"));
        Directory.CreateSymbolicLink(Path.Combine(_root, "b"), Path.Combine(_root, "a"));
        var task = Task.Run(() => FolderKey.Canonical(Path.Combine(_root, "a"), false));
        Assert.True(task.Wait(TimeSpan.FromSeconds(10)), "a symlink loop must not hang the key");
        Assert.False(string.IsNullOrEmpty(task.Result));
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
}
