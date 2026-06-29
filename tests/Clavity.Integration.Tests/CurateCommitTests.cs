using Clavity.Ls;

namespace Clavity.Integration.Tests;

public sealed class CurateCommitTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-cc-" + Guid.NewGuid().ToString("N"));
    public CurateCommitTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, recursive: true); } catch { } }

    [Fact]
    public void CurateCommit_writes_resolved_path_from_stdin()
    {
        var path = Path.Combine(_dir, "golden-header.md");
        var rc = CliVerbs.CurateCommit(path, new StringReader("compiled rules"), TextWriter.Null);
        Assert.Equal(0, rc);
        Assert.Equal("compiled rules", GoldenHeader.TryRead(path));
        Assert.True(File.Exists(path + ".sha256"));
    }

    [Fact]
    public void CurateCommit_refuses_over_cap_input_without_writing()
    {
        var path = Path.Combine(_dir, "golden-header.md");
        var err = new StringWriter();
        var rc = CliVerbs.CurateCommit(path, new StringReader(new string('x', GoldenHeader.MaxBytes + 1)), err);
        Assert.NotEqual(0, rc);
        Assert.False(File.Exists(path));
        Assert.Contains("cap", err.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void CurateCommit_returns_nonzero_and_reports_cleanly_when_the_write_path_is_unusable()
    {
        // Parent is a FILE, so GoldenHeader.Commit's Directory.CreateDirectory throws IOException — the verb must
        // report it cleanly (no uncaught stack trace) and return non-zero (agy review req-djlih4srlzr0).
        var blocker = Path.Combine(_dir, "blocker");
        File.WriteAllText(blocker, "i am a file, not a directory");
        var unwritable = Path.Combine(blocker, "golden-header.md");
        var err = new StringWriter();

        var rc = CliVerbs.CurateCommit(unwritable, new StringReader("rules"), err);

        Assert.NotEqual(0, rc);
        Assert.Contains("curate-commit", err.ToString());
    }
}
