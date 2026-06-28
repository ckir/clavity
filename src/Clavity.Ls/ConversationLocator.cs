namespace Clavity.Ls;

/// <summary>A persisted agy conversation: its id (the .db filename stem) and last-write time (UTC).</summary>
public sealed record ConversationDb(string ConversationId, DateTime LastWriteUtc);

/// <summary>
/// Locates the ACTIVE agy conversation = the most-recently-modified <c>conversations/&lt;uuid&gt;.db</c>.
/// EMPIRICALLY-DERIVED (agy 1.0.11): per-conversation state is SQLite at
/// <c>~/.gemini/antigravity-cli/conversations/&lt;uuid&gt;.db</c>; the active one is newest by mtime.
/// </summary>
public static class ConversationLocator
{
    /// <summary>The conversation id of the newest entry by <see cref="ConversationDb.LastWriteUtc"/>, or null if none.</summary>
    public static string? Newest(IEnumerable<ConversationDb> conversations)
    {
        ConversationDb? best = null;
        foreach (var c in conversations)
            if (best is null || c.LastWriteUtc > best.LastWriteUtc)
                best = c;
        return best?.ConversationId;
    }

    /// <summary>
    /// Enumerate <paramref name="conversationsDir"/> for <c>*.db</c> and return the newest conversation id by
    /// file mtime, or null if the directory is missing or empty. The id is the filename without the .db extension.
    /// </summary>
    public static string? NewestActive(string conversationsDir)
    {
        if (!Directory.Exists(conversationsDir))
            return null;
        var dbs = Directory.EnumerateFiles(conversationsDir, "*.db")
            .Select(p => new ConversationDb(Path.GetFileNameWithoutExtension(p), File.GetLastWriteTimeUtc(p)));
        return Newest(dbs);
    }
}
