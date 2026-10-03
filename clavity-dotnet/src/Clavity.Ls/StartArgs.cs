namespace Clavity.Ls;

/// <summary>Parsed <c>clavity-ls start [folder] [--attach &lt;session-id&gt;] [claude-args...]</c>.</summary>
public sealed record StartArgs(string Folder, string? AttachSessionId, string[] ClaudeArgs)
{
    public const string AttachFlag = "--attach";

    /// <summary>The folder is the first argument unless it starts with '-'. <c>--attach &lt;id&gt;</c> is ours only
    /// DIRECTLY after it (or first, with no folder), so every later argument still reaches Claude untouched. Throws
    /// <see cref="ArgumentException"/> for a missing or malformed id.</summary>
    public static StartArgs Parse(string[] rest, string currentDirectory)
    {
        var i = 0;
        string folder;
        if (rest.Length > 0 && !rest[0].StartsWith('-'))
        {
            folder = Path.GetFullPath(rest[0]);
            i = 1;
        }
        else
        {
            folder = currentDirectory;
        }

        string? attach = null;
        if (i < rest.Length && rest[i] == AttachFlag)
        {
            if (i + 1 >= rest.Length)
                throw new ArgumentException($"{AttachFlag} needs the session id that `clavity-ls agy` printed.");
            attach = rest[i + 1];
            if (!SessionPaths.IsValidSessionId(attach))
                throw new ArgumentException(
                    $"{AttachFlag} '{attach}' is not a session id - use the one `clavity-ls agy` printed.");
            i += 2;
        }

        return new StartArgs(folder, attach, rest[i..]);
    }
}
