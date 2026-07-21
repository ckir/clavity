using System.Text;

namespace Clavity.Ls;

/// <summary>Testable bodies for the non-host CLI verbs (kept out of Program.cs top-level for unit testing).</summary>
public static class CliVerbs
{
    /// <summary>
    /// `curate-commit` — read the compiled golden-header from <paramref name="stdin"/> (NOT a shell arg: a
    /// multi-line markdown header blows past command-line quoting/length limits — F5) and atomically commit it
    /// as the GROWTH region file inside <paramref name="dir"/> (never touching SEED). The read is BOUNDED to
    /// GoldenHeader.MaxBytes+1 chars so a hostile pipe cannot OOM the process (F12); over-cap input is refused
    /// with a non-zero exit. The caller resolves the dir from CLAVITY_GOLDEN_HEADER (F8 — the verb never touches
    /// the environment, so tests stay parallel-safe).
    /// <para>
    /// Takes a raw <see cref="Stream"/>, NOT a TextReader, and owns the decoding itself — deliberately, because
    /// the decoder choice is the entire bug this signature exists to prevent. <c>Console.In</c> decodes via the
    /// console's input code page (on Windows the OEM page, CP437 — not UTF-8), so piping UTF-8 markdown through
    /// it mis-decoded the header on the way in: an em dash was stored as "Γ Ç ö", "⚠️" as "ΓÜá∩╕Å". Nothing
    /// downstream can catch that — mojibake is still perfectly valid UTF-8, so the .sha256 sidecar hashes the
    /// corrupt bytes happily and <see cref="GoldenHeader"/>'s strict read-side decode accepts them. Decoding
    /// correctly HERE is the only defence, so no caller is given the chance to supply its own reader.
    /// Mirrors classic's <c>curate_commit</c> (clavity-classic/src/main.rs:690), which likewise takes raw bytes
    /// and validates them itself. Two divergences, both deliberate and neither affecting WHICH inputs are
    /// accepted: (1) classic caps BYTES as it reads, while this caps CHARS at read and byte-count at commit;
    /// (2) the two variants number their non-zero exit codes oppositely — classic returns 1 for over-cap and
    /// non-UTF-8 input and 2 for an IO failure, this returns 2 for bad input and 1 for an IO failure. The
    /// accept/reject SET is identical, so any caller testing zero-vs-non-zero is unaffected; no caller in this
    /// repo branches on the specific code (agy-curate/SKILL.md:167-172 just runs the verb). Unifying them
    /// would change a shipped CLI contract in one variant or the other, which is not worth doing while
    /// nothing reads the codes. The trigger to resolve it is concrete: the FIRST time any caller branches on
    /// a specific non-zero code, unify both variants on THIS scheme (2 = bad input, 1 = environmental
    /// failure) and say so in agy-curate/SKILL.md, which currently calls the two variants "identical".
    /// </para>
    /// </summary>
    public static int CurateCommit(string dir, Stream stdin, TextWriter error)
    {
        // detectEncodingFromByteOrderMarks is FALSE on purpose: with BOM detection on, a UTF-16 BOM silently
        // switches the decoder to UTF-16 and accepts non-UTF-8 input — exactly what GoldenHeader's sidecar read
        // path goes out of its way to reject. Keep the two consistent. throwOnInvalidBytes makes input that is
        // not UTF-8 at all (e.g. CP1252 bytes) a hard refusal rather than silently-mangled plausible text.
        using var reader = new StreamReader(
            stdin,
            new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true),
            detectEncodingFromByteOrderMarks: false,
            bufferSize: -1,
            // leaveOpen so the reader does not dispose a stream it does not own (Program.cs disposes stdin
            // itself). It does NOT make the stream reusable: StreamReader buffers ahead, so on return the
            // underlying stream is positioned past what was actually decoded, and any bytes still sitting in
            // the reader's buffer are gone. A caller that read on after this would silently skip input — so
            // the contract is "yours to dispose", not "yours to keep reading".
            leaveOpen: true);

        // Bounded read: at most MaxBytes+1 chars, so input can never balloon memory before the cap check.
        var buffer = new char[GoldenHeader.MaxBytes + 1];
        var total = 0;
        int read;
        try
        {
            while (total < buffer.Length && (read = reader.Read(buffer, total, buffer.Length - total)) > 0)
                total += read;
        }
        catch (DecoderFallbackException)
        {
            error.WriteLine("curate-commit: stdin is not valid UTF-8; nothing written. Pipe the compiled "
                + "header as UTF-8 rather than retyping it through a terminal (a console code page mangles "
                + "em dashes and emoji).");
            return 2;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // A broken pipe or unreadable stdin. Report cleanly rather than dumping a stack trace, for the same
            // reason the write path below does: agy-curate invokes this verb and a stack trace clutters the
            // agent's context (agy review req-djlih4srlzr0).
            error.WriteLine($"curate-commit: cannot read stdin: {ex.Message}; nothing written.");
            return 1;
        }

        if (total > GoldenHeader.MaxBytes)
        {
            error.WriteLine($"curate-commit: input exceeds the {GoldenHeader.MaxBytes}-byte golden-header cap; nothing written.");
            return 2;
        }

        try
        {
            GoldenHeader.CommitGrowth(dir, new string(buffer, 0, total));
            return 0;
        }
        catch (InvalidOperationException ex)   // multibyte content whose UTF-8 BYTE count exceeds the cap
        {
            error.WriteLine($"curate-commit: {ex.Message}; nothing written.");
            return 2;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Environmental write failure (disk full, read-only path, bad CLAVITY_GOLDEN_HEADER). Report cleanly
            // instead of dumping a raw stack trace — agy-curate invokes this verb, and a stack trace would clutter
            // the agent's context (agy review req-djlih4srlzr0).
            error.WriteLine($"curate-commit: cannot write golden-header to {dir}: {ex.Message}");
            return 1;
        }
    }
}
