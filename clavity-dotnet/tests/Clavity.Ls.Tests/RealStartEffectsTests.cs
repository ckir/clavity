// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/




using Clavity.Cli;
using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public sealed class RealStartEffectsTests
{
    [Fact]
    public void Real_effects_report_IsMacOS_from_the_OS() =>
        Assert.Equal(OperatingSystem.IsMacOS(), new RealStartEffects().IsMacOS);

    [Fact]
    public void Real_effects_read_the_ssh_variables_through_the_injected_reader()
    {
        Assert.True(new RealStartEffects(n => n == "SSH_TTY" ? "/dev/pts/1" : null).IsSshSession);
        Assert.False(new RealStartEffects(_ => null).IsSshSession);
    }

    [Fact]
    public void Real_ResolveOnPath_finds_a_command_on_the_process_PATH_as_an_absolute_path_and_misses_an_absent_one()
    {
        if (OperatingSystem.IsWindows()) return;   // the exec-bit lookup is the POSIX one; sh is on every POSIX PATH
        var fx = new RealStartEffects();
        var found = fx.ResolveOnPath("sh");
        Assert.NotNull(found);
        Assert.True(Path.IsPathRooted(found));
        Assert.True(fx.OnPath("sh"));
        Assert.Null(fx.ResolveOnPath("clavity-no-such-command-" + Guid.NewGuid().ToString("N")));
        Assert.False(fx.OnPath("clavity-no-such-command-" + Guid.NewGuid().ToString("N")));
    }
}
