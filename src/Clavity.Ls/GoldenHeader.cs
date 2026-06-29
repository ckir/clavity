using System.Security.Cryptography;
using System.Text;

namespace Clavity.Ls;

/// <summary>
/// The shared, variant-agnostic golden-header (accumulated agy-driving wisdom). Read+prepended to every ask by
/// the binary, written only by `clavity-ls curate-commit`. Path = %USERPROFILE%\.clavity\golden-header.md,
/// overridable via CLAVITY_GOLDEN_HEADER. Reads NO-OP cleanly when the file is absent, empty, or over the size
/// cap — that is what makes the agy-autotrain add-on optional.
/// </summary>
public static class GoldenHeader
{
    public const string PathVar = "CLAVITY_GOLDEN_HEADER";

    /// <summary>Strict byte cap (security §size-cap): over-cap content is refused, not injected.</summary>
    public const int MaxBytes = 16 * 1024;

    /// <summary>CLAVITY_GOLDEN_HEADER if set+non-blank, else %USERPROFILE%\.clavity\golden-header.md.</summary>
    public static string ResolvePath(string? envOverride, string userProfileDir) =>
        string.IsNullOrWhiteSpace(envOverride)
            ? Path.Combine(userProfileDir, ".clavity", "golden-header.md")
            : envOverride;

    /// <summary>
    /// Content to inject, or null when absent / empty / over-cap. Never throws on IO.
    /// F13: absent/empty is a SILENT null (add-on simply not installed); over-cap returns null AND emits a
    /// visible warning via <paramref name="warn"/> so a user whose oversized hand-edit deactivated injection
    /// is told why. NOTE: this does NOT validate the .sha256 sidecar — active tamper-detection (warn/refuse on a
    /// sidecar mismatch) is the explicitly DEFERRED follow-on (packaging Task 7.4); today the sidecar is written
    /// but not read.
    /// </summary>
    public static string? TryRead(string path, Action<string>? warn = null)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var len = new FileInfo(path).Length;
            if (len == 0) return null;
            if (len > MaxBytes)
            {
                warn?.Invoke($"golden-header at {path} is {len}B, over the {MaxBytes}B cap — injection skipped");
                return null;
            }
            var text = File.ReadAllText(path);
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// <summary>Prepend the header (blank-line separated) when present; otherwise return the message unchanged.</summary>
    public static string Apply(string? header, string message) =>
        string.IsNullOrEmpty(header) ? message : header.TrimEnd() + "\n\n" + message;

    /// <summary>
    /// Atomic write of curated content to the resolved path (+ a .sha256 sidecar for tamper detection).
    /// Enforces the size cap. Used by `clavity-ls curate-commit`; agy-curate INVOKES it (never raw-edits).
    /// F7: the .sha256 sidecar is written BEFORE the header is moved into place, so a crash mid-commit cannot
    /// leave a sidecar that falsely accuses an already-published header (Task 7.4 treats mismatch conservatively).
    /// </summary>
    public static void Commit(string path, string content)
    {
        var bytes = Encoding.UTF8.GetByteCount(content);
        if (bytes > MaxBytes)
            throw new InvalidOperationException($"golden-header content {bytes}B exceeds {MaxBytes}B cap");

        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

        var tmp = path + ".tmp";
        File.WriteAllText(tmp, content);
        File.WriteAllText(path + ".sha256", Sha256Hex(content));   // F7: sidecar BEFORE the move
        File.Move(tmp, path, overwrite: true);
    }

    public static string Sha256Hex(string content) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(content)));
}
