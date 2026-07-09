namespace Clavity.Ls;

/// <summary>
/// Age-based cleanup of per-session agy logs (<c>logs/clavity-*.log</c>), run on <c>clavity start</c>.
/// NOT PID-liveness based: the captured <c>wt.exe</c> PID is not agy's (spec §3/§11a).
/// </summary>
public static class LogRetention
{
    /// <summary>Default retention window for per-session logs.</summary>
    public static readonly TimeSpan DefaultMaxAge = TimeSpan.FromDays(7);

    /// <summary>Delete <c>clavity-*.log</c> files in <paramref name="logsDir"/> older than <paramref name="maxAge"/>
    /// relative to <paramref name="nowUtc"/>. Missing dir is a no-op; a file held open by a live agy is skipped.</summary>
    public static void Prune(string logsDir, TimeSpan maxAge, DateTime nowUtc)
    {
        if (!Directory.Exists(logsDir))
            return;

        foreach (var path in Directory.EnumerateFiles(logsDir, "clavity-*.log"))
        {
            try
            {
                if (nowUtc - File.GetLastWriteTimeUtc(path) > maxAge)
                    File.Delete(path);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                // A live agy may hold its log open, or perms may deny deletion — skip it. Pruning a stale
                // background log must never abort `clavity start`.
            }
        }
    }
}
