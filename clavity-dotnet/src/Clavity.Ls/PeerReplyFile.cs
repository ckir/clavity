using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>ROADMAP section 74 - the SECOND copy of a discipline reply, written by the peer itself (C-request) and read
/// back only when the chat copy fails a [13b] check (C-peer-read). The root is agy's OWN workspace, from the
/// conversation metadata, because agy writes only inside its working directory (agy-assumptions.md, "agy writes only
/// within its own working directory"); exactly one workspace is required, owner-ruled 2026-10-07 (D-root). The file is
/// requested only when that workspace's .clavity/.gitignore already holds a bare '*' line - the server never writes
/// the shield (D-shield). Every failure is a STATUS, never an exception: the peer file must never fail the ask.</summary>
public static class PeerReplyFile
{
    public const string NonceLinePrefix = "agy-reply-nonce: ";

    /// <summary>Largest peer file read back, in bytes - the same cap as the capture (spec panel R3, LI1).</summary>
    public const int MaxBytes = 1024 * 1024;

    public static (string? Root, string? Status) ResolveRoot(Clavity.Ls.Proto.Metadata? metadata, string? metadataError)
    {
        if (metadata is null)
            return (null, $"not requested: agy's workspace is unknown ({ReplyCapture.Clip(metadataError ?? "no metadata", 120)})");
        var n = metadata.Workspaces.Count;
        if (n == 0) return (null, "not requested: agy reported no workspace");
        if (n > 1)
            return (null, $"not requested: agy reported {n} workspaces, and which one it writes into is not measured (ROADMAP section 74, D-root)");
        var uri = metadata.Workspaces[0].WorkspaceFolderAbsoluteUri;
        if (!Uri.TryCreate(uri, UriKind.Absolute, out var u) || !u.IsFile)
            return (null, $"not requested: agy's workspace URI '{ReplyCapture.Clip(uri, 120)}' is not a local folder");
        var root = u.LocalPath;
        if (!Directory.Exists(root))
            return (null, $"not requested: agy's workspace '{ReplyCapture.Clip(root, 120)}' does not exist on this machine");
        return (root, null);
    }

    public static (string? Path, string? Nonce, string? Status) Prepare(string root, string cascadeId, int firstStepIndex)
    {
        try
        {
            if (!ReplyCapture.IsSafeName(cascadeId)) return (null, null, "not requested: the cascade id is not safe in a file name");
            var shield = System.IO.Path.Combine(root, ".clavity", ".gitignore");
            if (!File.Exists(shield) || !File.ReadLines(shield).Any(l => l.Trim() == "*"))
                return (null, null, $"not requested: {shield} does not hold a '*' line, so a reply file there could be committed");
            var dir = System.IO.Path.Combine(root, ".clavity", "scratch", "agy-replies");
            Directory.CreateDirectory(dir);
            return (System.IO.Path.Combine(dir, $"{cascadeId}-{firstStepIndex}.md"), Guid.NewGuid().ToString("N"), null);
        }
        catch (Exception ex)
        {
            return (null, null, "not requested: " + ReplyCapture.OneLine(ex));
        }
    }

    /// <summary>The block appended to a discipline ask. A RECORDED EXCEPTION to the T4b "raw ask only" rule: it is
    /// peer-facing completion protocol, never driver guidance. Its LAST line is the nonce line the file must start with.</summary>
    public static string RequestBlock(string path, string nonce) =>
        "\n\n---\n"
        + "REPLY FILE (completion protocol from the clavity driver, not part of the request above): BEFORE you send your "
        + "final chat message, ALSO write your WHOLE reply, verbatim, to this file - create it, or replace it:\n"
        + path + "\n"
        + "Its FIRST line must be exactly the line below, then a blank line, then the reply. This one write is permitted "
        + "even when the request above is review-only. Then send the same reply in chat as usual.\n"
        + NonceLinePrefix + nonce;

    public static (string? Body, string? Status) TryRead(string path, string nonce)
    {
        try
        {
            if (!File.Exists(path)) return (null, "not read: the peer did not write it");
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            if (!stream.CanSeek) return (null, "not read: not a regular file");
            if (stream.Length > MaxBytes)
                return (null, $"not read: {stream.Length} bytes is over the {MaxBytes}-byte cap; the chat verdict stands");
            using var reader = new StreamReader(stream);
            var text = reader.ReadToEnd().Replace("\r\n", "\n");
            var nl = text.IndexOf('\n');
            var first = nl < 0 ? text : text[..nl];
            if (first.Trim() != NonceLinePrefix + nonce) return (null, "not read: its first line does not carry this ask's nonce");
            var body = nl < 0 ? "" : text[(nl + 1)..];
            if (body.StartsWith('\n')) body = body[1..];
            return (body, null);
        }
        catch (Exception ex)
        {
            return (null, "not read: " + ReplyCapture.OneLine(ex));
        }
    }
}
