using System;
using System.Globalization;
using System.IO;
using System.Linq;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class ReplyArchiveTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "ra-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true);
    }

    [Fact]
    public void Write_persists_the_answer_and_returns_its_path()
    {
        var path = ReplyArchive.Write(_dir, "conv-1", "the full review text", new DateTime(2026, 8, 19, 10, 30, 0, DateTimeKind.Utc));
        Assert.True(File.Exists(path));
        Assert.Contains("the full review text", File.ReadAllText(path));
    }

    [Fact]
    public void Write_appends_one_size_row_per_reply_and_ReadRecentSizes_returns_them_in_order()
    {
        ReplyArchive.Write(_dir, "c", new string('a', 100), new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc));
        ReplyArchive.Write(_dir, "c", new string('b', 200), new DateTime(2026, 8, 19, 10, 1, 0, DateTimeKind.Utc));
        Assert.Equal(new[] { 100, 200 }, ReplyArchive.ReadRecentSizes(_dir).ToArray());
    }

    [Fact]
    public void ReadRecentSizes_on_a_missing_directory_returns_EMPTY_not_a_throw()
    {
        // A fresh install has no archive. This must be a legitimate empty state, never a crash on the
        // first consult - and never a phantom baseline either.
        Assert.Empty(ReplyArchive.ReadRecentSizes(Path.Combine(_dir, "does-not-exist")));
    }

    [Fact]
    public void A_corrupt_size_row_is_SKIPPED_not_fatal()
    {
        // The archive is observational. A hand-edited or torn row must never take down an ask.
        Directory.CreateDirectory(_dir);
        File.WriteAllText(Path.Combine(_dir, ReplyArchive.SizeIndexFileName), "100\nnot-a-number\n250\n");
        Assert.Equal(new[] { 100, 250 }, ReplyArchive.ReadRecentSizes(_dir).ToArray());
    }

    [Fact]
    public void The_size_index_is_PRUNED_ON_WRITE_to_MaxIndexRows()
    {
        // MUTATION-AUDIT ROW, not in the plan. Deleting the prune block left all five planned rows GREEN,
        // so the AGY-AFTER panel's own accepted fix - the one that stops every ask doing an O(N) read
        // that grows forever with age - shipped with nothing guarding it. A fix nobody tests is a fix
        // the next refactor deletes.
        var t0 = new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc);
        for (var i = 1; i <= ReplyArchive.MaxIndexRows + 5; i++)
            ReplyArchive.Write(_dir, "c", new string('a', i), t0.AddSeconds(i));

        var sizes = ReplyArchive.ReadRecentSizes(_dir);
        Assert.Equal(ReplyArchive.MaxIndexRows, sizes.Count);
        Assert.Equal(6, sizes[0]);                                  // the oldest five were dropped
        Assert.Equal(ReplyArchive.MaxIndexRows + 5, sizes[^1]);      // the newest is still there
    }

    [Fact]
    public void The_REPLY_FILES_are_bounded_too_not_just_the_size_index()
    {
        // CAPSTONE R1 FINDING (Resource Vampire), verified. The index is pruned on write; the .md files
        // it indexes were not, so every ask left one behind forever. The panel's earlier prune fix
        // bounded the READ and left the actual disk growth untouched - a partial fix that reads as a
        // complete one.
        var t0 = new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc);
        for (var i = 1; i <= ReplyArchive.MaxIndexRows + 5; i++)
            ReplyArchive.Write(_dir, "c", new string('a', i), t0.AddSeconds(i));

        var files = Directory.GetFiles(_dir, "*.md");
        Assert.Equal(ReplyArchive.MaxIndexRows, files.Length);
        // The survivors must be the NEWEST, not an arbitrary subset.
        Assert.Contains(files, f => Path.GetFileName(f).StartsWith("20260819-100145", StringComparison.Ordinal));
        Assert.DoesNotContain(files, f => Path.GetFileName(f).StartsWith("20260819-100001", StringComparison.Ordinal));
    }

    [Fact]
    public void A_torn_index_rewrite_cannot_be_observed_because_the_write_is_ATOMIC()
    {
        // CAPSTONE R1 FINDING (Cascade Analyst), folded with a STATED LIMIT. File.WriteAllLines truncates
        // in place, so a crash mid-prune destroys the whole size history silently. No in-process test can
        // kill the process mid-write, so this row pins what IS observable: the prune leaves no temp
        // residue and loses no rows. The atomicity itself rests on File.Replace, the same mechanism the
        // golden header already uses in this repo.
        var t0 = new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc);
        for (var i = 1; i <= ReplyArchive.MaxIndexRows + 3; i++)
            ReplyArchive.Write(_dir, "c", new string('a', i), t0.AddSeconds(i));

        Assert.Empty(Directory.GetFiles(_dir, "*.tmp"));
        Assert.Equal(ReplyArchive.MaxIndexRows, ReplyArchive.ReadRecentSizes(_dir).Count);
    }

    [Fact]
    public void The_pruner_deletes_only_files_IT_wrote_never_a_foreign_one()
    {
        // CAPSTONE R2 FINDING (Mechanism Gamer), verified. The pruner sorted ORDINALLY and deleted the
        // first N. Digits sort before letters, so a file an operator drops in here named "00-scratch.md"
        // sorts above every 2026-timestamped name and is deleted first - silently, since every failure in
        // this class is swallowed. A pruner that deletes someone else's data is a footgun, not a bound.
        Directory.CreateDirectory(_dir);
        var foreign = Path.Combine(_dir, "00-scratch.md");
        File.WriteAllText(foreign, "an operator's notes");

        var t0 = new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc);
        for (var i = 1; i <= ReplyArchive.MaxIndexRows + 5; i++)
            ReplyArchive.Write(_dir, "c", new string('a', i), t0.AddSeconds(i));

        Assert.True(File.Exists(foreign), "the pruner deleted a file it did not write");
        Assert.Equal("an operator's notes", File.ReadAllText(foreign));
    }

    [Fact]
    public void A_concurrent_prune_does_not_make_this_write_fail()
    {
        // CAPSTONE R3 FINDING (State Corruptor) - a defect ROUND 1'S OWN FIX introduced. The atomic prune
        // used a single hardcoded "index.tmp", so two asks pruning at once collide: the loser takes an
        // IOException, swallows it, returns null, and the caller then reports "the size baseline will not
        // advance" - a FALSE alarm, since that ask's row was already appended. A held-open temp file
        // reproduces the collision deterministically, with no threads.
        var t0 = new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc);
        for (var i = 1; i <= ReplyArchive.MaxIndexRows; i++)
            ReplyArchive.Write(_dir, "c", new string('a', i), t0.AddSeconds(i));

        var contended = Path.Combine(_dir, ReplyArchive.SizeIndexFileName + ".tmp");
        using (var _ = new FileStream(contended, FileMode.Create, FileAccess.Write, FileShare.None))
        {
            // The next write must prune (the index is at the cap) while that name is locked.
            var path = ReplyArchive.Write(_dir, "c", new string('a', 500), t0.AddSeconds(999));
            Assert.NotNull(path);
        }
    }

    [Fact]
    public void The_pruner_does_not_delete_a_LOOKALIKE_extension()
    {
        // CAPSTONE R3 FINDING (Dependency Cynic), verified against the documented .NET behaviour: on
        // Windows Directory.GetFiles matches 8.3 short names too, so the pattern "*.md" also matches
        // ".mdx" - the docs give exactly this example ("*.xls" returning "book.xlsx"). A backup named
        // 20260820-120000-notes.mdx would therefore be deleted on Windows and spared on Linux.
        Directory.CreateDirectory(_dir);
        // THE NAME MUST SORT OLDEST, or this row cannot fail for the reason it claims: only the OLDEST
        // files past the cap are deleted. My first attempt used a 2026-08-20 stamp, which sorts NEWEST
        // against the 2026-08-19 fixtures below and so survived no matter what the glob did.
        var lookalike = Path.Combine(_dir, "20260101-000000-notes.mdx");
        File.WriteAllText(lookalike, "a backup");

        var t0 = new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc);
        for (var i = 1; i <= ReplyArchive.MaxIndexRows + 5; i++)
            ReplyArchive.Write(_dir, "c", new string('a', i), t0.AddSeconds(i));

        Assert.True(File.Exists(lookalike), "the pruner deleted a file whose extension only LOOKS like .md");
    }

    [Theory]
    [InlineData("th-TH")]   // Buddhist calendar  -> year 2569
    [InlineData("ar-SA")]   // Umm al-Qura        -> year 1448
    [InlineData("fa-IR")]   // Persian calendar   -> year 1405
    public void The_archive_stays_bounded_under_a_NON_GREGORIAN_calendar_culture(string culture)
    {
        // CAPSTONE R4 FINDING (Time Traveler), confirmed by measurement and WORSE than reported - three
        // cultures break it, not one. String interpolation formats with CurrentCulture, so
        // $"{utcNow:yyyyMMdd-HHmmss}" yields 25690820 under th-TH, 14480307 under ar-SA and 14050529
        // under fa-IR. None of those match the pruner's "20??????-??????-*.md", so the pruner silently
        // stops recognising its OWN files and the archive grows forever. The size index still prunes (it
        // counts lines), so nothing else betrays it. The timestamp is a MACHINE-READABLE KEY, and a key
        // must never be formatted in a user's culture.
        var previous = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = new CultureInfo(culture);
            var t0 = new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc);
            for (var i = 1; i <= ReplyArchive.MaxIndexRows + 5; i++)
                ReplyArchive.Write(_dir, "c", new string('a', i), t0.AddSeconds(i));

            Assert.Equal(ReplyArchive.MaxIndexRows, Directory.GetFiles(_dir, "*.md").Length);
        }
        finally { CultureInfo.CurrentCulture = previous; }
    }

    [Fact]
    public void A_hostile_cascade_id_cannot_write_OUTSIDE_the_archive_directory()
    {
        // MUTATION-AUDIT ROW, not in the plan. Dropping Sanitise entirely left all five planned rows
        // GREEN. The cascade id reaches the filename, so a traversal sequence in it would place the
        // written file outside the archive - a Boundary Smuggler defect with no oracle.
        //
        // THE ID MATTERS. A leading "../.." does NOT escape here and would make this row a control that
        // passes for the wrong reason: the id is always prefixed with the timestamp, so the first segment
        // is "20260819-100000-.." - a literal name, and Windows trims its trailing dots, leaving it
        // harmless. Measured. An id with its OWN separator first ("a/../../evil") produces a real ".."
        // segment and genuinely escapes, which is what this row pins.
        var path = ReplyArchive.Write(_dir, "a/../../evil", "text", new DateTime(2026, 8, 19, 10, 0, 0, DateTimeKind.Utc));
        Assert.NotNull(path);
        Assert.StartsWith(Path.GetFullPath(_dir), Path.GetFullPath(path!), StringComparison.Ordinal);
    }

    [Fact]
    public void Write_NEVER_throws_when_the_directory_cannot_be_created()
    {
        // Capture is observational: a broken archive must not convert a working ask into a failure.
        // A regular FILE where the directory must go makes creation fail deterministically (ENOTDIR).
        var blocker = Path.Combine(Path.GetTempPath(), "ra-block-" + Guid.NewGuid().ToString("N"));
        File.WriteAllText(blocker, "x");
        try
        {
            var path = ReplyArchive.Write(Path.Combine(blocker, "nested"), "c", "text", DateTime.UtcNow);
            Assert.Null(path);
        }
        finally { File.Delete(blocker); }
    }
}
