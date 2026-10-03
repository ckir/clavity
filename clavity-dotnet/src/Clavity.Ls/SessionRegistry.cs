namespace Clavity.Ls;

/// <summary>An agy session started by `clavity-ls agy` that `start --attach` without an id may pair with. <see
/// cref="Paired"/>: agy has published an endpoint whose port listens; false while agy is still starting (or waiting on a
/// trust prompt). <see cref="Taken"/>: another `start` holds its lock - returned, not dropped, so the caller can say
/// "already has a Claude" instead of "run agy first". <see cref="Folder"/>: the folder its `.folder` record names.</summary>
public sealed record WaitingSession(string SessionId, bool Paired, DateTime StartedUtc, bool Taken = false, string Folder = "");

/// <summary>Finds the agy sessions in a folder that `start --attach` without an id may pair with (ROADMAP section 65). A
/// session counts when its `.folder` record names the folder, the `clavity-ls agy` running it still holds its `.alive`
/// lock, it has no `.exited` file, and its published endpoint (if any) still listens; a session another `start` holds is
/// returned with <see cref="WaitingSession.Taken"/> set. A null <paramref name="folder"/> returns every folder's sessions
/// (capstone R1: the same folder reached through a symlink does not compare equal, so `start` lists those instead of
/// saying none waits). <paramref name="isHeld"/> answers "does some process hold this lock file?"
/// (<see cref="SessionLock.IsTaken"/>).</summary>
public static class SessionRegistry
{
    private const string Prefix = "agy-session.";
    private const string Suffix = ".folder";

    public static IReadOnlyList<WaitingSession> Find(string userProfileDir, string? folder, IListeningPorts listening,
        Func<string, bool> isHeld)
    {
        var dir = Path.Combine(userProfileDir, ".clavity");
        if (!Directory.Exists(dir))
            return [];
        var found = new List<WaitingSession>();
        foreach (var record in Directory.EnumerateFiles(dir, Prefix + "*" + Suffix))
        {
            var name = Path.GetFileName(record);
            var id = name[Prefix.Length..^Suffix.Length];
            if (!SessionPaths.IsValidSessionId(id))
                continue;
            string recorded;
            try
            {
                recorded = File.ReadAllText(record).Trim();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                continue;
            }
            if (recorded.Length == 0 || (folder is not null && !SameFolder(recorded, folder)))
                continue;
            var paths = SessionPaths.For(userProfileDir, id);
            if (!isHeld(paths.Alive))
                continue;   // its `clavity-ls agy` is gone - killed, or the machine rebooted - even if no .exited exists
            if (File.Exists(paths.Exited))
                continue;
            var paired = false;
            if (AgyEndpoint.TryRead(paths.Endpoint) is { } ep)
            {
                if (!listening.IsListening(ep.Port))
                    continue;   // published, but nothing listens: that agy is gone
                paired = true;
            }
            found.Add(new WaitingSession(id, paired, File.GetLastWriteTimeUtc(record), Taken: isHeld(paths.Lock),
                Folder: recorded));
        }
        return found.OrderBy(s => s.StartedUtc).ThenBy(s => s.SessionId, StringComparer.Ordinal).ToList();
    }

    /// <summary>The comparison `start` and the registry agree on: full paths, a trailing separator ignored, ordinal (the
    /// `agy` verb that writes records runs on Linux / macOS). Symlinks are NOT resolved - on purpose (capstone R1,
    /// AGY-FIRST): a mismatch is answered by listing the sessions waiting elsewhere.</summary>
    public static bool SameFolder(string a, string b) => Normalize(a) == Normalize(b);

    private static string Normalize(string path) => Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
}
