namespace Clavity.Ls;

/// <summary>The per-session files every verb that pairs Claude with agy agrees on: <c>start</c> (launches both),
/// <c>start --attach</c> (Claude only) and <c>agy</c> (agy only, Linux/macOS). All of them derive the names from the
/// session id alone, so two commands run in two different terminals still meet (ROADMAP section 62).</summary>
public sealed record SessionPaths(string SessionId, string AgyLog, string Endpoint, string AgyScript, string Claim, string Exited,
    string Folder, string Lock, string Alive)
{
    public static SessionPaths For(string userProfileDir, string sessionId)
    {
        var logs = Path.Combine(userProfileDir, ".gemini", "antigravity-cli", "logs");
        var clavity = Path.Combine(userProfileDir, ".clavity");
        return new SessionPaths(
            sessionId,
            AgyLog: Path.Combine(logs, $"clavity-{sessionId}.log"),
            Endpoint: Path.Combine(clavity, $"agy-endpoint.{sessionId}.json"),
            AgyScript: Path.Combine(clavity, $"agy-session.{sessionId}.sh"),
            Claim: Path.Combine(clavity, $"agy-session.{sessionId}.claim"),
            // Written by the agy script (trap / finally) with agy's exit code, so a waiting start stops waiting.
            Exited: Path.Combine(clavity, $"agy-session.{sessionId}.exited"),
            // Written by `clavity-ls agy`: the folder this session runs in, so `start --attach` without an id finds it
            // (ROADMAP section 65).
            Folder: Path.Combine(clavity, $"agy-session.{sessionId}.folder"),
            // Held exclusively by the `start --attach` that paired with this session, for as long as it runs (SessionLock).
            Lock: Path.Combine(clavity, $"agy-session.{sessionId}.lock"),
            // Held exclusively by the `clavity-ls agy` that runs this session, for agy's whole run: a session counts as
            // waiting only while it is held, so a terminal killed -9 (no exit trap) or a reboot leaves no stale session.
            Alive: Path.Combine(clavity, $"agy-session.{sessionId}.alive"));
    }

    /// <summary>A session id is the GUID "D" form <c>start</c> and <c>agy</c> mint. Anything else is refused before it
    /// becomes part of a file name: an id typed into <c>--attach</c> must not be able to name another path.</summary>
    public static bool IsValidSessionId(string? id) => id is not null && Guid.TryParseExact(id, "D", out _);
}
