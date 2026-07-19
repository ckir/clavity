using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class GoldenHeaderTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-gh-" + Guid.NewGuid().ToString("N"));

    public GoldenHeaderTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, recursive: true); } catch { } }

    [Fact]
    public void ResolveDir_uses_env_override_when_set()
        => Assert.Equal(@"D:\x", GoldenHeader.ResolveDir(@"D:\x", @"C:\Users\u"));

    [Fact]
    public void ResolveDir_falls_back_to_userprofile_dot_clavity_when_blank()
        => Assert.Equal(Path.Combine(@"C:\Users\u", ".clavity"), GoldenHeader.ResolveDir("  ", @"C:\Users\u"));

    [Fact]
    public void TryReadCombined_returns_null_when_dir_empty()
        => Assert.Null(GoldenHeader.TryReadCombined(_dir));

    [Fact]
    public void TryReadCombined_returns_seed_alone_when_only_seed_present()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
        Assert.Equal("SEED", GoldenHeader.TryReadCombined(_dir));
    }

    // Parity block — mirrors clavity-classic golden_header.rs `read_combined_*` comment tests exactly.
    // The shipped seed/golden-header.md opens with a maintainer note that must never reach the peer.

    [Fact]
    public void TryReadCombined_strips_the_seeded_maintainer_comment()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName),
            "<!-- Compiled SEED baseline for the golden-header.\n     Keep dense. -->\n\nSEED");
        Assert.Equal("SEED", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_treats_a_comment_only_region_as_absent()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "<!-- nothing but a note -->\n");
        Assert.Null(GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_leaves_an_unterminated_comment_intact()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "<!-- oops no close\nSEED");
        Assert.Equal("<!-- oops no close\nSEED", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_leaves_a_bare_short_opener_intact()
    {
        // `<!-->` has no terminator AFTER the 4-char opener; both variants must leave it alone.
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "<!-->SEED");
        Assert.Equal("<!-->SEED", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_returns_growth_alone_when_only_growth_present()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), "GROWTH");
        Assert.Equal("GROWTH", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_concatenates_seed_then_growth_blank_line_separated()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED\n");
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), "GROWTH\n");
        Assert.Equal("SEED\n\nGROWTH", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_falls_back_to_legacy_flat_file_as_growth()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "LEGACY");
        Assert.Equal("LEGACY", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_injects_legacy_ALONE_not_concatenated_with_seed()
    {
        // Upgrade case (panels A1 + R2-agy-1): installer seeded SEED, user's legacy flat file already contains the
        // OLD baseline + their wisdom, no growth.md yet. Inject legacy alone — concatenating with the new SEED
        // would inject the baseline twice.
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "OLD-BASELINE\n\nLEARNED");
        Assert.Equal("OLD-BASELINE\n\nLEARNED", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_ignores_legacy_once_growth_file_present()
    {
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), "GROWTH");
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "LEGACY");
        Assert.Equal("SEED\n\nGROWTH", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_prefers_seed_over_legacy_when_growth_file_exists_but_is_empty()
    {
        // SHOULD-FIX (final review): once a growth.md FILE exists the migration is done, even if that file is
        // transiently empty. Must NOT revert to the stale legacy flat file (left on disk forever) — the fresh
        // SEED baseline wins.
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), "");   // present but empty
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.LegacyFileName), "STALE-LEGACY");
        Assert.Equal("SEED", GoldenHeader.TryReadCombined(_dir));
    }

    [Fact]
    public void TryReadCombined_drops_growth_but_keeps_seed_when_combined_over_cap()
    {
        // Each region is under the per-file cap, but their sum is over it. Degrade to SEED, do NOT drop everything.
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.SeedFileName), "SEED");
        File.WriteAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName), new string('a', GoldenHeader.MaxBytes));
        string? warned = null;
        Assert.Equal("SEED", GoldenHeader.TryReadCombined(_dir, w => warned = w));
        Assert.NotNull(warned);   // the drop-GROWTH warning fired
    }

    [Fact]
    public void Apply_prepends_with_blank_line_when_header_present()
        => Assert.Equal("HDR\n\nmsg", GoldenHeader.Apply("HDR\n", "msg"));

    [Fact]
    public void Apply_returns_message_unchanged_when_header_null_or_empty()
    {
        Assert.Equal("msg", GoldenHeader.Apply(null, "msg"));
        Assert.Equal("msg", GoldenHeader.Apply("", "msg"));
    }

    [Fact]
    public void Commit_writes_content_atomically_and_is_readable_back()
    {
        var p = Path.Combine(_dir, "sub", "golden-header.md");
        GoldenHeader.Commit(p, "compiled wisdom");
        Assert.Equal("compiled wisdom", File.ReadAllText(p));
    }

    [Fact]
    public void Commit_writes_sha256_sidecar_matching_content()
    {
        var p = Path.Combine(_dir, "golden-header.md");
        GoldenHeader.Commit(p, "compiled wisdom");
        Assert.True(File.Exists(p + ".sha256"));
        Assert.Equal(GoldenHeader.Sha256Hex("compiled wisdom"), File.ReadAllText(p + ".sha256"));
    }

    [Fact]
    public void Commit_throws_when_content_exceeds_cap()
    {
        var p = Path.Combine(_dir, "h.md");
        Assert.Throws<InvalidOperationException>(() => GoldenHeader.Commit(p, new string('x', GoldenHeader.MaxBytes + 1)));
    }

    [Fact]
    public void CommitGrowth_writes_growth_file_only_and_leaves_seed_untouched()
    {
        GoldenHeader.CommitSeed(_dir, "SEED");
        GoldenHeader.CommitGrowth(_dir, "GROWTH");
        Assert.Equal("SEED", File.ReadAllText(Path.Combine(_dir, GoldenHeader.SeedFileName)));
        Assert.Equal("GROWTH", File.ReadAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
    }

    [Fact]
    public void CommitSeed_writes_seed_file_only_and_leaves_growth_untouched()
    {
        GoldenHeader.CommitGrowth(_dir, "GROWTH");
        GoldenHeader.CommitSeed(_dir, "SEED");
        Assert.Equal("GROWTH", File.ReadAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
        Assert.Equal("SEED", File.ReadAllText(Path.Combine(_dir, GoldenHeader.SeedFileName)));
    }

    [Fact]
    public void CommitSeed_writes_per_file_sidecar()
    {
        GoldenHeader.CommitSeed(_dir, "SEED");
        var sidecar = Path.Combine(_dir, GoldenHeader.SeedFileName) + ".sha256";
        Assert.True(File.Exists(sidecar));
        Assert.Equal(GoldenHeader.Sha256Hex("SEED"), File.ReadAllText(sidecar));
    }
}
