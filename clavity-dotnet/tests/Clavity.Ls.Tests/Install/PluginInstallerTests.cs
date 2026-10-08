using Clavity.Ls.Install;
using Xunit;

namespace Clavity.Ls.Tests.Install;

public sealed class PluginInstallerTests
{
    // U+1F600 is the surrogate pair 😀: two UTF-16 chars, one character.
    private const string Emoji = "\U0001F600";

    private static PowerShellStreamer Returning(int exit, string output) => _ => new ProcessOutcome(exit, output);

    [Fact]
    public void Install_message_never_ends_on_the_high_half_of_a_surrogate_pair()
    {
        // 199 ASCII chars put the pair at [199],[200]: a raw s[..200] keeps only the high half.
        var output = new string('a', 199) + Emoji + "tail that is cut";
        var r = PluginInstaller.Install(Agent.Claude, "clavity", @"C:\mp", Returning(0, output));
        Assert.True(r.Ok);
        Assert.StartsWith("register-plugin.ps1 exit 0: ", r.Detail);
        var cut = r.Detail["register-plugin.ps1 exit 0: ".Length..];
        Assert.Equal(new string('a', 199), cut);                 // the pair backed off, nothing else lost
        Assert.False(char.IsHighSurrogate(cut[^1]));
        Assert.DoesNotContain("\uFFFD", r.Detail);
    }

    [Fact]
    public void Uninstall_message_keeps_at_most_200_chars_of_output()
    {
        var r = PluginInstaller.Uninstall(Agent.Agy, "clavity", Returning(4, new string('b', 300)));
        Assert.True(r.Ok);                                        // exit 4 = agent not detected = fail-open
        Assert.EndsWith(new string('b', 200), r.Detail);
        Assert.DoesNotContain(new string('b', 201), r.Detail);
    }

    [Fact]
    public void Empty_output_is_named_not_blank()
    {
        var r = PluginInstaller.Install(Agent.Agy, "clavity", @"C:\mp", Returning(3, ""));
        Assert.False(r.Ok);
        Assert.Equal("register-plugin.ps1 exit 3: (no output)", r.Detail);
    }
}
