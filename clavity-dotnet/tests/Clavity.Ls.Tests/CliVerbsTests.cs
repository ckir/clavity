using System.Text;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

/// <summary>
/// Pins `curate-commit`, whose load-bearing behaviour is its DECODER. Reading the compiled header through the
/// console's OEM code page (CP437) instead of UTF-8 silently corrupted the GROWTH region in production — em
/// dash stored as "Γ Ç ö", "⚠️" as "ΓÜá∩╕Å". Nothing downstream can catch that (mojibake is valid UTF-8, so
/// the .sha256 sidecar and the strict read-side decode both accept it), so it has to be caught here.
/// <para>
/// These tests are only meaningful because <see cref="CliVerbs.CurateCommit"/> takes a raw <see cref="Stream"/>
/// and decodes internally. An earlier iteration exposed the reader as a parameter and tested THAT — which was
/// worthless: the defect lived in the call site's choice of reader, so reverting the fix left every test green.
/// Assert on BYTES, not strings, for the same reason — the bug produced a perfectly valid string.
/// </para>
/// </summary>
public sealed class CliVerbsTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-cliverbs-" + Guid.NewGuid().ToString("N"));
    public CliVerbsTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { /* best effort */ } }

    /// <summary>The exact characters the CP437 mis-decode destroyed, plus an emoji with a variation selector.</summary>
    private const string NonAsciiSample = "[⚠️ ANTI-PATTERNS — newly learned]\n- process-alive ≠ endpoint-reachable.\n";

    private static MemoryStream Utf8(string content) => new(Encoding.UTF8.GetBytes(content));

    [Fact]
    public void CurateCommit_round_trips_non_ascii_content_byte_identically()
    {
        var error = new StringWriter();

        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8(NonAsciiSample), error));

        // THE regression test: a CP437 (or any non-UTF-8) decoder inside CurateCommit fails this on bytes
        // while still producing a valid-looking string.
        Assert.Equal(Encoding.UTF8.GetBytes(NonAsciiSample), File.ReadAllBytes(GoldenHeader.GrowthPath(_dir)));
        Assert.Equal("", error.ToString());
    }

    [Fact]
    public void CurateCommit_written_growth_survives_the_strict_read_side_decode()
    {
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8(NonAsciiSample), new StringWriter()));

        // End-to-end: what curate-commit writes must be readable back by the injection path, sidecar
        // verification included (Commit writes the .sha256; TryReadCombined verifies it).
        var combined = GoldenHeader.TryReadCombined(_dir);
        Assert.NotNull(combined);
        Assert.Contains("⚠️", combined);
        Assert.Contains("—", combined);
        Assert.DoesNotContain("Γ", combined);   // the mojibake signature
    }

    [Fact]
    public void CurateCommit_refuses_input_that_is_not_utf8_and_writes_nothing()
    {
        // 0x93/0x94 are CP1252 smart quotes — invalid as UTF-8. The old OEM decoder accepted bytes like these
        // and wrote plausible-looking mojibake; strict decoding must refuse instead.
        var error = new StringWriter();

        Assert.Equal(2, CliVerbs.CurateCommit(_dir, new MemoryStream([0x41, 0x93, 0x94, 0x42]), error));
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
        Assert.Contains("not valid UTF-8", error.ToString());
    }

    [Fact]
    public void CurateCommit_does_not_switch_codec_on_a_utf16_bom()
    {
        // BOM detection is off deliberately: a UTF-16 BOM must NOT re-codec the stream, mirroring the sidecar
        // read path in GoldenHeader, which rejects a UTF-16LE sidecar rather than decoding it. With detection
        // ON this input would decode cleanly to "hi" and be committed — so this test discriminates.
        var utf16 = new byte[] { 0xFF, 0xFE }.Concat(Encoding.Unicode.GetBytes("hi")).ToArray();

        Assert.Equal(2, CliVerbs.CurateCommit(_dir, new MemoryStream(utf16), new StringWriter()));
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
    }

    [Fact]
    public void CurateCommit_leaves_the_callers_stream_open()
    {
        // leaveOpen: true — Program.cs owns the standard input stream and disposes it via its own `using`.
        // A StreamReader that disposed the caller's stream would be a silent ownership violation.
        var stream = Utf8("growth\n");

        Assert.Equal(0, CliVerbs.CurateCommit(_dir, stream, new StringWriter()));

        Assert.True(stream.CanRead);
        stream.Dispose();
    }

    [Fact]
    public void CurateCommit_refuses_over_cap_input_and_writes_nothing()
    {
        var error = new StringWriter();

        Assert.Equal(2, CliVerbs.CurateCommit(_dir, Utf8(new string('x', GoldenHeader.MaxBytes + 1)), error));
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
        Assert.Contains("cap", error.ToString());
    }

    [Fact]
    public void CurateCommit_refuses_multibyte_content_over_the_BYTE_cap_and_writes_nothing()
    {
        // The char-cap alone lets this through — every "—" is 1 char but 3 UTF-8 bytes — so the byte-count
        // check at commit time is what refuses it. Distinct from the char-cap case above.
        var error = new StringWriter();
        var content = new string('—', (GoldenHeader.MaxBytes / 3) + 1);

        Assert.Equal(2, CliVerbs.CurateCommit(_dir, Utf8(content), error));
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
        Assert.Contains("cap", error.ToString());
    }

    [Fact]
    public void CurateCommit_never_touches_the_seed_region()
    {
        var seed = GoldenHeader.SeedPath(_dir);
        File.WriteAllText(seed, "SEED baseline\n");
        var before = File.ReadAllBytes(seed);

        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("growth content\n"), new StringWriter()));

        Assert.Equal(before, File.ReadAllBytes(seed));
    }
}
