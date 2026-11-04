// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

namespace Clavity.Ls;

/// <summary>Parsed <c>clavity-ls start [folder] [--attach [&lt;session-id&gt;]] [--profile &lt;name&gt;] [claude-args...]</c>
/// (<c>--attach</c> and <c>--profile</c> in either order).</summary>
public sealed record StartArgs(string Folder, bool Attach, string? AttachSessionId, string? Profile, string[] ClaudeArgs)
{
    public const string AttachFlag = "--attach";
    public const string ProfileFlag = "--profile";

    /// <summary>The folder is the first argument unless it starts with '-'. <c>--attach</c> and <c>--profile</c> are ours
    /// only in the run of arguments DIRECTLY after it (or first, with no folder), in either order, so every later
    /// argument still reaches Claude untouched. <c>--profile</c> takes a required value (non-blank, not starting with
    /// '-') and may appear once; a missing or bad value or a repeat throws <see cref="ArgumentException"/>. The
    /// <c>--attach</c> id is optional (ROADMAP
    /// section 65: with none, `start` pairs with the one agy session waiting in the folder): a valid id is consumed; an
    /// argument SHAPED like an id but invalid throws <see cref="ArgumentException"/> (a mistyped id must not silently
    /// become a prompt); anything else is Claude's. Only a valid id ever becomes part of a file name.</summary>
    public static StartArgs Parse(string[] rest, string currentDirectory)
    {
        var i = 0;
        string folder;
        if (rest.Length > 0 && !rest[0].StartsWith('-'))
        {
            folder = Path.GetFullPath(rest[0], currentDirectory);
            i = 1;
        }
        else
        {
            folder = currentDirectory;
        }

        var attach = false;
        string? id = null;
        string? profile = null;
        while (i < rest.Length)
        {
            if (rest[i] == AttachFlag && !attach)
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
            else if (rest[i] == ProfileFlag)
            {
                if (profile is not null)
                {
                    throw new ArgumentException($"{ProfileFlag} may be given only once.");
                }

                i++;
                if (i >= rest.Length || string.IsNullOrWhiteSpace(rest[i]) || rest[i].StartsWith('-'))
                {
                    throw new ArgumentException($"{ProfileFlag} needs a profile name (a non-blank value not starting with '-').");
                }

                if (!ValidProfileName(rest[i]))
                {
                    throw new ArgumentException(
                        $"{ProfileFlag} '{rest[i]}' is not a valid profile name - use only letters, digits, '.', '_' and '-' (not '.' or '..').");
                }

                profile = rest[i];
                i++;
            }
            else
            {
                break;
            }
        }

        return new StartArgs(folder, attach, id, profile, rest[i..]);
    }

    // A profile name becomes a file name (the setup lock) and a directory name (agent-profile), so only a plain token is allowed:
    // no path separators, drive colons, spaces or other characters a path or a shell would treat specially.
    private static bool ValidProfileName(string s) =>
        s is not ("." or "..") && s.Length > 0 && s.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-');

    // Hex digits and dashes only, 8 or more: what a mistyped or truncated session id looks like.
    private static bool LooksLikeAnId(string s) => s.Length >= 8 && s.All(c => c == '-' || char.IsAsciiHexDigit(c));
}
