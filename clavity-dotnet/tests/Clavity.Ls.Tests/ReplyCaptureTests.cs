using System;
using System.IO;
using System.Linq;
using Clavity.Ls;
using Clavity.Ls.Proto;
using Xunit;

namespace Clavity.Ls.Tests;

public class ReplyCaptureTests : IDisposable
{
    private readonly string _dir = Path.Combine(Path.GetTempPath(), "rc-" + Guid.NewGuid().ToString("N"));
    public void Dispose() { if (Directory.Exists(_dir)) Directory.Delete(_dir, recursive: true); }

    private static CascadeStep User(string t) => new() { Kind = 14, UserInput = new CascadeUserInput { Text = t } };
    private static CascadeStep Asst(string t) => new() { Kind = 15, AssistantOutput = new CascadeAssistantOutput { Text = t } };
    private static CascadeStep Tool() => new() { Kind = 5 };

    [Fact]
    public void Writes_every_assistant_step_with_its_trajectory_index()
    {
        var (path, error) = ReplyCapture.Write(_dir, "abc-123", 40, new[] { User("q"), Asst("report"), Tool(), Asst("Noted.") });
        Assert.Null(error);
        Assert.Equal(Path.Combine(_dir, "abc-123-40.md"), path);
        Assert.Equal("----- agy step 41 -----\nreport\n----- agy step 43 -----\nNoted.\n", File.ReadAllText(path!));
    }

    [Fact]
    public void Over_the_cap_keeps_head_and_tail_and_says_how_much_was_cut()
    {
        var big = new string('h', ReplyCapture.MaxChars) + "THE-VERDICT";
        var text = ReplyCapture.Render(0, new[] { Asst(big) });
        Assert.StartsWith("----- agy step 0 -----\nhhh", text);
        Assert.EndsWith("THE-VERDICT\n", text);
        var all = "----- agy step 0 -----\n".Length + big.Length + 1;
        Assert.Contains($"\n----- cut: {all - ReplyCapture.HeadChars - ReplyCapture.TailChars} characters omitted -----\n", text);
        Assert.True(text.Length < ReplyCapture.MaxChars);
    }

    [Fact]
    public void A_failed_write_is_returned_never_thrown()
    {
        Directory.CreateDirectory(_dir);
        var blocker = Path.Combine(_dir, "a-file");
        File.WriteAllText(blocker, "x");
        var (path, error) = ReplyCapture.Write(blocker, "abc", 1, new[] { Asst("r") });   // a FILE where the dir should be
        Assert.Null(path);
        Assert.False(string.IsNullOrWhiteSpace(error));
        Assert.DoesNotContain('\n', error!);
    }

    [Fact]
    public void An_unsafe_cascade_id_is_refused()
    {
        var (path, error) = ReplyCapture.Write(_dir, "..\\evil", 1, new[] { Asst("r") });
        Assert.Null(path);
        Assert.Contains("not safe", error);
    }

    [Fact]
    public void Prune_keeps_the_newest_N_md_files_only()
    {
        Directory.CreateDirectory(_dir);
        var t0 = DateTime.UtcNow.AddHours(-1);
        for (var i = 0; i < 5; i++)
        {
            var f = Path.Combine(_dir, $"f{i}.md");
            File.WriteAllText(f, "x");
            File.SetLastWriteTimeUtc(f, t0.AddMinutes(i));
        }
        File.WriteAllText(Path.Combine(_dir, "keep.txt"), "not a capture");
        ReplyCapture.Prune(_dir, 2);
        Assert.Equal(new[] { "f3.md", "f4.md", "keep.txt" },
                     Directory.GetFiles(_dir).Select(Path.GetFileName).OrderBy(n => n, StringComparer.Ordinal).ToArray());
    }

    private static bool HasLoneSurrogate(string s)
    {
        for (var i = 0; i < s.Length; i++)
        {
            if (char.IsHighSurrogate(s[i]) && !(i + 1 < s.Length && char.IsLowSurrogate(s[i + 1]))) return true;
            if (char.IsLowSurrogate(s[i]) && !(i > 0 && char.IsHighSurrogate(s[i - 1]))) return true;
        }
        return false;
    }

    [Fact]
    public void An_emoji_straddling_the_head_cut_or_the_tail_cut_is_never_split()
    {
        // Capstone R1 BS1. Put a surrogate pair exactly across BOTH cut points: its high half is the last char the
        // head would keep, and its low half is the first char the tail would keep.
        const string emoji = "\U0001F600";
        var header = "----- agy step 0 -----\n".Length;
        var pre = new string('h', ReplyCapture.HeadChars - 1 - header);
        var mid = new string('m', 200_000);
        var text = pre + emoji + mid + emoji + new string('t', ReplyCapture.TailChars - 2);

        var rendered = ReplyCapture.Render(0, new[] { Asst(text) });

        Assert.Contains("characters omitted", rendered);
        Assert.False(HasLoneSurrogate(rendered), "the cut left half of an emoji");
        Assert.True(HasLoneSurrogate(text.Substring(0, ReplyCapture.HeadChars - header)),
                    "control: a raw cut of this very text DOES split the pair, so the row can fail");
    }
}
