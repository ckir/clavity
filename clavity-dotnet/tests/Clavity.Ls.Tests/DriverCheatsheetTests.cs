using System.Text;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public sealed class DriverCheatsheetTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "clavity-cheat-" + Guid.NewGuid().ToString("N"));
    public DriverCheatsheetTests() => Directory.CreateDirectory(_dir);
    public void Dispose() { try { Directory.Delete(_dir, true); } catch { /* best effort */ } }

    [Fact]
    public void Read_returns_baseline_floor_when_file_absent()
    {
        var text = DriverCheatsheet.Read(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor, text);
    }

    [Fact]
    public void Read_returns_file_contents_when_present()
    {
        File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.FileName), "custom core\n");
        Assert.Equal("custom core", DriverCheatsheet.Read(_dir));
    }

    [Fact]
    public void Read_falls_back_to_floor_when_over_cap()
    {
        File.WriteAllBytes(Path.Combine(_dir, DriverCheatsheet.FileName),
            Encoding.UTF8.GetBytes(new string('x', DriverCheatsheet.MaxBytes + 1)));
        Assert.Equal(DriverCheatsheet.BaselineFloor, DriverCheatsheet.Read(_dir));
    }

    // F2 (panel finding): a genuinely-absent file is the normal fresh-install state, NOT a degrade — Degraded
    // must be false so the caller doesn't lead the delivered block with a warning nobody needs to see.
    [Fact]
    public void ReadWithDegradeStatus_reports_not_degraded_when_file_absent()
    {
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor, text);
        Assert.False(degraded);
    }

    // F2: over-cap is an ANOMALOUS degrade — the file exists but is unusable — so Degraded must be true.
    [Fact]
    public void ReadWithDegradeStatus_reports_degraded_when_over_cap()
    {
        File.WriteAllBytes(Path.Combine(_dir, DriverCheatsheet.FileName),
            Encoding.UTF8.GetBytes(new string('x', DriverCheatsheet.MaxBytes + 1)));
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor, text);
        Assert.True(degraded);
    }

    // F2: a present-but-empty file is also an ANOMALOUS degrade (distinct from a genuinely absent file).
    [Fact]
    public void ReadWithDegradeStatus_reports_degraded_when_file_present_but_empty()
    {
        File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.FileName), "");
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal(DriverCheatsheet.BaselineFloor, text);
        Assert.True(degraded);
    }

    // F2: a small, present, non-empty file is normal content delivery — never a degrade.
    [Fact]
    public void ReadWithDegradeStatus_reports_not_degraded_when_file_present_and_readable()
    {
        File.WriteAllText(Path.Combine(_dir, DriverCheatsheet.FileName), "custom core\n");
        var (text, degraded) = DriverCheatsheet.ReadWithDegradeStatus(_dir);
        Assert.Equal("custom core", text);
        Assert.False(degraded);
    }

    [Fact]
    public void Block_prefixes_the_driver_guidance_label()
    {
        var block = DriverCheatsheet.Block("hello");
        Assert.StartsWith("[driver_guidance]", block);
        Assert.Contains("hello", block);
    }

    // Cross-file invariant (spec acceptance 4 — identical content): the compiled-in floor MUST match the
    // canonical source authored in Task 1.4. This is executed by a DIFFERENT subagent than Task 1.4, so this
    // test mechanically catches drift (e.g. an auto-reflow) instead of relying on a "keep them identical" note.
    [Fact]
    public void BaselineFloor_matches_the_canonical_core_source()
    {
        // Normalize CRLF -> LF: CI may check out the .md with Windows line endings, but BaselineFloor
        // is an \n literal. Parity is about CONTENT, not the checkout's EOL artifact.
        var core = File.ReadAllText(CoreSourcePath()).Replace("\r\n", "\n").Trim();
        Assert.Equal(DriverCheatsheet.BaselineFloor, core);
    }

    // Locate agy-autotrain/knowledge/driver-cheatsheet.core.md via THIS test's compile-time source path
    // (robust to the test's runtime working dir). This file lives at
    // clavity/clavity-dotnet/tests/Clavity.Ls.Tests/DriverCheatsheetTests.cs -> 3 dirs up == repo root.
    private static string CoreSourcePath([System.Runtime.CompilerServices.CallerFilePath] string? thisFile = null)
    {
        var dir = Path.GetDirectoryName(thisFile)!;                              // Clavity.Ls.Tests
        var repoRoot = Path.GetFullPath(Path.Combine(dir, "..", "..", ".."));    // clavity/
        return Path.Combine(repoRoot, "agy-autotrain", "knowledge", "driver-cheatsheet.core.md");
    }
}
