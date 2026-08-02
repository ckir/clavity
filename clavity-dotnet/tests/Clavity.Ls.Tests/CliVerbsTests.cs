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
    public void CurateCommit_refuses_a_sequence_truncated_at_end_of_stream()
    {
        // "abc" followed by the first TWO bytes of a three-byte em dash (E2 80 94) — exactly what a pipe
        // that dies mid-character delivers. The dangling bytes are only detectable when the decoder is
        // FLUSHED at EOF; a decoder that is never flushed drops them and commits a silently truncated
        // header, which is the same class of undetectable corruption this verb exists to prevent (the
        // .sha256 sidecar would happily vouch for the truncated bytes). StreamReader does flush at EOF —
        // measured, not assumed — so this pins behaviour that is real but entirely non-obvious, and that a
        // refactor to a hand-rolled decode loop would silently lose.
        var error = new StringWriter();

        Assert.Equal(2, CliVerbs.CurateCommit(_dir, new MemoryStream([0x61, 0x62, 0x63, 0xE2, 0x80]), error));
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
        // This pins NON-DISPOSAL only. It deliberately does not assert the stream's position: the reader
        // buffers ahead, so the cursor on return is past what was decoded. "Still disposable by its owner"
        // is the contract; "still readable from where the verb stopped" is not.
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

    // The 13-day corruption: a text pipe re-encoded the payload through the console code page before
    // curate-commit ever saw it, so the bytes arrived already wrong - and arrived as VALID UTF-8
    // (the CP437 round-trip of an em-dash is the well-formed sequence U+0393 U+00C7 U+00F6). The .sha256
    // sidecar therefore MATCHED, confirming corrupt content. An integrity sidecar catches torn writes; it
    // cannot catch content that was wrong on arrival.
    private const string Cp437MangledEmDash = "\u0393\u00C7\u00F6";
    private const string Cp1252MangledPrefix = "\u00E2\u20AC";

    [Fact]
    public void CurateCommit_refuses_a_payload_carrying_the_CP437_mojibake_signature()
    {
        var error = new StringWriter();
        var payload = $"[ANTI-PATTERNS]\n- a rule {Cp437MangledEmDash} with a mangled dash\n";
        Assert.NotEqual(0, CliVerbs.CurateCommit(_dir, Utf8(payload), error));
        Assert.Contains("mojibake", error.ToString(), StringComparison.OrdinalIgnoreCase);
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
    }

    [Fact]
    public void CurateCommit_refuses_a_payload_carrying_the_CP1252_mojibake_signature()
    {
        var error = new StringWriter();
        var payload = $"[ANTI-PATTERNS]\n- a rule {Cp1252MangledPrefix}\u201D with a mangled quote\n";
        Assert.NotEqual(0, CliVerbs.CurateCommit(_dir, Utf8(payload), error));
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
    }

    [Fact]
    public void CurateCommit_still_accepts_legitimate_non_ascii()
    {
        // Guards the tripwire against becoming a blanket ASCII rule. curate-commit is a FAITHFUL BYTE
        // TRANSPORT by contract - that property is exactly why the raw-byte publish path is worth
        // mandating over a text pipe. A blanket rule would break it and force the two round-trip tests
        // above to be inverted, which is not a change this milestone is permitted to make.
        var error = new StringWriter();
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8(NonAsciiSample), error));
        Assert.Equal(Encoding.UTF8.GetBytes(NonAsciiSample), File.ReadAllBytes(GoldenHeader.GrowthPath(_dir)));
    }

    // AT-2: the snapshot ring. The sidecar rotates in the SAME slot as its header - a header restored
    // without its matching sidecar mismatches on read and is silently dropped from every ask, so a
    // header-only backup is an unrestorable backup.
    private static string[] Baks(string dir) =>
        Directory.GetFiles(dir, "golden-header.growth.md.*.bak");

    [Fact]
    public void Commit_snapshots_the_previous_header_and_its_sidecar_together()
    {
        GoldenHeader.CommitGrowth(_dir, "first\n");
        GoldenHeader.CommitGrowth(_dir, "second\n");

        var baks = Baks(_dir);
        Assert.Single(baks);
        Assert.Equal("first\n", File.ReadAllText(baks[0]));
        Assert.True(File.Exists(baks[0] + ".sha256"), "the sidecar must rotate in the same slot");
    }

    [Fact]
    public void Commit_does_not_consume_a_slot_when_content_is_unchanged()
    {
        GoldenHeader.CommitGrowth(_dir, "same\n");
        GoldenHeader.CommitGrowth(_dir, "same\n");
        GoldenHeader.CommitGrowth(_dir, "same\n");
        Assert.Empty(Baks(_dir));
    }

    [Fact]
    public void Commit_prunes_the_ring_to_the_retention_limit()
    {
        // Pre-seed the ring rather than looping CommitGrowth. The snapshot stamp has ONE-SECOND
        // resolution, so a tight loop of commits produces the SAME filename every iteration and
        // File.Copy(overwrite: true) collapses them into one .bak - the assert would read 1, not 5.
        // Seeding fixed 2026-01-01 names and firing a single real commit exercises the prune in
        // milliseconds with no sleeps. Today's stamp sorts above 20260101-* under the Ordinal
        // descending sort the implementation uses, so the newest slot is the real one.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        for (var i = 1; i <= GoldenHeader.SnapshotKeep + 2; i++)
            File.WriteAllText(Path.Combine(_dir, $"golden-header.growth.md.20260101-00000{i}.bak"), $"old {i}\n");

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        Assert.Equal(GoldenHeader.SnapshotKeep, Baks(_dir).Length);
    }

    [Fact]
    public void A_restored_snapshot_slot_round_trips_through_the_read_side()
    {
        GoldenHeader.CommitGrowth(_dir, "original\n");
        GoldenHeader.CommitGrowth(_dir, "replacement\n");

        var bak = Baks(_dir)[0];
        File.Copy(bak, GoldenHeader.GrowthPath(_dir), overwrite: true);
        File.Copy(bak + ".sha256", GoldenHeader.GrowthPath(_dir) + ".sha256", overwrite: true);

        // The whole point: restoring BOTH files leaves the read side satisfied rather than silently
        // dropping the region on a hash mismatch.
        Assert.Contains("original", GoldenHeader.TryReadCombined(_dir) ?? "");
    }
}
