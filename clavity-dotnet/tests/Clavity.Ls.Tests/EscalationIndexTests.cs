// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

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

    [Fact]
    public void ResolveManualsDir_prefers_plugin_root_knowledge_dir_when_present()
    {
        var pluginRoot = Directory.CreateTempSubdirectory().FullName;
        var expected = Path.Combine(pluginRoot, "knowledge");
        Directory.CreateDirectory(expected);
        var installRoot = Directory.CreateTempSubdirectory().FullName;

        var resolved = EscalationIndex.ResolveManualsDir(pluginRoot, installRoot);

        Assert.Equal(expected, resolved);
    }

    [Fact]
    public void ResolveManualsDir_falls_back_to_install_root_when_plugin_root_is_null_or_blank()
    {
        var installRoot = Path.Combine(Path.GetTempPath(), "clavity-install-root");
        var expected = Path.Combine(installRoot, "plugins", Clavity.Ls.Install.PluginInstaller.PluginName, "knowledge");

        Assert.Equal(expected, EscalationIndex.ResolveManualsDir(null, installRoot));
        Assert.Equal(expected, EscalationIndex.ResolveManualsDir("   ", installRoot));
    }
}
