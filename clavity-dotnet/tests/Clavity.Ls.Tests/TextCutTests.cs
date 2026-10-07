using Clavity.Ls;
using Xunit;

namespace Clavity.Ls.Tests;

public class TextCutTests
{
    // U+1F600 is the surrogate pair 😀: two UTF-16 chars, one character.
    private const string Emoji = "\U0001F600";

    [Fact]
    public void Prefix_backs_off_one_char_rather_than_split_a_surrogate_pair()
    {
        var s = "abc" + Emoji + "def";          // indexes: a0 b1 c2 hi3 lo4 d5 e6 f7
        Assert.Equal("abc", TextCut.Prefix(s, 4));   // a cut at 4 would keep the high surrogate alone
        Assert.Equal("abc" + Emoji, TextCut.Prefix(s, 5));
        Assert.Equal("ab", TextCut.Prefix(s, 2));
    }

    [Fact]
    public void Prefix_of_a_short_or_exact_string_is_the_string() =>
        Assert.Equal("abc", TextCut.Prefix("abc", 3));

    [Fact]
    public void Suffix_starts_one_char_later_rather_than_begin_on_a_lone_low_surrogate()
    {
        var s = "abc" + Emoji + "def";
        Assert.Equal("def", s[TextCut.SuffixStart(s, 4)..]);              // 4 is the LOW half: start after the pair
        Assert.Equal(Emoji + "def", s[TextCut.SuffixStart(s, 3)..]);      // 3 is the HIGH half: the pair is whole
        Assert.Equal("f", s[TextCut.SuffixStart(s, 7)..]);
    }

    [Fact]
    public void No_cut_ever_leaves_a_lone_surrogate()
    {
        var s = string.Concat(Enumerable.Repeat("a" + Emoji, 50));
        for (var n = 0; n <= s.Length; n++)
        {
            var p = TextCut.Prefix(s, n);
            Assert.False(p.Length > 0 && char.IsHighSurrogate(p[^1]), $"prefix {n} ends on a lone high surrogate");
            var t = s[TextCut.SuffixStart(s, n)..];
            Assert.False(t.Length > 0 && char.IsLowSurrogate(t[0]), $"suffix {n} starts on a lone low surrogate");
        }
    }
}
