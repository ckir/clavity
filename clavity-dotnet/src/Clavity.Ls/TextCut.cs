namespace Clavity.Ls;

/// <summary>Cuts a string at a character budget WITHOUT splitting a UTF-16 surrogate pair. A raw <c>s[..n]</c> keeps half
/// of an emoji when n lands between its two chars, and a file written through a UTF-8 encoder turns the orphan into a
/// replacement character (ROADMAP section 74, capstone R1 BS1). Both helpers move the cut by at most one char.</summary>
public static class TextCut
{
    /// <summary>The first <paramref name="max"/> chars of <paramref name="s"/>, or one fewer when that would end on the
    /// high half of a pair.</summary>
    public static string Prefix(string s, int max)
    {
        if (s.Length <= max) return s;
        var n = max;
        if (n > 0 && char.IsHighSurrogate(s[n - 1]) && char.IsLowSurrogate(s[n])) n--;
        return s[..n];
    }

    /// <summary>The index to start a tail slice at: <paramref name="start"/>, or one later when that would begin on the
    /// low half of a pair.</summary>
    public static int SuffixStart(string s, int start)
    {
        if (start > 0 && start < s.Length && char.IsLowSurrogate(s[start]) && char.IsHighSurrogate(s[start - 1])) return start + 1;
        return start;
    }
}
