// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class LogRetentionTests
{
    [Fact]
    public void Prune_deletes_logs_older_than_max_age_and_keeps_recent_ones()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-logret-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var now = new DateTime(2026, 6, 28, 12, 0, 0, DateTimeKind.Utc);
            var old = Path.Combine(dir, "clavity-old.log");
            var fresh = Path.Combine(dir, "clavity-fresh.log");
            var unrelated = Path.Combine(dir, "cli.log");
            File.WriteAllText(old, "");
            File.WriteAllText(fresh, "");
            File.WriteAllText(unrelated, "");
            File.SetLastWriteTimeUtc(old, now.AddDays(-8));
            File.SetLastWriteTimeUtc(fresh, now.AddDays(-1));
            File.SetLastWriteTimeUtc(unrelated, now.AddDays(-30));

            LogRetention.Prune(dir, TimeSpan.FromDays(7), now);

            Assert.False(File.Exists(old), "old clavity log should be pruned");
            Assert.True(File.Exists(fresh), "recent clavity log should be kept");
            Assert.True(File.Exists(unrelated), "non-clavity logs must not be touched");
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void Prune_on_missing_directory_does_not_throw() =>
        LogRetention.Prune(
            Path.Combine(Path.GetTempPath(), "clavity-no-such-" + Guid.NewGuid().ToString("N")),
            TimeSpan.FromDays(7), DateTime.UtcNow);

    [Fact]
    public void Prune_skips_a_file_it_cannot_delete_and_still_prunes_what_it_can()
    {
        // A directory without write permission makes File.Delete throw UnauthorizedAccessException; the swallowed branch must
        // neither throw nor stop the sweep. (POSIX only: Windows ACLs are not set up from here; root ignores the mode.)
        if (OperatingSystem.IsWindows() || Environment.UserName == "root")
            return;
        var dir = Path.Combine(Path.GetTempPath(), "clavity-logret-ro-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var now = new DateTime(2026, 6, 28, 12, 0, 0, DateTimeKind.Utc);
        var old = Path.Combine(dir, "clavity-old.log");
        File.WriteAllText(old, "");
        File.SetLastWriteTimeUtc(old, now.AddDays(-8));
        var original = File.GetUnixFileMode(dir);
        File.SetUnixFileMode(dir, UnixFileMode.UserRead | UnixFileMode.UserExecute);
        try
        {
            LogRetention.Prune(dir, TimeSpan.FromDays(7), now);   // must not throw
            Assert.True(File.Exists(old), "a file that cannot be deleted stays");
        }
        finally
        {
            File.SetUnixFileMode(dir, original);
            Directory.Delete(dir, true);
        }
    }
}
