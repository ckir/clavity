// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

/// <summary>`clavity-ls --help`: which command lines ask for help (a help flag must never reach a verb that would act on it:
/// `install --help` used to run the install) and what the text must let a cold reader do.</summary>
public sealed class CliHelpTests
{
    [Theory]
    [InlineData("")]
    [InlineData("--help")]
    [InlineData("-h")]
    [InlineData("help")]
    [InlineData("install --help")]
    [InlineData("install -h")]
    [InlineData("install --plugin x --help")]
    [InlineData("uninstall --purge-data -h")]
    [InlineData("is-installed --help")]
    [InlineData("curate-commit --cheatsheet --help")]
    [InlineData("start --help")]
    [InlineData("start -h")]
    [InlineData("agy -h")]
    public void Help_is_requested(string line) => Assert.True(CliVerbs.IsHelpRequest(Words(line)), line);

    [Theory]
    [InlineData("--version")]
    [InlineData("-V")]
    [InlineData("install")]
    [InlineData("is-installed clavity")]
    [InlineData("start")]
    [InlineData("start --profile work")]
    [InlineData("start myrepo --help")]      // forwarded to Claude: a folder came first
    [InlineData("start --profile work -h")]
    [InlineData("agy myrepo -h")]
    [InlineData("some-folder --help")]           // not a verb, so not ours to read
    [InlineData("--helpful")]
    public void Help_is_not_requested(string line) => Assert.False(CliVerbs.IsHelpRequest(Words(line)), line);

    [Fact]
    public void Help_tells_a_cold_reader_how_to_install()
    {
        var help = CliVerbs.HelpText();
        Assert.Contains("claude plugin marketplace add ckir/clavity", help);
        Assert.Contains("claude plugin install clavity@clavity", help);
        Assert.Contains("keeps a clavity-ls launcher on PATH", help);
        Assert.Contains("INSTALL.md", help);
        Assert.Contains("agent-profile", help);
    }

    [Theory]
    [InlineData("  start [folder]")]
    [InlineData("  agy [folder]")]
    [InlineData("  --mcp")]
    [InlineData("  install [--plugin <name>]")]
    [InlineData("  uninstall [--purge-data]")]
    [InlineData("  is-installed <plugin-name>")]
    [InlineData("  curate-commit [--cheatsheet]")]
    [InlineData("  --version, -V")]
    [InlineData("  --help, -h, help")]
    public void Help_documents_every_command(string heading) => Assert.Contains(CliHelpLines(), l => l.StartsWith(heading, StringComparison.Ordinal));

    [Fact]
    public void Help_documents_the_installer_exit_codes_and_names_the_build()
    {
        var help = CliVerbs.HelpText();
        Assert.Contains("5 Claude Code is running", help);
        Assert.Contains("3 no Claude Code or agy found", help);
        Assert.StartsWith(CliVerbs.VersionLine(), help, StringComparison.Ordinal);
    }

    [Fact]
    public void Help_is_plain_ascii_so_a_code_page_console_cannot_garble_it() =>
        Assert.DoesNotContain(CliVerbs.HelpText(), c => c > 127);

    private static string[] Words(string line) => line.Split(' ', StringSplitOptions.RemoveEmptyEntries);

    private static string[] CliHelpLines() => CliVerbs.HelpText().Split('\n');
}
