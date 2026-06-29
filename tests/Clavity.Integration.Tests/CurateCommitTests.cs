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
}
