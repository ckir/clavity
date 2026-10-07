using System.Text;
using Clavity.Ls.Proto;

namespace Clavity.Ls;

/// <summary>ROADMAP section 74, C-capture: the server writes the FULL text of every assistant step of an ask's delta to
/// a file, so a reply the [13b] checks flag - or an Answer cut at 16 000 characters - can be read whole without a
/// re-ask. Every failure is RETURNED, never thrown: a capture must never fail the ask (spec panel R1, CA1).</summary>
public static class ReplyCapture
{
    /// <summary>Largest capture, in characters. Over it the head and the tail are kept - the verdict sits at the end.</summary>
    public const int MaxChars = 1024 * 1024;
    public const int HeadChars = 768 * 1024;
    public const int TailChars = 128 * 1024;

    /// <summary>Files kept per directory - a COUNT, not an age: a long session would defeat an age rule (D-prune).</summary>
    public const int Keep = 50;

    public static (string? Path, string? Error) Write(string dir, string cascadeId, int firstStepIndex, IReadOnlyList<CascadeStep> delta)
    {
        try
        {
            if (!IsSafeName(cascadeId)) return (null, $"cascade id '{Clip(cascadeId)}' is not safe in a file name");
            var text = Render(firstStepIndex, delta);
            Directory.CreateDirectory(dir);
            var path = System.IO.Path.Combine(dir, $"{cascadeId}-{firstStepIndex}.md");
            File.WriteAllText(path, text, new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
            return (path, null);
        }
        catch (Exception ex)
        {
            return (null, OneLine(ex));
        }
        finally
        {
            Prune(dir, Keep);   // after every write ATTEMPT (D-prune)
        }
    }

    /// <summary>Each assistant step with text, preceded by <c>----- agy step &lt;index&gt; -----</c>, where index is the
    /// step's position in the trajectory (<paramref name="firstStepIndex"/> + its position in the delta).</summary>
    public static string Render(int firstStepIndex, IReadOnlyList<CascadeStep> delta)
    {
        var sb = new StringBuilder();
        for (var i = 0; i < delta.Count; i++)
        {
            if (delta[i].Kind != StepKind.AssistantKind) continue;
            var t = delta[i].AssistantOutput?.Text;
            if (string.IsNullOrEmpty(t)) continue;
            sb.Append("----- agy step ").Append(firstStepIndex + i).Append(" -----\n").Append(t);
            if (!t.EndsWith('\n')) sb.Append('\n');
        }
        var all = sb.ToString();
        if (all.Length <= MaxChars) return all;
        var head = TextCut.Prefix(all, HeadChars);
        var tailStart = TextCut.SuffixStart(all, all.Length - TailChars);
        var omitted = tailStart - head.Length;
        return string.Concat(head, $"\n----- cut: {omitted} characters omitted -----\n", all.AsSpan(tailStart));
    }

    /// <summary>Delete all but the newest <paramref name="keep"/> <c>*.md</c> files. Best-effort: never throws.</summary>
    public static void Prune(string dir, int keep)
    {
        try
        {
            if (!Directory.Exists(dir)) return;
            var surplus = new DirectoryInfo(dir).GetFiles("*.md")
                .OrderByDescending(f => f.LastWriteTimeUtc)
                .ThenByDescending(f => f.Name, StringComparer.Ordinal)
                .Skip(keep);
            foreach (var f in surplus)
            {
                try { f.Delete(); } catch { /* best-effort */ }
            }
        }
        catch { /* best-effort: pruning never fails the ask */ }
    }

    /// <summary>A cascade id becomes part of a file name, so only ASCII letters, digits and '-' are accepted.</summary>
    public static bool IsSafeName(string s) => s.Length is > 0 and <= 100 && s.All(c => char.IsAsciiLetterOrDigit(c) || c == '-');

    public static string OneLine(Exception ex) => Clip($"{ex.GetType().Name}: {ex.Message}".ReplaceLineEndings(" "));

    public static string Clip(string s, int max = 200) => TextCut.Prefix(s, max);
}
