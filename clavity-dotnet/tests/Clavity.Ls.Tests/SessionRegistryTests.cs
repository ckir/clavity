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
    public void Sessions_started_at_the_same_moment_come_back_in_session_id_order()
    {
        var t = new DateTime(2026, 10, 3, 10, 0, 0, DateTimeKind.Utc);
        Record(B, _repo, t);
        Record(A, _repo, t);
        Assert.Equal([A, B], Find().Select(s => s.SessionId));
    }

    [Fact]
    public void An_empty_folder_record_is_skipped_even_when_every_folder_is_listed()
    {
        Record(A, "  ");            // a record that was created but never written (a crash in between)
        Record(B, _repo);
        Assert.Equal(B, Assert.Single(SessionRegistry.Find(_home, null, new Ports(), AliveOnly)).SessionId);
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
