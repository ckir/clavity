using System;
using System.IO;
using System.Linq;
using System.Text;

namespace Clavity.Ls;

/// <summary>Did the peer reach the END of the artifact it was told to read? The brief requires it to quote,
/// verbatim and near its verdict, the last substantive line of that artifact.
///
/// WHO READS THE FILE: NOT THIS CLASS, AND NOT THE LANGUAGE SERVER. An earlier version of this comment
/// said "the driver computes the same line from the same file and compares", which is false and would
/// mislead the next reader into looking for file IO that does not exist here. The CALLING AGENT applies
/// the rule to the artifact and passes the resulting line in as <paramref name="expectedEcho"/>; this
/// class only compares two strings. That is a deliberate boundary - the language server never learns
/// which file a consult is about - but it also means the expectation is only as honest as the caller.
/// (Capstone R5, The Second Reader.)
///
/// This is the strongest of 13b's three signals because it catches BOTH failure modes with one check. A
/// peer that stopped mid-thought never reached the end and cannot produce the line. A peer that emitted a
/// lone verdict line without doing the work never read the artifact and cannot produce it either - the
/// case a terminal-token oracle passes and only size statistics otherwise hint at.
///
/// LIMITS, stated because a guard whose limits are unstated gets trusted past them: it needs a primary
/// artifact, so a consult on a pasted question has nothing to echo; and a peer that reads only the file's
/// tail defeats it. It raises the floor. It does not prove the work was done.</summary>
public static class SemanticEcho
{
    /// <summary>How close to the end the echo must appear. Three tolerates a verdict line, a blank, and
    /// the echo itself without letting an early quote count.</summary>
    public const int TailLines = 3;

    /// <summary>Apply the echo rule to an ARTIFACT and return the line the peer must quote - the last
    /// line carrying at least <see cref="MinSubstantiveChars"/> letters or digits. Null when the path is
    /// absent, unreadable, or contains no line that could prove anything.
    ///
    /// THIS IS WHY THE DRIVER, NOT THE CALLER, NOW OWNS THE EXPECTATION. The first design had the calling
    /// agent apply the rule and pass the resulting line in. Two parties applying the same rule to the same
    /// file can still disagree - a different line each, both defensible - and the disagreement REDS an
    /// honest review on a fail-closed path. Worse, the rule is a character count, which language models
    /// are measurably bad at. One reader cannot disagree with itself, so the ambiguity class disappears
    /// rather than being mitigated.
    ///
    /// Reading a caller-named file must never fail an ask, so every failure returns null and the check
    /// degrades to "nothing claimed" - the same direction every other degradation here takes.</summary>
    public static string? ExpectedFrom(string? artifactPath)
    {
        if (string.IsNullOrWhiteSpace(artifactPath)) return null;
        try
        {
            // THIS METHOD OPENS A PATH THE CALLER SUPPLIED - a capability the language server did not
            // have before. Three guards, each measured rather than assumed (capstone R9, Boundary
            // Smuggler):
            //
            // 1. REGULAR FILES ONLY. File.Exists is false for a directory and, on this platform, for
            //    CON, NUL and a pipe path - so this one check closes the "block the ask forever on a
            //    device" vector without needing to enumerate device names.
            // 2. A SIZE CAP. Streaming bounds the memory but not the time; "the artifact" could be a
            //    multi-gigabyte log, and this runs on the ask path.
            // 3. SHARE THE FILE. The default File.ReadLines share mode CONFLICTS with an editor holding
            //    the artifact open for write: it throws, the catch swallows it, and the consult degrades
            //    to ECHO WEAK at random depending on whether someone had the file open. Measured both
            //    ways - default throws, FileShare.ReadWrite reads it fine.
            if (!File.Exists(artifactPath)) return null;

            // SINGLE PASS, CONSTANT MEMORY. The obvious spelling - ReadLines(...).Reverse() - materialises
            // the ENTIRE file to walk it backwards, and this path is now supplied by the caller, so
            // "the artifact" could be a multi-gigabyte log. Streaming forward and keeping the last usable
            // line answers the same question without ever holding more than one line.
            string? last = null;
            using var stream = new FileStream(artifactPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);

            // CHECK THE HANDLE, NOT THE PATH. Checking File.Exists and then FileInfo.Length and THEN
            // opening leaves two gaps in which the path can become something else, and the failure there
            // is not an exception but a HANG - a pipe or console device blocks the read, and a hang never
            // reaches the catch below, so it would deadlock the ask rather than degrade to skipped.
            // CanSeek is the property that distinguishes a real file from a pipe or device, and asking
            // the OPEN HANDLE makes the answer atomic with the thing actually being read.
            // (Capstone R10, Boundary Smuggler - correcting my own claim that this degraded safely.)
            if (!stream.CanSeek || stream.Length > MaxArtifactBytes) return null;

            using var reader = new StreamReader(stream);

            // SPLIT THE LINES MYSELF, because StreamReader.ReadLine has no upper bound. A budget checked
            // BETWEEN lines cannot protect against a read that never returns: FileShare.ReadWrite lets
            // another process append, and a writer that emits no newline makes ReadLine buffer until it
            // hangs or throws OutOfMemory. Reading fixed chunks bounds the TOTAL, and capping the line
            // buffer bounds a SINGLE line - the two together are what make this read finite regardless of
            // what the file does underneath. (Capstone R11, the disposition it named after R10's budget
            // turned out to be checked in the wrong place.)
            var buffer = new char[8192];
            var line = new StringBuilder();
            var remaining = MaxArtifactBytes;

            void Consider(string text)
            {
                // A line that HIT the cap was truncated, so what we hold is not what the file says - and
                // an echo target the peer could never reproduce verbatim is worse than none, because it
                // would red every honest reply. Truncated lines are not candidates.
                if (text.Length >= MaxLineChars) return;
                var candidate = Normalise(text);
                if (IsUsableExpectation(candidate)) last = candidate;
            }

            int read;
            while (remaining > 0 &&
                   (read = reader.Read(buffer, 0, Math.Min(buffer.Length, remaining))) > 0)
            {
                remaining -= read;
                for (var i = 0; i < read; i++)
                {
                    var c = buffer[i];
                    if (c == '\n')
                    {
                        Consider(line.ToString());
                        line.Clear();
                    }
                    else if (line.Length < MaxLineChars)
                    {
                        // Past the cap the rest of the line is dropped rather than buffered. A line that
                        // long is not a plausible echo target, and buffering it is the whole hazard.
                        line.Append(c);
                    }
                }
            }
            Consider(line.ToString());   // a final line with no trailing newline still counts
            return last;
        }
        catch
        {
            // Missing, locked, a directory, a permission failure - all the same answer.
        }
        return null;
    }

