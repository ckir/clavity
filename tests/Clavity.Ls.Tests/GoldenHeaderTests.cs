using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class GoldenHeaderTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-gh-" + Guid.NewGuid().ToString("N"));

    public GoldenHeaderTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, recursive: true); } catch { } }

    [Fact]
    public void ResolvePath_uses_env_override_when_set()
    {
        Assert.Equal(@"C:\custom\h.md", GoldenHeader.ResolvePath(@"C:\custom\h.md", @"C:\Users\u"));
    }

    [Fact]
    public void ResolvePath_falls_back_to_userprofile_dot_clavity_when_env_blank()
    {
        Assert.Equal(
            Path.Combine(@"C:\Users\u", ".clavity", "golden-header.md"),
            GoldenHeader.ResolvePath("   ", @"C:\Users\u"));
    }

    [Fact]
    public void TryRead_returns_null_when_absent()
        => Assert.Null(GoldenHeader.TryRead(Path.Combine(_dir, "nope.md")));

    [Fact]
    public void TryRead_returns_null_when_empty_or_whitespace()
    {
        var p = Path.Combine(_dir, "h.md");
        File.WriteAllText(p, "   \n  ");
        Assert.Null(GoldenHeader.TryRead(p));
    }

    [Fact]
    public void TryRead_returns_content_when_present()
    {
        var p = Path.Combine(_dir, "h.md");
        File.WriteAllText(p, "RULE: be precise");
        Assert.Equal("RULE: be precise", GoldenHeader.TryRead(p));
    }

    [Fact]
    public void TryRead_returns_null_when_over_cap()
    {
        var p = Path.Combine(_dir, "h.md");
        File.WriteAllText(p, new string('x', GoldenHeader.MaxBytes + 1));
        Assert.Null(GoldenHeader.TryRead(p));
    }

    [Fact]
    public void TryRead_warns_on_over_cap_but_is_silent_when_absent()
    {
        var p = Path.Combine(_dir, "big.md");
        File.WriteAllText(p, new string('x', GoldenHeader.MaxBytes + 1));
        var warnings = new List<string>();
        Assert.Null(GoldenHeader.TryRead(p, warnings.Add));
        Assert.Single(warnings);
        Assert.Contains("cap", warnings[0], StringComparison.OrdinalIgnoreCase);

        warnings.Clear();
        Assert.Null(GoldenHeader.TryRead(Path.Combine(_dir, "absent.md"), warnings.Add));
        Assert.Empty(warnings);
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
        Assert.Equal("compiled wisdom", GoldenHeader.TryRead(p));
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
}
