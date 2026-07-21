using System.Text;
using Clavity.Ls;

namespace Clavity.Integration.Tests;

public sealed class CurateCommitTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-cc-" + Guid.NewGuid().ToString("N"));
    public CurateCommitTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, recursive: true); } catch { } }

    /// <summary>
    /// These previously passed a <c>StringReader</c>, which hands the verb already-decoded chars and so skips
    /// the decoding step entirely — which is exactly why this suite stayed green while `curate-commit` was
    /// corrupting every non-ASCII character it was given. They now feed real UTF-8 BYTES. Byte-level coverage
    /// of the decoder itself lives in Clavity.Ls.Tests/CliVerbsTests.cs.
    /// </summary>
    private static MemoryStream Utf8(string content) => new(Encoding.UTF8.GetBytes(content));

    [Fact]
    public void CurateCommit_writes_growth_file_from_stdin_leaving_seed_absent()
    {
        var rc = CliVerbs.CurateCommit(_dir, Utf8("GROWTH RULES"), TextWriter.Null);
        Assert.Equal(0, rc);
        Assert.Equal("GROWTH RULES", File.ReadAllText(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
        Assert.False(File.Exists(Path.Combine(_dir, GoldenHeader.SeedFileName)));
        Assert.True(File.Exists(Path.Combine(_dir, GoldenHeader.GrowthFileName) + ".sha256"));
    }

    [Fact]
    public void CurateCommit_refuses_over_cap_input_without_writing()
    {
        var err = new StringWriter();
        var rc = CliVerbs.CurateCommit(_dir, Utf8(new string('x', GoldenHeader.MaxBytes + 1)), err);
        Assert.NotEqual(0, rc);
        Assert.False(File.Exists(Path.Combine(_dir, GoldenHeader.GrowthFileName)));
        Assert.Contains("cap", err.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void CurateCommit_returns_nonzero_and_reports_cleanly_when_the_write_dir_is_unusable()
    {
        // Pass a DIR that is actually a FILE, so GoldenHeader.Commit's Directory.CreateDirectory throws IOException —
        // the verb must report it cleanly (no uncaught stack trace) and return non-zero.
        var blocker = Path.Combine(_dir, "blocker");
        File.WriteAllText(blocker, "i am a file, not a directory");
        var err = new StringWriter();
        var rc = CliVerbs.CurateCommit(blocker, Utf8("rules"), err);
        Assert.NotEqual(0, rc);
        Assert.Contains("curate-commit", err.ToString());
    }
}
