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
}
