namespace Clavity.Ls;

/// <summary>The "a Claude has this agy session" marker (ROADMAP section 65): an exclusive handle on the session's `.lock`
/// file, held by the `start --attach` that paired, for as long as it runs. The OS drops it when that process ends, even
/// when it is killed - MEASURED 2026-10-03 on Windows 11 and Ubuntu: a second process's exclusive open fails with
/// IOException while it is held, and succeeds after the holder is killed -9.</summary>
public static class SessionLock
{
    /// <summary>The held lock, or null when another holder has it. Dispose it to release.</summary>
    public static IDisposable? TryTake(string lockPath)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(lockPath)!);
        try
        {
            return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        catch (IOException)
        {
            return null;
        }
    }

    /// <summary>True while another holder has <paramref name="lockPath"/>. A missing file is not taken; the probe holds
    /// nothing afterwards.</summary>
    public static bool IsTaken(string lockPath)
    {
        if (!File.Exists(lockPath))
            return false;
        try
        {
            using var probe = new FileStream(lockPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            return false;
        }
        catch (FileNotFoundException)
        {
            return false;   // removed between the check and the open
        }
        catch (IOException)
        {
            return true;
        }
    }
}
