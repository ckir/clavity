using Clavity.Ls;

namespace Clavity.Ls.Tests;

public class StartArgsTests
{
    private const string Sid = "11111111-2222-3333-4444-555555555555";
    private static readonly string Cwd = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "cwd"));
    private static readonly string Repo = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "repo"));

    [Fact]
    public void A_bare_folder_is_the_folder_and_nothing_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo }, Cwd);
        Assert.Equal(Repo, a.Folder);
        Assert.Null(a.AttachSessionId);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Without_a_folder_the_current_directory_is_used_and_dash_args_reach_Claude()
    {
        var a = StartArgs.Parse(new[] { "--model", "opus" }, Cwd);
        Assert.Equal(Cwd, a.Folder);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_directly_after_the_folder_is_consumed_and_the_rest_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", Sid, "--model", "opus" }, Cwd);
        Assert.Equal(Repo, a.Folder);
        Assert.Equal(Sid, a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_without_a_folder_uses_the_current_directory()
    {
        var a = StartArgs.Parse(new[] { "--attach", Sid }, Cwd);
        Assert.Equal(Cwd, a.Folder);
        Assert.Equal(Sid, a.AttachSessionId);
    }

    [Fact]
    public void Attach_after_a_Claude_argument_is_NOT_ours_and_reaches_Claude_untouched()
    {
        var a = StartArgs.Parse(new[] { Repo, "--model", "opus", "--attach", Sid }, Cwd);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus", "--attach", Sid }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_with_no_id_is_refused_naming_the_flag()
    {
        var ex = Assert.Throws<ArgumentException>(() => StartArgs.Parse(new[] { Repo, "--attach" }, Cwd));
        Assert.Contains("--attach", ex.Message);
    }

    [Theory]
    [InlineData("../../etc")]
    [InlineData("11111111222233334444555555555555")]
    [InlineData("--model")]
    public void Attach_with_a_malformed_id_is_refused_quoting_it(string bad)
    {
        var ex = Assert.Throws<ArgumentException>(() => StartArgs.Parse(new[] { Repo, "--attach", bad }, Cwd));
        Assert.Contains($"'{bad}'", ex.Message);
    }
}
