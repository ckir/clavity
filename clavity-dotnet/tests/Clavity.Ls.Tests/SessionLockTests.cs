// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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

    // ---- TryTakeChecked: the folder lock tells "someone holds it" from "cannot lock at all" (section 101) ----

    [Fact]
    public void TryTakeChecked_takes_a_free_lock_and_returns_null_while_another_holder_has_it()
    {
        using (var first = SessionLock.TryTakeChecked(LockPath))
        {
            Assert.NotNull(first);
            Assert.Null(SessionLock.TryTakeChecked(LockPath));   // held: null, NOT an exception
        }
        using var again = SessionLock.TryTakeChecked(LockPath);   // released: free again
        Assert.NotNull(again);
    }

    [Fact]
    public void TryTakeChecked_reports_an_unwritable_directory_instead_of_calling_it_a_holder()
    {
        if (OperatingSystem.IsWindows() || Environment.UserName == "root") return;   // the permission bits are the mechanism
        var locked = Path.Combine(_dir, "ro");
        Directory.CreateDirectory(locked);
        File.SetUnixFileMode(locked, UnixFileMode.UserRead | UnixFileMode.UserExecute);
        try
        {
            Assert.ThrowsAny<Exception>(() => SessionLock.TryTakeChecked(Path.Combine(locked, "x.lock")));
            Assert.IsType<UnauthorizedAccessException>(
                Record.Exception(() => SessionLock.TryTakeChecked(Path.Combine(locked, "x.lock"))));
        }
        finally
        {
            File.SetUnixFileMode(locked, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        }
    }

    [Fact]
    public void TryTakeChecked_does_not_call_a_lock_it_could_not_even_create_a_holder()
    {
        // An I/O failure that is not contention (here a file name over the 255-byte limit, so no lock file can exist) used to
        // collapse into "another holder has it" and would have printed "already running" for a disk problem.
        if (OperatingSystem.IsWindows()) return;   // long paths are legal there; the mechanism is the Unix name limit
        var tooLong = Path.Combine(_dir, new string('x', 300) + ".lock");
        Assert.Null(SessionLock.TryTake(tooLong));                                   // the old behaviour: a false "held"
        Assert.ThrowsAny<IOException>(() => SessionLock.TryTakeChecked(tooLong));    // the checked one tells the truth
    }
}
