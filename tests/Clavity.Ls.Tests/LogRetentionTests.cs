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
}
