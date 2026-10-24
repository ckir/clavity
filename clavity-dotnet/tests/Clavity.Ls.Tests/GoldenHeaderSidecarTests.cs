// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Text;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

/// <summary>Pins the shared sidecar verdict both readers consume (twin: golden_header.rs verify_sidecar_reports_each_verdict).</summary>
public sealed class GoldenHeaderSidecarTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-sidecar-" + Guid.NewGuid().ToString("N"));
    public GoldenHeaderSidecarTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { /* best effort */ } }

    [Fact]
    public void VerifySidecar_reports_each_verdict()
    {
        var p = Path.Combine(_dir, "region.md");
        var body = Encoding.UTF8.GetBytes("body");
        File.WriteAllBytes(p, body);
        Assert.Equal(GoldenHeader.SidecarVerdict.Absent, GoldenHeader.VerifySidecar(p, body, out _));

        File.WriteAllText(p + ".sha256", GoldenHeader.Sha256Hex(body).ToUpperInvariant()); // case-insensitive, like classic
        Assert.Equal(GoldenHeader.SidecarVerdict.Match, GoldenHeader.VerifySidecar(p, body, out _));

        File.WriteAllText(p + ".sha256", GoldenHeader.Sha256Hex(Encoding.UTF8.GetBytes("other")));
        Assert.Equal(GoldenHeader.SidecarVerdict.Mismatch, GoldenHeader.VerifySidecar(p, body, out _));

        File.WriteAllBytes(p + ".sha256", new byte[GoldenHeader.MaxSidecarBytes + 1]);
        Assert.Equal(GoldenHeader.SidecarVerdict.Oversize, GoldenHeader.VerifySidecar(p, body, out var len));
        Assert.Equal(GoldenHeader.MaxSidecarBytes + 1, len);
    }

    // Branch G test-audit BS-1: tolerant of a trailing newline and a UTF-8 BOM (what a shell tool or a Notepad
    // hand-edit adds), NOT of any other suffix or prefix (the distractors) - the same verdicts as classic.
    [Theory]
    [InlineData("{h}\n", true)]
    [InlineData("{h}\r\n", true)]
    [InlineData("﻿{h}", true)]
    [InlineData("﻿{h}\r\n", true)]
    [InlineData("{h}x", false)]
    [InlineData("x{h}", false)]
    public void VerifySidecar_tolerates_trailing_newlines_and_a_bom_but_not_other_suffixes(string template, bool match)
    {
        var p = Path.Combine(_dir, "region.md");
        var body = Encoding.UTF8.GetBytes("body");
        File.WriteAllBytes(p, body);
        File.WriteAllText(p + ".sha256", template.Replace("{h}", GoldenHeader.Sha256Hex(body)), new UTF8Encoding(false));
        var want = match ? GoldenHeader.SidecarVerdict.Match : GoldenHeader.SidecarVerdict.Mismatch;
        Assert.Equal(want, GoldenHeader.VerifySidecar(p, body, out _));
    }
}
