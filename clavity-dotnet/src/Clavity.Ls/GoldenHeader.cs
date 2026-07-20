using System.Security.Cryptography;
using System.Text;

namespace Clavity.Ls;

/// <summary>
/// The shared, variant-agnostic golden-header (accumulated agy-driving wisdom), split into two independently-
/// owned region files under %USERPROFILE%\.clavity\ (the DIRECTORY is overridable via CLAVITY_GOLDEN_HEADER):
/// golden-header.seed.md (the driver-seeded baseline) + golden-header.growth.md (written by
/// `clavity-ls curate-commit`). Read as SEED-then-GROWTH and prepended to every ask; a pre-split flat
/// golden-header.md is read ALONE as a one-time migration fallback. Reads NO-OP cleanly when the files are
/// absent, empty, or over the size cap — that is what makes the agy-autotrain add-on optional.
/// </summary>
public static class GoldenHeader
{
    public const string PathVar = "CLAVITY_GOLDEN_HEADER";

    /// <summary>Strict byte cap (security §size-cap): over-cap content is refused, not injected.</summary>
    public const int MaxBytes = 16 * 1024;

    public const string SeedFileName = "golden-header.seed.md";
    public const string GrowthFileName = "golden-header.growth.md";
    public const string LegacyFileName = "golden-header.md";

    /// <summary>CLAVITY_GOLDEN_HEADER (a directory) if set+non-blank, else %USERPROFILE%\.clavity.</summary>
    public static string ResolveDir(string? envOverride, string userProfileDir) =>
        string.IsNullOrWhiteSpace(envOverride)
            ? Path.Combine(userProfileDir, ".clavity")
            : envOverride;

    public static string SeedPath(string dir) => Path.Combine(dir, SeedFileName);
    public static string GrowthPath(string dir) => Path.Combine(dir, GrowthFileName);

    /// <summary>
    /// ASCII whitespace, a FIXED set identical cross-variant (space, tab, LF, VT, FF, CR) — mirrors Rust
    /// <c>ASCII_WS</c>. Deliberately not <c>char.IsWhiteSpace</c>, which disagrees with Rust on obscure separators.
    /// </summary>
    private static readonly char[] AsciiWs = { ' ', '\t', '\n', '\v', '\f', '\r' };

    /// <summary>
    /// Strip a single leading UTF-8 BOM (U+FEFF) — mirrors Rust <c>strip_bom</c>
    /// (<c>s.strip_prefix('\u{feff}').unwrap_or(s)</c>): removes at most one leading occurrence, ordinal.
    /// <c>File.ReadAllText</c> used to strip this for us automatically; now that we decode strictly via
    /// <c>Encoding.GetString</c>, which does NOT strip a BOM, this keeps cross-variant parity.
    /// </summary>
    private static string StripBom(string s) =>
        s.StartsWith("\uFEFF", StringComparison.Ordinal) ? s[1..] : s;

    /// <summary>
    /// Strip leading HTML comment blocks (<c>&lt;!-- … --&gt;</c>) plus the whitespace around them. The seeded
    /// golden-header opens with a maintainer-facing note that would otherwise be injected into every ask as if it
    /// were driving guidance. An UNTERMINATED <c>&lt;!--</c> is left alone rather than swallowing the whole file.
    /// Mirrors Rust <c>strip_leading_html_comments</c> exactly: the terminator search starts AFTER the 4-char
    /// opener, so <c>&lt;!--&gt;</c> (no real terminator) is left intact on both variants.
    /// </summary>
    private static string StripLeadingHtmlComments(string s)
    {
        var rest = s.TrimStart(AsciiWs);
        while (rest.StartsWith("<!--", StringComparison.Ordinal))
        {
            var end = rest.IndexOf("-->", 4, StringComparison.Ordinal);
            if (end < 0) break;
            rest = rest[(end + 3)..].TrimStart(AsciiWs);
        }
        return rest;
    }

    /// <summary>
    /// One region file's content, or null if absent/empty/over-cap/invalid-UTF-8/sidecar-mismatched.
    /// IO-safe; over-cap and sidecar-mismatch both warn and degrade the region to absent.
    /// </summary>
    private static string? TryReadFile(string path, Action<string>? warn = null)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var len = new FileInfo(path).Length;
            if (len == 0) return null;
            if (len > MaxBytes)
            {
                warn?.Invoke($"golden-header region at {path} is {len}B, over the {MaxBytes}B cap — skipped");
                return null;
            }
            var bytes = File.ReadAllBytes(path);

