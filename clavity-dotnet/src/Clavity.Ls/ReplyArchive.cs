using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;

namespace Clavity.Ls;

/// <summary>Persists every reply, so a review that dies on the wire is still on disk. The ROADMAP entry's
/// second measured loss was exactly this: "a reply died on the wire with the review stranded in the peer's
/// console". Today nothing in AgyView writes a reply anywhere.
///
/// EVERY operation is best-effort and swallows its own failures. The archive is OBSERVATIONAL: a broken or
/// unwritable archive must never convert a working ask into a failed one. That is the same rule the
/// progress sink follows in AgyView, and for the same reason.</summary>
public static class ReplyArchive
{
    public const string SizeIndexFileName = "reply-sizes.txt";

    /// <summary>Write one reply. Returns the path written, or null if anything at all went wrong.</summary>
    public static string? Write(string dir, string cascadeId, string? answer, DateTime utcNow)
    {
        try
        {
            Directory.CreateDirectory(dir);
            var safeCascade = Sanitise(cascadeId);
            // INVARIANT CULTURE, ALWAYS. This timestamp is a machine-readable KEY: the pruner recognises
            // its own files by it and sorts them by it. String interpolation formats with CurrentCulture,
            // so on a non-Gregorian calendar the year is not 2026 - measured: 2569 (th-TH), 1448 (ar-SA),
            // 1405 (fa-IR). None match the pruner's glob, so it silently stops recognising its own files
            // and the archive grows forever, while the line-counted index prune keeps working and hides
            // it. (Capstone R4, Time Traveler.)
            var stamp = utcNow.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture);
            var name = $"{stamp}-{safeCascade}.md";
            var path = Path.Combine(dir, name);
            File.WriteAllText(path, answer ?? string.Empty, new UTF8Encoding(false));

            // One row per reply: the byte length of the answer as UTF-8, which is what the peer sent.
            var bytes = answer is null ? 0 : Encoding.UTF8.GetByteCount(answer);
            var index = Path.Combine(dir, SizeIndexFileName);
            File.AppendAllText(index, bytes.ToString(CultureInfo.InvariantCulture) + "\n", new UTF8Encoding(false));

            // PRUNE ON WRITE so the read stays bounded. Only the most recent rows can ever matter -
            // ReplySizeHistory looks at the last Window - and an unpruned index turns every ask into an
            // O(N) read that grows forever. Rewrite only when the file has actually outgrown the cap.
            //
            // ATOMICALLY. A plain WriteAllLines truncates in place, so a crash mid-prune destroys the
            // whole size history and - because every failure here is swallowed - destroys it SILENTLY.
            // Write a sibling temp and move it over, the same mechanism the golden header uses.
            // (Capstone R1, Cascade Analyst.)
            var rows = File.ReadAllLines(index);
            if (rows.Length > MaxIndexRows)
            {
                // A UNIQUE temp name per write. A single hardcoded "index.tmp" turns two concurrent asks
                // into a collision: the loser takes an IOException, the swallow converts it to null, and
                // the caller then announces that the size baseline will not advance - a FALSE alarm, since
                // that ask's row was already appended and the winner is pruning it. A deceptive
                // diagnostic is worse than none. (Capstone R3, State Corruptor - a defect round 1's own
                // atomic-prune fix introduced.)
                var tmp = index + "." + Guid.NewGuid().ToString("N") + ".tmp";
                try
                {
                    File.WriteAllLines(tmp, rows[^MaxIndexRows..], new UTF8Encoding(false));
                    File.Move(tmp, index, overwrite: true);
                }
                finally
                {
                    // Never leave a temp behind if the move failed - the residue would accumulate exactly
                    // like the .md files did.
                    try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
                }
            }

            PruneReplyFiles(dir);
            return path;
        }
        catch
        {
            // Deliberately unconditional - see the class remark. There is no logger in this layer.
            return null;
        }
    }

    /// <summary>How many rows the index keeps. Bounded on WRITE so the read is O(1) in repo age.</summary>
    public const int MaxIndexRows = 100;

    /// <summary>Sizes of previously-archived replies, oldest first. Empty when the archive does not exist.
    ///
    /// BOUNDED BY CONSTRUCTION. An AGY-AFTER panel found the first draft read the ENTIRE index on every
    /// ask and parsed every row only for the caller to keep the last five - an O(N) read and parse on a
    /// hot path, growing forever with repo age. The index is now pruned on write, so this read is bounded
    /// by MaxIndexRows rather than by history.</summary>
    public static IReadOnlyList<int> ReadRecentSizes(string dir)
    {
        var sizes = new List<int>();
        try
        {
            var index = Path.Combine(dir, SizeIndexFileName);
            if (!File.Exists(index)) return sizes;
            foreach (var line in File.ReadAllLines(index))
            {
                // A torn or hand-edited row is skipped, never fatal.
                if (int.TryParse(line.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n))
                    sizes.Add(n);
            }
        }
        catch
        {
            // Same rule: an unreadable archive yields no baseline rather than an exception.
        }
        return sizes;
    }

    /// <summary>Bound the archive DIRECTORY, not just its index.
    ///
    /// The index was pruned from the start; the .md files it indexes were not, so every ask left one
    /// behind forever. Bounding the read while the actual disk growth continued is a partial fix that
    /// reads as a complete one - the worst kind. (Capstone R1, Resource Vampire.)
    ///
    /// The listing is O(files), but files is bounded by this very method, so it never grows past the cap.
    /// Names are timestamp-prefixed, so an ordinal sort is chronological.</summary>
    private static void PruneReplyFiles(string dir)
    {
        try
        {
            // MATCH ONLY WHAT THIS CLASS WRITES. An ordinal sort over every *.md puts a foreign
            // "00-scratch.md" above every 2026-timestamped name, and the pruner would delete it first -
            // silently, since everything here is swallowed. The glob is the fix: a name this class did
            // not produce is not a candidate for deletion. (Capstone R2, Mechanism Gamer.)
            var files = Directory.GetFiles(dir, "20??????-??????-*.md");
            if (files.Length <= MaxIndexRows) return;
            Array.Sort(files, StringComparer.Ordinal);
            for (var i = 0; i < files.Length - MaxIndexRows; i++)
            {
                try { File.Delete(files[i]); }
                catch { /* one undeletable file must not stop the rest, nor fail the ask. */ }
            }
        }
        catch
        {
            // Same rule as everything else here: observational, never fatal.
        }
    }

    private static string Sanitise(string value)
    {
        var sb = new StringBuilder(value.Length);
        foreach (var c in value)
            sb.Append(char.IsLetterOrDigit(c) || c == '-' || c == '_' ? c : '-');
        return sb.Length == 0 ? "unknown" : sb.ToString();
    }
}
