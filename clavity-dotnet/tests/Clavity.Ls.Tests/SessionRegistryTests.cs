using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class SessionRegistryTests : IDisposable
{
    private readonly string _home = Path.Combine(Path.GetTempPath(), "clavity-reg-" + Guid.NewGuid().ToString("N"));
    private readonly string _repo;
    private const string A = "aaaaaaaa-0000-0000-0000-000000000001";
    private const string B = "bbbbbbbb-0000-0000-0000-000000000002";

    public SessionRegistryTests()
    {
        Directory.CreateDirectory(Path.Combine(_home, ".clavity"));
        _repo = Directory.CreateDirectory(Path.Combine(_home, "repo")).FullName;
    }

    public void Dispose()
    {
        if (Directory.Exists(_home))
            Directory.Delete(_home, recursive: true);
    }

    private sealed class Ports(params int[] open) : IListeningPorts
    {
        public bool IsListening(int port) => open.Contains(port);
    }

    private SessionPaths Record(string id, string folder, DateTime? at = null)
    {
        var p = SessionPaths.For(_home, id);
        File.WriteAllText(p.Folder, folder + "\n");
        if (at is { } t)
            File.SetLastWriteTimeUtc(p.Folder, t);
        return p;
    }

    private static void Publish(SessionPaths p, int port) =>
        File.WriteAllText(p.Endpoint, $$"""{"csrf":"t","addr":"127.0.0.1:{{port}}","published":"x"}""");

    // Default: every session's `clavity-ls agy` is alive (its .alive held) and no `start` holds its .lock.
    private static bool AliveOnly(string path) => path.EndsWith(".alive", StringComparison.Ordinal);

    private IReadOnlyList<WaitingSession> Find(IListeningPorts? ports = null, Func<string, bool>? held = null) =>
        SessionRegistry.Find(_home, _repo, ports ?? new Ports(), held ?? AliveOnly);

    [Fact]
    public void A_session_that_has_not_published_yet_is_waiting_unpaired()
    {
        Record(A, _repo);
        var s = Assert.Single(Find());
        Assert.Equal(A, s.SessionId);
        Assert.False(s.Paired);
        Assert.False(s.Taken);
    }

    [Fact]
    public void A_session_whose_agy_process_is_gone_is_skipped_even_without_an_exited_file()
    {
        Record(A, _repo);                                       // killed -9 or rebooted: no .exited, .alive released
        Assert.Empty(Find(held: _ => false));
        Assert.Single(Find());                                  // control: the same record while .alive is held
    }

    [Fact]
    public void A_published_session_counts_only_while_its_port_listens()
    {
        Publish(Record(A, _repo), 4242);
        Assert.True(Assert.Single(Find(new Ports(4242))).Paired);
        Assert.Empty(Find(new Ports(1)));                       // published, nothing listens: that agy is gone
    }

    [Fact]
    public void An_ended_session_and_another_folders_session_are_skipped()
    {
        var ended = Record(A, _repo);
        File.WriteAllText(ended.Exited, "0\n");
        Record(B, _repo);
        Record("cccccccc-0000-0000-0000-000000000003", Path.Combine(_home, "other"));
        Assert.Equal(B, Assert.Single(Find()).SessionId);
    }

    [Fact]
    public void A_session_another_start_holds_comes_back_marked_taken()
    {
        var held = Record(A, _repo);
        Assert.True(Assert.Single(Find(held: path => AliveOnly(path) || path == held.Lock)).Taken);
        Assert.False(Assert.Single(Find()).Taken);              // control: free lock
    }

    [Fact]
    public void A_trailing_separator_in_the_record_still_matches_and_a_malformed_name_is_ignored()
    {
        Record(A, _repo + Path.DirectorySeparatorChar);
        File.WriteAllText(Path.Combine(_home, ".clavity", "agy-session.not-a-guid.folder"), _repo + "\n");
        Assert.Equal(A, Assert.Single(Find()).SessionId);
    }

    [Fact]
    public void Several_waiting_sessions_come_back_oldest_first()
    {
        Record(B, _repo, new DateTime(2026, 10, 3, 10, 0, 0, DateTimeKind.Utc));
        Record(A, _repo, new DateTime(2026, 10, 3, 11, 0, 0, DateTimeKind.Utc));
        Assert.Equal([B, A], Find().Select(s => s.SessionId));
    }

    [Fact]
    public void Without_a_folder_every_folders_sessions_come_back_each_with_its_recorded_folder()
    {
        var elsewhere = Path.Combine(_home, "other");
        Record(A, _repo);
        Record(B, elsewhere + Path.DirectorySeparatorChar);
        var all = SessionRegistry.Find(_home, null, new Ports(), AliveOnly);
        Assert.Equal(_repo, all.Single(s => s.SessionId == A).Folder);
        Assert.Equal(elsewhere + Path.DirectorySeparatorChar, all.Single(s => s.SessionId == B).Folder);
        Assert.Equal(A, Assert.Single(Find()).SessionId);       // control: with a folder, only that folder's
    }

    [Theory]
    [InlineData("a/b", "a/b/", true)]
    [InlineData("a/b", "a/c", false)]
    public void SameFolder_ignores_a_trailing_separator_only(string x, string y, bool same)
        => Assert.Equal(same, SessionRegistry.SameFolder(Path.Combine(_home, x), Path.Combine(_home, y)));

    [Fact]
    public void No_clavity_directory_means_no_sessions()
        => Assert.Empty(SessionRegistry.Find(Path.Combine(_home, "nobody"), _repo, new Ports(), AliveOnly));
}
