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
        Assert.True(a.Attach);
        Assert.Equal(Sid, a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Attach_without_a_folder_uses_the_current_directory()
    {
        var a = StartArgs.Parse(new[] { "--attach", Sid }, Cwd);
        Assert.Equal(Cwd, a.Folder);
        Assert.True(a.Attach);
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
    public void Attach_with_nothing_after_it_has_no_id()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Empty(a.ClaudeArgs);
    }

    [Fact]
    public void Attach_followed_by_a_dash_argument_has_no_id_and_the_argument_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "--model", "opus" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "--model", "opus" }, a.ClaudeArgs);
    }

    [Fact]
    public void Without_attach_Attach_is_false()
        => Assert.False(StartArgs.Parse(new[] { Repo }, Cwd).Attach);

    [Fact]
    public void Attach_followed_by_a_positional_prompt_has_no_id_and_the_prompt_reaches_Claude()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "fix the tests" }, Cwd);
        Assert.True(a.Attach);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "fix the tests" }, a.ClaudeArgs);
    }

    [Fact]
    public void A_path_after_attach_is_not_an_id_and_never_becomes_a_file_name()
    {
        var a = StartArgs.Parse(new[] { Repo, "--attach", "../../etc" }, Cwd);
        Assert.Null(a.AttachSessionId);
        Assert.Equal(new[] { "../../etc" }, a.ClaudeArgs);
    }

    [Theory]
    [InlineData("11111111222233334444555555555555")]      // GUID "N" form
    [InlineData("11111111-2222-3333-4444-55555555555")]   // one digit short
    [InlineData("deadbeef")]                              // 8 hex: shaped like a truncated id
    public void Attach_with_a_malformed_id_is_refused_quoting_it(string bad)
    {
        var ex = Assert.Throws<ArgumentException>(() => StartArgs.Parse(new[] { Repo, "--attach", bad }, Cwd));
        Assert.Contains($"'{bad}'", ex.Message);
    }
}