    /// <summary>Largest artifact the driver will open to derive an echo target. Beyond this the check is
    /// skipped rather than made to wait: no review artifact is this big, and the ask must not stall.</summary>
    public const int MaxArtifactBytes = 4 * 1024 * 1024;

    /// <summary>Longest single line the reader will buffer. Beyond this the remainder of that line is
    /// discarded: no plausible echo target is this long, and buffering an unbounded line is exactly the
    /// hazard a per-line cap exists to remove.</summary>
    public const int MaxLineChars = 4096;

    /// <summary>How many letters or digits an expectation needs before it can discriminate at all.</summary>
    public const int MinSubstantiveChars = 8;

    /// <summary>Can this expectation actually PROVE anything? A "last non-blank line" of `}` cannot: every
    /// C# file ends that way, so a peer emitting a closing brace satisfies the echo without reading a
    /// thing. The same goes for a fence, a horizontal rule, a block-comment terminator.
    ///
    /// Found twice on the same day - by the capstone's Mechanism Gamer and Boundary Smuggler seats, and
    /// independently while computing the echo target for that very consult, whose primary artifact was a
    /// .cs file. The weak target is chosen by the CALLING AGENT, not by this layer; the point of
    /// reporting it rather than failing is that the peer should not be penalised for the caller's pick.
    ///
    /// Reporting the weakness beats silently ignoring it. <see cref="IsSatisfied"/> still returns true for
    /// a weak expectation - failing consults over a bad ECHO TARGET would be punishing the wrong thing -
    /// but a caller that asked for an echo it cannot verify deserves to be told, or it will read an
    /// unchecked consult as a checked one.</summary>
    public static bool IsUsableExpectation(string? expectedEcho)
    {
        if (string.IsNullOrWhiteSpace(expectedEcho)) return false;
        var substantive = 0;
        foreach (var c in expectedEcho)
            if (char.IsLetterOrDigit(c)) substantive++;
        return substantive >= MinSubstantiveChars;
    }

    public static bool IsSatisfied(string? answer, string? expectedEcho)
    {
        // No artifact, no artifact whose last line is blank, and no expectation too thin to discriminate:
        // nothing to demand. Degrading to "satisfied" is deliberate - degrading to "failed" would red
        // every such consult forever.
        //
        // THE UNUSABLE CASE IS NOT COSMETIC. If the driver picks "}" as the echo target and the peer does
        // not happen to end on a brace, a "failed" here would flag the PEER for a bad target the DRIVER
        // chose - and a guard that reds on consults it was never meant to cover gets switched off, after
        // which it covers nothing. The caller is told separately, via IsUsableExpectation.
        if (!IsUsableExpectation(expectedEcho)) return true;
        if (string.IsNullOrWhiteSpace(answer)) return false;

        var needle = Normalise(expectedEcho);
        if (needle.Length == 0) return true;

        var tail = answer.Split('\n')
                         .Select(Normalise)
                         .Where(l => l.Length > 0)
                         .Reverse()
                         .Take(TailLines);

        return tail.Any(line => line.Contains(needle, StringComparison.Ordinal));
    }

    /// <summary>Strip the decoration a complying peer legitimately adds - backticks, blockquote markers,
    /// emphasis - so formatting never fails an honest echo.</summary>
    private static string Normalise(string line) =>
        line.Trim().Trim('>', '`', '*', '_', ' ', '\t').Trim();
}
