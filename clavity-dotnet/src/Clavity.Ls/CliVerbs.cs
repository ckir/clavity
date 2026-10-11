using System.Text;

namespace Clavity.Ls;

/// <summary>Testable bodies for the non-host CLI verbs (kept out of Program.cs top-level for unit testing).</summary>
public static class CliVerbs
{
    /// <summary>
    /// `curate-commit` — read the compiled golden-header from <paramref name="stdin"/> (NOT a shell arg: a
    /// multi-line markdown header blows past command-line quoting/length limits — F5) and atomically commit it
    /// as the GROWTH region file inside <paramref name="dir"/> (never touching SEED). The read is BOUNDED to
    /// GoldenHeader.MaxBytes+1 BYTES so a hostile pipe cannot OOM the process (F12); over-cap input is refused
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
    /// and validates them itself. Both variants now cap BYTES during read and use strict UTF-8 decode.
    /// Exit codes unified: 2 = bad input (over-cap, non-UTF-8, empty, mojibake), 1 = IO/environment error.
    /// </para>
    /// <para>
    /// <paramref name="cheatsheet"/> selects the driver-cheatsheet GROWTH file instead of the golden-header GROWTH
    /// (`curate-commit --cheatsheet`). Both readers deliver that file ONLY with the sidecar this write produces, so
    /// this verb is the mechanical half of agy-curate's human gate: the skill compiles to a staging path and calls
    /// this after approval. The two targets are disjoint - neither call touches the other's file.
    /// </para>
    /// </summary>
    public static int CurateCommit(string dir, Stream stdin, TextWriter error, bool cheatsheet = false)
    {
        // Read raw bytes directly from the stream, capped at MaxBytes+1 so we never allocate more than the cap.
        // This mirrors classic's stdin.lock().take(cap).read_to_end() — byte-level cap, not char-level.
        const int Cap = GoldenHeader.MaxBytes + 1;
        var buffer = new byte[Cap];
        int total = 0;
        try
        {
            while (total < Cap)
            {
                int read = stdin.Read(buffer, total, Cap - total);
                if (read == 0) break;
                total += read;
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // A broken pipe or unreadable stdin. Report cleanly rather than dumping a stack trace.
            error.WriteLine($"curate-commit: cannot read stdin: {ex.Message}; nothing written.");
            return 1;
        }

        if (total > GoldenHeader.MaxBytes)
        {
            error.WriteLine($"curate-commit: input exceeds the {GoldenHeader.MaxBytes}-byte golden-header cap; nothing written.");
            return 2;
        }

        // Strict UTF-8 decode (no BOM detection, throw on invalid bytes) — mirrors classic's String::from_utf8.
        string payload;
        try
        {
            payload = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true)
                .GetString(buffer, 0, total);
        }
        catch (DecoderFallbackException)
        {
            error.WriteLine("curate-commit: stdin is not valid UTF-8; nothing written. Pipe the compiled "
                + "header as UTF-8 rather than retyping it through a terminal (a console code page mangles "
                + "em dashes and emoji).");
            return 2;
        }

        // Mojibake tripwire. A text pipe on Windows re-encodes the stream through the console code page,
        // so the payload can arrive already mangled AND still be well-formed UTF-8 - which is why the
        // integrity sidecar matched corrupt content for 13 days. This is deliberately a HEURISTIC over
        // known corruption families, not a proof: it cannot enumerate every mis-encoding and does not
        // claim to. It is NOT a blanket non-ASCII rejection - curate-commit is a faithful byte transport
        // by contract (see CurateCommit_round_trips_non_ascii_content_byte_identically), and rejecting
        // all non-ASCII would break the very property that makes the raw-byte path worth mandating.
        // Empty (or blank) input is BAD INPUT (exit 2), never a request to wipe the region: a probe like
        // `curate-commit < /dev/null` once truncated the live GROWTH region from 11039 bytes to 0 and exited 0.
        if (string.IsNullOrWhiteSpace(payload))
        {
            error.WriteLine("curate-commit: stdin is empty; nothing written.");
            return 2;
        }
        foreach (var signature in new[] { "\u0393\u00C7", "\u00E2\u20AC" })
        {
            if (payload.Contains(signature, StringComparison.Ordinal))
            {
                error.WriteLine("curate-commit: input contains a suspected mojibake sequence " +
                                "(a text pipe re-encoded it through the console code page); nothing written. " +
                                "Stream the file's raw bytes to stdin instead of piping text.");
                return 2;
            }
        }

        try
        {
            if (cheatsheet) DriverCheatsheet.CommitGrowth(dir, payload);
            else GoldenHeader.CommitGrowth(dir, payload);
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
            error.WriteLine($"curate-commit: cannot write {(cheatsheet ? "driver-cheatsheet growth" : "golden-header")} to {dir}: {ex.Message}");
            return 1;
        }
    }

    /// <summary>
    /// `curate-commit [--cheatsheet]`: the verb takes exactly one optional flag. Anything else is refused with a
    /// sentence naming it, so a typo (`--cheatsheets`) cannot silently publish to the GOLDEN HEADER - the one
    /// mis-route that would put cheatsheet content on the peer-facing wire. Program.cs is top-level code with no
    /// test seam, so the parse lives here where it is pinned.
    /// </summary>
    public static bool TryParseCurateCommitArgs(string[] args, out bool cheatsheet, out string? error)
    {
        cheatsheet = false;
        error = null;
        foreach (var a in args.Skip(1))
        {
            if (a == "--cheatsheet") { cheatsheet = true; continue; }
            error = $"curate-commit: unknown argument '{a}' (the only option is --cheatsheet); nothing written.";
            return false;
        }
        return true;
    }
}
