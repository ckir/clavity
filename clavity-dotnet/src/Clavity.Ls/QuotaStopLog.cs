// Copyright (c) 2026 Costas Kirgoussios
//
// This software is licensed under the PolyForm Noncommercial License 1.0.0.
// You may obtain a copy of the License at:
// https://polyformproject.org/licenses/noncommercial/1.0.0/

using System.Text;
using System.Text.RegularExpressions;

namespace Clavity.Ls;

/// <summary>ROADMAP section 66. agy reports a quota stop ONLY in its own log and in its terminal; on the wire the turn
/// ends with no assistant text, which agy_ask could not tell from a dropped reply. The log is the file clavity-ls already
/// opens for port discovery (AgyViewOptions.CliLogPath), so: remember its length when an ask starts, and after the wait
/// scan what was APPENDED for the quota event. Position, not time: glog stamps carry no year or zone.</summary>
public static partial class QuotaStopLog   // not `QuotaStop`: that is the AskReply FIELD it fills, and `QuotaStop = QuotaStop.FindSince(...)` reads badly
{
    /// <summary>Only this much of the appended region is scanned, from its END: the event is written as the turn ends,
    /// so it is near the tail, and a chatty log must not make every ask read megabytes.</summary>
    public const long ScanWindow = 1024 * 1024;

    // The two lines agy writes per event both end with this; the capture is the human sentence after the code.
    // The trailing lookahead requires a COMPLETE line: agy may still be writing it when the scan runs, and a half-written
    // "Resets in 2" must not be reported as a 2-unit reset. A missed event degrades to today's [13b] notice, never to a wrong one.
    [GeneratedRegex(@"RESOURCE_EXHAUSTED \(code 429\): (Individual quota reached\.[^\r\n]*?Resets in [^\s.]+\.?)(?=\r?\n)", RegexOptions.CultureInvariant)]
    private static partial Regex EventRegex();

    // The sentence is lifted from a LOG FILE into the driver's context (test-audit Branch 4 R1, BS-1): control characters
    // (an escape sequence, a tab, a NUL) are mapped to '?' exactly as ArgumentPrecheck does for client-supplied names.
    private static string Printable(string s)
    {
        var sb = new StringBuilder(s.Length);
        foreach (var c in s) sb.Append(char.IsControl(c) ? '?' : c);
        return sb.ToString();
    }

    /// <summary>The log's current length, or 0 when it cannot be read. Never throws.</summary>
    public static long Mark(string? path)
    {
        try { return path is not null && File.Exists(path) ? new FileInfo(path).Length : 0; }
        catch { return 0; }
    }

    /// <summary>The quota message appended after <paramref name="mark"/>, or null. A file shorter than the mark (rotated,
    /// truncated) is scanned from the start. Opened shared: agy holds the file open for writing. Never throws.</summary>
    public static string? FindSince(string? path, long mark)
    {
        try
        {
            if (path is null || !File.Exists(path)) return null;
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
            var start = mark <= fs.Length ? mark : 0;
            if (fs.Length - start > ScanWindow) start = fs.Length - ScanWindow;
            fs.Position = start;
            using var reader = new StreamReader(fs, Encoding.UTF8, detectEncodingFromByteOrderMarks: false);
            var appended = reader.ReadToEnd();
            string? last = null;
            foreach (Match m in EventRegex().Matches(appended)) last = m.Groups[1].Value;
            return last is null ? null : Printable(last);
        }
        catch { return null; }
    }
}
