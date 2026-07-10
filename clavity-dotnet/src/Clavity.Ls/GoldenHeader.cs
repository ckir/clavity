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

    /// <summary>One region file's content, or null if absent/empty/over-cap. IO-safe; over-cap warns.</summary>
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
            var text = File.ReadAllText(path);
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
        // it already contains the old baseline + learned rules. Until GROWTH exists, inject the legacy file
        // ALONE; do NOT concatenate it with the new SEED, or the baseline is injected twice. This still
        // preserves the upgrading user's wisdom (A1). agy-curate migrates it to growth.md on its next run and
        // (T9). Once growth.md exists this branch no longer fires; the legacy file is LEFT in place as a
        // harmless fallback (not renamed — that would break the classic failover, panel agy-R3-c).
        if (growth is null)
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

    /// <summary>agy-curate writes ONLY this. Never touches SEED.</summary>
    public static void CommitGrowth(string dir, string content) => Commit(GrowthPath(dir), content);

    /// <summary>Driver install writes ONLY this. Never touches GROWTH.</summary>
    public static void CommitSeed(string dir, string content) => Commit(SeedPath(dir), content);
}
