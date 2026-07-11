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
        var core = File.ReadAllText(CoreSourcePath()).Trim();
        Assert.Equal(core, DriverCheatsheet.BaselineFloor);
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
