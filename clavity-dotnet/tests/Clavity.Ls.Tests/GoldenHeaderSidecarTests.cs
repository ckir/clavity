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
}
