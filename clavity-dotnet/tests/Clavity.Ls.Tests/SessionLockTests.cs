using Clavity.Ls;

namespace Clavity.Ls.Tests;

/// <summary>The "a Claude has this agy session" marker. Cross-process behaviour (a held lock blocks ANOTHER process and
/// is released when the holder is killed -9) was measured on Windows and Linux with .clavity/scratch/s65-lock; these rows
/// pin the same contract inside one process, where a second exclusive open conflicts the same way (measured on both).</summary>
public sealed class SessionLockTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-lock-" + Guid.NewGuid().ToString("N"));
    private string LockPath => Path.Combine(_dir, "sub", "s.lock");

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    [Fact]
    public void A_lock_nobody_holds_is_taken_and_a_second_taker_is_refused_until_it_is_released()
    {
        Assert.False(SessionLock.IsTaken(LockPath));            // missing file: not taken
        using (var first = SessionLock.TryTake(LockPath))        // creates the directory and the file
        {
            Assert.NotNull(first);
            Assert.True(SessionLock.IsTaken(LockPath));
            Assert.Null(SessionLock.TryTake(LockPath));
        }
        Assert.False(SessionLock.IsTaken(LockPath));            // released: free again, the file still exists
        Assert.True(File.Exists(LockPath));
        using var again = SessionLock.TryTake(LockPath);
        Assert.NotNull(again);
    }

    [Fact]
    public void Probing_a_free_lock_does_not_take_it()
    {
        using (SessionLock.TryTake(LockPath)) { }               // leave the file behind, unheld
        Assert.False(SessionLock.IsTaken(LockPath));
        using var taken = SessionLock.TryTake(LockPath);         // the probe released its handle
        Assert.NotNull(taken);
    }
}
