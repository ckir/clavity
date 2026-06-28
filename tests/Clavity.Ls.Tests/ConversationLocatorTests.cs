using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class ConversationLocatorTests
{
    [Fact]
    public void Newest_picks_the_latest_by_mtime()
    {
        var items = new[]
        {
            new ConversationDb("old", new DateTime(2026, 6, 1, 0, 0, 0, DateTimeKind.Utc)),
            new ConversationDb("newest", new DateTime(2026, 6, 28, 0, 0, 0, DateTimeKind.Utc)),
            new ConversationDb("mid", new DateTime(2026, 6, 15, 0, 0, 0, DateTimeKind.Utc)),
        };
        Assert.Equal("newest", ConversationLocator.Newest(items));
    }

    [Fact]
    public void Newest_of_empty_is_null() =>
        Assert.Null(ConversationLocator.Newest(Array.Empty<ConversationDb>()));

    [Fact]
    public void NewestActive_returns_newest_db_filename_stem()
    {
        var dir = Path.Combine(Path.GetTempPath(), "clavity-convtest-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var a = Path.Combine(dir, "aaaaaaaa-0000-0000-0000-000000000000.db");
            var b = Path.Combine(dir, "bbbbbbbb-0000-0000-0000-000000000000.db");
            File.WriteAllText(a, "");
            File.WriteAllText(b, "");
            File.SetLastWriteTimeUtc(a, new DateTime(2026, 6, 1, 0, 0, 0, DateTimeKind.Utc));
            File.SetLastWriteTimeUtc(b, new DateTime(2026, 6, 28, 0, 0, 0, DateTimeKind.Utc));
            Assert.Equal("bbbbbbbb-0000-0000-0000-000000000000", ConversationLocator.NewestActive(dir));
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void NewestActive_missing_dir_is_null() =>
        Assert.Null(ConversationLocator.NewestActive(
            Path.Combine(Path.GetTempPath(), "clavity-no-such-" + Guid.NewGuid().ToString("N"))));
}
