// clavity-dotnet/tests/Clavity.Ls.Tests/EscalationIndexTests.cs
using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class EscalationIndexTests
{
    [Fact]
    public void Build_returns_null_when_dir_is_null() =>
        Assert.Null(EscalationIndex.Build(null));

    [Fact]
    public void Build_returns_null_when_no_manuals_present()
    {
        var dir = Directory.CreateTempSubdirectory().FullName;
        Assert.Null(EscalationIndex.Build(dir));
    }

    [Fact]
    public void Build_lists_present_manuals_with_absolute_paths()
    {
        var dir = Directory.CreateTempSubdirectory().FullName;
        var a = Path.Combine(dir, "agy-assumptions.md");
        var c = Path.Combine(dir, "agy-capabilities.md");
        File.WriteAllText(a, "x");
        File.WriteAllText(c, "y");

        var block = EscalationIndex.Build(dir);

        Assert.NotNull(block);
        Assert.Contains("escalation index", block, StringComparison.OrdinalIgnoreCase);
        Assert.Contains(a, block);          // literal ABSOLUTE path (Read/view_file needs it)
        Assert.Contains(c, block);
    }

    [Fact]
    public void Build_is_pure_and_deterministic_for_the_same_dir()
    {
        var dir = Directory.CreateTempSubdirectory().FullName;
        File.WriteAllText(Path.Combine(dir, "agy-assumptions.md"), "x");
        Assert.Equal(EscalationIndex.Build(dir), EscalationIndex.Build(dir));   // built once at startup, reused
    }
}
