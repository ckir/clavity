// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Globalization;
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

    [Theory]
    [InlineData("")]
    [InlineData("  \n\t\n")]
    public void CurateCommit_refuses_empty_or_blank_input_and_leaves_the_existing_growth_untouched(string blank)
    {
        // Backlog curate-commit-accepts-empty-stdin: `curate-commit < /dev/null` truncated the live GROWTH
        // region from 11039 bytes to 0 and exited 0. Documented contract: 2 = bad input.
        var seeded = Encoding.UTF8.GetBytes("PRE-EXISTING GROWTH THAT MUST NOT VANISH\n");
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, new MemoryStream(seeded), new StringWriter()));
        var before = Directory.GetFiles(_dir).OrderBy(x => x).ToArray();

        var error = new StringWriter();
        Assert.Equal(2, CliVerbs.CurateCommit(_dir, Utf8(blank), error));

        Assert.Contains("nothing written", error.ToString());
        Assert.Equal(seeded, File.ReadAllBytes(GoldenHeader.GrowthPath(_dir)));
        Assert.Equal(before, Directory.GetFiles(_dir).OrderBy(x => x).ToArray()); // no new .bak either
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
        // Pre-seed the ring rather than looping CommitGrowth: seeding fixed 2026-01-01 names and firing a
        // single real commit exercises the prune in milliseconds with no sleeps. The real slot's stamp is
        // UTC yyyyMMdd-HHmmss plus a counter (ROADMAP section 99: a hex Stopwatch stamp sorted ABOVE or
        // BELOW the seeded names depending on the machine's uptime, and this test flipped with it), so
        // today's stamp sorts above 20260101-* under the Ordinal descending sort the implementation
        // uses, and the newest slot is the real one.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        for (var i = 1; i <= GoldenHeader.SnapshotKeep + 2; i++)
            File.WriteAllText(Path.Combine(_dir, $"golden-header.growth.md.20260101-00000{i}.bak"), $"old {i}\n");

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        var survivors = Array.ConvertAll(Baks(_dir), f => Path.GetFileName(f));

        Assert.Equal(GoldenHeader.SnapshotKeep, survivors.Length);

        // IDENTITY, not just cardinality - and this test is the reason that rule exists.
        // `Assert.Equal(SnapshotKeep, Baks(_dir).Length)` was for a long time the ONLY assertion here, and
        // a count is invariant under ANY permutation before truncation. MEASURED 2026-08-08: reversing the
        // sort at GoldenHeader.cs:256 to OrderBy - so the prune keeps the OLDEST slots and deletes the
        // NEWEST, including the snapshot this very commit had just written - left the count at exactly
        // SnapshotKeep and this test PASSING (Failed: 0, Passed: 1). It could not tell correct code from
        // inverted code. This is the founding example of PINNING-ASSERTION-STRENGTH (ROADMAP section 11)
        // and it stayed blind until after that discipline shipped.
        //
        // The rows below assert WHICH slots survive. The real slot carries today's stamp, so it is the
        // only survivor not named 20260101-*; the seeded ring is evicted oldest-first.
        Assert.Contains(survivors, f => !f.Contains("20260101-"));
        Assert.Contains(survivors, f => f.Contains($"20260101-00000{GoldenHeader.SnapshotKeep + 2}"));
        Assert.DoesNotContain(survivors, f => f.Contains("20260101-000001"));
        Assert.DoesNotContain(survivors, f => f.Contains("20260101-000002"));
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

    /// <summary>
    /// Seed the ring with <paramref name="count"/> slots whose stamps sort BELOW any real one, each with
    /// its sidecar, so a prune has something old to evict and the sidecars have something to orphan.
    /// </summary>
    private void SeedOldSlots(int count)
    {
        for (var i = 1; i <= count; i++)
        {
            var slot = Path.Combine(_dir, $"golden-header.growth.md.20260101-00000{i}.bak");
            File.WriteAllText(slot, $"old {i}\n");
            File.WriteAllText(slot + ".sha256", GoldenHeader.Sha256Hex($"old {i}\n"));
        }
    }

    [Fact]
    public void Commit_prunes_the_OLDEST_slots_and_keeps_the_newest()
    {
        // Counting survivors cannot catch a reversed sort. With OrderBy instead of OrderByDescending the
        // ring keeps the five OLDEST and deletes the three newest - including the snapshot just written -
        // and the count is still exactly SnapshotKeep, so the count-only assertion stays green while the
        // ring silently discards its most recent slot on every commit. Assert WHICH slots survive.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        SeedOldSlots(GoldenHeader.SnapshotKeep + 2);

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        var surviving = Baks(_dir);
        Assert.Equal(GoldenHeader.SnapshotKeep, surviving.Length);

        // The slot just written holds the superseded live content. It is the newest and must survive.
        Assert.Contains(surviving, f => File.ReadAllText(f) == "base\n");

        // The oldest seeded slots are the ones that go; the newest seeded slot stays.
        Assert.False(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000001.bak")),
            "the oldest slot must be evicted first");
        Assert.True(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000007.bak")),
            "the newest seeded slot must survive");
    }

    [Fact]
    public void Snapshot_slot_names_are_fixed_width_utc_time_then_counter()
    {
        // ROADMAP section 99: the prune orders slots BY NAME, so the stamp must sort as time does. A hex
        // Stopwatch tick count did not (variable width, restarting at every boot); this pins the shape.
        // Capstone round 1 (MG-1): three commits leave two slots, "first" (taken by the second commit)
        // and "second" (by the third). Each carries the FULL UTC stamp, bounded by the clock read
        // around the calls (a date-only check let local time, a 12-hour clock and a frozen counter
        // through), and the later slot sorts above the earlier one by name - within one second only
        // the counter can make that true, and a frozen counter collapses the two into one file.
        var before = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
        GoldenHeader.CommitGrowth(_dir, "first\n");
        GoldenHeader.CommitGrowth(_dir, "second\n");
        GoldenHeader.CommitGrowth(_dir, "third\n");
        var after = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);

        var slots = Baks(_dir);
        Assert.Equal(2, slots.Length);
        var first = Assert.Single(slots, f => File.ReadAllText(f) == "first\n");
        var second = Assert.Single(slots, f => File.ReadAllText(f) == "second\n");
        foreach (var slot in slots)
        {
            var name = Path.GetFileName(slot);
            Assert.Matches(@"^golden-header\.growth\.md\.\d{8}-\d{6}-\d{4}\.bak$", name);
            var stamp = name.Substring("golden-header.growth.md.".Length, 15);
            Assert.True(
                string.CompareOrdinal(before, stamp) <= 0 && string.CompareOrdinal(stamp, after) <= 0,
                $"stamp {stamp} is outside [{before}, {after}]");
        }
        Assert.True(
            string.CompareOrdinal(Path.GetFileName(second), Path.GetFileName(first)) > 0,
            "the later slot must sort above the earlier one");
    }

    [Fact]
    public void Commit_never_evicts_the_slot_it_has_just_written()
    {
        // Capstone round 1 (open question 1): a clock stepped backwards, or slots stamped ahead of
        // it, sorts the new slot below a full ring. That slot is the one snapshot this commit exists
        // to keep, so it is held out of the prune and the ring sheds the lowest of the OTHERS.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        for (var i = 1; i <= GoldenHeader.SnapshotKeep; i++)
            File.WriteAllText(
                Path.Combine(_dir, $"golden-header.growth.md.20991231-23595{i}-0001.bak"), $"future {i}\n");

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        var surviving = Baks(_dir);
        Assert.Equal(GoldenHeader.SnapshotKeep, surviving.Length);
        Assert.Contains(surviving, f => File.ReadAllText(f) == "base\n");
        Assert.False(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20991231-235951-0001.bak")),
            "the lowest of the other slots goes instead");
    }

    [Fact]
    public void Commit_prunes_a_legacy_hex_stamped_slot_before_any_dated_slot()
    {
        // Rings written by clavity-v26 hold slots named with hex Stopwatch ticks (ROADMAP section 99).
        // Some of those sort ABOVE every dated name under Ordinal order; a prune that trusted the name
        // alone would never evict such a slot and would evict every NEW snapshot ahead of it. A legacy
        // slot is older than any dated slot by construction, so it goes first.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        SeedOldSlots(GoldenHeader.SnapshotKeep);
        var legacy = Path.Combine(_dir, "golden-header.growth.md.fffffffffffffff1.bak");
        File.WriteAllText(legacy, "legacy\n");
        File.WriteAllText(legacy + ".sha256", GoldenHeader.Sha256Hex("legacy\n"));

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        var surviving = Baks(_dir);
        Assert.Equal(GoldenHeader.SnapshotKeep, surviving.Length);
        Assert.False(File.Exists(legacy), "the legacy slot is evicted before any dated slot");
        Assert.False(File.Exists(legacy + ".sha256"), "its sidecar goes with it");
        Assert.False(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000001.bak")),
            "then the oldest dated slot");
        Assert.True(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000002.bak")));
        Assert.Contains(surviving, f => File.ReadAllText(f) == "base\n");
    }

    // The six tests below close the gaps AGY-TEST-AUDIT round 1 (2026-10-26) found in this ring's
    // safety-net; each was watched red under the mutant named in its comment before it was kept.

    [Fact]
    public void Commit_evicts_every_legacy_slot_before_any_dated_slot_with_or_without_counter()
    {
        // MG-1: the dated-slot rule must accept both stamp forms (with and without the counter) and
        // reject a hex-tick name even when it starts with eight digits. Mutants: dropping the counter
        // branch from DatedSlot evicts the counter-bearing slots as if legacy; relaxing it to
        // `\.\d{8}.*` keeps the digit-leading hex slot forever.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        for (var i = 1; i <= 4; i++)
            File.WriteAllText(Path.Combine(_dir, $"golden-header.growth.md.20260101-00000{i}-0001.bak"), $"dated {i}\n");
        File.WriteAllText(Path.Combine(_dir, "golden-header.growth.md.20260101-000005.bak"), "pre-v26\n");
        var letters = Path.Combine(_dir, "golden-header.growth.md.fffffffffffffff1.bak");
        var digits = Path.Combine(_dir, "golden-header.growth.md.90000000abcdef.bak");
        File.WriteAllText(letters, "legacy a\n");
        File.WriteAllText(digits, "legacy b\n");

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        var surviving = Baks(_dir);
        Assert.Equal(GoldenHeader.SnapshotKeep, surviving.Length);
        Assert.False(File.Exists(letters), "a hex-tick slot goes before any dated slot");
        Assert.False(File.Exists(digits), "so does one that happens to start with eight digits");
        Assert.False(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000001-0001.bak")),
            "then the lowest dated slot");
        Assert.True(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000002-0001.bak")));
        Assert.True(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000005.bak")),
            "a pre-v26 counter-less stamp is a dated slot too");
        Assert.Contains(surviving, f => File.ReadAllText(f) == "base\n");
    }

    [Fact]
    public void Commit_prunes_rapid_same_second_commits_to_the_retention_limit()
    {
        // MG-2: the just-written slot is held out of the prune by its FULL name. Six commits in one
        // second share the stamp's date-time and differ only by counter; an exclusion by prefix would
        // hold all of them out and the ring would grow past SnapshotKeep.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        for (var i = 1; i <= GoldenHeader.SnapshotKeep + 1; i++)
            GoldenHeader.CommitGrowth(_dir, $"c{i}\n");

        var surviving = Baks(_dir);
        Assert.Equal(GoldenHeader.SnapshotKeep, surviving.Length);
        Assert.DoesNotContain(surviving, f => File.ReadAllText(f) == "base\n");
        Assert.Contains(surviving, f => File.ReadAllText(f) == $"c{GoldenHeader.SnapshotKeep}\n");
    }

    [Fact]
    public void Commit_snapshots_when_content_differs_only_by_case()
    {
        // MG-3: the dedup compares bytes, not letters. Mutant: OrdinalIgnoreCase skips the snapshot.
        GoldenHeader.CommitGrowth(_dir, "header\n");
        GoldenHeader.CommitGrowth(_dir, "HEADER\n");

        var bak = Assert.Single(Baks(_dir));
        Assert.Equal("header\n", File.ReadAllText(bak));
        Assert.Equal(GoldenHeader.Sha256Hex("header\n"), File.ReadAllText(bak + ".sha256").Trim());
        Assert.Equal("HEADER\n", File.ReadAllText(GoldenHeader.GrowthPath(_dir)));
    }

    [Fact]
    public void Commit_leaves_an_existing_ring_untouched_when_content_is_unchanged()
    {
        // BS-1: an unchanged re-commit neither adds a slot nor prunes - even over a ring already past
        // the limit. Mutant: running the prune on the unchanged path trims the ring to SnapshotKeep - 1.
        GoldenHeader.CommitGrowth(_dir, "same\n");
        SeedOldSlots(GoldenHeader.SnapshotKeep + 1);

        GoldenHeader.CommitGrowth(_dir, "same\n");

        var slots = Baks(_dir);
        Assert.Equal(GoldenHeader.SnapshotKeep + 1, slots.Length);
        for (var i = 1; i <= GoldenHeader.SnapshotKeep + 1; i++)
            Assert.Equal($"old {i}\n", File.ReadAllText(Path.Combine(_dir, $"golden-header.growth.md.20260101-00000{i}.bak")));
    }

    [Fact]
    public void Commit_snapshots_a_sidecarless_live_header_without_throwing()
    {
        // CA-1: a live header with no .sha256 beside it (the installer seeds SEED that way) is
        // snapshotted without a sidecar rather than crashing. Mutant: dropping the File.Exists guard
        // throws FileNotFoundException on the first commit over such a file.
        File.WriteAllText(GoldenHeader.GrowthPath(_dir), "seeded\n");
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir) + ".sha256"));

        GoldenHeader.CommitGrowth(_dir, "replacement\n");

        var bak = Assert.Single(Baks(_dir));
        Assert.Equal("seeded\n", File.ReadAllText(bak));
        Assert.False(File.Exists(bak + ".sha256"), "no sidecar existed to rotate");
        Assert.True(File.Exists(GoldenHeader.GrowthPath(_dir) + ".sha256"), "the new live header gets one");
    }

    [Fact]
    public void CommitGrowth_prunes_only_its_own_ring()
    {
        // PP-1: the SEED ring, the GROWTH ring and the driver cheatsheet's ring share one directory.
        // The prune globs by its own file name; a wider glob would count and delete the siblings' slots.
        for (var i = 1; i <= GoldenHeader.SnapshotKeep; i++)
            File.WriteAllText(Path.Combine(_dir, $"golden-header.seed.md.20260101-00000{i}.bak"), $"seed {i}\n");
        for (var i = 1; i <= 2; i++)
            File.WriteAllText(Path.Combine(_dir, $"driver-cheatsheet.growth.md.20260101-00000{i}.bak"), $"sheet {i}\n");
        GoldenHeader.CommitGrowth(_dir, "base\n");
        SeedOldSlots(GoldenHeader.SnapshotKeep + 1);

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        Assert.Equal(GoldenHeader.SnapshotKeep, Baks(_dir).Length);
        Assert.Equal(GoldenHeader.SnapshotKeep, Directory.GetFiles(_dir, "golden-header.seed.md.*.bak").Length);
        Assert.Equal(2, Directory.GetFiles(_dir, "driver-cheatsheet.growth.md.*.bak").Length);
    }

    [Fact]
    public void Commit_prunes_a_stale_slots_sidecar_along_with_it()
    {
        // A pruned header whose sidecar is left behind leaks one orphan file per drain forever, and the
        // orphans are indistinguishable from live slots by name.
        GoldenHeader.CommitGrowth(_dir, "base\n");
        SeedOldSlots(GoldenHeader.SnapshotKeep + 2);

        GoldenHeader.CommitGrowth(_dir, "trigger prune\n");

        Assert.False(File.Exists(Path.Combine(_dir, "golden-header.growth.md.20260101-000001.bak.sha256")),
            "a pruned slot must not leave its sidecar behind");
        Assert.Equal(
            Baks(_dir).Length,
            Directory.GetFiles(_dir, "golden-header.growth.md.*.bak.sha256").Length);
    }

    // Branch G: the --cheatsheet target writes the cheatsheet growth AND its sidecar and never the golden header.
    [Fact]
    public void CurateCommit_cheatsheet_writes_the_cheatsheet_growth_and_its_sidecar_and_not_the_golden_header()
    {
        var error = new StringWriter();
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("- CHEAT\n"), error, cheatsheet: true));
        var path = Path.Combine(_dir, DriverCheatsheet.GrowthFileName);
        Assert.Equal("- CHEAT\n", File.ReadAllText(path));
        Assert.True(File.Exists(path + ".sha256"), "the sidecar IS the publish");
        Assert.False(File.Exists(GoldenHeader.GrowthPath(_dir)));
        Assert.Equal("", error.ToString());
    }

    // Branch G test-audit PP-1: the other direction of the disjoint-targets property (classic pins both).
    [Fact]
    public void CurateCommit_cheatsheet_leaves_an_existing_golden_header_growth_untouched()
    {
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("GOLDEN\n"), new StringWriter()));
        var sidecarBefore = File.ReadAllText(GoldenHeader.GrowthPath(_dir) + ".sha256");
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("- CHEAT\n"), new StringWriter(), cheatsheet: true));
        Assert.Equal("GOLDEN\n", File.ReadAllText(GoldenHeader.GrowthPath(_dir)));
        Assert.Equal(sidecarBefore, File.ReadAllText(GoldenHeader.GrowthPath(_dir) + ".sha256"));
        Assert.Equal("- CHEAT\n", File.ReadAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName)));
    }

    [Fact]
    public void CurateCommit_cheatsheet_published_growth_is_delivered_by_the_reader_without_a_degrade()
    {
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("- SENTINEL-G-PUBLISHED\n"), new StringWriter(), cheatsheet: true));
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor + "\n\n- SENTINEL-G-PUBLISHED", text);
        Assert.False(degraded);
    }

    // 16 KiB of growth alone is under the reader's per-file cap but floor + growth is over it: refused at commit
    // (exit 2 = bad input in this variant's numbering), nothing written.
    [Fact]
    public void CurateCommit_cheatsheet_refuses_a_combined_over_cap_payload_and_writes_nothing()
    {
        var error = new StringWriter();
        Assert.Equal(2, CliVerbs.CurateCommit(_dir, Utf8(new string('g', 16 * 1024)), error, cheatsheet: true));
        Assert.Contains("combined cap", error.ToString());
        Assert.False(File.Exists(Path.Combine(_dir, DriverCheatsheet.GrowthFileName)));
        Assert.False(File.Exists(Path.Combine(_dir, DriverCheatsheet.GrowthFileName) + ".sha256"));
    }

    // The bare verb must leave an existing cheatsheet publish alone (the disjoint-targets property, other direction).
    [Fact]
    public void CurateCommit_bare_leaves_an_existing_cheatsheet_publish_untouched()
    {
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("- CHEAT\n"), new StringWriter(), cheatsheet: true));
        var sidecarBefore = File.ReadAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName) + ".sha256");
        Assert.Equal(0, CliVerbs.CurateCommit(_dir, Utf8("GOLDEN\n"), new StringWriter()));
        Assert.Equal("GOLDEN\n", File.ReadAllText(GoldenHeader.GrowthPath(_dir)));
        Assert.Equal("- CHEAT\n", File.ReadAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName)));
        Assert.Equal(sidecarBefore, File.ReadAllText(Path.Combine(_dir, DriverCheatsheet.GrowthFileName) + ".sha256"));
    }

    [Theory]
    [InlineData(new[] { "curate-commit" }, true, false)]
    [InlineData(new[] { "curate-commit", "--cheatsheet" }, true, true)]
    [InlineData(new[] { "curate-commit", "--bogus" }, false, false)]
    [InlineData(new[] { "curate-commit", "--cheatsheet", "extra" }, false, true)]
    public void TryParseCurateCommitArgs_accepts_only_the_cheatsheet_flag(string[] args, bool ok, bool cheatsheet)
    {
        Assert.Equal(ok, CliVerbs.TryParseCurateCommitArgs(args, out var gotCheatsheet, out var error));
        Assert.Equal(cheatsheet, gotCheatsheet);
        if (ok) Assert.Null(error);
        else Assert.Contains(args[^1], error!);
    }
}