            // Sidecar INTEGRITY check — NOT a security control: anyone able to rewrite the header file
            // can equally rewrite or delete the sidecar. It exists to catch torn writes, filesystem
            // corruption, and a hand-edited header that no longer matches what the tool committed
            // (mirrors Rust's read-side check in try_read_file). Hash the RAW bytes exactly as read from
            // disk — BEFORE the BOM/comment strip below — since Commit hashed the raw bytes it wrote.
            // Sidecar absent = ACCEPT unchanged: the installer's SeedGoldenHeader copies the seed file
            // but writes no sidecar, so every fresh install legitimately has a sidecar-less SEED
            // (installer/_shared/golden-header-data.iss). Sidecar unreadable = treat exactly as absent,
            // accept. Sidecar present but mismatched = warn and degrade this region to ABSENT, mirroring
            // the over-cap path above.
            var sidecarPath = path + ".sha256";
            try
            {
                if (File.Exists(sidecarPath))
                {
                    var expected = File.ReadAllText(sidecarPath).Trim(AsciiWs).ToLowerInvariant();
                    var actual = Sha256Hex(bytes);
                    if (expected != actual)
                    {
                        warn?.Invoke($"golden-header region at {path} did not match its .sha256 sidecar — skipped");
                        return null;
                    }
                }
            }
            catch (IOException) { /* sidecar unreadable: treat exactly as absent, accept */ }
            catch (UnauthorizedAccessException) { /* sidecar unreadable: treat exactly as absent, accept */ }

            string text;
            try
            {
                // Strict UTF-8, mirroring Rust's String::from_utf8(bytes).ok()? — invalid bytes mean the region is
                // ABSENT. File.ReadAllText would silently substitute U+FFFD and inject the garbled text instead.
                text = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true)
                    .GetString(bytes);
            }
            catch (DecoderFallbackException) { return null; }
            text = StripBom(text);
            text = StripLeadingHtmlComments(text);
            return string.IsNullOrWhiteSpace(text) ? null : text;
        }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    /// <summary>
    /// Combined SEED-then-GROWTH content to inject, or null when nothing usable. Legacy fallback: if BOTH split
    /// files are absent but a flat golden-header.md exists, treat it as GROWTH (one-directional migration). The
    /// 16 KB cap applies to the COMBINED result.
    /// </summary>
    public static string? TryReadCombined(string dir, Action<string>? warn = null)
    {
        var seed = TryReadFile(SeedPath(dir), warn);
        var growth = TryReadFile(GrowthPath(dir), warn);

        // Migration window (panels A1 + R2-agy-1): a pre-split flat golden-header.md is a COMPLETE header —
        // it already contains the old baseline + learned rules. While NO growth file exists yet, inject the
        // legacy file ALONE; do NOT concatenate it with the new SEED, or the baseline is injected twice. This
        // preserves the upgrading user's wisdom (A1) until agy-curate folds it into growth.md on its next run
        // (T9 migration step). Gate on the growth FILE's absence, not merely a null read: once a growth.md
        // exists (even transiently empty/over-cap/unreadable) the migration is done, so prefer the fresh SEED
        // over reverting to the stale legacy content. The legacy file is LEFT in place as a harmless fallback
        // (not renamed — that would break the classic failover, panel agy-R3-c).
        if (growth is null && !File.Exists(GrowthPath(dir)))
        {
            var legacy = TryReadFile(Path.Combine(dir, LegacyFileName), warn);
            if (legacy is not null)
                return WithinCap(legacy, dir, warn) ? legacy : null;
        }

        var combined = Join(seed, growth);
        if (combined is null) return null;
        if (WithinCap(combined, dir, warn)) return combined;

        // Combined over cap: degrade gracefully (panel F2) — keep the driver's SEED baseline and drop GROWTH,
        // rather than silently losing the whole header as GROWTH accretes.
        warn?.Invoke($"combined golden-header at {dir} exceeds the {MaxBytes}B cap — dropping GROWTH, keeping SEED");
        return (seed is not null && Encoding.UTF8.GetByteCount(seed) <= MaxBytes) ? seed : null;
    }

    private static bool WithinCap(string s, string dir, Action<string>? warn)
    {
        if (Encoding.UTF8.GetByteCount(s) <= MaxBytes) return true;
        warn?.Invoke($"golden-header at {dir} exceeds the {MaxBytes}B cap — injection skipped");
        return false;
    }

    private static string? Join(string? seed, string? growth)
    {
        if (seed is null) return growth;
        if (growth is null) return seed;
        return seed.TrimEnd() + "\n\n" + growth.Trim();
    }

    /// <summary>Prepend the header (blank-line separated) when present; otherwise return the message unchanged.</summary>
    public static string Apply(string? header, string message) =>
        string.IsNullOrEmpty(header) ? message : header.TrimEnd() + "\n\n" + message;

    /// <summary>
    /// Atomic write of curated content to the resolved path (+ a .sha256 sidecar for INTEGRITY checking —
    /// NOT a security control: anyone able to rewrite the header file can equally rewrite or delete the
    /// sidecar. It exists to catch torn writes, filesystem corruption, and a hand-edited header that no
    /// longer matches what the tool committed; see <see cref="TryReadFile"/> for the read-side check).
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

    /// <summary>
    /// Lowercase-hex SHA-256 of the exact RAW bytes (no string round-trip, which would corrupt
    /// non-UTF8 input). Used by the read-side sidecar verification in <see cref="TryReadFile"/>.
    /// </summary>
    public static string Sha256Hex(byte[] bytes) =>
        Convert.ToHexStringLower(SHA256.HashData(bytes));

    /// <summary>agy-curate writes ONLY this. Never touches SEED.</summary>
    public static void CommitGrowth(string dir, string content) => Commit(GrowthPath(dir), content);

    /// <summary>Driver install writes ONLY this. Never touches GROWTH.</summary>
    public static void CommitSeed(string dir, string content) => Commit(SeedPath(dir), content);
}
