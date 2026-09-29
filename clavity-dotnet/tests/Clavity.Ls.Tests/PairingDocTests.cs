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

    // Two releases' docs can have the same length, so the skip must compare BYTES: a stale doc of exactly the
    // current length must still be replaced.
    [Fact]
    public void Materialize_replaces_a_stale_doc_of_the_same_length()
    {
        Directory.CreateDirectory(_dir);
        var path = Path.Combine(_dir, PairingDoc.FileName);
        var stale = new byte[SourceDoc().Length];
        Array.Fill(stale, (byte)'x');
        File.WriteAllBytes(path, stale);

        PairingDoc.Materialize(_dir);

        Assert.Equal(SourceDoc(), File.ReadAllBytes(path));
    }

    // When the final move fails, the temp file must not be left behind in ~/.clavity, and the failure must reach
    // the caller as one of the exceptions `start` turns into a refusal. A directory squatting on the doc's name
    // makes the move fail deterministically on every platform.
    [Fact]
    public void Materialize_leaves_no_temp_file_when_the_move_fails()
    {
        Directory.CreateDirectory(Path.Combine(_dir, PairingDoc.FileName));

        var ex = Record.Exception(() => PairingDoc.Materialize(_dir));

        Assert.True(ex is IOException or UnauthorizedAccessException, $"unexpected {ex?.GetType().Name ?? "no exception"}");
        Assert.Empty(Directory.GetFiles(_dir));
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

    // Replacing a file that another process has open fails on Windows (measured: File.Move onto an open file is
    // "Access to the path is denied" under every share mode), and start then refuses to launch. Skipping the
    // write when the bytes already match keeps that risk to the one start after an upgrade, so pin the skip by
    // its effect: an unchanged doc is not rewritten.
    [Fact]
    public void Materialize_does_not_rewrite_a_doc_that_already_matches()
    {
        var path = PairingDoc.Materialize(_dir);
        var marker = new DateTime(2000, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        File.SetLastWriteTimeUtc(path, marker);

        PairingDoc.Materialize(_dir);

        Assert.Equal(marker, File.GetLastWriteTimeUtc(path));
    }
}
