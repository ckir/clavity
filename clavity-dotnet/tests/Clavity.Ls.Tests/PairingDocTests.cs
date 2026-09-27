using Clavity.Ls;

namespace Clavity.Ls.Tests;

public sealed class PairingDocTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-pairingdoc-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_dir))
            Directory.Delete(_dir, recursive: true);
    }

    // The source of truth is clavity-dotnet/pairing/agy-pairing-INSTALL.md, linked into the test output by the
    // csproj. The embedded copy must be byte-identical to it - a stale or empty resource would hand agy the
    // wrong instructions, and nothing downstream would notice.
    private static byte[] SourceDoc() => File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, PairingDoc.FileName));

    [Fact]
    public void Embedded_doc_is_byte_identical_to_the_source_doc()
    {
        var source = SourceDoc();
        Assert.NotEmpty(source);
        Assert.Equal(source, PairingDoc.ReadEmbedded());
    }

    [Fact]
    public void Materialize_creates_the_directory_and_writes_the_doc()
    {
        Assert.False(Directory.Exists(_dir));

        var path = PairingDoc.Materialize(_dir);

        Assert.Equal(Path.Combine(_dir, PairingDoc.FileName), path);
        Assert.Equal(SourceDoc(), File.ReadAllBytes(path));
    }

    [Fact]
    public void Materialize_replaces_a_stale_doc_left_by_an_older_version()
    {
        Directory.CreateDirectory(_dir);
        var path = Path.Combine(_dir, PairingDoc.FileName);
        File.WriteAllText(path, "stale instructions from an older clavity-ls");

        Assert.Equal(path, PairingDoc.Materialize(_dir));
        Assert.Equal(SourceDoc(), File.ReadAllBytes(path));
    }

    [Fact]
    public void Materialize_is_idempotent_and_leaves_no_temp_files()
    {
        var first = PairingDoc.Materialize(_dir);
        var second = PairingDoc.Materialize(_dir);

        Assert.Equal(first, second);
        Assert.Equal(SourceDoc(), File.ReadAllBytes(second));
        Assert.Equal(new[] { PairingDoc.FileName }, Directory.GetFiles(_dir).Select(Path.GetFileName));
    }
}
