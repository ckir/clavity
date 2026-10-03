namespace Clavity.Ls;

/// <summary>Parsed <c>clavity-ls start [folder] [--attach [&lt;session-id&gt;]] [claude-args...]</c>.</summary>
public sealed record StartArgs(string Folder, bool Attach, string? AttachSessionId, string[] ClaudeArgs)
{
    public const string AttachFlag = "--attach";

    /// <summary>The folder is the first argument unless it starts with '-'. <c>--attach</c> is ours only DIRECTLY after
    /// it (or first, with no folder), so every later argument still reaches Claude untouched. Its id is optional (ROADMAP
    /// section 65: with none, `start` pairs with the one agy session waiting in the folder): a valid id is consumed; an
    /// argument SHAPED like an id but invalid throws <see cref="ArgumentException"/> (a mistyped id must not silently
    /// become a prompt); anything else is Claude's. Only a valid id ever becomes part of a file name.</summary>
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

        var attach = false;
        string? id = null;
        if (i < rest.Length && rest[i] == AttachFlag)
        {
            attach = true;
            i++;
            if (i < rest.Length && SessionPaths.IsValidSessionId(rest[i]))
            {
                id = rest[i];
                i++;
            }
            else if (i < rest.Length && LooksLikeAnId(rest[i]))
            {
                throw new ArgumentException(
                    $"{AttachFlag} '{rest[i]}' is not a session id - use the one `clavity-ls agy` printed, or none.");
            }
        }

        return new StartArgs(folder, attach, id, rest[i..]);
    }

    // Hex digits and dashes only, 8 or more: what a mistyped or truncated session id looks like.
    private static bool LooksLikeAnId(string s) => s.Length >= 8 && s.All(c => c == '-' || char.IsAsciiHexDigit(c));
}
